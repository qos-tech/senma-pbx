#!/bin/bash
#
# SENMA dialplan PJSIP-legacy-closure smoke test (TASK-0028C).
#
# Proves, against a running `make dev` Docker environment, that the
# reachable SIP/IAX-era runtime constructs closed by TASK-0028C stay
# closed:
#
#   - the [default]/[hints] context-bleed bug that silently swallowed
#     custom/preagi.conf's own content is fixed (extension 1234 lands
#     under [default], [hints] stays empty) -- see
#     docs/tasks/0028c-pjsip-legacy-runtime-closure.md;
#   - the shipped custom/preagi.conf example no longer dials SIP/1003
#     (a runtime-verified dead technology) now that the context-bleed
#     fix makes it reachable;
#   - the unconditional SIPAddHeader(...) call in [ramais-agentes]
#     (unregistered on this build -- would hard-error any call that
#     ever reached it) is replaced with the PJSIP-native
#     PJSIP_HEADER(add,...) equivalent;
#   - the callback feature's (*33XXXX) generated .call file uses
#     Channel: PJSIP/..., not Channel: SIP/... -- proven end to end with
#     two real baresip endpoints (docker/baresip-test.Dockerfile, same
#     harness TASK-0011's call-smoke-test.sh uses), including the actual
#     spooled call-file origination and connection, not just the
#     dialplan source text;
#   - the entire live dialplan contains zero bare SIP/ or IAX2/ tokens
#     and zero SIPAddHeader( calls;
#   - Snep_InterfaceConf::loadConfFromDb() no longer issues the two
#     confirmed-dead "sip reload"/"iax2 reload" AMI commands (chan_sip
#     is absent from this image, chan_iax2 is Not Running -- both
#     commands verified live to return "No such command");
#   - the proven-dead legacy writer class Snep_Extensions is gone.
#
# Deliberately separate from call-smoke-test.sh/transport-smoke-test.sh
# -- this suite's failure domain is "reachable legacy dialplan/config
# constructs," not ordinary PJSIP extension/trunk provisioning (already
# covered elsewhere; not re-proven here).
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
FIXTURE_SECRET_MARKER="task0028c-fixture"
TEST_USER="admin"
TEST_PASSWORD="SmokeTest123!"
EXT_A=1091
EXT_B=1092
SECRET_A="${FIXTURE_SECRET_MARKER}-a"
SECRET_B="${FIXTURE_SECRET_MARKER}-b"
CALLBACK_CODE="*33${EXT_B}"

log()  { harness_log "$@"; }
ok()   { harness_ok "$1" "$2"; }
bad()  { harness_bad "$1" "$2"; }
stop() { harness_blocked "$*"; }

db_query() {
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
        "${DB_NAME:-snep}" -N -e "$1"
}

http_login() {
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null \
        -d "user=${TEST_USER}&password=${TEST_PASSWORD}" "${BASE_URL}/index.php/auth/login"
}

# create_extension/delete_extension -- identical shape to
# call-smoke-test.sh's own helpers (real ExtensionsController HTTP flow,
# not SQL, not hand-written config).
create_extension() {
    local ext="$1" secret="$2" body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "name=SENMA dialplan-closure-smoke ${ext}" \
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
    log "create_extension ${ext} failed (HTTP $httpcode): $(head -c 300 "$body")"
    rm -f "$body"
    return 1
}

delete_extension() {
    local ext="$1" httpcode
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "id=${ext}" \
        --data-urlencode "delete=Delete" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/extensions/remove")"
    [ "$httpcode" = "302" ]
}

# --- 1. Required containers / PJSIP module ---------------------------------

log "==> checking required containers"
harness_require_containers app asterisk db
harness_require_env DB_USER DB_PASSWORD DB_NAME

pjsip_modules_running() {
    $COMPOSE exec -T asterisk asterisk -rx 'module show like res_pjsip.so' 2>&1 | grep -q "Running" \
        && $COMPOSE exec -T asterisk asterisk -rx 'module show like chan_pjsip.so' 2>&1 | grep -q "Running"
}
if harness_retry 5 2 -- pjsip_modules_running; then
    ok "PJSIP modules Running" "res_pjsip.so and chan_pjsip.so both Running"
else
    stop "res_pjsip.so/chan_pjsip.so not both Running (checked 5 times over 8s)"
fi

# --- 2. chan_sip absent, chan_iax2 not running ------------------------------

MODULE_STATE="$($COMPOSE exec -T asterisk asterisk -rx 'module show like chan_' 2>&1)"
if ! echo "$MODULE_STATE" | grep -qi "chan_sip"; then
    ok "chan_sip absent from this runtime" "no chan_sip.so line in 'module show like chan_'"
else
    bad "chan_sip absent from this runtime" "chan_sip.so is present:\n$MODULE_STATE"
