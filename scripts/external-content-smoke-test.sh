#!/bin/bash
#
# SENMA vendor-content XSS hardening smoke test (TASK-0025).
#
# Proves, against a running `make dev` Docker environment, that data
# received from optional SENMA/vendor APIs cannot inject active
# HTML/JavaScript into local SENMA pages. Deliberately separate from
# `make external-failure-smoke` (TASK-0024, which simulates transport
# failures, not content) -- this suite is about CONTENT, not
# availability. See docs/tasks/0025-vendor-content-xss-hardening.md.
#
# NEVER calls the real vendor. Every payload below is served by a
# controlled local PHP router (docker/external-content-test/router.php,
# started only for the duration of this script) serving deterministic,
# fixed malicious fixtures.
#
# This suite proves what a server-output assertion CAN prove: that
# every server-rendered vendor field is escaped/neutralized at its
# output boundary. It additionally asserts (via a static, source-content
# check) that the one CLIENT-SIDE sink (notifications.js's Announce
# handler) ships the scheme-validation fix -- proving the browser-
# runtime behavior itself is out of scope for a server-output-only
# suite and was instead verified once, interactively, during this
# task's implementation (see docs/tasks/0025-vendor-content-xss-hardening.md
# §9/§21 for that evidence).
#
# Deliberately separate from `make smoke` -- never run implicitly by it.
#
# Exit code: 0 if every check PASSes; 1 if any check FAILs.

set -uo pipefail

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
BASE_URL="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
TEST_USER="admin"
TEST_PASSWORD="SmokeTest123!"
ROUTER_PORT=8996

PASS=0
FAIL=0
declare -a RESULTS=()
COOKIEJAR=""
ROUTER_STARTED=0
ORIG_HOST_NOTIFICATION=""
ORIG_UPDATE_SERVER=""

log()  { printf '%s\n' "$*" >&2; }
row()  { RESULTS+=("$1|$2|$3"); }
ok()   { row "$1" "PASS" "$2"; PASS=$((PASS+1)); log "PASS: $1 -- $2"; }
bad()  { row "$1" "FAIL" "$2"; FAIL=$((FAIL+1)); log "FAIL: $1 -- $2"; }

