#!/bin/bash
#
# DB -> PJSIP reconciliation regression coverage (TASK-0033B).
#
# Safe for `make regression` -- unlike scripts/backup-restore-dr-smoke-
# -test.sh, this never stops, restarts, or recreates a container, and
# never touches a Docker volume. Everything it deletes/corrupts
# (SENMA-managed generated PJSIP files) is, by the whole point of
# reconciliation, fully regenerable from the database -- the worst case
# of a bug here is `make reconcile` fixing it again, not lost state.
#
# Covers, in one pass against a real running dev stack:
#   1. in-sync state (make reconcile-check -> IN_SYNC)
#   2. drift detection (a hand-edited active file -> DRIFTED)
#   3. stale section removal (that same hand-edit is a live-reloaded
#      object Asterisk actually has -- reconcile must remove it from
#      both the file AND the runtime)
#   4. deleted managed files fully recreated, permissions correct
#      (owner=asterisk, group=senma-config, mode=664)
#   5. customer-owned custom/*.conf byte-identical before/after
#   6. TLS certificate/key byte-identical before/after
#   7. pjsip_external referenced-but-unmanaged endpoint never generated,
#      reported only as an external dependency, never a failure
#   8. invalid DB state (extension pinned to a since-disabled transport)
#      refused, active files left byte-identical to the last known-good
#      set. (Originally modeled as a dangling transport_id -- TASK-0018's
#      peers.transport_id FK, confirmed via information_schema.KEY_COLUMN_
#      USAGE, ON DELETE RESTRICT, has since made that literal state
#      unreachable; the disabled-transport state below exercises the
#      identical Reconciler::generateAll() INVALID_DB_STATE contract and
#      remains fully reachable, see TASK-0033F1.)
#   9. real runtime verification + a real endpoint registration and a
#      real completed call against the extensions reconcile itself just
#      recreated from nothing (Phase 26's core proof)
#  10. deleted extension does not reappear after reconcile (Phase 28)
#  11. no secret leakage in reconcile's own command output
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
FIXTURE_MARKER="task0033b-reconcile-fixture"
TEST_USER="admin"
TEST_PASSWORD="SmokeTest123!"
EXT_A=1094
EXT_B=1095
SECRET_A="${FIXTURE_MARKER}-a"
SECRET_B="${FIXTURE_MARKER}-b"
TRUNK_CALLERID="${FIXTURE_MARKER}-trunk"
EXTERNAL_FIXTURE_USERNAME="${FIXTURE_MARKER}-external"
# TASK-0033F1 scenario 8 fixture -- port 5099 is not used by any other
# scripts/*.sh transport fixture (checked: 5060/5061/5070/5073-5076/
# 5091/5097/5098/5211-5213 are all already claimed elsewhere).
RECONCILE_TRANSPORT_NAME="${FIXTURE_MARKER}-transport"
RECONCILE_TRANSPORT_PORT="5099"

log() { harness_log "$@"; }

harness_require_env DB_USER DB_PASSWORD DB_NAME TRUNK_TEST_USERNAME TRUNK_TEST_SECRET

db_query() {
    $COMPOSE exec -T db mariadb -u"${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" -N -e "$1"
}

reconcile() {
    $COMPOSE exec -T asterisk php /usr/local/bin/reconcile-pjsip.php 2>&1
}
reconcile_check() {
    $COMPOSE exec -T asterisk php /usr/local/bin/reconcile-pjsip.php --check 2>&1
}

snep_dir_sha() {
    # sha256 of one managed/customer file inside the asterisk-etc volume.
    $COMPOSE exec -T asterisk sha256sum "/etc/asterisk/snep/$1" 2>/dev/null | awk '{print $1}'
}
key_dir_sha() {
    $COMPOSE exec -T asterisk sha256sum "/etc/asterisk/keys/$1" 2>/dev/null | awk '{print $1}'
}
custom_dir_sha() {
    # custom/*.conf lives directly under /etc/asterisk/ (a sibling of
    # snep/), not under /etc/asterisk/snep/ -- confirmed live.
    $COMPOSE exec -T asterisk sha256sum "/etc/asterisk/custom/$1" 2>/dev/null | awk '{print $1}'
}

http_login() {
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null \
        -d "user=${TEST_USER}&password=${TEST_PASSWORD}" "${BASE_URL}/index.php/auth/login"
}

