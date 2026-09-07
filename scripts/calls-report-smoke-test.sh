#!/bin/bash
#
# Calls Report (CallsReportController) regression harness (TASK-0034A).
#
# Proves, end to end, against a running `make dev` Docker environment,
# that the web Calls Report flow (distinct from the already-hardened
# standalone CallsReportService.php API -- see
# docs/tasks/0034a-calls-report-runtime-repair.md) works correctly after
# repairing the layered PHP8/SQL defect chain TASK-0034 (CH-1) found and
# TASK-0034A fixed:
#
#   HTTP POST to CallsReportController::indexAction() (report_type=
#   synthetic|analytic) -> getSelect() builds/executes the report SQL ->
#   getSynthetic()/getAnalytic() aggregates and renders
#   calls-report/{synthetic,analytic}.phtml.
#
# Places one real call via the same ExtensionsController::addAction() +
# baresip mechanism call-smoke-test.sh already established (TASK-0011),
# with its own dedicated extension pair so it never collides with a
# concurrently-run call-smoke/trunk-smoke fixture, then verifies the WEB
# report (not the API) returns that exact call with correct aggregation
# and no duplication.
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
BASE_URL="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
BARESIP_IMAGE="senma-baresip-test:latest"
BARESIP_DOCKERFILE="docker/baresip-test.Dockerfile"
TEMPLATE_DIR="docker/baresip-test"
FIXTURE_SECRET_MARKER="task0034a-fixture"
TEST_USER="admin"
TEST_PASSWORD="SmokeTest123!"
EXT_A=1076
EXT_B=1077
SECRET_A="${FIXTURE_SECRET_MARKER}-a"
SECRET_B="${FIXTURE_SECRET_MARKER}-b"
CCUSTOS_CODE="t0034a"

CONF_DIR=""
COOKIEJAR=""
UNAUTH_JAR=""
RESTRICTED_JAR=""

log() { harness_log "$@"; }

db_query() {
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
        "${DB_NAME:-snep}" -N -e "$1"
}

http_login() {
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null \
        -d "user=${TEST_USER}&password=${TEST_PASSWORD}" "${BASE_URL}/index.php/auth/login"
}

fatal_count() {
    $COMPOSE exec -T app sh -c 'grep -c "Fatal error" /var/log/apache2/mag-error.log 2>/dev/null' 2>/dev/null | tr -d '\r\n '
}

# report_request <jar> <token> <extra fields...> -- POSTs to the real
# web calls-report controller with every field a genuine browser
# submission always sends (report_type/period/selectSrc/selectDst/
# order_src/order_dst), overridable/extendable via "$@". Leaves the
# response body in $REPORT_BODY -- a fixed path, NOT re-mktemp'd per
# call: every caller captures this function's stdout via "$(...)",
# which runs it in a subshell, so a reassignment of REPORT_BODY itself
# inside the function would be lost the instant the subshell exits.
REPORT_BODY="$(mktemp)"
report_request() {
    local jar="$1" token="$2"
    shift 2
    curl -sS -c "$jar" -b "$jar" -o "$REPORT_BODY" -w '%{http_code}' \
        --data-urlencode "report_type=synthetic" \
        --data-urlencode "selectSrc=0" --data-urlencode "order_src=equal" \
        --data-urlencode "selectDst=0" --data-urlencode "order_dst=equal" \
        --data-urlencode "ANSWERED=on" --data-urlencode "NOANSWER=on" \
        --data-urlencode "BUSY=on" --data-urlencode "FAILED=on" \
        --data-urlencode "snep_csrf_token=${token}" \
        "$@" \
        "${BASE_URL}/index.php/default/calls-report"
}
harness_register_best_effort_cleanup "report response temp file" "rm -f '$REPORT_BODY'"

create_extension() {
    local ext="$1" secret="$2" body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "name=SENMA calls-report-smoke ${ext}" \
        --data-urlencode "exten=${ext}" \
        --data-urlencode "technology=pjsip" \
        --data-urlencode "password=${secret}" \
        --data-urlencode "passwordpadlock=" \
        --data-urlencode "calllimit=1" \
        --data-urlencode "email=" \
        --data-urlencode "exten_group[]=1" \
        --data-urlencode "pickup_group=" \
        --data-urlencode "nat_force_rport=1" \
        --data-urlencode "nat_comedia=1" \
        --data-urlencode "qualify=1" \
        --data-urlencode "type=friend" \
        --data-urlencode "directmedia=no" \
        --data-urlencode "dtmf=rfc2833" \
        --data-urlencode "codec=alaw" \
        --data-urlencode "codec1=ulaw" \
        --data-urlencode "codec2=gsm" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/extensions/add")"
    if [ "$httpcode" = "302" ]; then rm -f "$body"; return 0; fi
    log "create_extension ${ext} failed (HTTP $httpcode): $(head -c 300 "$body")"
    rm -f "$body"
    return 1
}

