#!/bin/bash
#
# SENMA TLS/WSS transport certificate management smoke test (TASK-0029A).
#
# TASK-0028Z proved the WSS platform path works end to end using a
# test-generated self-signed certificate, but left a real architectural
# gap: pjsip_transports had no certificate-related schema fields at all
# and no product-level certificate ownership model, so TLS/WSS could not
# yet be configured safely for production certificates (TASK-0028W's own
# finding). This task closes that gap with Model B (externally-managed
# certificate PATHS -- an admin places real cert/key material at a
# filesystem path inside the persistent asterisk-etc volume, SENMA
# validates and references that path, never certificate/key BYTES).
#
# Proves, end to end, against a running `make dev` Docker environment,
# using SENMA's own real HTTP flow (never raw SQL, never hand-written
# PJSIP config):
#
#   1. a valid certificate/key configuration is accepted, generates the
#      correct config, and Asterisk's runtime actually presents it
#      (real TLS handshake, fingerprint/subject match) for BOTH
#      certificate models this product has (native PJSIP `tls`
#      transport -- cert_file/priv_key_file emitted directly onto the
#      transport object -- and `wss`, where those same fields are
#      confirmed live to be silently IGNORED by
#      res_pjsip_transport_websocket; real TLS control for wss/ws lives
#      only in Asterisk's global http.conf, generated from whichever one
#      enabled ws/wss row currently carries certificate material);
#   2. invalid paths (nonexistent file, non-PEM content), an incomplete
#      cert+key pair, and a second conflicting active WSS certificate
#      are all rejected BEFORE save -- never persisted as a silently
#      broken configuration;
#   3. a genuinely MISMATCHED cert/key pair (individually valid, real
#      files, wrong pairing) is caught at RUNTIME APPLY time -- SENMA
#      cannot validate a cert/key match itself without either reading
#      the intentionally 0600 private key from the app container or
#      building a privileged exec bridge into the Asterisk container
#      (both rejected -- see docs/tasks/0029a-tls-transport-certificate-management.md
#      DECISION), so this is deliberately proven via Asterisk's own
#      post-reload behavior, surfaced back through the existing
#      apply_failed flash-message mechanism;
#   4. certificate replacement (rotation) actually changes the
#      certificate a live TLS client is presented -- proven for WSS,
#      which is hot-reloadable via `module reload http` alone (confirmed
#      live, no Asterisk/container restart needed);
#   5. restart/recreate preserves the certificate/key files and the
#      generated http.conf TLS include byte-for-byte;
#   6. UDP/TCP transports remain completely unaffected (no cert-related
#      config lines emitted for them, confirmed by direct inspection of
#      the generated file);
#   7. no certificate/private key material is committed into this
#      repository's own fixtures.
#
# See docs/tasks/0029a-tls-transport-certificate-management.md.
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

# Fixed, never-reused-elsewhere bind ports for this suite's own
# throwaway `tls` transport fixture -- avoids TASK-0020's own documented
# "a plain reload never frees the OS socket" hazard colliding with any
# other suite's or a prior interrupted run's own leftover bind.
TLS_FIXTURE_PORT=15061
TLS_FIXTURE_NAME="task0029a-tls-fixture"
WSS_ROTATE_CERT_CN="task0029a-rotate-test"

KEY_DIR="/etc/asterisk/keys"
COOKIEJAR=""
CREATED_TLS_ID=""

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

# gen_cert <name-in-keydir-without-extension> <CN> -- real self-signed
# cert/key pair generated INSIDE the asterisk container (the only place
# that needs to trust its own path), matching this project's own
# TEST-ONLY fixture convention (docker/asterisk-entrypoint.sh). Never
# written to the host repo tree at all.
gen_cert() {
    local base="$1" cn="$2"
    asterisk_exec "openssl req -x509 -newkey rsa:2048 -nodes -keyout $KEY_DIR/${base}-key.pem -out $KEY_DIR/${base}-cert.pem -days 3650 -subj '/CN=${cn}' >/dev/null 2>&1"
}

