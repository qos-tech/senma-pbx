#!/bin/bash
#
# SENMA WSS / Asterisk HTTP transport platform smoke test (TASK-0028Z).
#
# TASK-0028W (PJSIP Completeness Architecture Review) found the product's
# "wss" PJSIP transport (pjsip_transports, seeded, protocol=wss,
# bind=0.0.0.0:8089) BROKEN, live-confirmed: Asterisk showed the
# transport object as loaded, but `asterisk -rx 'http show status'`
# reported "Server Disabled" -- no /etc/asterisk/http.conf existed at
# all, so res_http_websocket.so/res_pjsip_transport_websocket.so (both
# already Running) had no listening socket behind them. A WSS client had
# nothing to connect to.
#
# This suite proves the platform-layer fix end to end, against a running
# `make dev` Docker environment:
#
#   docker/asterisk-config/http.conf (new, TASK-0028Z) seeded into the
#   persistent asterisk-etc volume by docker/asterisk-entrypoint.sh
#   -> Asterisk's built-in HTTP server enabled, TLS terminated directly
#      in Asterisk (tlsbindaddr=0.0.0.0:8089, matching the already-seeded
#      "wss" transport's own bind exactly) against a self-signed
#      TEST-ONLY certificate generated once at container first boot
#      (never committed, never baked into the image -- real certificate
#      lifecycle management is TASK-0029A's separate concern)
#   -> a real TLS handshake + WebSocket upgrade at /ws negotiating the
#      "sip" subprotocol succeeds (docker/wss-test-client's minimal
#      RFC 7118 client -- no available client speaks this protocol:
#      baresip's Debian package has no SIP-over-WebSocket transport at
#      all)
#   -> a real SIP REGISTER transaction (digest-auth round trip) over
#      that WebSocket, against a real SENMA-provisioned PJSIP extension
#      bound to the "wss" transport, is accepted (200 OK) and produces a
#      live PJSIP contact Asterisk itself reports
#      (`pjsip show contacts`) -- not just a client-side belief
#   -> when the WebSocket session ends, that contact disappears (the
#      correct, expected lifecycle for a transport-bound WS contact --
#      not a defect)
#   -> the platform state (http.conf, the TLS cert's own identity, the
#      PJSIP wss transport, and a fresh /ws handshake) survives both
#      `docker compose restart asterisk` and
#      `docker compose up -d --force-recreate asterisk`
#   -> the plain (non-TLS) HTTP/WS listener Asterisk's own [general]
#      enabled switch cannot avoid also turning on stays reachable from
#      nowhere outside the asterisk container (loopback-only bind) --
#      the product exposes/supports "wss" only, never plain "ws"
#
# See docs/tasks/0028z-wss-asterisk-http-enablement.md.
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
BASE_URL="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
FIXTURE_MARKER="task0028z-wss"
TEST_USER="admin"
TEST_PASSWORD="SmokeTest123!"

WSS_CLIENT_IMAGE="senma-wss-test-client:latest"
WSS_CLIENT_DOCKERFILE="wss-test-client.Dockerfile"

TEST_EXT=1196
TEST_EXT_SECRET="${FIXTURE_MARKER}-ext"

COOKIEJAR=""
NETWORK_NAME=""
ASTERISK_CID=""

log() { harness_log "$@"; }

db_query() {
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
        "${DB_NAME:-snep}" -N -e "$1"
}

http_login() {
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null \
        -d "user=${TEST_USER}&password=${TEST_PASSWORD}" "${BASE_URL}/index.php/auth/login"
}

