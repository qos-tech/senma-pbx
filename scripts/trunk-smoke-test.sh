#!/bin/bash
#
# SENMA-provisioned outbound PJSIP trunk call smoke test (TASK-0015).
#
# Proves, end to end, against a running `make dev` Docker environment,
# using SENMA's own application flow (not direct SQL, not hand-written
# PJSIP config, not permanent seed data), the same "register-based
# outbound trunk" model TASK-0014 recommended:
#
#   HTTP POST to TrunksController::addAction() (technology=pjsip,
#   dialmethod=normal, reverse_auth=1)
#   -> trunks + peers rows persisted
#   -> Snep_PjsipTrunkConf::loadConfFromDb() generates
#      endpoint/auth/aor/registration -> module reload res_pjsip.so
#   -> outbound REGISTER succeeds against the local "provider" simulator
#      (a second, independent Asterisk 22/PJSIP instance -- see
#      compose.yaml's "provider" service and docker/provider-config/,
#      never a real commercial carrier)
#   -> a route/rule (created via PBX_Rules' own domain API -- see
#      scripts/trunk-smoke-route.php) sends a fixed test destination
#      through DiscarTronco -> this trunk
#   -> existing extensions.conf -> existing SENMA AGI (snep/snep.php) ->
#      existing PBX_Rules/PBX_Dialplan rule engine -> DiscarTronco ->
#      PBX_Asterisk_Interface_PJSIP -> Dial(PJSIP/600@trunk-<id>) ->
#      provider simulator receives the INVITE, answers, holds briefly,
#      hangs up
#   -> real cdr_adaptive_odbc CDR row -> existing SENMA report endpoint
#      reads it back
#   -> HTTP POST to TrunksController::removeAction() cleans up.
#
# TASK-0016 extends the same fixture (same trunk, same provider
# container, same registered test extension) with the reverse direction:
#
#   provider originates a real INVITE (PJSIP/58888@to-senma, a static
#   endpoint added to docker/provider-config/pjsip.conf) toward SENMA
#   -> Snep_PjsipTrunkConf's generated `identify` object (match=<trunk's
#      configured host>) resolves it to this same trunk's endpoint
#   -> PBX_Asterisk_AGI_Request correctly identifies the trunk (the
#      strrpos()/id_regex fixes -- see
#      docs/tasks/0016-pjsip-inbound-trunk-routing.md §2)
#   -> [default] -> existing AGI (snep/snep.php) -> existing
#      PBX_Rules/PBX_Dialplan engine -> a second route/rule (src=T:<id>,
#      dst=RX:58888) -> DiscarRamal -> the same registered test extension
#      rings and (answermode=auto) answers -> held briefly -> clean
#      hangup -> a second real CDR row -> report readback.
#
# Both directions share one trunk/extension provisioning pass and one
# finalization cleanup pass -- provisioning the same fixture twice would
# be pure waste, and nothing about either direction's checks touches the
# other's state (see docs/tasks/0016-pjsip-inbound-trunk-routing.md §15
# for why this stays one command instead of two).
#
# Separate from scripts/smoke-test.sh (HTTP-only) and
# scripts/call-smoke-test.sh (PJSIP extensions only) by design -- this is
# trunk-specific SIP/telephony-level proof, a different failure domain.
#
# TASK-0027: rebuilt on scripts/lib/harness.sh. Fixes two real defects
# found during TASK-0027's own investigation (see
# docs/tasks/0027-regression-harness-reliability.md §5/§6):
#
# 1. Dependency graph: an outbound route references the trunk; the
#    inbound route references BOTH the trunk (src=T:<id>) and the
#    extension (DiscarRamal's ramal=<extension>) -- confirmed by reading
#    TrunksController::removeAction()/ExtensionsController::removeAction(),
#    both of which block deletion while a route still references the
#    object. The OLD preflight checked for a stale trunk FIRST and
#    called stop() immediately, never reaching the route-fixture recovery
#    code further down -- so a trunk left behind by one interrupted run
#    permanently BLOCKED every later run. Stale-fixture recovery below is
#    now dependency-ordered: routes are discovered and removed via the
#    supported PBX_Rules::delete() path BEFORE the trunk/extension they
#    reference are ever touched -- exactly mirroring the cleanup-time
#    order this script already used correctly.
# 2. delete_trunk() previously hardcoded the trunk's `name` field to the
#    literal "1" (TrunksController::removeAction() deletes the `peers`
#    row using whatever `name` the POST sends, not a DB lookup by id).
#    Any run where the auto-generated trunk name wasn't literally "1"
#    silently left the `peers` row behind after "successful" cleanup.
#    Fixed to look up the real persisted name from the `trunks` table,
#    matching the pattern transport-smoke-test.sh's delete_trunk_fixture()
#    already used correctly.
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
ROUTE_SCRIPT="scripts/trunk-smoke-route.php"
FIXTURE_MARKER="task0015-trunk-smoke"
TEST_USER="admin"
TEST_PASSWORD="SmokeTest123!"
TEST_EXT=1099
TEST_EXT_SECRET="${FIXTURE_MARKER}-ext"
TRUNK_CALLERID="TASK-0015 trunk-smoke fixture"
ROUTE_DESC="TASK-0015 trunk-smoke route fixture"
TEST_DESTINATION=600
BARESIP_CONTAINER="senma-trunksmoke-${TEST_EXT}"

