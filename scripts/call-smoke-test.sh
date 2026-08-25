#!/bin/bash
#
# First real PJSIP call smoke test (TASK-0009).
#
# Proves, end to end, against a running `make dev` Docker environment:
#   PJSIP/1000 -> existing SENMA extensions.conf -> existing SENMA AGI
#   (snep/snep.php) -> existing PBX_Rules/PBX_Dialplan rule engine ->
#   PBX_Rule_Action_DiscarRamal -> PBX_Asterisk_Interface_PJSIP ->
#   Dial(PJSIP/1001) -> answered call -> real cdr_adaptive_odbc CDR row ->
#   existing SENMA report endpoint reads it back.
#
# Uses two disposable baresip containers (docker/baresip-test.Dockerfile)
# as the two endpoints -- not SIPp (not packaged for Debian 13), not
# physical phones. See docs/tasks/0009-first-pjsip-call.md.
#
# Separate from scripts/smoke-test.sh (HTTP-only) by design -- this is
# SIP/telephony-level, a different failure domain.
#
# Exit code: 0 if every check PASSes; 1 if any check FAILs.

set -uo pipefail

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
BASE_URL="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
BARESIP_IMAGE="senma-baresip-test:latest"
BARESIP_DOCKERFILE="docker/baresip-test.Dockerfile"
TEMPLATE_DIR="docker/baresip-test"
FIXTURE_SECRET_MARKER="task0009-fixture"
TEST_USER="admin"
TEST_PASSWORD="SmokeTest123!"

PASS=0
FAIL=0
declare -a RESULTS=()
CREATED_1000=0
CREATED_1001=0
CONF_DIR=""

log()  { printf '%s\n' "$*" >&2; }
row()  { RESULTS+=("$1|$2|$3"); }
ok()   { row "$1" "PASS" "$2"; PASS=$((PASS+1)); log "PASS: $1 -- $2"; }
bad()  { row "$1" "FAIL" "$2"; FAIL=$((FAIL+1)); log "FAIL: $1 -- $2"; }

print_report() {
    echo
    echo "================================================================"
    printf "%-32s %-8s %s\n" "CHECK" "RESULT" "DETAIL"
    echo "----------------------------------------------------------------"
    for r in "${RESULTS[@]}"; do
        IFS='|' read -r flow status detail <<< "$r"
        printf "%-32s %-8s %s\n" "$flow" "$status" "$detail"
    done
    echo "================================================================"
    echo "PASS: $PASS   FAIL: $FAIL"
    echo "================================================================"
}

# Hard stop: an unsafe/ambiguous state (e.g. a real, non-fixture peers row
# already occupying 1000/1001). Distinct from `bad()` -- this is not a
# checklist item failing, it's refusing to proceed at all.
stop() {
    log "STOP: $*"
    echo "STOP: $*"
    cleanup
    exit 1
}

db_query() {
    # stderr deliberately NOT redirected to /dev/null -- it flows through
    # to this script's own stderr (log stream) and is excluded from
    # $(db_query ...) capture by normal command-substitution semantics.
    # A silenced SQL error here would otherwise read back as "" with no
    # visible cause (this bit a first draft: `ORDER BY ... id DESC` on a
    # `cdr` table with no `id` column silently returned empty).
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
        "${DB_NAME:-snep}" -N -e "$1"
}

cleanup() {
    trap - EXIT
    log "==> cleanup"
    docker rm -f senma-callsmoke-1000 senma-callsmoke-1001 >/dev/null 2>&1
    [ -n "$CONF_DIR" ] && rm -rf "$CONF_DIR"
    if [ "$CREATED_1000" = "1" ]; then
        db_query "DELETE FROM peers WHERE name='1000' AND secret='${FIXTURE_SECRET_MARKER}';" >&2
        log "removed test fixture peer 1000"
    fi
    if [ "$CREATED_1001" = "1" ]; then
        db_query "DELETE FROM peers WHERE name='1001' AND secret='${FIXTURE_SECRET_MARKER}';" >&2
        log "removed test fixture peer 1001"
    fi
}
trap cleanup EXIT

# --- 1. Required containers healthy --------------------------------------

log "==> checking required containers"
ALL_UP=1
for svc in app asterisk db; do
    if ! $COMPOSE ps "$svc" 2>/dev/null | grep -q "Up"; then
        ALL_UP=0
    fi
done
if [ "$ALL_UP" = "1" ]; then
    ok "containers healthy" "app, asterisk, db all Up"
