#!/bin/bash
#
# TASK-0026F1 standalone API SQL boundary hardening focused security
# smoke test.
#
# TASK-0026F's own reconnaissance discovered that most of the standalone
# API's service implementations (snep/modules/default/api/actions/*.php)
# build SQL by direct string concatenation of $_GET values, with no
# parameterization -- a SQL-injection class of finding distinct from and
# unrelated to F17-A/F17-B (see docs/tasks/0026f-standalone-api-hardening.md
# section 5). This suite proves the TASK-0026F1 remediation of that
# finding, re-traced and documented in
# docs/tasks/0026f1-standalone-api-sql-boundary-hardening.md.
#
# For every confirmed-unsafe sink, this suite exercises the REAL,
# authenticated standalone API dispatcher (never a direct database
# connection, never bypassing TASK-0026F's authentication) with:
#   1. a normal valid request (still works exactly as before);
#   2. an ordinary invalid/nonexistent value (behaves normally);
#   3. an always-false SQL-shaped value (behaves as inert literal data);
#   4. an always-true SQL-shaped value (behaves as inert literal data too
#      -- proven against a real disposable fixture that must remain
#      unreachable by the injection attempt);
#   5. a quote/apostrophe-containing value (no SQL syntax error);
#   6. cleanup, via the same supported paths used elsewhere in this
#      project's smoke suites.
#
# Every payload is a harmless, non-destructive, syntax-shaped string
# applied only to fixtures this script itself owns -- never a real
# exploit chain, never secret/schema/credential extraction, matching
# this task's own explicit "do not extract data" instruction.
#
# Deliberately separate from `make smoke` -- never run implicitly by it.
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
BASE_URL="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
API_URL="${BASE_URL}/modules/default/api/index.php"
FIXTURE_USER="task0026f1-restricted"
FIXTURE_PASSWORD="Task0026f1Api123!"

log() { harness_log "$@"; }

db_query() {
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
        "${DB_NAME:-snep}" -N -e "$1"
}

fatal_count() {
    local n
    n="$($COMPOSE exec -T app sh -c 'grep -c "Fatal error" /var/log/apache2/mag-error.log 2>/dev/null' 2>/dev/null | tr -d '\r\n ')"
    echo "${n:-0}"
}

md5_of() {
    $COMPOSE exec -T app php -r "echo md5(\$argv[1]);" -- "$1" 2>/dev/null | tr -d '\r'
}

# api_request <service> [--data-urlencode "k=v" ...] -- authenticates as
# the fixture user, returns HTTP code, leaves the response body in $BODY.
BODY=""
api_request() {
    local service="$1"
    shift
    curl -sS -o "$BODY" -w '%{http_code}' -u "${FIXTURE_USER}:${FIXTURE_PASSWORD}" \
        -G "$API_URL" --data-urlencode "service=${service}" "$@"
}

# api_request_unauth <service> [...] -- no credentials at all.
api_request_unauth() {
    local service="$1"
    shift
    curl -sS -o "$BODY" -w '%{http_code}' -G "$API_URL" --data-urlencode "service=${service}" "$@"
}

body_status() {
    grep -o '"status":"[a-z]*"' "$BODY" | head -1
}

no_leaked_errors() {
    ! grep -qi "fatal\|stack trace\|/var/www\|SQLSTATE\|syntax error" "$BODY"
}

# --- 0. Preflight ------------------------------------------------------

harness_require_containers app db
harness_require_env DB_USER DB_PASSWORD DB_NAME

BODY="$(mktemp)"
harness_register_best_effort_cleanup "response temp file" "rm -f '$BODY'"

FATALS_BEFORE="$(fatal_count)"
log "==> baseline PHP Fatal Error count: ${FATALS_BEFORE}"

# Dedicated, persistent, reusable fixture account (TASK-0026C/D/E/F's own
# established convention), reset to a known password every run -- never
# a real admin credential.
FIXTURE_HASH="$(md5_of "$FIXTURE_PASSWORD")"
if [ -z "$FIXTURE_HASH" ]; then
    harness_blocked "could not compute the fixture user's password hash via the app container"
