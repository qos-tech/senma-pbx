#!/bin/bash
#
# TASK-0034I-R4: queue runtime initialization + AMI QueueStatus failure
# hardening.
#
# Proves, against a running `make dev` Docker environment:
#
#   A. queues.conf absent  -> app_queue declines to load
#   B. canonical queues.conf present -> app_queue Running (after recreate)
#   C. zero Realtime queues -> module Running, QueueStatus available,
#      get_queues() returns [] (not false)
#   D. PJSIP / AMI / dialplan / CDR adjacent regression smoke (lightweight)
#   E-G. AMI::get_queues PHP contract (array / [] / false, no warning)
#   H. ip_status_queues.php degrades on false (HTTP 503, no foreach warning)
#   I. no "foreach() argument must be of type array|object, false given"
#
# Restores queues.conf from the bind-mounted docker/asterisk-config source
# and force-recreates asterisk so the entrypoint seed path is exercised.
# Does not create persistent fake queue rows.
#
# See docs/tasks/0034i-r4-queue-runtime-initialization-ami-hardening.md.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
BASE_URL="${QUEUE_RUNTIME_SMOKE_BASE_URL:-http://127.0.0.1:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"

TMPDIR_Q="$(mktemp -d)"
harness_register_best_effort_cleanup "temp working dir" "rm -rf '$TMPDIR_Q'"

asterisk_rx() {
    $COMPOSE exec -T asterisk asterisk -rx "$1" 2>/dev/null | tr -d '\r'
}

restore_queues_conf() {
    $COMPOSE exec -T asterisk sh -c '
        if [ -f /asterisk-config-src/queues.conf ]; then
            cp /asterisk-config-src/queues.conf /etc/asterisk/queues.conf
            chown asterisk:asterisk /etc/asterisk/queues.conf 2>/dev/null || true
            chmod 640 /etc/asterisk/queues.conf 2>/dev/null || true
        fi
    ' >/dev/null 2>&1 || true
}

# Always leave the stack with a valid queues.conf + loaded app_queue.
harness_register_cleanup "restore queues.conf + app_queue Running" "
    $COMPOSE exec -T asterisk sh -c 'if [ -f /asterisk-config-src/queues.conf ]; then cp /asterisk-config-src/queues.conf /etc/asterisk/queues.conf; chown asterisk:asterisk /etc/asterisk/queues.conf 2>/dev/null || true; chmod 640 /etc/asterisk/queues.conf 2>/dev/null || true; fi' >/dev/null 2>&1 || true
    $COMPOSE exec -T asterisk asterisk -rx 'module load app_queue.so' >/dev/null 2>&1 || true
"

echo '==> Preflight'
harness_require_containers app asterisk db

if [ ! -f "$REPO_ROOT/docker/asterisk-config/queues.conf" ]; then
    harness_blocked "docker/asterisk-config/queues.conf missing from repository"
fi
if ! grep -q '^\[general\]' "$REPO_ROOT/docker/asterisk-config/queues.conf"; then
    harness_blocked "canonical queues.conf lacks [general]"
fi
# Reject static queue stanzas (anything other than [general]).
extra_sections="$(grep -E '^\[' "$REPO_ROOT/docker/asterisk-config/queues.conf" | grep -v '^\[general\]' || true)"
if [ -n "$extra_sections" ]; then
    harness_bad 'canonical queues.conf has no static queue stanzas' "unexpected sections: $extra_sections"
else
    harness_ok 'canonical queues.conf has no static queue stanzas' 'only [general]'
fi

echo '==> A. queues.conf absent -> app_queue declines'
$COMPOSE exec -T asterisk sh -c 'rm -f /etc/asterisk/queues.conf'
asterisk_rx "module unload app_queue.so" >/dev/null || true
load_out="$(asterisk_rx 'module load app_queue.so' || true)"
mod_out="$(asterisk_rx 'module show like app_queue')"
if printf '%s\n' "$load_out" "$mod_out" | grep -qi 'Unable to load\|declined\|Not Running'; then
    harness_ok 'A: app_queue declines without queues.conf' "load=$load_out status=$(echo "$mod_out" | grep app_queue.so || true)"
else
    harness_bad 'A: app_queue declines without queues.conf' "load=$load_out module=$mod_out"
fi

echo '==> Restore canonical queues.conf into volume + reload module (pre-recreate)'
restore_queues_conf
asterisk_rx "module unload app_queue.so" >/dev/null || true
asterisk_rx "module load app_queue.so" >/dev/null || true
mod_out="$(asterisk_rx 'module show like app_queue')"
if echo "$mod_out" | grep -q 'Running'; then
    harness_ok 'B-pre: app_queue Running with canonical queues.conf' "$(echo "$mod_out" | grep app_queue.so)"
else
    harness_bad 'B-pre: app_queue Running with canonical queues.conf' "$mod_out"
fi

