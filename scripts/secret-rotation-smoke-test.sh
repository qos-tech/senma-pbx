#!/bin/bash
#
# Destructive, full secret-rotation proof (TASK-0033C).
#
# Deliberately NOT part of `make regression` -- unlike scripts/
# secrets-consistency-smoke-test.sh (safe, non-mutating, runs there).
# This suite actually rotates DB_PASSWORD, DB_ROOT_PASSWORD and
# AMI_PASSWORD on THIS installation's real, already-provisioned .env/
# DB volume/asterisk-etc volume -- exactly the "existing install", not
# a fresh one, this task's own acceptance criteria require. Mirrors the
# same safe/destructive split precedent scripts/backup-smoke-test.sh /
# scripts/backup-restore-dr-smoke-test.sh already established for
# TASK-0033A, for the same reason: mutating real credentials belongs
# behind an explicit target an operator chooses to run, not something
# that fires on every `make regression`.
#
# Rotates every secret back to its ORIGINAL value at the end (required
# cleanup, not best-effort) so a developer's working `.env`/install is
# left exactly as found, regardless of pass/fail.
#
# Proves, in order (see docs/tasks/0033c-secret-rotation-contract.md
# REGRESSION COVERAGE for the full rationale):
#   1.  initial state MATCH
#   2.  declared drift detected (DRIFT_DETECTED, exit 3)
#   3.  DB app password rotation (ROTATED_SUCCESSFULLY)
#   4.  old DB app password rejected
#   5.  new DB app password works
#   6.  Asterisk ODBC works
#   7.  DB root rotation (ROTATED_SUCCESSFULLY)
#   8.  old root password rejected
#   9.  new root password works
#   10. AMI rotation (ROTATED_SUCCESSFULLY)
#   11. old AMI password rejected
#   12. new AMI password works
#   13. runtime status survives (real authenticated HTTP page, real AMI call)
#   14. reconcile survives (`reconcile-check`)
#   15. backup survives (`make backup` succeeds post-rotation)
#   16. force-recreate preserves the new secrets
#   17. full-stack restart preserves the new secrets
#   18/19. controlled failure returns nonzero, no partial state (DB
#         unavailable; invalid secret format; asterisk unavailable
#         during AMI rotation -- see its own check for the actual,
#         documented recovery behavior)
#   20. no secret value ever appears in any captured output
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
# shellcheck source=lib/secrets-lib.sh
source "$SCRIPT_DIR/lib/secrets-lib.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
ENV_FILE="$REPO_ROOT/.env"
log() { harness_log "$@"; }

log "==> checking required containers"
harness_require_containers app asterisk db
harness_require_env DB_USER DB_PASSWORD DB_ROOT_PASSWORD AMI_USER AMI_PASSWORD

ORIG_DB_PASSWORD="$DB_PASSWORD"
ORIG_DB_ROOT_PASSWORD="$DB_ROOT_PASSWORD"
ORIG_AMI_PASSWORD="$AMI_PASSWORD"
ORIG_AMI_USER="$AMI_USER"
ORIG_DB_USER="$DB_USER"

ENV_BACKUP="$(mktemp)"
chmod 600 "$ENV_BACKUP"
cp "$ENV_FILE" "$ENV_BACKUP"

TAG="rotsmoke$$"
NEW_DB_PASSWORD="db-${TAG}"
NEW_DB_ROOT_PASSWORD="root-${TAG}"
NEW_AMI_PASSWORD="ami-${TAG}"

