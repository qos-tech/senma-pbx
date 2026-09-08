#!/bin/bash
#
# SENMA production WSS certificate trust / runtime verification smoke
# test (TASK-0034E, closing TASK-0034's Finding CH-2).
#
# TASK-0028Z proved the WSS platform path works. TASK-0029A gave SENMA a
# real certificate-ownership model (path references, never bytes). Both
# left a real gap TASK-0034 (the release-readiness audit) named as
# Finding CH-2: nothing proves WHICH certificate the live WSS listener
# is actually presenting, nothing distinguishes a dev-fixture/self-signed
# certificate from a production-trusted one, and nothing proves a real
# client can connect with certificate verification actually ENABLED. This
# suite proves the tool that closes that gap
# (scripts/wss-cert-check.sh + scripts/lib/wss-cert-lib.sh) against real,
# live evidence:
#
#   1. the current dev-fixture certificate is correctly classified
#      FIXTURE + NOT_ACCEPTABLE_FOR_PILOT (Phase 47's own explicit
#      requirement -- the protocol works, but that alone must not
#      satisfy the pilot gate);
#   2. missing cert/key -> MISSING;
#   3. a genuinely mismatched cert/key pair -> PAIR_MISMATCH, with no
#      private key bytes ever appearing in the tool's own output;
#   4. a certificate valid for a different hostname -> HOSTNAME_MISMATCH;
#   5. an already-expired certificate (generated with a backdated
#      validity window -- the system clock is never touched) -> EXPIRED;
#   6. a real, ephemeral, test-only CA issues a certificate for a real
#      pilot-style hostname; the live `wss` transport is rotated to it
#      through SENMA's own real HTTP edit-form flow (the same mechanism
#      TASK-0029A already proved); scripts/wss-cert-check.sh classifies
#      it TRUSTED/PILOT_ACCEPTABLE; and a real SIP-over-WSS REGISTER
#      succeeds over a TLS connection with certificate verification
#      ACTUALLY ENABLED (never CERT_NONE, never -k/--insecure) --
#      TASK-0034 CH-2's own closure requirement;
#   7. a fullchain (leaf+CA) certificate file is served and its full
#      chain depth is confirmed reachable (Phase 14);
#   8. the configured certificate file changes on disk (an operator
#      renewing a certificate in place, bypassing SENMA entirely) while
#      Asterisk keeps serving the old one -> RUNTIME_MISMATCH; the
#      documented `module reload http` recovery converges it to MATCH
#      (TASK-0029A's own reload contract, re-verified against the
#      current Asterisk version -- Phase 24/48);
#   9. no certificate/private key material (including this suite's own
#      ephemeral test-CA/leaf material) is committed to this repository.
#
# Every negative-case fixture (missing/mismatched/expired/hostname
# cases) uses isolated file paths inspected via --cert/--key/--hostname/
# --no-runtime overrides -- the live `wss` pjsip_transports row is only
# ever touched through the real HTTP edit-form flow (items 6/8 above),
# exactly like scripts/tls-cert-management-smoke-test.sh's own rotation
# proof, and is always restored to its original value before this
# suite completes.
#
# See docs/tasks/0034e-production-wss-certificate-trust-runtime-verification.md.
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
# shellcheck source=lib/wss-cert-lib.sh
source "$SCRIPT_DIR/lib/wss-cert-lib.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
BASE_URL="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
TEST_USER="admin"
TEST_PASSWORD="SmokeTest123!"

KEY_DIR="/etc/asterisk/keys"
FIXTURE_PREFIX="task0034e"
PILOT_HOSTNAME="task0034e-pilot.test"
TEST_EXT=1197
TEST_EXT_SECRET="${FIXTURE_PREFIX}-ext"

WSS_CLIENT_IMAGE="senma-wss-test-client:latest"
WSS_CLIENT_DOCKERFILE="wss-test-client.Dockerfile"

HOST_SCRATCH="$(mktemp -d)"
harness_register_best_effort_cleanup "host scratch dir ($HOST_SCRATCH)" "rm -rf '$HOST_SCRATCH'"

COOKIEJAR=""
WSS_ID=""
ORIGINAL_CERT=""
ORIGINAL_KEY=""
ORIGINAL_CA=""
NETWORK_NAME=""
ASTERISK_SVC_NAME=""

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