fi
FID="$(db_query "SELECT id FROM users WHERE name='${FIXTURE_USER}';")"
if [ -z "$FID" ]; then
    db_query "INSERT INTO users (name,password,email,dashboard,profile_id,created,updated) VALUES ('${FIXTURE_USER}','${FIXTURE_HASH}','${FIXTURE_USER}@example.test','',1,NOW(),NOW());"
    FID="$(db_query "SELECT id FROM users WHERE name='${FIXTURE_USER}';")"
fi
if [ -z "$FID" ]; then
    harness_blocked "could not provision the API SQL fixture user"
fi
db_query "UPDATE users SET password='${FIXTURE_HASH}' WHERE id=${FID};" >/dev/null
harness_register_best_effort_cleanup "fixture user ${FIXTURE_USER} (id=${FID}) password reset to baseline" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}' -e \"UPDATE users SET password='${FIXTURE_HASH}' WHERE id=${FID};\" >/dev/null"

# =============================================================================
# Phase 11 -- Authentication/authorization preservation (TASK-0026F stays
# authoritative; this task does not touch it).
# =============================================================================

log "==> Authentication preservation (TASK-0026F boundary, unchanged here)"

code="$(api_request_unauth "CallsReport")"
if [ "$code" = "401" ]; then
    harness_ok "auth: unauthenticated request to a protected service is rejected" "HTTP 401"
else
    harness_bad "auth: unauthenticated request to a protected service is rejected" "HTTP ${code}"
fi

code="$(api_request "CallsReport" --data-urlencode "start_date=2020-01-01" --data-urlencode "start_hour=00:00" --data-urlencode "end_date=2030-01-01" --data-urlencode "end_hour=00:00" --data-urlencode "report_type=analitic")"
if [ "$code" = "200" ] && [ "$(body_status)" = '"status":"ok"' ]; then
    harness_ok "auth: authenticated legitimate request succeeds" "HTTP 200, status=ok"
else
    harness_bad "auth: authenticated legitimate request succeeds" "HTTP ${code}, body=$(head -c 200 "$BODY")"
fi

# =============================================================================
# ContactsService -- phone/callerid/name LIKE injection
# =============================================================================

log "==> ContactsService boundary"

CONTACT_NAME="task0026f1-contact"
CONTACT_PHONE="5599990000"

if [ -n "$(db_query "SELECT id FROM contacts_names WHERE name='${CONTACT_NAME}';")" ]; then
    harness_blocked "a contact named '${CONTACT_NAME}' already exists -- refusing to overwrite. Remove it manually first."
fi

GROUP_ID="$(db_query "SELECT id FROM contacts_group ORDER BY id LIMIT 1;")"
if [ -z "$GROUP_ID" ]; then
    harness_blocked "no contacts_group row exists to attach the disposable contact fixture to"
fi

db_query "INSERT INTO contacts_names (name,email,address,id_state,id_city,cep,\`group\`,created,updated) VALUES ('${CONTACT_NAME}','','','',NULL,'',${GROUP_ID},NOW(),NOW());" >/dev/null
CONTACT_ID="$(db_query "SELECT id FROM contacts_names WHERE name='${CONTACT_NAME}';")"
if [ -z "$CONTACT_ID" ]; then
    harness_blocked "could not provision the disposable contact fixture"
fi
harness_register_cleanup "contact fixture ${CONTACT_NAME} (id=${CONTACT_ID})" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}' -e \"DELETE FROM contacts_phone WHERE contact_id=${CONTACT_ID}; DELETE FROM contacts_names WHERE id=${CONTACT_ID};\" >/dev/null"
db_query "INSERT INTO contacts_phone (contact_id, phone) VALUES (${CONTACT_ID}, '${CONTACT_PHONE}');" >/dev/null

# 1. Valid request (phone).
code="$(api_request "Contacts" --data-urlencode "phone=${CONTACT_PHONE}")"
if [ "$code" = "200" ] && [ "$(body_status)" = '"status":"ok"' ] && grep -q "$CONTACT_NAME" "$BODY"; then
    harness_ok "Contacts valid: phone lookup finds the fixture" "HTTP 200, status=ok, fixture returned"
else
    harness_bad "Contacts valid: phone lookup finds the fixture" "HTTP ${code}, body=$(head -c 200 "$BODY")"
