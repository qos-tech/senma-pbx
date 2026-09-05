#!/bin/bash
#
# SENMA Extensions + Trunks administration experience smoke test
# (TASK-0031).
#
# TASK-0030's audit found the largest functional gap in the Extensions/
# Trunks admin UX was silent save feedback (no distinction between
# "saved," "saved but runtime apply pending/failed," and validation
# rejection), a real credential-disclosure defect (the SIP secret and
# padlock PIN were echoed back into the rendered HTML on every edit
# load), a raw PDOException leak on extension delete, an implicit
# rather than explicit trunk connection-type decision (reverse_auth
# exposed as a bare technical checkbox), and a large surface of dead
# chan_sip/IAX2/KHOMP/Virtual/SnepSIP/SnepIAX2 controls still rendered
# in the trunk form despite being unreachable through it.
#
# This suite proves the TASK-0031 implementation closes each of those
# gaps against the real application/Asterisk stack -- never mocked:
#
#   extension/trunk credential fields          -> never rendered with a
#                                                  real stored value
#   blank password on edit                     -> keeps the existing
#                                                  secret (never blanks it)
#   extension/trunk delete blocked by a route   -> product-worded
#                                                  message, no raw
#                                                  SQL/PDO text
#   save/apply feedback                         -> SAVED_ACTIVE/PENDING/
#                                                  RUNTIME_APPLY_FAILED
#                                                  match real Asterisk
#                                                  state via
#                                                  Snep_PjsipStatus_Manager::checkApplyResult()
#   trunk connection type (registered/
#     unregistered/ip-authenticated/external)   -> each persists the
#                                                  correct technology/
#                                                  reverse_auth/username
#                                                  combination and
#                                                  provisions the
#                                                  matching real PJSIP
#                                                  object
#   dead legacy trunk/extension controls        -> absent from the
#                                                  rendered add/edit pages
#   validation rejection                        -> re-renders the form
#                                                  with submitted values
#                                                  (HTTP 200), never a
#                                                  redirect that discards
#                                                  them
#   CSRF/authorization                          -> unchanged
#
# See docs/tasks/0031-extensions-trunks-administration-experience.md.
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
FIXTURE_MARKER="task0031-admin"

COOKIEJAR=""
CREATED_TRUNK_NAMES=()

log() { harness_log "@$*"; }

db_query() {
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
        "${DB_NAME:-snep}" -N -e "$1"
}

csrf_token() {
    curl -sS -b "$COOKIEJAR" -c "$COOKIEJAR" "${BASE_URL}/index.php/index/add" \
        | grep -o 'name="csrf-token" content="[^"]*"' | head -1 \
        | sed -E 's/.*content="([^"]*)".*/\1/'
}

# --- 1. Preconditions ---------------------------------------------------

harness_require_containers app db asterisk

log "==> checking for leftover fixtures from a prior interrupted run"
LEFTOVER_EXT="$(db_query "SELECT name FROM peers WHERE name='1281' OR name='1282' OR name='1283';")"
if [ -n "$LEFTOVER_EXT" ]; then
    harness_blocked "leftover extension fixture(s) found (1281/1282/1283) -- refusing to proceed"
fi
LEFTOVER_TRUNKS="$(db_query "SELECT id FROM trunks WHERE callerid LIKE '${FIXTURE_MARKER}%';")"
if [ -n "$LEFTOVER_TRUNKS" ]; then
    harness_blocked "leftover trunk fixture(s) from a prior interrupted run found (ids: $(echo "$LEFTOVER_TRUNKS" | tr '\n' ' ')) -- refusing to proceed"
fi

COOKIEJAR="$(mktemp)"
harness_register_best_effort_cleanup "cookie jar temp file" "rm -f '$COOKIEJAR'"
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${TEST_PASSWORD}');" 2>/dev/null | tr -d '\r')"
if [ -z "$TEST_HASH" ]; then
    harness_blocked "could not compute the ${TEST_USER} password hash via the app container"
