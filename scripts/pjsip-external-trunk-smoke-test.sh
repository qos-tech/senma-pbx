#!/bin/bash
#
# TASK-0028X regression coverage: pjsip_external outbound dial-string fix.
#
# The PJSIP-only architecture review (TASK-0028W) found that a
# `pjsip_external` trunk (TASK-0028B -- a trunk referencing a PJSIP
# endpoint an administrator already configured directly in Asterisk,
# outside SENMA) never reached PBX_Asterisk_Interface_PJSIP's
# getDialStringForDestination() override. trunks.type persists as the
# literal string "PJSIP_EXTERNAL" (TrunksController::preparePost()'s
# pjsip_external branch), which PBX_Trunks::get()'s tech dispatch did not
# recognize -- it fell through to the generic `else` branch and built a
# PBX_Asterisk_Interface_VIRTUAL from trunks.channel instead. VIRTUAL
# inherits the base class's default getDialStringForDestination()
# (chan_sip's "Peer/exten" concatenation), producing
# "PJSIP/<endpoint>/<destination>" -- structurally wrong for chan_pjsip,
# which requires "exten@endpoint". PBX_Trunks::get() (snep/lib/PBX/Trunks.php)
# now has a dedicated PJSIP_EXTERNAL branch that builds the same
# PBX_Asterisk_Interface_PJSIP class the native "pjsip" branch already
# uses, so the correct "PJSIP/<destination>@<endpoint>" form is produced
# for free -- no new dial-string formatting logic. See
# docs/tasks/0028x-pjsip-external-dialstring-fix.md.
#
# Inbound behavior (id_regex / PBX_Interfaces::getChannelOwner()) is
# documented-correct and explicitly OUT OF SCOPE for this task; this
# script proves it is unaffected via a direct, non-HTTP call into the
# real PBX_Interfaces::getChannelOwner() code path (item 6 below), and
# `make regression`'s existing trunk-smoke-test.sh continuing to pass
# (item 7) is the "existing registered PJSIP trunk regression" proof.
#
# Proves, end to end, against a running `make dev` Docker environment,
# using SENMA's own real HTTP flow (not raw SQL) to create the trunk:
#
#   1. a supported pjsip_external trunk can be created/configured
#      (TrunksController::addAction(), technology=pjsip_external,
#      validated live via AMI against a real, already-existing PJSIP
#      endpoint -- see "external endpoint fixture" below);
#   2/3. outbound routing (PBX_Trunks::get() -> interface selection)
#      resolves it to PBX_Asterisk_Interface_PJSIP, and the generated
#      dial string is exactly "PJSIP/<destination>@<endpoint>" -- proven
#      both directly (scripts/pjsip-external-trunk-check.php, the exact
#      call DiscarTronco::execute() itself makes) and via a real call's
#      Asterisk log trace;
#   4. the broken "PJSIP/<endpoint>/<destination>" form does not appear
#      anywhere in that trace;
#   5. a real outbound call, placed by a SENMA-provisioned extension
#      through this trunk, actually reaches a live, independently
#      registered PJSIP endpoint (CALL_ANSWERED/CALL_ESTABLISHED, then a
#      real CDR row);
#   6. PBX_Interfaces::getChannelOwner() still resolves a synthetic
#      inbound channel name for this same trunk row to the correct
#      Snep_Trunk (this task's PBX_Trunks::get() change does not sit on
#      that match path, but this proves it directly rather than by
#      inference);
#   7. is satisfied by trunk-smoke-test.sh (native registered PJSIP
#      trunk, both directions) continuing to pass in the same
#      `make regression` run -- not re-proven here.
#
# "External endpoint" fixture: since a pjsip_external trunk-by-contract
# references a PJSIP object SENMA never generates
# (docs/tasks/0028b-pjsip-external-endpoint-trunks.md: "O SENMA não gera
# endpoint, auth nem AOR para esse objeto externo"), this script models
# exactly that -- a standalone endpoint/auth/aor trio appended directly
# to the live (named-volume, writable) /etc/asterisk/pjsip.conf inside
# the running `asterisk` container, never to the git-tracked
# docker/asterisk-config/pjsip.conf source. A disposable baresip
# container registers to it (answermode=auto) exactly like any other
# real PJSIP UA would. install_external_endpoint()/
# strip_external_endpoint_fixture() add/remove only the block after a
# unique marker line, so cleanup restores the file exactly, byte for
# byte, regardless of run history.
#
# Built on scripts/lib/harness.sh, same lifecycle/cleanup contract as
# every other stateful suite in this repo (see trunk-smoke-test.sh's own
# header for the fuller rationale). Exit code: see scripts/lib/harness.sh
# (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

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
ROUTE_SCRIPT="scripts/trunk-smoke-route.php"
CHECK_SCRIPT="scripts/pjsip-external-trunk-check.php"
TEST_USER="admin"
TEST_PASSWORD="SmokeTest123!"

