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
# TASK-0027: rebuilt on scripts/lib/harness.sh for deterministic
# PASS/FAIL/BLOCKED/INCONCLUSIVE classification, dependency-ordered
# (LIFO) cleanup registered immediately after each fixture is created,
# and signal-safe finalization -- see
# docs/tasks/0027-regression-harness-reliability.md. TASK-0027's own
# investigation ran this exact script live end to end (29s, clean PASS,
# full summary) and did not reproduce TASK-0026A's "runner disconnected
# after hangup" observation; that was very likely the invoking session/
# tool disconnecting, not a logic defect in this script. The bounded
# `timeout` wrappers and signal traps below are still added as
# defense-in-depth so an interrupted run always finalizes.
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
FIXTURE_SECRET_MARKER="task0011-fixture"
TEST_USER="admin"
TEST_PASSWORD="SmokeTest123!"
EXT_A=1002
EXT_B=1003
SECRET_A="${FIXTURE_SECRET_MARKER}-a"
SECRET_B="${FIXTURE_SECRET_MARKER}-b"

CONF_DIR=""
COOKIEJAR=""

log() { harness_log "$@"; }

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
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
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
log "asterisk container: $ASTERISK_NAME  network: $NETWORK_NAME"

# --- 2. Asterisk PJSIP modules Running ------------------------------------

log "==> checking PJSIP module state"
pjsip_modules_running() {
    $COMPOSE exec -T asterisk asterisk -rx 'module show like res_pjsip.so' 2>&1 | grep -q "Running" \
        && $COMPOSE exec -T asterisk asterisk -rx 'module show like chan_pjsip.so' 2>&1 | grep -q "Running"
}
# TASK-0027 finding: see transport-smoke-test.sh's identical comment --
# a fresh `docker compose exec` can transiently see incomplete module
# state immediately after a DIFFERENT suite's own PJSIP reload.
if harness_retry 5 2 -- pjsip_modules_running; then
    harness_ok "PJSIP modules Running" "res_pjsip.so and chan_pjsip.so both Running"
else
    harness_blocked "res_pjsip.so/chan_pjsip.so not both Running (checked 5 times over 8s)"
fi

# --- 3. Log in, check for collisions, provision via the real UI -----------

COOKIEJAR="$(mktemp)"
harness_register_best_effort_cleanup "cookie jar temp file" "rm -f '$COOKIEJAR'"
log "==> logging in as ${TEST_USER}"
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${TEST_PASSWORD}');" 2>/dev/null | tr -d '\r')"
if [ -z "$TEST_HASH" ]; then
    harness_blocked "could not compute the ${TEST_USER} password hash via the app container"
fi
db_query "UPDATE users SET password = '${TEST_HASH}' WHERE name = '${TEST_USER}';" >&2
http_login
# TASK-0026G: create_extension()/delete_extension() below now need a valid
# snep_csrf_token (Snep_CsrfPlugin) on every POST -- fetched once, reused
# for the rest of this script's run (stable per-session value, not
# one-shot/rotating).
ADMIN_CSRF="$(harness_csrf_token "$COOKIEJAR" "$BASE_URL")"
if [ -z "$ADMIN_CSRF" ]; then harness_blocked "could not read the admin session's CSRF token"; fi

log "==> checking for pre-existing rows / provisioning ${EXT_A}, ${EXT_B} via the real UI"
for pair in "${EXT_A}:${SECRET_A}" "${EXT_B}:${SECRET_B}"; do
    IFS=':' read -r ext secret <<< "$pair"
    existing_canal="$(db_query "SELECT canal FROM peers WHERE name='${ext}';")"
    existing_secret="$(db_query "SELECT secret FROM peers WHERE name='${ext}';")"
    if [ -n "$existing_canal" ]; then
        if [ "$existing_canal" = "PJSIP/${ext}" ] && [[ "$existing_secret" == "${FIXTURE_SECRET_MARKER}"* ]]; then
            log "extension ${ext} is a leftover call-smoke fixture from a prior interrupted run -- removing via the supported HTTP delete flow before re-creating"
            delete_extension "$ext" || harness_blocked "found a leftover call-smoke fixture for extension ${ext} but the supported HTTP delete flow did not return 302 -- refusing to proceed with a raw SQL fallback; remove it manually first"
        else
            harness_blocked "peers row for extension '${ext}' already exists (canal='${existing_canal}') and is NOT a call-smoke fixture. Refusing to overwrite real/unknown data. Remove or rename it manually, or use a different test range, before running make call-smoke."
        fi
    fi
    if create_extension "$ext" "$secret"; then
        harness_register_cleanup "extension ${ext} (call-smoke fixture)" "delete_extension ${ext}"
        log "provisioned extension ${ext} via the real ExtensionsController::addAction() HTTP flow"
    else
        harness_blocked "creating extension ${ext} via the real UI flow failed -- see log above"
    fi
done
harness_ok "test fixtures available" "${EXT_A}/${EXT_B} provisioned through SENMA's real create-extension HTTP flow (not SQL, not hand-written config)"