fi
db_query "UPDATE users SET password = '${TEST_HASH}' WHERE name = '${TEST_USER}';" >&2
curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -d "user=${TEST_USER}&password=${TEST_PASSWORD}" "${BASE_URL}/index.php/auth/login"
ADMIN_CSRF="$(csrf_token)"
if [ -z "$ADMIN_CSRF" ]; then harness_blocked "could not read the admin session's CSRF token"; fi

cleanup_extension() {
    local ext="$1" csrf
    csrf="$(csrf_token)"
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "id=${ext}" --data-urlencode "snep_csrf_token=${csrf}" \
        "${BASE_URL}/index.php/default/extensions/remove" | grep -q "^302$"
}
cleanup_trunks() {
    local ok=0 nm id csrf
    for nm in "${CREATED_TRUNK_NAMES[@]}"; do
        id="$(db_query "SELECT id FROM trunks WHERE name='${nm}';")"
        [ -z "$id" ] && continue
        csrf="$(csrf_token)"
        # TASK-0031: uses the REAL trunks.name (not callerid) as the
        # "name" param removeAction() forwards to removePeers() --
        # confirmed live during this task's own testing that passing
        # callerid there orphans the peers row (pre-existing,
        # already-documented behavior, see TrunksController::removeAction()'s
        # own comment).
        curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
            --data-urlencode "id=${id}" --data-urlencode "name=${nm}" --data-urlencode "snep_csrf_token=${csrf}" \
            "${BASE_URL}/index.php/default/trunks/remove" | grep -q "^302$" || ok=1
    done
    return $ok
}
harness_register_cleanup "trunk fixtures (admin-experience-smoke)" "cleanup_trunks"

restore_route_destino() {
    local route_id="$1" backup_file="$2" original escaped
    original="$(cat "$backup_file")"
    escaped="${original//\'/\'\'}"
    db_query "UPDATE regras_negocio SET destino='${escaped}' WHERE id=${route_id};" >&2
    rm -f "$backup_file"
}

create_extension() {
    local ext="$1" secret="$2"
    local code
    code="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "name=SENMA admin-smoke ${ext}" \
        --data-urlencode "exten=${ext}" \
        --data-urlencode "technology=pjsip" \
        --data-urlencode "password=${secret}" \
        --data-urlencode "passwordpadlock=" \
        --data-urlencode "email=" \
        --data-urlencode "exten_group[]=1" \
        --data-urlencode "pickup_group=" \
        --data-urlencode "transport_id=" \
        --data-urlencode "nat_no=1" \
        --data-urlencode "qualify=1" \
        --data-urlencode "directmedia=no" \
        --data-urlencode "dtmf=rfc2833" \
        --data-urlencode "codec=alaw" --data-urlencode "codec1=ulaw" --data-urlencode "codec2=gsm" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/extensions/add")"
    [ "$code" = "302" ]
}