FIXTURE_MARKER="task0028x-pjsip-external-smoke"
PJSIP_CONF_PATH="/etc/asterisk/pjsip.conf"
PJSIP_CONF_FIXTURE_MARKER="; TASK0028X-PJSIP-EXTERNAL-SMOKE-FIXTURE-MARKER"

EXTERNAL_ENDPOINT="task0028x-ext-endpoint"
EXTERNAL_ENDPOINT_SECRET="${FIXTURE_MARKER}-ext-secret"
EXTERNAL_BARESIP_CONTAINER="senma-pjsipext-endpoint"

CALLER_EXT=1093
CALLER_EXT_SECRET="${FIXTURE_MARKER}-caller"
CALLER_BARESIP_CONTAINER="senma-pjsipext-caller-${CALLER_EXT}"

TRUNK_CALLERID="TASK-0028X pjsip_external smoke fixture"
ROUTE_DESC="TASK-0028X pjsip_external smoke route fixture"
# Used only for the direct, non-HTTP dial-string check (step 7 below) --
# a value deliberately DIFFERENT from EXTERNAL_ENDPOINT, to prove the
# fix's "PJSIP/<destination>@<endpoint>" format for an arbitrary
# destination, not merely the degenerate case where the two coincide.
CHECK_DESTINATION=604
# Used for the real live call (step 9 below). MUST equal
# EXTERNAL_ENDPOINT: confirmed live (pjsip set logger on) that baresip
# answers an INVITE only when its Request-URI user matches its own
# configured account name exactly, rejecting any other value with a SIP
# 404 -- a real, single-line SIP UA's own behavior, not a SENMA or
# Asterisk defect. Asterisk's [default] dialplan routes any dialed
# string here regardless (extensions.conf's `_.,` pattern), so this
# does not affect dialplan routing -- only which R-URI user baresip
# itself will accept as its callee. The dial-string FORMAT is still
# fully proven with distinct values by the step 7 direct check above;
# this live call's job is proving a real call reaches a real endpoint.
TEST_DESTINATION="${EXTERNAL_ENDPOINT}"

CREATED_TRUNK_ID=""
CREATED_TRUNK_NAME=""
CREATED_EXT=0
CONF_DIR=""
COOKIEJAR=""

log() { harness_log "$@"; }

db_query() {
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
        "${DB_NAME:-snep}" -N -e "$1"
}

http_login() {
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null \
        -d "user=${TEST_USER}&password=${TEST_PASSWORD}" "${BASE_URL}/index.php/auth/login"
}

pjsip_reload() { $COMPOSE exec -T asterisk asterisk -rx "module reload res_pjsip.so" >&2; }

external_endpoint_marker_present() {
    $COMPOSE exec -T asterisk sh -c "grep -qF '${PJSIP_CONF_FIXTURE_MARKER}' '${PJSIP_CONF_PATH}'"
}

# strip_external_endpoint_fixture -- removes the marker line and
# everything after it, then trims the trailing blank line
# install_external_endpoint() always adds right before that marker (a
# `sed` range delete only removes from the marker itself onward, so
# without this second step a leftover blank line would accumulate on
# every install/strip cycle -- caught live running this script twice in
# a row). Safe/idempotent: this script only ever appends after that
# marker, and nothing else writes to this file this way, so this always
# restores the original docker/asterisk-config/pjsip.conf-assembled
# content exactly, byte for byte.
strip_external_endpoint_fixture() {
    $COMPOSE exec -T asterisk sh -c "sed -i '/^${PJSIP_CONF_FIXTURE_MARKER}\$/,\$d' '${PJSIP_CONF_PATH}' && content=\$(cat '${PJSIP_CONF_PATH}') && printf '%s\n' \"\$content\" > '${PJSIP_CONF_PATH}'"
}