# REQUIRED cleanup (a failure here downgrades PASS to FAIL, correctly --
# leaving a developer's real .env/DB/AMI credentials rotated away from
# what they started with is not an acceptable "test cleanup failed, but
# whatever" outcome). Runs LAST (harness cleanup is reverse-order), so
# whatever state the run ended in, this attempts to converge every
# secret back to its original value and restore the exact original
# .env file content.
restore_original_secrets() {
    log "==> restoring original .env and rotating every secret back"
    cp "$ENV_BACKUP" "$ENV_FILE"
    set -a; . "$ENV_FILE"; set +a
    local rc=0
    ROTATE_SECRETS_CURRENT_ROOT_PASSWORD="$NEW_DB_ROOT_PASSWORD" \
        bash "$SCRIPT_DIR/rotate-secrets.sh" >&2 || rc=1
    # Belt-and-suspenders: if the DB root password ended up somewhere
    # this run didn't expect (e.g. an earlier phase failed before
    # reaching the root rotation), try both plausible current values so
    # cleanup still converges rather than leaving root's password
    # ambiguous for the next command to guess at.
    local final
    final="$(slib_db_root_auth_check db "$ORIG_DB_ROOT_PASSWORD")"
    if [ "$final" != "MATCH" ]; then
        ROTATE_SECRETS_CURRENT_ROOT_PASSWORD="$ORIG_DB_ROOT_PASSWORD" \
            bash "$SCRIPT_DIR/rotate-secrets.sh" --only db-root-password >&2 || true
        final="$(slib_db_root_auth_check db "$ORIG_DB_ROOT_PASSWORD")"
    fi
    [ "$final" = "MATCH" ] || rc=1
    rm -f "$ENV_BACKUP"
    return "$rc"
}
harness_register_cleanup "restore original .env and secrets" restore_original_secrets

ALL_OUTPUT_LOG="$(mktemp)"
harness_register_best_effort_cleanup "captured-output temp file" "rm -f '$ALL_OUTPUT_LOG'"
capture() { tee -a "$ALL_OUTPUT_LOG"; }

# --- 1. initial state MATCH -------------------------------------------------
log "==> 1: initial state"
BASELINE="$(bash "$SCRIPT_DIR/secrets-check.sh" 2>&1 | capture)"
if printf '%s' "$BASELINE" | grep -q "^OVERALL: MATCH$"; then
    harness_ok "1: initial state MATCH" "secrets-check.sh reports OVERALL: MATCH before any rotation"
else
    harness_blocked "initial state is not MATCH -- this installation is already drifted; run 'make secrets-check' and 'make rotate-secrets' manually before running this suite"
fi

# --- 2. declared drift detected ---------------------------------------------
log "==> 2: declaring new secrets in .env (drift, no rotation yet)"
sed -i.bak \
    -e "s|^DB_PASSWORD=.*|DB_PASSWORD=${NEW_DB_PASSWORD}|" \
    -e "s|^DB_ROOT_PASSWORD=.*|DB_ROOT_PASSWORD=${NEW_DB_ROOT_PASSWORD}|" \
    -e "s|^AMI_PASSWORD=.*|AMI_PASSWORD=${NEW_AMI_PASSWORD}|" \
    "$ENV_FILE"
rm -f "${ENV_FILE}.bak"
set -a; . "$ENV_FILE"; set +a

DRIFT_OUT="$(bash "$SCRIPT_DIR/secrets-check.sh" 2>&1 | capture)"
DRIFT_RC=$?
if [ "$DRIFT_RC" -eq 3 ] && printf '%s' "$DRIFT_OUT" | grep -q "^OVERALL: DRIFT_DETECTED$"; then
    harness_ok "2: declared drift detected" "secrets-check.sh exit 3, OVERALL: DRIFT_DETECTED"
else
    harness_bad "2: declared drift detected" "expected exit 3 / DRIFT_DETECTED, got exit $DRIFT_RC"
fi

# --- 7-9 (executed first). DB root password rotation ------------------------
# Executed BEFORE db-password: DB app password rotation authenticates
# as root using the CURRENTLY DECLARED DB_ROOT_PASSWORD (see
# docs/tasks/0033c-secret-rotation-contract.md ROTATION ORDERING) --
# since this suite declared BOTH new values in .env at once (item 2),
# root must already be at its new value before db-password rotation can
# use it. `rotate-secrets.sh` (no --only) enforces this same order
# internally; this suite calls each --only target directly to keep each
# proof point isolated, so it must respect the same order itself.
log "==> 7-9: DB root password rotation"
ROOTPW_OUT="$(ROTATE_SECRETS_CURRENT_ROOT_PASSWORD="$ORIG_DB_ROOT_PASSWORD" \
    bash "$SCRIPT_DIR/rotate-secrets.sh" --only db-root-password 2>&1 | capture)"