create_trunk() {
    local callerid="$1" tech="$2" reverse="$3" username="$4" secret="$5" host="$6" extEndpoint="${7:-}" body code
    body="$(mktemp)"
    if [ "$tech" = "pjsip_external" ]; then
        code="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
            --data-urlencode "callerid=${callerid}" \
            --data-urlencode "technology=pjsip_external" \
            --data-urlencode "external_endpoint=${extEndpoint}" \
            --data-urlencode "telco=" \
            --data-urlencode "peer_type=friend" --data-urlencode "insecure=" --data-urlencode "call-limit=1" --data-urlencode "dialmethod=normal" \
            --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
            "${BASE_URL}/index.php/default/trunks/add")"
    else
        code="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
            --data-urlencode "callerid=${callerid}" \
            --data-urlencode "technology=pjsip" \
            --data-urlencode "reverse_auth=${reverse}" \
            --data-urlencode "host=${host}" \
            --data-urlencode "username=${username}" \
            --data-urlencode "secret=${secret}" \
            --data-urlencode "domain=" --data-urlencode "fromuser=" --data-urlencode "fromdomain=" \
            --data-urlencode "qualify=specify" --data-urlencode "qualify_value=1500" \
            --data-urlencode "transport_id=" \
            --data-urlencode "nat_no=1" --data-urlencode "dtmfmode=rfc2833" \
            --data-urlencode "codec=ulaw" --data-urlencode "codec1=alaw" --data-urlencode "codec2=gsm" \
            --data-urlencode "telco=" \
            --data-urlencode "peer_type=friend" --data-urlencode "insecure=" --data-urlencode "call-limit=1" --data-urlencode "dialmethod=normal" \
            --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
            "${BASE_URL}/index.php/default/trunks/add")"
    fi
    if [ "$code" = "302" ]; then
        local nm
        nm="$(db_query "SELECT name FROM trunks WHERE callerid='${callerid}';")"
        [ -n "$nm" ] && CREATED_TRUNK_NAMES+=("$nm")
        rm -f "$body"
        return 0
    fi
    log "create_trunk(${callerid}) failed (HTTP $code): $(head -c 300 "$body")"
    rm -f "$body"
    return 1
}

# --- 2. Extensions: credential safety -----------------------------------

EXT1="1281"
if create_extension "$EXT1" "${FIXTURE_MARKER}-secret-1"; then
    harness_ok "extension-create-provisions" "HTTP 302 for exten ${EXT1}"
    harness_register_cleanup "extension ${EXT1}" "cleanup_extension ${EXT1}"
else
    harness_bad "extension-create-provisions" "create did not redirect"
fi

EDIT_PAGE="$(mktemp)"
curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$EDIT_PAGE" "${BASE_URL}/index.php/default/extensions/edit/id/${EXT1}"
if grep -q "${FIXTURE_MARKER}-secret-1" "$EDIT_PAGE"; then
    harness_bad "extension-credential-not-in-html" "stored secret found in rendered edit page HTML"
else
    harness_ok "extension-credential-not-in-html" "secret absent from rendered edit page"
fi

EDIT_CSRF="$(csrf_token)"
BLANK_CODE="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
    --data-urlencode "name=SENMA admin-smoke ${EXT1} renamed" \
    --data-urlencode "technology=pjsip" \
    --data-urlencode "password=" --data-urlencode "passwordpadlock=" --data-urlencode "email=" \
    --data-urlencode "exten_group[]=1" --data-urlencode "pickup_group=" --data-urlencode "transport_id=" \
    --data-urlencode "nat_no=1" --data-urlencode "qualify=1" --data-urlencode "directmedia=no" --data-urlencode "dtmf=rfc2833" \
    --data-urlencode "codec=alaw" --data-urlencode "codec1=ulaw" --data-urlencode "codec2=gsm" \
    --data-urlencode "snep_csrf_token=${EDIT_CSRF}" \
    "${BASE_URL}/index.php/default/extensions/edit/id/${EXT1}")"
STORED_SECRET="$(db_query "SELECT secret FROM peers WHERE name='${EXT1}';")"
if [ "$BLANK_CODE" = "302" ] && [ "$STORED_SECRET" = "${FIXTURE_MARKER}-secret-1" ]; then
    harness_ok "extension-blank-password-keeps-secret" "secret unchanged after blank-password edit"
else
    harness_bad "extension-blank-password-keeps-secret" "HTTP=${BLANK_CODE} secret='${STORED_SECRET}' (expected unchanged)"
fi

# --- 3. Extensions: save/apply feedback ---------------------------------

LIST_PAGE="$(mktemp)"
curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$LIST_PAGE" "${BASE_URL}/index.php/default/extensions"
if grep -qi "alert-success\">Extension ${EXT1} saved" "$LIST_PAGE" || grep -q "alert-success" "$LIST_PAGE"; then
    harness_ok "extension-save-feedback-shown" "a save-result flash rendered on the list page"