install_external_endpoint() {
    $COMPOSE exec -T asterisk sh -c "cat >> '${PJSIP_CONF_PATH}'" <<EOF

${PJSIP_CONF_FIXTURE_MARKER}
; TASK-0028X regression fixture: models a PJSIP endpoint an
; administrator configures directly in Asterisk, entirely outside SENMA
; (docs/tasks/0028b-pjsip-external-endpoint-trunks.md's own contract:
; "O SENMA não gera endpoint, auth nem AOR para esse objeto externo").
; Appended only to this live, volume-backed file -- never to the
; git-tracked docker/asterisk-config/pjsip.conf source. Removed by
; strip_external_endpoint_fixture() (marker line + everything after it).
[${EXTERNAL_ENDPOINT}]
type=endpoint
context=default
disallow=all
allow=alaw,ulaw,gsm
; TrunksController::externalPjsipEndpointExists() (TASK-0028B, pre-existing,
; out of this task's scope) matches AMI's "pjsip show endpoint <name>" output
; against '/^Endpoint:\s+<name>\/.../mi' -- Asterisk only prints that
; trailing "/<cid-number>" segment when the endpoint has a callerid
; configured; a callerid-less endpoint's status line reads
; "Endpoint:  <name>  <state>" with no slash at all, which the check would
; not recognize as existing. A callerid is realistic for any real
; externally-managed endpoint anyway, so one is set here.
callerid=TASK-0028X Ext Endpoint <${EXTERNAL_ENDPOINT}>
auth=${EXTERNAL_ENDPOINT}-auth
aors=${EXTERNAL_ENDPOINT}

[${EXTERNAL_ENDPOINT}-auth]
type=auth
auth_type=userpass
username=${EXTERNAL_ENDPOINT}
password=${EXTERNAL_ENDPOINT_SECRET}

[${EXTERNAL_ENDPOINT}]
type=aor
max_contacts=1
remove_existing=yes
EOF
    pjsip_reload
}

# create_extension <ext> <secret> -- same real HTTP flow as
# trunk-smoke-test.sh/call-smoke-test.sh, an independent fixture here
# (the SENMA-provisioned extension that ORIGINATES the outbound call).
create_extension() {
    local ext="$1" secret="$2" body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "name=SENMA pjsip-external-smoke ${ext}" \
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
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/extensions/remove")"
    [ "$httpcode" = "302" ]
}

# create_pjsip_external_trunk -- POSTs to the real
# TrunksController::addAction(), technology=pjsip_external, exactly what
# the real browser form submits (trunks/addedit.phtml's
# "Endpoint PJSIP externo" option + preparePost()'s pjsip_external
# branch). Only the fields that branch actually reads are sent -- every
# other trunk_fields/ip_fields column that branch never touches.
create_pjsip_external_trunk() {
    local body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "callerid=${TRUNK_CALLERID}" \
        --data-urlencode "technology=pjsip_external" \
        --data-urlencode "external_endpoint=${EXTERNAL_ENDPOINT}" \
        --data-urlencode "telco=" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/trunks/add")"
    if [ "$httpcode" = "302" ]; then
        rm -f "$body"
        return 0
    fi
    log "create_pjsip_external_trunk failed (HTTP $httpcode): $(grep -o 'Server Message[^<]*' "$body" || head -c 300 "$body")"
    rm -f "$body"
    return 1
}

# delete_trunk <id> <name> -- <name> MUST be the trunk's real persisted
# `name` column, same constraint as trunk-smoke-test.sh's identical
# helper (TrunksController::removeAction() deletes the matching `peers`
# row by this name -- a no-op here since pjsip_external never inserts
# one, see docs/tasks/0028b).
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

# remove_route_fixture <rule_id> <label> -- via PBX_Rules::delete(),
# never raw SQL. Same helper as trunk-smoke-test.sh.
remove_route_fixture() {
    local rule_id="$1" label="$2" result
    $COMPOSE exec -T app php -- remove "$rule_id" < "$ROUTE_SCRIPT" >&2
    result=$?
    if [ "$result" = 0 ]; then
        log "removed ${label} fixture id=${rule_id}"
    else
        log "WARNING: could not remove ${label} fixture id=${rule_id}"
    fi
    return "$result"
}

# --- 1. Required containers healthy -----------------------------------------

log "==> checking required containers"
harness_require_containers app asterisk db

harness_require_env DB_USER DB_PASSWORD DB_NAME

ASTERISK_CID="$($COMPOSE ps -q asterisk)"
ASTERISK_NAME="$(docker inspect "$ASTERISK_CID" --format '{{.Name}}' | sed 's#^/##')"
NETWORK_NAME="$(docker inspect "$ASTERISK_CID" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')"
if [ -z "$ASTERISK_NAME" ] || [ -z "$NETWORK_NAME" ]; then
    harness_blocked "could not resolve the asterisk container's name/network via docker inspect"
fi
log "asterisk container: $ASTERISK_NAME  network: $NETWORK_NAME"

# --- 2. PJSIP modules Running --------------------------------------------

log "==> checking PJSIP module state"
pjsip_modules_running() {
    $COMPOSE exec -T asterisk asterisk -rx 'module show like res_pjsip.so' 2>&1 | grep -q "Running" \
        && $COMPOSE exec -T asterisk asterisk -rx 'module show like chan_pjsip.so' 2>&1 | grep -q "Running"
}
if harness_retry 5 2 -- pjsip_modules_running; then
    harness_ok "PJSIP modules Running" "res_pjsip.so and chan_pjsip.so Running"
else
    harness_blocked "res_pjsip.so/chan_pjsip.so not both Running"
fi

# --- 3. Log in ----------------------------------------------------------

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

# --- 4. Dependency-ordered stale-fixture recovery ----------------------------
#
# Same ordering rationale as trunk-smoke-test.sh: routes reference the
# trunk (TrunksController::removeAction() refuses to delete a
# still-referenced trunk), so routes are recovered first, then the
# trunk, then the extension, then (unconditionally, harmless if absent)
# the pjsip.conf marker.

log "==> checking for a leftover route fixture from a prior interrupted run"
LEFTOVER_ROUTE_ID="$(db_query "SELECT id FROM regras_negocio WHERE \`desc\`='${ROUTE_DESC}';")"
if [ -n "$LEFTOVER_ROUTE_ID" ]; then
    remove_route_fixture "$LEFTOVER_ROUTE_ID" "outbound route" \
        || harness_blocked "found a leftover route fixture (id=${LEFTOVER_ROUTE_ID}) from a prior interrupted run but could not remove it via the supported PBX_Rules::delete() path -- refusing to proceed with a raw SQL fallback"
fi

log "==> checking for a leftover trunk fixture from a prior interrupted run"
EXISTING_TRUNK_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${TRUNK_CALLERID}';")"
if [ -n "$EXISTING_TRUNK_ID" ]; then
    EXISTING_TRUNK_NAME="$(db_query "SELECT name FROM trunks WHERE id=${EXISTING_TRUNK_ID};")"
    if [ -z "$EXISTING_TRUNK_NAME" ]; then
        harness_blocked "found a leftover trunk fixture (id=${EXISTING_TRUNK_ID}) from a prior interrupted run but could not look up its persisted name -- refusing to proceed"
    fi
    log "found a leftover trunk fixture id=${EXISTING_TRUNK_ID} name=${EXISTING_TRUNK_NAME} -- removing via the supported TrunksController::removeAction() HTTP flow"
    if delete_trunk "$EXISTING_TRUNK_ID" "$EXISTING_TRUNK_NAME"; then
        log "removed leftover trunk fixture id=${EXISTING_TRUNK_ID}"
    else
        harness_blocked "found a leftover trunk fixture (id=${EXISTING_TRUNK_ID}, name=${EXISTING_TRUNK_NAME}) from a prior interrupted run but the supported delete path did not return 302 even after clearing the dependent route fixture -- refusing to proceed with a raw SQL fallback"
    fi
fi

log "==> checking for a leftover caller-extension fixture from a prior interrupted run"
EXISTING_EXT_CANAL="$(db_query "SELECT canal FROM peers WHERE name='${CALLER_EXT}';")"
EXISTING_EXT_SECRET="$(db_query "SELECT secret FROM peers WHERE name='${CALLER_EXT}';")"
if [ -n "$EXISTING_EXT_CANAL" ]; then
    if [ "$EXISTING_EXT_CANAL" = "PJSIP/${CALLER_EXT}" ] && [[ "$EXISTING_EXT_SECRET" == "${FIXTURE_MARKER}"* ]]; then
        log "extension ${CALLER_EXT} is a leftover pjsip-external-smoke fixture from a prior run -- removing via HTTP before re-creating"
        delete_extension "$CALLER_EXT" || harness_blocked "found a leftover pjsip-external-smoke fixture for extension ${CALLER_EXT} but the HTTP delete flow did not return 302 -- refusing to proceed with a raw SQL fallback"
    else
        harness_blocked "peers row for extension '${CALLER_EXT}' already exists (canal='${EXISTING_EXT_CANAL}') and is NOT a pjsip-external-smoke fixture. Refusing to overwrite real/unknown data."
    fi
fi

log "==> checking for a leftover external-endpoint fixture in pjsip.conf from a prior interrupted run"
if external_endpoint_marker_present; then
    log "found a leftover pjsip.conf fixture marker -- stripping before proceeding"
    strip_external_endpoint_fixture
    pjsip_reload
fi

# --- 5. Install the "external" (non-SENMA) PJSIP endpoint fixture -----------

log "==> installing external PJSIP endpoint fixture directly into the live Asterisk config (models an admin-managed, non-SENMA endpoint)"
install_external_endpoint
harness_register_cleanup "external PJSIP endpoint fixture (pjsip.conf restore)" "strip_external_endpoint_fixture; pjsip_reload"

endpoint_visible() { $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${EXTERNAL_ENDPOINT}" 2>&1 | grep -q "Endpoint:  ${EXTERNAL_ENDPOINT}"; }
if harness_retry 5 1 -- endpoint_visible; then
    harness_ok "external endpoint fixture live" "pjsip show endpoint ${EXTERNAL_ENDPOINT} found it in the live Asterisk PJSIP config"
else
    harness_bad "external endpoint fixture live" "endpoint not found after 5 attempts over ~4s"
    harness_complete
fi

# --- 6. item 1: supported pjsip_external trunk can be created/configured ---

log "==> creating the pjsip_external trunk via the real TrunksController::addAction() HTTP flow"
if create_pjsip_external_trunk; then
    CREATED_TRUNK_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${TRUNK_CALLERID}';")"
    if [ -z "$CREATED_TRUNK_ID" ]; then
        harness_blocked "trunk creation returned 302 but no matching trunks row was found afterward"
    fi
    CREATED_TRUNK_NAME="$(db_query "SELECT name FROM trunks WHERE id=${CREATED_TRUNK_ID};")"
    if [ -z "$CREATED_TRUNK_NAME" ]; then
        harness_blocked "trunk id=${CREATED_TRUNK_ID} was created but its persisted name could not be looked up -- cannot register a correct cleanup path"
    fi
    harness_register_cleanup "trunk id=${CREATED_TRUNK_ID} name=${CREATED_TRUNK_NAME} (pjsip-external-smoke fixture)" "delete_trunk ${CREATED_TRUNK_ID} '${CREATED_TRUNK_NAME}'"
    harness_ok "supported pjsip_external trunk can be created/configured" "trunk id=${CREATED_TRUNK_ID} created via the real HTTP flow, externalPjsipEndpointExists() validated it live via AMI against ${EXTERNAL_ENDPOINT}"
else
    harness_blocked "creating the pjsip_external trunk via the real UI flow failed -- see log above"
fi

TRUNK_ROW="$(db_query "SELECT type,trunktype,channel,id_regex,username FROM trunks WHERE id=${CREATED_TRUNK_ID};")"
TRUNK_TYPE="$(echo "$TRUNK_ROW" | awk -F'\t' '{print $1}')"
TRUNK_TRUNKTYPE="$(echo "$TRUNK_ROW" | awk -F'\t' '{print $2}')"
TRUNK_CHANNEL="$(echo "$TRUNK_ROW" | awk -F'\t' '{print $3}')"
TRUNK_ID_REGEX="$(echo "$TRUNK_ROW" | awk -F'\t' '{print $4}')"
TRUNK_USERNAME="$(echo "$TRUNK_ROW" | awk -F'\t' '{print $5}')"
if [ "$TRUNK_TYPE" = "PJSIP_EXTERNAL" ] \
    && [ "$TRUNK_TRUNKTYPE" = "T" ] \
    && [ "$TRUNK_CHANNEL" = "PJSIP/${EXTERNAL_ENDPOINT}" ] \
    && [ "$TRUNK_ID_REGEX" = "PJSIP/${EXTERNAL_ENDPOINT}" ] \
    && [ "$TRUNK_USERNAME" = "$EXTERNAL_ENDPOINT" ]; then
    harness_ok "persisted trunk row matches the pjsip_external contract" "type=PJSIP_EXTERNAL trunktype=T channel=id_regex=PJSIP/${EXTERNAL_ENDPOINT} username=${EXTERNAL_ENDPOINT}"
else
    harness_bad "persisted trunk row matches the pjsip_external contract" "type='$TRUNK_TYPE' trunktype='$TRUNK_TRUNKTYPE' channel='$TRUNK_CHANNEL' id_regex='$TRUNK_ID_REGEX' username='$TRUNK_USERNAME'"
fi

PEERS_ROW_COUNT="$(db_query "SELECT COUNT(*) FROM peers WHERE name='${CREATED_TRUNK_NAME}';")"
if [ "${PEERS_ROW_COUNT:-1}" = "0" ]; then
    harness_ok "no peers row generated for the external endpoint" "matches docs/tasks/0028b's contract -- SENMA generators stay invisible to this object"
else
    harness_bad "no peers row generated for the external endpoint" "expected 0 peers rows for name='${CREATED_TRUNK_NAME}', found ${PEERS_ROW_COUNT}"
fi

if [ "$_HARNESS_FAIL_COUNT" -gt 0 ]; then
    log "trunk provisioning verification failed -- aborting before placing a call"
    harness_complete
fi

# --- 7. items 2/3/4: direct, non-HTTP proof of the fixed dial string -------

log "==> checking PBX_Trunks::get() interface selection + dial string directly (scripts/pjsip-external-trunk-check.php)"
# stderr discarded on purpose here (php -- ... 2>/dev/null, not 2>&1) --
# PHP 8.4 emits several unrelated Zend Framework 1 deprecation notices
# on every bootstrap (pre-existing, out of this task's scope), which
# would otherwise corrupt this exact-string comparison.
DIALSTRING_OUT="$($COMPOSE exec -T app php -- dialstring "$CREATED_TRUNK_ID" "$CHECK_DESTINATION" < "$CHECK_SCRIPT" 2>/dev/null)"
EXPECTED_DIALSTRING_OUT="PBX_Asterisk_Interface_PJSIP PJSIP/${CHECK_DESTINATION}@${EXTERNAL_ENDPOINT}"
if [ "$DIALSTRING_OUT" = "$EXPECTED_DIALSTRING_OUT" ]; then
    harness_ok "outbound routing resolves to PBX_Asterisk_Interface_PJSIP with the correct dial string" "$DIALSTRING_OUT"
else
    harness_bad "outbound routing resolves to PBX_Asterisk_Interface_PJSIP with the correct dial string" "expected '$EXPECTED_DIALSTRING_OUT', got '$DIALSTRING_OUT'"
fi
if echo "$DIALSTRING_OUT" | grep -qF "PJSIP/${EXTERNAL_ENDPOINT}/${CHECK_DESTINATION}"; then
    harness_bad "no legacy/generic incorrect dial-string form" "found the broken 'PJSIP/<endpoint>/<destination>' form in: $DIALSTRING_OUT"
else
    harness_ok "no legacy/generic incorrect dial-string form" "'PJSIP/${EXTERNAL_ENDPOINT}/${CHECK_DESTINATION}' does not appear"
fi

# --- 8. item 6: inbound id_regex/getChannelOwner() still resolves this trunk

log "==> checking PBX_Interfaces::getChannelOwner() directly for a synthetic inbound channel on this trunk"
# No trailing "-<numeric suffix>" here: PBX_Asterisk_AGI_Request already
# strips that (strrpos()-based, TASK-0016) before ever calling
# getChannelOwner(), which itself does a plain anchored regex match
# against id_regex with no wildcard for that suffix -- this mirrors
# exactly what getChannelOwner() actually receives in production, not
# the raw Asterisk channel name.
SYNTHETIC_CHANNEL="PJSIP/${EXTERNAL_ENDPOINT}"
CHANNELOWNER_OUT="$($COMPOSE exec -T app php -- channelowner "$SYNTHETIC_CHANNEL" < "$CHECK_SCRIPT" 2>/dev/null)"
EXPECTED_CHANNELOWNER_OUT="Snep_Trunk id=${CREATED_TRUNK_ID} name=${TRUNK_CALLERID}"
if [ "$CHANNELOWNER_OUT" = "$EXPECTED_CHANNELOWNER_OUT" ]; then
    harness_ok "inbound id_regex/getChannelOwner() still resolves this trunk" "$CHANNELOWNER_OUT"
else
    harness_bad "inbound id_regex/getChannelOwner() still resolves this trunk" "expected '$EXPECTED_CHANNELOWNER_OUT', got '$CHANNELOWNER_OUT'"
fi

if [ "$_HARNESS_FAIL_COUNT" -gt 0 ]; then
    log "direct dial-string/channel-owner verification failed -- aborting before placing a real call"
    harness_complete
fi

# --- 9. item 5: real outbound call reaches a live PJSIP external endpoint --

log "==> provisioning caller extension ${CALLER_EXT} via the real ExtensionsController::addAction() HTTP flow"
if create_extension "$CALLER_EXT" "$CALLER_EXT_SECRET"; then
    CREATED_EXT=1
    harness_register_cleanup "extension ${CALLER_EXT} (pjsip-external-smoke fixture)" "delete_extension ${CALLER_EXT}"
    harness_ok "caller extension provisioned" "extension ${CALLER_EXT} created"
else
    harness_blocked "creating caller extension ${CALLER_EXT} via the real UI flow failed -- see log above"
fi

log "==> creating the outbound route fixture (destination ${TEST_DESTINATION} -> trunk ${CREATED_TRUNK_ID})"
ROUTE_OUT="$($COMPOSE exec -T app php -- create "$CREATED_TRUNK_ID" "$TEST_DESTINATION" "$ROUTE_DESC" < "$ROUTE_SCRIPT" 2>&1)"
CREATED_ROUTE_ID="$(echo "$ROUTE_OUT" | grep -oE '^[0-9]+$' | tail -1)"
if [ -n "$CREATED_ROUTE_ID" ]; then
    harness_register_cleanup "outbound route id=${CREATED_ROUTE_ID} (pjsip-external-smoke fixture)" "remove_route_fixture ${CREATED_ROUTE_ID} 'outbound route'"
    harness_ok "route fixture created" "rule id=${CREATED_ROUTE_ID} via PBX_Rules::register() (destino=RX:${TEST_DESTINATION} -> DiscarTronco tronco=${CREATED_TRUNK_ID})"
else
    harness_blocked "route fixture creation failed: $ROUTE_OUT"
fi

log "==> building baresip test image"
if ! harness_timeout 180 docker build -q -t "$BARESIP_IMAGE" -f "$BARESIP_DOCKERFILE" docker >&2; then
    harness_blocked "failed to build $BARESIP_IMAGE from $BARESIP_DOCKERFILE within 180s"
fi

CONF_DIR="$(mktemp -d)"
harness_register_best_effort_cleanup "baresip config temp dir" "rm -rf '$CONF_DIR'"

# External-endpoint-side UA: registers directly to the fixture endpoint
# installed in step 5, answermode=auto (it has no dialplan/scripted
# hangup of its own -- see the "channel request hangup all" step below).
mkdir -p "$CONF_DIR/external"
cp "$TEMPLATE_DIR/config.template" "$CONF_DIR/external/config"
sed \
    -e "s|__EXTEN__|${EXTERNAL_ENDPOINT}|g" \
    -e "s|__ASTERISK_HOST__|${ASTERISK_NAME}|g" \
    -e "s|__SECRET__|${EXTERNAL_ENDPOINT_SECRET}|g" \
    -e "s|__ANSWERMODE__|auto|g" \
    "$TEMPLATE_DIR/accounts.template" > "$CONF_DIR/external/accounts"

# Caller-side UA: the SENMA-provisioned extension that originates the
# call, ctrl_tcp-driven exactly like trunk-smoke-test.sh/call-smoke-test.sh.
mkdir -p "$CONF_DIR/caller"
cp "$TEMPLATE_DIR/config.template" "$CONF_DIR/caller/config"
sed \
    -e "s|__EXTEN__|${CALLER_EXT}|g" \
    -e "s|__ASTERISK_HOST__|${ASTERISK_NAME}|g" \
    -e "s|__SECRET__|${CALLER_EXT_SECRET}|g" \
    -e "s|__ANSWERMODE__|manual|g" \
    "$TEMPLATE_DIR/accounts.template" > "$CONF_DIR/caller/accounts"

log "==> starting baresip test endpoints (external endpoint + caller extension ${CALLER_EXT})"
docker rm -f "$EXTERNAL_BARESIP_CONTAINER" "$CALLER_BARESIP_CONTAINER" >/dev/null 2>&1
docker run -d --name "$EXTERNAL_BARESIP_CONTAINER" --network "$NETWORK_NAME" \
    -v "$CONF_DIR/external:/root/.baresip" "$BARESIP_IMAGE" baresip -f /root/.baresip >&2
harness_register_best_effort_cleanup "baresip container ${EXTERNAL_BARESIP_CONTAINER}" "docker rm -f '$EXTERNAL_BARESIP_CONTAINER' >/dev/null 2>&1"
docker run -d --name "$CALLER_BARESIP_CONTAINER" --network "$NETWORK_NAME" \
    -v "$CONF_DIR/caller:/root/.baresip" "$BARESIP_IMAGE" baresip -f /root/.baresip >&2
harness_register_best_effort_cleanup "baresip container ${CALLER_BARESIP_CONTAINER}" "docker rm -f '$CALLER_BARESIP_CONTAINER' >/dev/null 2>&1"

wait_registered() {
    local aor="$1" tries=15
    while [ "$tries" -gt 0 ]; do
        if $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${aor}" 2>&1 | grep -q "Contact:.*${aor}/sip:"; then
            return 0
        fi
        sleep 1
        tries=$((tries-1))
    done
    return 1
}
if wait_registered "$EXTERNAL_ENDPOINT"; then
    harness_ok "external endpoint ${EXTERNAL_ENDPOINT} registered" "contact bound within 15s"
else
    harness_bad "external endpoint ${EXTERNAL_ENDPOINT} registered" "no contact bound within 15s"
fi
if wait_registered "$CALLER_EXT"; then
    harness_ok "caller extension ${CALLER_EXT} registered" "contact bound within 15s"
else
    harness_bad "caller extension ${CALLER_EXT} registered" "no contact bound within 15s"
fi

if [ "$_HARNESS_FAIL_COUNT" -gt 0 ]; then
    log "registration failed -- aborting before placing a call"
    harness_complete
fi

log "==> placing outbound call: ${CALLER_EXT} -> ${TEST_DESTINATION} (through pjsip_external trunk id=${CREATED_TRUNK_ID}, endpoint=${EXTERNAL_ENDPOINT})"
LOG_MARK_BEFORE="$($COMPOSE exec -T asterisk sh -c 'wc -l < /var/log/asterisk/full' 2>/dev/null | tr -d '\r ')"
UNIQUEID_MARK="$(db_query "SELECT MAX(uniqueid) FROM cdr;")"
UNIQUEID_MARK="${UNIQUEID_MARK:-0}"

PAYLOAD="{\"command\":\"dial\",\"params\":\"${TEST_DESTINATION}\"}"
LEN=${#PAYLOAD}
EVENTS="$(harness_timeout 25 docker run --rm --network "$NETWORK_NAME" "$BARESIP_IMAGE" sh -c \
    "printf '%s:%s,' '$LEN' '$PAYLOAD' | timeout 15 nc ${CALLER_BARESIP_CONTAINER} 4444" 2>&1)"

if echo "$EVENTS" | grep -q '"response":true,"ok":true'; then
    harness_ok "call placed" "dial command accepted by caller extension ${CALLER_EXT}"
else
    harness_bad "call placed" "ctrl_tcp dial command was not accepted: $EVENTS"
fi

if echo "$EVENTS" | grep -q '"type":"CALL_ANSWERED"'; then
    harness_ok "external endpoint answered" "CALL_ANSWERED event observed (live PJSIP external endpoint ${EXTERNAL_ENDPOINT} reached and answered)"
else
    harness_bad "external endpoint answered" "no CALL_ANSWERED event observed: $EVENTS"
fi

if echo "$EVENTS" | grep -q '"type":"CALL_ESTABLISHED"'; then
    harness_ok "call established" "CALL_ESTABLISHED event observed"
else
    harness_bad "call established" "no CALL_ESTABLISHED event observed"
fi

# Neither UA has any scripted hangup of its own (unlike trunk-smoke-test.sh's
# provider simulator, which runs Wait()+Hangup() in its own dialplan) --
# same pattern call-smoke-test.sh uses for its two bare baresip UAs.
sleep 5
log "==> hangup"
$COMPOSE exec -T asterisk asterisk -rx "channel request hangup all" >&2
sleep 3
REMAINING="$($COMPOSE exec -T asterisk asterisk -rx 'core show channels' 2>&1)"
if echo "$REMAINING" | grep -q "^0 active channels"; then
    harness_ok "hangup succeeded" "0 active channels after hangup"
else
    harness_bad "hangup succeeded" "channels still active"
fi

# --- 10. Asterisk log trace: exact dial string, correct + not the broken one

log "==> checking AGI/rule engine trace for the exact dial string"
AGI_TRACE="$($COMPOSE exec -T asterisk sh -c "tail -n +$((LOG_MARK_BEFORE+1)) /var/log/asterisk/full" 2>/dev/null)"
if echo "$AGI_TRACE" | grep -q "Running the rule .*:${ROUTE_DESC}" \
    && echo "$AGI_TRACE" | grep -qF "Dialing to ${TEST_DESTINATION} through trunk ${TRUNK_CALLERID}(PJSIP/${TEST_DESTINATION}@${EXTERNAL_ENDPOINT})" \
    && echo "$AGI_TRACE" | grep -q "Launched AGI Script .*snep/snep.php" \
    && ! echo "$AGI_TRACE" | grep -qF "PJSIP/${EXTERNAL_ENDPOINT}/${TEST_DESTINATION}"; then
    harness_ok "AGI/rule/trunk-selection path was exercised with the correct dial string" "snep.php ran, matched the fixture rule, DiscarTronco selected trunk id=${CREATED_TRUNK_ID}, dialed PJSIP/${TEST_DESTINATION}@${EXTERNAL_ENDPOINT} (never PJSIP/${EXTERNAL_ENDPOINT}/${TEST_DESTINATION})"
else
    harness_bad "AGI/rule/trunk-selection path was exercised with the correct dial string" "expected AGI/rule/trunk trace (with the correct dial string, and without the broken form) not found in Asterisk's log for this call"
fi

# --- 11. CDR row exists and is correct --------------------------------------

log "==> checking CDR"
# Same duplicate-row/timezone-safe pattern as trunk-smoke-test.sh -- a
# trunk call produces two cdr rows sharing one uniqueid; ASC + the
# pre-call uniqueid mark picks the real, fully-populated one.
CDR_ROW="$(db_query "SELECT uniqueid,disposition,duration,billsec,channel,dstchannel,calldate FROM cdr WHERE src='${CALLER_EXT}' AND dst='${TEST_DESTINATION}' AND uniqueid > '${UNIQUEID_MARK}' ORDER BY calldate ASC, uniqueid ASC LIMIT 1;")"
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
    && [[ "$CDR_CHANNEL" == PJSIP/${CALLER_EXT}-* ]] \
    && [[ "$CDR_DSTCHANNEL" == PJSIP/${EXTERNAL_ENDPOINT}-* ]] \
    && [[ "$CDR_CALLDATE" != "0000-00-00"* ]]; then
    harness_ok "CDR row exists and is correct" "uniqueid=$CDR_UNIQUEID disposition=ANSWERED duration=$CDR_DURATION billsec=$CDR_BILLSEC channel=$CDR_CHANNEL dstchannel=$CDR_DSTCHANNEL calldate=$CDR_CALLDATE"
else
    harness_bad "CDR row exists and is correct" "no matching/valid CDR row found (uniqueid='$CDR_UNIQUEID' disposition='$CDR_DISPOSITION' duration='$CDR_DURATION' billsec='$CDR_BILLSEC' channel='$CDR_CHANNEL' dstchannel='$CDR_DSTCHANNEL' calldate='$CDR_CALLDATE')"
fi

# --- Cleanup happens via harness_complete's cleanup pass (best-effort
#     baresip containers/tempdir, then HTTP delete of the outbound route,
#     extension, and trunk fixtures in dependency-safe LIFO order, and
#     finally pjsip.conf restored to its original, non-fixture content)
# -----------------------------------------------------------------------

harness_complete