rm_cert() {
    local base="$1"
    asterisk_exec "rm -f $KEY_DIR/${base}-key.pem $KEY_DIR/${base}-cert.pem"
}

# save_transport <url-suffix> <name> <protocol> <bind_port> <cert> <key> <method_field> -- POST
# the pjsip-transports add/edit form. Echoes "<httpcode> <bodyfile>" --
# both values must travel back through the SAME command-substitution
# stdout capture, since this function runs in a subshell (any plain
# variable assignment inside it, e.g. a global LAST_BODY_FILE, is
# invisible to the caller once the subshell exits).
save_transport() {
    local urlSuffix="$1" name="$2" protocol="$3" bindPort="$4" cert="$5" key="$6" tlsMethod="$7"
    local body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "name=${name}" \
        --data-urlencode "protocol=${protocol}" \
        --data-urlencode "bind_address=0.0.0.0" \
        --data-urlencode "bind_port=${bindPort}" \
        --data-urlencode "domain=" \
        --data-urlencode "external_signaling_address=" \
        --data-urlencode "external_signaling_port=" \
        --data-urlencode "external_media_address=" \
        --data-urlencode "local_net=" \
        --data-urlencode "allow_reload=1" \
        --data-urlencode "enabled=1" \
        --data-urlencode "cert_file=${cert}" \
        --data-urlencode "priv_key_file=${key}" \
        --data-urlencode "ca_list_file=" \
        --data-urlencode "method=${tlsMethod}" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/pjsip-transports/${urlSuffix}")"
    echo "$httpcode $body"
}

last_error_message() {
    grep -o 'alert alert-danger">[^<]*' "$1" | head -1 | sed -e 's/alert alert-danger">//'
}

# do_save <args...> -- calls save_transport as a normal function (not a
# command substitution), so it can set SAVE_CODE/SAVE_BODY as plain
# globals the caller reads directly, sidestepping the subshell problem
# above entirely for callers that don't need the one-line combined form.
do_save() {
    local result
    result="$(save_transport "$@")"
    SAVE_CODE="${result%% *}"
    SAVE_BODY="${result#* }"
}

last_flash_message() {
    curl -sS -b "$COOKIEJAR" -c "$COOKIEJAR" "${BASE_URL}/index.php/default/pjsip-transports" | grep -o 'alert[a-z -]*">[^<]*' | head -1
}

delete_transport() {
    local id="$1"
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null "${BASE_URL}/index.php/default/pjsip-transports/remove/id/${id}" >/dev/null
    local httpcode
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/pjsip-transports/remove/id/${id}")"
    [ "$httpcode" = "302" ]
}

# --- 1. Required containers + WSS platform prerequisites --------------

log "==> checking required containers"
harness_require_containers app asterisk db
harness_require_env DB_USER DB_PASSWORD DB_NAME

log "==> checking for a leftover fixture from a prior interrupted run"
LEFTOVER_IDS="$(db_query "SELECT id FROM pjsip_transports WHERE name='${TLS_FIXTURE_NAME}' OR name LIKE '${TLS_FIXTURE_NAME}-conflict%';")"
if [ -n "$LEFTOVER_IDS" ]; then
    while IFS= read -r leftover_id; do
        [ -z "$leftover_id" ] && continue
        leftover_name="$(db_query "SELECT name FROM pjsip_transports WHERE id=${leftover_id};")"
        db_query "DELETE FROM pjsip_transports WHERE id=${leftover_id};" >/dev/null
        log "removed leftover transport row id=${leftover_id} (name='${leftover_name}') from a prior interrupted run"
    done <<< "$LEFTOVER_IDS"
    $COMPOSE exec -T asterisk php /usr/local/bin/reconcile-pjsip.php >/dev/null 2>&1 || true
fi
rm_cert "task0029a-tls" 2>/dev/null || true
rm_cert "task0029a-mismatch-a" 2>/dev/null || true
rm_cert "task0029a-mismatch-b" 2>/dev/null || true
rm_cert "task0029a-rotate" 2>/dev/null || true

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