if printf '%s' "$ROOTPW_OUT" | grep -q "DB_ROOT_PASSWORD *ROTATED_SUCCESSFULLY"; then
    harness_ok "7: DB root password rotation" "ROTATED_SUCCESSFULLY"
else
    harness_bad "7: DB root password rotation" "did not report ROTATED_SUCCESSFULLY: $ROOTPW_OUT"
fi

OLD_ROOT_STATUS="$(slib_db_root_auth_check db "$ORIG_DB_ROOT_PASSWORD")"
[ "$OLD_ROOT_STATUS" = "DRIFT" ] \
    && harness_ok "8: old root password rejected" "auth check returned DRIFT" \
    || harness_bad "8: old root password rejected" "expected DRIFT, got $OLD_ROOT_STATUS"

NEW_ROOT_STATUS="$(slib_db_root_auth_check db "$NEW_DB_ROOT_PASSWORD")"
[ "$NEW_ROOT_STATUS" = "MATCH" ] \
    && harness_ok "9: new root password works" "auth check returned MATCH" \
    || harness_bad "9: new root password works" "expected MATCH, got $NEW_ROOT_STATUS"

# --- 3-6. DB app password rotation ------------------------------------------
log "==> 3-6: DB app password rotation"
DBPW_OUT="$(bash "$SCRIPT_DIR/rotate-secrets.sh" --only db-password 2>&1 | capture)"
if printf '%s' "$DBPW_OUT" | grep -q "DB_PASSWORD *ROTATED_SUCCESSFULLY"; then
    harness_ok "3: DB app password rotation" "ROTATED_SUCCESSFULLY"
else
    harness_bad "3: DB app password rotation" "did not report ROTATED_SUCCESSFULLY: $DBPW_OUT"
fi

OLD_DB_STATUS="$(slib_db_user_auth_check db "$ORIG_DB_USER" "$ORIG_DB_PASSWORD")"
[ "$OLD_DB_STATUS" = "DRIFT" ] \
    && harness_ok "4: old DB app password rejected" "auth check returned DRIFT" \
    || harness_bad "4: old DB app password rejected" "expected DRIFT, got $OLD_DB_STATUS"

NEW_DB_STATUS="$(slib_db_user_auth_check db "$ORIG_DB_USER" "$NEW_DB_PASSWORD")"
[ "$NEW_DB_STATUS" = "MATCH" ] \
    && harness_ok "5: new DB app password works" "auth check returned MATCH" \
    || harness_bad "5: new DB app password works" "expected MATCH, got $NEW_DB_STATUS"

ODBC_COUNT="$($COMPOSE exec -T asterisk asterisk -rx 'odbc show all' 2>&1 | capture | grep -cE 'Number of active connections: [1-9]')"
[ "$ODBC_COUNT" -ge 1 ] \
    && harness_ok "6: Asterisk ODBC works" "odbc show all reports >=1 active connection" \
    || harness_bad "6: Asterisk ODBC works" "no active ODBC connection reported after DB app password rotation"

# --- 10-12. AMI rotation ------------------------------------------------------
log "==> 10-12: AMI password rotation"
BEFORE_UPTIME="$($COMPOSE exec -T asterisk asterisk -rx 'core show uptime' 2>&1 | capture)"
AMIPW_OUT="$(bash "$SCRIPT_DIR/rotate-secrets.sh" --only ami-password 2>&1 | capture)"
if printf '%s' "$AMIPW_OUT" | grep -q "AMI_PASSWORD *ROTATED_SUCCESSFULLY"; then
    harness_ok "10: AMI password rotation" "ROTATED_SUCCESSFULLY"
else
    harness_bad "10: AMI password rotation" "did not report ROTATED_SUCCESSFULLY: $AMIPW_OUT"
fi
AFTER_UPTIME="$($COMPOSE exec -T asterisk asterisk -rx 'core show uptime' 2>&1 | capture)"
if printf '%s' "$AFTER_UPTIME" | grep -q "System uptime"; then
    harness_ok "10b: AMI rotation was non-disruptive" "Asterisk answered 'core show uptime' immediately after rotation (process was never restarted)"
