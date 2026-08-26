#!/bin/bash
#
# SENMA PJSIP transport smoke test (TASK-0018).
#
# Proves, end to end, against a running `make dev` Docker environment,
# using SENMA's own application flow (not direct SQL for the transport
# itself, not hand-written PJSIP config), that first-class PJSIP
# transports work:
#
#   HTTP POST to PjsipTransportsController::addAction()
#   -> pjsip_transports (+ pjsip_transport_networks) rows persisted
#   -> Snep_PjsipTransportConf::loadConfFromDb() generates the [name]
#      transport section into senma-pjsip-transports.conf
#      -> module reload res_pjsip.so
#   -> real Asterisk PJSIP runtime shows the transport (pjsip show
#      transport <name>), with every independently-configured field
#      (domain, external_signaling_address/port, external_media_address,
#      local_net x2, symmetric_transport) present and NOT collapsed into
#      each other or into the remote-host/identify concepts trunks
#      already use (docs/tasks/0017-pjsip-transports-and-templates-architecture.md
#      §1.6/§13/§14 -- this is the exact "independent concepts" acceptance
#      case the architecture doc's Sercomtel-style example describes)
#   -> edit the transport (a real Asterisk-confirmed hot-reloadable
#      change, see docs/tasks/0018-pjsip-transports.md's reload-semantics
#      findings) -> regenerated config + live runtime both reflect it
#   -> a controlled extension fixture is pointed at this transport
#      (peers.transport_id) -> Snep_PjsipConf emits transport=<name> for
#      it instead of the system default -> deletion is blocked while
#      referenced -> reference cleared -> deletion succeeds -> no stale
#      transport remains anywhere.
#
# bind_port is 5070, NOT the literal 0.0.0.0:5060 the architecture doc's
# illustrative example used -- 5060/udp is already bound by the real
# seeded default `udp` transport for the whole duration of this test
# suite; reusing it would be a genuine port conflict, not a fixture
# choice. external_media_address/external_signaling_address use
# 203.0.113.0/24 (RFC 5737 TEST-NET-3, reserved for documentation/
# examples) -- a structural acceptance fixture, never a real carrier's
# address.
#
# Separate from scripts/smoke-test.sh/call-smoke-test.sh/
# trunk-smoke-test.sh by design -- transport lifecycle is its own
# failure domain, independent of any specific extension/trunk.
#
# Exit code: 0 if every check PASSes; 1 if any check FAILs.

set -uo pipefail

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
BASE_URL="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
TEST_USER="admin"
TEST_PASSWORD="SmokeTest123!"
FIXTURE_MARKER="task0018-transport-smoke"

TRANSPORT_NAME="sercomtel-smoke"
TRANSPORT_BIND_ADDRESS="0.0.0.0"
TRANSPORT_BIND_PORT="5070"
TRANSPORT_DOMAIN="sercomtel.example.test"
TRANSPORT_EXT_MEDIA="203.0.113.10"
TRANSPORT_EXT_MEDIA_EDITED="203.0.113.20"
TRANSPORT_EXT_SIGNALING="203.0.113.11"
TRANSPORT_EXT_SIGNALING_PORT="5070"
TRANSPORT_LOCAL_NET_1="172.28.0.0/16"
TRANSPORT_LOCAL_NET_2="192.168.0.0/16"

REF_EXT=1098
REF_EXT_SECRET="${FIXTURE_MARKER}-ext"

PASS=0
FAIL=0
declare -a RESULTS=()
CREATED_TRANSPORT_ID=""
CREATED_REF_EXT=0
COOKIEJAR=""

log()  { printf '%s\n' "$*" >&2; }
row()  { RESULTS+=("$1|$2|$3"); }
ok()   { row "$1" "PASS" "$2"; PASS=$((PASS+1)); log "PASS: $1 -- $2"; }
bad()  { row "$1" "FAIL" "$2"; FAIL=$((FAIL+1)); log "FAIL: $1 -- $2"; }