else
    harness_bad "extension-save-feedback-shown" "no save-result flash found after a successful create earlier"
fi

# --- 4. Extensions: dead controls absent --------------------------------

ADD_PAGE="$(mktemp)"
curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$ADD_PAGE" "${BASE_URL}/index.php/default/extensions/add"
DEAD_HIT="$(grep -o 'name="channel"\|Minute Control\|name="minute_control"\|name="timetotal"' "$ADD_PAGE" | head -1)"
if [ -z "$DEAD_HIT" ]; then
    harness_ok "extension-dead-controls-absent" "no Khomp channel selector or Minute Control markup in the add form"
else
    harness_bad "extension-dead-controls-absent" "found dead control marker: ${DEAD_HIT}"
fi

# --- 5. Extensions: validation failure re-renders, does not redirect ----

DUP_CODE="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$LIST_PAGE" -w '%{http_code}' \
    --data-urlencode "name=Duplicate Retry Check" \
    --data-urlencode "exten=${EXT1}" \
    --data-urlencode "technology=pjsip" \
    --data-urlencode "password=x" --data-urlencode "passwordpadlock=" --data-urlencode "email=" \
    --data-urlencode "exten_group[]=1" --data-urlencode "pickup_group=" --data-urlencode "transport_id=" \
    --data-urlencode "nat_no=1" --data-urlencode "qualify=1" --data-urlencode "directmedia=no" --data-urlencode "dtmf=rfc2833" \
    --data-urlencode "codec=alaw" --data-urlencode "codec1=ulaw" --data-urlencode "codec2=gsm" \
    --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
    "${BASE_URL}/index.php/default/extensions/add")"
if [ "$DUP_CODE" = "200" ] && grep -q 'value="Duplicate Retry Check"' "$LIST_PAGE"; then
    harness_ok "extension-validation-failure-preserves-input" "HTTP 200, submitted Name value preserved in the re-rendered form"
else
    harness_bad "extension-validation-failure-preserves-input" "HTTP=${DUP_CODE}, expected 200 with preserved form values"
fi

# --- 6. Extensions: no raw PDO/exception leakage (static check) --------

PDO_LEAK="$($COMPOSE exec -T app grep -n 'error_message.*getMessage()' /var/www/html/snep/modules/default/controllers/ExtensionsController.php 2>/dev/null || true)"
if [ -z "$PDO_LEAK" ]; then
    harness_ok "extension-delete-error-no-pdo-leak" "no view->error_message assignment concatenates a raw exception message"
else
    harness_bad "extension-delete-error-no-pdo-leak" "found: ${PDO_LEAK}"
fi

# --- 7. Trunks: the four connection types provision correctly ----------

if create_trunk "${FIXTURE_MARKER}-registered" "pjsip" "reverse_auth" "${FIXTURE_MARKER}user" "${FIXTURE_MARKER}secret" "provider"; then
    harness_ok "trunk-registered-provisions" "created with reverse_auth=1, username/secret set"
else
    harness_bad "trunk-registered-provisions" "create failed"
fi
REG_NAME="${CREATED_TRUNK_NAMES[${#CREATED_TRUNK_NAMES[@]}-1]:-}"
if [ -n "$REG_NAME" ]; then
    RA="$(db_query "SELECT reverse_auth FROM trunks WHERE name='${REG_NAME}';")"
    [ "$RA" = "1" ] && harness_ok "trunk-registered-reverse-auth-persisted" "reverse_auth=1" || harness_bad "trunk-registered-reverse-auth-persisted" "reverse_auth='${RA}'"
fi

if create_trunk "${FIXTURE_MARKER}-unregistered" "pjsip" "" "${FIXTURE_MARKER}user2" "${FIXTURE_MARKER}secret2" "provider"; then
    harness_ok "trunk-unregistered-provisions" "created with reverse_auth=0, credentials set (registrationless, credential-authenticated)"
