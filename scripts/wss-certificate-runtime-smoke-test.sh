#!/bin/bash
#
# SENMA production WSS certificate trust / runtime verification smoke
# test (TASK-0034E, realigned by TASK-0035A).
#
# Public WSS TLS terminates at the app reverse proxy:
#
#   client --WSS/TLS--> app:443 /asterisk/ws --plain WS--> asterisk:8088/ws
#
# Proves scripts/wss-cert-check.sh against that contract without mutating
# the seeded pjsip `wss` signaling row away from protocol=ws / :8088 /
# empty Asterisk cert fields.
#
# Exit code: scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
# shellcheck source=lib/wss-cert-lib.sh
source "$SCRIPT_DIR/lib/wss-cert-lib.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
BASE_URL="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
HTTPS_PORT="${MAG_HTTPS_PORT:-8443}"
TEST_USER="admin"
TEST_PASSWORD="SmokeTest123!"

PUBLIC_CERT="/etc/senma/certs/public-wss.crt"
PUBLIC_KEY="/etc/senma/certs/public-wss.key"
FIXTURE_DIR="/etc/senma/certs/fixtures"
FIXTURE_PREFIX="task0034e"
PILOT_HOSTNAME="task0034e-pilot.test"
TEST_EXT=1197
TEST_EXT_SECRET="${FIXTURE_PREFIX}-ext"
PUBLIC_PATH="/asterisk/ws"

WSS_CLIENT_IMAGE="senma-wss-test-client:latest"
WSS_CLIENT_DOCKERFILE="wss-test-client.Dockerfile"

HOST_SCRATCH="$(mktemp -d)"
harness_register_best_effort_cleanup "host scratch dir ($HOST_SCRATCH)" "rm -rf '$HOST_SCRATCH'"

COOKIEJAR=""
WSS_ID=""
NETWORK_NAME=""
PUBLIC_CERT_BACKUP=""
PUBLIC_KEY_BACKUP=""

log() { harness_log "$@"; }

db_query() {
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
        "${DB_NAME:-snep}" -N -e "$1"
}

app_exec() {
    $COMPOSE exec -T app bash -c "$1"
}

check() {
    SMOKE_COMPOSE="$COMPOSE" bash "$SCRIPT_DIR/wss-cert-check.sh" "$@"
}

reload_public_tls() {
    app_exec "apache2ctl graceful" >/dev/null 2>&1
}

restore_public_cert() {
    if [ -n "$PUBLIC_CERT_BACKUP" ] && [ -n "$PUBLIC_KEY_BACKUP" ]; then
        app_exec "cp -f '$PUBLIC_CERT_BACKUP' '$PUBLIC_CERT' && cp -f '$PUBLIC_KEY_BACKUP' '$PUBLIC_KEY' && chown www-data:www-data '$PUBLIC_CERT' '$PUBLIC_KEY' && chmod 644 '$PUBLIC_CERT' && chmod 600 '$PUBLIC_KEY'"
        reload_public_tls || true
    fi
    if [ -n "$WSS_ID" ]; then
        db_query "UPDATE pjsip_transports SET protocol='ws', bind_port=8088, cert_file=NULL, priv_key_file=NULL, ca_list_file=NULL WHERE id=${WSS_ID};" >/dev/null 2>&1 || true
    fi
}

create_wss_extension() {
    local body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "name=SENMA task0034e ${TEST_EXT}" \
        --data-urlencode "exten=${TEST_EXT}" \
        --data-urlencode "technology=pjsip" \
        --data-urlencode "password=${TEST_EXT_SECRET}" \
        --data-urlencode "passwordpadlock=" \
        --data-urlencode "email=" \
        --data-urlencode "exten_group[]=1" \
        --data-urlencode "pickup_group=" \
        --data-urlencode "transport_id=${WSS_ID}" \
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
    local ok=1
    [ "$httpcode" = "302" ] || ok=0
    if [ "$ok" != "1" ]; then
        log "create_wss_extension failed (HTTP $httpcode): $(grep -o 'Server Message[^<]*' "$body" || head -c 300 "$body")"
    fi
    rm -f "$body"
    [ "$ok" = "1" ]
}

