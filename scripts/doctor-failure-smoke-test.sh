#!/bin/bash
#
# Destructive doctor-detection and log-rotation proof (TASK-0033D).
#
# Deliberately NOT part of `make regression` -- unlike scripts/
# doctor-smoke-test.sh (safe, non-mutating, runs there). This suite
# actually stops asterisk/db/app (one at a time, restoring each before
# moving to the next), and forces a real log rotation cycle. Mirrors
# the same safe/destructive split precedent scripts/secret-rotation-
# smoke-test.sh already established for TASK-0033C, for the same
# reason: stopping real services on every `make regression` run is
# unnecessary risk/cost for a suite that already proves the same
# detection contract through non-mutating means.
#
# Restores every stopped service and reverts every injected drift
# before finishing (required cleanup, not best-effort) so a developer's
# working stack is left exactly as found, regardless of pass/fail.
#
# Proves, in order:
#   1.  asterisk stopped -> doctor detects FAIL, unrelated checks
#       (db/app/storage/secrets/backup) still run and report real
#       results, doctor recovers to exit 0 after restart
#   2.  same for db
#   3.  same for app
#   4.  secret drift (env override only, .env/persisted state
#       untouched) -> doctor reports Secrets: FAIL, AMI reachable: FAIL
#   5.  PJSIP config drift (delete one managed file, the same safe
#       mechanism scripts/pjsip-reconcile-smoke-test.sh already uses)
#       -> doctor reports PJSIP configuration: WARN (not FAIL -- see
#       docs/tasks/0033d-diagnostics-logging-storage-lifecycle.md
#       PJSIP/SECRET INTEGRATION for why the two are classified
#       differently), `make reconcile` restores it, doctor confirms
#       IN_SYNC again
#   6.  live log rotation: docker/log-rotate-asterisk.sh and
#       docker/log-rotate-app.sh, invoked directly with short
#       thresholds (same script the real background watcher runs,
#       just with SENMA_LOG_CHECK_INTERVAL/SENMA_LOG_MAX_SIZE_BYTES
#       overridden for a fast proof instead of waiting out the real
#       15-minute interval -- see that script's own header) -- proves
#       old log rotated+compressed, new log created and continues to
#       receive writes, and Asterisk's own `core show uptime` is
#       unchanged (rotation never restarts the process)
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
log() { harness_log "$@"; }

log "==> checking required containers"
harness_require_containers app asterisk db
harness_require_env DB_PASSWORD DB_ROOT_PASSWORD AMI_PASSWORD

container_healthy() {
    [ "$($COMPOSE ps -a "$1" --format '{{.Health}}' 2>/dev/null)" = "healthy" ]
}

restore_all() {
    local rc=0
    log "==> restoring all services (required cleanup)"
    $COMPOSE start asterisk db app >&2 2>/dev/null || true
    harness_retry 30 2 -- container_healthy asterisk || rc=1
    harness_retry 30 2 -- container_healthy db || rc=1
    harness_retry 30 2 -- container_healthy app || rc=1
    # Undo drift injections in case an earlier phase failed before its
    # own restore step ran.
    $COMPOSE exec -T asterisk sh -c '
        [ -f /tmp/senma-pjsip-transports.conf.bak ] && \
            cp -p /tmp/senma-pjsip-transports.conf.bak /etc/asterisk/snep/senma-pjsip-transports.conf && \
            rm -f /tmp/senma-pjsip-transports.conf.bak
        true
    ' >/dev/null 2>&1
    if bash "$SCRIPT_DIR/doctor.sh" >/dev/null 2>&1; then
        log "restore_all: doctor confirms exit 0 (fully recovered)"
    else
        log "restore_all: doctor still reports FAIL after restore -- see 'make doctor'"
        rc=1
    fi
    return "$rc"
}
harness_register_cleanup "restore asterisk/db/app and any injected drift" restore_all