fi

# Valid request (name) -- also proves the pre-existing ambiguous-column
# crash discovered and minimally guarded by this task (see docs) no
# longer fires for an ordinary name search.
code="$(api_request "Contacts" --data-urlencode "name=${CONTACT_NAME}")"
if [ "$code" = "200" ] && [ "$(body_status)" = '"status":"ok"' ]; then
    harness_ok "Contacts valid: name lookup finds the fixture" "HTTP 200, status=ok"
else
    harness_bad "Contacts valid: name lookup finds the fixture" "HTTP ${code}, body=$(head -c 200 "$BODY")"
fi

# 2. Ordinary nonexistent value.
code="$(api_request "Contacts" --data-urlencode "phone=0000000000")"
if [ "$code" = "200" ] && [ "$(body_status)" = '"status":"empty"' ]; then
    harness_ok "Contacts: ordinary nonexistent phone behaves normally" "HTTP 200, status=empty"
else
    harness_bad "Contacts: ordinary nonexistent phone behaves normally" "HTTP ${code}, body=$(head -c 200 "$BODY")"
fi

# 3/4. Always-false / always-true SQL-shaped phone -- neither may return
# the fixture (an always-true condition succeeding would return the
# FIRST row in the joined result set, which is this fixture, since it is
# the only contact in this dev database).
before_fatals="$(fatal_count)"
code="$(api_request "Contacts" --data-urlencode "phone=x' AND '1'='2")"
after_fatals="$(fatal_count)"
if [ "$code" = "200" ] && [ "$(body_status)" = '"status":"empty"' ] && [ "$before_fatals" = "$after_fatals" ] && no_leaked_errors; then
    harness_ok "Contacts: always-false SQL-shaped phone stays inert" "HTTP 200, status=empty, no new fatals"
else
    harness_bad "Contacts: always-false SQL-shaped phone stays inert" "HTTP ${code}, fatals ${before_fatals}->${after_fatals}, body=$(head -c 300 "$BODY")"
fi

before_fatals="$(fatal_count)"
code="$(api_request "Contacts" --data-urlencode "phone=x' OR '1'='1")"
after_fatals="$(fatal_count)"
if [ "$code" = "200" ] && [ "$(body_status)" = '"status":"empty"' ] && [ "$before_fatals" = "$after_fatals" ] && no_leaked_errors; then
    harness_ok "Contacts: always-true SQL-shaped phone cannot reach the fixture" "HTTP 200, status=empty (a real vulnerability would have returned the fixture contact), no new fatals"
else
    harness_bad "Contacts: always-true SQL-shaped phone cannot reach the fixture" "HTTP ${code}, fatals ${before_fatals}->${after_fatals}, body=$(head -c 300 "$BODY")"
fi

# Same always-true proof against the name-search branch.
code="$(api_request "Contacts" --data-urlencode "name=x' OR '1'='1")"
if [ "$code" = "200" ] && [ "$(body_status)" = '"status":"empty"' ]; then
    harness_ok "Contacts: always-true SQL-shaped name cannot reach the fixture" "HTTP 200, status=empty"
else
    harness_bad "Contacts: always-true SQL-shaped name cannot reach the fixture" "HTTP ${code}, body=$(head -c 300 "$BODY")"
fi

# 5. Quote-containing value produces no syntax error.
before_fatals="$(fatal_count)"
code="$(api_request "Contacts" --data-urlencode "phone=O'Brien")"
after_fatals="$(fatal_count)"
if [ "$code" = "200" ] && [ "$before_fatals" = "$after_fatals" ] && no_leaked_errors; then
    harness_ok "Contacts: apostrophe-containing value causes no syntax error" "HTTP 200, no new fatals"
else
    harness_bad "Contacts: apostrophe-containing value causes no syntax error" "HTTP ${code}, fatals ${before_fatals}->${after_fatals}"
fi

# No search parameter at all -- the minimal guard added for the
# pre-existing missing-parameter crash, not a broader fix.
code="$(api_request "Contacts")"
if [ "$code" = "200" ] && [ "$(body_status)" = '"status":"empty"' ]; then
    harness_ok "Contacts: no search parameter fails safely (not a crash)" "HTTP 200, status=empty"