delete_extension() {
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "id=${TEST_EXT}" \
        --data-urlencode "delete=Delete" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/extensions/remove" >/dev/null
}

http_login() {
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null \
        -d "user=${TEST_USER}&password=${TEST_PASSWORD}" "${BASE_URL}/index.php/auth/login"
}

# =============================================================================
# 1. Preconditions
# =============================================================================

log "==> checking required containers"
harness_require_containers app asterisk db
harness_require_env DB_USER DB_PASSWORD DB_NAME

log "==> preparing app fixture dir and backing up the live public WSS certificate"
app_exec "mkdir -p '$FIXTURE_DIR' && rm -f '$FIXTURE_DIR'/${FIXTURE_PREFIX}-*.pem"
PUBLIC_CERT_BACKUP="${FIXTURE_DIR}/${FIXTURE_PREFIX}-backup.crt"
PUBLIC_KEY_BACKUP="${FIXTURE_DIR}/${FIXTURE_PREFIX}-backup.key"
app_exec "cp -f '$PUBLIC_CERT' '$PUBLIC_CERT_BACKUP' && cp -f '$PUBLIC_KEY' '$PUBLIC_KEY_BACKUP'"
harness_register_cleanup "public WSS certificate restored" "restore_public_cert"
harness_register_best_effort_cleanup "app fixture certs" "app_exec 'rm -f $FIXTURE_DIR/${FIXTURE_PREFIX}-*.pem'"

LEFTOVER_EXT="$(db_query "SELECT name FROM peers WHERE name='${TEST_EXT}';" 2>/dev/null || true)"
if [ -n "$LEFTOVER_EXT" ]; then
    # peers.name holds the extension number in this schema (no exten column).
    db_query "DELETE FROM peers WHERE name='${TEST_EXT}';" >/dev/null 2>&1 || true
    log "removed leftover extension ${TEST_EXT} from a prior interrupted run"
fi

log "==> logging in as ${TEST_USER}"
COOKIEJAR="$(mktemp)"
harness_register_best_effort_cleanup "cookie jar temp file" "rm -f '$COOKIEJAR'"
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${TEST_PASSWORD}');" 2>/dev/null | tr -d '\r')"
if [ -z "$TEST_HASH" ]; then harness_blocked "could not compute the ${TEST_USER} password hash via the app container"; fi
db_query "UPDATE users SET password = '${TEST_HASH}' WHERE name = '${TEST_USER}';" >&2
http_login
ADMIN_CSRF="$(harness_csrf_token "$COOKIEJAR" "$BASE_URL")"
if [ -z "$ADMIN_CSRF" ]; then harness_blocked "could not read the admin session's CSRF token"; fi

WSS_ID="$(db_query "SELECT id FROM pjsip_transports WHERE name='wss';")"
if [ -z "$WSS_ID" ]; then harness_blocked "no 'wss' pjsip_transports row exists"; fi
WSS_SHAPE="$(db_query "SELECT CONCAT(protocol,':',bind_port,':',COALESCE(cert_file,'')) FROM pjsip_transports WHERE id=${WSS_ID};")"
log "wss signaling row id=${WSS_ID} shape=${WSS_SHAPE}"
if [ "$WSS_SHAPE" != "ws:8088:" ]; then
    harness_blocked "seeded wss row is not in TASK-0035A proxy-backend shape (expected ws:8088:, got $WSS_SHAPE)"
fi

ASTERISK_CID="$($COMPOSE ps -q asterisk)"
NETWORK_NAME="$(harness_asterisk_test_network "$ASTERISK_CID")"
if [ -z "$NETWORK_NAME" ]; then harness_blocked "could not resolve the asterisk compose network"; fi

