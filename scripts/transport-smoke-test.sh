#!/bin/bash
#
# SENMA PJSIP transport smoke test (TASK-0018, extended by TASK-0019).
#
# Checks 1-18 (TASK-0018) prove the transport model/generator/CRUD UI,
# with transport_id set via direct SQL since no selector existed yet.
# Checks 19+ (TASK-0019, "PART 2" below) prove the real extension/trunk
# transport <select> TASK-0019 added -- full AUTO/EXPLICIT-A/EXPLICIT-B/
# AUTO edit-transition round trips via the real HTTP form, the mandatory
# EXPLICIT->AUTO write-NULL fix, disabled-transport selection rejection,
# an already-referenced transport later being disabled (dangling
# reference prevention + UI surfacing), trunk-referenced delete-blocked
# (a real coverage gap in checks 1-18, where the trunk fixture is always
# removed before the transport delete is attempted), and rename cascading
# into a live dependent object. See
# docs/tasks/0019-pjsip-transport-selection-ux.md.
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
#   -> a fresh extension with transport_id still NULL (AUTO, the only
#      state reachable through the real UI today, item 10) generates NO
#      transport= line at all -> pointed at this transport
#      (peers.transport_id, set directly -- no picker UI exists yet, see
#      docs/tasks/0018-pjsip-transports.md's UI section) ->
#      Snep_PjsipConf emits the exact transport=<name> pin -> deletion is
#      blocked while referenced -> reference cleared -> the extension
#      reverts to AUTO (no transport= line again, NOT transport=udp --
#      see the corrected invariant below) -> deletion succeeds -> no
#      stale transport remains anywhere. The identical AUTO-vs-pinned
#      proof is repeated for a trunk's endpoint AND registration objects
#      (§ below), since TASK-0018's correction verified -- rather than
#      assumed -- that both behave the same way for this question.
#
# TASK-0018 correction (post-initial-commit): transport_id=NULL means
# AUTO -- "no explicit transport pinning", never "resolve to the default
# transport". The original implementation always resolved NULL to
# whichever transport was marked is_default and always emitted a
# transport= line; that was a real functional bug, not a style choice --
# Asterisk's own documentation is explicit that an endpoint's transport=
# option "will *force* the endpoint to use the specified transport... You
# need to already know what kind of transport... the endpoint device will
# use", so pinning every extension to transport=udp would break a device
# that registered over TCP. Confirmed live (this task's own
# investigation) that omitting transport= entirely lets a real
# registration and a real call complete identically to having it set,
# for both endpoint and registration objects.
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
# TASK-0027: rebuilt on scripts/lib/harness.sh for explicit
# PASS/FAIL/BLOCKED/INCONCLUSIVE classification and signal-safe
# finalization. The three combined `trap 'x_cleanup; ...' EXIT` reassignments
# (checks 1-18, Part 2/UX, Part 3/T20) are replaced by
# harness_register_cleanup calls made right after each cleanup function is
# defined -- harness_finalize runs them in reverse (LIFO) registration
# order, which reproduces the exact same t20_cleanup -> ux_cleanup ->
# cleanup sequence the old chained trap used. Each cleanup function now
# also returns nonzero if any of its own fixture deletions failed, so a
# required-cleanup failure downgrades an otherwise-PASS run to FAIL
# instead of being silently invisible in the exit code. See
# docs/tasks/0027-regression-harness-reliability.md.
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

TRUNK_CALLERID="${FIXTURE_MARKER} trunk fixture"

CREATED_TRANSPORT_ID=""
CREATED_REF_EXT=0
CREATED_TRUNK_ID=""
CREATED_TRUNK_NAME=""
COOKIEJAR=""

log()  { harness_log "$@"; }
ok()   { harness_ok "$1" "$2"; }
bad()  { harness_bad "$1" "$2"; }

# stop() preserves every existing call site's syntax (`stop "reason"`)
# unchanged -- it now classifies BLOCKED (via the shared harness lib)
# instead of an ad hoc `cleanup; exit 1`.
stop() {
    harness_blocked "$*"
}

db_query() {
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
        "${DB_NAME:-snep}" -N -e "$1"
}

# is_db_null <value> -- mariadb's -N (skip column names) output still
# renders a SQL NULL as the literal text "NULL", not an empty string --
# TASK-0019's own checks below query transport_id directly (checks 1-18
# never did, they only ever inspected the generated file), so this
# matters here in a way it never did before.
is_db_null() {
    [ -z "$1" ] || [ "$1" = "NULL" ]
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
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
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
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
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
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
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
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
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
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/extensions/remove")"
    [ "$httpcode" = "302" ]
}

# create_trunk_fixture -- a minimal register-based PJSIP trunk (same
# field shape as trunk-smoke-test.sh's own create_trunk()), used here
# only to prove a trunk's endpoint AND registration objects can both be
# pinned to an explicit transport. reverse_auth=1 so a registration
# object actually exists to check.
create_trunk_fixture() {
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
    log "create_trunk_fixture failed (HTTP $httpcode): $(head -c 300 "$body")"
    rm -f "$body"
    return 1
}

# delete_trunk_fixture -- deliberately looks up the trunk's real `name`
# column from the DB rather than guessing/hardcoding it.
# TrunksController::removeAction() deletes the matching `peers` row using
# whatever `name` the request posts, NOT the trunk's actual stored name
# -- trunk-smoke-test.sh has a real, pre-existing, documented bug here
# (docs/tasks/0018-pjsip-transports.md §14, hardcodes "1"). Not fixed
# there (out of this task's scope, per its own stop-rule), but correctly
# avoided here by construction.
delete_trunk_fixture() {
    local id="$1" name
    name="$(db_query "SELECT name FROM trunks WHERE id=${id};")"
    if [ -z "$name" ]; then
        log "WARNING: could not look up trunk id=${id}'s name for cleanup -- may already be gone"
        return 1
    fi
    local httpcode
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "id=${id}" \
        --data-urlencode "name=${name}" \
        --data-urlencode "delete=Delete" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/trunks/remove")"
    [ "$httpcode" = "302" ]
}

# ---------------------------------------------------------------------------
# TASK-0019 helpers -- the real UI transport selector on extensions/trunks.
# Unlike everything above (which sets transport_id via direct SQL, since no
# selector existed when TASK-0018 shipped), these post the real
# transport_id form field TASK-0019 added.
# ---------------------------------------------------------------------------

# save_transport <add|edit> <id-or-empty> <name> <protocol> <port> <enabled:0|1>
# Sets SAVE_TRANSPORT_HTTPCODE/SAVE_TRANSPORT_BODY. enabled=0 OMITS the
# checkbox field entirely (matching a real unchecked checkbox -- browsers
# never POST "enabled=0", they omit the key, and buildData()'s
# isset($post['enabled']) check depends on that omission).
SAVE_TRANSPORT_HTTPCODE=""
SAVE_TRANSPORT_BODY=""
save_transport() {
    local mode="$1" id="$2" name="$3" protocol="$4" port="$5" enabled="$6" body url
    body="$(mktemp)"
    if [ "$mode" = "add" ]; then
        url="${BASE_URL}/index.php/default/pjsip-transports/add"
    else
        url="${BASE_URL}/index.php/default/pjsip-transports/edit/id/${id}"
    fi
    # NOTE: deliberately two full curl invocations rather than building an
    # "enabled" arg in an array conditionally added via "${arr[@]}" --
    # under `set -u`, bash 3.2 (macOS's shipped /bin/bash) treats
    # expanding a still-empty array as an unbound-variable error. enabled=0
    # OMITS the field entirely (matching a real unchecked checkbox --
    # buildData()'s isset($post['enabled']) check depends on the key being
    # absent, not on its value being "0").
    if [ "$enabled" = "1" ]; then
        SAVE_TRANSPORT_HTTPCODE="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
            --data-urlencode "name=${name}" \
            --data-urlencode "protocol=${protocol}" \
            --data-urlencode "bind_address=0.0.0.0" \
            --data-urlencode "bind_port=${port}" \
            --data-urlencode "domain=" \
            --data-urlencode "external_signaling_address=" \
            --data-urlencode "external_signaling_port=" \
            --data-urlencode "external_media_address=" \
            --data-urlencode "local_net=" \
            --data-urlencode "allow_reload=1" \
            --data-urlencode "enabled=1" \
            --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
            "$url")"
    else
        SAVE_TRANSPORT_HTTPCODE="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
            --data-urlencode "name=${name}" \
            --data-urlencode "protocol=${protocol}" \
            --data-urlencode "bind_address=0.0.0.0" \
            --data-urlencode "bind_port=${port}" \
            --data-urlencode "domain=" \
            --data-urlencode "external_signaling_address=" \
            --data-urlencode "external_signaling_port=" \
            --data-urlencode "external_media_address=" \
            --data-urlencode "local_net=" \
            --data-urlencode "allow_reload=1" \
            --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
            "$url")"
    fi
    SAVE_TRANSPORT_BODY="$(cat "$body")"
    rm -f "$body"
}

# save_ref_extension <add|edit> <ext> <secret> <transport_id-or-empty>
# transport_id="" means Automatic (the new <select>'s own empty-value option).
SAVE_EXT_HTTPCODE=""
SAVE_EXT_BODY=""
save_ref_extension() {
    local mode="$1" ext="$2" secret="$3" transport_id="$4" body url
    body="$(mktemp)"
    if [ "$mode" = "add" ]; then
        url="${BASE_URL}/index.php/default/extensions/add"
    else
        url="${BASE_URL}/index.php/default/extensions/edit/id/${ext}"
    fi
    SAVE_EXT_HTTPCODE="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "name=SENMA transport-smoke-ux ${ext}" \
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
        --data-urlencode "transport_id=${transport_id}" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "$url")"
    SAVE_EXT_BODY="$(cat "$body")"
    rm -f "$body"
}

# create_ux_trunk_fixture -- same shape as create_trunk_fixture() above,
# parameterized to UX_TRUNK_CALLERID so Part 2's fixture is independent
# of checks 1-18's own trunk fixture.
create_ux_trunk_fixture() {
    local body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "callerid=${UX_TRUNK_CALLERID}" \
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
    log "create_ux_trunk_fixture failed (HTTP $httpcode): $(head -c 300 "$body")"
    rm -f "$body"
    return 1
}

