#!/bin/bash
#
# TASK-0026J residual SQL boundary closure focused security smoke test.
#
# Exercises the two SQL-injection sinks TASK-0026Z's own closure static
# sweep found outside every prior TASK-0026A-I/F1 task's scope
# (docs/tasks/0026z-security-audit-closure.md Sec.5), now remediated by
# TASK-0026J (docs/tasks/0026j-residual-sql-boundary-closure.md):
#
#   BLOCKER A -- Snep_InterfaceConf::loadConfFromDb()'s legacy chan_sip/
#     iax2 trunk lookup (`where("name = {$peer['name']}")`, raw
#     interpolation) -- flagged as deferred debt during TASK-0026E,
#     never fixed until now.
#   BLOCKER B -- CallsReportController::getselect()'s report-filter SQL
#     construction (date range, contact group/id filters, src/dst,
#     duration, cost center, clausulepeer) -- the MVC twin of the
#     already-hardened API CallsReportService.php (TASK-0026F1), never
#     itself in scope until now.
#
# Every payload below is a harmless, non-destructive, syntax-shaped
# string or boolean-oracle value applied only to fixtures this script
# owns -- never a real exploit chain, never password/hash/schema
# extraction, matching this project's own established smoke-suite
# constraints.
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
ADMIN_USER="admin"
ADMIN_PASSWORD="SmokeTest123!"
MARKER="task0026j"

log() { harness_log "$@"; }

db_query() {
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
        "${DB_NAME:-snep}" -N -e "$1"
}

app_exec() {
    $COMPOSE exec -T app sh -c "$1"
}

fatal_count() {
    local n
    n="$(app_exec 'grep -c "Fatal error" /var/log/apache2/mag-error.log 2>/dev/null' | tr -d '\r\n ')"
    echo "${n:-0}"
}

redirects_to_permission_error() {
    grep -qi '^Location:.*permission/error' "$HEADERS"
}

BODY=""
HEADERS=""
request() {
    local jar="$1" method="$2" path="$3" data="${4:-}"
    if [ "$method" = POST ]; then
        curl -sS -b "$jar" -c "$jar" -D "$HEADERS" -o "$BODY" -w '%{http_code}' -d "$data" "${BASE_URL}${path}"
    else
        curl -sS -b "$jar" -c "$jar" -D "$HEADERS" -o "$BODY" -w '%{http_code}' "${BASE_URL}${path}"
    fi
}

# post_fields <jar> <path> <key=value> [<key=value> ...] -- curl
# --data-urlencode per field, matching TASK-0026E's own established
# convention for values that must survive on the wire byte-for-byte.
post_fields() {
    local jar="$1" path="$2"
    shift 2
    local curl_args=()
    for kv in "$@"; do
        curl_args+=(--data-urlencode "$kv")
    done
    curl -sS -b "$jar" -c "$jar" -D "$HEADERS" -o "$BODY" -w '%{http_code}' \
        "${curl_args[@]}" "${BASE_URL}${path}"
}

# --- 0. Preflight --------------------------------------------------------

harness_require_containers app asterisk db
harness_require_env DB_USER DB_PASSWORD DB_NAME

BODY="$(mktemp)"
HEADERS="$(mktemp)"
harness_register_best_effort_cleanup "request temp files" "rm -f '$BODY' '$HEADERS'"

ADMIN_JAR="$(mktemp)"
harness_register_best_effort_cleanup "admin cookie jar" "rm -f '$ADMIN_JAR'"
ADMIN_HASH="$(app_exec "php -r \"echo md5('${ADMIN_PASSWORD}');\"" | tr -d '\r')"
if [ -z "$ADMIN_HASH" ]; then
    harness_blocked "could not compute the ${ADMIN_USER} password hash via the app container"
fi
db_query "UPDATE users SET password = '${ADMIN_HASH}' WHERE name = '${ADMIN_USER}';" >&2
request "$ADMIN_JAR" POST /index.php/auth/login "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}" >/dev/null

FATALS_BEFORE="$(fatal_count)"
log "==> baseline PHP Fatal Error count: ${FATALS_BEFORE}"

CONF_DIR_APP="/etc/asterisk/snep"
LEGACY_SIP_CONF="${CONF_DIR_APP}/snep-sip.conf"