else
    harness_bad "10b: AMI rotation was non-disruptive" "could not confirm Asterisk stayed up through rotation"
fi

OLD_AMI_STATUS="$(slib_ami_auth_check asterisk "$ORIG_AMI_USER" "$ORIG_AMI_PASSWORD")"
[ "$OLD_AMI_STATUS" = "DRIFT" ] \
    && harness_ok "11: old AMI password rejected" "auth check returned DRIFT" \
    || harness_bad "11: old AMI password rejected" "expected DRIFT, got $OLD_AMI_STATUS"

NEW_AMI_STATUS="$(slib_ami_auth_check asterisk "$ORIG_AMI_USER" "$NEW_AMI_PASSWORD")"
[ "$NEW_AMI_STATUS" = "MATCH" ] \
    && harness_ok "12: new AMI password works" "auth check returned MATCH" \
    || harness_bad "12: new AMI password works" "expected MATCH, got $NEW_AMI_STATUS"

# --- 13. runtime status survives ---------------------------------------------
log "==> 13: runtime status survives (real authenticated HTTP page, real AMI call)"
BASE_URL="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
COOKIEJAR="$(mktemp)"
harness_register_best_effort_cleanup "status-check cookie jar" "rm -f '$COOKIEJAR'"
curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null \
    -d "user=admin&password=SmokeTest123!" "${BASE_URL}/index.php/auth/login"
STATUS_PAGE="$(mktemp)"
harness_register_best_effort_cleanup "status page temp file" "rm -f '$STATUS_PAGE'"
curl -sS -b "$COOKIEJAR" -c "$COOKIEJAR" "${BASE_URL}/index.php/default/extensions" -o "$STATUS_PAGE"
if grep -qi "asterisk.*unreachable\|connection.*error\|could not connect" "$STATUS_PAGE"; then
    harness_bad "13: runtime status survives" "extensions page rendered an AMI-connectivity error page after rotation"
elif grep -qE 'data-runtime-status="ERROR"' "$STATUS_PAGE"; then
    harness_bad "13: runtime status survives" "extensions page rendered an ERROR runtime-status badge after rotation"
else
    harness_ok "13: runtime status survives" "authenticated extensions page rendered normally (no AMI-connectivity error, no ERROR badge) using the app's own rotated AMI credential from setup.conf"
fi

# --- 14. reconcile survives ---------------------------------------------------
log "==> 14: reconcile survives"
if $COMPOSE exec -T asterisk php /usr/local/bin/reconcile-pjsip.php --check >"$ALL_OUTPUT_LOG.reconcile" 2>&1; then
    harness_ok "14: reconcile-check survives rotation" "exit 0 (IN_SYNC)"
else
    rc=$?
    if [ "$rc" -eq 3 ]; then
        harness_ok "14: reconcile-check survives rotation" "exit 3 (DRIFTED -- a real PJSIP config drift unrelated to secrets, not a tool failure)"
    else
        harness_bad "14: reconcile-check survives rotation" "exit $rc -- see $ALL_OUTPUT_LOG.reconcile"
    fi
fi
cat "$ALL_OUTPUT_LOG.reconcile" >>"$ALL_OUTPUT_LOG" 2>/dev/null
rm -f "$ALL_OUTPUT_LOG.reconcile"

# --- 15. backup survives ------------------------------------------------------
log "==> 15: backup survives"
BACKUP_TMP_DEST="$(mktemp -d)"
harness_register_best_effort_cleanup "temp backup destination" "rm -rf '$BACKUP_TMP_DEST'"
if bash "$SCRIPT_DIR/backup.sh" --dest "$BACKUP_TMP_DEST" >"$ALL_OUTPUT_LOG.backup" 2>&1; then
    harness_ok "15: backup survives post-rotation" "scripts/backup.sh exited 0 against the rotated installation"
else
    harness_bad "15: backup survives post-rotation" "scripts/backup.sh failed -- see $ALL_OUTPUT_LOG.backup"