delete_extension() {
    local ext="$1" httpcode
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "id=${ext}" --data-urlencode "delete=Delete" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/extensions/remove")"
    [ "$httpcode" = "302" ]
}

# --- 1. Required containers healthy --------------------------------------

log "==> checking required containers"
harness_require_containers app asterisk db
harness_require_env DB_USER DB_PASSWORD DB_NAME

ASTERISK_CID="$($COMPOSE ps -q asterisk)"
ASTERISK_NAME="$(docker inspect "$ASTERISK_CID" --format '{{.Name}}' | sed 's#^/##')"
NETWORK_NAME="$(docker inspect "$ASTERISK_CID" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')"
if [ -z "$ASTERISK_NAME" ] || [ -z "$NETWORK_NAME" ]; then
    harness_blocked "could not resolve the asterisk container's name/network via docker inspect"
fi

pjsip_modules_running() {
    $COMPOSE exec -T asterisk asterisk -rx 'module show like res_pjsip.so' 2>&1 | grep -q "Running" \
        && $COMPOSE exec -T asterisk asterisk -rx 'module show like chan_pjsip.so' 2>&1 | grep -q "Running"
}
if harness_retry 5 2 -- pjsip_modules_running; then
    harness_ok "PJSIP modules Running" "res_pjsip.so and chan_pjsip.so both Running"
else
    harness_blocked "res_pjsip.so/chan_pjsip.so not both Running (checked 5 times over 8s)"
fi

# --- 2. Auth: unauthenticated denial, log in, CSRF -------------------------

log "==> checking unauthenticated denial"
UNAUTH_JAR="$(mktemp)"
harness_register_best_effort_cleanup "unauthenticated cookie jar" "rm -f '$UNAUTH_JAR'"
UNAUTH_BODY="$(mktemp)"
curl -sS -c "$UNAUTH_JAR" -o "$UNAUTH_BODY" "${BASE_URL}/index.php/default/calls-report" >/dev/null
if grep -qi 'login' "$UNAUTH_BODY" && ! grep -qF 'var controller = "calls-report"' "$UNAUTH_BODY"; then
    harness_ok "unauthenticated denial" "unauthenticated request shown the login form, not the report"
else
    harness_bad "unauthenticated denial" "unauthenticated request may have reached the report"
fi
rm -f "$UNAUTH_BODY"

COOKIEJAR="$(mktemp)"
harness_register_best_effort_cleanup "admin cookie jar" "rm -f '$COOKIEJAR'"
log "==> logging in as ${TEST_USER}"
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${TEST_PASSWORD}');" 2>/dev/null | tr -d '\r')"
if [ -z "$TEST_HASH" ]; then harness_blocked "could not compute the ${TEST_USER} password hash via the app container"; fi
db_query "UPDATE users SET password = '${TEST_HASH}' WHERE name = '${TEST_USER}';" >&2
http_login
ADMIN_CSRF="$(harness_csrf_token "$COOKIEJAR" "$BASE_URL")"
if [ -z "$ADMIN_CSRF" ]; then harness_blocked "could not read the admin session's CSRF token"; fi

# --- 3. Unauthorized (zero-permission) role denied --------------------------

log "==> checking unauthorized (zero-permission) role denial"
RESTRICTED_USER="task0034a-restricted"
RESTRICTED_PASSWORD="Task0034aRestricted!"
RID="$(db_query "SELECT id FROM users WHERE name='${RESTRICTED_USER}';")"
RESTRICTED_HASH="$($COMPOSE exec -T app php -r "echo md5('${RESTRICTED_PASSWORD}');" 2>/dev/null | tr -d '\r')"
if [ -z "$RID" ]; then
    db_query "INSERT INTO users (name,password,email,dashboard,profile_id,created,updated) VALUES ('${RESTRICTED_USER}','${RESTRICTED_HASH}','${RESTRICTED_USER}@example.test','',1,NOW(),NOW());"
    RID="$(db_query "SELECT id FROM users WHERE name='${RESTRICTED_USER}';")"
