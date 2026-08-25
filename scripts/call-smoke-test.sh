#!/bin/bash
#
# SENMA-provisioned PJSIP extension call smoke test (TASK-0011).
#
# Proves, end to end, against a running `make dev` Docker environment,
# using SENMA's own application flow (not direct SQL, not hand-written
# PJSIP config, not permanent seed data):
#
#   HTTP POST to ExtensionsController::addAction() (technology=pjsip)
#   -> peers row persisted -> Snep_PjsipConf::loadConfFromDb() generates
#   endpoint/auth/aor -> module reload res_pjsip.so
#   -> PJSIP/1002 -> existing extensions.conf -> existing SENMA AGI
#   (snep/snep.php) -> existing PBX_Rules/PBX_Dialplan rule engine ->
#   PBX_Rule_Action_DiscarRamal -> PBX_Asterisk_Interface_PJSIP ->
#   Dial(PJSIP/1003) -> answered call -> real cdr_adaptive_odbc CDR row ->
#   existing SENMA report endpoint reads it back
#   -> HTTP POST to ExtensionsController::removeAction() cleans up.
#
# Fixtures are created/deleted through the real authenticated HTTP
# controller flow -- the highest-level stable interface available. There
# is no write-capable internal API for extensions (only read-only
# services like CallsReport exist under modules/default/api/), and going
# through the manager/service layer directly would prove the generator
# can render *a* row, not that the actual user-facing create/edit/delete
# flow -- the thing TASK-0011 exists to prove -- works end to end. See
# docs/tasks/0011-pjsip-extension-provisioning.md.
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
FIXTURE_SECRET_MARKER="task0011-fixture"
TEST_USER="admin"
TEST_PASSWORD="SmokeTest123!"
EXT_A=1002
EXT_B=1003
SECRET_A="${FIXTURE_SECRET_MARKER}-a"
SECRET_B="${FIXTURE_SECRET_MARKER}-b"

PASS=0
FAIL=0
declare -a RESULTS=()
CREATED_A=0
CREATED_B=0
CONF_DIR=""
COOKIEJAR=""

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
# already occupying 1002/1003). Distinct from `bad()` -- this is not a
# checklist item failing, it's refusing to proceed at all.
stop() {
    log "STOP: $*"
    echo "STOP: $*"
    cleanup
    exit 1
}

db_query() {
    # stderr deliberately NOT redirected to /dev/null -- flows through to
    # this script's own stderr and is excluded from $(db_query ...)
    # capture by normal command-substitution semantics. A silenced SQL
    # error here would otherwise read back as "" with no visible cause.
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
        "${DB_NAME:-snep}" -N -e "$1"
}

http_login() {
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null \
        -d "user=${TEST_USER}&password=${TEST_PASSWORD}" "${BASE_URL}/index.php/auth/login"
}

# create_extension <ext> <secret> -- POSTs to the real
# ExtensionsController::addAction(), technology=pjsip, exactly matching
# what the real browser form submits (see snep/modules/default/views/
# scripts/extensions/addedit.phtml + ExtensionsController::execAdd()).
create_extension() {
    local ext="$1" secret="$2" body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "name=SENMA call-smoke ${ext}" \
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
        "${BASE_URL}/index.php/default/extensions/add")"
    if [ "$httpcode" = "302" ]; then
        rm -f "$body"
        return 0
    fi
    log "create_extension ${ext} failed (HTTP $httpcode): $(grep -o 'Server Message[^<]*' "$body" || head -c 300 "$body")"
    rm -f "$body"
    return 1
}

# delete_extension <ext> -- POSTs to the real
# ExtensionsController::removeAction(), matching remove.phtml's form.
delete_extension() {
    local ext="$1" httpcode
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "id=${ext}" \
        --data-urlencode "delete=Delete" \
        "${BASE_URL}/index.php/default/extensions/remove")"
    [ "$httpcode" = "302" ]
}