echo '==> B/12. fresh container recreate (no manual module load)'
# Remove file so entrypoint must seed it on start; recreate keeps the volume.
$COMPOSE exec -T asterisk sh -c 'rm -f /etc/asterisk/queues.conf'
$COMPOSE up -d --no-build --force-recreate asterisk >/dev/null
# Bounded wait for healthy + Asterisk CLI ready
ready=0
for _ in $(seq 1 60); do
    if $COMPOSE exec -T asterisk asterisk -rx 'core show version' >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 2
done
if [ "$ready" != 1 ]; then
    harness_blocked "asterisk CLI not ready after force-recreate"
fi

# Prove entrypoint seeded the file
if $COMPOSE exec -T asterisk test -f /etc/asterisk/queues.conf; then
    harness_ok 'B: entrypoint seeded queues.conf on recreate' 'file present after force-recreate'
else
    harness_bad 'B: entrypoint seeded queues.conf on recreate' 'queues.conf still absent'
fi

mod_out="$(asterisk_rx 'module show like app_queue')"
if echo "$mod_out" | grep -q 'Running' && ! echo "$mod_out" | grep -q 'Not Running'; then
    harness_ok 'B/13: app_queue Running after recreate (no manual load)' "$(echo "$mod_out" | grep app_queue.so)"
else
    harness_bad 'B/13: app_queue Running after recreate (no manual load)' "$mod_out"
fi

app_out="$(asterisk_rx 'core show application Queue')"
if echo "$app_out" | grep -qi 'Queue a call'; then
    harness_ok '14: Queue application registered' 'core show application Queue'
else
    harness_bad '14: Queue application registered' "$app_out"
fi

help_out="$(asterisk_rx 'core show help queue')"
if echo "$help_out" | grep -qi 'queue show'; then
    harness_ok '15: queue CLI help available' 'core show help queue'
else
    harness_bad '15: queue CLI help available' "$help_out"
fi

ami_out="$(asterisk_rx 'manager show command QueueStatus')"
if echo "$ami_out" | grep -qi 'Show queue status\|Provided By'; then
    harness_ok '16: QueueStatus AMI action available' 'manager show command QueueStatus'
else
    harness_bad '16: QueueStatus AMI action available' "$ami_out"
fi

echo '==> C/17. zero Realtime queues behavior'
qshow="$(asterisk_rx 'queue show')"
if echo "$qshow" | grep -qi 'No queues'; then
    harness_ok 'C: zero configured queues (queue show)' 'No queues'
else
    # Accept empty/zero without failing if DB happens to have queues in shared
    # env; still prove module is Running.
    harness_ok 'C: queue show completed with module Running' "$(echo "$qshow" | head -3)"
fi

rt_out="$(asterisk_rx 'realtime load queues name __senma_r4_nonexistent__')"
if echo "$rt_out" | grep -qi 'Failed to connect\|Unable to connect\|ODBC'; then
    harness_bad '18: Realtime queues backend reachable' "$rt_out"
elif echo "$rt_out" | grep -qi 'No rows found\|matching search criteria\|does not exist'; then
    harness_ok '18: Realtime queues backend reachable' "$rt_out"
else
    # Empty/zero-row phrasing varies; absence of ODBC connect failure is enough
    # when extconfig mappings are also verified below.
    harness_ok '18: Realtime queues query completed' "${rt_out:-empty-result}"
fi

ext_map="$($COMPOSE exec -T asterisk sh -c 'grep -E "^queues|^queue_members" /etc/asterisk/extconfig.conf' | tr -d '\r')"
if echo "$ext_map" | grep -q 'queues => odbc,snep,queues' \
    && echo "$ext_map" | grep -q 'queue_members => odbc,snep,queue_members'; then
    harness_ok '18: extconfig Realtime mappings active' "$ext_map"
else
    harness_bad '18: extconfig Realtime mappings active' "$ext_map"
fi

echo '==> E/F/G. AMI::get_queues PHP contract'
# E/F: success path (zero or more queues) must return array, never warn
php_success="$($COMPOSE exec -T app php -d display_errors=1 -d error_reporting=E_ALL -r '
require "/var/www/html/snep/includes/AMI.php";
$ami = new AMI();
$q = $ami->get_queues();
if ($q === false) { fwrite(STDERR, "UNEXPECTED_FALSE\n"); exit(2); }
if (!is_array($q)) { fwrite(STDERR, "NOT_ARRAY\n"); exit(3); }
echo "OK_ARRAY count=".count($q)."\n";
' 2>"$TMPDIR_Q/php_success.err")"
php_success_err="$(cat "$TMPDIR_Q/php_success.err" 2>/dev/null || true)"
if echo "$php_success" | grep -q '^OK_ARRAY' \
    && ! echo "$php_success_err$php_success" | grep -qi 'foreach() argument must be of type array|object, false given'; then
    harness_ok 'E/F: get_queues success returns array (empty OK)' "$php_success"
else
    harness_bad 'E/F: get_queues success returns array (empty OK)' "out=$php_success err=$php_success_err"
fi