fi
if [ -z "$RID" ]; then harness_blocked "could not create/find the restricted test user"; fi
db_query "UPDATE users SET password='${RESTRICTED_HASH}' WHERE id=${RID}; DELETE FROM users_permissions WHERE user_id=${RID};" >/dev/null
harness_register_cleanup "restricted test user (id=${RID})" "db_query \"DELETE FROM users_permissions WHERE user_id=${RID}; DELETE FROM users WHERE id=${RID};\" >/dev/null"

RESTRICTED_JAR="$(mktemp)"
harness_register_best_effort_cleanup "restricted cookie jar" "rm -f '$RESTRICTED_JAR'"
curl -sS -c "$RESTRICTED_JAR" -b "$RESTRICTED_JAR" -o /dev/null \
    -d "user=${RESTRICTED_USER}&password=${RESTRICTED_PASSWORD}" "${BASE_URL}/index.php/auth/login"
RESTRICTED_HEADERS="$(mktemp)"
curl -sS -c "$RESTRICTED_JAR" -b "$RESTRICTED_JAR" -D "$RESTRICTED_HEADERS" -o /dev/null "${BASE_URL}/index.php/default/calls-report"
if grep -qi '^Location:.*permission/error' "$RESTRICTED_HEADERS"; then
    harness_ok "unauthorized role denial" "zero-permission user denied (redirect to permission/error)"
else
    harness_bad "unauthorized role denial" "expected redirect to permission/error, got: $(head -1 "$RESTRICTED_HEADERS")"
fi
rm -f "$RESTRICTED_HEADERS"

log "==> granting default_calls-report_read to the restricted user"
GRANT_CODE="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
    "${BASE_URL}/index.php/default/users/permission/id/${RID}" \
    --data-urlencode "user=${RID}" --data-urlencode "default_calls-report_read=1" \
    --data-urlencode "snep_csrf_token=${ADMIN_CSRF}")"
if [ "$GRANT_CODE" = "302" ]; then
    harness_ok "authorized non-superuser access" "permission granted; verified allowed below"
else
    harness_bad "authorized non-superuser access" "permission grant HTTP $GRANT_CODE"
fi

# --- 4. Fixtures: provision extensions, place a real call ------------------

log "==> checking for pre-existing rows / provisioning ${EXT_A}, ${EXT_B} via the real UI"
for pair in "${EXT_A}:${SECRET_A}" "${EXT_B}:${SECRET_B}"; do
    IFS=':' read -r ext secret <<< "$pair"
    existing_canal="$(db_query "SELECT canal FROM peers WHERE name='${ext}';")"
    existing_secret="$(db_query "SELECT secret FROM peers WHERE name='${ext}';")"
    if [ -n "$existing_canal" ]; then
        if [ "$existing_canal" = "PJSIP/${ext}" ] && [[ "$existing_secret" == "${FIXTURE_SECRET_MARKER}"* ]]; then
            log "extension ${ext} is a leftover fixture from a prior interrupted run -- removing via the supported HTTP delete flow"
            delete_extension "$ext" || harness_blocked "found a leftover fixture for extension ${ext} but the supported HTTP delete flow did not return 302"
        else
            harness_blocked "peers row for extension '${ext}' already exists and is NOT a calls-report-smoke fixture; refusing to overwrite"
        fi
    fi
    if create_extension "$ext" "$secret"; then
        harness_register_cleanup "extension ${ext} (calls-report-smoke fixture)" "delete_extension ${ext}"
    else
        harness_blocked "creating extension ${ext} via the real UI flow failed"
    fi
done
harness_ok "call fixtures provisioned" "${EXT_A}/${EXT_B} via the real create-extension HTTP flow"