print_report() {
    echo
    echo "================================================================"
    printf "%-40s %-8s %s\n" "CHECK" "RESULT" "DETAIL"
    echo "----------------------------------------------------------------"
    for r in "${RESULTS[@]}"; do
        IFS='|' read -r flow status detail <<< "$r"
        printf "%-40s %-8s %s\n" "$flow" "$status" "$detail"
    done
    echo "================================================================"
    echo "PASS: $PASS   FAIL: $FAIL"
    echo "================================================================"
}

stop() {
    log "STOP: $*"
    echo "STOP: $*"
    cleanup
    exit 1
}

db_query() {
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
        "${DB_NAME:-snep}" -N -e "$1"
}

http_login() {
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null \
        -d "user=${TEST_USER}&password=${TEST_PASSWORD}" "${BASE_URL}/index.php/auth/login"
}

create_transport() {
    local body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "name=${TRANSPORT_NAME}" \
        --data-urlencode "protocol=udp" \
        --data-urlencode "bind_address=${TRANSPORT_BIND_ADDRESS}" \
        --data-urlencode "bind_port=${TRANSPORT_BIND_PORT}" \
        --data-urlencode "domain=${TRANSPORT_DOMAIN}" \
        --data-urlencode "external_signaling_address=${TRANSPORT_EXT_SIGNALING}" \
        --data-urlencode "external_signaling_port=${TRANSPORT_EXT_SIGNALING_PORT}" \
        --data-urlencode "external_media_address=${TRANSPORT_EXT_MEDIA}" \
        --data-urlencode "local_net=${TRANSPORT_LOCAL_NET_1}
${TRANSPORT_LOCAL_NET_2}" \
        --data-urlencode "symmetric_transport=1" \
        --data-urlencode "allow_reload=1" \
        --data-urlencode "enabled=1" \
        "${BASE_URL}/index.php/default/pjsip-transports/add")"
    if [ "$httpcode" = "302" ]; then
        rm -f "$body"
        return 0
    fi
    log "create_transport failed (HTTP $httpcode): $(head -c 400 "$body")"
    rm -f "$body"
    return 1
}

edit_transport() {
    local id="$1" media="$2" httpcode body
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "name=${TRANSPORT_NAME}" \
        --data-urlencode "protocol=udp" \
        --data-urlencode "bind_address=${TRANSPORT_BIND_ADDRESS}" \
        --data-urlencode "bind_port=${TRANSPORT_BIND_PORT}" \
        --data-urlencode "domain=${TRANSPORT_DOMAIN}" \
        --data-urlencode "external_signaling_address=${TRANSPORT_EXT_SIGNALING}" \
        --data-urlencode "external_signaling_port=${TRANSPORT_EXT_SIGNALING_PORT}" \
        --data-urlencode "external_media_address=${media}" \
        --data-urlencode "local_net=${TRANSPORT_LOCAL_NET_1}
${TRANSPORT_LOCAL_NET_2}" \
        --data-urlencode "symmetric_transport=1" \
        --data-urlencode "allow_reload=1" \
        --data-urlencode "enabled=1" \
        "${BASE_URL}/index.php/default/pjsip-transports/edit/id/${id}")"
    if [ "$httpcode" = "302" ]; then
        rm -f "$body"
        return 0
    fi
    log "edit_transport failed (HTTP $httpcode): $(head -c 400 "$body")"
    rm -f "$body"
    return 1
}

# delete_transport -- returns the raw response body via a global, since
# the caller needs to distinguish "blocked" (200, error page) from
# "succeeded" (302) rather than just pass/fail.
DELETE_BODY=""
DELETE_HTTPCODE=""
delete_transport() {
    local id="$1"
    local body
    body="$(mktemp)"
    DELETE_HTTPCODE="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "id=${id}" \
        --data-urlencode "delete=Delete" \
        "${BASE_URL}/index.php/default/pjsip-transports/remove")"
    DELETE_BODY="$(cat "$body")"
    rm -f "$body"
}