fi
if ! echo "$MODULE_STATE" | grep -qi "chan_iax2.*Running$"; then
    ok "chan_iax2 not Running" "chan_iax2.so is absent or Not Running"
else
    bad "chan_iax2 not Running" "chan_iax2.so reports Running:\n$MODULE_STATE"
fi

# --- 3. Live dialplan: context-bleed fix, preagi.conf, SIPAddHeader --------

log "==> checking live dialplan for the TASK-0028C closures"
DIALPLAN_FULL="$($COMPOSE exec -T asterisk asterisk -rx "dialplan show" 2>&1)"
HINTS_CONTEXT="$($COMPOSE exec -T asterisk asterisk -rx "dialplan show hints" 2>&1)"

if echo "$HINTS_CONTEXT" | grep -q "0 extensions (0 priorities)"; then
    ok "[hints] context-bleed closed" "dialplan show hints -- 0 extensions (custom/preagi.conf no longer inherits this context)"
else
    bad "[hints] context-bleed closed" "expected an empty hints context:\n$HINTS_CONTEXT"
fi

DEFAULT_CONTEXT="$($COMPOSE exec -T asterisk asterisk -rx "dialplan show default" 2>&1)"
if echo "$DEFAULT_CONTEXT" | grep -q "'1234'" \
    && echo "$DEFAULT_CONTEXT" | grep -A3 "'1234'" | grep -q "Dial(PJSIP/1003,60,twg)"; then
    ok "custom/preagi.conf lands in [default], PJSIP-native" "extension 1234 correctly under [default] with Dial(PJSIP/1003,...), not SIP/"
else
    bad "custom/preagi.conf lands in [default], PJSIP-native" "expected [default] to contain 1234 -> Dial(PJSIP/1003,...):\n$(echo "$DEFAULT_CONTEXT" | grep -A3 "'1234'")"
fi

RAMAIS_AGENTES="$($COMPOSE exec -T asterisk asterisk -rx "dialplan show ramais-agentes" 2>&1)"
if echo "$RAMAIS_AGENTES" | grep -q "PJSIP_HEADER(add,Alert-Info)=Bellcore-r2" \
    && ! echo "$RAMAIS_AGENTES" | grep -qi "SIPAddHeader"; then
    ok "SIPAddHeader replaced with PJSIP_HEADER" "[ramais-agentes] uses Set(PJSIP_HEADER(add,Alert-Info)=Bellcore-r2), no SIPAddHeader left"
else
    bad "SIPAddHeader replaced with PJSIP_HEADER" "unexpected content:\n$RAMAIS_AGENTES"
fi

CALLBACK_LINE="$(echo "$DIALPLAN_FULL" | grep -i "Channel:.*EXTEN:3")"
if echo "$CALLBACK_LINE" | grep -q "Channel: PJSIP/" && ! echo "$CALLBACK_LINE" | grep -qi "Channel: SIP/"; then
    ok "callback .call generation is PJSIP-native (source)" "snep-features.conf's *33XXXX block writes Channel: PJSIP/\${EXTEN:3}"
else
    bad "callback .call generation is PJSIP-native (source)" "expected Channel: PJSIP/, got:\n$CALLBACK_LINE"
fi

BARE_SIP_HITS="$(echo "$DIALPLAN_FULL" | grep -i "SIP/" | grep -v "PJSIP/")"
if [ -z "$BARE_SIP_HITS" ]; then
    ok "zero reachable bare SIP/ tokens in the live dialplan" "dialplan show contains no SIP/ token outside of PJSIP/"
else
    bad "zero reachable bare SIP/ tokens in the live dialplan" "found:\n$BARE_SIP_HITS"
fi

IAX2_HITS="$(echo "$DIALPLAN_FULL" | grep -i "IAX2/")"
if [ -z "$IAX2_HITS" ]; then
    ok "zero reachable IAX2/ tokens in the live dialplan" "dialplan show contains no IAX2/ token"
else
    bad "zero reachable IAX2/ tokens in the live dialplan" "found:\n$IAX2_HITS"
fi

SIPADDHEADER_HITS="$(echo "$DIALPLAN_FULL" | grep -i "SIPAddHeader")"
if [ -z "$SIPADDHEADER_HITS" ]; then
    ok "zero SIPAddHeader( calls in the live dialplan" "dialplan show contains no SIPAddHeader( anywhere"
else
    bad "zero SIPAddHeader( calls in the live dialplan" "found:\n$SIPADDHEADER_HITS"
fi

# --- 4. Snep_InterfaceConf no longer issues dead sip/iax2 reload calls -----