check() {
    # check.sh args... -- runs scripts/wss-cert-check.sh with $COMPOSE
    # already exported for wcl_asterisk_exec to reuse.
    SMOKE_COMPOSE="$COMPOSE" bash "$SCRIPT_DIR/wss-cert-check.sh" "$@"
}

# save_transport <url-suffix> <cert> <key> <ca> -- edits the live "wss"
# transport through the real HTTP form (same mechanism/idiom as
# scripts/tls-cert-management-smoke-test.sh's own save_transport()).
save_transport() {
    local urlSuffix="$1" cert="$2" key="$3" ca="$4" body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "name=wss" \
        --data-urlencode "protocol=wss" \
        --data-urlencode "bind_address=0.0.0.0" \
        --data-urlencode "bind_port=8089" \
        --data-urlencode "domain=" \
        --data-urlencode "external_signaling_address=" \
        --data-urlencode "external_signaling_port=" \
        --data-urlencode "external_media_address=" \
        --data-urlencode "local_net=" \
        --data-urlencode "allow_reload=1" \
        --data-urlencode "enabled=1" \
        --data-urlencode "cert_file=${cert}" \
        --data-urlencode "priv_key_file=${key}" \
        --data-urlencode "ca_list_file=${ca}" \
        --data-urlencode "method=" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/pjsip-transports/${urlSuffix}")"
    rm -f "$body"
    [ "$httpcode" = "302" ]
}

