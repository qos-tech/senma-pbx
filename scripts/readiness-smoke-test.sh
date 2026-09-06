#!/bin/bash
#
# Safe, non-mutating regression coverage for the readiness contract
# (TASK-0033E).
#
# Included in `make regression` -- unlike scripts/
# readiness-failure-smoke-test.sh (which stops db/asterisk, drops the
# DB schema in an isolated project, and injects AMI/WSS/transport
# failures; deliberately kept out of default regression -- see that
# script's own header). This suite never stops a core service and
# never mutates persisted state -- it only:
#   1. asserts all four containers are currently `healthy` (the
#      READY signal per this task's own HEALTHCHECK = READINESS model);
#   2. re-invokes each of the three dedicated healthcheck scripts
#      directly and asserts each reports READY/exit 0 (the same
#      scripts Docker itself calls on an interval);
#   3. asserts the AMI and WSS conditions are actually PART of
#      Asterisk's reported readiness on this install (not merely
#      that they pass, but that the script's own contract requires
#      them -- see docker/healthcheck-asterisk.sh's own header);
#   4. asserts no secret value appears in any `docker inspect`
#      health log or healthcheck script output;
#   5. performs a full-stack `docker compose restart` (the same class
#      of operation scripts/restart-smoke-test.sh already exercises in
#      normal regression) and asserts every service reconverges to
#      healthy within a bounded wait.
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
log() { harness_log "$@"; }

log "==> checking required containers"
harness_require_containers app asterisk db provider
harness_require_env DB_PASSWORD DB_ROOT_PASSWORD AMI_PASSWORD

container_health() { $COMPOSE ps "$1" --format '{{.Health}}' 2>/dev/null; }

# --- 1. healthy stack reaches READY ------------------------------------------
log "==> 1: all core containers report healthy"
ALL_HEALTHY=1
for svc in app asterisk db provider; do
    h="$(container_health "$svc")"
    if [ "$h" != "healthy" ]; then
        ALL_HEALTHY=0
        harness_log "  $svc: $h (expected healthy)"
    fi
done
if [ "$ALL_HEALTHY" -eq 1 ]; then
    harness_ok "1: all core containers healthy" "app, asterisk, db, provider all report healthy"
else
    harness_bad "1: all core containers healthy" "at least one service is not healthy -- see log above"
fi

# --- 2. each dedicated healthcheck script reports READY on demand -----------
log "==> 2: dedicated healthcheck scripts report READY directly"
DB_OUT="$($COMPOSE exec -T db bash /usr/local/bin/healthcheck-db.sh 2>&1)"; DB_RC=$?
APP_OUT="$($COMPOSE exec -T app bash /usr/local/bin/healthcheck-app.sh 2>&1)"; APP_RC=$?
AST_OUT="$($COMPOSE exec -T asterisk bash /usr/local/bin/healthcheck-asterisk.sh 2>&1)"; AST_RC=$?

if [ "$DB_RC" -eq 0 ] && printf '%s' "$DB_OUT" | grep -q "^READY:"; then
    harness_ok "2a: healthcheck-db.sh reports READY" "$DB_OUT"
else
    harness_bad "2a: healthcheck-db.sh reports READY" "exit $DB_RC: $DB_OUT"
fi
if [ "$APP_RC" -eq 0 ] && printf '%s' "$APP_OUT" | grep -q "^READY:"; then
    harness_ok "2b: healthcheck-app.sh reports READY" "$APP_OUT"
else
    harness_bad "2b: healthcheck-app.sh reports READY" "exit $APP_RC: $APP_OUT"
fi
if [ "$AST_RC" -eq 0 ] && printf '%s' "$AST_OUT" | grep -q "^READY:"; then
    harness_ok "2c: healthcheck-asterisk.sh reports READY" "$AST_OUT"
else
    harness_bad "2c: healthcheck-asterisk.sh reports READY" "exit $AST_RC: $AST_OUT"
fi

# --- 3/4. AMI and WSS are actually part of the reported invariant -----------
log "==> 3/4: AMI and WSS conditions are part of Asterisk's own readiness contract"
if printf '%s' "$AST_OUT" | grep -q "AMI OK"; then
    harness_ok "3: AMI is part of the reported invariant" "healthcheck-asterisk.sh's own READY line names AMI OK, not merely silent"
else
    harness_bad "3: AMI is part of the reported invariant" "expected 'AMI OK' in: $AST_OUT"
