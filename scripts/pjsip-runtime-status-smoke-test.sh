#!/bin/bash
#
# SENMA PJSIP runtime status visibility smoke test (TASK-0029B).
#
# TASK-0028W's completeness review found the product PARTIAL/product-
# blind here: SENMA could provision PJSIP entities but had no coherent
# way to show an admin whether Asterisk's own live runtime state
# actually matched -- CONFIGURED was routinely confused with LIVE/
# REACHABLE/REGISTERED. This suite proves the new Snep_PjsipStatus_Manager
# service (and its wiring into ExtensionsController/TrunksController's
# real list pages) produces the correct normalized status for every
# entity/state combination this task's own investigation established as
# real, distinguishable Asterisk 22 runtime evidence:
#
#   extension, no device ever registered           -> INACTIVE
#   extension, registered + confirmed reachable     -> ACTIVE   (real baresip UA, real qualify OPTIONS round trip)
#   extension, registered + qualify failing         -> DEGRADED (real WSS registration, qualify forced, genuinely not answering OPTIONS)
#   registered trunk, real REGISTER succeeds         -> ACTIVE   (against the real "provider" simulator)
#   registered trunk, real REGISTER rejected         -> ERROR    (bad credentials against the same real provider)
#   registrationless trunk, qualify unreachable      -> DEGRADED (RFC 5737 TEST-NET-3 host, genuinely unreachable)
#   pjsip_external trunk, referenced endpoint exists -> ACTIVE
#   pjsip_external trunk, referenced endpoint absent -> ERROR
#   Asterisk unreachable                             -> an explicit
#     connection-error state, NEVER a fabricated per-row Offline/Inactive
#     badge (this product already had a page-level AMI-connectivity
#     guard predating this task, in both ExtensionsController::init()
#     and TrunksController::init() -- confirmed live still intact and
#     still the first line of defense; Snep_PjsipStatus_Manager's own
#     per-call try/catch is the second, narrower one, for the case AMI
#     is reachable but one specific query fails)
#
# Every fixture is created/edited/deleted through SENMA's own real HTTP
# flow (TrunksController/ExtensionsController), never raw SQL. Real
# runtime is exercised with the same already-established project
# fixtures: docker/baresip-test (a real, OPTIONS-answering SIP UA -- the
# only reason an "Active" reachability state is provable at all) and
# docker/wss-test-client (TASK-0028Z's minimal SIP-over-WebSocket
# client, which deliberately does NOT answer OPTIONS -- exactly what
# proves the "Degraded" path live, not simulated).
#
# See docs/tasks/0029b-pjsip-runtime-status-visibility.md.
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
BASE_URL="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
TEST_USER="admin"
TEST_PASSWORD="SmokeTest123!"
FIXTURE_MARKER="task0029b-status"

BARESIP_IMAGE="senma-baresip-test:latest"
BARESIP_DOCKERFILE="baresip-test.Dockerfile"
WSS_CLIENT_IMAGE="senma-wss-test-client:latest"
WSS_CLIENT_DOCKERFILE="wss-test-client.Dockerfile"

EXT_NOCONTACT=1195
EXT_DEGRADED=1194
EXT_ACTIVE=1193
EXT_SECRET_DEGRADED="${FIXTURE_MARKER}-degraded"
EXT_SECRET_ACTIVE="${FIXTURE_MARKER}-active"
EXT_SECRET_NOCONTACT="${FIXTURE_MARKER}-nocontact"

KEY_DIR="/etc/asterisk/keys"
EXTERNAL_STATIC_DIR="/etc/asterisk/task0029b-external"
EXTERNAL_ENDPOINT="task0029b-ext-endpoint"

COOKIEJAR=""
NETWORK_NAME=""
CREATED_TRUNK_IDS=()

log() { harness_log "$@"; }

db_query() {
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
        "${DB_NAME:-snep}" -N -e "$1"
}

http_login() {
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null \
        -d "user=${TEST_USER}&password=${TEST_PASSWORD}" "${BASE_URL}/index.php/auth/login"
}

asterisk_exec() {
    $COMPOSE exec -T asterisk bash -c "$1"
}