# create_wss_extension <ext> <secret> <transport_id> -- a real PJSIP
# extension pinned to the "wss" transport via the transport_id selector
# TASK-0019 added.
create_wss_extension() {
    local ext="$1" secret="$2" transport_id="$3" body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "name=SENMA wss-smoke ${ext}" \
        --data-urlencode "exten=${ext}" \
        --data-urlencode "technology=pjsip" \
        --data-urlencode "password=${secret}" \
        --data-urlencode "passwordpadlock=" \
        --data-urlencode "email=" \
        --data-urlencode "exten_group[]=1" \
        --data-urlencode "pickup_group=" \
        --data-urlencode "transport_id=${transport_id}" \
        --data-urlencode "nat_no=1" \
        --data-urlencode "qualify=0" \
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
    log "create_wss_extension ${ext} failed (HTTP $httpcode): $(grep -o 'Server Message[^<]*' "$body" || head -c 300 "$body")"
    rm -f "$body"
    return 1
}

# delete_extension <ext> -- idempotent (established convention, see
# docs/tasks/0028y-pjsip-parameter-regression-closure.md).
delete_extension() {
    local ext="$1" httpcode
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "id=${ext}" \
        --data-urlencode "delete=Delete" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/extensions/remove")"
    [ "$httpcode" = "302" ]
}

asterisk_healthy() {
    $COMPOSE ps asterisk --format '{{.Health}}' 2>/dev/null | grep -q '^healthy$'
}

http_status_shows() {
    $COMPOSE exec -T asterisk asterisk -rx 'http show status' 2>&1 | grep -q "$1"
}

pjsip_wss_transport_bound() {
    $COMPOSE exec -T asterisk asterisk -rx 'pjsip show transport wss' 2>&1 | grep -q '0\.0\.0\.0:8089'
}

wss_handshake_ok() {
    docker run --rm --network "$NETWORK_NAME" "$WSS_CLIENT_IMAGE" \
        --host "$ASTERISK_SVC_NAME" --port 8089 --mode handshake 2>&1 | grep -q '^HANDSHAKE_OK$'
}

# --- 1. Required containers healthy -----------------------------------------

log "==> checking required containers"
harness_require_containers app asterisk db
harness_require_env DB_USER DB_PASSWORD DB_NAME

ASTERISK_CID="$($COMPOSE ps -q asterisk)"
if [ -z "$ASTERISK_CID" ]; then
    harness_blocked "could not resolve the asterisk container id"
fi
ASTERISK_SVC_NAME="$(docker inspect "$ASTERISK_CID" --format '{{index .Config.Labels "com.docker.compose.service"}}')"
NETWORK_NAME="$(docker inspect "$ASTERISK_CID" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')"
if [ -z "$NETWORK_NAME" ] || [ "$ASTERISK_SVC_NAME" != "asterisk" ]; then
    harness_blocked "could not resolve the asterisk container's compose network/service name"
fi
log "asterisk container: $ASTERISK_CID  network: $NETWORK_NAME  service: $ASTERISK_SVC_NAME"

log "==> building $WSS_CLIENT_IMAGE from $WSS_CLIENT_DOCKERFILE"
if ! harness_timeout 120 docker build -q -t "$WSS_CLIENT_IMAGE" -f "docker/$WSS_CLIENT_DOCKERFILE" docker >&2; then
    harness_blocked "failed to build $WSS_CLIENT_IMAGE from docker/$WSS_CLIENT_DOCKERFILE within 120s"
fi

# --- 2. http.conf ownership/existence in the runtime config path -----------

log "==> checking http.conf exists in the persistent asterisk-etc volume"
HTTP_CONF_LS="$($COMPOSE exec -T asterisk bash -c "ls -la /etc/asterisk/http.conf" 2>&1)"
if echo "$HTTP_CONF_LS" | grep -q '/etc/asterisk/http.conf'; then
    harness_ok "http.conf present" "$HTTP_CONF_LS"
else
    harness_bad "http.conf present" "not found in /etc/asterisk: $HTTP_CONF_LS"
fi

log "==> checking the WSS TLS certificate/key fixture exists with sane permissions"
KEY_LS="$($COMPOSE exec -T asterisk bash -c "ls -la /etc/asterisk/keys/wss-test-cert.pem /etc/asterisk/keys/wss-test-key.pem" 2>&1)"
if echo "$KEY_LS" | grep -q 'wss-test-cert.pem' && echo "$KEY_LS" | grep -q -- '-rw-------.*wss-test-key.pem'; then
    harness_ok "TEST-ONLY TLS cert/key present" "$KEY_LS"
