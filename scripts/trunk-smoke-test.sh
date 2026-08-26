#!/bin/bash
#
# SENMA-provisioned outbound PJSIP trunk call smoke test (TASK-0015).
#
# Proves, end to end, against a running `make dev` Docker environment,
# using SENMA's own application flow (not direct SQL, not hand-written
# PJSIP config, not permanent seed data), the same "register-based
# outbound trunk" model TASK-0014 recommended:
#
#   HTTP POST to TrunksController::addAction() (technology=pjsip,
#   dialmethod=normal, reverse_auth=1)
#   -> trunks + peers rows persisted
#   -> Snep_PjsipTrunkConf::loadConfFromDb() generates
#      endpoint/auth/aor/registration -> module reload res_pjsip.so
#   -> outbound REGISTER succeeds against the local "provider" simulator
#      (a second, independent Asterisk 22/PJSIP instance -- see
#      compose.yaml's "provider" service and docker/provider-config/,
#      never a real commercial carrier)
#   -> a route/rule (created via PBX_Rules' own domain API -- see
#      scripts/trunk-smoke-route.php) sends a fixed test destination
#      through DiscarTronco -> this trunk
#   -> existing extensions.conf -> existing SENMA AGI (snep/snep.php) ->
#      existing PBX_Rules/PBX_Dialplan rule engine -> DiscarTronco ->
#      PBX_Asterisk_Interface_PJSIP -> Dial(PJSIP/600@trunk-<id>) ->
#      provider simulator receives the INVITE, answers, holds briefly,
#      hangs up
#   -> real cdr_adaptive_odbc CDR row -> existing SENMA report endpoint
#      reads it back
#   -> HTTP POST to TrunksController::removeAction() cleans up.
#
# Outbound only, per TASK-0014/TASK-0015's explicit scope boundary --
# inbound trunk identification/routing is TASK-0016.
#
# Separate from scripts/smoke-test.sh (HTTP-only) and
# scripts/call-smoke-test.sh (PJSIP extensions only) by design -- this is
# trunk-specific SIP/telephony-level proof, a different failure domain.
#
# Exit code: 0 if every check PASSes; 1 if any check FAILs.

set -uo pipefail

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
BASE_URL="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
BARESIP_IMAGE="senma-baresip-test:latest"
BARESIP_DOCKERFILE="docker/baresip-test.Dockerfile"
TEMPLATE_DIR="docker/baresip-test"
ROUTE_SCRIPT="scripts/trunk-smoke-route.php"
FIXTURE_MARKER="task0015-trunk-smoke"
TEST_USER="admin"
TEST_PASSWORD="SmokeTest123!"
TEST_EXT=1099
TEST_EXT_SECRET="${FIXTURE_MARKER}-ext"
TRUNK_CALLERID="TASK-0015 trunk-smoke fixture"
ROUTE_DESC="TASK-0015 trunk-smoke route fixture"
TEST_DESTINATION=600
BARESIP_CONTAINER="senma-trunksmoke-${TEST_EXT}"

PASS=0
FAIL=0
declare -a RESULTS=()
CREATED_EXT=0
CREATED_TRUNK_ID=""
CREATED_ROUTE_ID=""
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

stop() {
    log "STOP: $*"
    echo "STOP: $*"
    cleanup
    exit 1
}

db_query() {
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
        "${DB_NAME:-snep}" -N -e "$1"
}

http_login() {
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null \
        -d "user=${TEST_USER}&password=${TEST_PASSWORD}" "${BASE_URL}/index.php/auth/login"
}

# create_extension <ext> <secret> -- same real HTTP flow as
# call-smoke-test.sh, just an independent fixture for this script.
create_extension() {
    local ext="$1" secret="$2" body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "name=SENMA trunk-smoke ${ext}" \
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

delete_extension() {
    local ext="$1" httpcode
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "id=${ext}" \
        --data-urlencode "delete=Delete" \
        "${BASE_URL}/index.php/default/extensions/remove")"
    [ "$httpcode" = "302" ]
}

