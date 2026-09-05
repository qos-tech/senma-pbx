#!/bin/bash
#
# TASK-0028Y -- PJSIP parameter/lifecycle regression closure.
#
# Closes four of the regression-coverage gaps the PJSIP Completeness
# Architecture Review (TASK-0028W) identified, and gives live runtime
# proof for two of that same task's parameter fixes, all via SENMA's own
# real HTTP flow (never raw SQL, never hand-written PJSIP config):
#
# PART A -- a registrationless native PJSIP trunk (reverse_auth=0):
#   1. creation: endpoint + auth + static-contact AOR generated, NO
#      outbound registration object generated at all;
#   2. (bonus, same fixture) qualify's "specify" case (a literal
#      milliseconds value, TASK-0014's own historical field) converts to
#      PJSIP's qualify_frequency in *seconds*, live;
#   2b. (bonus, same fixture) the NAT "auto_*" checkboxes (auto_force_rport/
#       auto_comedia) now actually produce force_rport=yes/rtp_symmetric=yes,
#       live -- previously silently inert (TASK-0028Y gaps #1/#3);
#   3. update: editing the SAME trunk to enable reverse_auth generates a
#      real outbound registration object where none existed before,
#      proving the decision is live (driven by reverse_auth), not
#      hardcoded at creation time;
#   4. delete: proves absence, not just an HTTP redirect -- generated
#      config, live Asterisk (endpoint/aor/auth/registration/identify),
#      and the DB row are all confirmed gone.
#
# PART B -- a PJSIP extension, exercising an update beyond transport_id
# (TASK-0019's own transport-smoke-test.sh already covers that field
# exhaustively) and full delete-cleanup proof:
#   5. creation with NAT "auto_*" only;
#   6. update: NAT auto_* -> explicit "no", proving a real field change
#      (not transport_id) reaches both the generated config AND live
#      Asterisk;
#   7. delete: proves absence in generated config, live Asterisk, and
#      the DB row -- not just an HTTP redirect.
#
# No live call/baresip fixture is used -- TASK-0015/TASK-0016's own
# trunk-smoke-test.sh already proves a real registered-trunk call flow
# end to end (both directions); this suite's job is the specific
# lifecycle/parameter gaps above, not a second call-flow proof. The
# trunk fixture's host (203.0.113.10, RFC 5737 TEST-NET-3 -- guaranteed
# non-routable, never a real host) is deliberately unreachable: nothing
# here depends on a real REGISTER/OPTIONS response, only on the
# generated config and Asterisk's own local object state.
#
# See docs/tasks/0028y-pjsip-parameter-regression-closure.md.
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
BASE_URL="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
FIXTURE_MARKER="task0028y-lifecycle"
TEST_USER="admin"
TEST_PASSWORD="SmokeTest123!"

TRUNK_CALLERID="TASK-0028Y lifecycle trunk fixture"
TRUNK_HOST="203.0.113.10"
TEST_EXT=1198
TEST_EXT_SECRET="${FIXTURE_MARKER}-ext"

COOKIEJAR=""
CREATED_TRUNK_ID=""
CREATED_TRUNK_NAME=""

log() { harness_log "$@"; }

db_query() {
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
        "${DB_NAME:-snep}" -N -e "$1"
}

http_login() {
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null \
        -d "user=${TEST_USER}&password=${TEST_PASSWORD}" "${BASE_URL}/index.php/auth/login"
}

# extract_pjsip_block <content> <section-header> <type-value> -- the
# generator (Snep_PjsipTrunkConf::renderTrunk()) emits endpoint and aor
# stanzas sharing the IDENTICAL bracket name ([trunk-<id>]), separated by
# the auth stanza -- a plain grep for a value line risks matching the
# wrong stanza, or (in a shared dev DB) a different object's section
# entirely. Every stanza this generator emits is always terminated by a
# blank line, so paragraph-mode awk (RS="") cleanly isolates the one
# stanza that both starts with the wanted header AND carries the wanted
# type= line.
extract_pjsip_block() {
    local content="$1" header="$2" type="$3"
    echo "$content" | awk -v RS="" -v want="[$header]" -v type="type=$type" '
        index($0, want"\n") == 1 && index($0, type) > 0 { print; }
    '
}

# --- Trunk fixture helpers ---------------------------------------------