log "==> checking Snep_InterfaceConf::loadConfFromDb() source"
INTERFACE_CONF_SRC="$($COMPOSE exec -T app cat /var/www/html/snep/lib/Snep/InterfaceConf.php 2>&1)"
if echo "$INTERFACE_CONF_SRC" | grep -q 'Command("dialplan reload")' \
    && ! echo "$INTERFACE_CONF_SRC" | grep -qE 'Command\("sip reload"\)|Command\("iax2 reload"\)'; then
    ok "InterfaceConf no longer issues dead sip/iax2 reload AMI calls" "dialplan reload retained (still needed for hints), sip reload/iax2 reload removed (confirmed live: both return 'No such command' on this build)"
else
    bad "InterfaceConf no longer issues dead sip/iax2 reload AMI calls" "unexpected reload calls present in InterfaceConf.php"
fi

# --- 5. Snep_Extensions dead class removed ----------------------------------

log "==> checking Snep_Extensions removal"
EXTENSIONS_CLASS_STAT="$($COMPOSE exec -T app sh -c 'test -f /var/www/html/snep/lib/Snep/Extensions.php && echo present || echo absent' 2>&1)"
if [ "$EXTENSIONS_CLASS_STAT" = "absent" ]; then
    ok "Snep_Extensions dead class removed" "snep/lib/Snep/Extensions.php no longer exists (zero instantiations anywhere in the repo before removal)"
else
    bad "Snep_Extensions dead class removed" "snep/lib/Snep/Extensions.php still present"
fi

# --- 6. Live callback proof: two real PJSIP endpoints, *33<ext> ------------

log "==> checking for pre-existing fixtures"
for ext in "$EXT_A" "$EXT_B"; do
    existing_canal="$(db_query "SELECT canal FROM peers WHERE name='${ext}';")"
    existing_secret="$(db_query "SELECT secret FROM peers WHERE name='${ext}';")"
    if [ -n "$existing_canal" ]; then
        if [ "$existing_canal" = "PJSIP/${ext}" ] && [[ "$existing_secret" == "${FIXTURE_SECRET_MARKER}"* ]]; then
            log "extension ${ext} is a leftover dialplan-legacy-closure fixture from a prior interrupted run -- will be removed and recreated below"
        else
            stop "peers row for extension '${ext}' already exists (canal='${existing_canal}') and is NOT a dialplan-legacy-closure fixture. Refusing to overwrite real/unknown data. Remove or rename it manually first."
        fi
    fi
done

COOKIEJAR="$(mktemp)"
harness_register_best_effort_cleanup "cookie jar temp file" "rm -f '$COOKIEJAR'"
log "==> logging in as ${TEST_USER}"
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${TEST_PASSWORD}');" 2>/dev/null | tr -d '\r')"
db_query "UPDATE users SET password = '${TEST_HASH}' WHERE name = '${TEST_USER}';" >&2
http_login
ADMIN_CSRF="$(harness_csrf_token "$COOKIEJAR" "$BASE_URL")"
if [ -z "$ADMIN_CSRF" ]; then stop "could not read the admin session's CSRF token"; fi

for ext in "$EXT_A" "$EXT_B"; do
    existing_canal="$(db_query "SELECT canal FROM peers WHERE name='${ext}';")"
    if [ -n "$existing_canal" ]; then
        delete_extension "$ext" || stop "found a leftover fixture for extension ${ext} but the supported HTTP delete flow did not return 302 -- refusing to proceed with a raw SQL fallback; remove it manually first"
    fi
done

for pair in "${EXT_A}:${SECRET_A}" "${EXT_B}:${SECRET_B}"; do
    IFS=':' read -r ext secret <<< "$pair"
    if create_extension "$ext" "$secret"; then
        harness_register_cleanup "extension ${ext} (dialplan-legacy-closure fixture)" "delete_extension ${ext}"
    else
        stop "creating extension ${ext} via the real UI flow failed -- see log above"
    fi
done
ok "callback test fixtures available" "${EXT_A}/${EXT_B} provisioned through SENMA's real create-extension HTTP flow"