create_extension() {
    local ext="$1" secret="$2" body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "name=SENMA reconcile-smoke ${ext}" \
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
    if [ "$httpcode" = "302" ]; then rm -f "$body"; return 0; fi
    log "create_extension ${ext} failed (HTTP $httpcode): $(head -c 300 "$body")"
    rm -f "$body"
    return 1
}
delete_extension() {
    local ext="$1" httpcode
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "id=${ext}" --data-urlencode "delete=Delete" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/extensions/remove")"
    [ "$httpcode" = "302" ]
}

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
        --data-urlencode "fromuser=" --data-urlencode "fromdomain=" \
        --data-urlencode "qualify=yes" --data-urlencode "qualify_value=" \
        --data-urlencode "peer_type=friend" --data-urlencode "domain=" \
        --data-urlencode "insecure=" --data-urlencode "port=5060" \
        --data-urlencode "call-limit=" --data-urlencode "dtmfmode=rfc2833" \
        --data-urlencode "nat_no=1" --data-urlencode "codec=ulaw" \
        --data-urlencode "codec1=alaw" --data-urlencode "codec2=gsm" \
        --data-urlencode "reverse_auth=reverse_auth" --data-urlencode "telco=" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/trunks/add")"
    if [ "$httpcode" = "302" ]; then rm -f "$body"; return 0; fi
    log "create_trunk failed (HTTP $httpcode): $(head -c 300 "$body")"
    rm -f "$body"
    return 1
}
delete_trunk() {
    local id="$1" name="$2" httpcode
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "id=${id}" --data-urlencode "name=${name}" --data-urlencode "delete=Delete" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/trunks/remove")"
    [ "$httpcode" = "302" ]
}

# create_reconcile_transport_fixture / reconcile_transport_set_enabled /
# delete_reconcile_transport -- same real HTTP flow (add/edit/remove)
# scripts/transport-smoke-test.sh's save_transport()/delete_transport()
# already establish for TASK-0018/0019 transport fixtures. enabled=0
# OMITS the checkbox field entirely, matching a real unchecked checkbox
# (buildData()'s isset($post['enabled']) check depends on the key being
# absent, not its value).
create_reconcile_transport_fixture() {
    local body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "name=${RECONCILE_TRANSPORT_NAME}" \
        --data-urlencode "protocol=udp" \
        --data-urlencode "bind_address=0.0.0.0" \
        --data-urlencode "bind_port=${RECONCILE_TRANSPORT_PORT}" \
        --data-urlencode "domain=" \
        --data-urlencode "external_signaling_address=" \
        --data-urlencode "external_signaling_port=" \
        --data-urlencode "external_media_address=" \
        --data-urlencode "local_net=" \
        --data-urlencode "allow_reload=1" \
        --data-urlencode "enabled=1" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/pjsip-transports/add")"
    if [ "$httpcode" = "302" ]; then rm -f "$body"; return 0; fi
    log "create_reconcile_transport_fixture failed (HTTP $httpcode): $(head -c 300 "$body")"
    rm -f "$body"
    return 1
}
reconcile_transport_set_enabled() {
    local id="$1" enabled="$2" body httpcode
    body="$(mktemp)"
    if [ "$enabled" = "1" ]; then
        httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
            --data-urlencode "name=${RECONCILE_TRANSPORT_NAME}" \
            --data-urlencode "protocol=udp" \
            --data-urlencode "bind_address=0.0.0.0" \
            --data-urlencode "bind_port=${RECONCILE_TRANSPORT_PORT}" \
            --data-urlencode "domain=" \
            --data-urlencode "external_signaling_address=" \
            --data-urlencode "external_signaling_port=" \
            --data-urlencode "external_media_address=" \
            --data-urlencode "local_net=" \
            --data-urlencode "allow_reload=1" \
            --data-urlencode "enabled=1" \
            --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
            "${BASE_URL}/index.php/default/pjsip-transports/edit/id/${id}")"
    else
        httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
            --data-urlencode "name=${RECONCILE_TRANSPORT_NAME}" \
            --data-urlencode "protocol=udp" \
            --data-urlencode "bind_address=0.0.0.0" \
            --data-urlencode "bind_port=${RECONCILE_TRANSPORT_PORT}" \
            --data-urlencode "domain=" \
            --data-urlencode "external_signaling_address=" \
            --data-urlencode "external_signaling_port=" \
            --data-urlencode "external_media_address=" \
            --data-urlencode "local_net=" \
            --data-urlencode "allow_reload=1" \
            --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
            "${BASE_URL}/index.php/default/pjsip-transports/edit/id/${id}")"
    fi
    if [ "$httpcode" = "302" ]; then rm -f "$body"; return 0; fi
    log "reconcile_transport_set_enabled(${enabled}) failed (HTTP $httpcode): $(head -c 300 "$body")"
    rm -f "$body"
    return 1
}
delete_reconcile_transport() {
    local id="$1" httpcode
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "id=${id}" --data-urlencode "delete=Delete" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/pjsip-transports/remove")"
    [ "$httpcode" = "302" ]
}