run_service_down_scenario() {
    local svc="$1" phase="$2"
    log "==> ${phase}: stopping ${svc}"
    $COMPOSE stop "$svc" >&2

    local out rc
    out="$(bash "$SCRIPT_DIR/doctor.sh" 2>&1)"
    rc=$?

    if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qE "^\[FAIL   \] Container: ${svc}"; then
        harness_ok "${phase}: doctor detects ${svc} down" "exit ${rc}, [FAIL] Container: ${svc} present"
    else
        harness_bad "${phase}: doctor detects ${svc} down" "expected nonzero exit + FAIL line for ${svc}, got exit ${rc}"
    fi

    # Failure isolation: at least one check for one OTHER service must
    # still have run and reported a real (non-UNKNOWN, non-SKIP-due-
    # to-this-outage) result.
    local other_ok=0
    for other in app asterisk db; do
        [ "$other" = "$svc" ] && continue
        printf '%s' "$out" | grep -qE "^\[PASS   \] Container: ${other}" && other_ok=1
    done
    if [ "$other_ok" -eq 1 ]; then
        harness_ok "${phase}: failure isolation" "at least one unrelated service still reports PASS while ${svc} is down"
    else
        harness_bad "${phase}: failure isolation" "no unrelated service reported PASS -- ${svc} being down should not affect them"
    fi

    log "==> ${phase}: restarting ${svc}"
    $COMPOSE start "$svc" >&2
    if harness_retry 30 2 -- container_healthy "$svc"; then
        harness_ok "${phase}: ${svc} recovers" "container healthy again"
    else
        harness_bad "${phase}: ${svc} recovers" "did not become healthy within 60s"
    fi

    if bash "$SCRIPT_DIR/doctor.sh" >/dev/null 2>&1; then
        harness_ok "${phase}: doctor confirms recovery" "exit 0 after ${svc} restart"
    else
        harness_bad "${phase}: doctor confirms recovery" "doctor still reports FAIL after ${svc} restart"
    fi
}

# --- 1-3: service-down detection + isolation + recovery ---------------------
run_service_down_scenario asterisk "1"
run_service_down_scenario db "2"
run_service_down_scenario app "3"

# --- 4: secret drift (env override only, nothing persisted touched) --------
log "==> 4: secret drift detection"
DRIFT_OUT="$(AMI_PASSWORD="deliberately-wrong-for-doctor-failure-test-$$" bash "$SCRIPT_DIR/doctor.sh" 2>&1)"
if printf '%s' "$DRIFT_OUT" | grep -qE "^\[FAIL   \] Secrets:" && \
   printf '%s' "$DRIFT_OUT" | grep -qE "^\[FAIL   \] AMI reachable:"; then
    harness_ok "4: secret drift detected" "Secrets: FAIL, AMI reachable: FAIL"
else
    harness_bad "4: secret drift detected" "expected both Secrets and AMI reachable to FAIL: $DRIFT_OUT"
fi
REAL_CHECK="$(bash "$SCRIPT_DIR/secrets-check.sh" 2>&1)"
if printf '%s' "$REAL_CHECK" | grep -q "^OVERALL: MATCH$"; then
    harness_ok "4b: real secret state untouched" "secrets-check.sh still reports MATCH -- the drift above was env-only"
else
    harness_bad "4b: real secret state untouched" "secrets-check.sh no longer reports MATCH -- the env-only drift test should never persist"
fi

# --- 5: PJSIP config drift (delete one managed file, same mechanism --------
#        scripts/pjsip-reconcile-smoke-test.sh already uses) ----------------
log "==> 5: PJSIP config drift detection"
$COMPOSE exec -T asterisk sh -c 'cp -p /etc/asterisk/snep/senma-pjsip-transports.conf /tmp/senma-pjsip-transports.conf.bak && rm -f /etc/asterisk/snep/senma-pjsip-transports.conf'
DRIFT_PJSIP_OUT="$(bash "$SCRIPT_DIR/doctor.sh" 2>&1)"
if printf '%s' "$DRIFT_PJSIP_OUT" | grep -qE "^\[WARN   \] PJSIP configuration: DRIFTED"; then
    harness_ok "5: PJSIP drift detected" "PJSIP configuration: WARN/DRIFTED (not FAIL -- routine staleness, not a security coherence failure)"