# create_trunk -- POSTs to the real TrunksController::addAction(),
# technology=pjsip, dialmethod=normal, reverse_auth=1 -- exactly what the
# real browser form submits (snep/modules/default/views/scripts/trunks/
# addedit.phtml + TrunksController::preparePost()/execAdd() equivalent).
create_trunk() {
    local body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "callerid=${TRUNK_CALLERID}" \
        --data-urlencode "technology=pjsip" \
        --data-urlencode "dialmethod=normal" \
        --data-urlencode "username=${TRUNK_TEST_USERNAME}" \
        --data-urlencode "secret=${TRUNK_TEST_SECRET}" \
        --data-urlencode "host=provider" \
        --data-urlencode "fromuser=" \
        --data-urlencode "fromdomain=" \
        --data-urlencode "qualify=yes" \
        --data-urlencode "qualify_value=" \
        --data-urlencode "peer_type=friend" \
        --data-urlencode "domain=" \
        --data-urlencode "insecure=" \
        --data-urlencode "port=5060" \
        --data-urlencode "call-limit=" \
        --data-urlencode "dtmfmode=rfc2833" \
        --data-urlencode "nat_no=1" \
        --data-urlencode "codec=ulaw" \
        --data-urlencode "codec1=alaw" \
        --data-urlencode "codec2=gsm" \
        --data-urlencode "reverse_auth=reverse_auth" \
        --data-urlencode "telco=" \
        "${BASE_URL}/index.php/default/trunks/add")"
    if [ "$httpcode" = "302" ]; then
        rm -f "$body"
        return 0
    fi
    log "create_trunk failed (HTTP $httpcode): $(grep -o 'Server Message[^<]*' "$body" || head -c 300 "$body")"
    rm -f "$body"
    return 1
}

delete_trunk() {
    local id="$1" name="$2" httpcode
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "id=${id}" \
        --data-urlencode "name=${name}" \
        --data-urlencode "delete=Delete" \
        "${BASE_URL}/index.php/default/trunks/remove")"
    [ "$httpcode" = "302" ]
}

cleanup() {
    trap - EXIT
    log "==> cleanup"
    docker rm -f "$BARESIP_CONTAINER" >/dev/null 2>&1
    [ -n "$CONF_DIR" ] && rm -rf "$CONF_DIR"
    if [ -n "$CREATED_ROUTE_ID" ]; then
        $COMPOSE exec -T app php -- remove "$CREATED_ROUTE_ID" < "$ROUTE_SCRIPT" >/dev/null 2>&1 \
            && log "removed route fixture id=${CREATED_ROUTE_ID}" \
            || log "WARNING: could not remove route fixture id=${CREATED_ROUTE_ID} -- may need manual cleanup"
    fi
    if [ -n "$COOKIEJAR" ]; then
        if [ "$CREATED_EXT" = "1" ]; then
            delete_extension "$TEST_EXT" && log "removed test fixture extension ${TEST_EXT} via HTTP" \
                || log "WARNING: HTTP delete of extension ${TEST_EXT} did not return 302 -- may need manual cleanup"
        fi
        if [ -n "$CREATED_TRUNK_ID" ]; then
            delete_trunk "$CREATED_TRUNK_ID" "1" && log "removed test fixture trunk id=${CREATED_TRUNK_ID} via HTTP" \
                || log "WARNING: HTTP delete of trunk id=${CREATED_TRUNK_ID} did not return 302 -- may need manual cleanup"
        fi
        rm -f "$COOKIEJAR"
    fi
}
trap cleanup EXIT

# --- 1. Required containers healthy ---------------------------------------

log "==> checking required containers"
ALL_UP=1
for svc in app asterisk db provider; do
    if ! $COMPOSE ps "$svc" 2>/dev/null | grep -q "Up"; then
        ALL_UP=0
    fi