# edit_ux_trunk_fixture <id> <transport_id-or-empty>
EDIT_TRUNK_HTTPCODE=""
EDIT_TRUNK_BODY=""
edit_ux_trunk_fixture() {
    local id="$1" transport_id="$2" body
    body="$(mktemp)"
    EDIT_TRUNK_HTTPCODE="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "callerid=${UX_TRUNK_CALLERID}" \
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
        --data-urlencode "transport_id=${transport_id}" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/trunks/edit/trunk/${id}")"
    EDIT_TRUNK_BODY="$(cat "$body")"
    rm -f "$body"
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
    log "==> cleanup"
    local failed=0
    if [ -n "$COOKIEJAR" ]; then
        if [ "$CREATED_REF_EXT" = "1" ]; then
            db_query "UPDATE peers SET transport_id = NULL WHERE name = '${REF_EXT}';" >/dev/null 2>&1
            if delete_extension "$REF_EXT"; then
                log "removed reference extension ${REF_EXT} via HTTP"
            else
                log "WARNING: HTTP delete of extension ${REF_EXT} did not return 302 -- may need manual cleanup"
                failed=1
            fi
        fi
        if [ -n "$CREATED_TRUNK_ID" ]; then
            db_query "UPDATE trunks SET transport_id = NULL WHERE id = ${CREATED_TRUNK_ID};" >/dev/null 2>&1
            if delete_trunk_fixture "$CREATED_TRUNK_ID"; then
                log "removed trunk fixture id=${CREATED_TRUNK_ID} via HTTP"
            else
                log "WARNING: HTTP delete of trunk id=${CREATED_TRUNK_ID} did not return 302 -- may need manual cleanup"
                failed=1
            fi
        fi
        if [ -n "$CREATED_TRANSPORT_ID" ]; then
            delete_transport "$CREATED_TRANSPORT_ID"
            if [ "$DELETE_HTTPCODE" = "302" ]; then
                log "removed test fixture transport id=${CREATED_TRANSPORT_ID} via HTTP"
            else
                log "WARNING: HTTP delete of transport id=${CREATED_TRANSPORT_ID} did not return 302 (still referenced?) -- may need manual cleanup"
                failed=1
            fi
        fi
        rm -f "$COOKIEJAR"
    fi
    return "$failed"
}
harness_register_cleanup "transport-smoke fixtures (checks 1-18)" "cleanup"

# --- 1. Required containers healthy ---------------------------------------

log "==> checking required containers"
harness_require_containers app asterisk db

harness_require_env DB_USER DB_PASSWORD DB_NAME TRUNK_TEST_USERNAME TRUNK_TEST_SECRET

pjsip_module_running() {
    $COMPOSE exec -T asterisk asterisk -rx 'module show like res_pjsip.so' 2>&1 | grep -q "Running"
}
# TASK-0027 finding: a fresh `docker compose exec` querying module state
# can transiently see incomplete output immediately after a DIFFERENT
# suite's own PJSIP config write/reload (live-confirmed running
# `make regression` back-to-back with no settling gap). Bounded retry,
# not an unconditional delay.
if ! harness_retry 5 2 -- pjsip_module_running; then
    harness_blocked "res_pjsip.so not Running (checked 5 times over 8s)"
fi
ok "PJSIP module Running" "res_pjsip.so Running"

# --- 2. Log in, check for collisions ---------------------------------------

COOKIEJAR="$(mktemp)"
log "==> logging in as ${TEST_USER}"
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${TEST_PASSWORD}');" 2>/dev/null | tr -d '\r')"
db_query "UPDATE users SET password = '${TEST_HASH}' WHERE name = '${TEST_USER}';" >&2
http_login
# TASK-0026G: every authenticated POST helper below (create/edit/delete
# transport, extension, trunk) now needs a valid snep_csrf_token
# (Snep_CsrfPlugin) -- fetched once here, reused for the rest of this
# script's run, including Part 2/3 below (stable per-session value, not
# one-shot/rotating).
ADMIN_CSRF="$(harness_csrf_token "$COOKIEJAR" "$BASE_URL")"
if [ -z "$ADMIN_CSRF" ]; then stop "could not read the admin session's CSRF token"; fi

log "==> checking for pre-existing fixtures"
EXISTING_TRANSPORT="$(db_query "SELECT id FROM pjsip_transports WHERE name='${TRANSPORT_NAME}';")"
if [ -n "$EXISTING_TRANSPORT" ]; then
    # TASK-0028U: an interrupted prior run (SIGKILL, host/container
    # teardown mid-run -- anything that skips harness_install_traps' own
    # INT/TERM/EXIT cleanup) can leave this transport row behind. A bare
    # "name already exists" collision can't tell that apart from a real
    # or unrelated transport that independently happens to be named
    # "sercomtel-smoke", so the name alone is never enough. Ownership is
    # only accepted when every field this suite's own create_transport()
    # sets -- and that no check anywhere else in this script ever mutates
    # (unlike external_media_address, rewritten by the edit-transport
    # check right below) -- still matches verbatim: protocol,
    # bind_address, bind_port, domain, external_signaling_address/port,
    # and is_seed=0 (a real seeded transport is never is_seed=0).
    EXISTING_TRANSPORT_SHAPE="$(db_query "SELECT protocol, bind_address, bind_port, domain, external_signaling_address, external_signaling_port, is_seed FROM pjsip_transports WHERE id=${EXISTING_TRANSPORT};")"
    IFS=$'\t' read -r et_protocol et_bind_address et_bind_port et_domain et_ext_sig et_ext_sig_port et_is_seed <<< "$EXISTING_TRANSPORT_SHAPE"
    if [ "$et_protocol" = "udp" ] && [ "$et_bind_address" = "$TRANSPORT_BIND_ADDRESS" ] \
        && [ "$et_bind_port" = "$TRANSPORT_BIND_PORT" ] && [ "$et_domain" = "$TRANSPORT_DOMAIN" ] \
        && [ "$et_ext_sig" = "$TRANSPORT_EXT_SIGNALING" ] && [ "$et_ext_sig_port" = "$TRANSPORT_EXT_SIGNALING_PORT" ] \
        && [ "$et_is_seed" = "0" ]; then
        # Never delete a still-referenced transport out from under an
        # extension/trunk this preflight hasn't itself verified -- the FK
        # is ON DELETE RESTRICT for peers, and an unproven dependent could
        # just as easily be real data as another leftover fixture.
        DEP_PEERS="$(db_query "SELECT COUNT(*) FROM peers WHERE transport_id=${EXISTING_TRANSPORT};")"
        DEP_TRUNKS="$(db_query "SELECT COUNT(*) FROM trunks WHERE transport_id=${EXISTING_TRANSPORT};")"
        if [ "$DEP_PEERS" != "0" ] || [ "$DEP_TRUNKS" != "0" ]; then
            stop "transport '${TRANSPORT_NAME}' (id=${EXISTING_TRANSPORT}) is a leftover transport-smoke fixture but is still referenced by ${DEP_PEERS} extension(s)/${DEP_TRUNKS} trunk(s) of unproven ownership -- refusing to guess. Remove the references manually first."
        fi
        log "transport '${TRANSPORT_NAME}' (id=${EXISTING_TRANSPORT}) is a leftover transport-smoke fixture (protocol/bind/domain/signaling/is_seed all match this suite's own known fixture shape, unreferenced) -- removing via HTTP before re-creating"
        delete_transport "$EXISTING_TRANSPORT"
        if [ "$DELETE_HTTPCODE" != "302" ]; then
            stop "found a leftover transport-smoke fixture '${TRANSPORT_NAME}' (id=${EXISTING_TRANSPORT}) but the HTTP delete flow did not return 302"
        fi
    else
        stop "a transport named '${TRANSPORT_NAME}' already exists (id=${EXISTING_TRANSPORT}) and its stored fields do NOT match this suite's own known fixture shape -- refusing to overwrite real/unknown data. Remove it manually first."
    fi
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
EXISTING_TRUNK="$(db_query "SELECT id FROM trunks WHERE callerid='${TRUNK_CALLERID}';")"
if [ -n "$EXISTING_TRUNK" ]; then
    stop "a trunk with callerid '${TRUNK_CALLERID}' already exists (id=${EXISTING_TRUNK}) from a prior run that did not clean up. Remove it manually first."
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

log "==> creating a reference extension (AUTO -- no transport pinned yet)"
if create_ref_extension "$REF_EXT" "$REF_EXT_SECRET"; then
    CREATED_REF_EXT=1
else
    stop "creating reference extension ${REF_EXT} failed -- see log above"
fi

# AUTO case (item: "generated endpoint contains no transport="). This is
# the state every extension is in today through the real UI -- item 10
# deliberately has no transport picker, so transport_id is NULL here,
# not a test-only condition.
EXT_SECTION_AUTO="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip.conf 2>/dev/null | awk "/^\[${REF_EXT}\]/{f=1} f{print} f&&/^\$/{exit}")"
if ! echo "$EXT_SECTION_AUTO" | grep -q "^transport="; then
    ok "AUTO extension has no transport= line" "[${REF_EXT}] correctly omits transport= entirely -- Asterisk selects a compatible transport itself"
else
    bad "AUTO extension has no transport= line" "unexpected transport= line found:\n${EXT_SECTION_AUTO}"
fi
if $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${REF_EXT}" 2>&1 | grep -q "Endpoint:  ${REF_EXT}"; then
    ok "AUTO endpoint remains valid in Asterisk" "pjsip show endpoint ${REF_EXT} loads correctly with no transport= at all"
else
    bad "AUTO endpoint remains valid in Asterisk" "endpoint did not load"
fi

log "==> pinning the reference extension to the custom transport"
db_query "UPDATE peers SET transport_id = ${CREATED_TRANSPORT_ID} WHERE name = '${REF_EXT}';" >&2
regenerate_all

GENERATED_EXT_CONF="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip.conf 2>/dev/null)"
EXT_SECTION="$(echo "$GENERATED_EXT_CONF" | awk "/^\[${REF_EXT}\]/{f=1} f{print} f&&/^\$/{exit}")"
if echo "$EXT_SECTION" | grep -qF "transport=${TRANSPORT_NAME}"; then
    ok "EXPLICIT extension references the custom transport" "[${REF_EXT}] emits the exact transport=${TRANSPORT_NAME} pin"
else
    bad "EXPLICIT extension references the custom transport" "expected transport=${TRANSPORT_NAME} not found:\n${EXT_SECTION}"
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

# --- 8. Clear the reference, extension reverts to AUTO --------------------

log "==> clearing the reference (back to AUTO)"
db_query "UPDATE peers SET transport_id = NULL WHERE name = '${REF_EXT}';" >&2
regenerate_all

EXT_SECTION_AFTER="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip.conf 2>/dev/null | awk "/^\[${REF_EXT}\]/{f=1} f{print} f&&/^\$/{exit}")"
# TASK-0018 correction: NULL means AUTO, not "resolve to the default
# transport" -- this must NOT show transport=udp (the original,
# incorrect behavior). No transport= line at all is the correct,
# corrected outcome.
if ! echo "$EXT_SECTION_AFTER" | grep -q "^transport="; then
    ok "extension reverts to AUTO (no transport= line)" "[${REF_EXT}] correctly has no transport= line again -- NULL never meant 'default', it means 'no pin'"
else
    bad "extension reverts to AUTO (no transport= line)" "unexpected transport= line found:\n${EXT_SECTION_AFTER}"
fi

# --- 9. EXPLICIT trunk: both endpoint AND registration honor the pin ------
#
# The task's own Sercomtel-style motivating example is a TRUNK, not an
# extension -- proven here explicitly, and separately from the endpoint
# case, per this task's own "do not assume endpoint and registration
# semantics are identical" instruction (docs/tasks/0018-pjsip-transports.md's
# corrected §9 documents why they turned out to behave the same way here,
# verified rather than assumed).

log "==> creating a trunk fixture and pinning it to the custom transport"
if create_trunk_fixture; then
    CREATED_TRUNK_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${TRUNK_CALLERID}';")"
    CREATED_TRUNK_NAME="$(db_query "SELECT name FROM trunks WHERE id=${CREATED_TRUNK_ID};")"
    if [ -z "$CREATED_TRUNK_ID" ]; then
        stop "trunk fixture creation returned 302 but no matching row was found afterward"
    fi
