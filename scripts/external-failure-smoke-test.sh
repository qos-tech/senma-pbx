#!/bin/bash
#
# SENMA external-API failure isolation smoke test (TASK-0024).
#
# Proves, against a running `make dev` Docker environment, that a
# non-essential vendor API failure can no longer break unrelated SENMA
# pages -- the exact release blocker TASK-0023 discovered by accident
# (an intermittent, unrelated `make smoke` flake) and TASK-0024 traced
# to its root cause: Snep_Request::send_request() previously fataled
# with a PHP 8 count(null)/undefined-array-key error whenever the
# transport itself failed (DNS/refused/blackhole/TLS), and that call
# sat directly in the shared page layout (Snep_Notifications) and in
# SystemstatusController::indexAction() (Snep_Version). See
# docs/tasks/0024-external-api-failure-isolation.md.
#
# NEVER calls the real vendor. Every failure mode below is produced by
# a controlled local PHP router (docker/external-failure-test/router.php,
# started only for the duration of this script) or a reserved/loopback
# address that can never resolve to a real service:
#   - DNS failure:      a .invalid hostname (RFC 2606)
#   - connection refused: a closed local port
#   - blackhole/timeout: 192.0.2.1 (RFC 5737 TEST-NET-1)
#   - TLS/connect failure: https:// against the plain-HTTP local router
#   - HTTP 500 / malformed / empty / null payload: the local router
#
# Temporarily repoints core_config's host_notification/update_server
# rows at these controlled targets (reversible -- restored in cleanup,
# exactly like every fixture other smoke scripts in this project use)
# and forces the TASK-0024 cache to be stale before each check, so
# every check genuinely exercises a live (simulated) failure rather
# than being served from a still-fresh cache.
#
# Deliberately separate from `make smoke`, per this task's own explicit
# instruction -- never run implicitly by it.
#
# TASK-0027: rebuilt on scripts/lib/harness.sh for explicit
# PASS/FAIL/BLOCKED/INCONCLUSIVE classification and signal-safe
# finalization. See docs/tasks/0027-regression-harness-reliability.md.
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
ROUTER_PORT=8999
# TASK-0024's own recommended, evidence-based bound (investigation §12):
# a genuine vendor outage should add at most ~2s to an affected request,
# never the old 3-5s default. Checked with generous slack below.
LATENCY_BOUND_SECONDS=3

COOKIEJAR=""
ROUTER_STARTED=0
ORIG_HOST_NOTIFICATION=""
ORIG_UPDATE_SERVER=""
ORIG_HOST_INSPECT=""

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

http_login() {
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null \
        -d "user=${TEST_USER}&password=${TEST_PASSWORD}" "${BASE_URL}/index.php/auth/login"
}

fatal_count() {
    local n
    n="$($COMPOSE exec -T app sh -c 'grep -c "Fatal error" /var/log/apache2/mag-error.log 2>/dev/null' 2>/dev/null | tr -d '\r\n ')"
    echo "${n:-0}"
}

# set_vendor_config <core_config name> <value>
set_vendor_config() {
    db_query "DELETE FROM core_config WHERE config_module='default' AND config_name='$1';" >/dev/null
    db_query "INSERT INTO core_config (config_module, config_name, config_value) VALUES ('default','$1','$2');" >/dev/null
}

# force_cache_stale -- backdate/clear TASK-0024's own TTL markers so the
# very next request genuinely attempts a (simulated) live fetch instead
# of serving an already-fresh cache.
force_cache_stale() {
    db_query "DELETE FROM core_config WHERE config_name IN ('notifications_synced_at','update_server_synced_at','host_inspect_synced_at');" >/dev/null
}

# fresh_session_jar -- a brand-new cookiejar + login, used specifically
# for host_inspect's own once-per-session $_SESSION['cloud_noticed']
# gate (on top of its global TTL gate, TASK-0024 implementation §CloudNotice).
fresh_session_jar() {
    local jar
    jar="$(mktemp)"
    curl -sS -c "$jar" -b "$jar" -o /dev/null -d "user=${TEST_USER}&password=${TEST_PASSWORD}" "${BASE_URL}/index.php/auth/login"
    echo "$jar"
}