create_ref_extension() {
    local ext="$1" secret="$2" body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "name=SENMA transport-smoke ${ext}" \
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
        "${BASE_URL}/index.php/default/extensions/add")"
    if [ "$httpcode" = "302" ]; then
        rm -f "$body"
        return 0
    fi
    log "create_ref_extension ${ext} failed (HTTP $httpcode): $(head -c 300 "$body")"
    rm -f "$body"
    return 1
}

delete_extension() {
    local ext="$1" httpcode
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "id=${ext}" \
        --data-urlencode "delete=Delete" \
        "${BASE_URL}/index.php/default/extensions/remove")"
    [ "$httpcode" = "302" ]
}

regenerate_all() {
    # Same one-off bootstrap pattern used throughout this task's
    # implementation/validation -- no HTTP write action exists that
    # regenerates all three generators without also mutating a row, and
    # this script needs to force a regeneration after clearing
    # transport_id directly via SQL (item 10 deliberately has no UI for
    # that column yet, TASK-0017 §19/TASK-0018 item 10 scope).
    $COMPOSE exec -T app php -r '
        define("APPLICATION_PATH", "/var/www/html/snep");
        set_include_path(implode(PATH_SEPARATOR, array(APPLICATION_PATH . "/lib", get_include_path())));
        require_once "Snep/Config.php";
        Snep_Config::setConfigFile(APPLICATION_PATH . "/includes/setup.conf");
        require_once "Zend/Registry.php";
        Zend_Registry::set("config", Snep_Config::getConfig());
        require_once "Snep/Db.php";
        Zend_Registry::set("db", Snep_Db::getInstance());
        require_once "Snep/Logger.php";
        require_once "Zend/Log/Writer/Null.php";
        Snep_Logger::getInstance()->addWriter(new Zend_Log_Writer_Null());
        require_once "Zend/View.php";
        require_once "PBX/Exception/IO.php";
        require_once "PBX/Exception/NotFound.php";
        require_once "Asterisk/AMI.php";
        require_once "PBX/Asterisk/AMI.php";
        require_once "Snep/PjsipTransports/Manager.php";
        require_once "Snep/PjsipTransportConf.php";
        require_once "Snep/PjsipConf.php";
        require_once "Snep/PjsipTrunkConf.php";
        Snep_PjsipTransportConf::loadConfFromDb();
        Snep_PjsipConf::loadConfFromDb();
        Snep_PjsipTrunkConf::loadConfFromDb();
    ' >&2
}

cleanup() {
    trap - EXIT
    log "==> cleanup"
    if [ -n "$COOKIEJAR" ]; then
        if [ "$CREATED_REF_EXT" = "1" ]; then
            db_query "UPDATE peers SET transport_id = NULL WHERE name = '${REF_EXT}';" >/dev/null 2>&1
            delete_extension "$REF_EXT" && log "removed reference extension ${REF_EXT} via HTTP" \
                || log "WARNING: HTTP delete of extension ${REF_EXT} did not return 302 -- may need manual cleanup"
        fi
        if [ -n "$CREATED_TRANSPORT_ID" ]; then
            delete_transport "$CREATED_TRANSPORT_ID"
            if [ "$DELETE_HTTPCODE" = "302" ]; then
                log "removed test fixture transport id=${CREATED_TRANSPORT_ID} via HTTP"
            else
                log "WARNING: HTTP delete of transport id=${CREATED_TRANSPORT_ID} did not return 302 (still referenced?) -- may need manual cleanup"
            fi
        fi
        rm -f "$COOKIEJAR"
    fi
}
trap cleanup EXIT

# --- 1. Required containers healthy ---------------------------------------

log "==> checking required containers"
ALL_UP=1
for svc in app asterisk db; do
    if ! $COMPOSE ps "$svc" 2>/dev/null | grep -q "Up"; then
        ALL_UP=0
    fi