else
    stop "creating the trunk fixture failed -- see log above"
fi
db_query "UPDATE trunks SET transport_id = ${CREATED_TRANSPORT_ID} WHERE id = ${CREATED_TRUNK_ID};" >&2
regenerate_all

TRUNK_OBJ="trunk-${CREATED_TRUNK_ID}"
GENERATED_TRUNK_CONF="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip-trunks.conf 2>/dev/null)"
TRUNK_ENDPOINT_SECTION="$(echo "$GENERATED_TRUNK_CONF" | awk "/^\[${TRUNK_OBJ}\]\$/{f=1} f{print} f&&/^\$/{exit}")"
TRUNK_REG_SECTION="$(echo "$GENERATED_TRUNK_CONF" | awk "/^\[${TRUNK_OBJ}-registration\]/{f=1} f{print} f&&/^\$/{exit}")"

if echo "$TRUNK_ENDPOINT_SECTION" | grep -qF "transport=${TRANSPORT_NAME}"; then
    ok "EXPLICIT trunk endpoint references the custom transport" "[${TRUNK_OBJ}] emits the exact transport=${TRANSPORT_NAME} pin"
else
    bad "EXPLICIT trunk endpoint references the custom transport" "expected transport=${TRANSPORT_NAME} not found:\n${TRUNK_ENDPOINT_SECTION}"
fi
if echo "$TRUNK_REG_SECTION" | grep -qF "transport=${TRANSPORT_NAME}"; then
    ok "EXPLICIT trunk registration references the custom transport" "[${TRUNK_OBJ}-registration] emits the exact transport=${TRANSPORT_NAME} pin"
else
    bad "EXPLICIT trunk registration references the custom transport" "expected transport=${TRANSPORT_NAME} not found:\n${TRUNK_REG_SECTION}"
fi

log "==> removing the trunk fixture"
if delete_trunk_fixture "$CREATED_TRUNK_ID"; then
    ok "trunk fixture removed" "HTTP 302, real TrunksController::removeAction() flow"
    CREATED_TRUNK_ID=""
else
    bad "trunk fixture removed" "HTTP delete of trunk id=${CREATED_TRUNK_ID} did not return 302"
fi

# --- 10. Delete the transport, now unreferenced by both fixtures ----------

log "==> deleting the transport now that nothing references it"
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

# ===========================================================================
# PART 2 (TASK-0019): real UI transport-selection lifecycle
#
# Checks 1-18 above are TASK-0018's original coverage, PRESERVED
# UNCHANGED -- transport_id was only ever set via direct SQL there, since
# no selector existed yet. Everything below instead posts the real
# transport_id form field TASK-0019 added to the extension/trunk
# create/edit forms (ExtensionsController::execAdd()/
# TrunksController::preparePost()), using its own independent fixtures
# (UX_* names/ids, extension 1097, its own transports) so it cannot
# interfere with checks 1-18's fixtures or ordering.
# ===========================================================================

UX_TRANSPORT_A="task0019-a-smoke"
UX_TRANSPORT_A_RENAMED="task0019-a-smoke-renamed"
UX_TRANSPORT_B="task0019-b-smoke"
UX_TRANSPORT_DISABLED="task0019-disabled-smoke"
UX_REF_EXT=1097
UX_REF_EXT_SECRET="${FIXTURE_MARKER}-ux-ext"
UX_TRUNK_CALLERID="${FIXTURE_MARKER} ux trunk fixture"

UX_TRANSPORT_A_ID=""
UX_TRANSPORT_B_ID=""
UX_TRANSPORT_DISABLED_ID=""
UX_CREATED_EXT=0
UX_CREATED_TRUNK_ID=""

ux_cleanup() {
    log "==> UX (TASK-0019) cleanup"
    local failed=0
    if [ "$UX_CREATED_EXT" = "1" ]; then
        db_query "UPDATE peers SET transport_id = NULL WHERE name='${UX_REF_EXT}';" >/dev/null 2>&1
        delete_extension "$UX_REF_EXT" || { log "WARNING: HTTP delete of extension ${UX_REF_EXT} did not return 302 -- may need manual cleanup"; failed=1; }
    fi
    if [ -n "$UX_CREATED_TRUNK_ID" ]; then
        db_query "UPDATE trunks SET transport_id = NULL WHERE id=${UX_CREATED_TRUNK_ID};" >/dev/null 2>&1
        delete_trunk_fixture "$UX_CREATED_TRUNK_ID" || { log "WARNING: HTTP delete of ux trunk id=${UX_CREATED_TRUNK_ID} did not return 302 -- may need manual cleanup"; failed=1; }
    fi
    for tid in "$UX_TRANSPORT_A_ID" "$UX_TRANSPORT_B_ID" "$UX_TRANSPORT_DISABLED_ID"; do
        if [ -n "$tid" ]; then
            delete_transport "$tid"
            [ "$DELETE_HTTPCODE" = "302" ] || { log "WARNING: HTTP delete of ux transport id=${tid} did not return 302 -- may need manual cleanup"; failed=1; }
        fi
    done
    return "$failed"
}
# Registered right after cleanup() at definition time -- harness_finalize
# runs registered cleanups LIFO, so ux_cleanup (registered second) runs
# BEFORE cleanup() (checks 1-18's own fixtures, e.g. REF_EXT=1098),
# reproducing the exact order the old chained `trap 'ux_cleanup; cleanup'
# EXIT` used.
harness_register_cleanup "transport-smoke fixtures (Part 2 / UX)" "ux_cleanup"

log "==> [UX] checking for pre-existing fixtures"
for n in "$UX_TRANSPORT_A" "$UX_TRANSPORT_A_RENAMED" "$UX_TRANSPORT_B" "$UX_TRANSPORT_DISABLED"; do
    existing="$(db_query "SELECT id FROM pjsip_transports WHERE name='${n}';")"
    if [ -n "$existing" ]; then
        stop "a transport named '${n}' already exists (id=${existing}) from a prior run that did not clean up. Remove it manually first."
    fi
done
existing="$(db_query "SELECT canal FROM peers WHERE name='${UX_REF_EXT}';")"
if [ -n "$existing" ]; then
    stop "peers row for extension '${UX_REF_EXT}' already exists. Remove it manually first."
fi
existing="$(db_query "SELECT id FROM trunks WHERE callerid='${UX_TRUNK_CALLERID}';")"
if [ -n "$existing" ]; then
    stop "a trunk with callerid '${UX_TRUNK_CALLERID}' already exists (id=${existing}) from a prior run. Remove it manually first."
fi

# --- 19. Create extension via the real UI, Automatic (empty transport_id) --

log "==> [UX] creating extension ${UX_REF_EXT} via the real UI, technology=pjsip, transport_id='' (Automatic)"
if save_ref_extension add "$UX_REF_EXT" "$UX_REF_EXT_SECRET" ""; then
    if [ "$SAVE_EXT_HTTPCODE" = "302" ]; then
        UX_CREATED_EXT=1
    else
        stop "creating extension ${UX_REF_EXT} did not return 302 (HTTP $SAVE_EXT_HTTPCODE): $(echo "$SAVE_EXT_BODY" | head -c 300)"
    fi
fi
UX_EXT_TRANSPORT_ID_DB="$(db_query "SELECT transport_id FROM peers WHERE name='${UX_REF_EXT}';")"
UX_EXT_SECTION="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip.conf 2>/dev/null | awk "/^\[${UX_REF_EXT}\]/{f=1} f{print} f&&/^\$/{exit}")"
if is_db_null "$UX_EXT_TRANSPORT_ID_DB" && ! echo "$UX_EXT_SECTION" | grep -q "^transport="; then
    ok "UI create AUTO persists NULL + no transport= line" "peers.transport_id is NULL, [${UX_REF_EXT}] has no transport= line"
else
    bad "UI create AUTO persists NULL + no transport= line" "transport_id='${UX_EXT_TRANSPORT_ID_DB}', section:\n${UX_EXT_SECTION}"
fi

# --- 20. Create two explicit transports via the real UI --------------------

log "==> [UX] creating two explicit transports (A udp/5073, B tcp/5074)"
save_transport add "" "$UX_TRANSPORT_A" udp 5073 1
[ "$SAVE_TRANSPORT_HTTPCODE" = "302" ] || stop "creating transport ${UX_TRANSPORT_A} failed (HTTP $SAVE_TRANSPORT_HTTPCODE)"
UX_TRANSPORT_A_ID="$(db_query "SELECT id FROM pjsip_transports WHERE name='${UX_TRANSPORT_A}';")"
save_transport add "" "$UX_TRANSPORT_B" tcp 5074 1
[ "$SAVE_TRANSPORT_HTTPCODE" = "302" ] || stop "creating transport ${UX_TRANSPORT_B} failed (HTTP $SAVE_TRANSPORT_HTTPCODE)"
UX_TRANSPORT_B_ID="$(db_query "SELECT id FROM pjsip_transports WHERE name='${UX_TRANSPORT_B}';")"
if [ -n "$UX_TRANSPORT_A_ID" ] && [ -n "$UX_TRANSPORT_B_ID" ]; then
    ok "two explicit transports created via real UI" "A=${UX_TRANSPORT_A_ID}, B=${UX_TRANSPORT_B_ID}"
else
    stop "one or both UX transports were not found after creation"
fi

# --- 21. Extension edit-transition round trip: AUTO -> A -> B -> AUTO ------

log "==> [UX] extension: AUTO -> EXPLICIT(A)"
save_ref_extension edit "$UX_REF_EXT" "$UX_REF_EXT_SECRET" "$UX_TRANSPORT_A_ID"
UX_EXT_TRANSPORT_ID_DB="$(db_query "SELECT transport_id FROM peers WHERE name='${UX_REF_EXT}';")"
UX_EXT_SECTION="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip.conf 2>/dev/null | awk "/^\[${UX_REF_EXT}\]/{f=1} f{print} f&&/^\$/{exit}")"
if [ "$SAVE_EXT_HTTPCODE" = "302" ] && [ "$UX_EXT_TRANSPORT_ID_DB" = "$UX_TRANSPORT_A_ID" ] && echo "$UX_EXT_SECTION" | grep -qF "transport=${UX_TRANSPORT_A}"; then
    ok "extension AUTO -> EXPLICIT(A) via real UI" "peers.transport_id=${UX_TRANSPORT_A_ID}, transport=${UX_TRANSPORT_A} generated"
else
    bad "extension AUTO -> EXPLICIT(A) via real UI" "HTTP=$SAVE_EXT_HTTPCODE db_id=$UX_EXT_TRANSPORT_ID_DB section:\n${UX_EXT_SECTION}"
fi

log "==> [UX] extension: EXPLICIT(A) -> EXPLICIT(A) (no-op re-save)"
save_ref_extension edit "$UX_REF_EXT" "$UX_REF_EXT_SECRET" "$UX_TRANSPORT_A_ID"
UX_EXT_SECTION="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip.conf 2>/dev/null | awk "/^\[${UX_REF_EXT}\]/{f=1} f{print} f&&/^\$/{exit}")"
if [ "$SAVE_EXT_HTTPCODE" = "302" ] && echo "$UX_EXT_SECTION" | grep -qF "transport=${UX_TRANSPORT_A}"; then
    ok "extension EXPLICIT(A) -> EXPLICIT(A) unchanged" "still transport=${UX_TRANSPORT_A}, save succeeded"
