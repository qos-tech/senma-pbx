#!/bin/bash
#
# TASK-0033F: safe, non-mutating regression coverage for the database
# migration runner against the live dev database.
#
# Unlike scripts/db-migration-failure-smoke-test.sh (destructive,
# isolated Compose project only), this suite only ever reads state and
# performs the one genuinely idempotent mutating call this task's own
# contract requires to be safe: `migrate.php` (apply mode) against an
# already-current database, which must be a true no-op. Included in
# `make regression`.
#
# Proves:
#   1. containers healthy;
#   2. schema_migrations exists and reports SCHEMA_CURRENT via
#      `migrate.php --check`;
#   3. re-running `migrate.php` (apply mode) against an already-current
#      database is a safe no-op -- applies nothing, exits 0;
#   4. every applied migration's checksum still matches its on-disk
#      file (Phase 20 -- applied migrations are immutable);
#   5. `make doctor`'s own schema-status integration reports the same
#      CURRENT verdict (Phase 38 -- no duplicated detection logic);
#   6. no secret value (DB_PASSWORD/DB_ROOT_PASSWORD/AMI_PASSWORD)
#      appears anywhere in migrate.php's own output.
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps
log() { harness_log "$@"; }

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
harness_require_env DB_PASSWORD DB_ROOT_PASSWORD AMI_PASSWORD

log "==> checking required containers"
harness_require_containers app db

log "==> 1: migrate.php --check reports SCHEMA_CURRENT"
CHECK_OUT="$($COMPOSE exec -T app php /usr/local/bin/migrate.php --check 2>&1)"; CHECK_RC=$?
if [ "$CHECK_RC" -eq 0 ] && printf '%s' "$CHECK_OUT" | grep -q "SCHEMA_CURRENT"; then
    harness_ok "1: migrate.php --check reports SCHEMA_CURRENT" "$CHECK_OUT"
else
    harness_bad "1: migrate.php --check reports SCHEMA_CURRENT" "exit $CHECK_RC: $CHECK_OUT (run 'make migrate' if a real migration is genuinely pending)"
fi

log "==> 2: re-applying against an already-current database is a safe no-op"
APPLY_OUT="$($COMPOSE exec -T app php /usr/local/bin/migrate.php 2>&1)"; APPLY_RC=$?
if [ "$APPLY_RC" -eq 0 ] && printf '%s' "$APPLY_OUT" | grep -q "SCHEMA_CURRENT" && ! printf '%s' "$APPLY_OUT" | grep -q "^Applying"; then
    harness_ok "2: re-applying is a safe no-op" "$APPLY_OUT"
else
    harness_bad "2: re-applying is a safe no-op" "exit $APPLY_RC: $APPLY_OUT"
fi

log "==> 3: schema_migrations checksum integrity (Phase 20 -- applied migrations are immutable)"
if printf '%s\n%s' "$CHECK_OUT" "$APPLY_OUT" | grep -qi "checksum mismatch"; then
    harness_bad "3: applied migrations unchanged since they were recorded" "checksum drift detected -- see output above"
else
    harness_ok "3: applied migrations unchanged since they were recorded" "no checksum drift reported"
fi

log "==> 4: make doctor reports the same CURRENT verdict"
DOCTOR_OUT="$(set -a; . "$SCRIPT_DIR/../.env"; set +a; bash "$SCRIPT_DIR/doctor.sh" 2>&1 | grep "Database schema")"
if printf '%s' "$DOCTOR_OUT" | grep -q "PASS.*CURRENT"; then
    harness_ok "4: make doctor reports Database schema: CURRENT" "$DOCTOR_OUT"
else
    harness_bad "4: make doctor reports Database schema: CURRENT" "$DOCTOR_OUT"
fi

log "==> 5: no secret disclosure in migrate.php output"
DISCLOSED=0
for v in "$DB_PASSWORD" "$DB_ROOT_PASSWORD" "$AMI_PASSWORD"; do
    for blob in "$CHECK_OUT" "$APPLY_OUT"; do
        printf '%s' "$blob" | grep -qF "$v" && DISCLOSED=1
    done
done
if [ "$DISCLOSED" -eq 0 ]; then
    harness_ok "5: no secret disclosure in migrate.php output" "grepped both --check and apply-mode output for all three live secrets, none found"
else
    harness_bad "5: no secret disclosure in migrate.php output" "a secret value appeared verbatim in migrate.php's own output"
fi

harness_complete