done
if [ "$ALL_UP" = "1" ]; then
    ok "containers healthy" "app, asterisk, db, provider all Up"
else
    bad "containers healthy" "one or more of app/asterisk/db/provider not Up -- run 'make up' first"
    cleanup
    trap - EXIT
    exit 1
fi

: "${DB_USER:?DB_USER must be set (source .env first)}"
: "${DB_PASSWORD:?DB_PASSWORD must be set (source .env first)}"
: "${DB_NAME:?DB_NAME must be set (source .env first)}"
: "${TRUNK_TEST_USERNAME:?TRUNK_TEST_USERNAME must be set (source .env first)}"
: "${TRUNK_TEST_SECRET:?TRUNK_TEST_SECRET must be set (source .env first)}"

ASTERISK_CID="$($COMPOSE ps -q asterisk)"
ASTERISK_NAME="$(docker inspect "$ASTERISK_CID" --format '{{.Name}}' | sed 's#^/##')"
NETWORK_NAME="$(docker inspect "$ASTERISK_CID" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')"
if [ -z "$ASTERISK_NAME" ] || [ -z "$NETWORK_NAME" ]; then
    stop "could not resolve the asterisk container's name/network via docker inspect"
fi
log "asterisk container: $ASTERISK_NAME  network: $NETWORK_NAME"

# --- 2. PJSIP modules Running on both asterisk and provider ---------------

log "==> checking PJSIP module state (asterisk + provider)"
MODS_OK=1
for svc in asterisk provider; do
    P="$($COMPOSE exec -T "$svc" asterisk -rx 'module show like res_pjsip.so' 2>&1)"
    C="$($COMPOSE exec -T "$svc" asterisk -rx 'module show like chan_pjsip.so' 2>&1)"
    if ! echo "$P" | grep -q "Running" || ! echo "$C" | grep -q "Running"; then
        MODS_OK=0
    fi
done
if [ "$MODS_OK" = "1" ]; then
    ok "PJSIP modules Running" "res_pjsip.so and chan_pjsip.so Running on both asterisk and provider"
else
    bad "PJSIP modules Running" "res_pjsip.so/chan_pjsip.so not both Running on both instances"
    cleanup
    trap - EXIT
    exit 1
fi

# --- 3. Log in, check for collisions, provision the trunk via the real UI -

COOKIEJAR="$(mktemp)"
log "==> logging in as ${TEST_USER}"
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${TEST_PASSWORD}');" 2>/dev/null | tr -d '\r')"
db_query "UPDATE users SET password = '${TEST_HASH}' WHERE name = '${TEST_USER}';" >&2
http_login

log "==> checking for pre-existing trunk/extension fixtures"
EXISTING_TRUNK="$(db_query "SELECT id FROM trunks WHERE callerid='${TRUNK_CALLERID}';")"
if [ -n "$EXISTING_TRUNK" ]; then
    stop "a trunk with callerid '${TRUNK_CALLERID}' already exists (id=${EXISTING_TRUNK}) from a prior run that did not clean up. Refusing to proceed with a raw SQL fallback -- remove it manually (through the UI) first."
fi
EXISTING_EXT_CANAL="$(db_query "SELECT canal FROM peers WHERE name='${TEST_EXT}';")"
EXISTING_EXT_SECRET="$(db_query "SELECT secret FROM peers WHERE name='${TEST_EXT}';")"
if [ -n "$EXISTING_EXT_CANAL" ]; then
    if [ "$EXISTING_EXT_CANAL" = "PJSIP/${TEST_EXT}" ] && [[ "$EXISTING_EXT_SECRET" == "${FIXTURE_MARKER}"* ]]; then
        log "extension ${TEST_EXT} is a leftover trunk-smoke fixture from a prior run -- removing via HTTP before re-creating"
        delete_extension "$TEST_EXT" || stop "found a leftover trunk-smoke fixture for extension ${TEST_EXT} but the HTTP delete flow did not return 302"
    else
        stop "peers row for extension '${TEST_EXT}' already exists (canal='${EXISTING_EXT_CANAL}') and is NOT a trunk-smoke fixture. Refusing to overwrite real/unknown data."
    fi