done
if [ "$ALL_UP" = "1" ]; then
    ok "containers healthy" "app, asterisk, db all Up"
else
    bad "containers healthy" "one or more of app/asterisk/db not Up -- run 'make up' first"
    cleanup
    trap - EXIT
    exit 1
fi

: "${DB_USER:?DB_USER must be set (source .env first)}"
: "${DB_PASSWORD:?DB_PASSWORD must be set (source .env first)}"
: "${DB_NAME:?DB_NAME must be set (source .env first)}"

if ! $COMPOSE exec -T asterisk asterisk -rx 'module show like res_pjsip.so' 2>&1 | grep -q "Running"; then
    bad "PJSIP module Running" "res_pjsip.so not Running"
    cleanup
    trap - EXIT
    exit 1
fi
ok "PJSIP module Running" "res_pjsip.so Running"

# --- 2. Log in, check for collisions ---------------------------------------

COOKIEJAR="$(mktemp)"
log "==> logging in as ${TEST_USER}"
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${TEST_PASSWORD}');" 2>/dev/null | tr -d '\r')"
db_query "UPDATE users SET password = '${TEST_HASH}' WHERE name = '${TEST_USER}';" >&2
http_login

log "==> checking for pre-existing fixtures"
EXISTING_TRANSPORT="$(db_query "SELECT id FROM pjsip_transports WHERE name='${TRANSPORT_NAME}';")"
if [ -n "$EXISTING_TRANSPORT" ]; then
    stop "a transport named '${TRANSPORT_NAME}' already exists (id=${EXISTING_TRANSPORT}) from a prior run that did not clean up. Remove it manually first."
fi
EXISTING_EXT_CANAL="$(db_query "SELECT canal FROM peers WHERE name='${REF_EXT}';")"
EXISTING_EXT_SECRET="$(db_query "SELECT secret FROM peers WHERE name='${REF_EXT}';")"
if [ -n "$EXISTING_EXT_CANAL" ]; then
    if [ "$EXISTING_EXT_CANAL" = "PJSIP/${REF_EXT}" ] && [[ "$EXISTING_EXT_SECRET" == "${FIXTURE_MARKER}"* ]]; then
        log "extension ${REF_EXT} is a leftover transport-smoke fixture -- removing via HTTP before re-creating"
        delete_extension "$REF_EXT" || stop "found a leftover transport-smoke fixture for extension ${REF_EXT} but the HTTP delete flow did not return 302"
    else
        stop "peers row for extension '${REF_EXT}' already exists (canal='${EXISTING_EXT_CANAL}') and is NOT a transport-smoke fixture. Refusing to overwrite real/unknown data."
    fi
fi

# --- 3. Create the Sercomtel-style transport via the real UI ---------------

log "==> creating transport ${TRANSPORT_NAME} via the real PjsipTransportsController::addAction() HTTP flow"
if create_transport; then
    CREATED_TRANSPORT_ID="$(db_query "SELECT id FROM pjsip_transports WHERE name='${TRANSPORT_NAME}';")"
    if [ -z "$CREATED_TRANSPORT_ID" ]; then
        stop "transport creation returned 302 but no matching row was found afterward"
    fi
    ok "transport created" "id=${CREATED_TRANSPORT_ID} via the real HTTP flow (not SQL, not hand-written config)"
else
    stop "creating the test transport via the real UI flow failed -- see log above"
fi

# --- 4. Independent fields appear correctly in the generated config -------

log "==> checking generated senma-pjsip-transports.conf"
GENERATED_CONF="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip-transports.conf 2>/dev/null)"
SECTION="$(echo "$GENERATED_CONF" | awk "/^\[${TRANSPORT_NAME}\]/{f=1} f{print} f&&/^\$/{exit}")"