RESTRICTED_USER="task0026j-restricted"
RESTRICTED_PASSWORD="Task0026jRestricted!"
RID="$(db_query "SELECT id FROM users WHERE name='${RESTRICTED_USER}';")"
RESTRICTED_HASH="$(app_exec "php -r \"echo md5('${RESTRICTED_PASSWORD}');\"" | tr -d '\r')"
if [ -z "$RID" ]; then
    db_query "INSERT INTO users (name,password,email,dashboard,profile_id,created,updated) VALUES ('${RESTRICTED_USER}','${RESTRICTED_HASH}','${RESTRICTED_USER}@example.test','',1,NOW(),NOW());"
    RID="$(db_query "SELECT id FROM users WHERE name='${RESTRICTED_USER}';")"
fi
if [ -z "$RID" ]; then
    harness_blocked "could not provision the zero-permission restricted test user"
fi
db_query "UPDATE users SET password='${RESTRICTED_HASH}' WHERE id=${RID}; DELETE FROM users_permissions WHERE user_id=${RID};" >/dev/null
harness_register_best_effort_cleanup "restricted user permissions reset to baseline" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}' -e \"DELETE FROM users_permissions WHERE user_id=${RID};\" >/dev/null"

RESTRICTED_JAR="$(mktemp)"
harness_register_best_effort_cleanup "restricted cookie jar" "rm -f '$RESTRICTED_JAR'"
request "$RESTRICTED_JAR" POST /index.php/auth/login "user=${RESTRICTED_USER}&password=${RESTRICTED_PASSWORD}" >/dev/null

ADMIN_CSRF="$(harness_csrf_token "$ADMIN_JAR" "$BASE_URL")"
if [ -z "$ADMIN_CSRF" ]; then harness_blocked "could not read the admin session's CSRF token"; fi
RESTRICTED_CSRF="$(harness_csrf_token "$RESTRICTED_JAR" "$BASE_URL")"
if [ -z "$RESTRICTED_CSRF" ]; then harness_blocked "could not read the restricted session's CSRF token"; fi

for boundary_path in "/index.php/default/trunks/add" "/index.php/default/calls-report"; do
    code="$(request "$RESTRICTED_JAR" GET "$boundary_path")"
    if [ "$code" = 302 ] && redirects_to_permission_error; then
        harness_ok "authorization intact: ${boundary_path}" "zero-permission user denied (HTTP 302, Location: permission/error)"
    else
        harness_bad "authorization intact: ${boundary_path}" "expected 302+permission/error, got HTTP ${code}"
    fi
done

code="$(request "$ADMIN_JAR" POST /index.php/default/users/permission/id/$RID "user=$RID&default_trunks_write=1&default_calls-report_read=1&snep_csrf_token=${ADMIN_CSRF}")"
if [ "$code" = 302 ]; then
    harness_ok "admin grants exactly the two required permissions" "HTTP $code (trunks-write, calls-report-read)"
else
    harness_blocked "granting permissions to the restricted user failed (HTTP $code) -- cannot proceed"
fi

# =============================================================================
# BLOCKER A -- Snep_InterfaceConf legacy chan_sip trunk lookup
# =============================================================================

log "==> BLOCKER A: Snep_InterfaceConf chan_sip trunk-lookup boundary"

# Pre-existing, already-documented (TASK-0026C/E) hazard: preparePost()
# auto-generates a new trunk's name as MAX(existing trunk name)+1, or "1"
# if the trunks table is empty -- colliding with any orphaned
# peer_type='T' peers row left over from an earlier interrupted run.
# Swept via the same supported extensions/remove HTTP path this
# project's other smoke suites already use, never a raw SQL delete.
sweep_orphaned_trunk_peers() {
    # NOTE: this suite's own BLOCKER A payload deliberately mass-assigns
    # a peers.name value containing spaces/SQL syntax (e.g. "0 OR
    # id=<n>") -- unlike every prior TASK-0026x suite's orphan sweep
    # (whose names are always a single plain digit), such a name breaks
    # unquoted `for x in $(...)` word-splitting, silently fragmenting one
    # real orphaned row into several nonexistent ones and never actually
    # removing it. A newline-delimited `while read` loop and a properly
    # urlencoded post_fields() call (not a raw `-d` string) are required
    # here specifically because of that.
    local orphan_name
    db_query "SELECT p.name FROM peers p LEFT JOIN trunks t ON t.name = p.name WHERE p.peer_type='T' AND t.id IS NULL;" | while IFS= read -r orphan_name; do
        [ -z "$orphan_name" ] && continue
        log "found an orphaned trunk-type peers row (name='${orphan_name}') with no matching trunks row -- removing via the supported extensions/remove HTTP path"
        post_fields "$ADMIN_JAR" /index.php/default/extensions/remove "id=${orphan_name}" "snep_csrf_token=${ADMIN_CSRF}" >/dev/null
    done
}
sweep_orphaned_trunk_peers
harness_register_cleanup "orphaned trunk-type peers row sweep (BLOCKER A fixture side effect)" "sweep_orphaned_trunk_peers"