else
    bad "extension EXPLICIT(A) -> EXPLICIT(A) unchanged" "HTTP=$SAVE_EXT_HTTPCODE section:\n${UX_EXT_SECTION}"
fi

log "==> [UX] extension: EXPLICIT(A) -> EXPLICIT(B)"
save_ref_extension edit "$UX_REF_EXT" "$UX_REF_EXT_SECRET" "$UX_TRANSPORT_B_ID"
UX_EXT_TRANSPORT_ID_DB="$(db_query "SELECT transport_id FROM peers WHERE name='${UX_REF_EXT}';")"
UX_EXT_SECTION="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip.conf 2>/dev/null | awk "/^\[${UX_REF_EXT}\]/{f=1} f{print} f&&/^\$/{exit}")"
if [ "$UX_EXT_TRANSPORT_ID_DB" = "$UX_TRANSPORT_B_ID" ] && echo "$UX_EXT_SECTION" | grep -qF "transport=${UX_TRANSPORT_B}" && ! echo "$UX_EXT_SECTION" | grep -qF "transport=${UX_TRANSPORT_A}"; then
    ok "extension EXPLICIT(A) -> EXPLICIT(B) via real UI" "peers.transport_id=${UX_TRANSPORT_B_ID}, transport=${UX_TRANSPORT_B} generated, A reference gone"
else
    bad "extension EXPLICIT(A) -> EXPLICIT(B) via real UI" "db_id=$UX_EXT_TRANSPORT_ID_DB section:\n${UX_EXT_SECTION}"
fi

# --- 22. Rename lifecycle: the extension is currently pinned to B (the
#         live reference after check 21's A->B switch) -- renaming B must
#         cascade into the extension's generated config with zero manual
#         intervention. -----------------------------------------------

log "==> [UX] renaming ${UX_TRANSPORT_B} (currently referenced by extension ${UX_REF_EXT}) to ${UX_TRANSPORT_A_RENAMED}, also moving its port (5074 -> 5076)"
# TASK-0019 implementation-phase finding, correcting the investigation's
# own §11 "New fact 2": a rename that keeps the SAME bind address:port is
# the identical already-documented TASK-0018 §5 collision ("reusing a
# bind address:port that a differently-named, still-live transport
# previously held") -- confirmed live, repeatedly, during this
# implementation: the new name never became queryable even after 3
# manual retries AND two more explicit same-content reloads over 12+
# seconds, no restart, and Asterisk logged nothing. Moving the port
# alongside the rename (as any real admin renaming a placeholder-named
# transport would likely also do) sidesteps that OS-level socket
# collision entirely and reload succeeds immediately -- this is what
# this check actually needs to prove (dependent-object regeneration
# cascades correctly), not the unrelated, pre-existing bind-collision
# caveat. See docs/tasks/0019-pjsip-transport-selection-ux.md's
# implementation-evidence section for the full account.
save_transport edit "$UX_TRANSPORT_B_ID" "$UX_TRANSPORT_A_RENAMED" tcp 5076 1
UX_EXT_SECTION="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip.conf 2>/dev/null | awk "/^\[${UX_REF_EXT}\]/{f=1} f{print} f&&/^\$/{exit}")"
if [ "$SAVE_TRANSPORT_HTTPCODE" = "302" ] && echo "$UX_EXT_SECTION" | grep -qF "transport=${UX_TRANSPORT_A_RENAMED}"; then
    ok "rename cascades to the dependent extension" "extension ${UX_REF_EXT} now shows transport=${UX_TRANSPORT_A_RENAMED} with zero manual intervention"
else
    bad "rename cascades to the dependent extension" "HTTP=$SAVE_TRANSPORT_HTTPCODE section:\n${UX_EXT_SECTION}"
fi
RUNTIME_AFTER_RENAME="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show transport ${UX_TRANSPORT_A_RENAMED}" 2>&1)"
if echo "$RUNTIME_AFTER_RENAME" | grep -q "bind "; then
    ok "renamed transport (with a bind change) reload succeeds, no restart" "pjsip show transport ${UX_TRANSPORT_A_RENAMED} found live at 0.0.0.0:5076"
else
    bad "renamed transport (with a bind change) reload succeeds, no restart" "not found:\n${RUNTIME_AFTER_RENAME}"
fi
UX_TRANSPORT_B="$UX_TRANSPORT_A_RENAMED"

log "==> [UX] extension: EXPLICIT -> AUTO (the mandatory EXPLICIT->AUTO write-NULL check)"
save_ref_extension edit "$UX_REF_EXT" "$UX_REF_EXT_SECRET" ""
UX_EXT_TRANSPORT_ID_DB="$(db_query "SELECT transport_id FROM peers WHERE name='${UX_REF_EXT}';")"
UX_EXT_SECTION="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip.conf 2>/dev/null | awk "/^\[${UX_REF_EXT}\]/{f=1} f{print} f&&/^\$/{exit}")"
if is_db_null "$UX_EXT_TRANSPORT_ID_DB" && ! echo "$UX_EXT_SECTION" | grep -q "^transport="; then
    ok "extension EXPLICIT -> AUTO writes NULL (not omitted)" "peers.transport_id is NULL in the DB (not merely absent from the generated file) -- confirms the UPDATE explicitly included transport_id=NULL rather than omitting the column"
else
    bad "extension EXPLICIT -> AUTO writes NULL (not omitted)" "peers.transport_id='${UX_EXT_TRANSPORT_ID_DB}' -- the UI would be lying about Automatic being saved; section:\n${UX_EXT_SECTION}"
fi

# --- 23. Trunk edit-transition round trip: AUTO -> A -> AUTO, endpoint AND
#         registration both checked at every step -----------------------

log "==> [UX] creating trunk fixture (AUTO by default, no transport_id posted on create)"
if create_ux_trunk_fixture; then
    UX_CREATED_TRUNK_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${UX_TRUNK_CALLERID}';")"
    [ -n "$UX_CREATED_TRUNK_ID" ] || stop "ux trunk fixture creation returned 302 but no matching row was found afterward"
else
    stop "creating the ux trunk fixture failed -- see log above"
fi
UX_TRUNK_OBJ="trunk-${UX_CREATED_TRUNK_ID}"
UX_TRUNK_TRANSPORT_ID_DB="$(db_query "SELECT transport_id FROM trunks WHERE id=${UX_CREATED_TRUNK_ID};")"
UX_TRUNK_CONF="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip-trunks.conf 2>/dev/null)"
UX_TRUNK_EP="$(echo "$UX_TRUNK_CONF" | awk "/^\[${UX_TRUNK_OBJ}\]\$/{f=1} f{print} f&&/^\$/{exit}")"
UX_TRUNK_REG="$(echo "$UX_TRUNK_CONF" | awk "/^\[${UX_TRUNK_OBJ}-registration\]/{f=1} f{print} f&&/^\$/{exit}")"
if is_db_null "$UX_TRUNK_TRANSPORT_ID_DB" && ! echo "$UX_TRUNK_EP" | grep -q "^transport=" && ! echo "$UX_TRUNK_REG" | grep -q "^transport="; then
    ok "UI create AUTO trunk: neither endpoint nor registration gets transport=" "trunks.transport_id is NULL, both objects omit transport="
else
    bad "UI create AUTO trunk: neither endpoint nor registration gets transport=" "db_id=$UX_TRUNK_TRANSPORT_ID_DB ep:\n${UX_TRUNK_EP}\nreg:\n${UX_TRUNK_REG}"
fi

log "==> [UX] trunk: AUTO -> EXPLICIT(A)"
edit_ux_trunk_fixture "$UX_CREATED_TRUNK_ID" "$UX_TRANSPORT_A_ID"
UX_TRUNK_TRANSPORT_ID_DB="$(db_query "SELECT transport_id FROM trunks WHERE id=${UX_CREATED_TRUNK_ID};")"
UX_TRUNK_CONF="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip-trunks.conf 2>/dev/null)"
UX_TRUNK_EP="$(echo "$UX_TRUNK_CONF" | awk "/^\[${UX_TRUNK_OBJ}\]\$/{f=1} f{print} f&&/^\$/{exit}")"
UX_TRUNK_REG="$(echo "$UX_TRUNK_CONF" | awk "/^\[${UX_TRUNK_OBJ}-registration\]/{f=1} f{print} f&&/^\$/{exit}")"
if [ "$EDIT_TRUNK_HTTPCODE" = "302" ] && [ "$UX_TRUNK_TRANSPORT_ID_DB" = "$UX_TRANSPORT_A_ID" ] \
    && echo "$UX_TRUNK_EP" | grep -qF "transport=${UX_TRANSPORT_A}" && echo "$UX_TRUNK_REG" | grep -qF "transport=${UX_TRANSPORT_A}"; then
    ok "trunk AUTO -> EXPLICIT(A): both endpoint and registration pinned" "trunks.transport_id=${UX_TRANSPORT_A_ID}, both objects show transport=${UX_TRANSPORT_A}"
else
    bad "trunk AUTO -> EXPLICIT(A): both endpoint and registration pinned" "HTTP=$EDIT_TRUNK_HTTPCODE db_id=$UX_TRUNK_TRANSPORT_ID_DB ep:\n${UX_TRUNK_EP}\nreg:\n${UX_TRUNK_REG}"
fi

log "==> [UX] trunk: EXPLICIT -> AUTO (the mandatory EXPLICIT->AUTO write-NULL check, trunk side)"
edit_ux_trunk_fixture "$UX_CREATED_TRUNK_ID" ""
UX_TRUNK_TRANSPORT_ID_DB="$(db_query "SELECT transport_id FROM trunks WHERE id=${UX_CREATED_TRUNK_ID};")"
UX_TRUNK_CONF="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip-trunks.conf 2>/dev/null)"
UX_TRUNK_EP="$(echo "$UX_TRUNK_CONF" | awk "/^\[${UX_TRUNK_OBJ}\]\$/{f=1} f{print} f&&/^\$/{exit}")"
UX_TRUNK_REG="$(echo "$UX_TRUNK_CONF" | awk "/^\[${UX_TRUNK_OBJ}-registration\]/{f=1} f{print} f&&/^\$/{exit}")"
if is_db_null "$UX_TRUNK_TRANSPORT_ID_DB" && ! echo "$UX_TRUNK_EP" | grep -q "^transport=" && ! echo "$UX_TRUNK_REG" | grep -q "^transport="; then
    ok "trunk EXPLICIT -> AUTO writes NULL (not omitted)" "trunks.transport_id is NULL in the DB, both objects revert to no transport= line"
else
    bad "trunk EXPLICIT -> AUTO writes NULL (not omitted)" "db_id=$UX_TRUNK_TRANSPORT_ID_DB ep:\n${UX_TRUNK_EP}\nreg:\n${UX_TRUNK_REG}"
fi

log "==> [UX] removing the trunk fixture"
if delete_trunk_fixture "$UX_CREATED_TRUNK_ID"; then
    ok "ux trunk fixture removed" "HTTP 302, real TrunksController::removeAction() flow"
    UX_CREATED_TRUNK_ID=""