# --- 3b. Generated config + Asterisk runtime reflect the new endpoints ----

log "==> checking generated PJSIP config and Asterisk runtime state"
GENERATED_CONF="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip.conf 2>/dev/null)"
if echo "$GENERATED_CONF" | grep -q "^\[${EXT_A}\]" \
    && echo "$GENERATED_CONF" | grep -q "^\[${EXT_A}-auth\]" \
    && echo "$GENERATED_CONF" | grep -q "^\[${EXT_B}\]" \
    && echo "$GENERATED_CONF" | grep -q "^\[${EXT_B}-auth\]"; then
    harness_ok "generated endpoint/auth/aor sections exist" "senma-pjsip.conf contains [${EXT_A}], [${EXT_A}-auth], [${EXT_B}], [${EXT_B}-auth]"
else
    harness_bad "generated endpoint/auth/aor sections exist" "expected sections not found in senma-pjsip.conf"
fi

# TASK-0027 finding: `make regression`'s second consecutive run hit a
# genuine, reproducible propagation window -- "pjsip show endpoint 1003"
# transiently reported "not found" immediately after the reload, while
# "pjsip show aor 1003" (checked moments later, same reload) already
# succeeded. A PJSIP module reload is not atomic from the perspective of
# a query issued via a freshly-spawned `docker compose exec`; a short
# bounded retry absorbs this without weakening the assertion (a
# genuinely failed reload still fails after 5 attempts).
for ext in "$EXT_A" "$EXT_B"; do
    endpoint_visible() { $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${ext}" 2>&1 | grep -q "Endpoint:  ${ext}/${ext}"; }
    if harness_retry 5 1 -- endpoint_visible; then
        harness_ok "pjsip show endpoint ${ext}" "endpoint exists in the live Asterisk PJSIP config (reload succeeded)"
    else
        harness_bad "pjsip show endpoint ${ext}" "endpoint not found after 5 attempts over ~4s -- reload may have failed"
    fi
    aor_visible() { $COMPOSE exec -T asterisk asterisk -rx "pjsip show aor ${ext}" 2>&1 | grep -q "Aor:  *${ext}"; }
    if harness_retry 5 1 -- aor_visible; then
        harness_ok "pjsip show aor ${ext}" "aor exists in the live Asterisk PJSIP config"
    else
        harness_bad "pjsip show aor ${ext}" "aor not found after 5 attempts over ~4s -- reload may have failed"
    fi
done

if [ "$_HARNESS_FAIL_COUNT" -gt 0 ]; then
    log "provisioning/reload verification failed -- aborting before registration"
    harness_complete
fi

# --- Build baresip test image, generate per-instance config --------------

log "==> building baresip test image"
if ! harness_timeout 180 docker build -q -t "$BARESIP_IMAGE" -f "$BARESIP_DOCKERFILE" docker >&2; then
    harness_blocked "failed to build $BARESIP_IMAGE from $BARESIP_DOCKERFILE within 180s"
fi

CONF_DIR="$(mktemp -d)"
harness_register_best_effort_cleanup "baresip config temp dir" "rm -rf '$CONF_DIR'"
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
docker rm -f senma-callsmoke-1002 senma-callsmoke-1003 >/dev/null 2>&1
docker run -d --name senma-callsmoke-1002 --network "$NETWORK_NAME" \
    -v "$CONF_DIR/${EXT_A}:/root/.baresip" "$BARESIP_IMAGE" baresip -f /root/.baresip >&2
harness_register_best_effort_cleanup "baresip container senma-callsmoke-1002" "docker rm -f senma-callsmoke-1002 >/dev/null 2>&1"
docker run -d --name senma-callsmoke-1003 --network "$NETWORK_NAME" \
    -v "$CONF_DIR/${EXT_B}:/root/.baresip" "$BARESIP_IMAGE" baresip -f /root/.baresip >&2
harness_register_best_effort_cleanup "baresip container senma-callsmoke-1003" "docker rm -f senma-callsmoke-1003 >/dev/null 2>&1"

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
    harness_ok "endpoint ${EXT_A} registered" "contact bound to AOR ${EXT_A} within 15s"
else
    harness_bad "endpoint ${EXT_A} registered" "no contact bound within 15s"
fi

if wait_registered "$EXT_B"; then
    harness_ok "endpoint ${EXT_B} registered" "contact bound to AOR ${EXT_B} within 15s"
else
    harness_bad "endpoint ${EXT_B} registered" "no contact bound within 15s"
fi

if [ "$_HARNESS_FAIL_COUNT" -gt 0 ]; then
    log "registration failed -- aborting before placing a call"
    harness_complete
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
EVENTS="$(harness_timeout 20 docker run --rm --network "$NETWORK_NAME" "$BARESIP_IMAGE" sh -c \
    "printf '%s:%s,' '$LEN' '$PAYLOAD' | timeout 10 nc senma-callsmoke-1002 4444" 2>&1)"

if echo "$EVENTS" | grep -q '"response":true,"ok":true'; then
    harness_ok "call placed" "dial command accepted by endpoint ${EXT_A}"
else
    harness_bad "call placed" "ctrl_tcp dial command was not accepted: $EVENTS"
fi

if echo "$EVENTS" | grep -q '"type":"CALL_RINGING"'; then
    harness_ok "destination receives call" "CALL_RINGING event observed"
else
    harness_bad "destination receives call" "no CALL_RINGING event observed"
fi

if echo "$EVENTS" | grep -q '"type":"CALL_ANSWERED"'; then
    harness_ok "destination answers" "CALL_ANSWERED event observed (endpoint ${EXT_B} answermode=auto)"
else
    harness_bad "destination answers" "no CALL_ANSWERED event observed"
fi

if echo "$EVENTS" | grep -q '"type":"CALL_ESTABLISHED"'; then
    harness_ok "call remains established" "CALL_ESTABLISHED event observed"
else
    harness_bad "call remains established" "no CALL_ESTABLISHED event observed"
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
    harness_ok "hangup succeeds" "0 active channels after hangup"
else
    harness_bad "hangup succeeds" "channels still active after hangup request"
fi

# --- 11. AGI/rule path was exercised ---------------------------------------

log "==> checking AGI/rule engine trace"
AGI_TRACE="$($COMPOSE exec -T asterisk sh -c "tail -n +$((LOG_MARK_BEFORE+1)) /var/log/asterisk/full" 2>/dev/null)"
if echo "$AGI_TRACE" | grep -q "Running the rule .*:Internas - Ramal para Ramal" \
    && echo "$AGI_TRACE" | grep -q "Discando para ramal ${EXT_B} no canal PJSIP/${EXT_B}" \
    && echo "$AGI_TRACE" | grep -q "Launched AGI Script .*snep/snep.php"; then
    harness_ok "AGI/rule path was exercised" "snep.php ran, matched the seeded rule, dialed PJSIP/${EXT_B} (not a bypassed test-only Dial)"
else
    harness_bad "AGI/rule path was exercised" "expected AGI/rule engine trace not found in Asterisk's log for this call"
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
    harness_ok "CDR row exists and is correct" "uniqueid=$CDR_UNIQUEID disposition=ANSWERED duration=$CDR_DURATION billsec=$CDR_BILLSEC channel=$CDR_CHANNEL calldate=$CDR_CALLDATE"
else
    harness_bad "CDR row exists and is correct" "no matching/valid CDR row found (uniqueid='$CDR_UNIQUEID' disposition='$CDR_DISPOSITION' duration='$CDR_DURATION' billsec='$CDR_BILLSEC' channel='$CDR_CHANNEL' calldate='$CDR_CALLDATE')"
fi

# --- 13. SENMA reporting path can read it -----------------------------------

log "==> checking SENMA report readback"
if [ -n "$CDR_UNIQUEID" ] && harness_cdr_report_window "$CDR_CALLDATE" 5; then
    # CallsReportService.php string-concatenates start_date/end_date
    # straight into "WHERE calldate >= '$start_date'" with no
    # reformatting (unlike the web UI's CallsReportController, which
    # pre-formats via Snep_Reports::fmt_date() to 'yyyy-MM-dd' first) --
    # so this direct API caller must already send calldate's own
    # format/timezone. TASK-0027A: the window is anchored on this call's
    # own already-confirmed CDR_CALLDATE (see harness_cdr_report_window
    # in lib/harness.sh), not on "today" -- immune to any divergence
    # between the harness shell's local calendar day and whatever
    # timezone calldate is actually stored in.
    REPORT_JSON="$(curl -sS -u "${TEST_USER}:${TEST_PASSWORD}" \
        "${BASE_URL}/modules/default/api/index.php?service=CallsReport&start_date=${HARNESS_REPORT_START_DATE}&start_hour=${HARNESS_REPORT_START_HOUR}&end_date=${HARNESS_REPORT_END_DATE}&end_hour=${HARNESS_REPORT_END_HOUR}&report_type=analytic&status_answered=1&src=${EXT_A}&order_src=equal" 2>&1)"
    if echo "$REPORT_JSON" | grep -qF "\"uniqueid\":\"${CDR_UNIQUEID}\""; then
        harness_ok "SENMA reporting path can read it" "CallsReport API endpoint returned this exact CDR (uniqueid=$CDR_UNIQUEID)"
    else
        harness_bad "SENMA reporting path can read it" "CallsReport API did not return uniqueid=$CDR_UNIQUEID: $REPORT_JSON"
    fi
else
    harness_bad "SENMA reporting path can read it" "skipped -- no CDR uniqueid available, or the report window could not be computed"
fi

# --- 14. Cleanup happens via harness_complete's cleanup pass (HTTP delete
#         of both fixtures, then a fresh Snep_PjsipConf regeneration
#         naturally omits them) -------------------------------------------

harness_complete