else
    bad "containers healthy" "one or more of app/asterisk/db not Up -- run 'make up' first"
    cleanup
    trap - EXIT
    exit 1
fi

: "${DB_USER:?DB_USER must be set (source .env first)}"
: "${DB_PASSWORD:?DB_PASSWORD must be set (source .env first)}"
: "${DB_NAME:?DB_NAME must be set (source .env first)}"
: "${PJSIP_TEST_1000_SECRET:?PJSIP_TEST_1000_SECRET must be set (source .env first)}"
: "${PJSIP_TEST_1001_SECRET:?PJSIP_TEST_1001_SECRET must be set (source .env first)}"

ASTERISK_CID="$($COMPOSE ps -q asterisk)"
ASTERISK_NAME="$(docker inspect "$ASTERISK_CID" --format '{{.Name}}' | sed 's#^/##')"
NETWORK_NAME="$(docker inspect "$ASTERISK_CID" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')"
if [ -z "$ASTERISK_NAME" ] || [ -z "$NETWORK_NAME" ]; then
    stop "could not resolve the asterisk container's name/network via docker inspect"
fi
log "asterisk container: $ASTERISK_NAME  network: $NETWORK_NAME"

# --- 2. Asterisk PJSIP modules Running ------------------------------------

log "==> checking PJSIP module state"
PJSIP_STATE="$($COMPOSE exec -T asterisk asterisk -rx 'module show like res_pjsip.so' 2>&1)"
CHANPJSIP_STATE="$($COMPOSE exec -T asterisk asterisk -rx 'module show like chan_pjsip.so' 2>&1)"
if echo "$PJSIP_STATE" | grep -q "Running" && echo "$CHANPJSIP_STATE" | grep -q "Running"; then
    ok "PJSIP modules Running" "res_pjsip.so and chan_pjsip.so both Running"
else
    bad "PJSIP modules Running" "res_pjsip.so/chan_pjsip.so not both Running"
    cleanup
    trap - EXIT
    exit 1
fi

# --- 3. Test fixtures available -------------------------------------------

log "==> checking/creating peers fixtures (1000, 1001)"
for ext in 1000 1001; do
    existing_canal="$(db_query "SELECT canal FROM peers WHERE name='${ext}';")"
    existing_secret="$(db_query "SELECT secret FROM peers WHERE name='${ext}';")"
    if [ -n "$existing_canal" ]; then
        if [ "$existing_canal" = "PJSIP/${ext}" ] && [ "$existing_secret" = "$FIXTURE_SECRET_MARKER" ]; then
            log "peer ${ext} already exists as our own test fixture -- reusing"
        else
            stop "peers row for extension '${ext}' already exists (canal='${existing_canal}') and is NOT a call-smoke fixture (secret marker mismatch). Refusing to overwrite real/unknown data. Remove or rename it manually, or use a different test range, before running make call-smoke."
        fi
    else
        db_query "INSERT INTO peers (name, password, secret, callerid, host, canal, type, defaultuser, usa_vc, peer_type, trunk, lastms, context, authenticate, dnd) VALUES ('${ext}', '${ext}', '${FIXTURE_SECRET_MARKER}', '${ext}', 'dynamic', 'PJSIP/${ext}', 'friend', '', 'no', 'R', 'no', 0, 'default', 0, 0);" >&2
        if [ "$ext" = "1000" ]; then CREATED_1000=1; else CREATED_1001=1; fi
        log "created test fixture peer ${ext}"
    fi
done
ok "test fixtures available" "peers 1000/1001 present (canal=PJSIP/1000, PJSIP/1001)"

# --- Build baresip test image, generate per-instance config --------------

log "==> building baresip test image"
if ! docker build -q -t "$BARESIP_IMAGE" -f "$BARESIP_DOCKERFILE" docker >&2; then
    stop "failed to build $BARESIP_IMAGE from $BARESIP_DOCKERFILE"
fi

CONF_DIR="$(mktemp -d)"
for ext in 1000 1001; do
    mkdir -p "$CONF_DIR/$ext"
    cp "$TEMPLATE_DIR/config.template" "$CONF_DIR/$ext/config"
    secret_var="PJSIP_TEST_${ext}_SECRET"
    secret="${!secret_var}"
    answermode="manual"
    [ "$ext" = "1001" ] && answermode="auto"
    sed \
        -e "s|__EXTEN__|${ext}|g" \
        -e "s|__ASTERISK_HOST__|${ASTERISK_NAME}|g" \
        -e "s|__SECRET__|${secret}|g" \
        -e "s|__ANSWERMODE__|${answermode}|g" \
        "$TEMPLATE_DIR/accounts.template" > "$CONF_DIR/$ext/accounts"