# create_trunk <reverse_auth:0|1> -- technology=pjsip, qualify=specify
# (2000ms -> expect qualify_frequency=2), NAT auto_force_rport+auto_comedia
# only (expect force_rport=yes/rtp_symmetric=yes -- TASK-0028Y gaps #1/#3).
create_trunk() {
    local reverse_auth_field="" body httpcode
    [ "$1" = "1" ] && reverse_auth_field="reverse_auth"
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "callerid=${TRUNK_CALLERID}" \
        --data-urlencode "technology=pjsip" \
        --data-urlencode "dialmethod=normal" \
        --data-urlencode "username=${TRUNK_TEST_USERNAME}" \
        --data-urlencode "secret=${TRUNK_TEST_SECRET}" \
        --data-urlencode "host=${TRUNK_HOST}" \
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
        --data-urlencode "nat_auto_force_rport=1" \
        --data-urlencode "nat_auto_comedia=1" \
        --data-urlencode "codec=ulaw" \
        --data-urlencode "codec1=alaw" \
        --data-urlencode "codec2=gsm" \
        --data-urlencode "reverse_auth=${reverse_auth_field}" \
        --data-urlencode "telco=" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/trunks/add")"
    if [ "$httpcode" = "302" ]; then
        rm -f "$body"
        return 0
    fi
    log "create_trunk failed (HTTP $httpcode): $(grep -o 'Server Message[^<]*' "$body" || head -c 300 "$body")"
    rm -f "$body"
    return 1
}

# edit_trunk_reverse_auth <id> <name> <reverse_auth:0|1> -- same field
# shape as create_trunk, only reverse_auth varies, to isolate that as
# the single changed variable for the update proof.
edit_trunk_reverse_auth() {
    local id="$1" name="$2" reverse_auth_field="" body httpcode
    [ "$3" = "1" ] && reverse_auth_field="reverse_auth"
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "callerid=${TRUNK_CALLERID}" \
        --data-urlencode "technology=pjsip" \
        --data-urlencode "name=${name}" \
        --data-urlencode "dialmethod=normal" \
        --data-urlencode "username=${TRUNK_TEST_USERNAME}" \
        --data-urlencode "secret=${TRUNK_TEST_SECRET}" \
        --data-urlencode "host=${TRUNK_HOST}" \
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
        --data-urlencode "nat_auto_force_rport=1" \
        --data-urlencode "nat_auto_comedia=1" \
        --data-urlencode "codec=ulaw" \
        --data-urlencode "codec1=alaw" \
        --data-urlencode "codec2=gsm" \
        --data-urlencode "reverse_auth=${reverse_auth_field}" \
        --data-urlencode "telco=" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/trunks/edit/trunk/${id}")"
    if [ "$httpcode" = "302" ]; then
        rm -f "$body"
        return 0
    fi
    log "edit_trunk_reverse_auth failed (HTTP $httpcode): $(grep -o 'Server Message[^<]*' "$body" || head -c 300 "$body")"
    rm -f "$body"
    return 1
}

# delete_trunk <id> <name> -- <name> MUST be the trunk's real persisted
# `name` column (TrunksController::removeAction() uses it verbatim).
# Idempotent (verified): deleting an already-deleted id still returns
# 302, so this is safe to also run as the harness's own registered
# safety-net cleanup after this script's own explicit delete+verify step.
delete_trunk() {
    local id="$1" name="$2" httpcode
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "id=${id}" \
        --data-urlencode "name=${name}" \
        --data-urlencode "delete=Delete" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/trunks/remove")"
    [ "$httpcode" = "302" ]
}

# --- Extension fixture helpers -------------------------------------------

# create_extension_nat_auto <ext> <secret> -- NAT auto_force_rport/
# auto_comedia ONLY (no direct force_rport/comedia flags), so the live
# endpoint fields can only be "yes" if the auto_* collapse (TASK-0028Y
# gap #2) is actually working.
create_extension_nat_auto() {
    local ext="$1" secret="$2" body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "name=SENMA lifecycle-smoke ${ext}" \
        --data-urlencode "exten=${ext}" \
        --data-urlencode "technology=pjsip" \
        --data-urlencode "password=${secret}" \
        --data-urlencode "passwordpadlock=" \
        --data-urlencode "email=" \
        --data-urlencode "exten_group[]=1" \
        --data-urlencode "pickup_group=" \
        --data-urlencode "nat_auto_force_rport=1" \
        --data-urlencode "nat_auto_comedia=1" \
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
    log "create_extension_nat_auto ${ext} failed (HTTP $httpcode): $(grep -o 'Server Message[^<]*' "$body" || head -c 300 "$body")"
    rm -f "$body"
    return 1
}