fi

log "==> provisioning trunk and extension ${TEST_EXT} via the real UI"
if create_trunk; then
    CREATED_TRUNK_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${TRUNK_CALLERID}';")"
    if [ -z "$CREATED_TRUNK_ID" ]; then
        stop "trunk creation returned 302 but no matching trunks row was found afterward"
    fi
    log "provisioned trunk id=${CREATED_TRUNK_ID} via the real TrunksController::addAction() HTTP flow"
else
    stop "creating the test trunk via the real UI flow failed -- see log above"
fi

if create_extension "$TEST_EXT" "$TEST_EXT_SECRET"; then
    CREATED_EXT=1
    log "provisioned extension ${TEST_EXT} via the real ExtensionsController::addAction() HTTP flow"
else
    stop "creating extension ${TEST_EXT} via the real UI flow failed -- see log above"
fi
ok "test fixtures available" "trunk id=${CREATED_TRUNK_ID} and extension ${TEST_EXT} provisioned through SENMA's real HTTP flows (not SQL, not hand-written config)"

TRUNK_OBJ="trunk-${CREATED_TRUNK_ID}"

# --- 4. Generated config + Asterisk runtime reflect the new trunk --------

log "==> checking generated PJSIP trunk config and Asterisk runtime state"
GENERATED_CONF="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip-trunks.conf 2>/dev/null)"
if echo "$GENERATED_CONF" | grep -q "^\[${TRUNK_OBJ}\]" \
    && echo "$GENERATED_CONF" | grep -q "^\[${TRUNK_OBJ}-auth\]" \
    && echo "$GENERATED_CONF" | grep -q "^\[${TRUNK_OBJ}-registration\]"; then
    ok "generated endpoint/auth/aor/registration sections exist" "senma-pjsip-trunks.conf contains [${TRUNK_OBJ}], [${TRUNK_OBJ}-auth], [${TRUNK_OBJ}-registration]"
else
    bad "generated endpoint/auth/aor/registration sections exist" "expected sections not found in senma-pjsip-trunks.conf"
fi

if $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${TRUNK_OBJ}" 2>&1 | grep -q "Endpoint:  ${TRUNK_OBJ}"; then
    ok "pjsip show endpoint ${TRUNK_OBJ}" "endpoint exists in the live Asterisk PJSIP config (reload succeeded)"
else
    bad "pjsip show endpoint ${TRUNK_OBJ}" "endpoint not found -- reload may have failed"
fi

if [ "$FAIL" -gt 0 ]; then
    log "provisioning/reload verification failed -- aborting before registration"
    print_report
    exit 1
fi

# --- 5. Outbound registration state (this trunk model's status check) ----

log "==> checking outbound registration state"
wait_registered_outbound() {
    local tries=15
    while [ "$tries" -gt 0 ]; do
        if $COMPOSE exec -T asterisk asterisk -rx "pjsip show registrations outbound" 2>&1 \
            | grep "${TRUNK_OBJ}-registration" | grep -q "Registered"; then
            return 0
        fi
        sleep 1
        tries=$((tries-1))
    done
    return 1
}
if wait_registered_outbound; then
    ok "outbound registration Registered" "${TRUNK_OBJ}-registration reached Registered within 15s (real REGISTER against the provider simulator)"
else
    bad "outbound registration Registered" "${TRUNK_OBJ}-registration did not reach Registered within 15s"
    cleanup
    trap - EXIT
    exit 1
fi

# --- 6. Route fixture, through PBX_Rules' own domain API ------------------