restore_wss_transport() {
    save_transport "edit/id/${WSS_ID}" "$ORIGINAL_CERT" "$ORIGINAL_KEY" "$ORIGINAL_CA"
    asterisk_exec "asterisk -rx 'module reload http'" >/dev/null 2>&1
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

# =============================================================================
# 1. Preconditions + leftover-fixture recovery
# =============================================================================

log "==> checking required containers"
harness_require_containers app asterisk db
harness_require_env DB_USER DB_PASSWORD DB_NAME

log "==> removing any leftover isolated fixture files from a prior interrupted run"
asterisk_exec "rm -f ${KEY_DIR}/${FIXTURE_PREFIX}-*.pem" 2>/dev/null || true
LEFTOVER_EXT="$(db_query "SELECT exten FROM peers WHERE exten='${TEST_EXT}';" 2>/dev/null || true)"
if [ -n "$LEFTOVER_EXT" ]; then
    db_query "DELETE FROM peers WHERE exten='${TEST_EXT}';" >/dev/null 2>&1 || true
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
ORIGINAL_CERT="$(db_query "SELECT COALESCE(cert_file,'') FROM pjsip_transports WHERE id=${WSS_ID};")"
ORIGINAL_KEY="$(db_query "SELECT COALESCE(priv_key_file,'') FROM pjsip_transports WHERE id=${WSS_ID};")"
ORIGINAL_CA="$(db_query "SELECT COALESCE(ca_list_file,'') FROM pjsip_transports WHERE id=${WSS_ID};")"
log "wss transport id=${WSS_ID}, original cert=${ORIGINAL_CERT}"
harness_register_cleanup "wss transport restored to its original certificate" "restore_wss_transport"

ASTERISK_CID="$($COMPOSE ps -q asterisk)"
ASTERISK_SVC_NAME="$(docker inspect "$ASTERISK_CID" --format '{{index .Config.Labels "com.docker.compose.service"}}')"
NETWORK_NAME="$(harness_asterisk_test_network "$ASTERISK_CID")"
if [ -z "$NETWORK_NAME" ] || [ "$ASTERISK_SVC_NAME" != "asterisk" ]; then
    harness_blocked "could not resolve the asterisk container's compose network/service name"
fi

log "==> building $WSS_CLIENT_IMAGE from $WSS_CLIENT_DOCKERFILE"
if ! harness_timeout 120 docker build -q -t "$WSS_CLIENT_IMAGE" -f "docker/$WSS_CLIENT_DOCKERFILE" docker >&2; then
    harness_blocked "failed to build $WSS_CLIENT_IMAGE within 120s"
fi

# =============================================================================
# 2. Fixture classification (Phase 16/47) -- the CURRENT live default
#    must classify as a fixture and fail the pilot gate, even though the
#    protocol itself works.
# =============================================================================

log "==> baseline: current live wss certificate is the dev fixture"
BASELINE="$(check)"
if echo "$BASELINE" | grep -q '^FIXTURE: yes' && echo "$BASELINE" | grep -q '^TRUST_STATE: SELF_SIGNED'; then
    harness_ok "dev-fixture certificate classified as FIXTURE" "$(echo "$BASELINE" | grep '^FIXTURE:')"
else
    harness_bad "dev-fixture certificate classified as FIXTURE" "unexpected: $(echo "$BASELINE" | grep -E '^FIXTURE:|^TRUST_STATE:')"
fi

BASELINE_PILOT="$(check --pilot)"; BASELINE_PILOT_RC=$?
if [ $BASELINE_PILOT_RC -ne 0 ] && echo "$BASELINE_PILOT" | grep -q 'NOT_ACCEPTABLE_FOR_PILOT'; then
    harness_ok "fixture certificate rejected by the pilot gate (Phase 47)" "$(echo "$BASELINE_PILOT" | grep '^PILOT_ACCEPTANCE:')"
else
    harness_bad "fixture certificate rejected by the pilot gate (Phase 47)" "exit=$BASELINE_PILOT_RC: $(echo "$BASELINE_PILOT" | grep '^PILOT_ACCEPTANCE:')"
fi

# =============================================================================
# 3. Missing certificate/key (Phase 19)
# =============================================================================

log "==> missing certificate file -> MISSING"
OUT="$(check --cert "${KEY_DIR}/${FIXTURE_PREFIX}-does-not-exist.pem" --key "${KEY_DIR}/${FIXTURE_PREFIX}-does-not-exist-key.pem" --no-runtime)"
if echo "$OUT" | grep -q '^TRUST_STATE: MISSING'; then
    harness_ok "missing cert/key classified MISSING" "$(echo "$OUT" | grep '^TRUST_STATE:')"
else
    harness_bad "missing cert/key classified MISSING" "$(echo "$OUT" | grep '^TRUST_STATE:')"
fi

# =============================================================================
# 4. Mismatched cert/key pair (Phase 20) -- and no key material leaks
# =============================================================================

log "==> generating a mismatched cert/key pair (individually valid, wrong pairing)"
asterisk_exec "openssl req -x509 -newkey rsa:2048 -nodes -keyout ${KEY_DIR}/${FIXTURE_PREFIX}-mismatch-a-key.pem -out ${KEY_DIR}/${FIXTURE_PREFIX}-mismatch-a-cert.pem -days 3650 -subj '/CN=${FIXTURE_PREFIX}-mismatch-a' -addext 'subjectAltName=DNS:${FIXTURE_PREFIX}-mismatch-a' >/dev/null 2>&1"
asterisk_exec "openssl req -x509 -newkey rsa:2048 -nodes -keyout ${KEY_DIR}/${FIXTURE_PREFIX}-mismatch-b-key.pem -out ${KEY_DIR}/${FIXTURE_PREFIX}-mismatch-b-cert.pem -days 3650 -subj '/CN=${FIXTURE_PREFIX}-mismatch-b' -addext 'subjectAltName=DNS:${FIXTURE_PREFIX}-mismatch-b' >/dev/null 2>&1"
harness_register_best_effort_cleanup "mismatch-a/b fixture certs" "asterisk_exec 'rm -f ${KEY_DIR}/${FIXTURE_PREFIX}-mismatch-*.pem'"

OUT="$(check --cert "${KEY_DIR}/${FIXTURE_PREFIX}-mismatch-a-cert.pem" --key "${KEY_DIR}/${FIXTURE_PREFIX}-mismatch-b-key.pem" --no-runtime --pilot)"
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

# =============================================================================
# 5. Hostname mismatch (Phase 22)
# =============================================================================

log "==> hostname mismatch: certificate valid for a different host"
OUT="$(check --cert "${KEY_DIR}/${FIXTURE_PREFIX}-mismatch-a-cert.pem" --key "${KEY_DIR}/${FIXTURE_PREFIX}-mismatch-a-key.pem" --hostname "${FIXTURE_PREFIX}-some-other-host" --no-runtime --pilot)"
if echo "$OUT" | grep -q '^TRUST_STATE: HOSTNAME_MISMATCH' && echo "$OUT" | grep -q 'NOT_ACCEPTABLE_FOR_PILOT'; then
    harness_ok "certificate/hostname mismatch classified HOSTNAME_MISMATCH" "$(echo "$OUT" | grep '^TRUST_STATE:')"
else
    harness_bad "certificate/hostname mismatch classified HOSTNAME_MISMATCH" "$(echo "$OUT" | grep -E '^TRUST_STATE:|^PILOT_ACCEPTANCE:')"
fi

log "==> matching hostname is accepted"
OUT="$(check --cert "${KEY_DIR}/${FIXTURE_PREFIX}-mismatch-a-cert.pem" --key "${KEY_DIR}/${FIXTURE_PREFIX}-mismatch-a-key.pem" --hostname "${FIXTURE_PREFIX}-mismatch-a" --no-runtime)"
if echo "$OUT" | grep -q '^HOSTNAME_MATCH: yes'; then
    harness_ok "matching hostname accepted" "$(echo "$OUT" | grep '^HOSTNAME_MATCH:')"
else
    harness_bad "matching hostname accepted" "$(echo "$OUT" | grep '^HOSTNAME_MATCH:')"
fi

# =============================================================================
# 6. Expired certificate (Phase 21) -- backdated validity window, system
#    clock never touched
# =============================================================================

log "==> generating an already-expired certificate (backdated notBefore/notAfter)"
asterisk_exec "openssl req -x509 -newkey rsa:2048 -nodes -keyout ${KEY_DIR}/${FIXTURE_PREFIX}-expired-key.pem -out ${KEY_DIR}/${FIXTURE_PREFIX}-expired-cert.pem -subj '/CN=${FIXTURE_PREFIX}-expired' -not_before 20200101000000Z -not_after 20200201000000Z -addext 'subjectAltName=DNS:${FIXTURE_PREFIX}-expired' >/dev/null 2>&1"
harness_register_best_effort_cleanup "expired fixture cert" "asterisk_exec 'rm -f ${KEY_DIR}/${FIXTURE_PREFIX}-expired-*.pem'"
OUT="$(check --cert "${KEY_DIR}/${FIXTURE_PREFIX}-expired-cert.pem" --key "${KEY_DIR}/${FIXTURE_PREFIX}-expired-key.pem" --no-runtime --pilot)"
if echo "$OUT" | grep -q '^TRUST_STATE: EXPIRED' && echo "$OUT" | grep -q 'NOT_ACCEPTABLE_FOR_PILOT'; then
    harness_ok "expired certificate classified EXPIRED" "$(echo "$OUT" | grep '^TRUST_STATE:')"
else
    harness_bad "expired certificate classified EXPIRED" "$(echo "$OUT" | grep -E '^TRUST_STATE:|^PILOT_ACCEPTANCE:')"
fi

log "==> generating a not-yet-valid certificate (backdated notBefore in the future)"
asterisk_exec "openssl req -x509 -newkey rsa:2048 -nodes -keyout ${KEY_DIR}/${FIXTURE_PREFIX}-nyv-key.pem -out ${KEY_DIR}/${FIXTURE_PREFIX}-nyv-cert.pem -subj '/CN=${FIXTURE_PREFIX}-nyv' -not_before 20991231000000Z -not_after 21001231000000Z -addext 'subjectAltName=DNS:${FIXTURE_PREFIX}-nyv' >/dev/null 2>&1"
harness_register_best_effort_cleanup "not-yet-valid fixture cert" "asterisk_exec 'rm -f ${KEY_DIR}/${FIXTURE_PREFIX}-nyv-*.pem'"
OUT="$(check --cert "${KEY_DIR}/${FIXTURE_PREFIX}-nyv-cert.pem" --key "${KEY_DIR}/${FIXTURE_PREFIX}-nyv-key.pem" --no-runtime --pilot)"
if echo "$OUT" | grep -q '^TRUST_STATE: NOT_YET_VALID' && echo "$OUT" | grep -q 'NOT_ACCEPTABLE_FOR_PILOT'; then
    harness_ok "not-yet-valid certificate classified NOT_YET_VALID" "$(echo "$OUT" | grep '^TRUST_STATE:')"
else
    harness_bad "not-yet-valid certificate classified NOT_YET_VALID" "$(echo "$OUT" | grep -E '^TRUST_STATE:|^PILOT_ACCEPTANCE:')"
fi

# =============================================================================
# 7. Production-like trusted proof (Phase 29/42/46) -- real ephemeral
#    test CA, real hostname, real rotation through SENMA's own edit
#    form, real verified TLS client, real SIP REGISTER.
# =============================================================================

log "==> generating an ephemeral test CA + leaf certificate for ${PILOT_HOSTNAME} (inside the asterisk container, as the 'asterisk' user -- same convention as every other fixture cert in this repo; never committed)"
CA_CERT="${KEY_DIR}/${FIXTURE_PREFIX}-test-ca.pem"
CA_KEY="${KEY_DIR}/${FIXTURE_PREFIX}-test-ca-key.pem"
LEAF_KEY="${KEY_DIR}/${FIXTURE_PREFIX}-trusted-key.pem"
FULLCHAIN="${KEY_DIR}/${FIXTURE_PREFIX}-trusted-cert.pem"
asterisk_exec "
    set -e
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout '$CA_KEY' -out '$CA_CERT' \
        -days 30 -subj '/CN=SENMA Test CA (${FIXTURE_PREFIX})' \
        -addext 'basicConstraints=critical,CA:true' -addext 'keyUsage=critical,keyCertSign,cRLSign' >/dev/null 2>&1
    openssl req -newkey rsa:2048 -nodes \
        -keyout '$LEAF_KEY' -out '/tmp/${FIXTURE_PREFIX}-leaf-csr.pem' \
        -subj '/CN=${PILOT_HOSTNAME}' >/dev/null 2>&1
    printf 'subjectAltName=DNS:%s\nbasicConstraints=CA:false\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n' '${PILOT_HOSTNAME}' > '/tmp/${FIXTURE_PREFIX}-leaf-ext.cnf'
    openssl x509 -req -in '/tmp/${FIXTURE_PREFIX}-leaf-csr.pem' \
        -CA '$CA_CERT' -CAkey '$CA_KEY' -CAcreateserial \
        -out '/tmp/${FIXTURE_PREFIX}-leaf-cert.pem' -days 30 -extfile '/tmp/${FIXTURE_PREFIX}-leaf-ext.cnf' >/dev/null 2>&1
    cat '/tmp/${FIXTURE_PREFIX}-leaf-cert.pem' '$CA_CERT' > '$FULLCHAIN'
    rm -f '/tmp/${FIXTURE_PREFIX}-leaf-csr.pem' '/tmp/${FIXTURE_PREFIX}-leaf-ext.cnf' '/tmp/${FIXTURE_PREFIX}-leaf-cert.pem' '${KEY_DIR}/${FIXTURE_PREFIX}-test-ca.srl'
    chmod 600 '$CA_KEY' '$LEAF_KEY'
"
harness_register_best_effort_cleanup "trusted-proof fixture certs" "asterisk_exec 'rm -f ${KEY_DIR}/${FIXTURE_PREFIX}-trusted-*.pem ${KEY_DIR}/${FIXTURE_PREFIX}-test-ca*.pem'"

if ! wcl_file_exists "$FULLCHAIN" || ! wcl_file_exists "$LEAF_KEY"; then
    harness_blocked "failed to generate the ephemeral test CA/leaf certificate inside the asterisk container"
fi

log "==> copying the test CA's public certificate to the host (read-only export, for the separate wss-test-client container to trust)"
ASTERISK_CID="$($COMPOSE ps -q asterisk)"
docker cp "${ASTERISK_CID}:${CA_CERT}" "$HOST_SCRATCH/test-ca-cert.pem" >/dev/null

log "==> rotating the live wss transport to the trusted fullchain cert through the real edit form"
if ! save_transport "edit/id/${WSS_ID}" "${KEY_DIR}/${FIXTURE_PREFIX}-trusted-cert.pem" "${KEY_DIR}/${FIXTURE_PREFIX}-trusted-key.pem" "${KEY_DIR}/${FIXTURE_PREFIX}-test-ca.pem"; then
    harness_blocked "could not rotate the wss transport to the trusted test certificate"
fi

wss_serves_trusted() {
    asterisk_exec "echo | timeout 3 openssl s_client -connect localhost:8089 2>/dev/null | grep subject=" | grep -q "${PILOT_HOSTNAME}"
}
if harness_retry 5 1 -- wss_serves_trusted; then
    harness_ok "live WSS listener now presents the trusted test certificate" "subject matches ${PILOT_HOSTNAME}"
else
    harness_bad "live WSS listener now presents the trusted test certificate" "not presented after rotation"
fi

log "==> wss-cert-check classifies the trusted certificate correctly"
OUT="$(WSS_PUBLIC_HOSTNAME="$PILOT_HOSTNAME" check --pilot)"; OUT_RC=$?
if echo "$OUT" | grep -q '^TRUST_STATE: TRUSTED' && [ $OUT_RC -eq 0 ] && echo "$OUT" | grep -q '^PILOT_ACCEPTANCE: PILOT_ACCEPTABLE'; then
    harness_ok "trusted production-style certificate classified TRUSTED/PILOT_ACCEPTABLE" "$(echo "$OUT" | grep -E '^TRUST_STATE:|^PILOT_ACCEPTANCE:')"
else
    harness_bad "trusted production-style certificate classified TRUSTED/PILOT_ACCEPTABLE" "exit=$OUT_RC $(echo "$OUT" | grep -E '^TRUST_STATE:|^PILOT_ACCEPTANCE:|^CA_VERIFIED:')"
fi

log "==> full certificate chain is served (Phase 14 -- fullchain format)"
CHAIN_DEPTH="$(echo "$OUT" | grep '^CHAIN_DEPTH:' | awk '{print $2}')"
if [ "${CHAIN_DEPTH:-0}" -ge 2 ] 2>/dev/null; then
    harness_ok "full certificate chain served" "chain depth=$CHAIN_DEPTH (leaf+CA)"
else
    harness_bad "full certificate chain served" "expected chain depth >= 2, got: ${CHAIN_DEPTH:-unknown}"
fi

log "==> creating a real PJSIP extension pinned to the wss transport"
if create_wss_extension; then
    harness_ok "wss extension created" "exten=${TEST_EXT}"
else
    harness_blocked "could not create the ${TEST_EXT} wss extension fixture"
fi
harness_register_cleanup "extension ${TEST_EXT} (task0034e fixture)" "delete_extension"

log "==> real trusted-client SIP REGISTER over verified WSS (certificate verification ENABLED, never CERT_NONE/-k/--insecure)"
REGISTER_OUT="$(docker run --rm --network "$NETWORK_NAME" \
    -v "$HOST_SCRATCH/test-ca-cert.pem:/ca/test-ca.pem:ro" \
    "$WSS_CLIENT_IMAGE" \
    --host "$ASTERISK_SVC_NAME" --port 8089 --mode register \
    --ext "$TEST_EXT" --secret "$TEST_EXT_SECRET" \
    --ca-file /ca/test-ca.pem --verify-hostname "$PILOT_HOSTNAME" 2>&1)"
log "$REGISTER_OUT"
if echo "$REGISTER_OUT" | grep -q '^TLS_VERIFY_MODE: CERT_REQUIRED' \
    && echo "$REGISTER_OUT" | grep -q '^HANDSHAKE_OK$' \
    && echo "$REGISTER_OUT" | grep -q '^REGISTER_OK$'; then
    harness_ok "trusted-client SIP REGISTER over verified WSS succeeded" "TLS verification enabled, handshake+REGISTER both OK"
else
    harness_bad "trusted-client SIP REGISTER over verified WSS succeeded" "see logged client output above"
fi

# =============================================================================
# 8. Runtime stale-certificate proof (Phase 23/48) -- an operator
#    replaces the certificate bytes at the SAME configured path without
#    going through SENMA at all (no edit-form call, no reload) --
#    Asterisk keeps serving the old certificate until reloaded.
# =============================================================================

log "==> simulating an out-of-band certificate renewal at the same configured path (no SENMA edit, no reload)"
asterisk_exec "openssl req -x509 -newkey rsa:2048 -nodes -keyout '$LEAF_KEY' -out '$FULLCHAIN' -days 3650 -subj '/CN=${FIXTURE_PREFIX}-renewed' -addext 'subjectAltName=DNS:${FIXTURE_PREFIX}-renewed' >/dev/null 2>&1; chmod 600 '$LEAF_KEY'"

OUT="$(check)"
if echo "$OUT" | grep -q '^TRUST_STATE: RUNTIME_MISMATCH' && echo "$OUT" | grep -q '^RUNTIME_MATCH: RUNTIME_MISMATCH'; then
    harness_ok "stale runtime certificate detected (RUNTIME_MISMATCH)" "$(echo "$OUT" | grep -E '^SUBJECT:|^TRUST_STATE:')"
else
    harness_bad "stale runtime certificate detected (RUNTIME_MISMATCH)" "$(echo "$OUT" | grep -E '^SUBJECT:|^TRUST_STATE:|^RUNTIME_MATCH:')"
fi

log "==> the documented reload recovery ('module reload http') converges runtime to MATCH (Phase 24)"
converged_to_match() {
    # Captures check()'s output into a variable FIRST, then matches
    # against the captured string -- never `check | grep -q ...`
    # directly. `check` is a slow, multi-line-writing subprocess (many
    # docker execs); piping it straight into `grep -q` lets grep exit
    # the instant it sees the RUNTIME_MATCH line, closing the pipe while
    # `check` is still writing its own remaining output (TRUST_STATE/
    # PILOT_ACCEPTANCE) -- a real, reproducible SIGPIPE that makes
    # check's own process exit 141 under this script's `pipefail`,
    # which harness_retry then (wrongly) reads as "not converged yet"
    # on every single attempt, deterministically, regardless of the
    # actual certificate state. Confirmed as the actual root cause of an
    # initially-mystifying "always fails here, converges instantly in
    # every isolated manual reproduction" symptom during this task.
    local out
    out="$(check)"
    [[ "$out" == *$'\n'"RUNTIME_MATCH: MATCH"* ]]
}
asterisk_exec "asterisk -rx 'module reload http'" >/dev/null 2>&1
# Live finding (TASK-0034E): scripts/wss-cert-check.sh's own runtime peek
# (a fresh `docker compose exec` + real TLS connection per call) was
# observed, under this suite's own heavy concurrent Docker load
# (immediately after a docker build + a throwaway container run for the
# verified SIP-over-WSS proof above), to occasionally read a transiently
# stale/unreachable result on an individual poll even though the
# underlying certificate had already converged -- confirmed separately,
# deterministically 10/10, that scripts/wss-cert-check.sh itself is
# consistent when polled in isolation under normal load, and that
# 'module reload http' converges the actual runtime certificate
# immediately (single reload, no delay) in manual, isolated
# reproduction. This matches this project's own already-documented class
# of transient, harness-level polling flakiness under concurrent load
# (docs/tasks/0034-release-readiness-production-pilot-gate.md §44) --
# retried here, not treated as a silent pass, and never masked by an
# unconditional sleep.
if harness_retry 15 2 -- converged_to_match; then
    harness_ok "reload recovery converges to MATCH" "module reload http confirmed sufficient on this Asterisk version"
else
    harness_bad "reload recovery converges to MATCH" "not confirmed within the retry window: $(check | grep -E '^RUNTIME_MATCH:|^CONFIGURED_FINGERPRINT|^RUNTIME_FINGERPRINT')"
fi

# =============================================================================
# 9. Restore + no committed secrets
# =============================================================================

log "==> restoring the wss transport to its original certificate"
if restore_wss_transport; then
    harness_ok "wss transport restored" "cert_file=${ORIGINAL_CERT}"
else
    harness_bad "wss transport restored" "restore_wss_transport failed"
fi
wss_restored() {
    asterisk_exec "echo | timeout 3 openssl s_client -connect localhost:8089 2>/dev/null | grep subject=" | grep -q "senma-wss-test"
}
if harness_retry 10 2 -- wss_restored; then
    harness_ok "original dev-fixture certificate is live again" "confirmed via a fresh TLS handshake"
else
    harness_bad "original dev-fixture certificate is live again" "handshake did not present the original certificate"
fi

log "==> confirming no certificate/private key material is tracked by git"
TRACKED_KEYS="$(git -C "$SCRIPT_DIR/.." ls-files | grep -E '\.(pem|key|crt)$' || true)"
if [ -z "$TRACKED_KEYS" ]; then
    harness_ok "no committed certificate/key fixtures" "git ls-files has no .pem/.key/.crt files"
else
    harness_bad "no committed certificate/key fixtures" "found tracked files: $TRACKED_KEYS"
fi

harness_complete