cleanup() {
    trap - EXIT
    log "==> cleanup"
    docker rm -f senma-callsmoke-1002 senma-callsmoke-1003 >/dev/null 2>&1
    [ -n "$CONF_DIR" ] && rm -rf "$CONF_DIR"
    if [ -n "$COOKIEJAR" ]; then
        if [ "$CREATED_A" = "1" ]; then
            delete_extension "$EXT_A" && log "removed test fixture extension ${EXT_A} via HTTP" \
                || log "WARNING: HTTP delete of ${EXT_A} did not return 302 -- may need manual cleanup"
        fi
        if [ "$CREATED_B" = "1" ]; then
            delete_extension "$EXT_B" && log "removed test fixture extension ${EXT_B} via HTTP" \
                || log "WARNING: HTTP delete of ${EXT_B} did not return 302 -- may need manual cleanup"
        fi
        rm -f "$COOKIEJAR"
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

# --- 3. Log in, check for collisions, provision via the real UI -----------

COOKIEJAR="$(mktemp)"
log "==> logging in as ${TEST_USER}"
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${TEST_PASSWORD}');" 2>/dev/null | tr -d '\r')"
db_query "UPDATE users SET password = '${TEST_HASH}' WHERE name = '${TEST_USER}';" >&2
http_login

log "==> checking for pre-existing rows / provisioning ${EXT_A}, ${EXT_B} via the real UI"
for pair in "${EXT_A}:${SECRET_A}:CREATED_A" "${EXT_B}:${SECRET_B}:CREATED_B"; do
    IFS=':' read -r ext secret flagvar <<< "$pair"
    existing_canal="$(db_query "SELECT canal FROM peers WHERE name='${ext}';")"
    existing_secret="$(db_query "SELECT secret FROM peers WHERE name='${ext}';")"
    if [ -n "$existing_canal" ]; then
        if [ "$existing_canal" = "PJSIP/${ext}" ] && [[ "$existing_secret" == "${FIXTURE_SECRET_MARKER}"* ]]; then
            log "extension ${ext} is a leftover call-smoke fixture from a prior run -- removing via HTTP before re-creating"
            delete_extension "$ext" || stop "found a leftover call-smoke fixture for ${ext} but the HTTP delete flow did not return 302 -- refusing to proceed with a raw SQL fallback"
        else
            stop "peers row for extension '${ext}' already exists (canal='${existing_canal}') and is NOT a call-smoke fixture. Refusing to overwrite real/unknown data. Remove or rename it manually, or use a different test range, before running make call-smoke."
        fi
    fi
    if create_extension "$ext" "$secret"; then
        printf -v "$flagvar" '1'
        log "provisioned extension ${ext} via the real ExtensionsController::addAction() HTTP flow"
    else
        stop "creating extension ${ext} via the real UI flow failed -- see log above"
    fi
done
ok "test fixtures available" "${EXT_A}/${EXT_B} provisioned through SENMA's real create-extension HTTP flow (not SQL, not hand-written config)"

# --- 3b. Generated config + Asterisk runtime reflect the new endpoints ----

log "==> checking generated PJSIP config and Asterisk runtime state"
GENERATED_CONF="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip.conf 2>/dev/null)"
if echo "$GENERATED_CONF" | grep -q "^\[${EXT_A}\]" \
    && echo "$GENERATED_CONF" | grep -q "^\[${EXT_A}-auth\]" \
    && echo "$GENERATED_CONF" | grep -q "^\[${EXT_B}\]" \
    && echo "$GENERATED_CONF" | grep -q "^\[${EXT_B}-auth\]"; then
    ok "generated endpoint/auth/aor sections exist" "senma-pjsip.conf contains [${EXT_A}], [${EXT_A}-auth], [${EXT_B}], [${EXT_B}-auth]"
else
    bad "generated endpoint/auth/aor sections exist" "expected sections not found in senma-pjsip.conf"
fi

for ext in "$EXT_A" "$EXT_B"; do
    if $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${ext}" 2>&1 | grep -q "Endpoint:  ${ext}/${ext}"; then
        ok "pjsip show endpoint ${ext}" "endpoint exists in the live Asterisk PJSIP config (reload succeeded)"
    else
        bad "pjsip show endpoint ${ext}" "endpoint not found -- reload may have failed"
    fi
    if $COMPOSE exec -T asterisk asterisk -rx "pjsip show aor ${ext}" 2>&1 | grep -q "Aor:  *${ext}"; then
        ok "pjsip show aor ${ext}" "aor exists in the live Asterisk PJSIP config"
    else
        bad "pjsip show aor ${ext}" "aor not found -- reload may have failed"
    fi
done

if [ "$FAIL" -gt 0 ]; then
    log "provisioning/reload verification failed -- aborting before registration"
    print_report
    exit 1
fi

# --- Build baresip test image, generate per-instance config --------------

log "==> building baresip test image"
if ! docker build -q -t "$BARESIP_IMAGE" -f "$BARESIP_DOCKERFILE" docker >&2; then
    stop "failed to build $BARESIP_IMAGE from $BARESIP_DOCKERFILE"
fi

CONF_DIR="$(mktemp -d)"
for pair in "${EXT_A}:${SECRET_A}:manual" "${EXT_B}:${SECRET_B}:auto"; do
    IFS=':' read -r ext secret answermode <<< "$pair"
    mkdir -p "$CONF_DIR/$ext"
    cp "$TEMPLATE_DIR/config.template" "$CONF_DIR/$ext/config"
    sed \
        -e "s|__EXTEN__|${ext}|g" \
        -e "s|__ASTERISK_HOST__|${ASTERISK_NAME}|g" \
        -e "s|__SECRET__|${secret}|g" \
        -e "s|__ANSWERMODE__|${answermode}|g" \
        "$TEMPLATE_DIR/accounts.template" > "$CONF_DIR/$ext/accounts"
done

# --- 4/5. Start both endpoints, wait for registration ----------------------

log "==> starting baresip test endpoints"
docker run -d --name senma-callsmoke-1002 --network "$NETWORK_NAME" \
    -v "$CONF_DIR/${EXT_A}:/root/.baresip" "$BARESIP_IMAGE" baresip -f /root/.baresip >&2
docker run -d --name senma-callsmoke-1003 --network "$NETWORK_NAME" \
    -v "$CONF_DIR/${EXT_B}:/root/.baresip" "$BARESIP_IMAGE" baresip -f /root/.baresip >&2

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

if wait_registered "$EXT_A"; then
    ok "endpoint ${EXT_A} registered" "contact bound to AOR ${EXT_A} within 15s"
else
    bad "endpoint ${EXT_A} registered" "no contact bound within 15s"
fi

if wait_registered "$EXT_B"; then
    ok "endpoint ${EXT_B} registered" "contact bound to AOR ${EXT_B} within 15s"
else
    bad "endpoint ${EXT_B} registered" "no contact bound within 15s"
fi

if [ "$FAIL" -gt 0 ]; then
    log "registration failed -- aborting before placing a call"
    print_report
    exit 1
fi

# --- 6-9. Place the call, verify ringing/answered/established -------------

log "==> placing call: ${EXT_A} -> ${EXT_B}"
LOG_MARK_BEFORE="$($COMPOSE exec -T asterisk sh -c 'wc -l < /var/log/asterisk/full' 2>/dev/null | tr -d '\r ')"

PAYLOAD="{\"command\":\"dial\",\"params\":\"${EXT_B}\"}"
LEN=${#PAYLOAD}
# ctrl_tcp keeps the connection open streaming RTCP stats every ~2s once
# established -- nc's -w is an IDLE timeout, so continuous traffic would
# keep resetting it and the read would never return. `timeout` forces a
# hard cutoff regardless of ongoing activity.
EVENTS="$(docker run --rm --network "$NETWORK_NAME" "$BARESIP_IMAGE" sh -c \
    "printf '%s:%s,' '$LEN' '$PAYLOAD' | timeout 10 nc senma-callsmoke-1002 4444" 2>&1)"

if echo "$EVENTS" | grep -q '"response":true,"ok":true'; then
    ok "call placed" "dial command accepted by endpoint ${EXT_A}"
else
    bad "call placed" "ctrl_tcp dial command was not accepted: $EVENTS"
fi

if echo "$EVENTS" | grep -q '"type":"CALL_RINGING"'; then
    ok "destination receives call" "CALL_RINGING event observed"
else
    bad "destination receives call" "no CALL_RINGING event observed"
fi

if echo "$EVENTS" | grep -q '"type":"CALL_ANSWERED"'; then
    ok "destination answers" "CALL_ANSWERED event observed (endpoint ${EXT_B} answermode=auto)"
else
    bad "destination answers" "no CALL_ANSWERED event observed"
fi

if echo "$EVENTS" | grep -q '"type":"CALL_ESTABLISHED"'; then
    ok "call remains established" "CALL_ESTABLISHED event observed"
else
    bad "call remains established" "no CALL_ESTABLISHED event observed"
fi

# Let the bridge fully settle before hanging up -- hanging up too soon
# after CALL_ESTABLISHED raced with the dialplan's own DIALSTATUS read
# during TASK-0011 validation (channel torn down before snep.php's AGI
# GET VARIABLE call landed).
sleep 5

# --- 10. Hangup -------------------------------------------------------------

log "==> hangup"
$COMPOSE exec -T asterisk asterisk -rx "channel request hangup all" >&2
sleep 3
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
    && echo "$AGI_TRACE" | grep -q "Discando para ramal ${EXT_B} no canal PJSIP/${EXT_B}" \
    && echo "$AGI_TRACE" | grep -q "Launched AGI Script .*snep/snep.php"; then
    ok "AGI/rule path was exercised" "snep.php ran, matched the seeded rule, dialed PJSIP/${EXT_B} (not a bypassed test-only Dial)"
else
    bad "AGI/rule path was exercised" "expected AGI/rule engine trace not found in Asterisk's log for this call"
fi

# --- 12. CDR row exists and is correct -------------------------------------

log "==> checking CDR"
CDR_ROW="$(db_query "SELECT uniqueid,disposition,duration,billsec,channel,dstchannel,calldate FROM cdr WHERE src='${EXT_A}' AND dst='${EXT_B}' ORDER BY calldate DESC, uniqueid DESC LIMIT 1;")"
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
    && [[ "$CDR_CHANNEL" == PJSIP/${EXT_A}-* ]] \
    && [[ "$CDR_CALLDATE" != "0000-00-00"* ]]; then
    ok "CDR row exists and is correct" "uniqueid=$CDR_UNIQUEID disposition=ANSWERED duration=$CDR_DURATION billsec=$CDR_BILLSEC channel=$CDR_CHANNEL calldate=$CDR_CALLDATE"
else
    bad "CDR row exists and is correct" "no matching/valid CDR row found (uniqueid='$CDR_UNIQUEID' disposition='$CDR_DISPOSITION' duration='$CDR_DURATION' billsec='$CDR_BILLSEC' channel='$CDR_CHANNEL' calldate='$CDR_CALLDATE')"
fi

# --- 13. SENMA reporting path can read it -----------------------------------

log "==> checking SENMA report readback"
if [ -n "$CDR_UNIQUEID" ]; then
    # CallsReportService.php string-concatenates start_date/end_date
    # straight into "WHERE calldate >= '$start_date'" with no
    # reformatting (unlike the web UI's CallsReportController, which
    # pre-formats via Snep_Reports::fmt_date() to 'yyyy-MM-dd' first) --
    # so this direct API caller must already send calldate's own format,
    # ISO 'YYYY-MM-DD'.
    TODAY="$($COMPOSE exec -T asterisk date +%Y-%m-%d | tr -d '\r')"
    REPORT_JSON="$(curl -sS -u "${TEST_USER}:${TEST_PASSWORD}" \
        "${BASE_URL}/modules/default/api/index.php?service=CallsReport&start_date=${TODAY}&start_hour=00:00:00&end_date=${TODAY}&end_hour=23:59:59&report_type=analytic&status_answered=1&src=${EXT_A}&order_src=equal" 2>&1)"
    if echo "$REPORT_JSON" | grep -qF "\"uniqueid\":\"${CDR_UNIQUEID}\""; then
        ok "SENMA reporting path can read it" "CallsReport API endpoint returned this exact CDR (uniqueid=$CDR_UNIQUEID)"
    else
        bad "SENMA reporting path can read it" "CallsReport API did not return uniqueid=$CDR_UNIQUEID: $REPORT_JSON"
    fi
else
    bad "SENMA reporting path can read it" "skipped -- no CDR uniqueid available to look up"
fi

print_report

# --- 14. Cleanup happens via the EXIT trap (HTTP delete of both fixtures,
#         then a fresh Snep_PjsipConf regeneration naturally omits them) --

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