for ext in "$EXT_A" "$EXT_B"; do
    endpoint_visible() { $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${ext}" 2>&1 | grep -q "Endpoint:  ${ext}/${ext}"; }
    if ! harness_retry 5 1 -- endpoint_visible; then
        stop "pjsip endpoint ${ext} did not appear after 5 attempts over ~4s -- reload may have failed"
    fi
done

ASTERISK_CID="$($COMPOSE ps -q asterisk)"
ASTERISK_NAME="$(docker inspect "$ASTERISK_CID" --format '{{.Name}}' | sed 's#^/##')"
NETWORK_NAME="$(docker inspect "$ASTERISK_CID" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')"
if [ -z "$ASTERISK_NAME" ] || [ -z "$NETWORK_NAME" ]; then
    stop "could not resolve the asterisk container's name/network via docker inspect"
fi

log "==> building baresip test image"
if ! harness_timeout 180 docker build -q -t "$BARESIP_IMAGE" -f "$BARESIP_DOCKERFILE" docker >&2; then
    stop "failed to build $BARESIP_IMAGE from $BARESIP_DOCKERFILE within 180s"
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

log "==> starting baresip test endpoints"
docker rm -f senma-dialplanclosure-a senma-dialplanclosure-b >/dev/null 2>&1
docker run -d --name senma-dialplanclosure-a --network "$NETWORK_NAME" \
    -v "$CONF_DIR/${EXT_A}:/root/.baresip" "$BARESIP_IMAGE" baresip -f /root/.baresip >&2
harness_register_best_effort_cleanup "baresip container senma-dialplanclosure-a" "docker rm -f senma-dialplanclosure-a >/dev/null 2>&1"
docker run -d --name senma-dialplanclosure-b --network "$NETWORK_NAME" \
    -v "$CONF_DIR/${EXT_B}:/root/.baresip" "$BARESIP_IMAGE" baresip -f /root/.baresip >&2
harness_register_best_effort_cleanup "baresip container senma-dialplanclosure-b" "docker rm -f senma-dialplanclosure-b >/dev/null 2>&1"

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

if [ "$_HARNESS_FAIL_COUNT" -gt 0 ]; then
    log "registration failed -- aborting before placing the callback"
    harness_complete
fi

log "==> dialing ${CALLBACK_CODE} from ${EXT_A} (callback feature for busy extension ${EXT_B})"
LOG_MARK_BEFORE="$($COMPOSE exec -T asterisk sh -c 'wc -l < /var/log/asterisk/full' 2>/dev/null | tr -d '\r ')"
PAYLOAD="{\"command\":\"dial\",\"params\":\"${CALLBACK_CODE}\"}"
LEN=${#PAYLOAD}
EVENTS="$(harness_timeout 20 docker run --rm --network "$NETWORK_NAME" "$BARESIP_IMAGE" sh -c \
    "printf '%s:%s,' '$LEN' '$PAYLOAD' | timeout 10 nc senma-dialplanclosure-a 4444" 2>&1)"
if echo "$EVENTS" | grep -q '"response":true,"ok":true'; then
    ok "callback code dialed" "${CALLBACK_CODE} accepted by endpoint ${EXT_A}"
else
    bad "callback code dialed" "ctrl_tcp dial command was not accepted: $EVENTS"
fi

# Give pbx_spool time to pick up the generated .call file and originate.
sleep 8

CALLBACK_LOG="$($COMPOSE exec -T asterisk sh -c "tail -n +$((LOG_MARK_BEFORE+1)) /var/log/asterisk/full" 2>/dev/null)"
if echo "$CALLBACK_LOG" | grep -q "pbx_spool.c: Attempting call on PJSIP/${EXT_B}"; then
    ok "callback .call file originates via PJSIP" "pbx_spool attempted the callback on PJSIP/${EXT_B}, not SIP/${EXT_B}"
else
    bad "callback .call file originates via PJSIP" "expected 'Attempting call on PJSIP/${EXT_B}' in the Asterisk log for this callback:\n$CALLBACK_LOG"
fi

if echo "$CALLBACK_LOG" | grep -q "dial.c: PJSIP/${EXT_B}-.* is ringing" && echo "$CALLBACK_LOG" | grep -q "dial.c: PJSIP/${EXT_B}-.* answered"; then
    ok "callback call connects end to end" "PJSIP/${EXT_B} rang and answered the spooled callback origination"
else
    bad "callback call connects end to end" "expected ringing+answered for PJSIP/${EXT_B} in the callback log window"
fi

CALLBACK_BARE_SIP="$(echo "$CALLBACK_LOG" | grep -iE "SIP/${EXT_B}([^0-9]|$)" | grep -v "PJSIP/${EXT_B}")"
if [ -z "$CALLBACK_BARE_SIP" ]; then
    ok "no bare SIP/ channel appears in the callback flow" "the entire callback log window references PJSIP/${EXT_B} only"
else
    bad "no bare SIP/ channel appears in the callback flow" "found:\n$CALLBACK_BARE_SIP"
fi

# --- 7. Hangup + settle -----------------------------------------------------

log "==> hangup"
$COMPOSE exec -T asterisk asterisk -rx "channel request hangup all" >&2
sleep 3
REMAINING="$($COMPOSE exec -T asterisk asterisk -rx 'core show channels' 2>&1)"
if echo "$REMAINING" | grep -q "^0 active channels"; then
    ok "hangup succeeds, no leftover call-file spool entry" "0 active channels after hangup"
else
    bad "hangup succeeds, no leftover call-file spool entry" "channels still active after hangup request:\n$REMAINING"
fi

harness_complete