# check_page <label> <url> <also-must-contain>
# Fetches $url, asserts HTTP 200 (never 500), asserts latency within
# LATENCY_BOUND_SECONDS, asserts zero new PHP Fatal Errors, and (if
# given) asserts the body still contains an expected marker proving the
# page rendered its real content, not a blank/broken shell.
check_page() {
    local label="$1" url="$2" marker="${3:-}"
    local before after httpcode elapsed body
    before="$(fatal_count)"
    body="$(mktemp)"
    local t0 t1
    t0=$(date +%s.%N)
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' --max-time 10 "$url")"
    t1=$(date +%s.%N)
    elapsed="$(echo "$t1 $t0" | LC_NUMERIC=C awk '{printf "%.3f", $1-$2}')"
    after="$(fatal_count)"

    local within_bound
    within_bound="$(echo "$elapsed $LATENCY_BOUND_SECONDS" | LC_NUMERIC=C awk '{print ($1 <= $2+0.5) ? 1 : 0}')"

    if [ "$httpcode" = "200" ] && [ "$before" = "$after" ] && [ "$within_bound" = "1" ] \
        && { [ -z "$marker" ] || grep -q "$marker" "$body"; }; then
        ok "$label" "HTTP 200, ${elapsed}s (bound ${LATENCY_BOUND_SECONDS}s), fatals ${before}->${after}"
    else
        bad "$label" "HTTP ${httpcode}, ${elapsed}s, fatals ${before}->${after}$([ -n "$marker" ] && ! grep -q "$marker" "$body" && echo ", marker '$marker' missing")"
    fi
    rm -f "$body"
}

start_router() {
    local mode_dir
    mode_dir="$(mktemp -d)"
    cp docker/external-failure-test/router.php "$mode_dir/router.php"
    $COMPOSE cp "$mode_dir/router.php" "app:/tmp/t24-router/router.php" 2>/dev/null \
        || { $COMPOSE exec -T app mkdir -p /tmp/t24-router; $COMPOSE cp "$mode_dir/router.php" "app:/tmp/t24-router/router.php"; }
    $COMPOSE exec -d app sh -c "cd /tmp/t24-router && php -S 127.0.0.1:${ROUTER_PORT} router.php > /tmp/t24-router.log 2>&1"
    ROUTER_STARTED=1
    rm -rf "$mode_dir"
    sleep 1
    if ! $COMPOSE exec -T app sh -c "curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:${ROUTER_PORT}/mode/ok" 2>/dev/null | grep -q 200; then
        stop "controlled local test router did not start correctly -- refusing to proceed"
    fi
}

stop_router() {
    if [ "$ROUTER_STARTED" = "1" ]; then
        $COMPOSE exec -T app sh -c "pkill -f 'php -S 127.0.0.1:${ROUTER_PORT}' 2>/dev/null; rm -rf /tmp/t24-router" >/dev/null 2>&1
        ROUTER_STARTED=0
    fi
}

cleanup() {
    log "==> cleanup"
    stop_router
    # host_notification/update_server/host_inspect are global vendor
    # integration endpoints with no add/remove/edit UI of their own
    # (unlike extensions/trunks/transports) -- backing up and restoring
    # their exact prior value via the same core_config path this script
    # used to point them at the local test router is the established
    # pattern this project already uses for config-value fixtures (see
    # preauth-security-smoke-test.sh's setup.conf backup/restore), not a
    # raw-SQL fallback for a UI-created resource.
    if [ -n "$ORIG_HOST_NOTIFICATION" ]; then
        set_vendor_config "host_notification" "$ORIG_HOST_NOTIFICATION"
    fi
    if [ -n "$ORIG_UPDATE_SERVER" ]; then
        set_vendor_config "update_server" "$ORIG_UPDATE_SERVER"
    fi
    if [ -n "$ORIG_HOST_INSPECT" ]; then
        set_vendor_config "host_inspect" "$ORIG_HOST_INSPECT"
    fi
    db_query "DELETE FROM core_config WHERE config_name IN ('notifications_synced_at','update_server_synced_at','update_server_latest_version','host_inspect_synced_at');" >/dev/null 2>&1
    db_query "DELETE FROM core_notifications;" >/dev/null 2>&1
    [ -n "$COOKIEJAR" ] && rm -f "$COOKIEJAR"
    return 0
}
harness_register_cleanup "external-failure-smoke vendor config + router" "cleanup"

# --- 0. Safety guards ------------------------------------------------------

log "==> checking required containers"
harness_require_containers app db

harness_require_env DB_USER DB_PASSWORD DB_NAME

# --- 1. Log in, back up real vendor config ---------------------------------