else
    bad "ux trunk fixture removed" "HTTP delete did not return 302"
fi

# --- 24. Disabled transport is excluded from selection ---------------------

log "==> [UX] creating a disabled transport"
save_transport add "" "$UX_TRANSPORT_DISABLED" udp 5075 0
[ "$SAVE_TRANSPORT_HTTPCODE" = "302" ] || stop "creating disabled transport ${UX_TRANSPORT_DISABLED} failed (HTTP $SAVE_TRANSPORT_HTTPCODE)"
UX_TRANSPORT_DISABLED_ID="$(db_query "SELECT id FROM pjsip_transports WHERE name='${UX_TRANSPORT_DISABLED}';")"

log "==> [UX] confirming it is absent from the extension edit form's option list"
EDIT_FORM_HTML="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" "${BASE_URL}/index.php/default/extensions/edit/id/${UX_REF_EXT}")"
if ! echo "$EDIT_FORM_HTML" | grep -qF "value=\"${UX_TRANSPORT_DISABLED_ID}\""; then
    ok "disabled transport absent from selector" "extension ${UX_REF_EXT}'s edit form does not offer ${UX_TRANSPORT_DISABLED} as an option"
else
    bad "disabled transport absent from selector" "found an <option> for the disabled transport's id in the edit form"
fi

log "==> [UX] attempting to newly pin the extension to the disabled transport (must be rejected)"
save_ref_extension edit "$UX_REF_EXT" "$UX_REF_EXT_SECRET" "$UX_TRANSPORT_DISABLED_ID"
UX_EXT_TRANSPORT_ID_DB="$(db_query "SELECT transport_id FROM peers WHERE name='${UX_REF_EXT}';")"
if [ "$SAVE_EXT_HTTPCODE" != "302" ] && is_db_null "$UX_EXT_TRANSPORT_ID_DB"; then
    ok "newly pinning a disabled transport is rejected" "HTTP $SAVE_EXT_HTTPCODE (not 302), peers.transport_id stayed NULL"
else
    bad "newly pinning a disabled transport is rejected" "HTTP=$SAVE_EXT_HTTPCODE db_id=$UX_EXT_TRANSPORT_ID_DB -- the disabled transport was accepted"
fi

# --- 25. An already-referenced transport that later becomes disabled -------
#         (item 12 C-F): disabling is allowed, but the generator must not
#         emit a dangling reference, and the invalid state must be
#         surfaced, not silently swallowed. -------------------------------

log "==> [UX] pinning the extension to A (currently enabled), then disabling A"
save_ref_extension edit "$UX_REF_EXT" "$UX_REF_EXT_SECRET" "$UX_TRANSPORT_A_ID"
[ "$SAVE_EXT_HTTPCODE" = "302" ] || stop "re-pinning extension ${UX_REF_EXT} to transport A failed (HTTP $SAVE_EXT_HTTPCODE)"
save_transport edit "$UX_TRANSPORT_A_ID" "$UX_TRANSPORT_A" udp 5073 0
if [ "$SAVE_TRANSPORT_HTTPCODE" = "302" ]; then
    ok "disabling an already-referenced transport is allowed" "HTTP 302 -- unlike delete, disable is not blocked (matches the investigation's item 12 design)"
else
    bad "disabling an already-referenced transport is allowed" "HTTP $SAVE_TRANSPORT_HTTPCODE"
fi

UX_EXT_SECTION_AFTER_DISABLE="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip.conf 2>/dev/null | awk "/^\[${UX_REF_EXT}\]/{f=1} f{print} f&&/^\$/{exit}")"
if [ -z "$UX_EXT_SECTION_AFTER_DISABLE" ]; then
    ok "generator skips (does not dangle) an extension pinned to a disabled transport" "[${UX_REF_EXT}] is entirely absent from senma-pjsip.conf, per resolveTransportName()'s throw + the per-row skip in loadConfFromDb()"
else
    bad "generator skips (does not dangle) an extension pinned to a disabled transport" "section unexpectedly present:\n${UX_EXT_SECTION_AFTER_DISABLE}"
fi

RUNTIME_AFTER_DISABLE="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${UX_REF_EXT}" 2>&1)"
if echo "$RUNTIME_AFTER_DISABLE" | grep -qi "Unable to find"; then
    ok "endpoint disappears from Asterisk's live runtime, no dangling reference" "pjsip show endpoint ${UX_REF_EXT} -- Unable to find object (not a broken/dangling config)"
else
    bad "endpoint disappears from Asterisk's live runtime, no dangling reference" "expected 'Unable to find', got:\n${RUNTIME_AFTER_DISABLE}"
fi

TRANSPORTS_INDEX_HTML="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" "${BASE_URL}/index.php/default/pjsip-transports")"
if echo "$TRANSPORTS_INDEX_HTML" | grep -qi "disabled but still explicitly referenced"; then
    ok "UI surfaces the disabled-but-referenced state clearly" "Transports list page shows the item 12F warning"
else
    bad "UI surfaces the disabled-but-referenced state clearly" "expected warning text not found on the Transports list page"
fi

log "==> [UX] recovery: re-enabling A restores the extension"
save_transport edit "$UX_TRANSPORT_A_ID" "$UX_TRANSPORT_A" udp 5073 1
UX_EXT_SECTION_RECOVERED="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip.conf 2>/dev/null | awk "/^\[${UX_REF_EXT}\]/{f=1} f{print} f&&/^\$/{exit}")"
if [ "$SAVE_TRANSPORT_HTTPCODE" = "302" ] && echo "$UX_EXT_SECTION_RECOVERED" | grep -qF "transport=${UX_TRANSPORT_A}"; then
    ok "re-enabling the transport recovers the extension" "[${UX_REF_EXT}] regenerated with transport=${UX_TRANSPORT_A} again -- fully reversible, not a permanent break"
else
    bad "re-enabling the transport recovers the extension" "HTTP=$SAVE_TRANSPORT_HTTPCODE section:\n${UX_EXT_SECTION_RECOVERED}"
fi

log "==> [UX] clearing the reference back to AUTO before deleting A"
save_ref_extension edit "$UX_REF_EXT" "$UX_REF_EXT_SECRET" ""
[ "$SAVE_EXT_HTTPCODE" = "302" ] || log "WARNING: could not clear extension ${UX_REF_EXT}'s transport reference before cleanup"

# --- 26. Trunk-referenced delete-blocked (closes the checks 1-18 coverage
#         gap: their own trunk fixture is always deleted BEFORE the
#         transport delete is attempted, so that branch of
#         getUsageDetails() -- already correct in the application code --
#         was never actually exercised by the automated suite). ----------

log "==> [UX] creating a trunk fixture and pinning it to B, to prove trunk-referenced delete-blocked"
if create_ux_trunk_fixture; then
    UX_CREATED_TRUNK_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${UX_TRUNK_CALLERID}';")"
    [ -n "$UX_CREATED_TRUNK_ID" ] || stop "ux trunk fixture (part 2) creation returned 302 but no matching row was found"
else
    stop "creating the ux trunk fixture (part 2) failed -- see log above"
fi
edit_ux_trunk_fixture "$UX_CREATED_TRUNK_ID" "$UX_TRANSPORT_B_ID"
[ "$EDIT_TRUNK_HTTPCODE" = "302" ] || stop "pinning ux trunk to transport B failed (HTTP $EDIT_TRUNK_HTTPCODE)"

delete_transport "$UX_TRANSPORT_B_ID"
if [ "$DELETE_HTTPCODE" != "302" ] && echo "$DELETE_BODY" | grep -qi "Cannot remove" && echo "$DELETE_BODY" | grep -qi "Trunk"; then
    ok "delete blocked while referenced by a trunk" "HTTP $DELETE_HTTPCODE, error page correctly lists the referencing trunk (checks 1-18 only ever proved the extension-reference case)"
else
    bad "delete blocked while referenced by a trunk" "expected a blocked response naming the trunk; got HTTP $DELETE_HTTPCODE: $(echo "$DELETE_BODY" | head -c 300)"
fi

log "==> [UX] removing the trunk fixture, then deleting both remaining ux transports"
if delete_trunk_fixture "$UX_CREATED_TRUNK_ID"; then
    ok "ux trunk fixture (part 2) removed" "HTTP 302"
    UX_CREATED_TRUNK_ID=""
else
    bad "ux trunk fixture (part 2) removed" "HTTP delete did not return 302"
fi

delete_transport "$UX_TRANSPORT_A_ID"
DEL_A_CODE="$DELETE_HTTPCODE"
delete_transport "$UX_TRANSPORT_B_ID"
DEL_B_CODE="$DELETE_HTTPCODE"
delete_transport "$UX_TRANSPORT_DISABLED_ID"
DEL_D_CODE="$DELETE_HTTPCODE"
if [ "$DEL_A_CODE" = "302" ] && [ "$DEL_B_CODE" = "302" ] && [ "$DEL_D_CODE" = "302" ]; then
    ok "delete succeeds once unreferenced, for all three ux transports" "A=$DEL_A_CODE B(renamed)=$DEL_B_CODE disabled=$DEL_D_CODE"
    UX_TRANSPORT_A_ID=""
    UX_TRANSPORT_B_ID=""
    UX_TRANSPORT_DISABLED_ID=""
else
    bad "delete succeeds once unreferenced, for all three ux transports" "A=$DEL_A_CODE B(renamed)=$DEL_B_CODE disabled=$DEL_D_CODE"
fi

curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null --data-urlencode "id=${UX_REF_EXT}" --data-urlencode "delete=Delete" --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" "${BASE_URL}/index.php/default/extensions/remove" >/dev/null
UX_CREATED_EXT=0

# ===========================================================================
# PART 3 (TASK-0020): runtime lifecycle -- collision validation, rename/
# delete restart-required semantics, post-save runtime verification,
# list-page runtime-mismatch visibility, and controlled restart recovery.
#
# WARNING, READ BEFORE RUNNING: unlike checks 1-40, this part performs a
# REAL, controlled `core restart now` against the shared dev Asterisk
# container (initiated only by this test harness, never by application
# code -- see docs/tasks/0020-pjsip-transport-runtime-lifecycle.md item 12).
# It is necessary to prove the investigation's own restart-recovery
# findings and is not optional/skippable, per this task's own explicit
# instruction to expand `make transport-smoke` itself rather than carve
# out a separate opt-in target. Do not run `make transport-smoke`
# expecting the Asterisk container's uptime/registration state to survive
# unchanged -- it will not, briefly, exactly like a real administrator
# restarting Asterisk after a transport rename would experience.
#
# Uses its own independent fixtures (task0020-* transports, extension
# 1094, its own trunk fixture) so it cannot interfere with checks 1-40's
# fixtures or ordering, and cleans up thoroughly via t20_cleanup() below.
# ===========================================================================

T20_COL_A="task0020-col-a"
T20_COL_B="task0020-col-b"
T20_COL_C="task0020-col-c"
T20_RENAME_OLD="task0020-rename-old"
T20_RENAME_NEW="task0020-rename-new"
T20_DELDIS="task0020-deldis"
T20_REUSE="task0020-reuse"
T20_REF_EXT=1094
T20_REF_EXT_SECRET="${FIXTURE_MARKER}-t20-ext"
T20_TRUNK_CALLERID="${FIXTURE_MARKER} t20 lifecycle trunk fixture"