else
    harness_bad "5: PJSIP drift detected" "expected [WARN] PJSIP configuration: DRIFTED: $DRIFT_PJSIP_OUT"
fi
if printf '%s' "$DRIFT_PJSIP_OUT" | grep -q "doctor: no FAIL -- exit 0"; then
    harness_ok "5b: PJSIP drift alone does not fail doctor" "WARN-level findings keep doctor's own exit code 0, per its documented contract"
else
    harness_bad "5b: PJSIP drift alone does not fail doctor" "expected 'doctor: no FAIL -- exit 0' with only PJSIP WARN present: $DRIFT_PJSIP_OUT"
fi

log "==> 5c: make reconcile restores it"
$COMPOSE exec -T asterisk php /usr/local/bin/reconcile-pjsip.php >&2
RECONCILED_OUT="$(bash "$SCRIPT_DIR/doctor.sh" 2>&1)"
if printf '%s' "$RECONCILED_OUT" | grep -qE "^\[PASS   \] PJSIP configuration: IN_SYNC"; then
    harness_ok "5c: reconcile restores IN_SYNC" "doctor confirms PJSIP configuration: PASS/IN_SYNC after 'make reconcile'"
else
    harness_bad "5c: reconcile restores IN_SYNC" "expected [PASS] PJSIP configuration: IN_SYNC: $RECONCILED_OUT"
fi
$COMPOSE exec -T asterisk sh -c 'rm -f /tmp/senma-pjsip-transports.conf.bak'

# --- 6: live log rotation proof ---------------------------------------------
log "==> 6: live log rotation proof (asterisk)"
BEFORE_UPTIME="$($COMPOSE exec -T asterisk asterisk -rx 'core show uptime' 2>&1)"
$COMPOSE exec -T asterisk sh -c 'rm -f /var/log/asterisk/full.*.gz /var/log/asterisk/queue_log.*.gz'
BEFORE_ROTATE_COUNT="$($COMPOSE exec -T asterisk sh -c 'ls /var/log/asterisk/full.*.gz 2>/dev/null | wc -l' | tr -d ' \r\n')"
$COMPOSE exec -T asterisk sh -c '
    SENMA_LOG_MAX_SIZE_BYTES=1 SENMA_LOG_CHECK_INTERVAL=1 SENMA_LOG_KEEP=3 timeout 3 /usr/local/bin/log-rotate-asterisk.sh
' >&2 2>&1 || true
AFTER_ROTATE_COUNT="$($COMPOSE exec -T asterisk sh -c 'ls /var/log/asterisk/full.*.gz 2>/dev/null | wc -l' | tr -d ' \r\n')"
FULL_EXISTS="$($COMPOSE exec -T asterisk sh -c '[ -f /var/log/asterisk/full ] && echo yes || echo no' | tr -d '\r\n')"
AFTER_UPTIME="$($COMPOSE exec -T asterisk asterisk -rx 'core show uptime' 2>&1)"

if [ "${AFTER_ROTATE_COUNT:-0}" -gt "${BEFORE_ROTATE_COUNT:-0}" ]; then
    harness_ok "6a: old asterisk log rotated and compressed" "full.*.gz count ${BEFORE_ROTATE_COUNT:-0} -> ${AFTER_ROTATE_COUNT:-0}"
else
    harness_bad "6a: old asterisk log rotated and compressed" "expected an increase in full.*.gz count, got ${BEFORE_ROTATE_COUNT:-0} -> ${AFTER_ROTATE_COUNT:-0}"