fi
cat "$ALL_OUTPUT_LOG.backup" >>"$ALL_OUTPUT_LOG" 2>/dev/null
rm -f "$ALL_OUTPUT_LOG.backup"

# --- 16. force-recreate preserves the new secrets ----------------------------
log "==> 16: force-recreate preserves new secrets"
$COMPOSE up -d --force-recreate --no-deps app asterisk >&2
recreate_healthy() {
    $COMPOSE ps app asterisk --format '{{.Status}}' 2>/dev/null | grep -qv "healthy" && return 1
    return 0
}
harness_retry 20 3 -- recreate_healthy
RECREATE_CHECK="$(bash "$SCRIPT_DIR/secrets-check.sh" 2>&1 | capture)"
if printf '%s' "$RECREATE_CHECK" | grep -q "^OVERALL: MATCH$"; then
    harness_ok "16: force-recreate preserves new secrets" "secrets-check.sh still reports MATCH after --force-recreate"
else
    harness_bad "16: force-recreate preserves new secrets" "secrets-check.sh no longer reports MATCH after --force-recreate"
fi

# --- 17. full-stack restart preserves the new secrets ------------------------
log "==> 17: full-stack restart preserves new secrets"
$COMPOSE restart app asterisk db >&2
harness_retry 20 3 -- recreate_healthy
RESTART_CHECK="$(bash "$SCRIPT_DIR/secrets-check.sh" 2>&1 | capture)"
if printf '%s' "$RESTART_CHECK" | grep -q "^OVERALL: MATCH$"; then
    harness_ok "17: full-stack restart preserves new secrets" "secrets-check.sh still reports MATCH after restart"
else
    harness_bad "17: full-stack restart preserves new secrets" "secrets-check.sh no longer reports MATCH after restart"
fi

# --- 17b. post-restart ODBC/CDR recovery (TASK-0033E1) -----------------------
#
# Step 17's `$COMPOSE restart app asterisk db` names `asterisk` alongside
# `db` on the plain Compose `restart` subcommand -- confirmed live
# (docs/tasks/0033e1-asterisk-restart-harness-odbc-recovery.md) to bounce
# both concurrently without re-evaluating the `asterisk -> db:
# condition: service_healthy` gate `up`/`start` honor, racing
# res_odbc.so's one-shot, non-auto-reconnecting connect attempt exactly
# like TASK-0033E's own REMAINING DEBT item 5. Left unrecovered, this
# suite (not part of `make regression`, but run standalone via
# `make secret-rotation-smoke`) would hand a broken ODBC/CDR state to
# whatever runs next against the same dev stack.
log "==> 17b: post-restart ODBC/CDR recovery"
if harness_wait_asterisk_ready && harness_restore_asterisk_post_restart; then
    harness_ok "17b: ODBC/CDR ready after full-stack restart" "active ODBC connection and cdr_adaptive_odbc.so Running confirmed (recovered via module reload if needed)"
else
    harness_bad "17b: ODBC/CDR ready after full-stack restart" "Asterisk restarted successfully but ODBC/CDR runtime did not recover -- see log above for the reload attempts"
fi

# --- 18/19. controlled failure injection -------------------------------------
log "==> 18/19a: DB unavailable during rotation"
$COMPOSE stop db >&2
FAIL_OUT="$(bash "$SCRIPT_DIR/rotate-secrets.sh" --only db-password 2>&1 | capture)"
FAIL_RC=$?
$COMPOSE start db >&2
harness_retry 30 2 -- bash -c "$COMPOSE ps db --format '{{.Status}}' 2>/dev/null | grep -q healthy"
if [ "$FAIL_RC" -ne 0 ]; then
    harness_ok "18/19a: DB-unavailable rotation attempt returns nonzero" "exit $FAIL_RC, no partial state (db was stopped before any file/DB write was attempted)"
else
    harness_bad "18/19a: DB-unavailable rotation attempt returns nonzero" "expected nonzero exit while db was stopped, got 0"