done

# --- 4/5. Start both endpoints, wait for registration ----------------------

log "==> starting baresip test endpoints"
docker run -d --name senma-callsmoke-1000 --network "$NETWORK_NAME" \
    -v "$CONF_DIR/1000:/root/.baresip" "$BARESIP_IMAGE" baresip -f /root/.baresip >&2
docker run -d --name senma-callsmoke-1001 --network "$NETWORK_NAME" \
    -v "$CONF_DIR/1001:/root/.baresip" "$BARESIP_IMAGE" baresip -f /root/.baresip >&2

wait_registered() {
    local ext="$1" tries=15
    while [ "$tries" -gt 0 ]; do
        if $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${ext}" 2>&1 | grep -q "Contact:.*${ext}/sip:"; then
            return 0
        fi
        sleep 1
        tries=$((tries-1))
    done
    return 1
}

if wait_registered 1000; then
    ok "endpoint 1000 registered" "contact bound to AOR 1000 within 15s"
else
    bad "endpoint 1000 registered" "no contact bound within 15s"
fi

if wait_registered 1001; then
    ok "endpoint 1001 registered" "contact bound to AOR 1001 within 15s"
else
    bad "endpoint 1001 registered" "no contact bound within 15s"
fi

if [ "$FAIL" -gt 0 ]; then
    log "registration failed -- aborting before placing a call"
    cleanup
    trap - EXIT
    print_report
    exit 1
fi

# --- 6-9. Place the call, verify ringing/answered/established -------------

log "==> placing call: 1000 -> 1001"
LOG_MARK_BEFORE="$($COMPOSE exec -T asterisk sh -c 'wc -l < /var/log/asterisk/full' 2>/dev/null | tr -d '\r ')"