else
    harness_bad "TEST-ONLY TLS cert/key present" "missing or wrong permissions: $KEY_LS"
fi

# --- 3. Asterisk HTTP server reports enabled --------------------------------

log "==> checking 'http show status'"
HTTP_STATUS="$($COMPOSE exec -T asterisk asterisk -rx 'http show status' 2>&1)"
log "$HTTP_STATUS"
if echo "$HTTP_STATUS" | grep -q 'Server Enabled and Bound to 127.0.0.1:8088'; then
    harness_ok "plain HTTP listener" "enabled, loopback-only (127.0.0.1:8088)"
else
    harness_bad "plain HTTP listener" "expected 'Server Enabled and Bound to 127.0.0.1:8088', got: $HTTP_STATUS"
fi
if echo "$HTTP_STATUS" | grep -q 'HTTPS Server Enabled and Bound to 0\.0\.0\.0:8089'; then
    harness_ok "TLS/WSS listener" "enabled, bound to 0.0.0.0:8089"
else
    harness_bad "TLS/WSS listener" "expected 'HTTPS Server Enabled and Bound to 0.0.0.0:8089', got: $HTTP_STATUS"
fi
if echo "$HTTP_STATUS" | grep -q '/ws => Asterisk HTTP WebSocket'; then
    harness_ok "/ws URI registered" "present in 'Enabled URI's'"
else
    harness_bad "/ws URI registered" "not found in: $HTTP_STATUS"
fi
# Security review (Phase 7): no unexpected HTTP surface beyond the two
# websocket URIs res_http_websocket.so/chan_websocket.so themselves
# register -- no AMI-over-HTTP, no unexpected management endpoint.
UNEXPECTED_URI="$(echo "$HTTP_STATUS" | sed -n '/Enabled URI/,/Enabled Redirects/p' | grep '=>' | grep -v -E '/media/\.\.\.|^/ws ')"
if [ -z "$UNEXPECTED_URI" ]; then
    harness_ok "no unexpected HTTP management surface" "only /media/... and /ws are registered"
else
    harness_bad "no unexpected HTTP management surface" "unexpected URI(s) registered: $UNEXPECTED_URI"
fi

# --- 4. PJSIP wss transport still loaded, correct bind ----------------------

log "==> checking 'pjsip show transport wss'"
if harness_retry 3 2 -- pjsip_wss_transport_bound; then
    harness_ok "pjsip wss transport bound" "0.0.0.0:8089"
else
    harness_bad "pjsip wss transport bound" "$($COMPOSE exec -T asterisk asterisk -rx 'pjsip show transport wss' 2>&1)"
fi

# --- 5. No accidental legacy chan_sip dependency introduced -----------------

log "==> checking chan_sip is still absent (PJSIP-only invariant)"
CHAN_SIP="$($COMPOSE exec -T asterisk asterisk -rx 'module show like chan_sip' 2>&1)"
if echo "$CHAN_SIP" | grep -q '0 modules loaded'; then
    harness_ok "chan_sip absent" "http.conf/WSS enablement did not load chan_sip"
else
    harness_bad "chan_sip absent" "unexpected: $CHAN_SIP"
fi

# --- 6. Minimal exposure: plain HTTP/WS unreachable from another container --

log "==> checking the plain (non-TLS) listener is unreachable from another container"
PLAIN_REACH="$($COMPOSE exec -T app bash -c 'curl -sS --max-time 3 -o /dev/null -w "%{http_code}" http://asterisk:8088/ws 2>&1' || true)"
PLAIN_REACH_CODE="$(echo "$PLAIN_REACH" | tail -1)"
if [ "$PLAIN_REACH_CODE" = "000" ]; then
    harness_ok "plain HTTP/WS not network-exposed" "app container cannot reach asterisk:8088 (curl: $PLAIN_REACH)"