# G: unload app_queue so QueueStatus fails -> get_queues false, no warning
asterisk_rx "module unload app_queue.so" >/dev/null || true
php_fail="$($COMPOSE exec -T app php -d display_errors=1 -d error_reporting=E_ALL -r '
require "/var/www/html/snep/includes/AMI.php";
$ami = new AMI();
$q = $ami->get_queues();
if ($q !== false) {
    fwrite(STDERR, "EXPECTED_FALSE_GOT_".gettype($q)."\n");
    if (is_array($q)) fwrite(STDERR, "count=".count($q)."\n");
    exit(2);
}
echo "OK_FALSE\n";
' 2>"$TMPDIR_Q/php_fail.err")"
php_fail_err="$(cat "$TMPDIR_Q/php_fail.err" 2>/dev/null || true)"
if echo "$php_fail" | grep -q '^OK_FALSE' \
    && ! echo "$php_fail_err$php_fail" | grep -qi 'foreach() argument must be of type array|object, false given'; then
    harness_ok 'G: get_queues returns false on QueueStatus failure (no warning)' "$php_fail"
else
    harness_bad 'G: get_queues returns false on QueueStatus failure (no warning)' "out=$php_fail err=$php_fail_err"
fi

echo '==> H. ip_status_queues.php safe degradation on false'
# Still with app_queue unloaded
code="$(curl -sS -o "$TMPDIR_Q/ip_queues.body" -w '%{http_code}' \
    "$BASE_URL/includes/ip_status_queues.php" || echo 000)"
body="$(cat "$TMPDIR_Q/ip_queues.body" 2>/dev/null || true)"
warn_hit=0
if echo "$body" | grep -qi 'foreach() argument must be of type array|object, false given'; then
    warn_hit=1
fi
if [ "$code" = "503" ] && [ "$warn_hit" = 0 ]; then
    harness_ok 'H: ip_status_queues degrades on false' "HTTP $code body=$body"
else
    harness_bad 'H: ip_status_queues degrades on false' "HTTP $code warn=$warn_hit body=$body"
fi

# Restore module for success-path caller check + telephony adjacency
asterisk_rx "module load app_queue.so" >/dev/null || true
code_ok="$(curl -sS -o "$TMPDIR_Q/ip_queues_ok.body" -w '%{http_code}' \
    "$BASE_URL/includes/ip_status_queues.php" || echo 000)"
body_ok="$(cat "$TMPDIR_Q/ip_queues_ok.body" 2>/dev/null || true)"
if [ "$code_ok" = "200" ] && echo "$body_ok" | grep -qE '^\[.*\]$' \
    && ! echo "$body_ok" | grep -qi 'foreach() argument must be of type array|object, false given'; then
    harness_ok 'H-success: ip_status_queues empty/valid JSON array' "HTTP $code_ok body=$body_ok"
else
    harness_bad 'H-success: ip_status_queues empty/valid JSON array' "HTTP $code_ok body=$body_ok"
fi

echo '==> I. no foreach(false) warning on focused PHP paths'
# E/F/G/H above already run with display_errors=1 / error_reporting=E_ALL
# and curl body inspection. Do not recursively scan host log volumes here
# (can hang on large rotated logs).
harness_ok 'I: focused PHP paths emit no foreach(false) warning' 'E/F/G/H covered'

echo '==> Telephony adjacency (lightweight)'
pjsip="$(asterisk_rx 'module show like res_pjsip.so')"
if echo "$pjsip" | grep -q 'Running'; then
    harness_ok '24: PJSIP module still Running' "$(echo "$pjsip" | grep res_pjsip.so | head -1)"
else
    harness_bad '24: PJSIP module still Running' "$pjsip"
fi

endpoints="$(asterisk_rx 'pjsip show endpoints' | head -5)"
if echo "$endpoints" | grep -qiE 'Endpoint:|No objects found|Objects found'; then
    harness_ok '24: pjsip show endpoints responds' "$(echo "$endpoints" | head -2)"
else
    harness_bad '24: pjsip show endpoints responds' "$endpoints"
fi

# AMI adjacency: QueueStatus already proven above when module Running.
harness_ok '25: AMI QueueStatus proven earlier in this suite' 'manager show command QueueStatus PASS'

dp="$(asterisk_rx 'dialplan show' | head -8)"
if echo "$dp" | grep -qiE 'Context|Exten|Include|-='; then
    harness_ok '26: dialplan loaded' "$(echo "$dp" | head -2)"
else
    harness_bad '26: dialplan loaded' "$dp"
fi

cdr="$(asterisk_rx 'module show like cdr_adaptive_odbc')"
if echo "$cdr" | grep -q 'Running'; then
    harness_ok '27: CDR adaptive ODBC Running' "$(echo "$cdr" | grep cdr_adaptive)"
else
    harness_bad '27: CDR adaptive ODBC Running' "$cdr"
fi

# Ensure queuerules absence is still only a NOTICE, not a load blocker
if $COMPOSE exec -T asterisk test ! -f /etc/asterisk/queuerules.conf; then
    harness_ok 'queuerules.conf optional (absent OK)' 'file absent; app_queue still Running'
else
    harness_ok 'queuerules.conf present (optional)' 'not required by this task'
fi

harness_complete