# edit_extension_nat_explicit_no <ext> <secret> -- identical POST shape,
# only the NAT selection changes (auto_* -> "no"): the one variable this
# update proof isolates.
edit_extension_nat_explicit_no() {
    local ext="$1" secret="$2" body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "name=SENMA lifecycle-smoke ${ext}" \
        --data-urlencode "exten=${ext}" \
        --data-urlencode "technology=pjsip" \
        --data-urlencode "password=${secret}" \
        --data-urlencode "passwordpadlock=" \
        --data-urlencode "email=" \
        --data-urlencode "exten_group[]=1" \
        --data-urlencode "pickup_group=" \
        --data-urlencode "nat_no=1" \
        --data-urlencode "qualify=1" \
        --data-urlencode "type=friend" \
        --data-urlencode "directmedia=no" \
        --data-urlencode "dtmf=rfc2833" \
        --data-urlencode "codec=alaw" \
        --data-urlencode "codec1=ulaw" \
        --data-urlencode "codec2=gsm" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/extensions/edit/id/${ext}")"
    if [ "$httpcode" = "302" ]; then
        rm -f "$body"
        return 0
    fi
    log "edit_extension_nat_explicit_no ${ext} failed (HTTP $httpcode): $(grep -o 'Server Message[^<]*' "$body" || head -c 300 "$body")"
    rm -f "$body"
    return 1
}

# delete_extension <ext> -- idempotent (verified), same reasoning as
# delete_trunk above.
delete_extension() {
    local ext="$1" httpcode
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "id=${ext}" \
        --data-urlencode "delete=Delete" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/extensions/remove")"
    [ "$httpcode" = "302" ]
}

# --- 1. Required containers healthy ---------------------------------------

log "==> checking required containers"
harness_require_containers app asterisk db
harness_require_env DB_USER DB_PASSWORD DB_NAME TRUNK_TEST_USERNAME TRUNK_TEST_SECRET

log "==> checking PJSIP module state"
pjsip_modules_running() {
    $COMPOSE exec -T asterisk asterisk -rx 'module show like res_pjsip.so' 2>&1 | grep -q "Running" \
        && $COMPOSE exec -T asterisk asterisk -rx 'module show like chan_pjsip.so' 2>&1 | grep -q "Running"
}
if harness_retry 5 2 -- pjsip_modules_running; then
    harness_ok "PJSIP modules Running" "res_pjsip.so and chan_pjsip.so both Running"
else
    harness_blocked "res_pjsip.so/chan_pjsip.so not both Running (checked 5 times over 8s)"
fi

# --- 2. Log in --------------------------------------------------------------

COOKIEJAR="$(mktemp)"
harness_register_best_effort_cleanup "cookie jar temp file" "rm -f '$COOKIEJAR'"
log "==> logging in as ${TEST_USER}"
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${TEST_PASSWORD}');" 2>/dev/null | tr -d '\r')"
if [ -z "$TEST_HASH" ]; then
    harness_blocked "could not compute the ${TEST_USER} password hash via the app container"
fi
db_query "UPDATE users SET password = '${TEST_HASH}' WHERE name = '${TEST_USER}';" >&2
http_login
ADMIN_CSRF="$(harness_csrf_token "$COOKIEJAR" "$BASE_URL")"
if [ -z "$ADMIN_CSRF" ]; then harness_blocked "could not read the admin session's CSRF token"; fi

# --- 3. Stale-fixture recovery ----------------------------------------------

log "==> checking for a leftover trunk fixture from a prior interrupted run"
LEFTOVER_TRUNK_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${TRUNK_CALLERID}';")"
if [ -n "$LEFTOVER_TRUNK_ID" ]; then
    LEFTOVER_TRUNK_NAME="$(db_query "SELECT name FROM trunks WHERE id=${LEFTOVER_TRUNK_ID};")"
    if [ -z "$LEFTOVER_TRUNK_NAME" ]; then
        harness_blocked "found a leftover trunk fixture (id=${LEFTOVER_TRUNK_ID}) but could not look up its persisted name -- refusing to proceed"
    fi
    delete_trunk "$LEFTOVER_TRUNK_ID" "$LEFTOVER_TRUNK_NAME" \
        || harness_blocked "found a leftover trunk fixture (id=${LEFTOVER_TRUNK_ID}, name=${LEFTOVER_TRUNK_NAME}) from a prior interrupted run but the supported delete path did not return 302 -- refusing to proceed with a raw SQL fallback"
    log "removed leftover trunk fixture id=${LEFTOVER_TRUNK_ID}"