else
    harness_bad "Contacts: no search parameter fails safely (not a crash)" "HTTP ${code}, body=$(head -c 200 "$BODY")"
fi

# =============================================================================
# CSV_ExportDataService -- table/fields/order identifier allowlist
# =============================================================================

log "==> CSV_ExportDataService boundary"

# 1. Valid request.
code="$(api_request "CSV_ExportData" --data-urlencode "table=users" --data-urlencode "fields=id,name" --data-urlencode "order=id")"
if [ "$code" = "200" ] && grep -q '"id"' "$BODY" && ! grep -q "password" "$BODY"; then
    harness_ok "CSV_ExportData valid: allowlisted table/fields/order works" "HTTP 200, rows returned, no password column"
else
    harness_bad "CSV_ExportData valid: allowlisted table/fields/order works" "HTTP ${code}, body=$(head -c 200 "$BODY")"
fi

# 2. Non-allowlisted / SQL-shaped table fails closed.
before_fatals="$(fatal_count)"
code="$(api_request "CSV_ExportData" --data-urlencode "table=users' OR '1'='1" --data-urlencode "fields=id" --data-urlencode "order=id")"
after_fatals="$(fatal_count)"
if [ "$code" = "200" ] && [ "$(body_status)" = '"status":"error"' ] && [ "$before_fatals" = "$after_fatals" ] && no_leaked_errors; then
    harness_ok "CSV_ExportData: SQL-shaped table name fails closed" "HTTP 200, status=error, no new fatals"
else
    harness_bad "CSV_ExportData: SQL-shaped table name fails closed" "HTTP ${code}, fatals ${before_fatals}->${after_fatals}, body=$(head -c 300 "$BODY")"
fi

# 2b. An entirely unregistered table name fails closed the same way.
code="$(api_request "CSV_ExportData" --data-urlencode "table=nosuchtable" --data-urlencode "fields=id")"
if [ "$code" = "200" ] && [ "$(body_status)" = '"status":"error"' ]; then
    harness_ok "CSV_ExportData: unregistered table name fails closed" "HTTP 200, status=error"
else
    harness_bad "CSV_ExportData: unregistered table name fails closed" "HTTP ${code}, body=$(head -c 200 "$BODY")"
fi

# 3. Non-allowlisted column (password) is silently dropped, never selected.
before_fatals="$(fatal_count)"
code="$(api_request "CSV_ExportData" --data-urlencode "table=users" --data-urlencode "fields=id,password" --data-urlencode "order=id")"
after_fatals="$(fatal_count)"
if [ "$code" = "200" ] && ! grep -qi "password" "$BODY" && [ "$before_fatals" = "$after_fatals" ]; then
    harness_ok "CSV_ExportData: non-allowlisted column (password) is never selected" "HTTP 200, no password column in response, no new fatals"
else
    harness_bad "CSV_ExportData: non-allowlisted column (password) is never selected" "HTTP ${code}, fatals ${before_fatals}->${after_fatals}, body=$(head -c 300 "$BODY")"
fi

# 4. SQL-shaped order value falls back to a valid column instead of
# altering query structure -- must not error and must not drop or
# corrupt the real table.
before_fatals="$(fatal_count)"
code="$(api_request "CSV_ExportData" --data-urlencode "table=users" --data-urlencode "fields=id,name" --data-urlencode "order=id; DROP TABLE users")"
after_fatals="$(fatal_count)"
users_after="$(db_query "SELECT COUNT(*) FROM users;")"
if [ "$code" = "200" ] && [ "$before_fatals" = "$after_fatals" ] && [ "${users_after:-0}" -ge 1 ] && no_leaked_errors; then
    harness_ok "CSV_ExportData: SQL-shaped order value cannot alter query structure" "HTTP 200, no new fatals, users table intact (${users_after} rows)"
else
    harness_bad "CSV_ExportData: SQL-shaped order value cannot alter query structure" "HTTP ${code}, fatals ${before_fatals}->${after_fatals}, users_after=${users_after}"
fi