wait_registered() {
    local ext="$1" tries=15
    while [ "$tries" -gt 0 ]; do
        $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${ext}" 2>&1 | grep -q "Contact:.*${ext}/sip:" && return 0
        sleep 1; tries=$((tries-1))
    done
    return 1
}

# =====================================================================
# 1. Preflight
# =====================================================================

log "==> checking required containers"
harness_require_containers app asterisk db

pjsip_modules_running() {
    $COMPOSE exec -T asterisk asterisk -rx 'module show like res_pjsip.so' 2>&1 | grep -q "Running"
}
harness_retry 5 2 -- pjsip_modules_running || harness_blocked "PJSIP modules not Running"

COOKIEJAR="$(mktemp)"
harness_register_best_effort_cleanup "cookie jar" "rm -f '$COOKIEJAR'"
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${TEST_PASSWORD}');" 2>/dev/null | tr -d '\r')"
[ -n "$TEST_HASH" ] || harness_blocked "could not compute admin password hash"
db_query "UPDATE users SET password = '${TEST_HASH}' WHERE name = '${TEST_USER}';" >&2
http_login
ADMIN_CSRF="$(harness_csrf_token "$COOKIEJAR" "$BASE_URL")"
[ -n "$ADMIN_CSRF" ] || harness_blocked "could not read admin CSRF token"

log "==> checking for leftover fixtures from a prior interrupted run"
for ext in "$EXT_A" "$EXT_B"; do
    existing="$(db_query "SELECT canal FROM peers WHERE name='${ext}';")"
    [ -n "$existing" ] && harness_blocked "peers row for extension '${ext}' already exists -- refusing to proceed"
done
existing_trunk="$(db_query "SELECT id FROM trunks WHERE callerid='${TRUNK_CALLERID}';")"
[ -n "$existing_trunk" ] && harness_blocked "leftover trunk fixture (callerid=${TRUNK_CALLERID}) from a prior run -- remove it manually first"
existing_external="$(db_query "SELECT id FROM trunks WHERE username='${EXTERNAL_FIXTURE_USERNAME}';")"
[ -n "$existing_external" ] && harness_blocked "leftover pjsip_external fixture row -- remove it manually first"
existing_transport="$(db_query "SELECT id FROM pjsip_transports WHERE name='${RECONCILE_TRANSPORT_NAME}';")"
[ -n "$existing_transport" ] && harness_blocked "leftover fixture transport (name=${RECONCILE_TRANSPORT_NAME}) from a prior run -- remove it manually first"

# =====================================================================
# 2. Provision known-state fixtures (extensions + a native trunk)
# =====================================================================

log "==> provisioning fixtures: extensions ${EXT_A}/${EXT_B}, trunk callerid=${TRUNK_CALLERID}"
for pair in "${EXT_A}:${SECRET_A}" "${EXT_B}:${SECRET_B}"; do
    IFS=':' read -r ext secret <<< "$pair"
    create_extension "$ext" "$secret" || harness_blocked "provisioning extension ${ext} failed"
    harness_register_best_effort_cleanup "extension ${ext} (safety net -- normally deleted explicitly in scenario 10)" "delete_extension ${ext}"
done
create_trunk || harness_blocked "provisioning trunk failed"
TRUNK_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${TRUNK_CALLERID}';")"
TRUNK_NAME="$(db_query "SELECT name FROM trunks WHERE id=${TRUNK_ID};")"
[ -n "$TRUNK_ID" ] && [ -n "$TRUNK_NAME" ] || harness_blocked "could not resolve the newly created trunk's id/name"
harness_register_best_effort_cleanup "trunk id=${TRUNK_ID} (safety net -- normally deleted explicitly in scenario 10)" "delete_trunk ${TRUNK_ID} ${TRUNK_NAME}"
harness_ok "fixtures provisioned" "extensions ${EXT_A}/${EXT_B}, trunk id=${TRUNK_ID} via the real HTTP flows"