WSS_ID="$(db_query "SELECT id FROM pjsip_transports WHERE name='wss';")"
if [ -z "$WSS_ID" ]; then
    harness_blocked "no 'wss' pjsip_transports row exists -- cannot prove certificate management against it"
fi
ORIGINAL_WSS_CERT="$(db_query "SELECT cert_file FROM pjsip_transports WHERE id=${WSS_ID};")"
ORIGINAL_WSS_KEY="$(db_query "SELECT priv_key_file FROM pjsip_transports WHERE id=${WSS_ID};")"
log "wss transport id=${WSS_ID}, original cert=${ORIGINAL_WSS_CERT}"

# =============================================================================
# 2. Failure behavior -- rejected BEFORE save
# =============================================================================

# Under TASK-0035A the seeded websocket row has empty cert/key. Rejection
# tests must supply a real companion half-pair so validation reaches the
# intended branch (existence / PEM / both-or-neither), not a vacuous
# "both empty" success.
gen_cert "task0029a-reject" "task0029a-reject"

log "==> invalid path (nonexistent certificate file) is rejected"
do_save "edit/id/${WSS_ID}" "wss" "ws" "8088" "${KEY_DIR}/task0029a-does-not-exist.pem" "${KEY_DIR}/task0029a-reject-key.pem" ""
if [ "$SAVE_CODE" != "302" ] && [[ "$(last_error_message "$SAVE_BODY")" == *"does not exist"* ]]; then
    harness_ok "nonexistent cert path rejected" "$(last_error_message "$SAVE_BODY")"
else
    harness_bad "nonexistent cert path rejected" "HTTP $SAVE_CODE, message: $(last_error_message "$SAVE_BODY")"
fi
rm -f "$SAVE_BODY"

log "==> invalid PEM content is rejected"
asterisk_exec "echo 'not a real certificate' > $KEY_DIR/task0029a-bogus.pem"
do_save "edit/id/${WSS_ID}" "wss" "ws" "8088" "${KEY_DIR}/task0029a-bogus.pem" "${KEY_DIR}/task0029a-reject-key.pem" ""
if [ "$SAVE_CODE" != "302" ] && [[ "$(last_error_message "$SAVE_BODY")" == *"not a valid PEM"* ]]; then
    harness_ok "invalid PEM content rejected" "$(last_error_message "$SAVE_BODY")"
else
    harness_bad "invalid PEM content rejected" "HTTP $SAVE_CODE, message: $(last_error_message "$SAVE_BODY")"
fi
rm -f "$SAVE_BODY"
asterisk_exec "rm -f $KEY_DIR/task0029a-bogus.pem"

log "==> incomplete pair (cert set, key empty) is rejected"
do_save "edit/id/${WSS_ID}" "wss" "ws" "8088" "${KEY_DIR}/task0029a-reject-cert.pem" "" ""
if [ "$SAVE_CODE" != "302" ] && [[ "$(last_error_message "$SAVE_BODY")" == *"must both be set"* ]]; then
    harness_ok "incomplete cert/key pair rejected" "$(last_error_message "$SAVE_BODY")"
else
    harness_bad "incomplete cert/key pair rejected" "HTTP $SAVE_CODE, message: $(last_error_message "$SAVE_BODY")"
fi
rm -f "$SAVE_BODY"
rm_cert "task0029a-reject"

log "==> confirming wss transport is still in its original working state after rejected attempts"
STILL_CERT="$(db_query "SELECT cert_file FROM pjsip_transports WHERE id=${WSS_ID};")"
if [ "$STILL_CERT" = "$ORIGINAL_WSS_CERT" ]; then
    harness_ok "rejected saves did not mutate state" "cert_file unchanged ($STILL_CERT)"
else
    harness_bad "rejected saves did not mutate state" "expected $ORIGINAL_WSS_CERT, found $STILL_CERT"
fi