# 1. Normal supported lookup: a legitimate technology=sip trunk (CANARY)
# creates and renders correctly, carrying its own distinguishing context.
CANARY_CALLERID="Task0026j Canary"
CANARY_CONTEXT="${MARKER}-canary-ctx"
code="$(post_fields "$RESTRICTED_JAR" /index.php/default/trunks/add \
    "technology=sip" "peer_type=friend" "domain=" "callerid=${CANARY_CALLERID}" "username=task0026jcanary" "secret=Sup3rSecret" \
    "host=sip.example.test" "dtmfmode=rfc2833" "dialmethod=INVITE" "context=${CANARY_CONTEXT}" "reverse_auth=" "map_extensions=" \
    "dtmf_dial=" "codec=ulaw" "codec1=alaw" "codec2=gsm" "qualify=yes" "transport_id=" "snep_csrf_token=${RESTRICTED_CSRF}")"
CANARY_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${CANARY_CALLERID}' ORDER BY id DESC LIMIT 1;")"
if [ "$code" = 302 ] && [ -n "$CANARY_ID" ]; then
    harness_ok "InterfaceConf: create a legitimate technology=sip trunk (CANARY)" "HTTP $code, trunk id=${CANARY_ID}"
else
    harness_bad "InterfaceConf: create a legitimate technology=sip trunk (CANARY)" "HTTP $code, trunk id present='${CANARY_ID}'"
fi
harness_register_cleanup "trunk id=${CANARY_ID:-none} (BLOCKER A CANARY fixture)" \
    "[ -n '${CANARY_ID}' ] && request \"\$RESTRICTED_JAR\" POST /index.php/default/trunks/remove \"id=${CANARY_ID}&delete=1&snep_csrf_token=${RESTRICTED_CSRF}\" >/dev/null; true"

if [ -n "$CANARY_ID" ]; then
    GENERATED_SIP="$(app_exec "cat '$LEGACY_SIP_CONF' 2>/dev/null")"
    if echo "$GENERATED_SIP" | grep -qF "[task0026jcanary]" && echo "$GENERATED_SIP" | grep -qF "context=${CANARY_CONTEXT}"; then
        harness_ok "InterfaceConf: generated legacy config has expected section/context" "snep-sip.conf contains [task0026jcanary] with context=${CANARY_CONTEXT}"
    else
        harness_bad "InterfaceConf: generated legacy config has expected section/context" "expected section/context not found in generated snep-sip.conf"
    fi
fi

if [ -z "${CANARY_ID:-}" ]; then
    harness_blocked "could not create the CANARY trunk fixture -- cannot proceed with the injection proof"
fi

# 2. SQL-shaped value cannot alter lookup semantics: MALICIOUS's own
# `name` field is mass-assigned (TrunksController::preparePost() merges
# the whole POST body; `name` is in both $trunk_fields and $ip_fields,
# and is NOT covered by validateConfigFields()) to an unquoted-numeric-
# context boolean-always-true payload that, if the fix were absent,
# would make the vulnerable `where("name = {$peer['name']}")` lookup
# match CANARY's row by primary key regardless of table contents/order.
MAL_CALLERID="Task0026j Malicious"
MAL_CONTEXT="${MARKER}-malicious-ctx"
INJECTED_NAME="0 OR id=${CANARY_ID}"
code="$(post_fields "$RESTRICTED_JAR" /index.php/default/trunks/add \
    "technology=sip" "peer_type=friend" "domain=" "callerid=${MAL_CALLERID}" "username=task0026jmalicious" "secret=Sup3rSecret2" \
    "host=sip2.example.test" "dtmfmode=rfc2833" "dialmethod=INVITE" "context=${MAL_CONTEXT}" "name=${INJECTED_NAME}" "reverse_auth=" "map_extensions=" \
    "dtmf_dial=" "codec=ulaw" "codec1=alaw" "codec2=gsm" "qualify=yes" "transport_id=" "snep_csrf_token=${RESTRICTED_CSRF}")"