fi

log "==> checking for a leftover extension fixture from a prior interrupted run"
EXISTING_EXT_CANAL="$(db_query "SELECT canal FROM peers WHERE name='${TEST_EXT}';")"
EXISTING_EXT_SECRET="$(db_query "SELECT secret FROM peers WHERE name='${TEST_EXT}';")"
if [ -n "$EXISTING_EXT_CANAL" ]; then
    if [ "$EXISTING_EXT_CANAL" = "PJSIP/${TEST_EXT}" ] && [[ "$EXISTING_EXT_SECRET" == "${FIXTURE_MARKER}"* ]]; then
        delete_extension "$TEST_EXT" || harness_blocked "found a leftover lifecycle-smoke fixture for extension ${TEST_EXT} but the HTTP delete flow did not return 302 -- refusing to proceed with a raw SQL fallback"
        log "removed leftover extension fixture ${TEST_EXT}"
    else
        harness_blocked "peers row for extension '${TEST_EXT}' already exists (canal='${EXISTING_EXT_CANAL}') and is NOT a lifecycle-smoke fixture. Refusing to overwrite real/unknown data."
    fi
fi

# =============================================================================
# PART A -- registrationless trunk (reverse_auth=0), qualify "specify",
#           NAT auto_*, update, delete-cleanup
# =============================================================================

# --- 4. Create the trunk with reverse_auth=0 --------------------------------

log "==> creating registrationless trunk (reverse_auth not sent), qualify=specify(2000ms), NAT auto_force_rport+auto_comedia"
if create_trunk 0; then
    CREATED_TRUNK_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${TRUNK_CALLERID}';")"
    if [ -z "$CREATED_TRUNK_ID" ]; then
        harness_blocked "trunk creation returned 302 but no matching trunks row was found afterward"
    fi
    CREATED_TRUNK_NAME="$(db_query "SELECT name FROM trunks WHERE id=${CREATED_TRUNK_ID};")"
    if [ -z "$CREATED_TRUNK_NAME" ]; then
        harness_blocked "trunk id=${CREATED_TRUNK_ID} was created but its persisted name could not be looked up -- cannot register a correct cleanup path"
    fi
    harness_register_cleanup "trunk id=${CREATED_TRUNK_ID} name=${CREATED_TRUNK_NAME} (lifecycle-smoke fixture)" "delete_trunk ${CREATED_TRUNK_ID} '${CREATED_TRUNK_NAME}'"
    REVERSE_AUTH_DB="$(db_query "SELECT reverse_auth FROM trunks WHERE id=${CREATED_TRUNK_ID};")"
    if [ "$REVERSE_AUTH_DB" = "0" ]; then
        harness_ok "trunk created with reverse_auth=0" "trunks.reverse_auth persisted as 0 (id=${CREATED_TRUNK_ID})"
    else
        harness_bad "trunk created with reverse_auth=0" "expected reverse_auth=0, got '${REVERSE_AUTH_DB}'"
    fi
else
    harness_blocked "creating the registrationless test trunk via the real UI flow failed -- see log above"
fi

TRUNK_OBJ="trunk-${CREATED_TRUNK_ID}"

# --- 5. Generated config: endpoint+auth+aor present, NO registration -------

log "==> checking generated config (endpoint/auth/aor present, registration ABSENT)"
GENERATED_TRUNK_CONF="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip-trunks.conf 2>/dev/null)"
if echo "$GENERATED_TRUNK_CONF" | grep -q "^\[${TRUNK_OBJ}\]" \
    && echo "$GENERATED_TRUNK_CONF" | grep -q "^\[${TRUNK_OBJ}-auth\]"; then
    harness_ok "generated endpoint/auth/aor sections exist" "senma-pjsip-trunks.conf contains [${TRUNK_OBJ}], [${TRUNK_OBJ}-auth]"
else
    harness_bad "generated endpoint/auth/aor sections exist" "expected sections not found in senma-pjsip-trunks.conf"
fi
if echo "$GENERATED_TRUNK_CONF" | grep -q "^\[${TRUNK_OBJ}-registration\]"; then
    harness_bad "no registration section generated (reverse_auth=0)" "found an unexpected [${TRUNK_OBJ}-registration] section"
else
    harness_ok "no registration section generated (reverse_auth=0)" "[${TRUNK_OBJ}-registration] correctly absent from senma-pjsip-trunks.conf"