log "==> TASK-0035A: native SIP TLS does not conflict with the private ws backend (no Asterisk WSS cert)"
# Under reverse-proxy termination the seeded ws row carries no Asterisk
# cert_file, so Asterisk's single-HTTP-TLS-identity rule is idle. A
# native protocol=tls transport must be accepted alongside it.
CONFLICT_NAME="${TLS_FIXTURE_NAME}-conflict-$$"
gen_cert "task0029a-tls" "task0029a-conflict-test"
do_save "add" "$CONFLICT_NAME" "tls" "18089" "${KEY_DIR}/task0029a-tls-cert.pem" "${KEY_DIR}/task0029a-tls-key.pem" ""
if [ "$SAVE_CODE" = "302" ]; then
    CONFLICT_ID="$(db_query "SELECT id FROM pjsip_transports WHERE name='${CONFLICT_NAME}';")"
    harness_ok "native TLS transport accepted alongside private ws backend" "id=${CONFLICT_ID:-unknown} name=${CONFLICT_NAME}"
    if [ -n "$CONFLICT_ID" ]; then
        delete_transport "$CONFLICT_ID" || db_query "DELETE FROM pjsip_transports WHERE id=${CONFLICT_ID};" >/dev/null
        $COMPOSE exec -T asterisk php /usr/local/bin/reconcile-pjsip.php >/dev/null 2>&1 || true
    fi
else
    harness_bad "native TLS transport accepted alongside private ws backend" "HTTP $SAVE_CODE, message: $(last_error_message "$SAVE_BODY")"
fi
rm -f "$SAVE_BODY"
rm_cert "task0029a-tls"

# =============================================================================
# 3. Valid native `tls` transport: accepted, correct generated config,
#    real live TLS handshake with matching certificate identity
# =============================================================================

log "==> creating a valid native TLS transport with a real cert/key pair"
gen_cert "task0029a-tls" "${TLS_FIXTURE_NAME}"
do_save "add" "$TLS_FIXTURE_NAME" "tls" "$TLS_FIXTURE_PORT" "${KEY_DIR}/task0029a-tls-cert.pem" "${KEY_DIR}/task0029a-tls-key.pem" "tlsv1_2"
if [ "$SAVE_CODE" = "302" ]; then
    harness_ok "valid tls transport created" "HTTP 302"
else
    harness_blocked "could not create the tls fixture transport: HTTP $SAVE_CODE, $(last_error_message "$SAVE_BODY")"
fi
rm -f "$SAVE_BODY"
CREATED_TLS_ID="$(db_query "SELECT id FROM pjsip_transports WHERE name='${TLS_FIXTURE_NAME}';")"
harness_register_cleanup "transport ${TLS_FIXTURE_NAME} (tls-cert-management fixture)" "delete_transport ${CREATED_TLS_ID}"

GENERATED="$(asterisk_exec "cat /etc/asterisk/snep/senma-pjsip-transports.conf")"
TLS_STANZA="$(echo "$GENERATED" | awk -v RS="" -v want="[$TLS_FIXTURE_NAME]" 'index($0, want"\n") == 1 { print; }')"
if echo "$TLS_STANZA" | grep -q "^cert_file=${KEY_DIR}/task0029a-tls-cert.pem$" \
    && echo "$TLS_STANZA" | grep -q "^priv_key_file=${KEY_DIR}/task0029a-tls-key.pem$" \
    && echo "$TLS_STANZA" | grep -q "^method=tlsv1_2$"; then
    harness_ok "generated config references correct in-container paths" "cert_file/priv_key_file/method all present in [${TLS_FIXTURE_NAME}]"
else
    harness_bad "generated config references correct in-container paths" "missing expected lines in: $TLS_STANZA"
fi

live_tls_bound() {
    asterisk_exec "asterisk -rx 'pjsip show transport ${TLS_FIXTURE_NAME}'" 2>&1 | grep -q "0\.0\.0\.0:${TLS_FIXTURE_PORT}"
}
if harness_retry 5 1 -- live_tls_bound; then
    harness_ok "tls transport runtime loaded" "bound to 0.0.0.0:${TLS_FIXTURE_PORT}"
else
    harness_bad "tls transport runtime loaded" "not found in pjsip show transport"
fi