log "==> checking for a leftover route fixture from a prior interrupted run"
LEFTOVER_ROUTE_ID="$(db_query "SELECT id FROM regras_negocio WHERE \`desc\`='${ROUTE_DESC}';")"
if [ -n "$LEFTOVER_ROUTE_ID" ]; then
    log "found leftover route fixture id=${LEFTOVER_ROUTE_ID} -- removing via PBX_Rules::delete() before creating a new one"
    $COMPOSE exec -T app php -- remove "$LEFTOVER_ROUTE_ID" < "$ROUTE_SCRIPT" >&2 \
        || stop "found a leftover route fixture (id=${LEFTOVER_ROUTE_ID}) but could not remove it"
fi

log "==> creating the outbound route fixture (destination ${TEST_DESTINATION} -> trunk ${CREATED_TRUNK_ID})"
ROUTE_OUT="$($COMPOSE exec -T app php -- create "$CREATED_TRUNK_ID" "$TEST_DESTINATION" "$ROUTE_DESC" < "$ROUTE_SCRIPT" 2>&1)"
CREATED_ROUTE_ID="$(echo "$ROUTE_OUT" | grep -oE '^[0-9]+$' | tail -1)"
if [ -n "$CREATED_ROUTE_ID" ]; then
    ok "route fixture created" "rule id=${CREATED_ROUTE_ID} via PBX_Rules::register() (destino=RX:${TEST_DESTINATION} -> DiscarTronco tronco=${CREATED_TRUNK_ID})"
else
    stop "route fixture creation failed: $ROUTE_OUT"
fi

# --- 7/8. Build baresip test image, start the calling extension ----------

log "==> building baresip test image"
if ! docker build -q -t "$BARESIP_IMAGE" -f "$BARESIP_DOCKERFILE" docker >&2; then
    stop "failed to build $BARESIP_IMAGE from $BARESIP_DOCKERFILE"
fi

CONF_DIR="$(mktemp -d)"
mkdir -p "$CONF_DIR/${TEST_EXT}"
cp "$TEMPLATE_DIR/config.template" "$CONF_DIR/${TEST_EXT}/config"
sed \
    -e "s|__EXTEN__|${TEST_EXT}|g" \
    -e "s|__ASTERISK_HOST__|${ASTERISK_NAME}|g" \
    -e "s|__SECRET__|${TEST_EXT_SECRET}|g" \
    -e "s|__ANSWERMODE__|manual|g" \
    "$TEMPLATE_DIR/accounts.template" > "$CONF_DIR/${TEST_EXT}/accounts"

log "==> starting baresip test endpoint (extension ${TEST_EXT})"
docker run -d --name "$BARESIP_CONTAINER" --network "$NETWORK_NAME" \
    -v "$CONF_DIR/${TEST_EXT}:/root/.baresip" "$BARESIP_IMAGE" baresip -f /root/.baresip >&2

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
if wait_registered "$TEST_EXT"; then
    ok "test endpoint ${TEST_EXT} registered" "contact bound within 15s"
else
    bad "test endpoint ${TEST_EXT} registered" "no contact bound within 15s"
    cleanup
    trap - EXIT
    exit 1
fi

# --- 9-12. Place the outbound call, verify it reaches the provider --------

log "==> placing outbound call: ${TEST_EXT} -> ${TEST_DESTINATION} (through trunk id=${CREATED_TRUNK_ID})"
LOG_MARK_BEFORE="$($COMPOSE exec -T asterisk sh -c 'wc -l < /var/log/asterisk/full' 2>/dev/null | tr -d '\r ')"
# TASK-0015: src/dst alone (1099/600) are reused identically across runs,
# so an unscoped CDR lookup would match a PRIOR run's row instead of this
# one -- a real bug caught while proving idempotency (running trunk-smoke
# twice in a row). A wall-clock cutoff (docker exec's `date`, or even
# MariaDB's own NOW()) turned out unusable here: both read several hours
# behind the timestamps Asterisk itself writes into calldate in this
# environment (a container/DB timezone-handling difference unrelated to
# this task, not worth chasing further for a test-fixture marker).
# uniqueid (Asterisk's own <epoch>.<sequence> channel identifier) needs
# no timezone at all and is monotonically increasing call over call --
# capturing the highest one that exists before this call and requiring
# the result to be strictly greater sidesteps the clock-skew question
# entirely. cdr has no other auto-increment key to mark a "since" point
# with instead.
UNIQUEID_MARK="$(db_query "SELECT MAX(uniqueid) FROM cdr;")"
UNIQUEID_MARK="${UNIQUEID_MARK:-0}"

PAYLOAD="{\"command\":\"dial\",\"params\":\"${TEST_DESTINATION}\"}"
LEN=${#PAYLOAD}
EVENTS="$(docker run --rm --network "$NETWORK_NAME" "$BARESIP_IMAGE" sh -c \
    "printf '%s:%s,' '$LEN' '$PAYLOAD' | timeout 15 nc ${BARESIP_CONTAINER} 4444" 2>&1)"

if echo "$EVENTS" | grep -q '"response":true,"ok":true'; then
    ok "call placed" "dial command accepted by endpoint ${TEST_EXT}"
else
    bad "call placed" "ctrl_tcp dial command was not accepted: $EVENTS"
fi

if echo "$EVENTS" | grep -q '"type":"CALL_ANSWERED"'; then
    ok "provider answered" "CALL_ANSWERED event observed"
else
    bad "provider answered" "no CALL_ANSWERED event observed: $EVENTS"
fi

if echo "$EVENTS" | grep -q '"type":"CALL_ESTABLISHED"'; then
    ok "call established" "CALL_ESTABLISHED event observed"
else
    bad "call established" "no CALL_ESTABLISHED event observed"
fi

sleep 2

REMAINING="$($COMPOSE exec -T asterisk asterisk -rx 'core show channels' 2>&1)"
if echo "$REMAINING" | grep -q "^0 active channels"; then
    ok "hangup succeeded" "0 active channels after the provider's own Hangup()"
else
    bad "hangup succeeded" "channels still active"
fi

# --- 13. SENMA AGI/rule engine + trunk selection were actually exercised --

log "==> checking AGI/rule engine trace"
AGI_TRACE="$($COMPOSE exec -T asterisk sh -c "tail -n +$((LOG_MARK_BEFORE+1)) /var/log/asterisk/full" 2>/dev/null)"
if echo "$AGI_TRACE" | grep -q "Running the rule .*:${ROUTE_DESC}" \
    && echo "$AGI_TRACE" | grep -q "Dialing to ${TEST_DESTINATION} through trunk ${TRUNK_CALLERID}(PJSIP/${TEST_DESTINATION}@${TRUNK_OBJ})" \
    && echo "$AGI_TRACE" | grep -q "Launched AGI Script .*snep/snep.php"; then
    ok "AGI/rule/trunk-selection path was exercised" "snep.php ran, matched the fixture rule, DiscarTronco selected trunk id=${CREATED_TRUNK_ID}, dialed PJSIP/${TEST_DESTINATION}@${TRUNK_OBJ} (not a bypassed test-only Dial)"
else
    bad "AGI/rule/trunk-selection path was exercised" "expected AGI/rule/trunk trace not found in Asterisk's log for this call"
fi

# --- 14. CDR row exists and is correct -------------------------------------

log "==> checking CDR"
# TASK-0015 finding: a trunk call (unlike a plain extension-to-extension
# one) produces TWO cdr rows sharing one uniqueid -- the first, written
# alongside the Dial() itself (lastapp='Dial', fully populated), and a
# second, empty one written moments later when the calling channel's own
# dialplan reaches its explicit post-rule Hangup() (lastapp='Hangup',
# duration/billsec/dstchannel all blank). ORDER BY calldate DESC (the
# pattern call-smoke-test.sh uses, safe there because that duplicate never
# occurs for an internal ramal-to-ramal call) would silently pick the
# empty one here -- ASC picks the real, meaningful row. See
# docs/tasks/0015-pjsip-trunk-provisioning.md.
CDR_ROW="$(db_query "SELECT uniqueid,disposition,duration,billsec,channel,dstchannel,calldate FROM cdr WHERE src='${TEST_EXT}' AND dst='${TEST_DESTINATION}' AND uniqueid > '${UNIQUEID_MARK}' ORDER BY calldate ASC, uniqueid ASC LIMIT 1;")"
CDR_UNIQUEID="$(echo "$CDR_ROW" | awk -F'\t' '{print $1}')"
CDR_DISPOSITION="$(echo "$CDR_ROW" | awk -F'\t' '{print $2}')"
CDR_DURATION="$(echo "$CDR_ROW" | awk -F'\t' '{print $3}')"
CDR_BILLSEC="$(echo "$CDR_ROW" | awk -F'\t' '{print $4}')"
CDR_CHANNEL="$(echo "$CDR_ROW" | awk -F'\t' '{print $5}')"
CDR_DSTCHANNEL="$(echo "$CDR_ROW" | awk -F'\t' '{print $6}')"
CDR_CALLDATE="$(echo "$CDR_ROW" | awk -F'\t' '{print $7}')"

if [ -n "$CDR_UNIQUEID" ] \
    && [ "$CDR_DISPOSITION" = "ANSWERED" ] \
    && [ "${CDR_DURATION:-0}" -gt 0 ] 2>/dev/null \
    && [ "${CDR_BILLSEC:-0}" -gt 0 ] 2>/dev/null \
    && [[ "$CDR_CHANNEL" == PJSIP/${TEST_EXT}-* ]] \
    && [[ "$CDR_DSTCHANNEL" == PJSIP/${TRUNK_OBJ}-* ]] \
    && [[ "$CDR_CALLDATE" != "0000-00-00"* ]]; then
    ok "CDR row exists and is correct" "uniqueid=$CDR_UNIQUEID disposition=ANSWERED duration=$CDR_DURATION billsec=$CDR_BILLSEC channel=$CDR_CHANNEL dstchannel=$CDR_DSTCHANNEL calldate=$CDR_CALLDATE"
else
    bad "CDR row exists and is correct" "no matching/valid CDR row found (uniqueid='$CDR_UNIQUEID' disposition='$CDR_DISPOSITION' duration='$CDR_DURATION' billsec='$CDR_BILLSEC' channel='$CDR_CHANNEL' dstchannel='$CDR_DSTCHANNEL' calldate='$CDR_CALLDATE')"
fi

# --- 15. SENMA reporting path can read it -----------------------------------

log "==> checking SENMA report readback"
if [ -n "$CDR_UNIQUEID" ]; then
    TODAY="$($COMPOSE exec -T asterisk date +%Y-%m-%d | tr -d '\r')"
    REPORT_JSON="$(curl -sS -u "${TEST_USER}:${TEST_PASSWORD}" \
        "${BASE_URL}/modules/default/api/index.php?service=CallsReport&start_date=${TODAY}&start_hour=00:00:00&end_date=${TODAY}&end_hour=23:59:59&report_type=analytic&status_answered=1&src=${TEST_EXT}&order_src=equal" 2>&1)"
    if echo "$REPORT_JSON" | grep -qF "\"uniqueid\":\"${CDR_UNIQUEID}\""; then
        ok "SENMA reporting path can read it" "CallsReport API endpoint returned this exact CDR (uniqueid=$CDR_UNIQUEID)"
    else
        bad "SENMA reporting path can read it" "CallsReport API did not return uniqueid=$CDR_UNIQUEID: $REPORT_JSON"
    fi
else
    bad "SENMA reporting path can read it" "skipped -- no CDR uniqueid available to look up"
fi

print_report

# --- 16. Cleanup happens via the EXIT trap (HTTP delete of the trunk and
#         extension fixtures, PBX_Rules::delete() for the route fixture,
#         then a fresh Snep_PjsipTrunkConf/Snep_PjsipConf regeneration
#         naturally omits them all) ----------------------------------------

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