for name in "$EXT_A" "$EXT_B" "trunk-${TRUNK_ID}"; do
    endpoint_visible() { $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${name}" 2>&1 | grep -qE "Endpoint:  ${name}([ /]|\$)"; }
    harness_retry 5 1 -- endpoint_visible || harness_bad "endpoint ${name} visible after CRUD provisioning" "not found"
done
[ "$_HARNESS_FAIL_COUNT" -gt 0 ] && { log "fixture provisioning did not reach Asterisk -- aborting"; harness_complete; }

# =====================================================================
# 3. Scenario 1: in-sync state
# =====================================================================

log "==> scenario 1: in-sync state"
CHECK_OUT="$(reconcile_check)"
if echo "$CHECK_OUT" | grep -q "status: IN_SYNC"; then
    harness_ok "reconcile-check reports IN_SYNC" "immediately after a real CRUD save"
else
    harness_bad "reconcile-check reports IN_SYNC" "$CHECK_OUT"
fi

# =====================================================================
# Snapshot customer-owned + certificate state (Phase 23/24) BEFORE any
# destructive step below.
# =====================================================================

CUSTOM_PREAGI_BEFORE="$(custom_dir_sha preagi.conf)"
CUSTOM_POSAGI_BEFORE="$(custom_dir_sha posagi.conf)"
CUSTOM_EOF_BEFORE="$(custom_dir_sha eof.conf)"
CERT_BEFORE="$(key_dir_sha wss-test-cert.pem)"
KEY_BEFORE="$(key_dir_sha wss-test-key.pem)"
[ -n "$CUSTOM_PREAGI_BEFORE" ] && [ -n "$CERT_BEFORE" ] && [ -n "$KEY_BEFORE" ] || harness_blocked "could not snapshot customer/certificate file checksums before testing"

# =====================================================================
# 4. Scenario 2+3: drift detection + stale-object removal
# =====================================================================

log "==> scenario 2/3: hand-edit the active file, force a live reload, then reconcile"
STALE_NAME="9999-stale-reconcile-test"
$COMPOSE exec -T asterisk sh -c "cat >> /etc/asterisk/snep/senma-pjsip.conf" <<EOF

[$STALE_NAME]
type=endpoint
context=default
disallow=all
allow=alaw
auth=$STALE_NAME-auth
aors=$STALE_NAME

[$STALE_NAME-auth]
type=auth
auth_type=userpass
username=$STALE_NAME
password=stale-test-password

[$STALE_NAME]
type=aor
max_contacts=1
EOF
# Force it live -- otherwise this only proves the FILE has a stale
# section, not that reconcile can remove one Asterisk actually loaded.
$COMPOSE exec -T asterisk asterisk -rx "module reload res_pjsip.so" >&2
stale_live() { $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${STALE_NAME}" 2>&1 | grep -qE "Endpoint:  ${STALE_NAME}([ /]|\$)"; }
harness_retry 5 1 -- stale_live || harness_bad "stale section actually loaded live (test setup)" "hand-edited section never became live -- cannot prove removal"

CHECK_OUT="$(reconcile_check)"
if echo "$CHECK_OUT" | grep -q "status: DRIFTED"; then
    harness_ok "reconcile-check reports DRIFTED" "after a hand-edited active file"
else
    harness_bad "reconcile-check reports DRIFTED" "$CHECK_OUT"
fi

RECONCILE_OUT="$(reconcile)"
if echo "$RECONCILE_OUT" | grep -q "status: RECONCILED"; then
    harness_ok "reconcile clears drift" "status: RECONCILED"
else
    harness_bad "reconcile clears drift" "$RECONCILE_OUT"
fi

if $COMPOSE exec -T asterisk grep -q "$STALE_NAME" /etc/asterisk/snep/senma-pjsip.conf 2>/dev/null; then
    harness_bad "stale section removed from the generated file" "still present after reconcile"
else
    harness_ok "stale section removed from the generated file" "no longer present"
fi
stale_gone() { ! $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${STALE_NAME}" 2>&1 | grep -qE "Endpoint:  ${STALE_NAME}([ /]|\$)"; }
if harness_retry 5 1 -- stale_gone; then
    harness_ok "stale object removed from the live runtime" "pjsip show endpoint no longer finds it"
else
    harness_bad "stale object removed from the live runtime" "still loaded after reconcile"
fi

# =====================================================================
# 5. Scenario 4/5/6/9/10: delete the whole managed set, reconcile,
#    prove customer/cert preservation, permissions, and a real call.
# =====================================================================

log "==> scenario 4: deleting all SENMA-managed generated files"
for f in senma-pjsip.conf senma-pjsip-trunks.conf senma-pjsip-transports.conf senma-http-tls.conf; do
    $COMPOSE exec -T asterisk rm -f "/etc/asterisk/snep/$f"
done
STILL_PRESENT=""
for f in senma-pjsip.conf senma-pjsip-trunks.conf senma-pjsip-transports.conf senma-http-tls.conf; do
    $COMPOSE exec -T asterisk test -f "/etc/asterisk/snep/$f" 2>/dev/null && STILL_PRESENT="$STILL_PRESENT $f"
done
if [ -z "$STILL_PRESENT" ]; then
    harness_ok "managed files actually deleted" "confirmed absent before reconciling"
else
    harness_bad "managed files actually deleted" "still present:$STILL_PRESENT"
fi

RECONCILE_OUT="$(reconcile)"
if echo "$RECONCILE_OUT" | grep -q "status: RECONCILED"; then
    harness_ok "reconcile recreates the full managed set from nothing" "status: RECONCILED"
else
    harness_bad "reconcile recreates the full managed set from nothing" "$RECONCILE_OUT"
fi

for f in senma-pjsip.conf senma-pjsip-trunks.conf senma-pjsip-transports.conf senma-http-tls.conf; do
    PERMS="$($COMPOSE exec -T asterisk stat -c '%U %G %a' "/etc/asterisk/snep/$f" 2>/dev/null | tr -d '\r')"
    if [ "$PERMS" = "asterisk senma-config 664" ]; then
        harness_ok "$f ownership/mode correct" "$PERMS"
    else
        harness_bad "$f ownership/mode correct" "expected 'asterisk senma-config 664', got '$PERMS'"
    fi
done

if echo "$RECONCILE_OUT" | grep -qF -e "${SECRET_A}" -e "${SECRET_B}" -e "${TRUNK_TEST_SECRET}" -e "${DB_PASSWORD}"; then
    harness_bad "no secret leakage in reconcile's own output" "a known secret value appeared in the command's own stdout/stderr"
else
    harness_ok "no secret leakage in reconcile's own output" "confirmed absent from stdout/stderr"
fi

# --- Customer/certificate byte-identity (Phase 23/24) -----------------
CUSTOM_PREAGI_AFTER="$(custom_dir_sha preagi.conf)"
CUSTOM_POSAGI_AFTER="$(custom_dir_sha posagi.conf)"
CUSTOM_EOF_AFTER="$(custom_dir_sha eof.conf)"
CERT_AFTER="$(key_dir_sha wss-test-cert.pem)"
KEY_AFTER="$(key_dir_sha wss-test-key.pem)"
if [ "$CUSTOM_PREAGI_BEFORE" = "$CUSTOM_PREAGI_AFTER" ] && [ "$CUSTOM_POSAGI_BEFORE" = "$CUSTOM_POSAGI_AFTER" ] && [ "$CUSTOM_EOF_BEFORE" = "$CUSTOM_EOF_AFTER" ]; then
    harness_ok "customer custom/*.conf byte-identical" "preagi/posagi/eof checksums unchanged"
else
    harness_bad "customer custom/*.conf byte-identical" "before=$CUSTOM_PREAGI_BEFORE/$CUSTOM_POSAGI_BEFORE/$CUSTOM_EOF_BEFORE after=$CUSTOM_PREAGI_AFTER/$CUSTOM_POSAGI_AFTER/$CUSTOM_EOF_AFTER"
fi
if [ "$CERT_BEFORE" = "$CERT_AFTER" ] && [ "$KEY_BEFORE" = "$KEY_AFTER" ]; then
    harness_ok "TLS certificate/key byte-identical" "checksums unchanged across reconcile"
else
    harness_bad "TLS certificate/key byte-identical" "cert before=$CERT_BEFORE after=$CERT_AFTER key before=$KEY_BEFORE after=$KEY_AFTER"
fi

# --- Runtime objects reloaded correctly --------------------------------
for name in "$EXT_A" "$EXT_B" "trunk-${TRUNK_ID}"; do
    endpoint_visible() { $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${name}" 2>&1 | grep -qE "Endpoint:  ${name}([ /]|\$)"; }
    harness_retry 5 1 -- endpoint_visible && harness_ok "endpoint ${name} loaded after reconcile" "confirmed live" \
        || harness_bad "endpoint ${name} loaded after reconcile" "not found"
done
[ "$_HARNESS_FAIL_COUNT" -gt 0 ] && { log "runtime objects did not come back after deleting+reconciling -- aborting before the call proof"; harness_complete; }

# --- Real endpoint registration + real call (Phase 26 core proof) -----
log "==> registering real endpoints against the reconciled (not recreated) extensions"
harness_timeout 180 docker build -q -t "$BARESIP_IMAGE" -f "$BARESIP_DOCKERFILE" docker >&2 \
    || harness_blocked "failed to build $BARESIP_IMAGE"

ASTERISK_CID="$($COMPOSE ps -q asterisk)"
NETWORK_NAME="$(docker inspect "$ASTERISK_CID" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')"
ASTERISK_NAME="$(docker inspect "$ASTERISK_CID" --format '{{.Name}}' | sed 's#^/##')"

CONF_DIR="$(mktemp -d)"
harness_register_best_effort_cleanup "baresip config dir" "rm -rf '$CONF_DIR'"
for pair in "${EXT_A}:${SECRET_A}:manual" "${EXT_B}:${SECRET_B}:auto"; do
    IFS=':' read -r ext secret answermode <<< "$pair"
    mkdir -p "$CONF_DIR/$ext"
    cp "$TEMPLATE_DIR/config.template" "$CONF_DIR/$ext/config"
    sed -e "s|__EXTEN__|${ext}|g" -e "s|__ASTERISK_HOST__|${ASTERISK_NAME}|g" \
        -e "s|__SECRET__|${secret}|g" -e "s|__ANSWERMODE__|${answermode}|g" \
        "$TEMPLATE_DIR/accounts.template" > "$CONF_DIR/$ext/accounts"
done

docker rm -f senma-reconcilesmoke-1094 senma-reconcilesmoke-1095 >/dev/null 2>&1
docker run -d --name senma-reconcilesmoke-1094 --network "$NETWORK_NAME" -v "$CONF_DIR/${EXT_A}:/root/.baresip" "$BARESIP_IMAGE" baresip -f /root/.baresip >&2
harness_register_best_effort_cleanup "baresip senma-reconcilesmoke-1094" "docker rm -f senma-reconcilesmoke-1094 >/dev/null 2>&1"
docker run -d --name senma-reconcilesmoke-1095 --network "$NETWORK_NAME" -v "$CONF_DIR/${EXT_B}:/root/.baresip" "$BARESIP_IMAGE" baresip -f /root/.baresip >&2
harness_register_best_effort_cleanup "baresip senma-reconcilesmoke-1095" "docker rm -f senma-reconcilesmoke-1095 >/dev/null 2>&1"

wait_registered "$EXT_A" && harness_ok "${EXT_A} registers with its original secret" "not recreated, reconciled" || harness_bad "${EXT_A} registers with its original secret" "no contact within 15s"
wait_registered "$EXT_B" && harness_ok "${EXT_B} registers with its original secret" "contact bound" || harness_bad "${EXT_B} registers with its original secret" "no contact within 15s"

if [ "$_HARNESS_FAIL_COUNT" -eq 0 ]; then
    PAYLOAD="{\"command\":\"dial\",\"params\":\"${EXT_B}\"}"
    LEN=${#PAYLOAD}
    EVENTS="$(harness_timeout 20 docker run --rm --network "$NETWORK_NAME" "$BARESIP_IMAGE" sh -c \
        "printf '%s:%s,' '$LEN' '$PAYLOAD' | timeout 10 nc senma-reconcilesmoke-1094 4444" 2>&1)"
    echo "$EVENTS" | grep -q '"type":"CALL_ESTABLISHED"' \
        && harness_ok "real call completed after reconcile" "CALL_ESTABLISHED observed" \
        || harness_bad "real call completed after reconcile" "$EVENTS"
    sleep 3
    $COMPOSE exec -T asterisk asterisk -rx "channel request hangup all" >&2
fi
docker rm -f senma-reconcilesmoke-1094 senma-reconcilesmoke-1095 >/dev/null 2>&1

# =====================================================================
# 6. Scenario 7: pjsip_external referenced-but-unmanaged endpoint
# =====================================================================

log "==> scenario 7: pjsip_external endpoint must never be generated"
# Test-only direct-DB fixture: a real pjsip_external row cannot be
# created through the supported UI without a real externally-managed
# endpoint already loaded in Asterisk (TrunksController::
# externalPjsipEndpointExists()) -- this row exists purely to prove
# reconcile's own boundary, mirroring the existing test-only direct-DB
# fixture convention this project already uses when the supported UI
# path cannot construct the exact state under test.
NEXT_TRUNK_NAME="$(db_query "SELECT CAST(name AS DECIMAL) + 1 FROM trunks ORDER BY CAST(name AS DECIMAL) DESC LIMIT 1;")"
db_query "INSERT INTO trunks (name, callerid, context, dtmfmode, allow, channel, id_regex, type, trunktype, technology, username, domain, dialmethod, reverse_auth) VALUES ('${NEXT_TRUNK_NAME}', '${FIXTURE_MARKER}-ext', 'default', 'rfc2833', 'alaw', 'PJSIP/${EXTERNAL_FIXTURE_USERNAME}', 'PJSIP/${EXTERNAL_FIXTURE_USERNAME}', 'PJSIP_EXTERNAL', 'T', 'PJSIP_EXTERNAL', '${EXTERNAL_FIXTURE_USERNAME}', '', 'NORMAL', 0);" >&2
EXTERNAL_TRUNK_ID="$(db_query "SELECT id FROM trunks WHERE username='${EXTERNAL_FIXTURE_USERNAME}';")"
[ -n "$EXTERNAL_TRUNK_ID" ] || harness_blocked "could not create the test-only pjsip_external fixture row"

RECONCILE_OUT="$(reconcile)"
if echo "$RECONCILE_OUT" | grep -q "$EXTERNAL_FIXTURE_USERNAME: missing"; then
    harness_ok "pjsip_external reported as an external dependency, not repaired" "correctly reported missing, not generated"
else
    harness_bad "pjsip_external reported as an external dependency, not repaired" "$RECONCILE_OUT"
fi
if $COMPOSE exec -T asterisk grep -ql "$EXTERNAL_FIXTURE_USERNAME" /etc/asterisk/snep/senma-pjsip.conf /etc/asterisk/snep/senma-pjsip-trunks.conf 2>/dev/null; then
    harness_bad "pjsip_external endpoint never generated" "found in a SENMA-managed generated file"
else
    harness_ok "pjsip_external endpoint never generated" "absent from every managed file"
fi
db_query "DELETE FROM trunks WHERE id=${EXTERNAL_TRUNK_ID};" >&2

# =====================================================================
# 7. Scenario 8: invalid DB state refused, active files untouched
# =====================================================================

log "==> scenario 8: extension pinned to a disabled transport must be refused, not published"

# peers.transport_id -> pjsip_transports(id) ON DELETE RESTRICT (TASK-0018)
# now rejects a dangling id outright (ERROR 1452) before Reconciler ever
# runs, so a nonexistent-id fixture can no longer reach the
# INVALID_DB_STATE code path it used to exercise. A transport that
# exists but is disabled reaches the identical
# Reconciler::generateAll()/Snep_PjsipConf::resolveTransportName()
# contract instead (PBX_Exception_NotFound -> per-row warning -> full
# reconciliation treats any warning as INVALID_DB_STATE), and is real,
# currently-supported administrative behavior: PjsipTransportsController
# (TASK-0019 item 12) documents disabling a referenced transport as
# "a deliberately allowed admin action (unlike delete)".
create_reconcile_transport_fixture || harness_blocked "provisioning fixture transport failed"
RECONCILE_TRANSPORT_ID="$(db_query "SELECT id FROM pjsip_transports WHERE name='${RECONCILE_TRANSPORT_NAME}';")"
[ -n "$RECONCILE_TRANSPORT_ID" ] || harness_blocked "could not resolve the newly created fixture transport's id"
harness_register_best_effort_cleanup "fixture transport ${RECONCILE_TRANSPORT_NAME} (safety net -- normally deleted explicitly in scenario 10)" "delete_reconcile_transport ${RECONCILE_TRANSPORT_ID}"

db_query "UPDATE peers SET transport_id = ${RECONCILE_TRANSPORT_ID} WHERE name = '${EXT_A}';" >&2
RECONCILE_OUT="$(reconcile)"
echo "$RECONCILE_OUT" | grep -q "status: RECONCILED" \
    || harness_blocked "could not reconcile after pinning ${EXT_A} to the fixture transport (while it was still enabled): $RECONCILE_OUT"

reconcile_transport_set_enabled "$RECONCILE_TRANSPORT_ID" 0 || harness_blocked "could not disable the fixture transport"
# PjsipTransportsController::editAction() (the real HTTP action just
# used to disable the transport) calls its own regenerateAll() ->
# Snep_PjsipConf::loadConfFromDb() as a normal, expected, and here
# deliberately EXERCISED side effect of any transport CRUD save (TASK-
# 0017 cross-generator consistency) -- it already silently skipped
# ${EXT_A}'s now-invalid row and republished senma-pjsip.conf without it
# (a single CRUD save tolerates this row-level warning; Reconciler.php's
# own docblock documents that asymmetry with a full reconciliation
# explicitly). So the correct "known good" snapshot for THIS assertion
# is the file as that CRUD save already left it, captured here -- not
# before the disable.
KNOWN_GOOD_SHA="$(snep_dir_sha senma-pjsip.conf)"

RECONCILE_OUT="$(reconcile)"
if echo "$RECONCILE_OUT" | grep -q "status: INVALID_DB_STATE"; then
    harness_ok "reconcile refuses to publish with an extension pinned to a disabled transport" "status: INVALID_DB_STATE"
else
    harness_bad "reconcile refuses to publish with an extension pinned to a disabled transport" "$RECONCILE_OUT"
fi

AFTER_REFUSAL_SHA="$(snep_dir_sha senma-pjsip.conf)"
if [ "$KNOWN_GOOD_SHA" = "$AFTER_REFUSAL_SHA" ]; then
    harness_ok "active files left byte-identical after a refused publish" "senma-pjsip.conf checksum unchanged"
else
    harness_bad "active files left byte-identical after a refused publish" "checksum changed: before=$KNOWN_GOOD_SHA after=$AFTER_REFUSAL_SHA"
fi

reconcile_transport_set_enabled "$RECONCILE_TRANSPORT_ID" 1 || harness_blocked "could not re-enable the fixture transport"
RECONCILE_OUT="$(reconcile)"
echo "$RECONCILE_OUT" | grep -q "status: RECONCILED" \
    && harness_ok "reconcile succeeds again after the invalid state is fixed" "status: RECONCILED" \
    || harness_bad "reconcile succeeds again after the invalid state is fixed" "$RECONCILE_OUT"

# =====================================================================
# 8. Scenario 10: cleanup, then confirm deleted fixtures do not reappear
# =====================================================================

log "==> cleanup and post-delete non-reappearance check"
delete_extension "$EXT_A" && harness_ok "extension ${EXT_A} deleted via the real HTTP flow" "" || harness_bad "extension ${EXT_A} deleted via the real HTTP flow" "delete did not return 302"
delete_extension "$EXT_B" && harness_ok "extension ${EXT_B} deleted via the real HTTP flow" "" || harness_bad "extension ${EXT_B} deleted via the real HTTP flow" "delete did not return 302"
# Dependent row (peers.transport_id referencing it, via $EXT_A) must be
# gone before the parent transport fixture can be deleted -- $EXT_A was
# deleted immediately above, so no separate un-pin step is needed.
delete_reconcile_transport "$RECONCILE_TRANSPORT_ID" && harness_ok "fixture transport ${RECONCILE_TRANSPORT_NAME} deleted via the real HTTP flow" "" || harness_bad "fixture transport ${RECONCILE_TRANSPORT_NAME} deleted via the real HTTP flow" "delete did not return 302"
delete_trunk "$TRUNK_ID" "$TRUNK_NAME" && harness_ok "trunk id=${TRUNK_ID} deleted via the real HTTP flow" "" || harness_bad "trunk id=${TRUNK_ID} deleted via the real HTTP flow" "delete did not return 302"

RECONCILE_OUT="$(reconcile)"
echo "$RECONCILE_OUT" | grep -q "status: RECONCILED" \
    && harness_ok "final reconcile after cleanup succeeds" "status: RECONCILED" \
    || harness_bad "final reconcile after cleanup succeeds" "$RECONCILE_OUT"

for name in "$EXT_A" "$EXT_B" "trunk-${TRUNK_ID}"; do
    deleted_absent() { ! $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${name}" 2>&1 | grep -qE "Endpoint:  ${name}([ /]|\$)"; }
    harness_retry 5 1 -- deleted_absent && harness_ok "deleted object ${name} does not reappear after reconcile" "confirmed absent" \
        || harness_bad "deleted object ${name} does not reappear after reconcile" "still loaded"
done

harness_complete