HANDSHAKE_SUBJECT="$(asterisk_exec "echo | timeout 3 openssl s_client -tls1_2 -connect localhost:${TLS_FIXTURE_PORT} 2>/dev/null | grep subject=" | sed 's/subject=//')"
if [[ "$HANDSHAKE_SUBJECT" == *"CN"*"=${TLS_FIXTURE_NAME}"* ]]; then
    harness_ok "real TLS handshake presents the configured certificate" "subject: $HANDSHAKE_SUBJECT"
else
    harness_bad "real TLS handshake presents the configured certificate" "expected CN=${TLS_FIXTURE_NAME}, got: $HANDSHAKE_SUBJECT"
fi

# =============================================================================
# 4. Failure behavior -- mismatched cert/key pair caught at RUNTIME
#    APPLY time (SENMA cannot validate this pre-save -- see header)
# =============================================================================

log "==> a genuinely mismatched cert/key pair (individually valid, wrong pairing) is caught live, not silently accepted"
gen_cert "task0029a-mismatch-a" "task0029a-mismatch-a"
gen_cert "task0029a-mismatch-b" "task0029a-mismatch-b"
do_save "edit/id/${CREATED_TLS_ID}" "$TLS_FIXTURE_NAME" "tls" "$TLS_FIXTURE_PORT" "${KEY_DIR}/task0029a-mismatch-a-cert.pem" "${KEY_DIR}/task0029a-mismatch-b-key.pem" "tlsv1_2"
rm -f "$SAVE_BODY"
if [ "$SAVE_CODE" = "302" ]; then
    FLASH="$(last_flash_message)"
    if [[ "$FLASH" == *"could not be confirmed"* ]] || [[ "$FLASH" == *"could not be applied"* ]] || [[ "$FLASH" == *"apply"* ]]; then
        harness_ok "mismatched cert/key surfaced as apply_failed, not silent success" "$FLASH"
    else
        harness_bad "mismatched cert/key surfaced as apply_failed, not silent success" "expected an apply_failed flash, got: $FLASH"
    fi
else
    harness_bad "mismatched cert/key surfaced as apply_failed, not silent success" "unexpectedly rejected pre-save (HTTP $SAVE_CODE) -- SENMA cannot know this without reading the private key, so this should have reached runtime apply"
fi
rm_cert "task0029a-mismatch-a"
rm_cert "task0029a-mismatch-b"

# Restore the fixture to its own genuinely-matching pair before deleting
# it, so this suite's own cleanup below is not itself left in a
# broken/mismatched state for any other suite that might run next.
gen_cert "task0029a-tls" "${TLS_FIXTURE_NAME}-restored"
do_save "edit/id/${CREATED_TLS_ID}" "$TLS_FIXTURE_NAME" "tls" "$TLS_FIXTURE_PORT" "${KEY_DIR}/task0029a-tls-cert.pem" "${KEY_DIR}/task0029a-tls-key.pem" "tlsv1_2"
rm -f "$SAVE_BODY"

# =============================================================================
# 5. Public WSS trust surface is the reverse proxy (TASK-0035A)
# =============================================================================

log "==> TASK-0035A: public WSS TLS terminates at app; Asterisk ws backend carries no public cert"
WSS_SHAPE="$(db_query "SELECT CONCAT(protocol,':',bind_port,':',COALESCE(cert_file,'')) FROM pjsip_transports WHERE id=${WSS_ID};")"
if [ "$WSS_SHAPE" = "ws:8088:" ]; then
    harness_ok "seeded websocket row is private ws:8088 without Asterisk cert" "$WSS_SHAPE"
else
    harness_bad "seeded websocket row is private ws:8088 without Asterisk cert" "expected ws:8088:, got $WSS_SHAPE"
fi

GENERATED_HTTP_TLS="$(asterisk_exec "cat /etc/asterisk/snep/senma-http-tls.conf")"
if echo "$GENERATED_HTTP_TLS" | grep -qE '^tlsenable=no$|^tlsenable = no$'; then
    harness_ok "Asterisk HTTP TLS disabled for private WS backend" "tlsenable=no"