# TASK-0016 inbound fixtures. 58888 is the reserved inbound test DID
# established by investigation (docs/tasks/0016-pjsip-inbound-trunk-routing.md
# §3/§8): 600 is already the outbound destination, and any 3-digit
# number starting with 7 or 9 collides with pre-existing dialplan
# features (snep-features.conf's _7XX call-parking pattern, [default]'s
# own _9XX conference pattern) before a call would ever reach the AGI at
# all -- confirmed live, not assumed.
TEST_DESTINATION_INBOUND=58888
INBOUND_ROUTE_DESC="TASK-0016 trunk-smoke inbound route fixture"
PROVIDER_TO_SENMA_ENDPOINT="to-senma"

CREATED_EXT=0
CREATED_TRUNK_ID=""
CREATED_TRUNK_NAME=""
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

# create_extension <ext> <secret> -- same real HTTP flow as
# call-smoke-test.sh, just an independent fixture for this script.
create_extension() {
    local ext="$1" secret="$2" body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "name=SENMA trunk-smoke ${ext}" \
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

# create_trunk -- POSTs to the real TrunksController::addAction(),
# technology=pjsip, dialmethod=normal, reverse_auth=1 -- exactly what the
# real browser form submits (snep/modules/default/views/scripts/trunks/
# addedit.phtml + TrunksController::preparePost()/execAdd() equivalent).
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
    log "create_trunk failed (HTTP $httpcode): $(grep -o 'Server Message[^<]*' "$body" || head -c 300 "$body")"
    rm -f "$body"
    return 1
}

# delete_trunk <id> <name> -- <name> MUST be the trunk's real persisted
# `name` column (TrunksController::removeAction() uses it verbatim to
# delete the matching `peers` row, not a DB lookup by id -- see the
# TASK-0027 header comment above).
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
# never raw SQL. Used both for normal cleanup and stale-fixture recovery.
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

# --- 1. Required containers healthy ---------------------------------------

log "==> checking required containers"
harness_require_containers app asterisk db provider

harness_require_env DB_USER DB_PASSWORD DB_NAME TRUNK_TEST_USERNAME TRUNK_TEST_SECRET

ASTERISK_CID="$($COMPOSE ps -q asterisk)"
ASTERISK_NAME="$(docker inspect "$ASTERISK_CID" --format '{{.Name}}' | sed 's#^/##')"
NETWORK_NAME="$(docker inspect "$ASTERISK_CID" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')"
if [ -z "$ASTERISK_NAME" ] || [ -z "$NETWORK_NAME" ]; then
    harness_blocked "could not resolve the asterisk container's name/network via docker inspect"
fi
log "asterisk container: $ASTERISK_NAME  network: $NETWORK_NAME"

# --- 2. PJSIP modules Running on both asterisk and provider ---------------

log "==> checking PJSIP module state (asterisk + provider)"
# TASK-0027 finding: see transport-smoke-test.sh's identical comment --
# a fresh `docker compose exec` can transiently see incomplete module
# state immediately after a DIFFERENT suite's own PJSIP reload.
pjsip_modules_running_on() {
    local svc="$1"
    $COMPOSE exec -T "$svc" asterisk -rx 'module show like res_pjsip.so' 2>&1 | grep -q "Running" \
        && $COMPOSE exec -T "$svc" asterisk -rx 'module show like chan_pjsip.so' 2>&1 | grep -q "Running"
}
MODS_OK=1
for svc in asterisk provider; do
    if ! harness_retry 5 2 -- pjsip_modules_running_on "$svc"; then
        MODS_OK=0
    fi
done
if [ "$MODS_OK" = "1" ]; then
    harness_ok "PJSIP modules Running" "res_pjsip.so and chan_pjsip.so Running on both asterisk and provider"
else
    harness_blocked "res_pjsip.so/chan_pjsip.so not both Running on both instances"
fi

# --- 3. Log in --------------------------------------------------------------

COOKIEJAR="$(mktemp)"
harness_register_best_effort_cleanup "cookie jar temp file" "rm -f '$COOKIEJAR'"
log "==> logging in as ${TEST_USER}"
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${TEST_PASSWORD}');" 2>/dev/null | tr -d '\r')"
if [ -z "$TEST_HASH" ]; then
    harness_blocked "could not compute the ${TEST_USER} password hash via the app container"
fi
db_query "UPDATE users SET password = '${TEST_HASH}' WHERE name = '${TEST_USER}';" >&2
http_login
# TASK-0026G: create_extension()/delete_extension()/create_trunk()/
# delete_trunk() below now need a valid snep_csrf_token (Snep_CsrfPlugin)
# on every POST -- fetched once, reused for the rest of this script's run
# (stable per-session value, not one-shot/rotating). The route helpers
# (remove_route_fixture and the create/create-inbound calls further down)
# run entirely inside the app container via a direct PHP script, never
# over HTTP, so they need no token.
ADMIN_CSRF="$(harness_csrf_token "$COOKIEJAR" "$BASE_URL")"
if [ -z "$ADMIN_CSRF" ]; then harness_blocked "could not read the admin session's CSRF token"; fi

# --- 4. Dependency-ordered stale-fixture recovery ---------------------------
#
# Routes are discovered and removed FIRST, via the supported
# PBX_Rules::delete() path, because both the outbound and inbound route
# fixtures reference the trunk (and the inbound route also references the
# extension) -- TrunksController::removeAction()/
# ExtensionsController::removeAction() both refuse to delete an object
# still referenced by a route. Only once no route fixture remains do we
# attempt to recover a stale trunk/extension.