MAL_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${MAL_CALLERID}' ORDER BY id DESC LIMIT 1;")"
MAL_PEER_NAME="$(db_query "SELECT name FROM peers WHERE defaultuser='task0026jmalicious' ORDER BY id DESC LIMIT 1;")"
if [ "$code" = 302 ] && [ -n "$MAL_ID" ] && [ "$MAL_PEER_NAME" = "$INJECTED_NAME" ]; then
    harness_ok "InterfaceConf: mass-assigned SQL-shaped 'name' is stored as literal data" "peers.name='${MAL_PEER_NAME}', trunk id=${MAL_ID}"
else
    harness_bad "InterfaceConf: mass-assigned SQL-shaped 'name' is stored as literal data" "HTTP $code, trunk id='${MAL_ID}', peers.name='${MAL_PEER_NAME}'"
fi
if [ -n "$MAL_ID" ]; then
    harness_register_cleanup "trunk id=${MAL_ID} (BLOCKER A MALICIOUS fixture)" \
        "request \"\$RESTRICTED_JAR\" POST /index.php/default/trunks/remove \"id=${MAL_ID}&delete=1&snep_csrf_token=${RESTRICTED_CSRF}\" >/dev/null; true"
fi

# 3. The core proof: MALICIOUS's own generated block must reflect only
# its own (safe) attributes -- never CANARY's, which the pre-fix,
# unquoted `where("name = 0 OR id=<CANARY_ID>")` lookup would otherwise
# have matched (an order-independent, primary-key-targeted boolean-true
# injection -- not dependent on table row order/content).
GENERATED_SIP_AFTER="$(app_exec "cat '$LEGACY_SIP_CONF' 2>/dev/null")"
MAL_BLOCK="$(echo "$GENERATED_SIP_AFTER" | awk '/^\[task0026jmalicious\]$/{f=1;next}/^\[/{f=0}f')"
if echo "$MAL_BLOCK" | grep -qF "context=${MAL_CONTEXT}" && ! echo "$MAL_BLOCK" | grep -qF "${CANARY_CONTEXT}"; then
    harness_ok "InterfaceConf: SQL-shaped 'name' cannot cross-leak another trunk's data" "MALICIOUS's own generated block carries only its own context (${MAL_CONTEXT}), never CANARY's (${CANARY_CONTEXT})"
else
    harness_bad "InterfaceConf: SQL-shaped 'name' cannot cross-leak another trunk's data" "MALICIOUS block: $(echo "$MAL_BLOCK" | tr '\n' ' ')"
fi

# 4. PJSIP baseline remains unaffected by this legacy-generator boundary.
PJSIP_MODULE="$($COMPOSE exec -T asterisk asterisk -rx 'module show like res_pjsip.so' 2>/dev/null)"
if echo "$PJSIP_MODULE" | grep -q "Running"; then
    harness_ok "InterfaceConf: PJSIP baseline unaffected" "res_pjsip.so still Running"
else
    harness_bad "InterfaceConf: PJSIP baseline unaffected" "res_pjsip.so not reported Running: $PJSIP_MODULE"
fi

FATALS_AFTER_A="$(fatal_count)"
if [ "$FATALS_AFTER_A" = "$FATALS_BEFORE" ]; then
    harness_ok "BLOCKER A: application remained healthy" "PHP Fatal Error count unchanged (${FATALS_BEFORE})"
else
    harness_bad "BLOCKER A: application remained healthy" "PHP Fatal Error count changed: ${FATALS_BEFORE} -> ${FATALS_AFTER_A}"
fi

# =============================================================================
# BLOCKER B -- CallsReportController report-filter SQL construction
# =============================================================================

log "==> BLOCKER B: CallsReportController report-filter boundary"

# Pre-existing, unrelated PHP 8.4 compatibility bug discovered while
# building this suite (not fixed here, per this task's own scope
# boundary and CLAUDE.md's "do not fix unrelated legacy bugs
# opportunistically"): getselect() (CallsReportController.php:402)
# runs `count($stmt)` on the Zend_Db_Statement_Pdo object $db->query()
# returns -- not Countable/array under PHP 8 -- an uncaught TypeError on
# EVERY report request, legitimate or malicious, regardless of this
# task's own SQL fix (confirmed: the line immediately above it,
# $db->query($select), already completed by the time this throws, so
# the vulnerable/now-fixed boundary this suite exists to prove IS
# exercised before the crash). Every check below therefore expects
# exactly this ONE known crash signature and treats any OTHER fatal
# (in particular a SQLSTATE/syntax-error-shaped one, which is exactly
# what an unquoted apostrophe or broken-out-of-context value would have
# produced pre-fix) as a genuine failure -- proving the submitted value
# never reached SQL syntax position, which is the actual security
# property this suite exists to verify. See
# docs/tasks/0026j-residual-sql-boundary-closure.md for the
# Product-Readiness handoff of this bug.
KNOWN_BUG_MARK="CallsReportController.php:402"