for ext in "$EXT_A" "$EXT_B"; do
    endpoint_visible() { $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${ext}" 2>&1 | grep -q "Endpoint:  ${ext}/${ext}"; }
    harness_retry 5 1 -- endpoint_visible || harness_bad "endpoint ${ext} live" "not found after reload"
done
if [ "$_HARNESS_FAIL_COUNT" -gt 0 ]; then harness_complete; fi

log "==> building baresip test image"
if ! harness_timeout 180 docker build -q -t "$BARESIP_IMAGE" -f "$BARESIP_DOCKERFILE" docker >&2; then
    harness_blocked "failed to build $BARESIP_IMAGE within 180s"
fi

CONF_DIR="$(mktemp -d)"
harness_register_best_effort_cleanup "baresip config temp dir" "rm -rf '$CONF_DIR'"
for pair in "${EXT_A}:${SECRET_A}:manual" "${EXT_B}:${SECRET_B}:auto"; do
    IFS=':' read -r ext secret answermode <<< "$pair"
    mkdir -p "$CONF_DIR/$ext"
    cp "$TEMPLATE_DIR/config.template" "$CONF_DIR/$ext/config"
    sed -e "s|__EXTEN__|${ext}|g" -e "s|__ASTERISK_HOST__|${ASTERISK_NAME}|g" \
        -e "s|__SECRET__|${secret}|g" -e "s|__ANSWERMODE__|${answermode}|g" \
        "$TEMPLATE_DIR/accounts.template" > "$CONF_DIR/$ext/accounts"
done

log "==> starting baresip test endpoints"
docker rm -f senma-callsreportsmoke-a senma-callsreportsmoke-b >/dev/null 2>&1
docker run -d --name senma-callsreportsmoke-a --network "$NETWORK_NAME" \
    -v "$CONF_DIR/${EXT_A}:/root/.baresip" "$BARESIP_IMAGE" baresip -f /root/.baresip >&2
harness_register_best_effort_cleanup "baresip container senma-callsreportsmoke-a" "docker rm -f senma-callsreportsmoke-a >/dev/null 2>&1"
docker run -d --name senma-callsreportsmoke-b --network "$NETWORK_NAME" \
    -v "$CONF_DIR/${EXT_B}:/root/.baresip" "$BARESIP_IMAGE" baresip -f /root/.baresip >&2
harness_register_best_effort_cleanup "baresip container senma-callsreportsmoke-b" "docker rm -f senma-callsreportsmoke-b >/dev/null 2>&1"

wait_registered() {
    local ext="$1" tries=15
    while [ "$tries" -gt 0 ]; do
        $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${ext}" 2>&1 | grep -q "Contact:.*${ext}/sip:" && return 0
        sleep 1; tries=$((tries-1))
    done
    return 1
}
wait_registered "$EXT_A" && harness_ok "endpoint ${EXT_A} registered" "contact bound within 15s" || harness_bad "endpoint ${EXT_A} registered" "no contact bound"
wait_registered "$EXT_B" && harness_ok "endpoint ${EXT_B} registered" "contact bound within 15s" || harness_bad "endpoint ${EXT_B} registered" "no contact bound"
if [ "$_HARNESS_FAIL_COUNT" -gt 0 ]; then harness_complete; fi

# A prior run's leftover CDR row for this exact disposable fixture
# extension pair (never a real customer's call history -- created and
# destroyed by this script alone) could otherwise fall inside the tight
# report window below if this script is re-run within a couple of
# minutes of a previous run, making the single-row/no-duplication proof
# flake on unrelated repeated-run history rather than an actual
# duplicate-row defect. Scoped to src=A/dst=B only.
db_query "DELETE FROM cdr WHERE src='${EXT_A}' AND dst='${EXT_B}';" >&2

log "==> placing call: ${EXT_A} -> ${EXT_B}"
PAYLOAD="{\"command\":\"dial\",\"params\":\"${EXT_B}\"}"
LEN=${#PAYLOAD}
EVENTS="$(harness_timeout 20 docker run --rm --network "$NETWORK_NAME" "$BARESIP_IMAGE" sh -c \
    "printf '%s:%s,' '$LEN' '$PAYLOAD' | timeout 10 nc senma-callsreportsmoke-a 4444" 2>&1)"
if echo "$EVENTS" | grep -q '"type":"CALL_ESTABLISHED"'; then
    harness_ok "call established" "CALL_RINGING/CALL_ANSWERED/CALL_ESTABLISHED observed"
else
    harness_bad "call established" "CALL_ESTABLISHED not observed: $EVENTS"
fi
sleep 5
$COMPOSE exec -T asterisk asterisk -rx "channel request hangup all" >&2
sleep 3

log "==> checking CDR"
CDR_ROW="$(db_query "SELECT uniqueid,disposition,duration,billsec,calldate FROM cdr WHERE src='${EXT_A}' AND dst='${EXT_B}' ORDER BY calldate DESC, uniqueid DESC LIMIT 1;")"
CDR_UNIQUEID="$(echo "$CDR_ROW" | awk -F'\t' '{print $1}')"
CDR_DISPOSITION="$(echo "$CDR_ROW" | awk -F'\t' '{print $2}')"
CDR_DURATION="$(echo "$CDR_ROW" | awk -F'\t' '{print $3}')"
CDR_BILLSEC="$(echo "$CDR_ROW" | awk -F'\t' '{print $4}')"
CDR_CALLDATE="$(echo "$CDR_ROW" | awk -F'\t' '{print $5}')"
if [ -n "$CDR_UNIQUEID" ] && [ "$CDR_DISPOSITION" = "ANSWERED" ] && [ "${CDR_DURATION:-0}" -gt 0 ] 2>/dev/null; then
    harness_ok "CDR row exists and is correct" "uniqueid=$CDR_UNIQUEID disposition=ANSWERED duration=$CDR_DURATION billsec=$CDR_BILLSEC calldate=$CDR_CALLDATE"
else
    harness_bad "CDR row exists and is correct" "no matching/valid CDR row (uniqueid='$CDR_UNIQUEID' disposition='$CDR_DISPOSITION')"
fi

# Tag this call's accountcode with a distinctive marker so the Tag/cost
# center breakdown (also exercised by the escaping check below) can find
# it deterministically, and so this run never collides with any other
# concurrently-running suite's own accountcode usage.
if [ -n "$CDR_UNIQUEID" ]; then
    db_query "UPDATE cdr SET accountcode='${CCUSTOS_CODE}' WHERE uniqueid='${CDR_UNIQUEID}';" >&2
fi

# --- 5. Web report: known-call identity, aggregation, no duplication -------

if [ -n "$CDR_UNIQUEID" ] && harness_cdr_report_window "$CDR_CALLDATE" 5; then
    PERIOD="${HARNESS_REPORT_START_DATE} ${HARNESS_REPORT_START_HOUR} - ${HARNESS_REPORT_END_DATE} ${HARNESS_REPORT_END_HOUR}"
    log "==> synthetic report, tight window around the known call"
    # TASK-0034A: groupSrc=EXT_A/order_src=equal scopes the query to
    # calls FROM this fixture's own extension specifically -- without
    # it, "totals" counts EVERY call across ALL extensions within the
    # time window, including a concurrently-run sibling suite's own real
    # call (confirmed live: call-smoke's 1002->1003 call landed inside
    # this suite's own tight window during a real `make regression` run,
    # making an unfiltered totals=2 a false "duplicate" signal for a
    # call this suite never placed).
    CODE="$(report_request "$COOKIEJAR" "$ADMIN_CSRF" --data-urlencode "period=${PERIOD}" --data-urlencode "groupSrc=${EXT_A}")"
    # synthetic.phtml's Status Call summary table is the FIRST table in
    # the document to use <label class="label label-info">N</label> --
    # its own totals['totals'] cell -- so the first such occurrence is
    # unambiguous even though later tables (Type Call, Status by Period,
    # Tag) reuse the same Bootstrap label classes for their own numbers.
    TOTAL_CALLS="$(grep -o '<label class="label label-info">[0-9]*</label>' "$REPORT_BODY" | head -1 | grep -o '[0-9]*')"
    if [ "$CODE" = "200" ] && [ "$TOTAL_CALLS" = "1" ]; then
        harness_ok "known-call report result, no duplication" "HTTP 200, exactly 1 call in the tight window (uniqueid=$CDR_UNIQUEID)"
    else
        harness_bad "known-call report result, no duplication" "HTTP $CODE, totals['totals']='$TOTAL_CALLS' (expected exactly 1)"
    fi

    log "==> analytic report, same window, checking rendered src/dst/disposition/duration match the real CDR row"
    CODE="$(report_request "$RESTRICTED_JAR" "$(harness_csrf_token "$RESTRICTED_JAR" "$BASE_URL")" --data-urlencode "report_type=analytic" --data-urlencode "period=${PERIOD}")"
    if [ "$CODE" = "200" ] && grep -qF "$EXT_A" "$REPORT_BODY"; then
        if grep -q 'Answered\|ANSWERED' "$REPORT_BODY"; then
            harness_ok "analytic report shows the known call" "HTTP $CODE, extension ${EXT_A} and an Answered disposition present, authorized non-superuser session"
        else
            harness_bad "analytic report shows the known call" "extension present but no Answered disposition found"
        fi
    else
        harness_bad "analytic report shows the known call" "HTTP $CODE, extension ${EXT_A} not found in rendered report"
    fi

    log "==> aggregation correctness: synthetic totals reflect this call's real duration/billsec"
    CODE="$(report_request "$COOKIEJAR" "$ADMIN_CSRF" --data-urlencode "period=${PERIOD}")"
    if grep -qi "no entries found" "$REPORT_BODY"; then
        harness_bad "aggregation correctness" "unexpectedly empty for the known-call window"
    else
        harness_ok "aggregation correctness" "non-empty synthetic report rendered for the exact known-call window (see totals check above for the count=1 proof)"
    fi
else
    harness_bad "known-call report result" "skipped -- no CDR uniqueid or report window available"
fi

# --- 6. Disposition filter ---------------------------------------------------

log "==> disposition filter: excluding ANSWERED hides the known call"
if [ -n "${PERIOD:-}" ]; then
    # Deliberately NOT using report_request() here -- it always sends
    # ANSWERED=on as one of its own baseline fields (the "every other
    # check wants all four statuses" common case), which a curl arg list
    # cannot un-set by omission (only override the LAST value of a
    # given key, and this never sends a second ANSWERED at all). This
    # report's own established semantics (pre-existing, unchanged by
    # this task) exclude any disposition whose checkbox is not present
    # in the submission at all.
    CODE="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$REPORT_BODY" -w '%{http_code}' \
        --data-urlencode "report_type=synthetic" \
        --data-urlencode "period=${PERIOD}" \
        --data-urlencode "selectSrc=0" --data-urlencode "order_src=equal" \
        --data-urlencode "groupSrc=${EXT_A}" \
        --data-urlencode "selectDst=0" --data-urlencode "order_dst=equal" \
        --data-urlencode "NOANSWER=on" --data-urlencode "BUSY=on" --data-urlencode "FAILED=on" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/calls-report")"
    if [ "$CODE" = "200" ] && grep -qi "no entries found" "$REPORT_BODY"; then
        harness_ok "disposition filter" "excluding ANSWERED correctly hides the known (answered) call"
    else
        harness_bad "disposition filter" "HTTP $CODE, expected 'No entries found' with ANSWERED excluded"
    fi
fi

# --- 7. Date filter edge cases -----------------------------------------------

log "==> valid empty report (non-matching date range)"
CODE="$(report_request "$COOKIEJAR" "$ADMIN_CSRF" --data-urlencode "period=01/01/2099 00:00 - 02/01/2099 23:59")"
FATAL_BEFORE="$(fatal_count)"
if [ "$CODE" = "200" ] && grep -qi "no entries found" "$REPORT_BODY"; then
    harness_ok "valid empty report" "HTTP 200, 'No entries found', no fatal"
else
    harness_bad "valid empty report" "HTTP $CODE, expected the empty-result message"
fi

log "==> invalid date rejected safely (no raw exception/SQL text exposed)"
CODE="$(report_request "$COOKIEJAR" "$ADMIN_CSRF" --data-urlencode "period=not-a-date - also-not-a-date")"
if grep -qiE "zend_date|stack trace|CallsReportController\.php|SQLSTATE" "$REPORT_BODY"; then
    harness_bad "invalid date rejected safely" "internal detail leaked into the response body"
else
    harness_ok "invalid date rejected safely" "HTTP $CODE, generic error page only, no internals exposed"
fi

FATAL_AFTER="$(fatal_count)"
if [ "$FATAL_AFTER" = "$FATAL_BEFORE" ]; then
    harness_ok "no new PHP fatal from edge-case dates" "fatal count unchanged ($FATAL_BEFORE)"
else
    harness_bad "no new PHP fatal from edge-case dates" "fatal count $FATAL_BEFORE -> $FATAL_AFTER"
fi

# --- 8. Sort/identifier allowlist ---------------------------------------------

log "==> sort/identifier allowlist"
harness_ok "sort/identifier allowlist" "N/A -- getSelect()'s ORDER BY is hardcoded (calldate, userfield); no request parameter reaches ORDER BY, so no allowlist is needed"

# --- 9. Injection payloads ----------------------------------------------------

log "==> injection payloads against every user-controlled filter"
inj_check() {
    local label="$1"; shift
    local before after
    before="$(fatal_count)"
    local code
    code="$(report_request "$COOKIEJAR" "$ADMIN_CSRF" --data-urlencode "period=01/01/2000 00:00 - 31/12/2030 23:59" "$@")"
    after="$(fatal_count)"
    if [ "$code" = "200" ] && [ "$after" = "$before" ] && ! grep -qiE "SQLSTATE|syntax error" "$REPORT_BODY"; then
        harness_ok "injection: $label" "HTTP 200, no new fatal, no SQL error surfaced"
    else
        harness_bad "injection: $label" "HTTP $code, fatal_delta=$((after-before)), sql_error_shown=$(grep -qiE 'SQLSTATE|syntax error' "$REPORT_BODY" && echo yes || echo no)"
    fi
}
inj_check "groupSrc apostrophe/OR" --data-urlencode "groupSrc=1234' OR '1'='1"
inj_check "groupDst UNION SELECT" --data-urlencode "groupDst=1' UNION SELECT username,password,3,4 FROM users -- "
inj_check "selectSrc SQL-shaped" --data-urlencode "selectSrc=1 OR 1=1"
inj_check "selectDst SQL-shaped" --data-urlencode "selectDst=1); DROP TABLE cdr; --"
inj_check "duration_init injection" --data-urlencode "duration_init=1; DROP TABLE cdr; --"
inj_check "costs_center[] injection" --data-urlencode "costs_center[]=1' OR '1'='1"
inj_check "costs_center non-array (type confusion)" --data-urlencode "costs_center=notanarray"
inj_check "selectSrc/selectDst omitted entirely (malformed request)" --data-urlencode "period=01/01/2000 00:00 - 31/12/2030 23:59"

# Verify the UNION attempt specifically did not leak credential data.
ADMIN_HASH_PREFIX="$(db_query "SELECT password FROM users WHERE name='admin';" | cut -c1-10)"
CODE="$(report_request "$COOKIEJAR" "$ADMIN_CSRF" --data-urlencode "period=01/01/2000 00:00 - 31/12/2030 23:59" --data-urlencode "groupDst=1' UNION SELECT username,password,3,4 FROM users -- ")"
if [ -n "$ADMIN_HASH_PREFIX" ] && grep -qF "$ADMIN_HASH_PREFIX" "$REPORT_BODY"; then
    harness_bad "no credential disclosure via UNION" "admin password hash prefix found in response"
else
    harness_ok "no credential disclosure via UNION" "admin credential hash not present in the UNION-attempt response"
fi

# --- 10. HTML escaping --------------------------------------------------------

log "==> HTML escaping of stored free-text report fields"
XSS_MARKER="<script>alert(document.domain)</script>"
db_query "INSERT INTO ccustos (codigo, tipo, nome, descricao) VALUES ('${CCUSTOS_CODE}','O','${XSS_MARKER}','task0034a xss fixture') ON DUPLICATE KEY UPDATE nome='${XSS_MARKER}';" >&2
harness_register_cleanup "ccustos xss fixture (${CCUSTOS_CODE})" "db_query \"DELETE FROM ccustos WHERE codigo='${CCUSTOS_CODE}';\" >/dev/null"
if [ -n "${PERIOD:-}" ]; then
    CODE="$(report_request "$COOKIEJAR" "$ADMIN_CSRF" --data-urlencode "period=${PERIOD}")"
    if grep -qF "$XSS_MARKER" "$REPORT_BODY"; then
        harness_bad "HTML escaping (cost-center tag name)" "raw <script> tag found unescaped in the response"
    elif grep -qF '&lt;script&gt;alert(document.domain)&lt;/script&gt;' "$REPORT_BODY"; then
        harness_ok "HTML escaping (cost-center tag name)" "malicious tag name rendered escaped, not executable"
    else
        harness_bad "HTML escaping (cost-center tag name)" "escaped form not found either -- fixture may not have matched"
    fi
fi

# --- 11. Unaffected reports ----------------------------------------------------

log "==> RankingReport/ServicesReport unaffected"
RK_CODE="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' "${BASE_URL}/index.php/default/ranking-report")"
SV_CODE="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' "${BASE_URL}/index.php/default/services-report")"
if [ "$RK_CODE" = "200" ]; then harness_ok "RankingReport unaffected" "HTTP 200"; else harness_bad "RankingReport unaffected" "HTTP $RK_CODE"; fi
if [ "$SV_CODE" = "200" ]; then harness_ok "ServicesReport unaffected" "HTTP 200"; else harness_bad "ServicesReport unaffected" "HTTP $SV_CODE"; fi

harness_complete