fi

ENDPOINT_BLOCK="$(extract_pjsip_block "$GENERATED_TRUNK_CONF" "$TRUNK_OBJ" "endpoint")"
AOR_BLOCK="$(extract_pjsip_block "$GENERATED_TRUNK_CONF" "$TRUNK_OBJ" "aor")"

if echo "$ENDPOINT_BLOCK" | grep -q "^force_rport=yes$" && echo "$ENDPOINT_BLOCK" | grep -q "^rtp_symmetric=yes$"; then
    harness_ok "generated NAT auto_* mapping (trunk)" "endpoint stanza has force_rport=yes/rtp_symmetric=yes from auto_force_rport+auto_comedia alone (TASK-0028Y gaps #1/#3)"
else
    harness_bad "generated NAT auto_* mapping (trunk)" "expected force_rport=yes/rtp_symmetric=yes in the endpoint stanza:\n${ENDPOINT_BLOCK}"
fi

if echo "$AOR_BLOCK" | grep -q "^qualify_frequency=2$"; then
    harness_ok "generated qualify_frequency (trunk, specify=2000ms)" "aor stanza has qualify_frequency=2 (2000ms -> 2s, TASK-0028Y gap #1)"
else
    harness_bad "generated qualify_frequency (trunk, specify=2000ms)" "expected qualify_frequency=2 in the aor stanza:\n${AOR_BLOCK}"
fi

if [ "$_HARNESS_FAIL_COUNT" -gt 0 ]; then
    log "generated-config verification failed -- aborting before live checks"
    harness_complete
fi

# --- 6. Live Asterisk state --------------------------------------------------

log "==> checking live Asterisk PJSIP state"
# TASK-0027 finding (reused here): a PJSIP reload is not atomic from a
# freshly-spawned `docker compose exec`'s perspective -- bounded retry.
trunk_endpoint_visible() { $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${TRUNK_OBJ}" 2>&1 | grep -q "Endpoint:  ${TRUNK_OBJ}"; }
if harness_retry 5 1 -- trunk_endpoint_visible; then
    harness_ok "pjsip show endpoint ${TRUNK_OBJ}" "endpoint exists live (reload succeeded)"
else
    harness_bad "pjsip show endpoint ${TRUNK_OBJ}" "endpoint not found after 5 attempts over ~4s -- reload may have failed"
fi

LIVE_ENDPOINT_DETAIL="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${TRUNK_OBJ}" 2>&1)"
if echo "$LIVE_ENDPOINT_DETAIL" | grep -qE 'force_rport[[:space:]]*:[[:space:]]*true' \
    && echo "$LIVE_ENDPOINT_DETAIL" | grep -qE 'rtp_symmetric[[:space:]]*:[[:space:]]*true'; then
    harness_ok "live NAT auto_* mapping (trunk)" "pjsip show endpoint ${TRUNK_OBJ}: force_rport=true, rtp_symmetric=true"
else
    harness_bad "live NAT auto_* mapping (trunk)" "expected force_rport/rtp_symmetric=true in live endpoint detail"
fi

LIVE_AOR_DETAIL="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show aor ${TRUNK_OBJ}" 2>&1)"
if echo "$LIVE_AOR_DETAIL" | grep -qE 'qualify_frequency[[:space:]]*:[[:space:]]*2$'; then
    harness_ok "live qualify_frequency (trunk)" "pjsip show aor ${TRUNK_OBJ}: qualify_frequency=2"
else
    harness_bad "live qualify_frequency (trunk)" "expected qualify_frequency=2 in live aor detail: $LIVE_AOR_DETAIL"
fi

LIVE_REGISTRATIONS="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show registrations outbound" 2>&1)"
if echo "$LIVE_REGISTRATIONS" | grep -q "${TRUNK_OBJ}-registration"; then
    harness_bad "no live outbound registration object (reverse_auth=0)" "unexpectedly found ${TRUNK_OBJ}-registration: $LIVE_REGISTRATIONS"
else
    harness_ok "no live outbound registration object (reverse_auth=0)" "${TRUNK_OBJ}-registration correctly absent from 'pjsip show registrations outbound'"
fi

if echo "$($COMPOSE exec -T asterisk asterisk -rx "pjsip show identifies" 2>&1)" | grep -q "${TRUNK_OBJ}-identify/${TRUNK_OBJ}"; then
    harness_ok "live identify object present" "${TRUNK_OBJ}-identify/${TRUNK_OBJ} found (inbound identification, TASK-0016, unaffected by reverse_auth)"