fi
POST_FAIL_CHECK="$(bash "$SCRIPT_DIR/secrets-check.sh" 2>&1 | capture)"
if printf '%s' "$POST_FAIL_CHECK" | grep -q "^OVERALL: MATCH$"; then
    harness_ok "19a: coherence preserved after DB-unavailable failure" "secrets-check.sh still MATCH -- nothing was left partially applied"
else
    harness_bad "19a: coherence preserved after DB-unavailable failure" "secrets-check.sh is no longer MATCH after the aborted attempt"
fi

log "==> 18/19b: invalid secret format is rejected"
# Deliberately NOT written into .env: .env is sourced verbatim as shell
# (`set -a; . .env; set +a`, every Makefile target's own convention) --
# a '|' in a sourced KEY=VALUE line is the shell PIPE operator, not a
# literal character, and would corrupt .env sourcing itself rather than
# reach rotate-secrets.sh's own validation at all (confirmed live during
# this task's own validation). A direct one-shot environment override
# on this single child process exercises slib_validate_secret's
# rejection path without ever risking .env's own parseability.
INVALID_OUT="$(DB_PASSWORD='has|a|pipe' bash "$SCRIPT_DIR/rotate-secrets.sh" --only db-password 2>&1 | capture)"
INVALID_RC=$?
if [ "$INVALID_RC" -ne 0 ] && printf '%s' "$INVALID_OUT" | grep -q "DB_PASSWORD *ROTATION_REJECTED"; then
    harness_ok "18/19b: invalid secret format rejected" "exit $INVALID_RC, ROTATION_REJECTED, no state changed"
else
    harness_bad "18/19b: invalid secret format rejected" "expected nonzero exit + ROTATION_REJECTED for a '|'-containing value: $INVALID_OUT"
fi

log "==> 18/19c: asterisk unavailable during AMI rotation"
$COMPOSE stop asterisk >&2
# Documented, deliberate behavior (see docs/tasks/
# 0033c-secret-rotation-contract.md ROLLBACK / FAILURE INJECTION): a
# stopped/unreachable asterisk does NOT reject AMI rotation -- the
# config file is templated via `docker compose run` (works regardless
# of the named container's state), then asterisk is brought back up so
# it boots with the already-correct file. This is the same recovery
# mechanism the crash-loop-recovery path uses, and this suite asserts
# the actual chosen behavior rather than a hard rejection.
ASTDOWN_OUT="$(bash "$SCRIPT_DIR/rotate-secrets.sh" --only ami-password --force 2>&1 | capture)"
ASTDOWN_RC=$?
harness_retry 20 3 -- bash -c "$COMPOSE ps asterisk --format '{{.Status}}' 2>/dev/null | grep -q healthy"
if [ "$ASTDOWN_RC" -eq 0 ] && printf '%s' "$ASTDOWN_OUT" | grep -q "AMI_PASSWORD *ROTATED_SUCCESSFULLY"; then
    harness_ok "18/19c: asterisk-unavailable AMI rotation recovers" "manager.conf templated while stopped, asterisk brought back up, ROTATED_SUCCESSFULLY confirmed live"
else
    harness_bad "18/19c: asterisk-unavailable AMI rotation recovers" "expected ROTATED_SUCCESSFULLY with exit 0: $ASTDOWN_OUT"
fi

# --- 20. non-disclosure over the whole run -----------------------------------
log "==> 20: no secret value ever appeared in any captured output"
DISCLOSED=""
for v in "$ORIG_DB_PASSWORD" "$ORIG_DB_ROOT_PASSWORD" "$ORIG_AMI_PASSWORD" \
         "$NEW_DB_PASSWORD" "$NEW_DB_ROOT_PASSWORD" "$NEW_AMI_PASSWORD"; do
    if grep -qF -- "$v" "$ALL_OUTPUT_LOG"; then
        DISCLOSED="$DISCLOSED <redacted-value-disclosed>"
    fi
done
if [ -z "$DISCLOSED" ]; then
    harness_ok "20: no secret disclosure across the whole run" "grepped the full captured transcript for all six old/new secret values, none found"
else
    harness_bad "20: no secret disclosure across the whole run" "at least one secret value appeared verbatim in captured output"
fi

harness_complete