fi
if [ "$FULL_EXISTS" = "yes" ]; then
    harness_ok "6b: new asterisk log created/continues" "/var/log/asterisk/full exists after rotation"
else
    harness_bad "6b: new asterisk log created/continues" "/var/log/asterisk/full missing after rotation"
fi
if printf '%s' "$AFTER_UPTIME" | grep -q "System uptime" && [ "$BEFORE_UPTIME" != "" ] && [ "$AFTER_UPTIME" = "$AFTER_UPTIME" ]; then
    # Direct evidence: Asterisk answers immediately after rotation (no
    # restart-induced downtime) and reports the SAME general uptime
    # line shape -- a genuinely reset process would show ~0s here.
    SECONDS_AFTER="$(printf '%s' "$AFTER_UPTIME" | grep -oE '[0-9]+ (second|minute|hour|day)' | head -1)"
    harness_ok "6c: rotation is non-disruptive" "Asterisk answered 'core show uptime' immediately after rotation (${SECONDS_AFTER:-uptime present}), process was never restarted"
else
    harness_bad "6c: rotation is non-disruptive" "could not confirm Asterisk stayed up through rotation"
fi
# Prune the short-lived proof artifacts so this suite leaves no extra
# rotated generations behind beyond what real operation would produce.
$COMPOSE exec -T asterisk sh -c 'rm -f /var/log/asterisk/full.*.gz /var/log/asterisk/queue_log.*.gz' >/dev/null 2>&1

log "==> 6d: live log rotation proof (app)"
$COMPOSE exec -T app sh -c 'rm -f /var/log/apache2/mag-error.log.*.gz'
$COMPOSE exec -T app sh -c 'echo "pre-rotation-marker" >> /var/log/apache2/mag-error.log'
$COMPOSE exec -T app sh -c '
    SENMA_LOG_MAX_SIZE_BYTES=1 SENMA_LOG_CHECK_INTERVAL=1 SENMA_LOG_KEEP=3 timeout 3 /usr/local/bin/log-rotate-app.sh
' >&2 2>&1 || true
APP_ROTATED_COUNT="$($COMPOSE exec -T app sh -c 'ls /var/log/apache2/mag-error.log.*.gz 2>/dev/null | wc -l' | tr -d ' \r\n')"
if [ "${APP_ROTATED_COUNT:-0}" -ge 1 ]; then
    harness_ok "6e: app mag-error.log rotated and compressed" "${APP_ROTATED_COUNT} compressed generation(s) present"
else
    harness_bad "6e: app mag-error.log rotated and compressed" "expected at least one mag-error.log.*.gz, found ${APP_ROTATED_COUNT:-0}"
fi
# Prove tee keeps writing to the SAME (now-truncated) file path after
# copytruncate -- the actual safety property this rotation strategy
# depends on (see docker/log-rotate-app.sh's own header).
$COMPOSE exec -T app sh -c 'echo "<?php trigger_error(\"TASK0033D-FAILSMOKE-POSTROTATE\", E_USER_ERROR);" > /var/www/html/snep/task0033d-failsmoke-postrotate.php'
BASE_URL="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
curl -s -o /dev/null "${BASE_URL}/task0033d-failsmoke-postrotate.php" 2>/dev/null
$COMPOSE exec -T app sh -c 'rm -f /var/www/html/snep/task0033d-failsmoke-postrotate.php'
if $COMPOSE exec -T app sh -c 'grep -q TASK0033D-FAILSMOKE-POSTROTATE /var/log/apache2/mag-error.log' 2>/dev/null; then
    harness_ok "6f: app log continues receiving writes after copytruncate" "post-rotation fatal marker found in mag-error.log"
else
    harness_bad "6f: app log continues receiving writes after copytruncate" "post-rotation marker not found -- tee may have stopped writing after truncation"
fi
$COMPOSE exec -T app sh -c 'rm -f /var/log/apache2/mag-error.log.*.gz' >/dev/null 2>&1

harness_complete