# 6. Missing parameters fail closed with a controlled error (the
# pre-existing PHP 8.4 crash resolved as a side effect of the allowlist
# check, see docs/tasks/0026f1-...), never a Fatal Error.
before_fatals="$(fatal_count)"
code="$(api_request "CSV_ExportData")"
after_fatals="$(fatal_count)"
if [ "$code" = "200" ] && [ "$(body_status)" = '"status":"error"' ] && [ "$before_fatals" = "$after_fatals" ]; then
    harness_ok "CSV_ExportData: missing table/fields fails closed, not a crash" "HTTP 200, status=error, no new fatals"
else
    harness_bad "CSV_ExportData: missing table/fields fails closed, not a crash" "HTTP ${code}, fatals ${before_fatals}->${after_fatals}"
fi

# =============================================================================
# CallsReportService -- date range / src,dst / ids / limit / cost_center /
# exceptions,clausulepeer
# =============================================================================

log "==> CallsReportService boundary"

CR_ARGS=(--data-urlencode "start_date=2020-01-01" --data-urlencode "start_hour=00:00" \
         --data-urlencode "end_date=2030-01-01" --data-urlencode "end_hour=00:00" \
         --data-urlencode "report_type=analitic")

# 1. Valid request (already proven under Phase 11 above); repeat here for
# a users-table sanity baseline specific to this section.
users_before="$(db_query "SELECT COUNT(*) FROM users;")"

before_fatals="$(fatal_count)"
code="$(api_request "CallsReport" "${CR_ARGS[@]}")"
after_fatals="$(fatal_count)"
if [ "$code" = "200" ] && [ "$(body_status)" = '"status":"ok"' ] && [ "$before_fatals" = "$after_fatals" ]; then
    harness_ok "CallsReport valid: date-range request works" "HTTP 200, status=ok, no new fatals"
else
    harness_bad "CallsReport valid: date-range request works" "HTTP ${code}, fatals ${before_fatals}->${after_fatals}"
fi

# 3/4. Always-false / always-true SQL-shaped values across every
# confirmed sink in one pass -- must all remain inert (status=ok with an
# empty/unaffected result, no syntax error, no new fatal, users table
# untouched).
declare -a INJECTION_CHECKS=(
    "start_date-injection|--data-urlencode|start_date=2020-01-01' OR '1'='1"
    "src-injection|--data-urlencode|src=1' OR '1'='1"
    "dst-injection|--data-urlencode|dst=1' OR '1'='1"
    "limit-injection|--data-urlencode|limit=1; DROP TABLE cdr"
    "contactSrcId-injection|--data-urlencode|contactSrcId=1 OR 1=1"
    "contactGroupSrcId-injection|--data-urlencode|contactGroupSrcId=1 OR 1=1"
    "cost_center-injection|--data-urlencode|cost_center=a' OR '1'='1"
    "exceptions-injection|--data-urlencode|exceptions=1' OR '1'='1"
    "clausulepeer-injection|--data-urlencode|clausulepeer=1' OR '1'='1"
    "time_call-injection|--data-urlencode|time_call_init=0 OR 1=1"
    "apostrophe-only|--data-urlencode|src=O'Brien"
)
for entry in "${INJECTION_CHECKS[@]}"; do
    label="${entry%%|*}"
    rest="${entry#*|}"
    flag="${rest%%|*}"
    kv="${rest#*|}"
    before_fatals="$(fatal_count)"
    if [ "$label" = "clausulepeer-injection" ]; then
        code="$(api_request "CallsReport" "${CR_ARGS[@]}" "$flag" "$kv" --data-urlencode "clausule=x")"
    else
        code="$(api_request "CallsReport" "${CR_ARGS[@]}" "$flag" "$kv")"
    fi
    after_fatals="$(fatal_count)"
    users_now="$(db_query "SELECT COUNT(*) FROM users;")"
    if [ "$code" = "200" ] && [ "$(body_status)" = '"status":"ok"' ] && [ "$before_fatals" = "$after_fatals" ] \
        && no_leaked_errors && [ "$users_now" = "$users_before" ]; then
        harness_ok "CallsReport: ${label} stays inert" "HTTP 200, status=ok, no new fatals, users table unaffected (${users_now})"
    else
        harness_bad "CallsReport: ${label} stays inert" "HTTP ${code}, fatals ${before_fatals}->${after_fatals}, users ${users_before}->${users_now}, body=$(head -c 300 "$BODY")"
    fi