fi
if printf '%s' "$AST_OUT" | grep -q "wss"; then
    harness_ok "4: WSS transport is recognized/required" "declared wss transport present in the reported transport list: $AST_OUT"
else
    harness_log "4: no wss transport declared on this install -- WSS requirement is correctly conditional, not asserted here (see docker/healthcheck-asterisk.sh's own header)"
fi

# --- 5. no secret leakage -----------------------------------------------------
log "==> 5: no secret leakage in health output"
DB_HEALTH_LOG="$(docker inspect mag-pbx-db-1 --format '{{json .State.Health.Log}}' 2>/dev/null)"
APP_HEALTH_LOG="$(docker inspect mag-pbx-app-1 --format '{{json .State.Health.Log}}' 2>/dev/null)"
AST_HEALTH_LOG="$(docker inspect mag-pbx-asterisk-1 --format '{{json .State.Health.Log}}' 2>/dev/null)"
DISCLOSED=0
for v in "$DB_PASSWORD" "$DB_ROOT_PASSWORD" "$AMI_PASSWORD"; do
    for blob in "$DB_HEALTH_LOG" "$APP_HEALTH_LOG" "$AST_HEALTH_LOG" "$DB_OUT" "$APP_OUT" "$AST_OUT"; do
        printf '%s' "$blob" | grep -qF "$v" && DISCLOSED=1
    done
done
# Also confirm the stored healthcheck COMMAND itself (not just its
# output) never contains a secret -- `docker inspect .Config.Healthcheck.Test`
# must show the fixed script invocation, never a resolved value.
for c in mag-pbx-db-1 mag-pbx-app-1 mag-pbx-asterisk-1; do
    test_json="$(docker inspect "$c" --format '{{json .Config.Healthcheck.Test}}' 2>/dev/null)"
    for v in "$DB_PASSWORD" "$DB_ROOT_PASSWORD" "$AMI_PASSWORD"; do
        printf '%s' "$test_json" | grep -qF "$v" && DISCLOSED=1
    done
done
if [ "$DISCLOSED" -eq 0 ]; then
    harness_ok "5: no secret disclosure in health output" "grepped health logs, script output, and stored healthcheck commands for all three live secrets, none found"
else
    harness_bad "5: no secret disclosure in health output" "a secret value appeared verbatim somewhere in health output/command"
fi

# --- 6. full-stack restart convergence ---------------------------------------
log "==> 6: full-stack restart convergence"
$COMPOSE restart >&2
all_healthy() {
    for svc in app asterisk db provider; do
        [ "$(container_health "$svc")" = "healthy" ] || return 1
    done
    return 0
}
if harness_retry 20 3 -- all_healthy; then
    harness_ok "6: full-stack restart reconverges" "all four services healthy again within 60s"
else
    harness_bad "6: full-stack restart reconverges" "not all services healthy within 60s of 'docker compose restart'"
fi

# --- 7. post-restart ODBC/CDR recovery (TASK-0033E1) -------------------------
#
# This suite's own bare `docker compose restart` above is the confirmed
# root cause of TASK-0033E's REMAINING DEBT item 5: the plain `restart`
# subcommand bounces `asterisk` and `db` concurrently and does not
# re-evaluate the `asterisk -> db: condition: service_healthy` gate the
# way `docker compose up`/`start` do, so `res_odbc.so`'s one-shot,
# non-auto-reconnecting connection attempt can race a `db` that is not
# yet accepting connections -- live-reproduced 100% of trials during
# this task (docs/tasks/0033e1-asterisk-restart-harness-odbc-recovery.md).
# Without this step, a later suite in the SAME or a SUBSEQUENT
# `make regression` run (call-smoke/trunk-smoke/dialplan-legacy-closure)
# would inherit a broken ODBC connection and fail its own CDR assertions
# despite the call itself, the dialplan, and the trunk all being correct.
log "==> 7: post-restart ODBC/CDR recovery"
if harness_wait_asterisk_ready && harness_restore_asterisk_post_restart; then
    harness_ok "7: ODBC/CDR ready after full-stack restart" "active ODBC connection and cdr_adaptive_odbc.so Running confirmed (recovered via module reload if needed)"
else
    harness_bad "7: ODBC/CDR ready after full-stack restart" "Asterisk restarted successfully but ODBC/CDR runtime did not recover -- see log above for the reload attempts"
fi

harness_complete