log "==> building $WSS_CLIENT_IMAGE from $WSS_CLIENT_DOCKERFILE"
if ! harness_timeout 120 docker build -q -t "$WSS_CLIENT_IMAGE" -f "docker/$WSS_CLIENT_DOCKERFILE" docker >/dev/null; then
    harness_blocked "failed to build $WSS_CLIENT_IMAGE"
fi

# =============================================================================
# 2. Fixture classification
# =============================================================================

log "==> baseline: current public WSS certificate is the dev fixture"
BASELINE="$(check)"
if echo "$BASELINE" | grep -q '^FIXTURE: yes' && echo "$BASELINE" | grep -q '^TRUST_STATE: SELF_SIGNED'; then
    harness_ok "dev-fixture certificate classified as FIXTURE" "$(echo "$BASELINE" | grep '^FIXTURE:')"
else
    harness_bad "dev-fixture certificate classified as FIXTURE" "unexpected: $(echo "$BASELINE" | grep -E '^FIXTURE:|^TRUST_STATE:')"
fi

BASELINE_PILOT="$(check --pilot)"; BASELINE_PILOT_RC=$?
if [ "$BASELINE_PILOT_RC" -ne 0 ] && echo "$BASELINE_PILOT" | grep -q 'NOT_ACCEPTABLE_FOR_PILOT'; then
    harness_ok "fixture certificate rejected by the pilot gate" "$(echo "$BASELINE_PILOT" | grep '^PILOT_ACCEPTANCE:')"
else
    harness_bad "fixture certificate rejected by the pilot gate" "exit=$BASELINE_PILOT_RC $(echo "$BASELINE_PILOT" | grep '^PILOT_ACCEPTANCE:')"
fi

# =============================================================================
# 3. Negative classifications (files on app)
# =============================================================================

log "==> missing certificate file -> MISSING"
OUT="$(check --cert "${FIXTURE_DIR}/${FIXTURE_PREFIX}-does-not-exist.pem" --key "${FIXTURE_DIR}/${FIXTURE_PREFIX}-does-not-exist-key.pem" --no-runtime)"
if echo "$OUT" | grep -q '^TRUST_STATE: MISSING'; then
    harness_ok "missing cert/key classified MISSING" "$(echo "$OUT" | grep '^TRUST_STATE:')"
else
    harness_bad "missing cert/key classified MISSING" "$(echo "$OUT" | grep '^TRUST_STATE:')"
fi

log "==> generating a mismatched cert/key pair on app"
app_exec "
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout '${FIXTURE_DIR}/${FIXTURE_PREFIX}-mismatch-a-key.pem' \
        -out '${FIXTURE_DIR}/${FIXTURE_PREFIX}-mismatch-a-cert.pem' \
        -days 3650 -subj '/CN=${FIXTURE_PREFIX}-mismatch-a' \
        -addext 'subjectAltName=DNS:${FIXTURE_PREFIX}-mismatch-a' >/dev/null 2>&1
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout '${FIXTURE_DIR}/${FIXTURE_PREFIX}-mismatch-b-key.pem' \
        -out '${FIXTURE_DIR}/${FIXTURE_PREFIX}-mismatch-b-cert.pem' \
        -days 3650 -subj '/CN=${FIXTURE_PREFIX}-mismatch-b' \
        -addext 'subjectAltName=DNS:${FIXTURE_PREFIX}-mismatch-b' >/dev/null 2>&1
"
OUT="$(check --cert "${FIXTURE_DIR}/${FIXTURE_PREFIX}-mismatch-a-cert.pem" --key "${FIXTURE_DIR}/${FIXTURE_PREFIX}-mismatch-b-key.pem" --no-runtime --pilot)"
if echo "$OUT" | grep -q '^TRUST_STATE: PAIR_MISMATCH' && echo "$OUT" | grep -q 'NOT_ACCEPTABLE_FOR_PILOT'; then
    harness_ok "mismatched cert/key pair classified PAIR_MISMATCH" "$(echo "$OUT" | grep '^TRUST_STATE:')"