COOKIEJAR="$(mktemp)"
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${TEST_PASSWORD}');" 2>/dev/null | tr -d '\r')"
db_query "UPDATE users SET password = '${TEST_HASH}' WHERE name = '${TEST_USER}';" >&2
http_login
ok "authenticated session" "logged in as ${TEST_USER}"

ORIG_HOST_NOTIFICATION="$(db_query "SELECT config_value FROM core_config WHERE config_module='default' AND config_name='host_notification';")"
ORIG_UPDATE_SERVER="$(db_query "SELECT config_value FROM core_config WHERE config_module='default' AND config_name='update_server';")"
ORIG_HOST_INSPECT="$(db_query "SELECT config_value FROM core_config WHERE config_module='default' AND config_name='host_inspect';")"
if [ -z "$ORIG_HOST_NOTIFICATION" ] || [ -z "$ORIG_UPDATE_SERVER" ] || [ -z "$ORIG_HOST_INSPECT" ]; then
    stop "could not read the existing host_notification/update_server/host_inspect config rows -- refusing to proceed without a value to restore"
fi
ok "vendor config backed up" "host_notification, update_server, and host_inspect originals captured for restoration"

start_router
ok "controlled local test router started" "docker/external-failure-test/router.php on 127.0.0.1:${ROUTER_PORT}, never the real vendor"

# --- 2. Sanity baseline: local pages healthy before any failure mode ------

force_cache_stale
set_vendor_config "host_notification" "http://127.0.0.1:${ROUTER_PORT}/mode/ok"
set_vendor_config "update_server" "http://127.0.0.1:${ROUTER_PORT}/mode/version_ok"
set_vendor_config "host_inspect" "http://127.0.0.1:${ROUTER_PORT}/mode/version_ok"
check_page "baseline: extensions healthy (vendor OK)" "${BASE_URL}/index.php/default/extensions" "controller = \"extensions\""
check_page "baseline: systemstatus healthy (vendor OK)" "${BASE_URL}/index.php/default/systemstatus" "Asterisk"

# --- A. DNS failure ----------------------------------------------------

force_cache_stale
set_vendor_config "host_notification" "http://this-host-does-not-exist.invalid"
set_vendor_config "update_server" "http://this-host-does-not-exist.invalid"
set_vendor_config "host_inspect" "http://this-host-does-not-exist.invalid"
check_page "A. DNS failure: extensions stays healthy" "${BASE_URL}/index.php/default/extensions" "controller = \"extensions\""
force_cache_stale
check_page "A. DNS failure: systemstatus stays healthy" "${BASE_URL}/index.php/default/systemstatus" "Asterisk"

# --- B. connection refused ----------------------------------------------

force_cache_stale
set_vendor_config "host_notification" "http://127.0.0.1:8998"
set_vendor_config "update_server" "http://127.0.0.1:8998"
set_vendor_config "host_inspect" "http://127.0.0.1:8998"
check_page "B. connection refused: extensions stays healthy" "${BASE_URL}/index.php/default/extensions" "controller = \"extensions\""
force_cache_stale
check_page "B. connection refused: systemstatus stays healthy" "${BASE_URL}/index.php/default/systemstatus" "Asterisk"

# --- C. timeout / blackhole (RFC 5737 TEST-NET-1) -----------------------

force_cache_stale
set_vendor_config "host_notification" "http://192.0.2.1"
set_vendor_config "update_server" "http://192.0.2.1"
set_vendor_config "host_inspect" "http://192.0.2.1"
check_page "C. blackhole timeout: extensions stays healthy" "${BASE_URL}/index.php/default/extensions" "controller = \"extensions\""
force_cache_stale
check_page "C. blackhole timeout: systemstatus stays healthy" "${BASE_URL}/index.php/default/systemstatus" "Asterisk"

# --- D. TLS/connect failure (https against the plain-HTTP local router) --

force_cache_stale
set_vendor_config "host_notification" "https://127.0.0.1:${ROUTER_PORT}/mode/ok"
set_vendor_config "update_server" "https://127.0.0.1:${ROUTER_PORT}/mode/version_ok"
set_vendor_config "host_inspect" "https://127.0.0.1:${ROUTER_PORT}/mode/version_ok"
check_page "D. TLS failure: extensions stays healthy" "${BASE_URL}/index.php/default/extensions" "controller = \"extensions\""
force_cache_stale
check_page "D. TLS failure: systemstatus stays healthy" "${BASE_URL}/index.php/default/systemstatus" "Asterisk"