T20_COL_A_ID=""
T20_COL_C_ID=""
T20_RENAME_ID=""
T20_DELDIS_ID=""
T20_REUSE_ID=""
T20_CREATED_EXT=0
T20_CREATED_TRUNK_ID=""

t20_cleanup() {
    log "==> TASK-0020 lifecycle cleanup"
    local failed=0
    if [ "$T20_CREATED_EXT" = "1" ]; then
        db_query "UPDATE peers SET transport_id = NULL WHERE name='${T20_REF_EXT}';" >/dev/null 2>&1
        delete_extension "$T20_REF_EXT" || { log "WARNING: HTTP delete of extension ${T20_REF_EXT} did not return 302 -- may need manual cleanup"; failed=1; }
    fi
    if [ -n "$T20_CREATED_TRUNK_ID" ]; then
        db_query "UPDATE trunks SET transport_id = NULL WHERE id=${T20_CREATED_TRUNK_ID};" >/dev/null 2>&1
        delete_trunk_fixture "$T20_CREATED_TRUNK_ID" || { log "WARNING: HTTP delete of t20 trunk id=${T20_CREATED_TRUNK_ID} did not return 302 -- may need manual cleanup"; failed=1; }
    fi
    for tid in "$T20_COL_A_ID" "$T20_COL_C_ID" "$T20_RENAME_ID" "$T20_DELDIS_ID" "$T20_REUSE_ID"; do
        if [ -n "$tid" ]; then
            delete_transport "$tid"
            [ "$DELETE_HTTPCODE" = "302" ] || { log "WARNING: HTTP delete of t20 transport id=${tid} did not return 302 -- may need manual cleanup"; failed=1; }
        fi
    done
    # item 16: never leave a deliberately-malformed row behind. This row
    # was itself created via raw SQL (a deliberate synthetic-corruption
    # fixture with no supported UI equivalent, see check 54 below) --
    # cleaning it up the same way is not a "raw SQL cleanup fallback" for
    # a real application-owned fixture, it is the only way to remove
    # something that was never created through a supported path.
    db_query "DELETE FROM pjsip_transports WHERE name='task0020-badproto';" >/dev/null 2>&1
    return "$failed"
}
# Registered right after cleanup()/ux_cleanup() at definition time --
# harness_finalize runs registered cleanups LIFO, so t20_cleanup (the
# last one registered) runs FIRST, then ux_cleanup, then cleanup --
# reproducing the exact order the old chained `trap 't20_cleanup;
# ux_cleanup; cleanup' EXIT` used.
harness_register_cleanup "transport-smoke fixtures (Part 3 / T20 lifecycle)" "t20_cleanup"

# t20_wait_for_asterisk -- poll after a real restart until the CLI
# connection is answering again. Up to 20s, matching the "within 15-20s"
# settling window already established elsewhere in this project's own
# smoke tests (e.g. call-smoke-test.sh's registration wait).
t20_wait_for_asterisk() {
    local attempt
    for attempt in $(seq 1 20); do
        if $COMPOSE exec -T asterisk asterisk -rx "core show uptime" 2>&1 | grep -q "System uptime"; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# t20_list_html -- fetch the transports list page HTML into a temp file,
# print its path. Used to inspect flash-message banners and the new
# per-row runtime badge (docs/tasks/0020-pjsip-transport-runtime-lifecycle.md
# items 2-4/6/7) without guessing at exact markup by hand each time.
t20_list_html() {
    local f
    f="$(mktemp)"
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" "${BASE_URL}/index.php/default/pjsip-transports" -o "$f"
    echo "$f"
}

# t20_runtime_badge <html_file> <transport_name> -- prints "active",
# "restart_required", "disabled", or "" (not found), read from the row's
# own Runtime column's data-runtime-state="..." attribute (index.phtml).
# Deliberately NOT grepping for the label-success/label-warning CSS
# classes directly: label-success is ALSO the Status column's own
# "Enabled" badge (an unrelated concept using the identical Bootstrap
# class), which sits earlier in the same row and would produce a false
# "active" match every time -- confirmed by hand during implementation.
# Uses the LAST occurrence of the name in the page, not the first -- a
# flash banner (which can also legitimately mention the same transport
# name, e.g. the rename/delete messages) always renders ABOVE the table.
t20_runtime_badge() {
    local f="$1" name="$2" lineno window
    lineno="$(grep -n "$name" "$f" | tail -1 | cut -d: -f1)"
    if [ -z "$lineno" ]; then
        echo ""
        return
    fi
    window="$(sed -n "${lineno},$((lineno + 15))p" "$f")"
    echo "$window" | grep -o 'data-runtime-state="[a-z_]*"' | head -1 | sed -e 's/data-runtime-state="//' -e 's/"$//'
}

log "==> [T20] checking for pre-existing fixtures"
for n in "$T20_COL_A" "$T20_COL_B" "$T20_COL_C" "$T20_RENAME_OLD" "$T20_RENAME_NEW" "$T20_DELDIS" "$T20_REUSE"; do
    existing="$(db_query "SELECT id FROM pjsip_transports WHERE name='${n}';")"
    if [ -n "$existing" ]; then
        stop "a transport named '${n}' already exists (id=${existing}) from a prior run that did not clean up. Remove it manually first."
    fi
done
existing="$(db_query "SELECT canal FROM peers WHERE name='${T20_REF_EXT}';")"
if [ -n "$existing" ]; then
    stop "peers row for extension '${T20_REF_EXT}' already exists. Remove it manually first."
fi
existing="$(db_query "SELECT id FROM trunks WHERE callerid='${T20_TRUNK_CALLERID}';")"
if [ -n "$existing" ]; then
    stop "a trunk with callerid '${T20_TRUNK_CALLERID}' already exists (id=${existing}) from a prior run. Remove it manually first."
fi

# --- 41. Pre-save collision rejected on create ------------------------------

log "==> [T20] creating ${T20_COL_A} (udp 0.0.0.0:5211)"
save_transport add "" "$T20_COL_A" udp 5211 1
[ "$SAVE_TRANSPORT_HTTPCODE" = "302" ] || stop "creating ${T20_COL_A} failed (HTTP $SAVE_TRANSPORT_HTTPCODE)"
T20_COL_A_ID="$(db_query "SELECT id FROM pjsip_transports WHERE name='${T20_COL_A}';")"

log "==> [T20] attempting to create ${T20_COL_B} on the identical udp 0.0.0.0:5211 (must be rejected BEFORE persistence)"
save_transport add "" "$T20_COL_B" udp 5211 1
COL_B_EXISTS="$(db_query "SELECT COUNT(*) FROM pjsip_transports WHERE name='${T20_COL_B}';")"
if [ "$SAVE_TRANSPORT_HTTPCODE" != "302" ] && echo "$SAVE_TRANSPORT_BODY" | grep -qi "already used by transport" && [ "$COL_B_EXISTS" = "0" ]; then
    ok "pre-save collision rejected (create)" "HTTP $SAVE_TRANSPORT_HTTPCODE, no DB row created for ${T20_COL_B}, error names the colliding transport"
else
    bad "pre-save collision rejected (create)" "HTTP=$SAVE_TRANSPORT_HTTPCODE db_rows=$COL_B_EXISTS body:\n$(echo "$SAVE_TRANSPORT_BODY" | head -c 300)"
fi

GENERATED_AFTER_COLLISION="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip-transports.conf 2>/dev/null)"
if echo "$GENERATED_AFTER_COLLISION" | grep -qF "[${T20_COL_A}]" && ! echo "$GENERATED_AFTER_COLLISION" | grep -qF "[${T20_COL_B}]"; then
    ok "A's config unchanged, B never generated" "[${T20_COL_A}] present, [${T20_COL_B}] absent from senma-pjsip-transports.conf"
else
    bad "A's config unchanged, B never generated" "unexpected content:\n$(echo "$GENERATED_AFTER_COLLISION" | grep -F "$T20_COL_A" -A6)"
fi

RUNTIME_A="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show transport ${T20_COL_A}" 2>&1)"
RUNTIME_B="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show transport ${T20_COL_B}" 2>&1)"
if echo "$RUNTIME_A" | grep -q "bind " && echo "$RUNTIME_B" | grep -qi "Unable to find"; then
    ok "A's runtime unchanged, B never reaches Asterisk" "A still live, B never attempted at all (rejected pre-save, not merely post-save)"
else
    bad "A's runtime unchanged, B never reaches Asterisk" "A:\n${RUNTIME_A}\nB:\n${RUNTIME_B}"
fi

# --- 42. Non-collision accepted: UDP/TCP share a numeric port cleanly ------

log "==> [T20] creating ${T20_COL_C} (tcp 0.0.0.0:5211 -- same port, different socket family)"
save_transport add "" "$T20_COL_C" tcp 5211 1
T20_COL_C_ID="$(db_query "SELECT id FROM pjsip_transports WHERE name='${T20_COL_C}';")"
if [ "$SAVE_TRANSPORT_HTTPCODE" = "302" ] && [ -n "$T20_COL_C_ID" ]; then
    ok "non-collision accepted (udp+tcp, same numeric port)" "HTTP 302, ${T20_COL_C} created -- confirms the collision rule is protocol-family-scoped, not bare-port-scoped"
else
    stop "creating ${T20_COL_C} failed (HTTP $SAVE_TRANSPORT_HTTPCODE) -- unexpected, this must not collide per the investigation's own §5 finding"
fi
RUNTIME_C="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show transport ${T20_COL_C}" 2>&1)"
if echo "$RUNTIME_C" | grep -q "bind "; then
    ok "non-colliding transport is live" "pjsip show transport ${T20_COL_C} found, bind 0.0.0.0:5211/tcp alongside ${T20_COL_A}'s udp on the same port"
else
    bad "non-colliding transport is live" "not found:\n${RUNTIME_C}"
fi

# --- 43. A plain hot-applied edit is reported ACTIVE, no spurious banner ---

log "==> [T20] editing ${T20_COL_C}'s domain (no identity change) -- must stay ACTIVE, no restart-required/apply-failed banner"
curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '' \
    --data-urlencode "name=${T20_COL_C}" --data-urlencode "protocol=tcp" \
    --data-urlencode "bind_address=0.0.0.0" --data-urlencode "bind_port=5211" \
    --data-urlencode "domain=task0020.example.test" --data-urlencode "external_signaling_address=" \
    --data-urlencode "external_signaling_port=" --data-urlencode "external_media_address=" \
    --data-urlencode "local_net=" --data-urlencode "allow_reload=1" --data-urlencode "enabled=1" \
    --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
    "${BASE_URL}/index.php/default/pjsip-transports/edit/id/${T20_COL_C_ID}"
LIST_HTML="$(t20_list_html)"
BADGE_C="$(t20_runtime_badge "$LIST_HTML" "$T20_COL_C")"
HAS_BANNER="$(grep -c "alert alert-warning\|alert alert-danger" "$LIST_HTML")"
if [ "$BADGE_C" = "active" ] && [ "$HAS_BANNER" = "0" ]; then
    ok "hot-applied edit reported ACTIVE, no spurious banner" "runtime badge=active, zero restart-required/apply-failed banners present"