else
    harness_bad "live identify object present" "${TRUNK_OBJ}-identify not found in 'pjsip show identifies'"
fi

# --- 7. Update: enable reverse_auth, prove a registration object appears ---

log "==> updating the trunk to enable reverse_auth (same fixture, one field changed)"
if edit_trunk_reverse_auth "$CREATED_TRUNK_ID" "$CREATED_TRUNK_NAME" 1; then
    harness_ok "trunk update accepted" "TrunksController::editAction() returned 302"
else
    harness_bad "trunk update accepted" "edit did not return 302 -- see log above"
fi

REVERSE_AUTH_DB_AFTER="$(db_query "SELECT reverse_auth FROM trunks WHERE id=${CREATED_TRUNK_ID};")"
if [ "$REVERSE_AUTH_DB_AFTER" = "1" ]; then
    harness_ok "reverse_auth persisted as 1 after update" "trunks.reverse_auth=1"
else
    harness_bad "reverse_auth persisted as 1 after update" "expected 1, got '${REVERSE_AUTH_DB_AFTER}'"
fi

GENERATED_TRUNK_CONF_AFTER="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip-trunks.conf 2>/dev/null)"
if echo "$GENERATED_TRUNK_CONF_AFTER" | grep -q "^\[${TRUNK_OBJ}-registration\]"; then
    harness_ok "registration section now generated after update" "[${TRUNK_OBJ}-registration] now present in senma-pjsip-trunks.conf"
else
    harness_bad "registration section now generated after update" "[${TRUNK_OBJ}-registration] still absent after enabling reverse_auth"
fi

registration_now_visible() { $COMPOSE exec -T asterisk asterisk -rx "pjsip show registrations outbound" 2>&1 | grep -q "${TRUNK_OBJ}-registration"; }
if harness_retry 5 1 -- registration_now_visible; then
    harness_ok "registration object now live after update" "${TRUNK_OBJ}-registration now present in 'pjsip show registrations outbound' (status irrelevant here -- ${TRUNK_HOST} is a deliberately non-routable RFC 5737 test address; only object EXISTENCE is under test)"
else
    harness_bad "registration object now live after update" "${TRUNK_OBJ}-registration not found live after 5 attempts over ~4s"
fi

# --- 8. Delete: explicit delete + verify absence (not just HTTP 302) -------

log "==> deleting the trunk and verifying full cleanup (generated config + live Asterisk + DB, not just HTTP redirect)"
if delete_trunk "$CREATED_TRUNK_ID" "$CREATED_TRUNK_NAME"; then
    harness_ok "trunk delete request accepted" "TrunksController::removeAction() returned 302"
else
    harness_bad "trunk delete request accepted" "delete did not return 302 -- see log above"
fi

trunk_gone_from_generated_config() {
    ! $COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip-trunks.conf 2>/dev/null | grep -q "${TRUNK_OBJ}"
}
if harness_retry 5 1 -- trunk_gone_from_generated_config; then
    harness_ok "trunk absent from generated config after delete" "no ${TRUNK_OBJ}* section remains in senma-pjsip-trunks.conf"
else
    harness_bad "trunk absent from generated config after delete" "a ${TRUNK_OBJ}* section is still present after 5 attempts over ~4s"
fi

