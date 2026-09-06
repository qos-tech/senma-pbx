#!/bin/bash
#
# Safe, non-mutating regression coverage for the secret-consistency
# contract (TASK-0033C).
#
# Included in `make regression` -- unlike scripts/secret-rotation-smoke-
# -test.sh (which actually rotates DB_PASSWORD/DB_ROOT_PASSWORD/
# AMI_PASSWORD on this installation and is deliberately kept out of
# default regression; see that script's own header and docs/tasks/
# 0033c-secret-rotation-contract.md REGRESSION COVERAGE for why). This
# suite never writes to disk, never touches a DB account, never
# restarts/reloads anything -- it only:
#   1. runs scripts/secrets-check.sh against this dev install's own
#      current .env and asserts OVERALL: MATCH (this project's own
#      baseline is expected to be fully coherent at all times -- a
#      committed dev placeholder secret that's actually drifted would
#      itself be a real, if narrow, regression worth catching here);
#   2. captures its full stdout+stderr and asserts none of the three
#      live DB_PASSWORD/DB_ROOT_PASSWORD/AMI_PASSWORD values appear in
#      it anywhere (non-disclosure proof, Phase 14);
#   3. asserts a deliberately WRONG declared value is correctly reported
#      as DRIFT (not silently MATCH, not UNKNOWN) for one representative
#      secret/consumer pair, entirely via environment-variable overrides
#      -- .env itself is never touched.
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
# shellcheck source=lib/secrets-lib.sh
source "$SCRIPT_DIR/lib/secrets-lib.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
log() { harness_log "$@"; }

log "==> checking required containers"
harness_require_containers app asterisk db

harness_require_env DB_USER DB_PASSWORD DB_ROOT_PASSWORD AMI_USER AMI_PASSWORD

log "==> running scripts/secrets-check.sh against the current .env"
CHECK_OUT="$(bash "$SCRIPT_DIR/secrets-check.sh" 2>&1)"
CHECK_RC=$?

if [ "$CHECK_RC" -eq 0 ] && printf '%s' "$CHECK_OUT" | grep -q "^OVERALL: MATCH$"; then
    harness_ok "1: baseline is fully coherent" "secrets-check.sh exited 0, OVERALL: MATCH"
else
    harness_bad "1: baseline is fully coherent" "expected exit 0 / OVERALL: MATCH, got exit $CHECK_RC -- see docs/tasks/0033c-secret-rotation-contract.md; this dev install's own .env should never be left drifted"
fi

log "==> checking non-disclosure of all three live secret values"
DISCLOSED=0
for v in "$DB_PASSWORD" "$DB_ROOT_PASSWORD" "$AMI_PASSWORD"; do
    if printf '%s' "$CHECK_OUT" | grep -qF "$v"; then
        DISCLOSED=1
    fi
done
if [ "$DISCLOSED" -eq 0 ]; then
    harness_ok "2: no secret value disclosed in secrets-check output" "grepped full stdout+stderr for all three live values, none found"
else
    harness_bad "2: no secret value disclosed in secrets-check output" "at least one live secret value appeared verbatim in secrets-check.sh output"
fi

log "==> asserting a deliberately wrong declared value reports DRIFT (env override only, .env untouched)"
# Same live-auth check secrets-check.sh's own DB_PASSWORD row uses,
# called directly against a value known not to be active.
DRIFT_STATUS="$(slib_db_user_auth_check db "$DB_USER" "definitely-not-the-real-password-$$")"
if [ "$DRIFT_STATUS" = "DRIFT" ]; then
    harness_ok "3: wrong declared value correctly reports DRIFT" "slib_db_user_auth_check returned DRIFT for a value known not to be active"
else
    harness_bad "3: wrong declared value correctly reports DRIFT" "expected DRIFT, got '$DRIFT_STATUS' -- drift detection must never silently report MATCH/UNKNOWN for a known-wrong value"
fi

harness_complete