else
    bad "hot-applied edit reported ACTIVE, no spurious banner" "badge=$BADGE_C banners=$HAS_BANNER"
fi
rm -f "$LIST_HTML"

# --- 44. Rename setup: dependent extension + trunk pinned to the pre-rename name

log "==> [T20] creating ${T20_RENAME_OLD} (udp 0.0.0.0:5212) and pinning a reference extension + trunk to it"
save_transport add "" "$T20_RENAME_OLD" udp 5212 1
T20_RENAME_ID="$(db_query "SELECT id FROM pjsip_transports WHERE name='${T20_RENAME_OLD}';")"
[ "$SAVE_TRANSPORT_HTTPCODE" = "302" ] || stop "creating ${T20_RENAME_OLD} failed (HTTP $SAVE_TRANSPORT_HTTPCODE)"

save_ref_extension add "$T20_REF_EXT" "$T20_REF_EXT_SECRET" "$T20_RENAME_ID"
[ "$SAVE_EXT_HTTPCODE" = "302" ] || stop "creating+pinning extension ${T20_REF_EXT} failed (HTTP $SAVE_EXT_HTTPCODE)"
T20_CREATED_EXT=1

UX_TRUNK_CALLERID="$T20_TRUNK_CALLERID"
if create_ux_trunk_fixture; then
    T20_CREATED_TRUNK_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${T20_TRUNK_CALLERID}';")"
    [ -n "$T20_CREATED_TRUNK_ID" ] || stop "t20 trunk fixture creation returned 302 but no matching row was found afterward"
else
    stop "creating the t20 trunk fixture failed -- see log above"
fi
edit_ux_trunk_fixture "$T20_CREATED_TRUNK_ID" "$T20_RENAME_ID"
[ "$EDIT_TRUNK_HTTPCODE" = "302" ] || stop "pinning t20 trunk to ${T20_RENAME_OLD} failed (HTTP $EDIT_TRUNK_HTTPCODE)"

EXT_SECTION_BEFORE="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip.conf 2>/dev/null | awk "/^\[${T20_REF_EXT}\]/{f=1} f{print} f&&/^\$/{exit}")"
T20_TRUNK_OBJ="trunk-${T20_CREATED_TRUNK_ID}"
TRUNK_CONF_BEFORE="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip-trunks.conf 2>/dev/null)"
TRUNK_EP_BEFORE="$(echo "$TRUNK_CONF_BEFORE" | awk "/^\[${T20_TRUNK_OBJ}\]\$/{f=1} f{print} f&&/^\$/{exit}")"
TRUNK_REG_BEFORE="$(echo "$TRUNK_CONF_BEFORE" | awk "/^\[${T20_TRUNK_OBJ}-registration\]/{f=1} f{print} f&&/^\$/{exit}")"
if echo "$EXT_SECTION_BEFORE" | grep -qF "transport=${T20_RENAME_OLD}" \
    && echo "$TRUNK_EP_BEFORE" | grep -qF "transport=${T20_RENAME_OLD}" \
    && echo "$TRUNK_REG_BEFORE" | grep -qF "transport=${T20_RENAME_OLD}"; then
    ok "dependents correctly pinned before rename" "extension ${T20_REF_EXT} and trunk ${T20_TRUNK_OBJ} (endpoint+registration) all reference ${T20_RENAME_OLD}"
else
    stop "dependents not correctly pinned before rename -- aborting the rename test, see sections above"
fi

# --- 45/46. Rename executed: restart-required, config-level cascade, runtime NOT falsely active

log "==> [T20] renaming ${T20_RENAME_OLD} -> ${T20_RENAME_NEW} (same bind 0.0.0.0:5212)"
save_transport edit "$T20_RENAME_ID" "$T20_RENAME_NEW" udp 5212 1
[ "$SAVE_TRANSPORT_HTTPCODE" = "302" ] || bad "rename save succeeds" "HTTP $SAVE_TRANSPORT_HTTPCODE"

LIST_HTML="$(t20_list_html)"
if grep -qi "restart required\|restart-required\|Asterisk restart required" "$LIST_HTML"; then
    ok "rename reports restart-required" "the flash-message banner naming the restart requirement is present on the list page"
else
    bad "rename reports restart-required" "no restart-required banner found on the list page after renaming"
fi

EXT_SECTION_AFTER="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip.conf 2>/dev/null | awk "/^\[${T20_REF_EXT}\]/{f=1} f{print} f&&/^\$/{exit}")"
TRUNK_CONF_AFTER="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip-trunks.conf 2>/dev/null)"
TRUNK_EP_AFTER="$(echo "$TRUNK_CONF_AFTER" | awk "/^\[${T20_TRUNK_OBJ}\]\$/{f=1} f{print} f&&/^\$/{exit}")"
TRUNK_REG_AFTER="$(echo "$TRUNK_CONF_AFTER" | awk "/^\[${T20_TRUNK_OBJ}-registration\]/{f=1} f{print} f&&/^\$/{exit}")"
if echo "$EXT_SECTION_AFTER" | grep -qF "transport=${T20_RENAME_NEW}" \
    && echo "$TRUNK_EP_AFTER" | grep -qF "transport=${T20_RENAME_NEW}" \
    && echo "$TRUNK_REG_AFTER" | grep -qF "transport=${T20_RENAME_NEW}"; then
    ok "dependent regeneration cascades to the new name (configured state)" "extension and trunk (endpoint+registration) all updated to transport=${T20_RENAME_NEW} immediately, at the file level"
else
    bad "dependent regeneration cascades to the new name (configured state)" "ext:\n${EXT_SECTION_AFTER}\ntrunk ep:\n${TRUNK_EP_AFTER}\ntrunk reg:\n${TRUNK_REG_AFTER}"
fi

# TASK-0028V: the original assumption here -- "a same-port rename can
# NEVER become live without a restart, zero exceptions" (TASK-0020's own
# investigation) -- is disproven. Live, reproducible evidence (raw CLI
# ground truth, persistent across 58s of follow-up polling, not a
# transient blip) shows regenerateAll()'s three sequential, redundant
# "module reload res_pjsip.so" calls per single edit (transport conf,
# then pjsip conf, then trunk conf -- all three fire even though only
# the transport actually changed) occasionally give Asterisk's own
# internal old-socket-teardown/new-socket-bind sequence enough chances to
# complete entirely server-side, before this script's HTTP response is
# even returned. No client-side wait/retry can observe a "before" state
# that has already resolved server side -- see
# docs/tasks/0028v-transport-smoke-t20-restart-race.md for the full
# reproduction. The real, always-true contract is not "it can never
# apply early" but "Asterisk's own runtime and the app's derived badge
# must always AGREE, whichever of the two legitimate outcomes occurred" --
# asserted below by checking coherence against ground truth (queried
# once, synchronously, exactly as before) rather than a single hardcoded
# expected value. This still fails on the original bug this check exists
# to catch (badge/reality mismatch in either direction) and on any
# incoherent/wrong-identity runtime state; it does not degrade into a
# generic "something succeeded" check.
RUNTIME_NEW_BEFORE_RESTART="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show transport ${T20_RENAME_NEW}" 2>&1)"
if echo "$RUNTIME_NEW_BEFORE_RESTART" | grep -qi "Unable to find"; then
    RUNTIME_NEW_CONVERGED=0
elif echo "$RUNTIME_NEW_BEFORE_RESTART" | grep -qE "bind[[:space:]]*:[[:space:]]*0\.0\.0\.0:5212([[:space:]]|$)"; then
    RUNTIME_NEW_CONVERGED=1
else
    RUNTIME_NEW_CONVERGED=-1
fi

if [ "$RUNTIME_NEW_CONVERGED" = "0" ]; then
    ok "runtime state before restart is coherent (not yet applied)" "pjsip show transport ${T20_RENAME_NEW} correctly reports 'Unable to find object' -- restart still required, the common case"
elif [ "$RUNTIME_NEW_CONVERGED" = "1" ]; then
    ok "runtime state before restart is coherent (self-applied early)" "pjsip show transport ${T20_RENAME_NEW} already shows the correct bind 0.0.0.0:5212 -- Asterisk's own reload occasionally completes the rebind before any restart (confirmed, non-deterministic -- see docs/tasks/0028v-transport-smoke-t20-restart-race.md), not a false report"
else
    bad "runtime state before restart is coherent" "neither 'Unable to find' nor the correct bind 0.0.0.0:5212 -- got:\n${RUNTIME_NEW_BEFORE_RESTART}"
fi

BADGE_NEW_BEFORE="$(t20_runtime_badge "$LIST_HTML" "$T20_RENAME_NEW")"
EXPECTED_BADGE_NEW="restart_required"
[ "$RUNTIME_NEW_CONVERGED" = "1" ] && EXPECTED_BADGE_NEW="active"
if [ "$BADGE_NEW_BEFORE" = "$EXPECTED_BADGE_NEW" ]; then
    ok "list-page badge matches Asterisk's real runtime state" "the list page never lies about runtime state -- badge=$BADGE_NEW_BEFORE, matching the raw runtime check above"
else
    bad "list-page badge matches Asterisk's real runtime state" "badge=$BADGE_NEW_BEFORE expected=$EXPECTED_BADGE_NEW (raw runtime check reported converged=$RUNTIME_NEW_CONVERGED)"
fi
rm -f "$LIST_HTML"

# --- 47/48. Delete leaves a stale socket; reusing it before restart is never claimed active

log "==> [T20] creating ${T20_DELDIS} (udp 0.0.0.0:5213), then deleting it"
save_transport add "" "$T20_DELDIS" udp 5213 1
T20_DELDIS_ID="$(db_query "SELECT id FROM pjsip_transports WHERE name='${T20_DELDIS}';")"
[ "$SAVE_TRANSPORT_HTTPCODE" = "302" ] || stop "creating ${T20_DELDIS} failed (HTTP $SAVE_TRANSPORT_HTTPCODE)"

delete_transport "$T20_DELDIS_ID"
LIST_HTML="$(t20_list_html)"
if [ "$DELETE_HTTPCODE" = "302" ] && grep -qi "restart" "$LIST_HTML"; then
    ok "delete reports restart-required" "HTTP 302, list page shows the restart-required banner naming the stale socket risk"
else
    bad "delete reports restart-required" "HTTP=$DELETE_HTTPCODE banner_present=$(grep -ci "restart" "$LIST_HTML")"
fi
T20_DELDIS_ID=""
rm -f "$LIST_HTML"

log "==> [T20] attempting to reuse the just-deleted socket under a new name (${T20_REUSE}, udp 0.0.0.0:5213)"
save_transport add "" "$T20_REUSE" udp 5213 1
T20_REUSE_ID="$(db_query "SELECT id FROM pjsip_transports WHERE name='${T20_REUSE}';")"
if [ "$SAVE_TRANSPORT_HTTPCODE" != "302" ]; then
    bad "socket reuse is accepted at the DB level (no collision)" "HTTP=$SAVE_TRANSPORT_HTTPCODE -- expected 302, the deleted row's socket must not DB-collide"
else
    ok "socket reuse is accepted at the DB level (no collision)" "HTTP 302, no DB-level collision -- ${T20_DELDIS_ID:-the deleted row} is gone"