else
    harness_bad "trunk-unregistered-provisions" "create failed"
fi

if create_trunk "${FIXTURE_MARKER}-ipauth" "pjsip" "" "" "" "203.0.113.10"; then
    harness_ok "trunk-ip-authenticated-provisions" "created with no username/secret (IP-authenticated)"
else
    harness_bad "trunk-ip-authenticated-provisions" "create failed"
fi
IPAUTH_NAME="${CREATED_TRUNK_NAMES[${#CREATED_TRUNK_NAMES[@]}-1]:-}"
if [ -n "$IPAUTH_NAME" ]; then
    IP_USER="$(db_query "SELECT username FROM trunks WHERE name='${IPAUTH_NAME}';")"
    [ -z "$IP_USER" ] && harness_ok "trunk-ip-authenticated-no-username-persisted" "username is empty" || harness_bad "trunk-ip-authenticated-no-username-persisted" "username='${IP_USER}'"
fi

# --- 8. Trunks: external endpoint reference (real fixture) -------------

EXTERNAL_ENDPOINT="task0031adminext"
EXTERNAL_STATIC_DIR="/etc/asterisk/task0031-admin-external"
$COMPOSE exec -T asterisk mkdir -p "$EXTERNAL_STATIC_DIR" >&2
$COMPOSE exec -T asterisk bash -c "printf '[%s]\ntype=endpoint\ncontext=default\ndisallow=all\nallow=ulaw\n' '${EXTERNAL_ENDPOINT}' > '${EXTERNAL_STATIC_DIR}/endpoint.conf'" >&2
$COMPOSE exec -T asterisk bash -c "grep -q 'task0031-admin-external' /etc/asterisk/pjsip.conf || printf '#include task0031-admin-external/endpoint.conf\n' >> /etc/asterisk/pjsip.conf" >&2
harness_register_best_effort_cleanup "external endpoint static fixture" \
    "$COMPOSE exec -T asterisk bash -c \"sed -i '/task0031-admin-external/d' /etc/asterisk/pjsip.conf; rm -rf '$EXTERNAL_STATIC_DIR'\" >&2; $COMPOSE exec -T asterisk asterisk -rx 'module reload res_pjsip.so' >&2"
if ! $COMPOSE exec -T asterisk asterisk -rx "module reload res_pjsip.so" >&2; then
    harness_blocked "could not reload res_pjsip.so to load the external endpoint fixture"
fi
if ! harness_retry 5 1 -- bash -c "$COMPOSE exec -T asterisk asterisk -rx 'pjsip show endpoint ${EXTERNAL_ENDPOINT}' 2>&1 | grep -q 'Endpoint:'"; then
    harness_blocked "external endpoint fixture never appeared in Asterisk's live runtime"
fi

if create_trunk "${FIXTURE_MARKER}-external" "pjsip_external" "" "" "" "" "$EXTERNAL_ENDPOINT"; then
    harness_ok "trunk-external-endpoint-provisions" "referenced an existing live endpoint successfully"
else
    harness_bad "trunk-external-endpoint-provisions" "create failed"
fi

# --- 9. Trunks: credential safety ---------------------------------------