else
    harness_bad "mismatched cert/key pair classified PAIR_MISMATCH" "$(echo "$OUT" | grep -E '^TRUST_STATE:|^PILOT_ACCEPTANCE:')"
fi
if echo "$OUT" | grep -qiE 'BEGIN (RSA )?PRIVATE KEY'; then
    harness_bad "no private key material in tool output" "PEM private key body found in output"
else
    harness_ok "no private key material in tool output" "confirmed absent"
fi

log "==> hostname mismatch"
OUT="$(check --cert "${FIXTURE_DIR}/${FIXTURE_PREFIX}-mismatch-a-cert.pem" --key "${FIXTURE_DIR}/${FIXTURE_PREFIX}-mismatch-a-key.pem" --hostname "${FIXTURE_PREFIX}-other-host" --no-runtime --pilot)"
if echo "$OUT" | grep -q '^TRUST_STATE: HOSTNAME_MISMATCH' && echo "$OUT" | grep -q 'NOT_ACCEPTABLE_FOR_PILOT'; then
    harness_ok "certificate/hostname mismatch classified HOSTNAME_MISMATCH" "$(echo "$OUT" | grep '^TRUST_STATE:')"
else
    harness_bad "certificate/hostname mismatch classified HOSTNAME_MISMATCH" "$(echo "$OUT" | grep -E '^TRUST_STATE:|^PILOT_ACCEPTANCE:')"
fi

OUT="$(check --cert "${FIXTURE_DIR}/${FIXTURE_PREFIX}-mismatch-a-cert.pem" --key "${FIXTURE_DIR}/${FIXTURE_PREFIX}-mismatch-a-key.pem" --hostname "${FIXTURE_PREFIX}-mismatch-a" --no-runtime)"
if echo "$OUT" | grep -qE '^HOSTNAME_MATCH: yes'; then
    harness_ok "matching hostname accepted" "$(echo "$OUT" | grep '^HOSTNAME_MATCH:')"
else
    harness_bad "matching hostname accepted" "$(echo "$OUT" | grep '^HOSTNAME_MATCH:')"
fi

log "==> expired certificate"
app_exec "openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout '${FIXTURE_DIR}/${FIXTURE_PREFIX}-expired-key.pem' \
    -out '${FIXTURE_DIR}/${FIXTURE_PREFIX}-expired-cert.pem' \
    -subj '/CN=${FIXTURE_PREFIX}-expired' \
    -not_before 20200101000000Z -not_after 20200201000000Z \
    -addext 'subjectAltName=DNS:${FIXTURE_PREFIX}-expired' >/dev/null 2>&1"
OUT="$(check --cert "${FIXTURE_DIR}/${FIXTURE_PREFIX}-expired-cert.pem" --key "${FIXTURE_DIR}/${FIXTURE_PREFIX}-expired-key.pem" --no-runtime --pilot)"
if echo "$OUT" | grep -q '^TRUST_STATE: EXPIRED' && echo "$OUT" | grep -q 'NOT_ACCEPTABLE_FOR_PILOT'; then
    harness_ok "expired certificate classified EXPIRED" "$(echo "$OUT" | grep '^TRUST_STATE:')"
else
    harness_bad "expired certificate classified EXPIRED" "$(echo "$OUT" | grep -E '^TRUST_STATE:|^PILOT_ACCEPTANCE:')"
fi

log "==> not-yet-valid certificate"
app_exec "openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout '${FIXTURE_DIR}/${FIXTURE_PREFIX}-nyv-key.pem' \
    -out '${FIXTURE_DIR}/${FIXTURE_PREFIX}-nyv-cert.pem' \
    -subj '/CN=${FIXTURE_PREFIX}-nyv' \
    -not_before 20991231000000Z -not_after 21001231000000Z \
    -addext 'subjectAltName=DNS:${FIXTURE_PREFIX}-nyv' >/dev/null 2>&1"