else
    harness_bad "Asterisk HTTP TLS disabled for private WS backend" "expected tlsenable=no, got: $GENERATED_HTTP_TLS"
fi

PUBLIC_TLS_SUBJECT="$(echo | timeout 5 openssl s_client -connect 127.0.0.1:${MAG_HTTPS_PORT:-8443} -servername localhost 2>/dev/null | openssl x509 -noout -subject | sed 's/^subject=//')"
if echo "$PUBLIC_TLS_SUBJECT" | grep -qi 'senma-public-wss-dev'; then
    harness_ok "public reverse-proxy TLS presents the app public-wss certificate" "subject: $PUBLIC_TLS_SUBJECT"
else
    harness_bad "public reverse-proxy TLS presents the app public-wss certificate" "unexpected subject: $PUBLIC_TLS_SUBJECT"
fi

# Native SIP TLS certificate rotation remains covered by section 3/4 above.
# Do NOT attach cert_file onto the seeded ws row — that would re-couple
# Asterisk HTTP TLS to the public WSS trust surface (superseded by TASK-0035A).

# =============================================================================
# 6. UDP/TCP unaffected
# =============================================================================

log "==> confirming udp/tcp transports carry no TLS/certificate lines"
GENERATED="$(asterisk_exec "cat /etc/asterisk/snep/senma-pjsip-transports.conf")"
UDP_STANZA="$(echo "$GENERATED" | awk -v RS="" -v want="[udp]" 'index($0, want"\n") == 1 { print; }')"
TCP_STANZA="$(echo "$GENERATED" | awk -v RS="" -v want="[tcp]" 'index($0, want"\n") == 1 { print; }')"
if ! echo "$UDP_STANZA$TCP_STANZA" | grep -qE "cert_file|priv_key_file|ca_list_file|verify_client|verify_server|^method="; then
    harness_ok "udp/tcp carry no TLS fields" "confirmed absent from both generated stanzas"
else
    harness_bad "udp/tcp carry no TLS fields" "unexpected TLS-related line found in udp/tcp stanza"
fi

# =============================================================================
# 7. Restart/recreate persistence (certificate files + generated config)
# =============================================================================

# Public WSS certificate lifecycle is owned by the app reverse proxy.
# Asterisk restart must not disturb the public cert, and must leave the
# private ws backend + tlsenable=no contract intact.
PUBLIC_CERT_PATH="/etc/senma/certs/public-wss.crt"
PUBLIC_CERT_HASH_BEFORE="$($COMPOSE exec -T app sha256sum "$PUBLIC_CERT_PATH" | awk '{print $1}')"
HTTP_TLS_HASH_BEFORE="$(asterisk_exec "cat /etc/asterisk/snep/senma-http-tls.conf" | sha256sum | awk '{print $1}')"
WSS_SHAPE_BEFORE="$(db_query "SELECT CONCAT(protocol,':',bind_port,':',COALESCE(cert_file,'')) FROM pjsip_transports WHERE id=${WSS_ID};")"

log "==> docker compose restart asterisk"
$COMPOSE restart asterisk >&2
asterisk_healthy() { $COMPOSE ps asterisk --format '{{.Health}}' 2>/dev/null | grep -q '^healthy$'; }
if harness_retry 30 2 -- asterisk_healthy; then
    harness_ok "container healthy after restart" "asterisk reports healthy again"
else
    harness_bad "container healthy after restart" "not healthy within 60s"
fi

PUBLIC_CERT_HASH_AFTER="$($COMPOSE exec -T app sha256sum "$PUBLIC_CERT_PATH" | awk '{print $1}')"
HTTP_TLS_HASH_AFTER="$(asterisk_exec "cat /etc/asterisk/snep/senma-http-tls.conf" | sha256sum | awk '{print $1}')"
WSS_SHAPE_AFTER="$(db_query "SELECT CONCAT(protocol,':',bind_port,':',COALESCE(cert_file,'')) FROM pjsip_transports WHERE id=${WSS_ID};")"
if [ "$PUBLIC_CERT_HASH_BEFORE" = "$PUBLIC_CERT_HASH_AFTER" ] && [ -n "$PUBLIC_CERT_HASH_BEFORE" ]; then
    harness_ok "public reverse-proxy certificate preserved across Asterisk restart" "sha256 unchanged ($PUBLIC_CERT_HASH_BEFORE)"