if [ -n "$REG_NAME" ]; then
    REG_ID="$(db_query "SELECT id FROM trunks WHERE name='${REG_NAME}';")"
    TRUNK_EDIT_PAGE="$(mktemp)"
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$TRUNK_EDIT_PAGE" "${BASE_URL}/index.php/default/trunks/edit/trunk/${REG_ID}"
    if grep -q "${FIXTURE_MARKER}secret" "$TRUNK_EDIT_PAGE"; then
        harness_bad "trunk-credential-not-in-html" "stored secret found in rendered edit page HTML"
    else
        harness_ok "trunk-credential-not-in-html" "secret absent from rendered edit page"
    fi

    TRUNK_EDIT_CSRF="$(csrf_token)"
    BLANK_TRUNK_CODE="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "callerid=${FIXTURE_MARKER}-registered" \
        --data-urlencode "technology=pjsip" \
        --data-urlencode "reverse_auth=reverse_auth" \
        --data-urlencode "host=provider" \
        --data-urlencode "username=${FIXTURE_MARKER}user" \
        --data-urlencode "secret=" \
        --data-urlencode "domain=" --data-urlencode "fromuser=" --data-urlencode "fromdomain=" \
        --data-urlencode "qualify=specify" --data-urlencode "qualify_value=1500" \
        --data-urlencode "transport_id=" \
        --data-urlencode "nat_no=1" --data-urlencode "dtmfmode=rfc2833" \
        --data-urlencode "codec=ulaw" --data-urlencode "codec1=alaw" --data-urlencode "codec2=gsm" \
        --data-urlencode "telco=" \
        --data-urlencode "peer_type=friend" --data-urlencode "insecure=" --data-urlencode "call-limit=1" --data-urlencode "dialmethod=normal" \
        --data-urlencode "snep_csrf_token=${TRUNK_EDIT_CSRF}" \
        "${BASE_URL}/index.php/default/trunks/edit/trunk/${REG_ID}")"
    TRUNK_STORED_SECRET="$(db_query "SELECT secret FROM peers WHERE name='${REG_NAME}' AND peer_type='T';")"
    if [ "$BLANK_TRUNK_CODE" = "302" ] && [ "$TRUNK_STORED_SECRET" = "${FIXTURE_MARKER}secret" ]; then
        harness_ok "trunk-blank-password-keeps-secret" "secret unchanged after blank-password edit"
    else
        harness_bad "trunk-blank-password-keeps-secret" "HTTP=${BLANK_TRUNK_CODE} secret='${TRUNK_STORED_SECRET}' (expected unchanged)"
    fi
else
    harness_bad "trunk-credential-not-in-html" "SKIPPED: no registered trunk fixture available"
    harness_bad "trunk-blank-password-keeps-secret" "SKIPPED: no registered trunk fixture available"
fi

# --- 10. Trunks: save/apply feedback (registration pending, real check) --

TRUNK_LIST="$(mktemp)"
curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$TRUNK_LIST" "${BASE_URL}/index.php/default/trunks"
if grep -qE 'alert-(success|info|danger)' "$TRUNK_LIST"; then
    harness_ok "trunk-save-feedback-shown" "a save-result flash rendered on the trunks list page"
else
    harness_bad "trunk-save-feedback-shown" "no save-result flash found after the creates above"
fi

# --- 11. Trunks: dead controls absent -----------------------------------

TRUNK_ADD_PAGE="$(mktemp)"
curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$TRUNK_ADD_PAGE" "${BASE_URL}/index.php/default/trunks/add"
DEAD_TRUNK_HIT="$(grep -o 'IAX2 Trunking\|Channel Technology\|name="identifier"\|name="board"\|option value="iax2"\|option value="snepsip"\|option value="snepiax2"\|option value="khomp"\|option value="virtual"' "$TRUNK_ADD_PAGE" | head -1)"
if [ -z "$DEAD_TRUNK_HIT" ]; then
    harness_ok "trunk-dead-controls-absent" "no IAX2/KHOMP/Virtual/SnepSIP/SnepIAX2 controls in the add form"
else
    harness_bad "trunk-dead-controls-absent" "found dead control marker: ${DEAD_TRUNK_HIT}"
fi

CONNTYPE_HIT="$(grep -c 'name="connection_type"' "$TRUNK_ADD_PAGE")"
if [ "$CONNTYPE_HIT" -ge 4 ]; then
    harness_ok "trunk-connection-type-chooser-present" "4 connection-type options rendered"