trunk_endpoint_gone() { $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${TRUNK_OBJ}" 2>&1 | grep -q "Unable to find object"; }
if harness_retry 5 1 -- trunk_endpoint_gone; then
    harness_ok "live endpoint gone after delete" "pjsip show endpoint ${TRUNK_OBJ}: Unable to find object"
else
    harness_bad "live endpoint gone after delete" "endpoint still resolves live after 5 attempts over ~4s"
fi

trunk_aor_gone() { $COMPOSE exec -T asterisk asterisk -rx "pjsip show aor ${TRUNK_OBJ}" 2>&1 | grep -q "Unable to find object"; }
if harness_retry 5 1 -- trunk_aor_gone; then
    harness_ok "live aor gone after delete" "pjsip show aor ${TRUNK_OBJ}: Unable to find object"
else
    harness_bad "live aor gone after delete" "aor still resolves live after 5 attempts over ~4s"
fi

if $COMPOSE exec -T asterisk asterisk -rx "pjsip show auths" 2>&1 | grep -q "${TRUNK_OBJ}-auth"; then
    harness_bad "live auth gone after delete" "${TRUNK_OBJ}-auth still listed in 'pjsip show auths'"
else
    harness_ok "live auth gone after delete" "${TRUNK_OBJ}-auth absent from 'pjsip show auths'"
fi

if $COMPOSE exec -T asterisk asterisk -rx "pjsip show registrations outbound" 2>&1 | grep -q "${TRUNK_OBJ}-registration"; then
    harness_bad "live registration gone after delete" "${TRUNK_OBJ}-registration still listed"
else
    harness_ok "live registration gone after delete" "${TRUNK_OBJ}-registration absent from 'pjsip show registrations outbound'"
fi

if $COMPOSE exec -T asterisk asterisk -rx "pjsip show identifies" 2>&1 | grep -q "${TRUNK_OBJ}-identify"; then
    harness_bad "live identify gone after delete" "${TRUNK_OBJ}-identify still listed"
else
    harness_ok "live identify gone after delete" "${TRUNK_OBJ}-identify absent from 'pjsip show identifies'"
fi

TRUNK_DB_COUNT="$(db_query "SELECT COUNT(*) FROM trunks WHERE id=${CREATED_TRUNK_ID};")"
PEERS_DB_COUNT="$(db_query "SELECT COUNT(*) FROM peers WHERE name='${CREATED_TRUNK_NAME}' AND peer_type='T';")"
if [ "$TRUNK_DB_COUNT" = "0" ] && [ "$PEERS_DB_COUNT" = "0" ]; then
    harness_ok "DB rows gone after delete" "trunks and peers rows both removed"
else
    harness_bad "DB rows gone after delete" "trunks count=${TRUNK_DB_COUNT} peers count=${PEERS_DB_COUNT} (expected 0/0)"
fi

# =============================================================================
# PART B -- extension update beyond transport_id + delete-cleanup proof
# =============================================================================

# --- 9. Create extension with NAT auto_* only -------------------------------

log "==> creating extension ${TEST_EXT} with NAT auto_force_rport+auto_comedia only"
if create_extension_nat_auto "$TEST_EXT" "$TEST_EXT_SECRET"; then
    harness_register_cleanup "extension ${TEST_EXT} (lifecycle-smoke fixture)" "delete_extension ${TEST_EXT}"
    harness_ok "extension fixture created" "extension ${TEST_EXT} provisioned through the real ExtensionsController::addAction() HTTP flow"
else
    harness_blocked "creating extension ${TEST_EXT} via the real UI flow failed -- see log above"
fi

GENERATED_EXT_CONF="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip.conf 2>/dev/null)"
EXT_ENDPOINT_BLOCK="$(extract_pjsip_block "$GENERATED_EXT_CONF" "$TEST_EXT" "endpoint")"
if echo "$EXT_ENDPOINT_BLOCK" | grep -q "^force_rport=yes$" && echo "$EXT_ENDPOINT_BLOCK" | grep -q "^rtp_symmetric=yes$"; then
    harness_ok "generated NAT auto_* mapping (extension, create)" "endpoint stanza has force_rport=yes/rtp_symmetric=yes from auto_force_rport+auto_comedia alone (TASK-0028Y gap #2)"
else
    harness_bad "generated NAT auto_* mapping (extension, create)" "expected force_rport=yes/rtp_symmetric=yes in the endpoint stanza:\n${EXT_ENDPOINT_BLOCK}"
fi

ext_endpoint_visible() { $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${TEST_EXT}" 2>&1 | grep -q "Endpoint:  ${TEST_EXT}/${TEST_EXT}"; }
if harness_retry 5 1 -- ext_endpoint_visible; then
    harness_ok "pjsip show endpoint ${TEST_EXT}" "endpoint exists live (reload succeeded)"
else
    harness_bad "pjsip show endpoint ${TEST_EXT}" "endpoint not found after 5 attempts over ~4s -- reload may have failed"
    harness_complete
fi

LIVE_EXT_DETAIL="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${TEST_EXT}" 2>&1)"
if echo "$LIVE_EXT_DETAIL" | grep -qE 'force_rport[[:space:]]*:[[:space:]]*true' \
    && echo "$LIVE_EXT_DETAIL" | grep -qE 'rtp_symmetric[[:space:]]*:[[:space:]]*true'; then
    harness_ok "live NAT auto_* mapping (extension, create)" "force_rport=true, rtp_symmetric=true"
else
    harness_bad "live NAT auto_* mapping (extension, create)" "expected force_rport/rtp_symmetric=true in live endpoint detail"
fi

# --- 10. Update: NAT auto_* -> explicit "no" (a real field beyond transport_id) --

log "==> updating extension ${TEST_EXT}: NAT auto_* -> explicit 'no' (transport_id itself is already covered exhaustively by transport-smoke-test.sh; this proves a DIFFERENT field's update reaches config+runtime)"
if edit_extension_nat_explicit_no "$TEST_EXT" "$TEST_EXT_SECRET"; then
    harness_ok "extension update accepted" "ExtensionsController::editAction() returned 302"
else
    harness_bad "extension update accepted" "edit did not return 302 -- see log above"
fi

GENERATED_EXT_CONF_AFTER="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip.conf 2>/dev/null)"
EXT_ENDPOINT_BLOCK_AFTER="$(extract_pjsip_block "$GENERATED_EXT_CONF_AFTER" "$TEST_EXT" "endpoint")"
if echo "$EXT_ENDPOINT_BLOCK_AFTER" | grep -q "^force_rport=no$" && echo "$EXT_ENDPOINT_BLOCK_AFTER" | grep -q "^rtp_symmetric=no$"; then
    harness_ok "generated NAT change after update" "endpoint stanza now has force_rport=no/rtp_symmetric=no"
else
    harness_bad "generated NAT change after update" "expected force_rport=no/rtp_symmetric=no after update:\n${EXT_ENDPOINT_BLOCK_AFTER}"
fi

ext_nat_updated_live() {
    $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${TEST_EXT}" 2>&1 \
        | grep -qE 'force_rport[[:space:]]*:[[:space:]]*false' \
        && $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${TEST_EXT}" 2>&1 \
        | grep -qE 'rtp_symmetric[[:space:]]*:[[:space:]]*false'
}
if harness_retry 5 1 -- ext_nat_updated_live; then
    harness_ok "live NAT change after update" "force_rport=false, rtp_symmetric=false after reload"
else
    harness_bad "live NAT change after update" "endpoint still reports force_rport/rtp_symmetric=true after 5 attempts over ~4s"
fi

# --- 11. Delete: explicit delete + verify absence ---------------------------

log "==> deleting extension ${TEST_EXT} and verifying full cleanup (generated config + live Asterisk + DB, not just HTTP redirect)"
if delete_extension "$TEST_EXT"; then
    harness_ok "extension delete request accepted" "ExtensionsController::removeAction() returned 302"
else
    harness_bad "extension delete request accepted" "delete did not return 302 -- see log above"
fi

ext_gone_from_generated_config() {
    ! $COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip.conf 2>/dev/null | grep -q "^\[${TEST_EXT}\]"
}
if harness_retry 5 1 -- ext_gone_from_generated_config; then
    harness_ok "extension absent from generated config after delete" "no [${TEST_EXT}] section remains in senma-pjsip.conf"
else
    harness_bad "extension absent from generated config after delete" "[${TEST_EXT}] still present after 5 attempts over ~4s"
fi

ext_endpoint_gone() { $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${TEST_EXT}" 2>&1 | grep -q "Unable to find object"; }
if harness_retry 5 1 -- ext_endpoint_gone; then
    harness_ok "live endpoint gone after delete" "pjsip show endpoint ${TEST_EXT}: Unable to find object"
else
    harness_bad "live endpoint gone after delete" "endpoint still resolves live after 5 attempts over ~4s"
fi

ext_aor_gone() { $COMPOSE exec -T asterisk asterisk -rx "pjsip show aor ${TEST_EXT}" 2>&1 | grep -q "Unable to find object"; }
if harness_retry 5 1 -- ext_aor_gone; then
    harness_ok "live aor gone after delete" "pjsip show aor ${TEST_EXT}: Unable to find object"
else
    harness_bad "live aor gone after delete" "aor still resolves live after 5 attempts over ~4s"
fi

EXT_DB_COUNT="$(db_query "SELECT COUNT(*) FROM peers WHERE name='${TEST_EXT}';")"
if [ "$EXT_DB_COUNT" = "0" ]; then
    harness_ok "DB row gone after delete" "peers row removed"
else
    harness_bad "DB row gone after delete" "peers count=${EXT_DB_COUNT} (expected 0)"
fi

# --- Cleanup happens via harness_complete's cleanup pass too (both
#     delete_trunk/delete_extension are idempotent -- the explicit
#     delete-and-verify steps above already did the real work; the
#     registered safety net only matters if something earlier aborted) --

harness_complete