else
    harness_bad "plain HTTP/WS not network-exposed" "expected curl's own connection-failure code '000' from another container, got HTTP $PLAIN_REACH_CODE: $PLAIN_REACH"
fi

# --- 7. Real WSS handshake proof --------------------------------------------

log "==> performing a real TLS handshake + WebSocket upgrade at /ws"
WSS_HANDSHAKE_OUT="$(docker run --rm --network "$NETWORK_NAME" "$WSS_CLIENT_IMAGE" \
    --host "$ASTERISK_SVC_NAME" --port 8089 --mode handshake 2>&1)"
log "$WSS_HANDSHAKE_OUT"
if echo "$WSS_HANDSHAKE_OUT" | grep -q '^HANDSHAKE_OK$'; then
    harness_ok "real WSS handshake" "TLS + WebSocket upgrade to /ws succeeded, Sec-WebSocket-Protocol: sip negotiated"
else
    harness_bad "real WSS handshake" "$WSS_HANDSHAKE_OUT"
fi

# =============================================================================
# Real end-to-end proof: SIP REGISTER over the WSS transport
# =============================================================================

log "==> logging in as ${TEST_USER}"
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

log "==> resolving the seeded 'wss' pjsip_transports row"
WSS_TRANSPORT_ID="$(db_query "SELECT id FROM pjsip_transports WHERE name='wss' AND enabled=1;")"
if [ -z "$WSS_TRANSPORT_ID" ]; then
    harness_blocked "no enabled 'wss' row in pjsip_transports -- cannot prove the product's WSS option end to end"
fi

log "==> checking for a leftover extension fixture from a prior interrupted run"
EXISTING_EXT_CANAL="$(db_query "SELECT canal FROM peers WHERE name='${TEST_EXT}';")"
EXISTING_EXT_SECRET="$(db_query "SELECT secret FROM peers WHERE name='${TEST_EXT}';")"
if [ -n "$EXISTING_EXT_CANAL" ]; then
    if [ "$EXISTING_EXT_CANAL" = "PJSIP/${TEST_EXT}" ] && [[ "$EXISTING_EXT_SECRET" == "${FIXTURE_MARKER}"* ]]; then
        delete_extension "$TEST_EXT" || harness_blocked "found a leftover wss-smoke fixture for extension ${TEST_EXT} but the HTTP delete flow did not return 302 -- refusing to proceed with a raw SQL fallback"
        log "removed leftover extension fixture ${TEST_EXT}"
    else
        harness_blocked "peers row for extension '${TEST_EXT}' already exists (canal='${EXISTING_EXT_CANAL}') and is NOT a wss-smoke fixture. Refusing to overwrite real/unknown data."
    fi
fi

log "==> creating extension ${TEST_EXT} pinned to the wss transport (id=${WSS_TRANSPORT_ID})"
if create_wss_extension "$TEST_EXT" "$TEST_EXT_SECRET" "$WSS_TRANSPORT_ID"; then
    harness_ok "extension created" "extension ${TEST_EXT}, transport_id=${WSS_TRANSPORT_ID}"
else
    harness_blocked "could not create the wss-smoke extension fixture"
fi
harness_register_cleanup "extension ${TEST_EXT} (wss-smoke fixture)" "delete_extension ${TEST_EXT}"

GENERATED_STANZA="$($COMPOSE exec -T asterisk bash -c 'cat /etc/asterisk/snep/senma-pjsip.conf' 2>&1)"
if echo "$GENERATED_STANZA" | grep -A5 "^\[${TEST_EXT}\]" | grep -q '^transport=wss$'; then
    harness_ok "generated config: transport=wss" "extension ${TEST_EXT} endpoint stanza pins transport=wss"
else
    harness_bad "generated config: transport=wss" "expected 'transport=wss' in extension ${TEST_EXT}'s endpoint stanza"