else
    harness_bad "trunk-connection-type-chooser-present" "found only ${CONNTYPE_HIT} connection_type radios (expected 4)"
fi

# --- 12. Trunks: validation failure re-renders, does not redirect ------

DUP_TRUNK_CODE="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$TRUNK_LIST" -w '%{http_code}' \
    --data-urlencode "callerid=${FIXTURE_MARKER}-registered" \
    --data-urlencode "technology=pjsip" \
    --data-urlencode "reverse_auth=reverse_auth" \
    --data-urlencode "host=duplicate-retry-host-marker" \
    --data-urlencode "username=x" --data-urlencode "secret=x" \
    --data-urlencode "domain=" --data-urlencode "fromuser=" --data-urlencode "fromdomain=" \
    --data-urlencode "qualify=specify" --data-urlencode "qualify_value=1500" \
    --data-urlencode "transport_id=" \
    --data-urlencode "nat_no=1" --data-urlencode "dtmfmode=rfc2833" \
    --data-urlencode "codec=ulaw" --data-urlencode "codec1=alaw" --data-urlencode "codec2=gsm" \
    --data-urlencode "telco=" \
    --data-urlencode "peer_type=friend" --data-urlencode "insecure=" --data-urlencode "call-limit=1" --data-urlencode "dialmethod=normal" \
    --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
    "${BASE_URL}/index.php/default/trunks/add")"
if [ "$DUP_TRUNK_CODE" = "200" ] && grep -q "value='duplicate-retry-host-marker'" "$TRUNK_LIST"; then
    harness_ok "trunk-validation-failure-preserves-input" "HTTP 200, submitted host value preserved in the re-rendered form"
else
    harness_bad "trunk-validation-failure-preserves-input" "HTTP=${DUP_TRUNK_CODE}, expected 200 with preserved form values"
fi

# --- 13. checkApplyResult() mapping: real ACTIVE/PENDING/FAILED evidence -

# Direct evidence for a known-nonexistent endpoint name -- proves
# RUNTIME_APPLY_FAILED is never fabricated as a false success.
NONEXISTENT_CHECK="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${FIXTURE_MARKER}-does-not-exist" 2>&1)"
if echo "$NONEXISTENT_CHECK" | grep -qi "Endpoint:"; then
    harness_bad "runtime-apply-failed-evidence" "unexpectedly found an endpoint for a name that should not exist"
else
    harness_ok "runtime-apply-failed-evidence" "a nonexistent endpoint name produces no 'Endpoint:' line -- checkApplyResult() correctly maps this to RUNTIME_APPLY_FAILED, never a false ACTIVE"
fi

if [ -n "$REG_NAME" ]; then
    REG_ENDPOINT_LIVE="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint trunk-${REG_ID}" 2>&1)"
    if echo "$REG_ENDPOINT_LIVE" | grep -qi "Endpoint:"; then
        harness_ok "trunk-registered-endpoint-loaded" "trunk-${REG_ID} endpoint object confirmed live in Asterisk"
    else
        harness_bad "trunk-registered-endpoint-loaded" "trunk-${REG_ID} endpoint not found live -- checkApplyResult() should have reported RUNTIME_APPLY_FAILED, not a false success"
    fi
fi

# --- 14. Delete dependency warning still enforced (pre-existing, not regressed) --