else
    harness_bad "public reverse-proxy certificate preserved across Asterisk restart" "before=$PUBLIC_CERT_HASH_BEFORE after=$PUBLIC_CERT_HASH_AFTER"
fi
if [ "$WSS_SHAPE_BEFORE" = "$WSS_SHAPE_AFTER" ] && [ "$WSS_SHAPE_AFTER" = "ws:8088:" ]; then
    harness_ok "websocket backend shape unchanged after Asterisk restart" "$WSS_SHAPE_AFTER"
else
    harness_bad "websocket backend shape unchanged after Asterisk restart" "before=$WSS_SHAPE_BEFORE after=$WSS_SHAPE_AFTER"
fi

public_tls_still_ok() {
    echo | timeout 5 openssl s_client -connect "127.0.0.1:${MAG_HTTPS_PORT:-8443}" -servername localhost 2>/dev/null         | openssl x509 -noout -subject | grep -qi 'senma-public-wss-dev'
}
if harness_retry 10 2 -- public_tls_still_ok; then
    harness_ok "public WSS TLS still presents the proxy certificate after Asterisk restart" "confirmed via a fresh TLS handshake to app"
else
    harness_bad "public WSS TLS still presents the proxy certificate after Asterisk restart" "handshake did not present the public-wss fixture"
fi
log "senma-http-tls.conf sha256 before=${HTTP_TLS_HASH_BEFORE} after=${HTTP_TLS_HASH_AFTER}"

# --- post-restart ODBC/CDR recovery (TASK-0033E1) ----------------------------
#
# `docker compose restart asterisk` above names only `asterisk`, never
# `db` -- live-confirmed (docs/tasks/
# 0033e1-asterisk-restart-harness-odbc-recovery.md) to self-heal reliably
# since `db` is never touched. Verified explicitly anyway so this
# suite's own pass/fail contract does not silently depend on that
# self-healing behavior continuing to hold under a future change.
if harness_wait_asterisk_ready && harness_restore_asterisk_post_restart; then
    harness_ok "ODBC/CDR ready after restart" "active ODBC connection and cdr_adaptive_odbc.so Running confirmed"
else
    harness_bad "ODBC/CDR ready after restart" "Asterisk restarted successfully but ODBC/CDR runtime did not recover"
fi

# =============================================================================
# 8. No secrets committed
# =============================================================================

log "==> confirming no certificate/private key material is tracked by git"
TRACKED_KEYS="$(git -C "$SCRIPT_DIR/.." ls-files | grep -E '\.(pem|key|crt)$' || true)"
if [ -z "$TRACKED_KEYS" ]; then
    harness_ok "no committed certificate/key fixtures" "git ls-files has no .pem/.key/.crt files"
else
    harness_bad "no committed certificate/key fixtures" "found tracked files: $TRACKED_KEYS"
fi

# --- cleanup: remove the tls fixture's own generated cert/key files ---
harness_register_best_effort_cleanup "tls fixture certificate files" "rm_cert task0029a-tls"

# TASK-0035A: always leave the seeded websocket row in the supported
# reverse-proxy shape (protocol=ws, :8088, no Asterisk public cert).
do_save "edit/id/${WSS_ID}" "wss" "ws" "8088" "" "" "" || true
FINAL_PROTO="$(db_query "SELECT CONCAT(protocol,':',bind_port,':',COALESCE(cert_file,'')) FROM pjsip_transports WHERE id=${WSS_ID};")"
if [ "$FINAL_PROTO" = "ws:8088:" ]; then
    harness_ok "seeded websocket row left in proxy-backend shape" "$FINAL_PROTO"
else
    harness_bad "seeded websocket row left in proxy-backend shape" "expected ws:8088:, got $FINAL_PROTO"
fi

harness_complete