OUT="$(check --cert "${FIXTURE_DIR}/${FIXTURE_PREFIX}-nyv-cert.pem" --key "${FIXTURE_DIR}/${FIXTURE_PREFIX}-nyv-key.pem" --no-runtime --pilot)"
if echo "$OUT" | grep -q '^TRUST_STATE: NOT_YET_VALID' && echo "$OUT" | grep -q 'NOT_ACCEPTABLE_FOR_PILOT'; then
    harness_ok "not-yet-valid certificate classified NOT_YET_VALID" "$(echo "$OUT" | grep '^TRUST_STATE:')"
else
    harness_bad "not-yet-valid certificate classified NOT_YET_VALID" "$(echo "$OUT" | grep -E '^TRUST_STATE:|^PILOT_ACCEPTANCE:')"
fi

# =============================================================================
# 4. Trusted public-proxy proof (TASK-0035A)
# =============================================================================

log "==> generating ephemeral test CA + leaf for ${PILOT_HOSTNAME} on app"
CA_CERT="${FIXTURE_DIR}/${FIXTURE_PREFIX}-test-ca.pem"
CA_KEY="${FIXTURE_DIR}/${FIXTURE_PREFIX}-test-ca-key.pem"
LEAF_KEY="${FIXTURE_DIR}/${FIXTURE_PREFIX}-trusted-key.pem"
FULLCHAIN="${FIXTURE_DIR}/${FIXTURE_PREFIX}-trusted-cert.pem"
app_exec "
    set -e
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout '$CA_KEY' -out '$CA_CERT' -days 30 \
        -subj '/CN=SENMA Test CA (${FIXTURE_PREFIX})' \
        -addext 'basicConstraints=critical,CA:true' \
        -addext 'keyUsage=critical,keyCertSign,cRLSign' >/dev/null 2>&1
    openssl req -newkey rsa:2048 -nodes \
        -keyout '$LEAF_KEY' -out '/tmp/${FIXTURE_PREFIX}-leaf.csr' \
        -subj '/CN=${PILOT_HOSTNAME}' >/dev/null 2>&1
    printf 'subjectAltName=DNS:%s\nbasicConstraints=CA:false\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n' \
        '${PILOT_HOSTNAME}' > '/tmp/${FIXTURE_PREFIX}-leaf.ext'
    openssl x509 -req -in '/tmp/${FIXTURE_PREFIX}-leaf.csr' \
        -CA '$CA_CERT' -CAkey '$CA_KEY' -CAcreateserial \
        -out '/tmp/${FIXTURE_PREFIX}-leaf.pem' -days 30 \
        -extfile '/tmp/${FIXTURE_PREFIX}-leaf.ext' >/dev/null 2>&1
    cat '/tmp/${FIXTURE_PREFIX}-leaf.pem' '$CA_CERT' > '$FULLCHAIN'
    chmod 600 '$CA_KEY' '$LEAF_KEY'
    rm -f '/tmp/${FIXTURE_PREFIX}-leaf.csr' '/tmp/${FIXTURE_PREFIX}-leaf.ext' '/tmp/${FIXTURE_PREFIX}-leaf.pem' '${FIXTURE_DIR}/${FIXTURE_PREFIX}-test-ca.srl'
"

log "==> installing trusted leaf as the public reverse-proxy certificate"
app_exec "cp -f '$FULLCHAIN' '$PUBLIC_CERT' && cp -f '$LEAF_KEY' '$PUBLIC_KEY' && chown www-data:www-data '$PUBLIC_CERT' '$PUBLIC_KEY' && chmod 644 '$PUBLIC_CERT' && chmod 600 '$PUBLIC_KEY'"
reload_public_tls

public_presents_pilot() {
    echo | timeout 5 openssl s_client -connect "127.0.0.1:${HTTPS_PORT}" -servername "$PILOT_HOSTNAME" 2>/dev/null \
        | openssl x509 -noout -subject | grep -q "$PILOT_HOSTNAME"
}
if harness_retry 8 1 -- public_presents_pilot; then
    harness_ok "public reverse-proxy now presents the trusted test certificate" "subject matches ${PILOT_HOSTNAME}"