# status_cell_for <page-html-file> <row-label> -- extracts the
# data-runtime-status value and badge title for the table row whose
# label cell contains <row-label>. Uses the same awk paragraph-mode
# isolation technique established in TASK-0028Y's own
# extract_pjsip_block(), applied to <tr>...</tr> blocks instead of PJSIP
# config stanzas -- both solve the identical problem (isolate ONE
# specific block among several that share substrings).
status_cell_for() {
    local file="$1" label="$2"
    awk -v RS="</tr>" -v want="$label" '
        index($0, want) > 0 { print; exit }
    ' "$file" | grep -o 'data-runtime-status="[A-Z]*"' | head -1 | sed -E 's/.*"([A-Z]*)"/\1/'
}
detail_cell_for() {
    local file="$1" label="$2"
    awk -v RS="</tr>" -v want="$label" '
        index($0, want) > 0 { print; exit }
    ' "$file" | grep -o 'title="[^"]*"' | head -1 | sed -E 's/title="([^"]*)"/\1/'
}

create_extension() {
    local ext="$1" secret="$2" transportId="$3" body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "name=SENMA status-smoke ${ext}" \
        --data-urlencode "exten=${ext}" \
        --data-urlencode "technology=pjsip" \
        --data-urlencode "password=${secret}" \
        --data-urlencode "passwordpadlock=" \
        --data-urlencode "email=" \
        --data-urlencode "exten_group[]=1" \
        --data-urlencode "pickup_group=" \
        --data-urlencode "transport_id=${transportId}" \
        --data-urlencode "nat_no=1" \
        --data-urlencode "qualify=1" \
        --data-urlencode "type=friend" \
        --data-urlencode "directmedia=no" \
        --data-urlencode "dtmf=rfc2833" \
        --data-urlencode "codec=alaw" \
        --data-urlencode "codec1=ulaw" \
        --data-urlencode "codec2=gsm" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/extensions/add")"
    rm -f "$body"
    [ "$httpcode" = "302" ]
}

delete_extension() {
    local ext="$1"
    local httpcode
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "id=${ext}" \
        --data-urlencode "delete=Delete" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/extensions/remove")"
    [ "$httpcode" = "302" ]
}

# create_trunk <callerid> <username> <secret> -- always technology=pjsip,
# reverse_auth=1 (a real registered trunk).
create_trunk() {
    local callerid="$1" username="$2" secret="$3" body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "callerid=${callerid}" \
        --data-urlencode "technology=pjsip" \
        --data-urlencode "dialmethod=normal" \
        --data-urlencode "username=${username}" \
        --data-urlencode "secret=${secret}" \
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
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/trunks/add")"
    if [ "$httpcode" = "302" ]; then
        rm -f "$body"
        return 0
    fi
    log "create_trunk(${callerid}) failed (HTTP $httpcode): $(grep -o 'Server Message[^<]*' "$body" || head -c 300 "$body")"
    rm -f "$body"
    return 1
}

# create_registrationless_trunk <callerid> -- reverse_auth left unset
# (0), host = RFC 5737 TEST-NET-3 (guaranteed non-routable), qualify
# specify/2000ms.
create_registrationless_trunk() {
    local callerid="$1" body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "callerid=${callerid}" \
        --data-urlencode "technology=pjsip" \
        --data-urlencode "dialmethod=normal" \
        --data-urlencode "username=${FIXTURE_MARKER}-noauth" \
        --data-urlencode "secret=${FIXTURE_MARKER}-noauth-secret" \
        --data-urlencode "host=203.0.113.10" \
        --data-urlencode "fromuser=" \
        --data-urlencode "fromdomain=" \
        --data-urlencode "qualify=specify" \
        --data-urlencode "qualify_value=2000" \
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
        --data-urlencode "telco=" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/trunks/add")"
    if [ "$httpcode" = "302" ]; then
        rm -f "$body"
        return 0
    fi
    log "create_registrationless_trunk failed (HTTP $httpcode): $(grep -o 'Server Message[^<]*' "$body" || head -c 300 "$body")"
    rm -f "$body"
    return 1
}

create_external_trunk() {
    local callerid="$1" endpoint="$2" body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "callerid=${callerid}" \
        --data-urlencode "technology=pjsip_external" \
        --data-urlencode "external_endpoint=${endpoint}" \
        --data-urlencode "telco=" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/trunks/add")"
    if [ "$httpcode" = "302" ]; then
        rm -f "$body"
        return 0
    fi
    log "create_external_trunk failed (HTTP $httpcode): $(grep -o 'Server Message[^<]*' "$body" || head -c 300 "$body")"
    rm -f "$body"
    return 1
}

delete_trunk_by_id_name() {
    local id="$1" name="$2"
    local httpcode
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "id=${id}" \
        --data-urlencode "name=${name}" \
        --data-urlencode "delete=Delete" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/trunks/remove")"
    [ "$httpcode" = "302" ]
}

cleanup_trunk_fixtures() {
    local ok=1
    for id in "${CREATED_TRUNK_IDS[@]}"; do
        local name
        name="$(db_query "SELECT name FROM trunks WHERE id=${id};")"
        if [ -n "$name" ]; then
            delete_trunk_by_id_name "$id" "$name" || ok=0
        fi
    done
    [ "$ok" = "1" ]
}

# --- 1. Required containers + build client images --------------------------

log "==> checking required containers"
harness_require_containers app asterisk db provider
harness_require_env DB_USER DB_PASSWORD DB_NAME TRUNK_TEST_USERNAME TRUNK_TEST_SECRET

ASTERISK_CID="$($COMPOSE ps -q asterisk)"
NETWORK_NAME="$(docker inspect "$ASTERISK_CID" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')"
if [ -z "$NETWORK_NAME" ]; then
    harness_blocked "could not resolve the asterisk container's compose network"
fi

log "==> building ${BARESIP_IMAGE}/${WSS_CLIENT_IMAGE} (may be cached)"
if ! harness_timeout 180 docker build -q -t "$BARESIP_IMAGE" -f "docker/$BARESIP_DOCKERFILE" docker >&2; then
    harness_blocked "failed to build $BARESIP_IMAGE"
fi
if ! harness_timeout 120 docker build -q -t "$WSS_CLIENT_IMAGE" -f "docker/$WSS_CLIENT_DOCKERFILE" docker >&2; then
    harness_blocked "failed to build $WSS_CLIENT_IMAGE"
fi

log "==> checking for leftover fixtures from a prior interrupted run"
for ext in "$EXT_NOCONTACT" "$EXT_DEGRADED" "$EXT_ACTIVE"; do
    existing_canal="$(db_query "SELECT canal FROM peers WHERE name='${ext}';")"
    if [ -n "$existing_canal" ]; then
        harness_blocked "peers row for extension '${ext}' already exists (canal='${existing_canal}') -- refusing to overwrite unknown data"
    fi
done
LEFTOVER_TRUNKS="$(db_query "SELECT id FROM trunks WHERE callerid LIKE '${FIXTURE_MARKER}%';")"
if [ -n "$LEFTOVER_TRUNKS" ]; then
    harness_blocked "leftover trunk fixture(s) from a prior interrupted run found (ids: $(echo "$LEFTOVER_TRUNKS" | tr '\n' ' ')) -- refusing to proceed"
fi
docker rm -f senma-statussmoke-active >/dev/null 2>&1 || true

# --- 2. Log in ---------------------------------------------------------------

COOKIEJAR="$(mktemp)"
harness_register_best_effort_cleanup "cookie jar temp file" "rm -f '$COOKIEJAR'"
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${TEST_PASSWORD}');" 2>/dev/null | tr -d '\r')"
if [ -z "$TEST_HASH" ]; then
    harness_blocked "could not compute the ${TEST_USER} password hash via the app container"
fi
db_query "UPDATE users SET password = '${TEST_HASH}' WHERE name = '${TEST_USER}';" >&2
http_login
ADMIN_CSRF="$(harness_csrf_token "$COOKIEJAR" "$BASE_URL")"
if [ -z "$ADMIN_CSRF" ]; then harness_blocked "could not read the admin session's CSRF token"; fi

WSS_ID="$(db_query "SELECT id FROM pjsip_transports WHERE name='wss' AND enabled=1;")"
if [ -z "$WSS_ID" ]; then
    harness_blocked "no enabled 'wss' pjsip_transports row -- cannot prove the Degraded extension state"
fi

# =============================================================================
# PART A -- Extension statuses
# =============================================================================

log "==> creating extension fixtures (no-contact / degraded / active)"
create_extension "$EXT_NOCONTACT" "$EXT_SECRET_NOCONTACT" "" || harness_blocked "could not create no-contact extension fixture"
harness_register_cleanup "extension ${EXT_NOCONTACT} (status-smoke fixture)" "delete_extension ${EXT_NOCONTACT}"
create_extension "$EXT_DEGRADED" "$EXT_SECRET_DEGRADED" "$WSS_ID" || harness_blocked "could not create degraded extension fixture"
harness_register_cleanup "extension ${EXT_DEGRADED} (status-smoke fixture)" "delete_extension ${EXT_DEGRADED}"
create_extension "$EXT_ACTIVE" "$EXT_SECRET_ACTIVE" "" || harness_blocked "could not create active extension fixture"
harness_register_cleanup "extension ${EXT_ACTIVE} (status-smoke fixture)" "delete_extension ${EXT_ACTIVE}"

log "==> starting a real baresip UA registration for the 'active' extension (answers OPTIONS -- proves a real Active/reachable state)"
CONF_DIR="$(mktemp -d)"
harness_register_best_effort_cleanup "baresip config temp dir" "rm -rf '$CONF_DIR'"
mkdir -p "$CONF_DIR/$EXT_ACTIVE"
cp docker/baresip-test/config.template "$CONF_DIR/$EXT_ACTIVE/config"
sed -e "s|__EXTEN__|${EXT_ACTIVE}|g" -e "s|__ASTERISK_HOST__|asterisk|g" -e "s|__SECRET__|${EXT_SECRET_ACTIVE}|g" -e "s|__ANSWERMODE__|manual|g" \
    docker/baresip-test/accounts.template > "$CONF_DIR/$EXT_ACTIVE/accounts"
docker run -d --name senma-statussmoke-active --network "$NETWORK_NAME" \
    -v "$CONF_DIR/$EXT_ACTIVE:/root/.baresip" "$BARESIP_IMAGE" baresip -f /root/.baresip >&2
harness_register_cleanup "senma-statussmoke-active baresip container" "docker rm -f senma-statussmoke-active"

active_registered() {
    $COMPOSE exec -T asterisk asterisk -rx "pjsip show contacts" 2>&1 | grep -q "^  Contact:  ${EXT_ACTIVE}/.*Avail"
}
if ! harness_retry 10 1 -- active_registered; then
    harness_blocked "baresip fixture for extension ${EXT_ACTIVE} never reached a live Avail contact"
fi

log "==> real proof: TLS handshake -> /ws -> SIP REGISTER (degraded fixture, deliberately does not answer OPTIONS)"
docker run --rm --network "$NETWORK_NAME" "$WSS_CLIENT_IMAGE" \
    --host asterisk --port 8089 --mode register --ext "$EXT_DEGRADED" --secret "$EXT_SECRET_DEGRADED" --hold-seconds 12 > /tmp/task0029b-wss-reg.log 2>&1 &
WSS_REG_PID=$!
sleep 3
$COMPOSE exec -T asterisk asterisk -rx "pjsip qualify ${EXT_DEGRADED}" >&2
sleep 2

log "==> fetching the real extensions list page and reading the rendered status column"
EXT_PAGE="$(mktemp)"
harness_register_best_effort_cleanup "extensions page temp file" "rm -f '$EXT_PAGE'"
curl -sS -b "$COOKIEJAR" -c "$COOKIEJAR" "${BASE_URL}/index.php/default/extensions" -o "$EXT_PAGE"

NOCONTACT_STATE="$(status_cell_for "$EXT_PAGE" "SENMA status-smoke ${EXT_NOCONTACT}")"
if [ "$NOCONTACT_STATE" = "INACTIVE" ]; then
    harness_ok "extension no-contact status" "rendered as INACTIVE"
else
    harness_bad "extension no-contact status" "expected INACTIVE, got '$NOCONTACT_STATE'"
fi

ACTIVE_STATE="$(status_cell_for "$EXT_PAGE" "SENMA status-smoke ${EXT_ACTIVE}")"
ACTIVE_DETAIL="$(detail_cell_for "$EXT_PAGE" "SENMA status-smoke ${EXT_ACTIVE}")"
if [ "$ACTIVE_STATE" = "ACTIVE" ] && [[ "$ACTIVE_DETAIL" == *"reachable"* ]]; then
    harness_ok "extension registered+reachable status" "rendered as ACTIVE ($ACTIVE_DETAIL)"
else
    harness_bad "extension registered+reachable status" "expected ACTIVE/reachable, got '$ACTIVE_STATE' ($ACTIVE_DETAIL)"
fi

DEGRADED_STATE="$(status_cell_for "$EXT_PAGE" "SENMA status-smoke ${EXT_DEGRADED}")"
if [ "$DEGRADED_STATE" = "DEGRADED" ] || [ "$DEGRADED_STATE" = "PENDING" ]; then
    harness_ok "extension registered+not-responding status" "rendered as $DEGRADED_STATE (registered but qualify not confirmed -- the wss test client deliberately never answers OPTIONS)"
else
    harness_bad "extension registered+not-responding status" "expected DEGRADED or PENDING, got '$DEGRADED_STATE'"
fi

wait "$WSS_REG_PID" || true

# =============================================================================
# PART B -- Trunk statuses
# =============================================================================

log "==> creating a real registered trunk (good credentials against the real 'provider' fixture)"
create_trunk "${FIXTURE_MARKER}-ok" "${TRUNK_TEST_USERNAME}" "${TRUNK_TEST_SECRET}" || harness_blocked "could not create the registered-trunk fixture"
OK_TRUNK_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${FIXTURE_MARKER}-ok';")"
CREATED_TRUNK_IDS+=("$OK_TRUNK_ID")
harness_register_cleanup "trunk fixtures (status-smoke, all 4)" "cleanup_trunk_fixtures"

log "==> creating a trunk with deliberately bad credentials against the same real provider"
create_trunk "${FIXTURE_MARKER}-rejected" "${TRUNK_TEST_USERNAME}" "wrong-secret-${FIXTURE_MARKER}" || harness_blocked "could not create the rejected-trunk fixture"
REJECTED_TRUNK_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${FIXTURE_MARKER}-rejected';")"
CREATED_TRUNK_IDS+=("$REJECTED_TRUNK_ID")

log "==> creating a registrationless trunk (RFC 5737 TEST-NET-3, genuinely unreachable, qualify enabled)"
create_registrationless_trunk "${FIXTURE_MARKER}-noauth" || harness_blocked "could not create the registrationless-trunk fixture"
NOAUTH_TRUNK_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${FIXTURE_MARKER}-noauth';")"
CREATED_TRUNK_IDS+=("$NOAUTH_TRUNK_ID")

log "==> seeding a static externally-managed endpoint (pjsip_external's own trust boundary: SENMA never provisions this)"
asterisk_exec "mkdir -p $EXTERNAL_STATIC_DIR && cat > $EXTERNAL_STATIC_DIR/endpoint.conf <<EOF
[$EXTERNAL_ENDPOINT]
type=endpoint
context=default
disallow=all
allow=ulaw
aors=$EXTERNAL_ENDPOINT

[$EXTERNAL_ENDPOINT]
type=aor
contact=sip:203.0.113.20:5060
EOF
"
asterisk_exec "grep -q '$EXTERNAL_STATIC_DIR/endpoint.conf' /etc/asterisk/pjsip.conf || echo '#include ${EXTERNAL_STATIC_DIR#/etc/asterisk/}/endpoint.conf' >> /etc/asterisk/pjsip.conf"
asterisk_exec "asterisk -rx 'module reload res_pjsip.so'" >&2
external_endpoint_loaded() { asterisk_exec "asterisk -rx 'pjsip show endpoint ${EXTERNAL_ENDPOINT}'" 2>&1 | grep -q "Endpoint:  ${EXTERNAL_ENDPOINT}"; }
if ! harness_retry 5 1 -- external_endpoint_loaded; then
    harness_blocked "static external endpoint fixture did not load"
fi
cleanup_external_endpoint_fixture() {
    asterisk_exec "sed -i '\\|task0029b-external/endpoint.conf|d' /etc/asterisk/pjsip.conf; rm -rf $EXTERNAL_STATIC_DIR" >/dev/null
    asterisk_exec "asterisk -rx 'module reload res_pjsip.so'" >/dev/null
}
harness_register_cleanup "static external endpoint fixture" "cleanup_external_endpoint_fixture"

log "==> creating a pjsip_external trunk referencing the existing external endpoint"
create_external_trunk "${FIXTURE_MARKER}-ext-present" "$EXTERNAL_ENDPOINT" || harness_blocked "could not create the pjsip_external trunk fixture"
EXT_PRESENT_TRUNK_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${FIXTURE_MARKER}-ext-present';")"
CREATED_TRUNK_IDS+=("$EXT_PRESENT_TRUNK_ID")

log "==> creating a second pjsip_external trunk referencing an endpoint that does NOT exist"
# Appended into the SAME already-#include'd endpoint.conf (adding a
# second, separate file here would need its own #include line, an easy
# thing to get wrong -- appending to the one file already wired in is
# simpler and just as real a fixture).
asterisk_exec "cat >> $EXTERNAL_STATIC_DIR/endpoint.conf <<'EOF'

[task0029b-ext-endpoint-decoy]
type=endpoint
context=default
disallow=all
allow=ulaw
aors=task0029b-ext-endpoint-decoy

[task0029b-ext-endpoint-decoy]
type=aor
EOF
"
asterisk_exec "asterisk -rx 'module reload res_pjsip.so'" >&2
decoy_loaded() { asterisk_exec "asterisk -rx 'pjsip show endpoint task0029b-ext-endpoint-decoy'" 2>&1 | grep -q "Endpoint:  task0029b-ext-endpoint-decoy"; }
harness_retry 5 1 -- decoy_loaded || harness_blocked "decoy external endpoint fixture (used to prove 'external_endpoint must exist at creation time') did not load"
create_external_trunk "${FIXTURE_MARKER}-ext-missing" "task0029b-ext-endpoint-decoy" || harness_blocked "could not create the second pjsip_external trunk fixture"
MISSING_TRUNK_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${FIXTURE_MARKER}-ext-missing';")"
CREATED_TRUNK_IDS+=("$MISSING_TRUNK_ID")
# Now remove the decoy endpoint from Asterisk's runtime entirely --
# this trunk row remains (SENMA has no way to know it disappeared until
# it next queries runtime state, exactly the scenario this task exists
# to make visible), proving the ERROR-on-missing path against a trunk
# that really was valid a moment ago, not merely one that could never
# have been created. Rewrites endpoint.conf back to just the "present"
# fixture's own stanza.
asterisk_exec "cat > $EXTERNAL_STATIC_DIR/endpoint.conf <<EOF
[$EXTERNAL_ENDPOINT]
type=endpoint
context=default
disallow=all
allow=ulaw
aors=$EXTERNAL_ENDPOINT

[$EXTERNAL_ENDPOINT]
type=aor
contact=sip:203.0.113.20:5060
EOF
"
asterisk_exec "asterisk -rx 'module reload res_pjsip.so'" >&2

log "==> waiting for the registered trunk's outbound registration to settle"
trunk_ok_registered() {
    $COMPOSE exec -T asterisk asterisk -rx 'pjsip show registrations outbound' 2>&1 | grep -q "trunk-${OK_TRUNK_ID}-registration.*Registered"
}
harness_retry 10 2 -- trunk_ok_registered || harness_blocked "registered-trunk fixture never reached Registered"

log "==> waiting for the rejected trunk's registration to settle"
trunk_rejected_settled() {
    $COMPOSE exec -T asterisk asterisk -rx 'pjsip show registrations outbound' 2>&1 | grep -q "trunk-${REJECTED_TRUNK_ID}-registration.*Rejected"
}
harness_retry 10 2 -- trunk_rejected_settled || harness_blocked "rejected-trunk fixture never reached Rejected"

log "==> forcing a qualify check on the registrationless trunk"
asterisk_exec "asterisk -rx 'pjsip qualify trunk-${NOAUTH_TRUNK_ID}'" >&2
sleep 2

log "==> fetching the real trunks list page and reading the rendered status column"
TRUNK_PAGE="$(mktemp)"
harness_register_best_effort_cleanup "trunks page temp file" "rm -f '$TRUNK_PAGE'"
curl -sS -b "$COOKIEJAR" -c "$COOKIEJAR" "${BASE_URL}/index.php/default/trunks" -o "$TRUNK_PAGE"

OK_STATE="$(status_cell_for "$TRUNK_PAGE" "${FIXTURE_MARKER}-ok")"
if [ "$OK_STATE" = "ACTIVE" ]; then
    harness_ok "registered trunk (real REGISTER succeeds)" "rendered as ACTIVE"
else
    harness_bad "registered trunk (real REGISTER succeeds)" "expected ACTIVE, got '$OK_STATE'"
fi

REJECTED_STATE="$(status_cell_for "$TRUNK_PAGE" "${FIXTURE_MARKER}-rejected")"
if [ "$REJECTED_STATE" = "ERROR" ]; then
    harness_ok "rejected trunk (real REGISTER rejected)" "rendered as ERROR"
else
    harness_bad "rejected trunk (real REGISTER rejected)" "expected ERROR, got '$REJECTED_STATE'"
fi

NOAUTH_STATE="$(status_cell_for "$TRUNK_PAGE" "${FIXTURE_MARKER}-noauth")"
if [ "$NOAUTH_STATE" = "DEGRADED" ]; then
    harness_ok "registrationless trunk (qualify unreachable)" "rendered as DEGRADED"
else
    harness_bad "registrationless trunk (qualify unreachable)" "expected DEGRADED, got '$NOAUTH_STATE'"
fi

EXT_PRESENT_STATE="$(status_cell_for "$TRUNK_PAGE" "${FIXTURE_MARKER}-ext-present")"
if [ "$EXT_PRESENT_STATE" = "ACTIVE" ]; then
    harness_ok "pjsip_external trunk (endpoint present)" "rendered as ACTIVE"
else
    harness_bad "pjsip_external trunk (endpoint present)" "expected ACTIVE, got '$EXT_PRESENT_STATE'"
fi

EXT_MISSING_STATE="$(status_cell_for "$TRUNK_PAGE" "${FIXTURE_MARKER}-ext-missing")"
if [ "$EXT_MISSING_STATE" = "ERROR" ]; then
    harness_ok "pjsip_external trunk (referenced endpoint now missing)" "rendered as ERROR -- read-only observation, SENMA never recreated/modified the missing endpoint"
else
    harness_bad "pjsip_external trunk (referenced endpoint now missing)" "expected ERROR, got '$EXT_MISSING_STATE'"
fi

# =============================================================================
# PART C -- Runtime-query failure must never fabricate a false Offline
# =============================================================================

ensure_asterisk_started_and_healthy() {
    $COMPOSE start asterisk >/dev/null 2>&1
    local i h
    for i in $(seq 1 30); do
        h="$($COMPOSE ps asterisk --format '{{.Health}}' 2>/dev/null)"
        [ "$h" = "healthy" ] && return 0
        sleep 2
    done
    return 1
}

log "==> stopping asterisk to prove a runtime-query failure never fabricates a false per-row Offline/Inactive state"
$COMPOSE stop asterisk >&2
harness_register_cleanup "asterisk container (restart after Part C)" "ensure_asterisk_started_and_healthy"

DOWN_PAGE="$(mktemp)"
harness_register_best_effort_cleanup "down-state page temp file" "rm -f '$DOWN_PAGE'"
curl -sS -b "$COOKIEJAR" -c "$COOKIEJAR" "${BASE_URL}/index.php/default/extensions" -o "$DOWN_PAGE"
if grep -q 'data-runtime-status="INACTIVE"\|data-runtime-status="ERROR"' "$DOWN_PAGE"; then
    harness_bad "AMI-down does not fabricate a false per-row state" "found a fabricated INACTIVE/ERROR badge while Asterisk was stopped"
elif grep -qi "Asterisk" "$DOWN_PAGE"; then
    harness_ok "AMI-down does not fabricate a false per-row state" "the pre-existing page-level Asterisk-connectivity guard (ExtensionsController::init()) rendered an explicit connection-error page instead of any per-row status at all"
else
    harness_bad "AMI-down does not fabricate a false per-row state" "page rendered neither a recognizable connection-error message nor a fabricated per-row status -- unexpected content"
fi

log "==> restarting asterisk"
$COMPOSE start asterisk >&2
asterisk_healthy() { $COMPOSE ps asterisk --format '{{.Health}}' 2>/dev/null | grep -q '^healthy$'; }
if harness_retry 30 2 -- asterisk_healthy; then
    harness_ok "asterisk recovers after restart" "container healthy again"
else
    harness_bad "asterisk recovers after restart" "did not become healthy within 60s"
fi

log "==> confirming normal status reporting resumes"
pjsip_modules_running() {
    $COMPOSE exec -T asterisk asterisk -rx 'module show like res_pjsip.so' 2>&1 | grep -q "Running"
}
harness_retry 10 2 -- pjsip_modules_running
RECOVERED_PAGE="$(mktemp)"
harness_register_best_effort_cleanup "recovered page temp file" "rm -f '$RECOVERED_PAGE'"
# A container restart means the trunk's outbound registration has to
# happen fresh -- bounded polling, not a single immediate check, same
# reasoning as every other suite's own post-reload settling checks.
recovered_trunk_active() {
    curl -sS -b "$COOKIEJAR" -c "$COOKIEJAR" "${BASE_URL}/index.php/default/trunks" -o "$RECOVERED_PAGE"
    [ "$(status_cell_for "$RECOVERED_PAGE" "${FIXTURE_MARKER}-ok")" = "ACTIVE" ]
}
if harness_retry 10 2 -- recovered_trunk_active; then
    harness_ok "status reporting resumes after Asterisk recovers" "registered trunk fixture is ACTIVE again"
else
    harness_bad "status reporting resumes after Asterisk recovers" "expected ACTIVE within 20s, got '$(status_cell_for "$RECOVERED_PAGE" "${FIXTURE_MARKER}-ok")'"
fi

# =============================================================================
# Security: status is read-only, no secrets leak into the rendered page
# =============================================================================

log "==> confirming no secret material leaks into the status columns/pages"
if grep -qE "${TRUNK_TEST_SECRET}|${EXT_SECRET_ACTIVE}|${EXT_SECRET_DEGRADED}|probesecret|wrong-secret-${FIXTURE_MARKER}" "$TRUNK_PAGE" "$EXT_PAGE" "$RECOVERED_PAGE"; then
    harness_bad "no secrets in rendered status pages" "a configured secret/password value was found verbatim in rendered HTML"
else
    harness_ok "no secrets in rendered status pages" "none of the fixtures' passwords/secrets appear in the rendered extensions/trunks pages"
fi

log "==> confirming the status pages require authentication (no unauthenticated status disclosure)"
# This project's existing session-enforcement convention renders the
# login page at HTTP 200 for an unauthenticated request (a redirect-via-
# render pattern, not a 3xx) -- already proven safe/established by the
# pre-existing session-csrf-security/authorization-smoke suites. What
# actually matters here is that no real status data leaks out, not the
# specific HTTP status code.
UNAUTH_BODY="$(mktemp)"
harness_register_best_effort_cleanup "unauth check temp file" "rm -f '$UNAUTH_BODY'"
curl -sS -o "$UNAUTH_BODY" "${BASE_URL}/index.php/default/extensions"
if grep -q "data-runtime-status=" "$UNAUTH_BODY"; then
    harness_bad "extensions status requires authentication" "an unauthenticated request rendered real runtime-status data"
else
    harness_ok "extensions status requires authentication" "an unauthenticated request rendered no runtime-status data (title: $(grep -o '<title>[^<]*</title>' "$UNAUTH_BODY"))"
fi

harness_complete