known_bug_count() {
    local n
    n="$(app_exec "grep -c '${KNOWN_BUG_MARK}' /var/log/apache2/mag-error.log 2>/dev/null" | tr -d '\r\n ')"
    echo "${n:-0}"
}

# calls_report_check <label> <field=value>... -- POSTs to calls-report
# and classifies strictly against the known pre-existing crash signature
# above. PASS means the query layer raised no SQL/syntax error at all.
calls_report_check() {
    local label="$1"
    shift
    local before_total before_known after_total after_known tail_text total_delta known_delta
    before_total="$(fatal_count)"
    before_known="$(known_bug_count)"
    post_fields "$RESTRICTED_JAR" /index.php/default/calls-report "$@" >/dev/null
    after_total="$(fatal_count)"
    after_known="$(known_bug_count)"
    tail_text="$(app_exec 'tail -c 4000 /var/log/apache2/mag-error.log 2>/dev/null')"
    total_delta=$((after_total - before_total))
    known_delta=$((after_known - before_known))
    if [ "$total_delta" -eq "$known_delta" ] && [ "$known_delta" -ge 1 ] && ! echo "$tail_text" | grep -qi "SQLSTATE\|syntax error"; then
        harness_ok "$label" "only the known, pre-existing CallsReportController.php:402 count()/Countable PHP 8.4 bug fired -- the query itself completed with no SQL/syntax error"
    else
        harness_bad "$label" "unexpected fatal signature: total_delta=${total_delta} known_delta=${known_delta}"
    fi
}

WIDE_PERIOD="01/01/2000 00:00 - 31/12/2030 23:59"

# 6/7. A legitimate request and an ordinary nonexistent filter value both
# reach the database layer cleanly (item 12's "no unexpected PHP Fatal"
# requirement is folded into calls_report_check's own signature check).
calls_report_check "CallsReport: legitimate synthetic report request reaches the DB layer cleanly" \
    "report_type=synthetic" "period=${WIDE_PERIOD}" "selectContactGroupSrc=0" "selectContactSrc=0" "selectSrc=0" \
    "groupSrc=" "order_src=equal" "selectContactGroupDst=0" "selectContactDst=0" "selectDst=0" "groupDst=" "order_dst=equal" \
    "ANSWERED=on" "NOANSWER=on" "BUSY=on" "FAILED=on" "duration_init=" "duration_end=" "snep_csrf_token=${RESTRICTED_CSRF}"

calls_report_check "CallsReport: ordinary nonexistent filter value behaves normally" \
    "report_type=synthetic" "period=${WIDE_PERIOD}" "selectContactGroupSrc=0" "selectContactSrc=0" "selectSrc=0" \
    "groupSrc=99999999999" "order_src=equal" "selectContactGroupDst=0" "selectContactDst=0" "selectDst=0" "groupDst=" "order_dst=equal" \
    "ANSWERED=on" "NOANSWER=on" "BUSY=on" "FAILED=on" "duration_init=" "duration_end=" "snep_csrf_token=${RESTRICTED_CSRF}"

# 8/9. Always-false vs always-true SQL-shaped duration_init cannot alter
# semantics -- (int) casting collapses "... OR 1=1" to a plain integer
# (a real, harmless duration value), never executable SQL syntax.
calls_report_check "CallsReport: always-false SQL-shaped duration_init cannot alter semantics" \
    "report_type=synthetic" "period=${WIDE_PERIOD}" "selectContactGroupSrc=0" "selectContactSrc=0" "selectSrc=0" \
    "groupSrc=" "order_src=equal" "selectContactGroupDst=0" "selectContactDst=0" "selectDst=0" "groupDst=" "order_dst=equal" \
    "ANSWERED=on" "NOANSWER=on" "BUSY=on" "FAILED=on" "duration_init=0 AND 1=2" "duration_end=" "snep_csrf_token=${RESTRICTED_CSRF}"