print_report() {
    echo
    echo "================================================================"
    printf "%-46s %-8s %s\n" "CHECK" "RESULT" "DETAIL"
    echo "----------------------------------------------------------------"
    for r in "${RESULTS[@]}"; do
        IFS='|' read -r flow status detail <<< "$r"
        printf "%-46s %-8s %s\n" "$flow" "$status" "$detail"
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

fatal_count() {
    local n
    n="$($COMPOSE exec -T app sh -c 'grep -c "Fatal error" /var/log/apache2/mag-error.log 2>/dev/null' 2>/dev/null | tr -d '\r\n ')"
    echo "${n:-0}"
}

set_vendor_config() {
    db_query "DELETE FROM core_config WHERE config_module='default' AND config_name='$1';" >/dev/null
    db_query "INSERT INTO core_config (config_module, config_name, config_value) VALUES ('default','$1','$2');" >/dev/null
}

force_cache_stale() {
    db_query "DELETE FROM core_config WHERE config_name IN ('notifications_synced_at','update_server_synced_at','update_server_latest_version');" >/dev/null
    db_query "DELETE FROM core_notifications;" >/dev/null
}

start_router() {
    local mode_dir
    mode_dir="$(mktemp -d)"
    cp docker/external-content-test/router.php "$mode_dir/router.php"
    $COMPOSE cp "$mode_dir/router.php" "app:/tmp/t25-router/router.php" 2>/dev/null \
        || { $COMPOSE exec -T app mkdir -p /tmp/t25-router; $COMPOSE cp "$mode_dir/router.php" "app:/tmp/t25-router/router.php"; }
    $COMPOSE exec -d app sh -c "cd /tmp/t25-router && php -S 127.0.0.1:${ROUTER_PORT} router.php > /tmp/t25-router.log 2>&1"
    ROUTER_STARTED=1
    rm -rf "$mode_dir"
    sleep 1
    if ! $COMPOSE exec -T app sh -c "curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:${ROUTER_PORT}/mode/plain_text" 2>/dev/null | grep -q 200; then
        stop "controlled local test router did not start correctly -- refusing to proceed"
    fi
}

stop_router() {
    if [ "$ROUTER_STARTED" = "1" ]; then
        $COMPOSE exec -T app sh -c "pkill -f 'php -S 127.0.0.1:${ROUTER_PORT}' 2>/dev/null; rm -rf /tmp/t25-router" >/dev/null 2>&1
        ROUTER_STARTED=0
    fi
}

cleanup() {
    trap - EXIT
    log "==> cleanup"
    stop_router
    if [ -n "$ORIG_HOST_NOTIFICATION" ]; then
        set_vendor_config "host_notification" "$ORIG_HOST_NOTIFICATION"
    fi
    if [ -n "$ORIG_UPDATE_SERVER" ]; then
        set_vendor_config "update_server" "$ORIG_UPDATE_SERVER"
    fi
    force_cache_stale
    [ -n "$COOKIEJAR" ] && rm -f "$COOKIEJAR"
}
trap cleanup EXIT

# --- 0. Safety guards -------------------------------------------------------

log "==> checking required containers"
ALL_UP=1
for svc in app db; do
    if ! $COMPOSE ps "$svc" 2>/dev/null | grep -q "Up"; then
        ALL_UP=0
    fi
done
if [ "$ALL_UP" != "1" ]; then
    bad "containers healthy" "app/db not Up -- run 'make up' first"
    cleanup; trap - EXIT; exit 1
fi
ok "containers healthy" "app, db Up"

: "${DB_USER:?DB_USER must be set (source .env first)}"
: "${DB_PASSWORD:?DB_PASSWORD must be set (source .env first)}"
: "${DB_NAME:?DB_NAME must be set (source .env first)}"

# --- 1. Log in, back up real vendor config -----------------------------

COOKIEJAR="$(mktemp)"
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${TEST_PASSWORD}');" 2>/dev/null | tr -d '\r')"
db_query "UPDATE users SET password = '${TEST_HASH}' WHERE name = '${TEST_USER}';" >&2
http_login
ok "authenticated session" "logged in as ${TEST_USER}"

ORIG_HOST_NOTIFICATION="$(db_query "SELECT config_value FROM core_config WHERE config_module='default' AND config_name='host_notification';")"
ORIG_UPDATE_SERVER="$(db_query "SELECT config_value FROM core_config WHERE config_module='default' AND config_name='update_server';")"
if [ -z "$ORIG_HOST_NOTIFICATION" ] || [ -z "$ORIG_UPDATE_SERVER" ]; then
    stop "could not read the existing host_notification/update_server config rows -- refusing to proceed without a value to restore"
fi
ok "vendor config backed up" "host_notification and update_server originals captured for restoration"

start_router
ok "controlled local test router started" "docker/external-content-test/router.php on 127.0.0.1:${ROUTER_PORT}, never the real vendor"

# --- 2. Iteration 1 -- single-notification view (NotificationsController.php) --

before="$(fatal_count)"
set_vendor_config "host_notification" "http://127.0.0.1:${ROUTER_PORT}/mode/xss_notif_single"
body="$(mktemp)"
httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' "${BASE_URL}/index.php/default/notifications?id=1")"
after="$(fatal_count)"

if [ "$httpcode" = "200" ] && [ "$before" = "$after" ] \
    && ! grep -q "<script>alert(1)</script>" "$body" \
    && ! grep -q "<img src=x onerror=" "$body" \
    && ! grep -q "<svg/onload=" "$body" \
    && ! grep -q 'href="javascript:alert(1)"' "$body" \
    && grep -q "&lt;script&gt;alert(1)&lt;/script&gt;" "$body"; then
    ok "iter1: single-notification title/from/message escaped" "HTTP 200, raw <script>/<img onerror>/<svg onload>/javascript: href all absent, escaped form present, fatals ${before}->${after}"
else
    bad "iter1: single-notification title/from/message escaped" "HTTP ${httpcode}, fatals ${before}->${after} -- see $body"
fi
rm -f "$body"

# --- 3. Iteration 2 -- "all notifications" table (notifications/index.phtml) --

before="$(fatal_count)"
force_cache_stale
set_vendor_config "host_notification" "http://127.0.0.1:${ROUTER_PORT}/mode/xss_notif_list"
body="$(mktemp)"
httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' "${BASE_URL}/index.php/default/notifications?id=all")"
after="$(fatal_count)"

if [ "$httpcode" = "200" ] && [ "$before" = "$after" ] \
    && ! grep -q "<script>alert(1)</script>" "$body" \
    && ! grep -q "<img src=x onerror=" "$body" \
    && grep -q "&lt;script&gt;alert(1)&lt;/script&gt;" "$body" \
    && grep -q "notifications?id=1001" "$body" \
    && grep -q "notifications?id=1002" "$body"; then
    ok "iter2: notifications table escaped, ids intact" "HTTP 200, raw markup absent, escaped form present, both fixture ids (1001/1002) reachable as safe href values, fatals ${before}->${after}"
else
    bad "iter2: notifications table escaped, ids intact" "HTTP ${httpcode}, fatals ${before}->${after} -- see $body"
fi

if grep -q '{&quot;nested&quot;:&quot;looks-like-json&quot;,&quot;evil&quot;:&quot;&lt;script&gt;alert(2)&lt;/script&gt;&quot;}' "$body"; then
    ok "iter2: nested JSON-looking title single-encoded, not double-decoded" "the JSON-shaped title string itself renders as inert single-encoded text"
else
    bad "iter2: nested JSON-looking title single-encoded, not double-decoded" "expected exact single-encoded nested-JSON marker not found -- see $body"
fi
rm -f "$body"

# --- 4. Iteration 3 -- changelog (Snep_Version::getChangelog / newversion) --

before="$(fatal_count)"
set_vendor_config "update_server" "http://127.0.0.1:${ROUTER_PORT}/mode/xss_version"
body="$(mktemp)"
httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' "${BASE_URL}/index.php/newversion")"
after="$(fatal_count)"

if [ "$httpcode" = "200" ] && [ "$before" = "$after" ] \
    && ! grep -q "<script>alert(1)</script>" "$body" \
    && grep -q "&lt;script&gt;alert(1)&lt;/script&gt;" "$body" \
    && grep -q "Line one<br" "$body"; then
    ok "iter3: changelog escaped, line breaks preserved" "HTTP 200, raw <script> absent, escaped form present, <br /> line-break formatting intact, fatals ${before}->${after}"
else
    bad "iter3: changelog escaped, line breaks preserved" "HTTP ${httpcode}, fatals ${before}->${after} -- see $body"
fi
rm -f "$body"

# --- 5. Iteration 4 -- new_version (layout.phtml text node + systemstatus JS) --

before="$(fatal_count)"
force_cache_stale
body="$(mktemp)"
httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' "${BASE_URL}/index.php/default/systemstatus")"
after="$(fatal_count)"

if [ "$httpcode" = "200" ] && [ "$before" = "$after" ] \
    && ! grep -q "<script>alert(1)</script>" "$body" \
    && ! grep -q '</script>alert' "$body" \
    && grep -q 'var new_version = "999.999.999\\u003Cscript\\u003E' "$body"; then
    ok "iter4: new_version JS-string context neutralized" "HTTP 200, json_encode()-with-HEX-flags output present, no raw <script>/breakout, fatals ${before}->${after}"
else
    bad "iter4: new_version JS-string context neutralized" "HTTP ${httpcode}, fatals ${before}->${after} -- see $body"
fi
rm -f "$body"

body="$(mktemp)"
httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' "${BASE_URL}/index.php/default/extensions")"
if [ "$httpcode" = "200" ] && ! grep -q "<script>alert(1)</script>" "$body"; then
    ok "iter4: shared layout (layout.phtml) still renders safely" "HTTP 200 on an unrelated layout-rendered page, new_version text-node escape() call does not error even though the property is unset on this page"
else
    bad "iter4: shared layout (layout.phtml) still renders safely" "HTTP ${httpcode} -- see $body"
fi
rm -f "$body"

# --- 6. Iteration 5 -- Announce client-side sink (static source assertion) --
#
# The dynamic claim (the browser never actually calls
# setAttribute("href","javascript:...")) cannot be proven by a server-
# output assertion -- the vulnerable/fixed code runs client-side. This
# section proves what CAN be proven deterministically without a
# browser: the shipped JS contains the scheme-validation fix guarding
# both setAttribute calls, and the fixture endpoint serves the exact
# malicious payload unmodified. The dynamic behavior was verified once,
# interactively (Claude in Chrome), during implementation -- see
# docs/tasks/0025-vendor-content-xss-hardening.md §9/§21 for that
# evidence; this is the explicit gap-report required by this task's
# own §15 instruction.

js_body="$(mktemp)"
js_httpcode="$(curl -sS -o "$js_body" -w '%{http_code}' "${BASE_URL}/includes/javascript/notifications.js")"
if [ "$js_httpcode" = "200" ] \
    && grep -q "function isSafeAnnounceUrl" "$js_body" \
    && grep -q 'isSafeAnnounceUrl(data.link) && isSafeAnnounceUrl(data.image)' "$js_body"; then
    ok "iter5: shipped notifications.js contains the scheme-validation fix" "isSafeAnnounceUrl() defined and guards both setAttribute(href/src) calls -- static source assertion only, see gap note above"
else
    bad "iter5: shipped notifications.js contains the scheme-validation fix" "HTTP ${js_httpcode} -- fix not found in served JS"
fi
rm -f "$js_body"

announce_body="$(mktemp)"
announce_httpcode="$($COMPOSE exec -T app sh -c "curl -sS -o /tmp/t25-announce.json -w '%{http_code}' http://127.0.0.1:${ROUTER_PORT}/mode/xss_announce" 2>/dev/null)"
$COMPOSE cp "app:/tmp/t25-announce.json" "$announce_body" 2>/dev/null
if [ "$announce_httpcode" = "200" ] && grep -q "javascript:alert(document.cookie)" "$announce_body"; then
    ok "iter5: announce fixture endpoint serves the malicious payload unmodified" "confirms this test is exercising the real fixture, not a simplified stand-in"
else
    bad "iter5: announce fixture endpoint serves the malicious payload unmodified" "HTTP ${announce_httpcode} -- see $announce_body"
fi
rm -f "$announce_body"

# --- 7. Double-escaping / plain-text fidelity (§17) -------------------------
#
# The "all" (cached, getAll()) path never populates ->from (a pre-
# existing TASK-0024 gap, documented separately, not this task's to
# fix -- see docs/tasks/0025-vendor-content-xss-hardening.md §3) -- so
# the `from`-field check below uses the single-notification (live,
# getNotification()) path instead, which does receive every field
# straight from the vendor payload. title/message are checked via the
# "all" (cached) path, which does populate both.

before="$(fatal_count)"
force_cache_stale
set_vendor_config "host_notification" "http://127.0.0.1:${ROUTER_PORT}/mode/plain_text"
body="$(mktemp)"
httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' "${BASE_URL}/index.php/default/notifications?id=all")"
after="$(fatal_count)"

# Single-level encoding only: &amp; not &amp;amp;, &lt; not &amp;lt;, etc.
if [ "$httpcode" = "200" ] && [ "$before" = "$after" ] \
    && grep -q "Café résumé" "$body" \
    && ! grep -q "&amp;amp;" "$body" \
    && ! grep -q "&amp;lt;" "$body" \
    && ! grep -q "&amp;quot;" "$body" \
    && grep -q 'Quotes: &quot;double&quot;' "$body"; then
    ok "no double-escaping across cache/read/render (title/message)" "ordinary UTF-8/quotes render as single-level entities, human-readable, not re-encoded"
else
    bad "no double-escaping across cache/read/render (title/message)" "HTTP ${httpcode}, fatals ${before}->${after} -- see $body"
fi
rm -f "$body"

before="$(fatal_count)"
set_vendor_config "host_notification" "http://127.0.0.1:${ROUTER_PORT}/mode/plain_text_single"
body="$(mktemp)"
httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' "${BASE_URL}/index.php/default/notifications?id=2001")"
after="$(fatal_count)"
if [ "$httpcode" = "200" ] && [ "$before" = "$after" ] \
    && grep -q "Ops &amp; Support" "$body" \
    && ! grep -q "&amp;amp;" "$body"; then
    ok "no double-escaping across cache/read/render (from, live path)" "the & in a vendor 'from' field renders as a single &amp;, not &amp;amp;"
else
    bad "no double-escaping across cache/read/render (from, live path)" "HTTP ${httpcode}, fatals ${before}->${after} -- see $body"
fi
rm -f "$body"

print_report
cleanup
trap - EXIT
[ "$FAIL" -eq 0 ]