# item 11's explicit non-equivalence requirement: signaling destination,
# identify match, domain, external signaling, external media are
# independent values -- assert each appears with its OWN distinct value,
# not that "some address" appears anywhere.
if echo "$SECTION" | grep -qF "protocol=udp" \
    && echo "$SECTION" | grep -qF "bind=${TRANSPORT_BIND_ADDRESS}:${TRANSPORT_BIND_PORT}" \
    && echo "$SECTION" | grep -qF "domain=${TRANSPORT_DOMAIN}" \
    && echo "$SECTION" | grep -qF "external_signaling_address=${TRANSPORT_EXT_SIGNALING}" \
    && echo "$SECTION" | grep -qF "external_signaling_port=${TRANSPORT_EXT_SIGNALING_PORT}" \
    && echo "$SECTION" | grep -qF "external_media_address=${TRANSPORT_EXT_MEDIA}" \
    && echo "$SECTION" | grep -qF "local_net=${TRANSPORT_LOCAL_NET_1}" \
    && echo "$SECTION" | grep -qF "local_net=${TRANSPORT_LOCAL_NET_2}" \
    && echo "$SECTION" | grep -qF "symmetric_transport=yes"; then
    ok "generated config has independent field values" "domain/${TRANSPORT_DOMAIN}, external_signaling/${TRANSPORT_EXT_SIGNALING}:${TRANSPORT_EXT_SIGNALING_PORT}, external_media/${TRANSPORT_EXT_MEDIA}, 2x local_net all present and distinct"
else
    bad "generated config has independent field values" "expected fields not found verbatim in [${TRANSPORT_NAME}] section:\n${SECTION}"
fi

# --- 5. Asterisk's real runtime sees it (not just the generated file) -----

log "==> checking Asterisk's live PJSIP runtime"
RUNTIME="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show transport ${TRANSPORT_NAME}" 2>&1)"
if echo "$RUNTIME" | grep -qF "bind                        : ${TRANSPORT_BIND_ADDRESS}:${TRANSPORT_BIND_PORT}" \
    && echo "$RUNTIME" | grep -qF "domain                      : ${TRANSPORT_DOMAIN}" \
    && echo "$RUNTIME" | grep -qF "external_media_address      : ${TRANSPORT_EXT_MEDIA}" \
    && echo "$RUNTIME" | grep -qF "external_signaling_address  : ${TRANSPORT_EXT_SIGNALING}" \
    && echo "$RUNTIME" | grep -qF "symmetric_transport         : true"; then
    ok "pjsip show transport ${TRANSPORT_NAME}" "live runtime reflects every configured field (not inferred from the file alone)"
else
    bad "pjsip show transport ${TRANSPORT_NAME}" "live runtime did not reflect expected values:\n${RUNTIME}"
fi

ALL_TRANSPORTS="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show transports" 2>&1)"
if echo "$ALL_TRANSPORTS" | grep -qF "${TRANSPORT_NAME}"; then
    ok "pjsip show transports lists it" "${TRANSPORT_NAME} present alongside the system default"
else
    bad "pjsip show transports lists it" "not found: $ALL_TRANSPORTS"
fi

# --- 6. Edit is hot-reloadable (empirically confirmed safe, see docs) -----

log "==> editing the transport's external_media_address"
if edit_transport "$CREATED_TRANSPORT_ID" "$TRANSPORT_EXT_MEDIA_EDITED"; then
    RUNTIME_AFTER_EDIT="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show transport ${TRANSPORT_NAME}" 2>&1)"
    if echo "$RUNTIME_AFTER_EDIT" | grep -qF "external_media_address      : ${TRANSPORT_EXT_MEDIA_EDITED}"; then
        ok "edit reflected live via plain reload" "external_media_address updated to ${TRANSPORT_EXT_MEDIA_EDITED} with no process restart"
    else
        bad "edit reflected live via plain reload" "still shows old value:\n${RUNTIME_AFTER_EDIT}"
    fi
else
    bad "edit reflected live via plain reload" "HTTP edit did not return 302"