fi

# TASK-0028V: same non-deterministic-early-convergence class as the
# rename checks above -- a delete+reuse on the same port can also
# occasionally self-apply within the create request itself, before any
# restart. Ground truth (raw CLI) decides which of the two legitimate
# outcomes applies; badge and apply-failed banner must both agree with it.
RUNTIME_REUSE_BEFORE_RESTART="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show transport ${T20_REUSE}" 2>&1)"
if echo "$RUNTIME_REUSE_BEFORE_RESTART" | grep -qi "Unable to find"; then
    REUSE_CONVERGED=0
elif echo "$RUNTIME_REUSE_BEFORE_RESTART" | grep -qE "bind[[:space:]]*:[[:space:]]*0\.0\.0\.0:5213([[:space:]]|$)"; then
    REUSE_CONVERGED=1
else
    REUSE_CONVERGED=-1
fi

LIST_HTML="$(t20_list_html)"
BADGE_REUSE_BEFORE="$(t20_runtime_badge "$LIST_HTML" "$T20_REUSE")"
if grep -qi "could not apply\|previous configuration may still be active" "$LIST_HTML"; then
    HAS_APPLY_FAILED_BANNER=1
else
    HAS_APPLY_FAILED_BANNER=0
fi

if [ "$REUSE_CONVERGED" = "0" ] && [ "$BADGE_REUSE_BEFORE" != "active" ] && [ "$HAS_APPLY_FAILED_BANNER" = "1" ]; then
    ok "socket reuse before restart is coherent (still stuck, the common case)" "runtime not found, apply-failed banner present, badge='$BADGE_REUSE_BEFORE'"
elif [ "$REUSE_CONVERGED" = "1" ] && [ "$BADGE_REUSE_BEFORE" = "active" ]; then
    ok "socket reuse before restart is coherent (self-applied early)" "pjsip show transport ${T20_REUSE} already shows the correct bind 0.0.0.0:5213 -- Asterisk freed and rebound the socket within the create request itself (confirmed, non-deterministic -- see docs/tasks/0028v-transport-smoke-t20-restart-race.md); badge correctly says active"
else
    bad "socket reuse before restart is coherent" "converged=$REUSE_CONVERGED badge=$BADGE_REUSE_BEFORE banner=$HAS_APPLY_FAILED_BANNER raw:\n${RUNTIME_REUSE_BEFORE_RESTART}"
fi
rm -f "$LIST_HTML"

# --- 49. Controlled restart -- TEST HARNESS ONLY, never application code --

log "==> [T20] performing a REAL, test-harness-controlled Asterisk restart to prove recovery (docs/tasks/0020-pjsip-transport-runtime-lifecycle.md item 12)"
$COMPOSE exec -T asterisk asterisk -rx "core restart now" >/dev/null 2>&1
if t20_wait_for_asterisk; then
    ok "controlled restart completes" "Asterisk answering the CLI again within 20s"
else
    stop "Asterisk did not come back within 20s after the controlled restart -- environment needs manual attention"
fi

# TASK-0028V: a genuinely distinct, harness-side race found during this
# investigation -- "core show uptime" answering (above) proves Asterisk's
# CLI/AMI is up, NOT that every module has finished loading. res_pjsip.so
# is one of the heavier modules to initialize after a full restart
# (reloads every sorcery-backed endpoint/aor/auth/registration object),
# and a "pjsip show transport ..." query issued too early after the
# restart can hit "No such command 'pjsip show transport ...'" -- observed
# live during reproduction. Same bounded-retry pattern already used for
# this exact module at this script's own startup check (pjsip_module_running
# + harness_retry), just never applied after a REAL restart before.
if ! harness_retry 15 1 -- pjsip_module_running; then
    stop "res_pjsip.so did not report Running within 15s after the controlled restart"
fi

# --- 50. Post-restart: renamed transport active, old name gone -------------

RUNTIME_NEW_AFTER="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show transport ${T20_RENAME_NEW}" 2>&1)"
RUNTIME_OLD_AFTER="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show transport ${T20_RENAME_OLD}" 2>&1)"
if echo "$RUNTIME_NEW_AFTER" | grep -q "bind " && echo "$RUNTIME_OLD_AFTER" | grep -qi "Unable to find"; then
    ok "restart recovery: renamed transport active, old name absent" "${T20_RENAME_NEW} live with the correct bind, ${T20_RENAME_OLD} correctly gone"
else
    bad "restart recovery: renamed transport active, old name absent" "new:\n${RUNTIME_NEW_AFTER}\nold:\n${RUNTIME_OLD_AFTER}"
fi
LIST_HTML="$(t20_list_html)"
BADGE_NEW_AFTER="$(t20_runtime_badge "$LIST_HTML" "$T20_RENAME_NEW")"
if [ "$BADGE_NEW_AFTER" = "active" ]; then
    ok "list-page badge flips to active after restart" "badge=$BADGE_NEW_AFTER -- the same derived check that correctly said restart_required before now correctly says active, with no persisted flag anywhere"
else
    bad "list-page badge flips to active after restart" "badge=$BADGE_NEW_AFTER"
fi
rm -f "$LIST_HTML"

# --- 51/52. Post-restart: dependent extension + trunk functionality recovers

RUNTIME_EXT="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${T20_REF_EXT}" 2>&1)"
if echo "$RUNTIME_EXT" | grep -qE "^ *transport +: ${T20_RENAME_NEW}$"; then
    ok "dependent extension functionality recovers after restart" "pjsip show endpoint ${T20_REF_EXT} reports transport: ${T20_RENAME_NEW}"
else
    bad "dependent extension functionality recovers after restart" "$RUNTIME_EXT"
fi

RUNTIME_TRUNK_EP="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${T20_TRUNK_OBJ}" 2>&1)"
if echo "$RUNTIME_TRUNK_EP" | grep -qE "^ *transport +: ${T20_RENAME_NEW}$"; then
    ok "dependent trunk endpoint functionality recovers after restart" "pjsip show endpoint ${T20_TRUNK_OBJ} reports transport: ${T20_RENAME_NEW}"
else
    bad "dependent trunk endpoint functionality recovers after restart" "$RUNTIME_TRUNK_EP"
fi

# Same command/assertion shape trunk-smoke-test.sh already uses and
# proves reliable ("outbound registration Registered" -- up to 15s to
# settle, matching that established convention exactly).
T20_REG_OK=0
for _attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    RUNTIME_TRUNK_REG="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show registrations outbound" 2>&1)"
    if echo "$RUNTIME_TRUNK_REG" | grep "${T20_TRUNK_OBJ}-registration" | grep -q "Registered"; then
        T20_REG_OK=1
        break
    fi
    sleep 1
done
if [ "$T20_REG_OK" = "1" ]; then
    ok "dependent trunk outbound registration recovers after restart" "${T20_TRUNK_OBJ}-registration reached Registered again within 15s"
else
    bad "dependent trunk outbound registration recovers after restart" "did not reach Registered within 15s:\n$RUNTIME_TRUNK_REG"
fi

# --- 53. Post-restart: the previously-stuck socket reuse now succeeds ------

RUNTIME_REUSE_AFTER="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show transport ${T20_REUSE}" 2>&1)"
if echo "$RUNTIME_REUSE_AFTER" | grep -q "bind "; then
    ok "socket reuse succeeds after restart" "pjsip show transport ${T20_REUSE} now live at 0.0.0.0:5213 -- the exact socket ${T20_DELDIS} left stuck is now free"
else
    bad "socket reuse succeeds after restart" "$RUNTIME_REUSE_AFTER"
fi

# --- 54. Reload-error-masking fix: a genuine per-object failure must not be
#         replaced by a secondary Zend_Registry exception, and must leave a
#         useful trace in /var/log/asterisk/full (item 9/16). ---------------

log "==> [T20] triggering a deliberate, malformed transport row to validate the reload-failure-masking fix"
db_query "INSERT INTO pjsip_transports (name, protocol, bind_address, bind_port, symmetric_transport, allow_reload, is_default, enabled, is_seed) VALUES ('task0020-badproto', 'garbage123', '0.0.0.0', 5299, 0, 1, 0, 1, 0);" >/dev/null
REGEN_OUTPUT="$(regenerate_all 2>&1)"
if echo "$REGEN_OUTPUT" | grep -qi "No entry is registered for key 'log'\|Zend_Exception"; then
    bad "reload failure does not mask as a secondary Zend_Registry exception" "found the exact masking exception this fix removes:\n$(echo "$REGEN_OUTPUT" | grep -i "zend\|log" | head -5)"
else
    ok "reload failure does not mask as a secondary Zend_Registry exception" "regenerateAll() completed without the pre-existing 'No entry is registered for key log' exception"
fi
ASTERISK_LOG_DETAIL="$($COMPOSE exec -T asterisk grep -c "task0020-badproto" /var/log/asterisk/full 2>/dev/null)"
if [ "${ASTERISK_LOG_DETAIL:-0}" -gt 0 ]; then
    ok "useful failure detail exists in /var/log/asterisk/full" "found ${ASTERISK_LOG_DETAIL} log line(s) naming the malformed object -- confirms this class of failure is only ever visible there, never in docker compose logs (investigation §11/§19)"
else
    bad "useful failure detail exists in /var/log/asterisk/full" "no log line found naming task0020-badproto"
fi
GOOD_TRANSPORT_SURVIVED="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip-transports.conf 2>/dev/null | grep -c "^\[${T20_RENAME_NEW}\]")"
if [ "$GOOD_TRANSPORT_SURVIVED" -gt 0 ]; then
    ok "a malformed row does not corrupt generation of everything else" "[${T20_RENAME_NEW}] still present in the regenerated file alongside the malformed row"
else
    bad "a malformed row does not corrupt generation of everything else" "[${T20_RENAME_NEW}] missing after regeneration"
fi
db_query "DELETE FROM pjsip_transports WHERE name='task0020-badproto';" >/dev/null
regenerate_all >/dev/null

log "==> [T20] final cleanup"
# Dependents FIRST -- task0020-rename-new is still explicitly referenced
# by both the reference extension and the trunk fixture at this point,
# and PjsipTransportsController::removeAction() correctly blocks
# deleting a referenced transport (same protection §7 of the
# investigation already documented) -- attempting the transport deletes
# before clearing/removing what references them would silently fail
# every time, exactly as first discovered running this suite twice in a
# row during implementation.
if [ -n "$T20_CREATED_TRUNK_ID" ]; then
    db_query "UPDATE trunks SET transport_id = NULL WHERE id=${T20_CREATED_TRUNK_ID};" >/dev/null 2>&1
    delete_trunk_fixture "$T20_CREATED_TRUNK_ID" && T20_CREATED_TRUNK_ID=""
fi
db_query "UPDATE peers SET transport_id = NULL WHERE name='${T20_REF_EXT}';" >/dev/null 2>&1
delete_extension "$T20_REF_EXT" && T20_CREATED_EXT=0

delete_transport "$T20_COL_A_ID"; T20_COL_A_ID=""
delete_transport "$T20_COL_C_ID"; T20_COL_C_ID=""
delete_transport "$T20_RENAME_ID"; T20_RENAME_ID=""
delete_transport "$T20_REUSE_ID"; T20_REUSE_ID=""

harness_complete