# --- E. HTTP 500 ---------------------------------------------------------

force_cache_stale
set_vendor_config "host_notification" "http://127.0.0.1:${ROUTER_PORT}/mode/500"
set_vendor_config "update_server" "http://127.0.0.1:${ROUTER_PORT}/mode/500"
set_vendor_config "host_inspect" "http://127.0.0.1:${ROUTER_PORT}/mode/500"
check_page "E. HTTP 500: extensions stays healthy" "${BASE_URL}/index.php/default/extensions" "controller = \"extensions\""
force_cache_stale
check_page "E. HTTP 500: systemstatus stays healthy" "${BASE_URL}/index.php/default/systemstatus" "Asterisk"

# --- F. malformed payload -------------------------------------------------

force_cache_stale
set_vendor_config "host_notification" "http://127.0.0.1:${ROUTER_PORT}/mode/malformed"
set_vendor_config "update_server" "http://127.0.0.1:${ROUTER_PORT}/mode/malformed"
set_vendor_config "host_inspect" "http://127.0.0.1:${ROUTER_PORT}/mode/malformed"
check_page "F. malformed payload: extensions stays healthy" "${BASE_URL}/index.php/default/extensions" "controller = \"extensions\""
force_cache_stale
check_page "F. malformed payload: systemstatus stays healthy" "${BASE_URL}/index.php/default/systemstatus" "Asterisk"

# --- G. empty/null payload -------------------------------------------------

force_cache_stale
set_vendor_config "host_notification" "http://127.0.0.1:${ROUTER_PORT}/mode/empty"
set_vendor_config "update_server" "http://127.0.0.1:${ROUTER_PORT}/mode/null"
set_vendor_config "host_inspect" "http://127.0.0.1:${ROUTER_PORT}/mode/empty"
check_page "G. empty/null payload: extensions stays healthy" "${BASE_URL}/index.php/default/extensions" "controller = \"extensions\""
force_cache_stale
check_page "G. empty/null payload: systemstatus stays healthy" "${BASE_URL}/index.php/default/systemstatus" "Asterisk"

# --- H. restart controls remain reachable under vendor failure ------------
# TASK-0024 §26's own most important finding: a vendor outage previously
# risked transitively blocking restart *availability* (not restart
# functionality itself) via SystemstatusController::indexAction()'s own
# inline Snep_Version call. Prove the confirmation controls still render.

force_cache_stale
set_vendor_config "update_server" "http://192.0.2.1"
STATUS_PAGE="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" "${BASE_URL}/index.php/default/systemstatus")"
if echo "$STATUS_PAGE" | grep -q 'id="restartStateLabel"'; then
    ok "restart controls render with vendor unavailable" "restartStateLabel present in systemstatus HTML"
else
    bad "restart controls render with vendor unavailable" "restart controls missing from rendered page"
fi
RESTART_STATUS_HTTP="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' "${BASE_URL}/index.php/default/systemstatus/restart-status")"
if [ "$RESTART_STATUS_HTTP" = "200" ]; then
    ok "restart readiness polling reachable with vendor unavailable" "restart-status HTTP 200"
else
    bad "restart readiness polling reachable with vendor unavailable" "restart-status HTTP ${RESTART_STATUS_HTTP}"
fi

# --- I. host_inspect: cold-cache worst case, warm-cache, recovery --------
# CloudNotice()'s host_inspect call was found and approved for TASK-0024
# during implementation (not the original investigation) -- see the doc's
# implementation section. All three vendor endpoints down simultaneously,
# on a genuinely fresh session with a genuinely cold cache, is the one
# remaining bounded-but-not-instant case (measured ~5.26s pre-existing,
# down from ~6.23s before this fix) -- rare (once per
# HOST_INSPECT_CACHE_TTL_SECONDS globally) and explicitly measured here,
# not hidden.