else
    harness_bad "public reverse-proxy now presents the trusted test certificate" "not presented after install+reload"
fi

log "==> wss-cert-check classifies the trusted public certificate correctly"
OUT="$(WSS_PUBLIC_HOSTNAME="$PILOT_HOSTNAME" check --hostname "$PILOT_HOSTNAME" --ca "$CA_CERT" --pilot)"; OUT_RC=$?
if echo "$OUT" | grep -q '^TRUST_STATE: TRUSTED' && [ "$OUT_RC" -eq 0 ] && echo "$OUT" | grep -q '^PILOT_ACCEPTANCE: PILOT_ACCEPTABLE'; then
    harness_ok "trusted production-style certificate classified TRUSTED/PILOT_ACCEPTABLE" "$(echo "$OUT" | grep -E '^TRUST_STATE:|^PILOT_ACCEPTANCE:')"
else
    harness_bad "trusted production-style certificate classified TRUSTED/PILOT_ACCEPTABLE" "exit=$OUT_RC $(echo "$OUT" | grep -E '^TRUST_STATE:|^PILOT_ACCEPTANCE:|^CA_VERIFIED:|^FIXTURE:')"
fi

CHAIN_DEPTH="$(echo "$OUT" | grep '^CHAIN_DEPTH:' | awk '{print $2}')"
if [ "${CHAIN_DEPTH:-0}" -ge 2 ] 2>/dev/null; then
    harness_ok "full certificate chain served" "chain depth=$CHAIN_DEPTH (leaf+CA)"
else
    harness_bad "full certificate chain served" "expected chain depth >= 2, got: ${CHAIN_DEPTH:-unknown}"
fi

log "==> creating a real PJSIP extension pinned to the wss signaling transport"
if create_wss_extension; then
    harness_ok "wss extension created" "exten=${TEST_EXT}"
else
    harness_blocked "could not create the ${TEST_EXT} wss extension fixture"
fi
harness_register_cleanup "extension ${TEST_EXT}" "delete_extension"

log "==> exporting the test CA for the verified WSS client"
APP_CID="$($COMPOSE ps -q app)"
docker cp "${APP_CID}:${CA_CERT}" "$HOST_SCRATCH/test-ca.pem" >/dev/null

log "==> real trusted-client SIP REGISTER over verified public WSS"
REGISTER_OUT="$(docker run --rm --network host \
    -v "$HOST_SCRATCH/test-ca.pem:/ca/test-ca.pem:ro" \
    "$WSS_CLIENT_IMAGE" \
    --host 127.0.0.1 --port "$HTTPS_PORT" --path "$PUBLIC_PATH" --mode register \
    --ext "$TEST_EXT" --secret "$TEST_EXT_SECRET" \
    --ca-file /ca/test-ca.pem --verify-hostname "$PILOT_HOSTNAME" 2>&1 || true)"
log "$REGISTER_OUT"
if echo "$REGISTER_OUT" | grep -q '^HANDSHAKE_OK$' \
    && echo "$REGISTER_OUT" | grep -q '^REGISTER_OK$'; then
    harness_ok "trusted-client SIP REGISTER over verified WSS succeeded" "TLS verification enabled, handshake+REGISTER both OK"
else
    harness_bad "trusted-client SIP REGISTER over verified WSS succeeded" "see logged client output above"
fi

# =============================================================================
# 5. Stale public certificate without proxy reload
# =============================================================================