PAYLOAD='{"command":"dial","params":"1001"}'
LEN=${#PAYLOAD}
# ctrl_tcp keeps the connection open streaming RTCP stats every ~2s once
# established -- nc's -w is an IDLE timeout, so continuous traffic would
# keep resetting it and the read would never return. `timeout` forces a
# hard cutoff regardless of ongoing activity.
EVENTS="$(docker run --rm --network "$NETWORK_NAME" "$BARESIP_IMAGE" sh -c \
    "printf '%s:%s,' '$LEN' '$PAYLOAD' | timeout 10 nc senma-callsmoke-1000 4444" 2>&1)"

if echo "$EVENTS" | grep -q '"response":true,"ok":true'; then
    ok "call placed" "dial command accepted by endpoint 1000"
else
    bad "call placed" "ctrl_tcp dial command was not accepted: $EVENTS"
fi

if echo "$EVENTS" | grep -q '"type":"CALL_RINGING"'; then
    ok "destination receives call" "CALL_RINGING event observed"
else
    bad "destination receives call" "no CALL_RINGING event observed"
fi

if echo "$EVENTS" | grep -q '"type":"CALL_ANSWERED"'; then
    ok "destination answers" "CALL_ANSWERED event observed (endpoint 1001 answermode=auto)"
else
    bad "destination answers" "no CALL_ANSWERED event observed"
fi

if echo "$EVENTS" | grep -q '"type":"CALL_ESTABLISHED"'; then
    ok "call remains established" "CALL_ESTABLISHED event observed"
else
    bad "call remains established" "no CALL_ESTABLISHED event observed"
fi

sleep 2

# --- 10. Hangup -------------------------------------------------------------

log "==> hangup"
$COMPOSE exec -T asterisk asterisk -rx "channel request hangup all" >&2
sleep 2
REMAINING="$($COMPOSE exec -T asterisk asterisk -rx 'core show channels' 2>&1)"
if echo "$REMAINING" | grep -q "^0 active channels"; then
    ok "hangup succeeds" "0 active channels after hangup"
else
    bad "hangup succeeds" "channels still active after hangup request"
fi

# --- 11. AGI/rule path was exercised ---------------------------------------

log "==> checking AGI/rule engine trace"
AGI_TRACE="$($COMPOSE exec -T asterisk sh -c "tail -n +$((LOG_MARK_BEFORE+1)) /var/log/asterisk/full" 2>/dev/null)"
if echo "$AGI_TRACE" | grep -q "Running the rule .*:Internas - Ramal para Ramal" \
    && echo "$AGI_TRACE" | grep -q "Discando para ramal 1001 no canal PJSIP/1001" \
    && echo "$AGI_TRACE" | grep -q "Launched AGI Script .*snep/snep.php"; then
    ok "AGI/rule path was exercised" "snep.php ran, matched the seeded rule, dialed PJSIP/1001 (not a bypassed test-only Dial)"
else
    bad "AGI/rule path was exercised" "expected AGI/rule engine trace not found in Asterisk's log for this call"
fi

# --- 12. CDR row exists and is correct -------------------------------------

log "==> checking CDR"
CDR_ROW="$(db_query "SELECT uniqueid,disposition,duration,billsec,channel,dstchannel,calldate FROM cdr WHERE src='1000' AND dst='1001' ORDER BY calldate DESC, uniqueid DESC LIMIT 1;")"
CDR_UNIQUEID="$(echo "$CDR_ROW" | awk -F'\t' '{print $1}')"
CDR_DISPOSITION="$(echo "$CDR_ROW" | awk -F'\t' '{print $2}')"
CDR_DURATION="$(echo "$CDR_ROW" | awk -F'\t' '{print $3}')"
CDR_BILLSEC="$(echo "$CDR_ROW" | awk -F'\t' '{print $4}')"
CDR_CHANNEL="$(echo "$CDR_ROW" | awk -F'\t' '{print $5}')"
CDR_CALLDATE="$(echo "$CDR_ROW" | awk -F'\t' '{print $7}')"

if [ -n "$CDR_UNIQUEID" ] \
    && [ "$CDR_DISPOSITION" = "ANSWERED" ] \
    && [ "${CDR_DURATION:-0}" -gt 0 ] 2>/dev/null \
    && [ "${CDR_BILLSEC:-0}" -gt 0 ] 2>/dev/null \
    && [[ "$CDR_CHANNEL" == PJSIP/1000-* ]] \
    && [[ "$CDR_CALLDATE" != "0000-00-00"* ]]; then
    ok "CDR row exists and is correct" "uniqueid=$CDR_UNIQUEID disposition=ANSWERED duration=$CDR_DURATION billsec=$CDR_BILLSEC channel=$CDR_CHANNEL calldate=$CDR_CALLDATE"
else
    bad "CDR row exists and is correct" "no matching/valid CDR row found (uniqueid='$CDR_UNIQUEID' disposition='$CDR_DISPOSITION' duration='$CDR_DURATION' billsec='$CDR_BILLSEC' channel='$CDR_CHANNEL' calldate='$CDR_CALLDATE')"
fi

# --- 13. SENMA reporting path can read it -----------------------------------

log "==> checking SENMA report readback"
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${TEST_PASSWORD}');" 2>/dev/null | tr -d '\r')"
db_query "UPDATE users SET password = '${TEST_HASH}' WHERE name = '${TEST_USER}';" >&2

if [ -n "$CDR_UNIQUEID" ]; then
    # CallsReportService.php string-concatenates start_date/end_date
    # straight into "WHERE calldate >= '$start_date'" with no
    # reformatting (unlike the web UI's CallsReportController, which
    # pre-formats via Snep_Reports::fmt_date() to 'yyyy-MM-dd' before
    # building SQL) -- so this direct API caller must already send
    # calldate's own format, ISO 'YYYY-MM-DD'.
    TODAY="$($COMPOSE exec -T asterisk date +%Y-%m-%d | tr -d '\r')"
    REPORT_JSON="$(curl -sS -u "${TEST_USER}:${TEST_PASSWORD}" \
        "${BASE_URL}/modules/default/api/index.php?service=CallsReport&start_date=${TODAY}&start_hour=00:00:00&end_date=${TODAY}&end_hour=23:59:59&report_type=analytic&status_answered=1&src=1000&order_src=equal" 2>&1)"
    if echo "$REPORT_JSON" | grep -qF "\"uniqueid\":\"${CDR_UNIQUEID}\""; then
        ok "SENMA reporting path can read it" "CallsReport API endpoint returned this exact CDR (uniqueid=$CDR_UNIQUEID)"
    else
        bad "SENMA reporting path can read it" "CallsReport API did not return uniqueid=$CDR_UNIQUEID: $REPORT_JSON"
    fi
else
    bad "SENMA reporting path can read it" "skipped -- no CDR uniqueid available to look up"
fi

print_report

# --- 14. Cleanup happens via the EXIT trap ----------------------------------

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