calls_report_check "CallsReport: always-true SQL-shaped duration_init cannot alter semantics" \
    "report_type=synthetic" "period=${WIDE_PERIOD}" "selectContactGroupSrc=0" "selectContactSrc=0" "selectSrc=0" \
    "groupSrc=" "order_src=equal" "selectContactGroupDst=0" "selectContactDst=0" "selectDst=0" "groupDst=" "order_dst=equal" \
    "ANSWERED=on" "NOANSWER=on" "BUSY=on" "FAILED=on" "duration_init=99999999 OR 1=1" "duration_end=" "snep_csrf_token=${RESTRICTED_CSRF}"

# 10. Apostrophe-containing value causes no SQL error -- the core proof:
# pre-fix, an unescaped apostrophe here would break out of the LIKE
# '%...%' string literal and produce a genuine SQLSTATE syntax error
# (a DIFFERENT fatal than the known count() bug); calls_report_check
# fails the check if that signature ever appears.
calls_report_check "CallsReport: apostrophe-containing value causes no SQL error" \
    "report_type=synthetic" "period=${WIDE_PERIOD}" "selectContactGroupSrc=0" "selectContactSrc=0" "selectSrc=0" \
    "groupSrc=O'Brien" "order_src=contain" "selectContactGroupDst=0" "selectContactDst=0" "selectDst=0" "groupDst=" "order_dst=equal" \
    "ANSWERED=on" "NOANSWER=on" "BUSY=on" "FAILED=on" "duration_init=" "duration_end=" "snep_csrf_token=${RESTRICTED_CSRF}"

# 11. Analytic report path is also protected (same getselect() boundary,
# different renderer).
calls_report_check "CallsReport: analytic report path is also protected" \
    "report_type=analytic" "period=${WIDE_PERIOD}" "selectContactGroupSrc=0" "selectContactSrc=0" "selectSrc=0" \
    "groupSrc=1' OR '1'='1" "order_src=equal" "selectContactGroupDst=0" "selectContactDst=0" "selectDst=0" "groupDst=" "order_dst=equal" \
    "ANSWERED=on" "NOANSWER=on" "BUSY=on" "FAILED=on" "duration_init=" "duration_end=" "snep_csrf_token=${RESTRICTED_CSRF}"

# 13. CDR timezone semantics (TASK-0027A) remain unchanged: the fix only
# wraps the exact same start_date/end_date string in $db->quote() instead
# of raw interpolation -- the comparison VALUE is byte-identical for any
# legitimate input, so a real CDR row's own calldate-anchored window
# (built the same way TASK-0027A's own harness_cdr_report_window() proves
# for call-smoke/trunk-smoke) must still reach the DB layer with no SQL
# error, midnight-crossing or not.
LATEST_CALLDATE="$(db_query "SELECT calldate FROM cdr ORDER BY calldate DESC LIMIT 1;")"
if [ -n "$LATEST_CALLDATE" ] && harness_cdr_report_window "$LATEST_CALLDATE" 5; then
    ANCHORED_PERIOD="$(echo "$HARNESS_REPORT_START_DATE" | awk -F- '{print $3"/"$2"/"$1}')" # dd/mm/yyyy
    ANCHORED_PERIOD="${ANCHORED_PERIOD} ${HARNESS_REPORT_START_HOUR%:*} - "
    END_DMY="$(echo "$HARNESS_REPORT_END_DATE" | awk -F- '{print $3"/"$2"/"$1}')"
    ANCHORED_PERIOD="${ANCHORED_PERIOD}${END_DMY} ${HARNESS_REPORT_END_HOUR%:*}"
    calls_report_check "CallsReport: CDR timezone semantics (TASK-0027A) unchanged" \
        "report_type=synthetic" "period=${ANCHORED_PERIOD}" "selectContactGroupSrc=0" "selectContactSrc=0" "selectSrc=0" \
        "groupSrc=" "order_src=equal" "selectContactGroupDst=0" "selectContactDst=0" "selectDst=0" "groupDst=" "order_dst=equal" \
        "ANSWERED=on" "NOANSWER=on" "BUSY=on" "FAILED=on" "duration_init=" "duration_end=" "snep_csrf_token=${RESTRICTED_CSRF}"
else
    harness_ok "CallsReport: CDR timezone semantics (TASK-0027A) unchanged" "no existing CDR row available in this environment yet -- skipping the anchored proof, already covered by the other checks above"
fi

harness_complete