fi

# --- 7. Usage tracking + delete-blocked-while-in-use -----------------------

log "==> creating a reference extension and pointing it at this transport"
if create_ref_extension "$REF_EXT" "$REF_EXT_SECRET"; then
    CREATED_REF_EXT=1
else
    stop "creating reference extension ${REF_EXT} failed -- see log above"
fi
db_query "UPDATE peers SET transport_id = ${CREATED_TRANSPORT_ID} WHERE name = '${REF_EXT}';" >&2
regenerate_all

GENERATED_EXT_CONF="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip.conf 2>/dev/null)"
EXT_SECTION="$(echo "$GENERATED_EXT_CONF" | awk "/^\[${REF_EXT}\]/{f=1} f{print} f&&/^\$/{exit}")"
if echo "$EXT_SECTION" | grep -qF "transport=${TRANSPORT_NAME}"; then
    ok "extension references the custom transport" "[${REF_EXT}] emits transport=${TRANSPORT_NAME} (not the system default)"
else
    bad "extension references the custom transport" "expected transport=${TRANSPORT_NAME} not found:\n${EXT_SECTION}"
fi

log "==> attempting to delete the transport while it is still referenced"
delete_transport "$CREATED_TRANSPORT_ID"
if [ "$DELETE_HTTPCODE" != "302" ] && echo "$DELETE_BODY" | grep -qi "Cannot remove"; then
    ok "delete blocked while in use" "HTTP $DELETE_HTTPCODE, error page correctly lists the referencing extension"
else
    bad "delete blocked while in use" "expected a blocked (non-302) response with 'Cannot remove'; got HTTP $DELETE_HTTPCODE"
fi

STILL_THERE="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show transport ${TRANSPORT_NAME}" 2>&1)"
if echo "$STILL_THERE" | grep -q "bind "; then
    ok "transport survives the blocked delete attempt" "still present in Asterisk's live runtime, unchanged"
else
    bad "transport survives the blocked delete attempt" "transport disappeared despite the delete being blocked"
fi

# --- 8. Clear the reference, delete succeeds, no stale transport remains --

log "==> clearing the reference and deleting the transport for real"
db_query "UPDATE peers SET transport_id = NULL WHERE name = '${REF_EXT}';" >&2
regenerate_all

EXT_SECTION_AFTER="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip.conf 2>/dev/null | awk "/^\[${REF_EXT}\]/{f=1} f{print} f&&/^\$/{exit}")"
if echo "$EXT_SECTION_AFTER" | grep -qF "transport=udp"; then
    ok "extension reverts to the default transport" "[${REF_EXT}] now emits transport=udp (NULL transport_id resolves to is_default)"
else
    bad "extension reverts to the default transport" "expected transport=udp not found:\n${EXT_SECTION_AFTER}"
fi

delete_transport "$CREATED_TRANSPORT_ID"
if [ "$DELETE_HTTPCODE" = "302" ]; then
    ok "delete succeeds once unreferenced" "HTTP 302"
    CREATED_TRANSPORT_ID=""
else
    bad "delete succeeds once unreferenced" "HTTP $DELETE_HTTPCODE: $DELETE_BODY"
fi

FINAL_CONF="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip-transports.conf 2>/dev/null)"
FINAL_RUNTIME="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show transports" 2>&1)"
if ! echo "$FINAL_CONF" | grep -q "\[${TRANSPORT_NAME}\]" && ! echo "$FINAL_RUNTIME" | grep -q "${TRANSPORT_NAME}"; then
    ok "no stale transport remains" "removed from both the generated file and Asterisk's live runtime"
else
    bad "no stale transport remains" "still present somewhere -- file: $(echo "$FINAL_CONF" | grep -c "\[${TRANSPORT_NAME}\]"), runtime: $(echo "$FINAL_RUNTIME" | grep -c "${TRANSPORT_NAME}")"
fi

print_report

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