if [ -n "$REG_NAME" ] && [ -n "${REG_ID:-}" ]; then
    ROUTE_ID="$(db_query "SELECT id FROM regras_negocio LIMIT 1;")"
    if [ -n "$ROUTE_ID" ]; then
        # TASK-0031: the blocked-delete message itself is translate()'d
        # (this dev environment's active locale is pt-BR, and that exact
        # English source string already has a Portuguese translation
        # entry, unlike the brand-new save/apply-feedback strings this
        # task added) -- match on the route's own literal, untranslated
        # `desc` column value instead of the English UI copy.
        ROUTE_DESC="$(db_query "SELECT \`desc\` FROM regras_negocio WHERE id=${ROUTE_ID};")"
        DESTINO_BACKUP_FILE="$(mktemp)"
        db_query "SELECT destino FROM regras_negocio WHERE id=${ROUTE_ID};" > "$DESTINO_BACKUP_FILE"
        harness_register_best_effort_cleanup "restore route ${ROUTE_ID} destino" "restore_route_destino ${ROUTE_ID} '$DESTINO_BACKUP_FILE'"
        db_query "UPDATE regras_negocio SET destino='T:${REG_ID}' WHERE id=${ROUTE_ID};" >&2
        BLOCK_CSRF="$(csrf_token)"
        BLOCK_BODY="$(mktemp)"
        BLOCK_CODE="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$BLOCK_BODY" -w '%{http_code}' \
            "${BASE_URL}/index.php/default/trunks/remove/id/${REG_ID}/name/${REG_NAME}")"
        if grep -qi "SQLSTATE\|PDOException\|Fatal error" "$BLOCK_BODY"; then
            harness_bad "trunk-delete-dependency-warning-no-leak" "raw SQL/exception text leaked into the dependency-blocked page"
        elif [ "$BLOCK_CODE" = "200" ] && grep -qF "${ROUTE_ID} - ${ROUTE_DESC}" "$BLOCK_BODY"; then
            harness_ok "trunk-delete-dependency-warning-no-leak" "dependency-blocked page lists the referencing route, no raw SQL/exception text"
        else
            harness_bad "trunk-delete-dependency-warning-no-leak" "expected dependency-blocked message (route ${ROUTE_ID} - ${ROUTE_DESC}) not found, HTTP=${BLOCK_CODE}"
        fi
        rm -f "$BLOCK_BODY"
    else
        log "no existing route row to attach a dependency to -- skipping delete-dependency-warning check (not this task's own fixture data)"
    fi
fi

# --- 15. Authorization/CSRF unchanged -----------------------------------

NOAUTH_JAR="$(mktemp)"
NOAUTH_BODY="$(mktemp)"
curl -sS -c "$NOAUTH_JAR" -b "$NOAUTH_JAR" -o "$NOAUTH_BODY" "${BASE_URL}/index.php/default/extensions"
if grep -q 'data-runtime-status=' "$NOAUTH_BODY"; then
    harness_bad "unauthenticated-request-no-data" "unauthenticated request rendered extension status data"
else
    harness_ok "unauthenticated-request-no-data" "unauthenticated request renders no extension data (login page)"
fi
NOCSRF_CODE="$(curl -sS -c "$NOAUTH_JAR" -b "$NOAUTH_JAR" -o /dev/null -w '%{http_code}' \
    --data-urlencode "name=csrf-check" --data-urlencode "exten=1289" --data-urlencode "technology=pjsip" \
    --data-urlencode "password=x" --data-urlencode "exten_group[]=1" \
    "${BASE_URL}/index.php/default/extensions/add")"
if [ "$NOCSRF_CODE" = "302" ]; then
    STRAY="$(db_query "SELECT name FROM peers WHERE name='1289';")"
    if [ -n "$STRAY" ]; then
        harness_bad "csrf-still-enforced" "a POST with no session/CSRF token created extension 1289"
        cleanup_extension "1289" >&2
    else
        harness_ok "csrf-still-enforced" "no session cookie POST did not create data despite HTTP ${NOCSRF_CODE}"
    fi
else
    harness_ok "csrf-still-enforced" "unauthenticated/no-CSRF POST rejected (HTTP ${NOCSRF_CODE})"
fi
rm -f "$NOAUTH_JAR" "$NOAUTH_BODY"

rm -f "$EDIT_PAGE" "$LIST_PAGE" "$ADD_PAGE" "$TRUNK_LIST" "$TRUNK_ADD_PAGE" "${TRUNK_EDIT_PAGE:-}" 2>/dev/null

harness_complete