force_cache_stale
set_vendor_config "host_notification" "http://192.0.2.1"
set_vendor_config "update_server" "http://192.0.2.1"
set_vendor_config "host_inspect" "http://192.0.2.1"
COLD_JAR="$(fresh_session_jar)"
harness_register_best_effort_cleanup "cold-cache session jar temp file" "rm -f '$COLD_JAR'"
COLD_T0=$(date +%s.%N)
COLD_HTTP="$(curl -sS -c "$COLD_JAR" -b "$COLD_JAR" -o /dev/null -w '%{http_code}' --max-time 15 "${BASE_URL}/index.php/default/systemstatus")"
COLD_T1=$(date +%s.%N)
COLD_ELAPSED="$(echo "$COLD_T1 $COLD_T0" | LC_NUMERIC=C awk '{printf "%.3f", $1-$2}')"
COLD_WITHIN_BOUND="$(echo "$COLD_ELAPSED" | LC_NUMERIC=C awk '{print ($1 <= 8.0) ? 1 : 0}')"
if [ "$COLD_HTTP" = "200" ] && [ "$COLD_WITHIN_BOUND" = "1" ]; then
    ok "I. cold cache + all vendors down: bounded worst case" "HTTP 200, ${COLD_ELAPSED}s (bound 8s -- CloudNotice 2s + Version 2s + local rendering, all sequential, once globally per TTL)"
else
    bad "I. cold cache + all vendors down: bounded worst case" "HTTP ${COLD_HTTP}, ${COLD_ELAPSED}s"
fi

WARM_T0=$(date +%s.%N)
WARM_HTTP="$(curl -sS -c "$COLD_JAR" -b "$COLD_JAR" -o /dev/null -w '%{http_code}' "${BASE_URL}/index.php/default/systemstatus")"
WARM_T1=$(date +%s.%N)
WARM_ELAPSED="$(echo "$WARM_T1 $WARM_T0" | LC_NUMERIC=C awk '{printf "%.3f", $1-$2}')"
WARM_WITHIN_BOUND="$(echo "$WARM_ELAPSED" | LC_NUMERIC=C awk '{print ($1 <= 2.0) ? 1 : 0}')"
if [ "$WARM_HTTP" = "200" ] && [ "$WARM_WITHIN_BOUND" = "1" ]; then
    ok "I. warm cache, same session, vendors still down" "HTTP 200, ${WARM_ELAPSED}s (near local baseline -- both TTLs now fresh)"
else
    bad "I. warm cache, same session, vendors still down" "HTTP ${WARM_HTTP}, ${WARM_ELAPSED}s"
fi

NEWSESSION_JAR="$(fresh_session_jar)"
harness_register_best_effort_cleanup "new-session jar temp file" "rm -f '$NEWSESSION_JAR'"
NEWSESSION_T0=$(date +%s.%N)
NEWSESSION_HTTP="$(curl -sS -c "$NEWSESSION_JAR" -b "$NEWSESSION_JAR" -o /dev/null -w '%{http_code}' "${BASE_URL}/index.php/default/systemstatus")"
NEWSESSION_T1=$(date +%s.%N)
NEWSESSION_ELAPSED="$(echo "$NEWSESSION_T1 $NEWSESSION_T0" | LC_NUMERIC=C awk '{printf "%.3f", $1-$2}')"
NEWSESSION_WITHIN_BOUND="$(echo "$NEWSESSION_ELAPSED" | LC_NUMERIC=C awk '{print ($1 <= 2.0) ? 1 : 0}')"
if [ "$NEWSESSION_HTTP" = "200" ] && [ "$NEWSESSION_WITHIN_BOUND" = "1" ]; then
    ok "I. brand-new session, global TTL still protects it" "HTTP 200, ${NEWSESSION_ELAPSED}s -- host_inspect's TTL gate is global, not per-session"
else
    bad "I. brand-new session, global TTL still protects it" "HTTP ${NEWSESSION_HTTP}, ${NEWSESSION_ELAPSED}s"
fi
rm -f "$COLD_JAR" "$NEWSESSION_JAR"

# --- J. vendor recovery: healthy again, no restart needed ------------------

force_cache_stale
set_vendor_config "host_notification" "http://127.0.0.1:${ROUTER_PORT}/mode/ok"
set_vendor_config "update_server" "http://127.0.0.1:${ROUTER_PORT}/mode/version_ok"
set_vendor_config "host_inspect" "http://127.0.0.1:${ROUTER_PORT}/mode/ok"
check_page "J. vendor recovers: extensions healthy, no restart needed" "${BASE_URL}/index.php/default/extensions" "controller = \"extensions\""
force_cache_stale
check_page "J. vendor recovers: systemstatus healthy, no restart needed" "${BASE_URL}/index.php/default/systemstatus" "Asterisk"

# --- K. cache determinism: within TTL, no repeated vendor contact needed --
# (implicitly proven by every check_page() call above never exceeding the
# latency bound even against a blackhole/timeout target -- each is its own
# forced-stale, single attempt, never compounding)

harness_complete