log "==> checking for a leftover outbound route fixture from a prior interrupted run"
LEFTOVER_ROUTE_ID="$(db_query "SELECT id FROM regras_negocio WHERE \`desc\`='${ROUTE_DESC}';")"
if [ -n "$LEFTOVER_ROUTE_ID" ]; then
    remove_route_fixture "$LEFTOVER_ROUTE_ID" "outbound route" \
        || harness_blocked "found a leftover outbound route fixture (id=${LEFTOVER_ROUTE_ID}) from a prior interrupted run but could not remove it via the supported PBX_Rules::delete() path -- refusing to proceed with a raw SQL fallback"
fi

log "==> checking for a leftover inbound route fixture from a prior interrupted run"
LEFTOVER_INBOUND_ROUTE_ID="$(db_query "SELECT id FROM regras_negocio WHERE \`desc\`='${INBOUND_ROUTE_DESC}';")"
if [ -n "$LEFTOVER_INBOUND_ROUTE_ID" ]; then
    remove_route_fixture "$LEFTOVER_INBOUND_ROUTE_ID" "inbound route" \
        || harness_blocked "found a leftover inbound route fixture (id=${LEFTOVER_INBOUND_ROUTE_ID}) from a prior interrupted run but could not remove it via the supported PBX_Rules::delete() path -- refusing to proceed with a raw SQL fallback"
fi

log "==> checking for a leftover trunk fixture from a prior interrupted run (any referencing routes were cleared above)"
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
        harness_blocked "found a leftover trunk fixture (id=${EXISTING_TRUNK_ID}, name=${EXISTING_TRUNK_NAME}) from a prior interrupted run but the supported delete path did not return 302 even after clearing all known dependent route fixtures -- refusing to proceed with a raw SQL fallback; investigate/remove it manually (possible undiscovered dependency or product defect -- document separately, do not fix here)"
    fi
fi

log "==> checking for a leftover extension fixture from a prior interrupted run"
EXISTING_EXT_CANAL="$(db_query "SELECT canal FROM peers WHERE name='${TEST_EXT}';")"
EXISTING_EXT_SECRET="$(db_query "SELECT secret FROM peers WHERE name='${TEST_EXT}';")"
if [ -n "$EXISTING_EXT_CANAL" ]; then
    if [ "$EXISTING_EXT_CANAL" = "PJSIP/${TEST_EXT}" ] && [[ "$EXISTING_EXT_SECRET" == "${FIXTURE_MARKER}"* ]]; then
        log "extension ${TEST_EXT} is a leftover trunk-smoke fixture from a prior run -- removing via HTTP before re-creating"
        delete_extension "$TEST_EXT" || harness_blocked "found a leftover trunk-smoke fixture for extension ${TEST_EXT} but the HTTP delete flow did not return 302 -- refusing to proceed with a raw SQL fallback"
    else
        harness_blocked "peers row for extension '${TEST_EXT}' already exists (canal='${EXISTING_EXT_CANAL}') and is NOT a trunk-smoke fixture. Refusing to overwrite real/unknown data."
    fi
fi

# --- 5. Provision trunk and extension via the real UI -----------------------

log "==> provisioning trunk and extension ${TEST_EXT} via the real UI"
if create_trunk; then
    CREATED_TRUNK_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${TRUNK_CALLERID}';")"
    if [ -z "$CREATED_TRUNK_ID" ]; then
        harness_blocked "trunk creation returned 302 but no matching trunks row was found afterward"
    fi
    CREATED_TRUNK_NAME="$(db_query "SELECT name FROM trunks WHERE id=${CREATED_TRUNK_ID};")"
    if [ -z "$CREATED_TRUNK_NAME" ]; then
        harness_blocked "trunk id=${CREATED_TRUNK_ID} was created but its persisted name could not be looked up -- cannot register a correct cleanup path"
    fi
    harness_register_cleanup "trunk id=${CREATED_TRUNK_ID} name=${CREATED_TRUNK_NAME} (trunk-smoke fixture)" "delete_trunk ${CREATED_TRUNK_ID} '${CREATED_TRUNK_NAME}'"
    log "provisioned trunk id=${CREATED_TRUNK_ID} name=${CREATED_TRUNK_NAME} via the real TrunksController::addAction() HTTP flow"
else
    harness_blocked "creating the test trunk via the real UI flow failed -- see log above"
fi

if create_extension "$TEST_EXT" "$TEST_EXT_SECRET"; then
    CREATED_EXT=1
    harness_register_cleanup "extension ${TEST_EXT} (trunk-smoke fixture)" "delete_extension ${TEST_EXT}"
    log "provisioned extension ${TEST_EXT} via the real ExtensionsController::addAction() HTTP flow"
else
    harness_blocked "creating extension ${TEST_EXT} via the real UI flow failed -- see log above"
fi
harness_ok "test fixtures available" "trunk id=${CREATED_TRUNK_ID} and extension ${TEST_EXT} provisioned through SENMA's real HTTP flows (not SQL, not hand-written config)"

TRUNK_OBJ="trunk-${CREATED_TRUNK_ID}"

# --- 6. Generated config + Asterisk runtime reflect the new trunk --------

log "==> checking generated PJSIP trunk config and Asterisk runtime state"
GENERATED_CONF="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip-trunks.conf 2>/dev/null)"
if echo "$GENERATED_CONF" | grep -q "^\[${TRUNK_OBJ}\]" \
    && echo "$GENERATED_CONF" | grep -q "^\[${TRUNK_OBJ}-auth\]" \
    && echo "$GENERATED_CONF" | grep -q "^\[${TRUNK_OBJ}-registration\]"; then
    harness_ok "generated endpoint/auth/aor/registration sections exist" "senma-pjsip-trunks.conf contains [${TRUNK_OBJ}], [${TRUNK_OBJ}-auth], [${TRUNK_OBJ}-registration]"
else
    harness_bad "generated endpoint/auth/aor/registration sections exist" "expected sections not found in senma-pjsip-trunks.conf"
fi

# TASK-0028Y (confirmed gap #1, PJSIP Completeness Architecture Review
# TASK-0028W): this fixture already posts qualify=yes -- previously
# Snep_PjsipTrunkConf::renderTrunk() never consumed peers.qualify at
# all, so no qualify_frequency= line was ever emitted here regardless.
# The "specify" (custom-ms) case is covered separately by
# pjsip-lifecycle-smoke-test.sh; this is the plain "yes" case, on the
# same fixture the rest of this suite already exercises end to end.
if echo "$GENERATED_CONF" | grep -q "^qualify_frequency=60$"; then
    harness_ok "generated qualify_frequency (trunk, qualify=yes)" "aor stanza has qualify_frequency=60 (TASK-0028Y gap #1)"
else
    harness_bad "generated qualify_frequency (trunk, qualify=yes)" "expected qualify_frequency=60 not found in senma-pjsip-trunks.conf"
fi

# TASK-0027 finding: see call-smoke-test.sh's identical comment -- a
# PJSIP reload is not atomic from a freshly-spawned `docker compose
# exec`'s perspective; bounded retry, not a weakened assertion.
trunk_endpoint_visible() { $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${TRUNK_OBJ}" 2>&1 | grep -q "Endpoint:  ${TRUNK_OBJ}"; }
if harness_retry 5 1 -- trunk_endpoint_visible; then
    harness_ok "pjsip show endpoint ${TRUNK_OBJ}" "endpoint exists in the live Asterisk PJSIP config (reload succeeded)"
else
    harness_bad "pjsip show endpoint ${TRUNK_OBJ}" "endpoint not found after 5 attempts over ~4s -- reload may have failed"
fi

if $COMPOSE exec -T asterisk asterisk -rx "pjsip show aor ${TRUNK_OBJ}" 2>&1 | grep -qE 'qualify_frequency[[:space:]]*:[[:space:]]*60$'; then
    harness_ok "live qualify_frequency (trunk, qualify=yes)" "pjsip show aor ${TRUNK_OBJ}: qualify_frequency=60"
else
    harness_bad "live qualify_frequency (trunk, qualify=yes)" "expected qualify_frequency=60 not found in live aor detail"
fi

if [ "$_HARNESS_FAIL_COUNT" -gt 0 ]; then
    log "provisioning/reload verification failed -- aborting before registration"
    harness_complete
fi

# --- 7. Outbound registration state (this trunk model's status check) ----

log "==> checking outbound registration state"
wait_registered_outbound() {
    local tries=15
    while [ "$tries" -gt 0 ]; do
        if $COMPOSE exec -T asterisk asterisk -rx "pjsip show registrations outbound" 2>&1 \
            | grep "${TRUNK_OBJ}-registration" | grep -q "Registered"; then
            return 0
        fi
        sleep 1
        tries=$((tries-1))
    done
    return 1
}
if wait_registered_outbound; then
    harness_ok "outbound registration Registered" "${TRUNK_OBJ}-registration reached Registered within 15s (real REGISTER against the provider simulator)"
else
    harness_bad "outbound registration Registered" "${TRUNK_OBJ}-registration did not reach Registered within 15s"
    harness_complete
fi

# --- 8. Outbound route fixture, through PBX_Rules' own domain API -----------

log "==> creating the outbound route fixture (destination ${TEST_DESTINATION} -> trunk ${CREATED_TRUNK_ID})"
ROUTE_OUT="$($COMPOSE exec -T app php -- create "$CREATED_TRUNK_ID" "$TEST_DESTINATION" "$ROUTE_DESC" < "$ROUTE_SCRIPT" 2>&1)"
CREATED_ROUTE_ID="$(echo "$ROUTE_OUT" | grep -oE '^[0-9]+$' | tail -1)"
if [ -n "$CREATED_ROUTE_ID" ]; then
    harness_register_cleanup "outbound route id=${CREATED_ROUTE_ID} (trunk-smoke fixture)" "remove_route_fixture ${CREATED_ROUTE_ID} 'outbound route'"
    harness_ok "route fixture created" "rule id=${CREATED_ROUTE_ID} via PBX_Rules::register() (destino=RX:${TEST_DESTINATION} -> DiscarTronco tronco=${CREATED_TRUNK_ID})"
else
    harness_blocked "route fixture creation failed: $ROUTE_OUT"
fi

# --- 9/10. Build baresip test image, start the calling extension ----------

log "==> building baresip test image"
if ! harness_timeout 180 docker build -q -t "$BARESIP_IMAGE" -f "$BARESIP_DOCKERFILE" docker >&2; then
    harness_blocked "failed to build $BARESIP_IMAGE from $BARESIP_DOCKERFILE within 180s"
fi

CONF_DIR="$(mktemp -d)"
harness_register_best_effort_cleanup "baresip config temp dir" "rm -rf '$CONF_DIR'"
mkdir -p "$CONF_DIR/${TEST_EXT}"
cp "$TEMPLATE_DIR/config.template" "$CONF_DIR/${TEST_EXT}/config"
sed \
    -e "s|__EXTEN__|${TEST_EXT}|g" \
    -e "s|__ASTERISK_HOST__|${ASTERISK_NAME}|g" \
    -e "s|__SECRET__|${TEST_EXT_SECRET}|g" \
    -e "s|__ANSWERMODE__|auto|g" \
    "$TEMPLATE_DIR/accounts.template" > "$CONF_DIR/${TEST_EXT}/accounts"
# TASK-0016: was "manual". answermode only governs how this endpoint
# handles an INCOMING INVITE -- placing the outbound call below is
# always an explicit ctrl_tcp "dial" command regardless, so this has no
# effect on the existing outbound checks (confirmed: they stay green
# unchanged). "auto" lets this same already-registered endpoint also
# auto-answer the new inbound-phase call below with zero extra
# ctrl_tcp/config plumbing -- one registered test extension proves both
# directions, matching call-smoke-test.sh's own destination-extension
# precedent (answermode=auto there too).

log "==> starting baresip test endpoint (extension ${TEST_EXT})"
docker rm -f "$BARESIP_CONTAINER" >/dev/null 2>&1
docker run -d --name "$BARESIP_CONTAINER" --network "$NETWORK_NAME" \
    -v "$CONF_DIR/${TEST_EXT}:/root/.baresip" "$BARESIP_IMAGE" baresip -f /root/.baresip >&2
harness_register_best_effort_cleanup "baresip container ${BARESIP_CONTAINER}" "docker rm -f '$BARESIP_CONTAINER' >/dev/null 2>&1"

wait_registered() {
    local ext="$1" tries=15
    while [ "$tries" -gt 0 ]; do
        if $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${ext}" 2>&1 | grep -q "Contact:.*${ext}/sip:"; then
            return 0
        fi
        sleep 1
        tries=$((tries-1))
    done
    return 1
}
if wait_registered "$TEST_EXT"; then
    harness_ok "test endpoint ${TEST_EXT} registered" "contact bound within 15s"
else
    harness_bad "test endpoint ${TEST_EXT} registered" "no contact bound within 15s"
    harness_complete
fi

# --- 11-14. Place the outbound call, verify it reaches the provider --------

log "==> placing outbound call: ${TEST_EXT} -> ${TEST_DESTINATION} (through trunk id=${CREATED_TRUNK_ID})"
LOG_MARK_BEFORE="$($COMPOSE exec -T asterisk sh -c 'wc -l < /var/log/asterisk/full' 2>/dev/null | tr -d '\r ')"
# TASK-0015: src/dst alone (1099/600) are reused identically across runs,
# so an unscoped CDR lookup would match a PRIOR run's row instead of this
# one -- a real bug caught while proving idempotency (running trunk-smoke
# twice in a row). A wall-clock cutoff (docker exec's `date`, or even
# MariaDB's own NOW()) turned out unusable here: both read several hours
# behind the timestamps Asterisk itself writes into calldate in this
# environment (a container/DB timezone-handling difference unrelated to
# this task, not worth chasing further for a test-fixture marker).
# uniqueid (Asterisk's own <epoch>.<sequence> channel identifier) needs
# no timezone at all and is monotonically increasing call over call --
# capturing the highest one that exists before this call and requiring
# the result to be strictly greater sidesteps the clock-skew question
# entirely. cdr has no other auto-increment key to mark a "since" point
# with instead.
UNIQUEID_MARK="$(db_query "SELECT MAX(uniqueid) FROM cdr;")"
UNIQUEID_MARK="${UNIQUEID_MARK:-0}"

PAYLOAD="{\"command\":\"dial\",\"params\":\"${TEST_DESTINATION}\"}"
LEN=${#PAYLOAD}
EVENTS="$(harness_timeout 25 docker run --rm --network "$NETWORK_NAME" "$BARESIP_IMAGE" sh -c \
    "printf '%s:%s,' '$LEN' '$PAYLOAD' | timeout 15 nc ${BARESIP_CONTAINER} 4444" 2>&1)"

if echo "$EVENTS" | grep -q '"response":true,"ok":true'; then
    harness_ok "call placed" "dial command accepted by endpoint ${TEST_EXT}"
else
    harness_bad "call placed" "ctrl_tcp dial command was not accepted: $EVENTS"
fi

if echo "$EVENTS" | grep -q '"type":"CALL_ANSWERED"'; then
    harness_ok "provider answered" "CALL_ANSWERED event observed"
else
    harness_bad "provider answered" "no CALL_ANSWERED event observed: $EVENTS"
fi

if echo "$EVENTS" | grep -q '"type":"CALL_ESTABLISHED"'; then
    harness_ok "call established" "CALL_ESTABLISHED event observed"
else
    harness_bad "call established" "no CALL_ESTABLISHED event observed"
fi

sleep 2

REMAINING="$($COMPOSE exec -T asterisk asterisk -rx 'core show channels' 2>&1)"
if echo "$REMAINING" | grep -q "^0 active channels"; then
    harness_ok "hangup succeeded" "0 active channels after the provider's own Hangup()"
else
    harness_bad "hangup succeeded" "channels still active"
fi

# --- 15. SENMA AGI/rule engine + trunk selection were actually exercised --

log "==> checking AGI/rule engine trace"
AGI_TRACE="$($COMPOSE exec -T asterisk sh -c "tail -n +$((LOG_MARK_BEFORE+1)) /var/log/asterisk/full" 2>/dev/null)"
if echo "$AGI_TRACE" | grep -q "Running the rule .*:${ROUTE_DESC}" \
    && echo "$AGI_TRACE" | grep -q "Dialing to ${TEST_DESTINATION} through trunk ${TRUNK_CALLERID}(PJSIP/${TEST_DESTINATION}@${TRUNK_OBJ})" \
    && echo "$AGI_TRACE" | grep -q "Launched AGI Script .*snep/snep.php"; then
    harness_ok "AGI/rule/trunk-selection path was exercised" "snep.php ran, matched the fixture rule, DiscarTronco selected trunk id=${CREATED_TRUNK_ID}, dialed PJSIP/${TEST_DESTINATION}@${TRUNK_OBJ} (not a bypassed test-only Dial)"
else
    harness_bad "AGI/rule/trunk-selection path was exercised" "expected AGI/rule/trunk trace not found in Asterisk's log for this call"
fi

# --- 16. CDR row exists and is correct -------------------------------------

log "==> checking CDR"
# TASK-0015 finding: a trunk call (unlike a plain extension-to-extension
# one) produces TWO cdr rows sharing one uniqueid -- the first, written
# alongside the Dial() itself (lastapp='Dial', fully populated), and a
# second, empty one written moments later when the calling channel's own
# dialplan reaches its explicit post-rule Hangup() (lastapp='Hangup',
# duration/billsec/dstchannel all blank). ORDER BY calldate DESC (the
# pattern call-smoke-test.sh uses, safe there because that duplicate never
# occurs for an internal ramal-to-ramal call) would silently pick the
# empty one here -- ASC picks the real, meaningful row. See
# docs/tasks/0015-pjsip-trunk-provisioning.md.
CDR_ROW="$(db_query "SELECT uniqueid,disposition,duration,billsec,channel,dstchannel,calldate FROM cdr WHERE src='${TEST_EXT}' AND dst='${TEST_DESTINATION}' AND uniqueid > '${UNIQUEID_MARK}' ORDER BY calldate ASC, uniqueid ASC LIMIT 1;")"
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
    && [[ "$CDR_CHANNEL" == PJSIP/${TEST_EXT}-* ]] \
    && [[ "$CDR_DSTCHANNEL" == PJSIP/${TRUNK_OBJ}-* ]] \
    && [[ "$CDR_CALLDATE" != "0000-00-00"* ]]; then
    harness_ok "CDR row exists and is correct" "uniqueid=$CDR_UNIQUEID disposition=ANSWERED duration=$CDR_DURATION billsec=$CDR_BILLSEC channel=$CDR_CHANNEL dstchannel=$CDR_DSTCHANNEL calldate=$CDR_CALLDATE"
else
    harness_bad "CDR row exists and is correct" "no matching/valid CDR row found (uniqueid='$CDR_UNIQUEID' disposition='$CDR_DISPOSITION' duration='$CDR_DURATION' billsec='$CDR_BILLSEC' channel='$CDR_CHANNEL' dstchannel='$CDR_DSTCHANNEL' calldate='$CDR_CALLDATE')"
fi

# --- 17. SENMA reporting path can read it -----------------------------------

log "==> checking SENMA report readback"
if [ -n "$CDR_UNIQUEID" ] && harness_cdr_report_window "$CDR_CALLDATE" 5; then
    # TASK-0027A: window anchored on this call's own already-confirmed
    # CDR_CALLDATE (see harness_cdr_report_window in lib/harness.sh),
    # not on "today" -- see call-smoke-test.sh's equivalent check for the
    # full rationale.
    REPORT_JSON="$(curl -sS -u "${TEST_USER}:${TEST_PASSWORD}" \
        "${BASE_URL}/modules/default/api/index.php?service=CallsReport&start_date=${HARNESS_REPORT_START_DATE}&start_hour=${HARNESS_REPORT_START_HOUR}&end_date=${HARNESS_REPORT_END_DATE}&end_hour=${HARNESS_REPORT_END_HOUR}&report_type=analytic&status_answered=1&src=${TEST_EXT}&order_src=equal" 2>&1)"
    if echo "$REPORT_JSON" | grep -qF "\"uniqueid\":\"${CDR_UNIQUEID}\""; then
        harness_ok "SENMA reporting path can read it" "CallsReport API endpoint returned this exact CDR (uniqueid=$CDR_UNIQUEID)"
    else
        harness_bad "SENMA reporting path can read it" "CallsReport API did not return uniqueid=$CDR_UNIQUEID: $REPORT_JSON"
    fi
else
    harness_bad "SENMA reporting path can read it" "skipped -- no CDR uniqueid available, or the report window could not be computed"
fi

# =============================================================================
# TASK-0016 -- inbound direction (provider -> SENMA -> SENMA extension)
# =============================================================================
#
# Reuses the exact trunk/extension fixture provisioned above -- no second
# trunk, no second provider, no second extension (docs/tasks/
# 0016-pjsip-inbound-trunk-routing.md §15).

# --- 18. Generated `identify` section exists --------------------------------

log "==> checking generated identify section"
# $GENERATED_CONF was captured in step 6 above and nothing has edited or
# reloaded the trunk since -- still an accurate snapshot, no need to
# re-fetch.
if echo "$GENERATED_CONF" | grep -q "^\[${TRUNK_OBJ}-identify\]"; then
    harness_ok "generated identify section exists" "senma-pjsip-trunks.conf contains [${TRUNK_OBJ}-identify]"
else
    harness_bad "generated identify section exists" "expected [${TRUNK_OBJ}-identify] section not found in senma-pjsip-trunks.conf"
fi

# --- 19. Provider's static to-senma endpoint is present ---------------------

log "==> checking provider's to-senma endpoint (docker/provider-config/pjsip.conf)"
if $COMPOSE exec -T provider asterisk -rx "pjsip show endpoint ${PROVIDER_TO_SENMA_ENDPOINT}" 2>&1 | grep -q "Endpoint:  ${PROVIDER_TO_SENMA_ENDPOINT}"; then
    harness_ok "provider to-senma endpoint present" "static endpoint used to originate the inbound test call is loaded"
else
    harness_blocked "provider's static to-senma endpoint not found -- check docker/provider-config/pjsip.conf (test fixture precondition, not application behavior)"
fi

# --- 20. Inbound route fixture, through the same PBX_Rules domain API ------

log "==> creating the inbound route fixture (trunk ${CREATED_TRUNK_ID} -> DID ${TEST_DESTINATION_INBOUND} -> extension ${TEST_EXT})"
INBOUND_ROUTE_OUT="$($COMPOSE exec -T app php -- create-inbound "$CREATED_TRUNK_ID" "$TEST_DESTINATION_INBOUND" "$TEST_EXT" "$INBOUND_ROUTE_DESC" < "$ROUTE_SCRIPT" 2>&1)"
CREATED_INBOUND_ROUTE_ID="$(echo "$INBOUND_ROUTE_OUT" | grep -oE '^[0-9]+$' | tail -1)"
if [ -n "$CREATED_INBOUND_ROUTE_ID" ]; then
    harness_register_cleanup "inbound route id=${CREATED_INBOUND_ROUTE_ID} (trunk-smoke fixture)" "remove_route_fixture ${CREATED_INBOUND_ROUTE_ID} 'inbound route'"
    harness_ok "inbound route fixture created" "rule id=${CREATED_INBOUND_ROUTE_ID} via PBX_Rules::register() (src=T:${CREATED_TRUNK_ID} -> dst=RX:${TEST_DESTINATION_INBOUND} -> DiscarRamal ramal=${TEST_EXT})"
else
    harness_blocked "inbound route fixture creation failed: $INBOUND_ROUTE_OUT"
fi

# --- 21-23. Provider originates the inbound call, verify it rings/answers/hangs up

log "==> placing inbound call: provider -> ${TEST_DESTINATION_INBOUND} (through trunk id=${CREATED_TRUNK_ID}) -> extension ${TEST_EXT}"
LOG_MARK_BEFORE_IN="$($COMPOSE exec -T asterisk sh -c 'wc -l < /var/log/asterisk/full' 2>/dev/null | tr -d '\r ')"
UNIQUEID_MARK_IN="$(db_query "SELECT MAX(uniqueid) FROM cdr;")"
UNIQUEID_MARK_IN="${UNIQUEID_MARK_IN:-0}"

# The provider originates a real INVITE through its own static to-senma
# endpoint (docker/provider-config/pjsip.conf), Request-URI user=58888.
# Once SENMA's routed extension answers, the LOCAL (provider-side) leg
# runs a plain Wait() -- exactly how a real carrier switch originates a
# call without running any dialplan logic of its own; the actual
# ring/answer/hold under test happens entirely on SENMA's side.
$COMPOSE exec -T provider asterisk -rx "channel originate PJSIP/${TEST_DESTINATION_INBOUND}@${PROVIDER_TO_SENMA_ENDPOINT} application Wait 5" >&2

sleep 2
MIDCALL="$($COMPOSE exec -T asterisk asterisk -rx 'core show channels' 2>&1)"
if echo "$MIDCALL" | grep -qE "^[1-9][0-9]* active channels?"; then
    harness_ok "call established briefly" "SENMA reports active channel(s) mid-call: $(echo "$MIDCALL" | grep -E "^[0-9]+ active channels?")"
else
    harness_bad "call established briefly" "no active channels observed mid-call: $MIDCALL"
fi

sleep 5
FINAL_IN="$($COMPOSE exec -T asterisk asterisk -rx 'core show channels' 2>&1)"
if echo "$FINAL_IN" | grep -q "^0 active channels"; then
    harness_ok "inbound call hangup succeeded" "0 active channels after the provider's own Wait()+Hangup"
else
    harness_bad "inbound call hangup succeeded" "channels still active: $FINAL_IN"
fi

# --- 24. Trunk identity + AGI/rule engine trace (item 8: do not infer trunk
#         identity merely because the destination rang) --------------------

log "==> checking trunk identity + AGI/rule engine trace"
AGI_TRACE_IN="$($COMPOSE exec -T asterisk sh -c "tail -n +$((LOG_MARK_BEFORE_IN+1)) /var/log/asterisk/full" 2>/dev/null)"
if echo "$AGI_TRACE_IN" | grep -q "(PJSIP/${TRUNK_OBJ}-" \
    && echo "$AGI_TRACE_IN" | grep -qF "Identified source: ${TRUNK_CALLERID} (Snep_Trunk)" \
    && echo "$AGI_TRACE_IN" | grep -q "Running the rule .*:${INBOUND_ROUTE_DESC}" \
    && echo "$AGI_TRACE_IN" | grep -q "Discando para ramal ${TEST_EXT} no canal PJSIP/${TEST_EXT}" \
    && echo "$AGI_TRACE_IN" | grep -q "Launched AGI Script .*snep/snep.php"; then
    harness_ok "trunk identity + AGI/rule engine trace" "channel resolved to PJSIP/${TRUNK_OBJ}-*, PBX_Interfaces::getChannelOwner() identified it as Snep_Trunk '${TRUNK_CALLERID}' (not merely 'destination rang'), matched the inbound fixture rule, DiscarRamal dialed extension ${TEST_EXT}"
else
    harness_bad "trunk identity + AGI/rule engine trace" "expected trunk-identity/AGI/rule trace not found in Asterisk's log for this call"
fi

# --- 25. CDR row exists and is correct --------------------------------------

log "==> checking inbound CDR"
CDR_ROW_IN="$(db_query "SELECT uniqueid,src,disposition,duration,billsec,channel,dstchannel,calldate FROM cdr WHERE dst='${TEST_DESTINATION_INBOUND}' AND uniqueid > '${UNIQUEID_MARK_IN}' ORDER BY calldate ASC, uniqueid ASC LIMIT 1;")"
CDR_IN_UNIQUEID="$(echo "$CDR_ROW_IN" | awk -F'\t' '{print $1}')"
CDR_IN_SRC="$(echo "$CDR_ROW_IN" | awk -F'\t' '{print $2}')"
CDR_IN_DISPOSITION="$(echo "$CDR_ROW_IN" | awk -F'\t' '{print $3}')"
CDR_IN_DURATION="$(echo "$CDR_ROW_IN" | awk -F'\t' '{print $4}')"
CDR_IN_BILLSEC="$(echo "$CDR_ROW_IN" | awk -F'\t' '{print $5}')"
CDR_IN_CHANNEL="$(echo "$CDR_ROW_IN" | awk -F'\t' '{print $6}')"
CDR_IN_DSTCHANNEL="$(echo "$CDR_ROW_IN" | awk -F'\t' '{print $7}')"
CDR_IN_CALLDATE="$(echo "$CDR_ROW_IN" | awk -F'\t' '{print $8}')"

if [ -n "$CDR_IN_UNIQUEID" ] \
    && [ "$CDR_IN_DISPOSITION" = "ANSWERED" ] \
    && [ "${CDR_IN_DURATION:-0}" -gt 0 ] 2>/dev/null \
    && [ "${CDR_IN_BILLSEC:-0}" -gt 0 ] 2>/dev/null \
    && [[ "$CDR_IN_CHANNEL" == PJSIP/${TRUNK_OBJ}-* ]] \
    && [[ "$CDR_IN_DSTCHANNEL" == PJSIP/${TEST_EXT}-* ]] \
    && [[ "$CDR_IN_CALLDATE" != "0000-00-00"* ]]; then
    harness_ok "inbound CDR row exists and is correct" "uniqueid=$CDR_IN_UNIQUEID src=$CDR_IN_SRC disposition=ANSWERED duration=$CDR_IN_DURATION billsec=$CDR_IN_BILLSEC channel=$CDR_IN_CHANNEL dstchannel=$CDR_IN_DSTCHANNEL calldate=$CDR_IN_CALLDATE"
else
    harness_bad "inbound CDR row exists and is correct" "no matching/valid CDR row found (uniqueid='$CDR_IN_UNIQUEID' src='$CDR_IN_SRC' disposition='$CDR_IN_DISPOSITION' duration='$CDR_IN_DURATION' billsec='$CDR_IN_BILLSEC' channel='$CDR_IN_CHANNEL' dstchannel='$CDR_IN_DSTCHANNEL' calldate='$CDR_IN_CALLDATE')"
fi

# --- 26. SENMA reporting path can read it back ------------------------------

log "==> checking SENMA report readback (inbound)"
if [ -n "$CDR_IN_UNIQUEID" ] && harness_cdr_report_window "$CDR_IN_CALLDATE" 5; then
    # TASK-0027A: window anchored on this call's own already-confirmed
    # CDR_IN_CALLDATE (see harness_cdr_report_window in lib/harness.sh),
    # not on "today" -- see call-smoke-test.sh's equivalent check for the
    # full rationale.
    REPORT_JSON_IN="$(curl -sS -u "${TEST_USER}:${TEST_PASSWORD}" \
        "${BASE_URL}/modules/default/api/index.php?service=CallsReport&start_date=${HARNESS_REPORT_START_DATE}&start_hour=${HARNESS_REPORT_START_HOUR}&end_date=${HARNESS_REPORT_END_DATE}&end_hour=${HARNESS_REPORT_END_HOUR}&report_type=analytic&status_answered=1&dst=${TEST_DESTINATION_INBOUND}&order_dst=equal" 2>&1)"
    if echo "$REPORT_JSON_IN" | grep -qF "\"uniqueid\":\"${CDR_IN_UNIQUEID}\""; then
        harness_ok "SENMA reporting path can read it (inbound)" "CallsReport API endpoint returned this exact CDR (uniqueid=$CDR_IN_UNIQUEID)"
    else
        harness_bad "SENMA reporting path can read it (inbound)" "CallsReport API did not return uniqueid=$CDR_IN_UNIQUEID: $REPORT_JSON_IN"
    fi
else
    harness_bad "SENMA reporting path can read it (inbound)" "skipped -- no CDR uniqueid available, or the report window could not be computed"
fi

# --- Cleanup happens via harness_complete's cleanup pass (HTTP delete of
#     the trunk and extension fixtures, PBX_Rules::delete() for both
#     route fixtures, in dependency-safe LIFO order: inbound route,
#     outbound route, extension, trunk -- then a fresh
#     Snep_PjsipTrunkConf/Snep_PjsipConf regeneration naturally omits
#     them all) ------------------------------------------------------------

harness_complete
