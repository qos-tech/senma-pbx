#!/usr/bin/env bash
#
# TASK-0035A — Reverse-proxy WSS TLS termination smoke.
#
# Proves the supported public contract:
#
#   client --WSS/TLS--> app:443 /asterisk/ws --plain WS--> asterisk:8088/ws
#
# and that Asterisk 8088/8089 are NOT published to the host.
# A plain HTTPS 200 is NOT accepted as WebSocket proof.
#
# Exit codes: scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
HTTPS_PORT="${MAG_HTTPS_PORT:-8443}"
PUBLIC_PATH="/asterisk/ws"
WSS_CLIENT_IMAGE="senma-wss-test-client:latest"
WSS_CLIENT_DOCKERFILE="wss-test-client.Dockerfile"

log() { harness_log "$@"; }

harness_require_env DB_USER DB_PASSWORD DB_NAME
harness_require_containers app asterisk db

log "==> TASK-0035A proxy WSS termination smoke"

ASTERISK_PORTS="$($COMPOSE ps asterisk --format '{{.Ports}}' 2>/dev/null | tr -d '\r')"
log "asterisk ports: ${ASTERISK_PORTS:-(none)}"
if echo "$ASTERISK_PORTS" | grep -Eq '(^|[ ,])8088:|0\.0\.0\.0:8088|[[:space:]]:::8088'; then
    harness_bad "Asterisk 8088 unpublished" "host publish still present: $ASTERISK_PORTS"
else
    harness_ok "Asterisk 8088 unpublished" "not present in host port map"
fi
if echo "$ASTERISK_PORTS" | grep -Eq '(^|[ ,])8089:|0\.0\.0\.0:8089|[[:space:]]:::8089'; then
    harness_bad "Asterisk 8089 unpublished" "host publish still present under TASK-0035A: $ASTERISK_PORTS"
else
    harness_ok "Asterisk 8089 unpublished" "not present in host port map"
fi

APP_PORTS="$($COMPOSE ps app --format '{{.Ports}}' 2>/dev/null | tr -d '\r')"
log "app ports: ${APP_PORTS:-(none)}"
if echo "$APP_PORTS" | grep -Eq '443/tcp|:443->|:443/'; then
    harness_ok "App HTTPS published" "$APP_PORTS"
else
    harness_bad "App HTTPS published" "expected host mapping to container :443, got: $APP_PORTS"
fi

HTTP_STATUS="$($COMPOSE exec -T asterisk asterisk -rx 'http show status' 2>/dev/null | tr -d '\r')"
log "$HTTP_STATUS"
if echo "$HTTP_STATUS" | grep -qiE 'Bound to 0\.0\.0\.0:8088'; then
    harness_ok "Asterisk private HTTP/WS bind" "0.0.0.0:8088"
elif echo "$HTTP_STATUS" | grep -qi '8088'; then
    harness_ok "Asterisk private HTTP/WS bind" "8088 present in http show status"
else
    harness_bad "Asterisk private HTTP/WS bind" "8088 not observed"
fi
if echo "$HTTP_STATUS" | grep -qiE 'Bound to 127\.0\.0\.1:8088'; then
    harness_bad "Asterisk HTTP not loopback-only" "proxy cannot reach loopback-only 8088"
fi

REACH="$($COMPOSE exec -T app bash -lc 'curl -s -o /dev/null -w "%{http_code}" --max-time 5 -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" -H "Sec-WebSocket-Protocol: sip" http://asterisk:8088/ws' 2>/dev/null | tr -d '\r' || true)"
if [ -z "$REACH" ] || [ "$REACH" = "000" ]; then
    harness_bad "app->asterisk:8088/ws reachability" "curl code=$REACH"
else
    harness_ok "app->asterisk:8088/ws reachability" "HTTP $REACH (non-zero proves Docker-network reachability)"
fi

TLS_OUT="$(echo | timeout 8 openssl s_client -connect "127.0.0.1:${HTTPS_PORT}" -servername localhost 2>/dev/null | tr -d '\r' || true)"
if echo "$TLS_OUT" | grep -q 'BEGIN CERTIFICATE'; then
    harness_ok "public TLS handshake" "127.0.0.1:${HTTPS_PORT}"
else
    harness_bad "public TLS handshake" "no certificate from 127.0.0.1:${HTTPS_PORT}"
fi

log "==> building $WSS_CLIENT_IMAGE"
if ! harness_timeout 120 docker build -q -t "$WSS_CLIENT_IMAGE" -f "docker/$WSS_CLIENT_DOCKERFILE" docker >/dev/null; then
    harness_blocked "failed to build $WSS_CLIENT_IMAGE"
fi

WS_OUT="$(docker run --rm --network host "$WSS_CLIENT_IMAGE" \
    --host 127.0.0.1 --port "$HTTPS_PORT" --path "$PUBLIC_PATH" --mode handshake 2>&1 || true)"
log "$WS_OUT"
if echo "$WS_OUT" | grep -q '^HANDSHAKE_OK$'; then
    harness_ok "public WSS upgrade" "HANDSHAKE_OK on ${PUBLIC_PATH}"
else
    harness_bad "public WSS upgrade" "$WS_OUT"
fi

PROXY_LINE="$($COMPOSE exec -T app bash -lc 'grep -R "ws://asterisk:8088/ws" /etc/apache2/sites-enabled /etc/apache2/sites-available 2>/dev/null' | tr -d '\r' || true)"
if echo "$PROXY_LINE" | grep -q 'ws://asterisk:8088/ws'; then
    harness_ok "Apache ProxyPass target" "ws://asterisk:8088/ws"
else
    harness_bad "Apache ProxyPass target" "ws://asterisk:8088/ws not found in Apache site config"
fi

ROW="$($COMPOSE exec -T db mariadb -N -u"${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" \
    -e "SELECT protocol, bind_port, COALESCE(cert_file,'') FROM pjsip_transports WHERE name='wss' AND enabled=1 LIMIT 1;" 2>/dev/null | tr -d '\r')"
log "signaling row: $ROW"
if echo "$ROW" | awk '{exit !($1=="ws" && $2=="8088")}'; then
    harness_ok "signaling transport private ws:8088" "$ROW"
else
    harness_bad "signaling transport private ws:8088" "got: $ROW"
fi
if echo "$ROW" | awk '{exit !($3=="" || $3=="NULL")}'; then
    harness_ok "signaling transport has no Asterisk public cert_file" "public trust is on proxy cert"
else
    harness_bad "signaling transport has no Asterisk public cert_file" "unexpected cert_file on private ws row: $ROW"
fi

harness_complete