log "==> simulating out-of-band renewal of public-wss.crt without Apache reload"
# Renew with the SAME public hostname/SAN as the live leaf so
# HOSTNAME_MISMATCH does not mask the fingerprint drift. Configured
# fingerprint moves; Apache keeps the previous in-memory certificate
# until apache2ctl graceful -> RUNTIME_MISMATCH (not PAIR_MISMATCH).
app_exec "openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout '${FIXTURE_DIR}/${FIXTURE_PREFIX}-renewed-key.pem' \
    -out '${FIXTURE_DIR}/${FIXTURE_PREFIX}-renewed-cert.pem' -days 3650 \
    -subj '/CN=${PILOT_HOSTNAME}' \
    -addext 'subjectAltName=DNS:${PILOT_HOSTNAME}' >/dev/null 2>&1; \
    cp -f '${FIXTURE_DIR}/${FIXTURE_PREFIX}-renewed-cert.pem' '$PUBLIC_CERT'; \
    cp -f '${FIXTURE_DIR}/${FIXTURE_PREFIX}-renewed-key.pem' '$PUBLIC_KEY'; \
    chown www-data:www-data '$PUBLIC_CERT' '$PUBLIC_KEY'; chmod 644 '$PUBLIC_CERT'; chmod 600 '$PUBLIC_KEY'"

OUT="$(WSS_PUBLIC_HOSTNAME="$PILOT_HOSTNAME" check --hostname "$PILOT_HOSTNAME")"
if echo "$OUT" | grep -q '^RUNTIME_MATCH: RUNTIME_MISMATCH'; then
    harness_ok "stale runtime certificate detected (RUNTIME_MISMATCH)" "$(echo "$OUT" | grep -E '^SUBJECT:|^TRUST_STATE:|^RUNTIME_MATCH:')"
else
    harness_bad "stale runtime certificate detected (RUNTIME_MISMATCH)" "$(echo "$OUT" | grep -E '^SUBJECT:|^TRUST_STATE:|^RUNTIME_MATCH:')"
fi

log "==> apache2ctl graceful converges runtime to MATCH"
reload_public_tls
converged_to_match() {
    local out
    out="$(WSS_PUBLIC_HOSTNAME="$PILOT_HOSTNAME" check --hostname "$PILOT_HOSTNAME")"
    [[ "$out" == *$'\n'"RUNTIME_MATCH: MATCH"* ]]
}
if harness_retry 15 2 -- converged_to_match; then
    harness_ok "proxy reload recovery converges to MATCH" "apache2ctl graceful confirmed sufficient"
else
    harness_bad "proxy reload recovery converges to MATCH" "not confirmed: $(WSS_PUBLIC_HOSTNAME="$PILOT_HOSTNAME" check --hostname "$PILOT_HOSTNAME" | grep -E '^RUNTIME_MATCH:|^TRUST_STATE:')"
fi

# =============================================================================
# 6. Restore + no committed secrets
# =============================================================================

log "==> restoring the original public WSS fixture certificate"
restore_public_cert
public_restored() {
    echo | timeout 5 openssl s_client -connect "127.0.0.1:${HTTPS_PORT}" -servername localhost 2>/dev/null \
        | openssl x509 -noout -subject | grep -qi 'senma-public-wss-dev'
}
if harness_retry 10 2 -- public_restored; then
    harness_ok "original public WSS fixture certificate is live again" "confirmed via a fresh TLS handshake"
else
    harness_bad "original public WSS fixture certificate is live again" "handshake did not present the original fixture"
fi

FINAL_SHAPE="$(db_query "SELECT CONCAT(protocol,':',bind_port,':',COALESCE(cert_file,'')) FROM pjsip_transports WHERE id=${WSS_ID};")"
if [ "$FINAL_SHAPE" = "ws:8088:" ]; then
    harness_ok "seeded websocket row left in proxy-backend shape" "$FINAL_SHAPE"
else
    harness_bad "seeded websocket row left in proxy-backend shape" "expected ws:8088:, got $FINAL_SHAPE"
fi

log "==> confirming no certificate/private key material is tracked by git"
TRACKED_KEYS="$(git -C "$SCRIPT_DIR/.." ls-files | grep -E '\.(pem|key|crt)$' || true)"
if [ -z "$TRACKED_KEYS" ]; then
    harness_ok "no committed certificate/key fixtures" "git ls-files has no .pem/.key/.crt files"
else
    harness_bad "no committed certificate/key fixtures" "found tracked files: $TRACKED_KEYS"
fi

harness_complete