done

# =============================================================================
# RankingReportService -- date range / clausulepeer
# =============================================================================

log "==> RankingReportService boundary"

RR_ARGS=(--data-urlencode "start_date=2020-01-01" --data-urlencode "start_hour=00:00" \
         --data-urlencode "end_date=2030-01-01" --data-urlencode "end_hour=00:00" \
         --data-urlencode "showsource=5" --data-urlencode "showdestiny=5" --data-urlencode "type=num")

before_fatals="$(fatal_count)"
code="$(api_request "RankingReport" "${RR_ARGS[@]}")"
after_fatals="$(fatal_count)"
if [ "$code" = "200" ] && [ "$before_fatals" = "$after_fatals" ]; then
    harness_ok "RankingReport valid: date-range request works" "HTTP ${code}, no new fatals"
else
    harness_bad "RankingReport valid: date-range request works" "HTTP ${code}, fatals ${before_fatals}->${after_fatals}"
fi

before_fatals="$(fatal_count)"
code="$(api_request "RankingReport" "${RR_ARGS[@]}" --data-urlencode "start_date=2020-01-01' OR '1'='1" --data-urlencode "clausulepeer=1' OR '1'='1" --data-urlencode "clausule=x")"
after_fatals="$(fatal_count)"
if [ "$code" = "200" ] && [ "$before_fatals" = "$after_fatals" ] && no_leaked_errors; then
    harness_ok "RankingReport: SQL-shaped date+clausulepeer stays inert" "HTTP ${code}, no new fatals"
else
    harness_bad "RankingReport: SQL-shaped date+clausulepeer stays inert" "HTTP ${code}, fatals ${before_fatals}->${after_fatals}, body=$(head -c 300 "$BODY")"
fi

# =============================================================================
# ServicesReportService -- date range / clausulepeer
# =============================================================================

log "==> ServicesReportService boundary"

SR_ARGS=(--data-urlencode "start_date=2020-01-01" --data-urlencode "start_hour=00:00" \
         --data-urlencode "end_date=2030-01-01" --data-urlencode "end_hour=00:00")

before_fatals="$(fatal_count)"
code="$(api_request "ServicesReport" "${SR_ARGS[@]}")"
after_fatals="$(fatal_count)"
if [ "$code" = "200" ] && [ "$before_fatals" = "$after_fatals" ]; then
    harness_ok "ServicesReport valid: date-range request works" "HTTP ${code}, no new fatals"
else
    harness_bad "ServicesReport valid: date-range request works" "HTTP ${code}, fatals ${before_fatals}->${after_fatals}"
fi

before_fatals="$(fatal_count)"
code="$(api_request "ServicesReport" "${SR_ARGS[@]}" --data-urlencode "start_date=2020-01-01' OR '1'='1" --data-urlencode "clausulepeer=1' OR '1'='1" --data-urlencode "clausule=x")"
after_fatals="$(fatal_count)"
if [ "$code" = "200" ] && [ "$before_fatals" = "$after_fatals" ] && no_leaked_errors; then
    harness_ok "ServicesReport: SQL-shaped date+clausulepeer stays inert" "HTTP ${code}, no new fatals"
else
    harness_bad "ServicesReport: SQL-shaped date+clausulepeer stays inert" "HTTP ${code}, fatals ${before_fatals}->${after_fatals}, body=$(head -c 300 "$BODY")"
fi

# =============================================================================
# Phase 11 (continued) -- an authenticated malicious-looking request
# cannot alter SQL syntax on the previously-safe services either
# (regression guard: CSV_GetParams/dispatch remain unaffected).
# =============================================================================

code="$(api_request "CSV_GetParams" --data-urlencode "option=fields" --data-urlencode "table=users' OR '1'='1")"
if [ "$code" = "200" ]; then
    harness_ok "CSV_GetParams: SQL-shaped table param does not affect this static, no-SQL service" "HTTP ${code}"
else
    harness_bad "CSV_GetParams: SQL-shaped table param does not affect this static, no-SQL service" "HTTP ${code}"
fi

harness_complete