fi

log "==> real proof: TLS handshake -> /ws -> SIP REGISTER (digest auth) -> 200 OK, held open 4s"
REGISTER_OUT_FILE="$(mktemp)"
docker run --rm --network "$NETWORK_NAME" "$WSS_CLIENT_IMAGE" \
    --host "$ASTERISK_SVC_NAME" --port 8089 --mode register \
    --ext "$TEST_EXT" --secret "$TEST_EXT_SECRET" --hold-seconds 4 \
    > "$REGISTER_OUT_FILE" 2>&1 &
REGISTER_PID=$!

sleep 2
log "==> while the WS session is held open, checking Asterisk's own live contact list"
LIVE_CONTACTS="$($COMPOSE exec -T asterisk asterisk -rx 'pjsip show contacts' 2>&1)"
if echo "$LIVE_CONTACTS" | grep -q "^  Contact:  ${TEST_EXT}/sip:${TEST_EXT}@.*transport=ws"; then
    harness_ok "live PJSIP contact via wss" "Asterisk itself reports a live contact for extension ${TEST_EXT} over the ws(s) transport"
else
    harness_bad "live PJSIP contact via wss" "expected a live '${TEST_EXT}' contact with transport=ws in: $LIVE_CONTACTS"
fi

wait "$REGISTER_PID"
REGISTER_EXIT=$?
REGISTER_OUT="$(cat "$REGISTER_OUT_FILE")"
rm -f "$REGISTER_OUT_FILE"
log "$REGISTER_OUT"
if [ "$REGISTER_EXIT" -eq 0 ] && echo "$REGISTER_OUT" | grep -q '^REGISTER_OK$'; then
    harness_ok "real SIP REGISTER over WSS" "digest-auth REGISTER accepted (200 OK) end to end"
else
    harness_bad "real SIP REGISTER over WSS" "client exited $REGISTER_EXIT: $REGISTER_OUT"
fi

log "==> after the WS session ends, checking the contact disappears (expected transport-bound lifecycle, not a defect)"
contact_gone() {
    ! $COMPOSE exec -T asterisk asterisk -rx 'pjsip show contacts' 2>&1 | grep -q "^  Contact:  ${TEST_EXT}/"
}
if harness_retry 5 1 -- contact_gone; then
    harness_ok "contact removed when WS session ends" "no live contact for ${TEST_EXT} remains after the client disconnected"
else
    harness_bad "contact removed when WS session ends" "a contact for ${TEST_EXT} is still reported: $($COMPOSE exec -T asterisk asterisk -rx 'pjsip show contacts' 2>&1)"
fi

log "==> deleting extension ${TEST_EXT} fixture"
if delete_extension "$TEST_EXT"; then
    harness_ok "extension delete" "HTTP 302"
else
    harness_bad "extension delete" "supported delete flow did not return 302"
fi
DELETE_CHECK="$($COMPOSE exec -T asterisk bash -c 'cat /etc/asterisk/snep/senma-pjsip.conf' 2>&1)"
if ! echo "$DELETE_CHECK" | grep -q "^\[${TEST_EXT}\]"; then
    harness_ok "generated config: extension gone" "no [${TEST_EXT}] stanza remains"
else
    harness_bad "generated config: extension gone" "a [${TEST_EXT}] stanza still exists after delete"
fi

# =============================================================================
# Restart / recreate persistence proof (Phase 9)
# =============================================================================

CERT_HASH_BEFORE="$($COMPOSE exec -T asterisk sha256sum /etc/asterisk/keys/wss-test-cert.pem 2>/dev/null | awk '{print $1}')"
HTTP_CONF_HASH_BEFORE="$($COMPOSE exec -T asterisk sha256sum /etc/asterisk/http.conf 2>/dev/null | awk '{print $1}')"
if [ -z "$CERT_HASH_BEFORE" ] || [ -z "$HTTP_CONF_HASH_BEFORE" ]; then
    harness_blocked "could not hash http.conf/cert before restart -- cannot prove persistence"
fi

log "==> docker compose restart asterisk"
$COMPOSE restart asterisk >&2
if harness_retry 30 2 -- asterisk_healthy; then
    harness_ok "container healthy after restart" "asterisk reports healthy again"
else
    harness_bad "container healthy after restart" "asterisk did not report healthy within 60s"
fi
if harness_retry 10 2 -- http_status_shows 'HTTPS Server Enabled and Bound to 0\.0\.0\.0:8089'; then
    harness_ok "HTTP/WSS ready after restart" "'http show status' shows the HTTPS listener enabled again"
else
    harness_bad "HTTP/WSS ready after restart" "$($COMPOSE exec -T asterisk asterisk -rx 'http show status' 2>&1)"
fi
if harness_retry 10 2 -- pjsip_wss_transport_bound; then
    harness_ok "pjsip wss transport ready after restart" "bound to 0.0.0.0:8089 again"
else
    harness_bad "pjsip wss transport ready after restart" "not bound after restart"
fi
if harness_retry 10 2 -- wss_handshake_ok; then
    harness_ok "real WSS handshake after restart" "a fresh TLS+WebSocket upgrade succeeds"
else
    harness_bad "real WSS handshake after restart" "handshake failed after restart"
fi

log "==> docker compose up -d --force-recreate asterisk"
$COMPOSE up -d --force-recreate asterisk >&2
ASTERISK_CID="$($COMPOSE ps -q asterisk)"
if harness_retry 30 2 -- asterisk_healthy; then
    harness_ok "container healthy after recreate" "asterisk reports healthy again"
else
    harness_bad "container healthy after recreate" "asterisk did not report healthy within 60s"
fi
if harness_retry 10 2 -- http_status_shows 'HTTPS Server Enabled and Bound to 0\.0\.0\.0:8089'; then
    harness_ok "HTTP/WSS ready after recreate" "'http show status' shows the HTTPS listener enabled again"
else
    harness_bad "HTTP/WSS ready after recreate" "$($COMPOSE exec -T asterisk asterisk -rx 'http show status' 2>&1)"
fi
if harness_retry 10 2 -- pjsip_wss_transport_bound; then
    harness_ok "pjsip wss transport ready after recreate" "bound to 0.0.0.0:8089 again"
else
    harness_bad "pjsip wss transport ready after recreate" "not bound after recreate"
fi
if harness_retry 10 2 -- wss_handshake_ok; then
    harness_ok "real WSS handshake after recreate" "a fresh TLS+WebSocket upgrade succeeds"
else
    harness_bad "real WSS handshake after recreate" "handshake failed after recreate"
fi

CERT_HASH_AFTER="$($COMPOSE exec -T asterisk sha256sum /etc/asterisk/keys/wss-test-cert.pem 2>/dev/null | awk '{print $1}')"
HTTP_CONF_HASH_AFTER="$($COMPOSE exec -T asterisk sha256sum /etc/asterisk/http.conf 2>/dev/null | awk '{print $1}')"
if [ "$CERT_HASH_BEFORE" = "$CERT_HASH_AFTER" ]; then
    harness_ok "TLS cert identity preserved" "sha256 unchanged across restart+recreate ($CERT_HASH_BEFORE) -- not regenerated"
else
    harness_bad "TLS cert identity preserved" "cert hash changed: before=$CERT_HASH_BEFORE after=$CERT_HASH_AFTER"
fi
if [ "$HTTP_CONF_HASH_BEFORE" = "$HTTP_CONF_HASH_AFTER" ]; then
    harness_ok "http.conf preserved" "sha256 unchanged across restart+recreate ($HTTP_CONF_HASH_BEFORE)"
else
    harness_bad "http.conf preserved" "http.conf hash changed: before=$HTTP_CONF_HASH_BEFORE after=$HTTP_CONF_HASH_AFTER"
fi

harness_complete
