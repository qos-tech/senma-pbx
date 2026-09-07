#!/bin/bash
#
# TASK-0033F: destructive database bootstrap/migration proof.
#
# Runs entirely against throwaway, fully isolated Compose projects (own
# network/volumes, `docker compose -p <name> -f compose.yaml -f
# <override>`, matching scripts/readiness-failure-smoke-test.sh's own
# established pattern) -- the main dev stack is never touched. Reuses
# the already-built `mag-pbx-app`/`mariadb:10.11` images and the REAL
# compose.yaml service definitions (db-init scripts, healthchecks,
# mounts) rather than a hand-rolled minimal stand-in, so every proof
# below exercises the actual shipped bootstrap/migration path.
#
# Deliberately NOT part of `make regression` (mirrors readiness-failure-
# smoke/doctor-failure-smoke/secret-rotation-smoke's own precedent) --
# run explicitly via `make db-migration-failure-smoke`.
#
# Proves, in order (see docs/tasks/
# 0033f-database-bootstrap-resilience-upgrade-path.md for the full
# design this validates):
#   A. fresh bootstrap: empty DB -> normal bootstrap -> schema_migrations
#      established automatically -> restart -> still current.
#   B. partial bootstrap failure: a deliberate mid-import failure leaves
#      the DB unhealthy (never falsely READY) on every subsequent
#      restart, until a genuinely clean re-bootstrap succeeds.
#   C. older-schema fixture upgrade path: a DB bootstrapped from the
#      schema as it existed immediately before this task (git HEAD,
#      missing migration 0001's effect) with no bootstrap-completion
#      marker at all (simulating a real pre-TASK-0033F install) is
#      correctly baselined by structural fingerprint, migration 0001 is
#      detected pending, and applying it for real converges the schema.
#   D. mid-migration failure + retry: migration A succeeds, B fails
#      deliberately, C is never attempted; fixing the cause and retrying
#      converges correctly, in order.
#   E. concurrent migration locking: a held advisory lock causes a
#      second runner invocation to fail boundedly, never wait forever.
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps
log() { harness_log "$@"; }

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
harness_require_env DB_USER DB_PASSWORD DB_ROOT_PASSWORD DB_NAME

# The isolated project's own `app` service still publishes a host port
# (compose.yaml's ports: "${MAG_HTTP_PORT:-8080}:80") -- override it so
# this suite never collides with the main dev stack's own app container
# on 8080 while both are running simultaneously (live-confirmed
# collision during this suite's own first draft; same class of
# artifact TASK-0033E's own fresh-install proof already documented).
export MAG_HTTP_PORT="${MAG_HTTP_PORT_TEST:-18080}"

ISOLATED_PROJECT="senma-dbmigtest-$$"
WORKDIR="$(mktemp -d)"
OVERRIDE="$WORKDIR/override.yaml"

cat > "$OVERRIDE" <<'EOF'
networks:
  mag:
    ipam:
      config:
        - subnet: 172.32.0.0/16
EOF

iso() { $COMPOSE -p "$ISOLATED_PROJECT" -f "$REPO_ROOT/compose.yaml" -f "$OVERRIDE" "$@"; }

teardown_isolated() {
    iso down -v >/dev/null 2>&1 || true
    docker rmi "${ISOLATED_PROJECT}-app:latest" "${ISOLATED_PROJECT}-asterisk:latest" "${ISOLATED_PROJECT}-provider:latest" >/dev/null 2>&1 || true
}
# Registration order matters: harness cleanup runs LIFO (last-registered-
# first), and teardown_isolated's own `iso down -v` needs $OVERRIDE
# (under $WORKDIR) to still exist on disk to resolve which project/
# compose-file combination to tear down. Register the workdir removal
# FIRST so it runs LAST, after teardown_isolated has already run --
# reversing this order once left `iso down -v` silently failing
# (compose file not found, swallowed by `|| true`) while still reporting
# "cleanup OK", orphaning every isolated container/network/volume.
harness_register_best_effort_cleanup "remove isolated fixture workdir" "rm -rf '$WORKDIR'"
harness_register_cleanup "tear down isolated db-migration-test project" teardown_isolated

db_healthy_iso() { [ "$(iso ps db --format '{{.Health}}' 2>/dev/null)" = "healthy" ]; }
db_root_query() {
    iso exec -T db sh -c "read -r PW; MYSQL_PWD=\"\$PW\" mariadb -uroot \"\$0\" -N -e \"\$1\"" "$DB_NAME" "$1" <<< "$DB_ROOT_PASSWORD" 2>/dev/null
}

# Starts `db` alone, waits for it healthy using this script's OWN bounded
# retry (generous -- 120s), THEN starts `app` separately. Deliberately
# NOT a single `up -d db app` -- that relies on Compose's own internal
# dependency-wait, tied directly to db's declared healthcheck
# retries*interval (~50s, TASK-0033E's own tuned production value) with
# no separate allowance for this suite's own added bootstrap cost
# (99-bootstrap-marker.sh's extra mysql round-trips) or for a host
# already busy running the main dev stack plus concurrent image builds
# -- live-observed during this task's own validation to fail the whole
# `up` command before this script's own retry loop ever got a chance to
# run. Splitting the wait out and controlling it directly avoids
# depending on Compose's own timeout matching this suite's own needs.
wait_db_then_start_app() {
    local compose_fn="$1"
    "$compose_fn" up -d db >&2 || return 1
    harness_retry 60 2 -- bash -c "[ \"\$($COMPOSE -p '$ISOLATED_PROJECT' ps db --format '{{.Health}}' 2>/dev/null)\" = healthy ]" || return 1
    "$compose_fn" up -d app >&2 || return 1
    return 0
}

# =============================================================================
# A. Fresh bootstrap proof
# =============================================================================
log "==> A: fresh bootstrap (empty DB -> schema_migrations established automatically)"
if wait_db_then_start_app iso; then
    ROWS="$(db_root_query "SELECT COUNT(*) FROM schema_migrations;")"
    if [ "$ROWS" = "2" ]; then
        harness_ok "A1: fresh bootstrap establishes schema_migrations automatically" "2 row(s) recorded by docker/db-init/99-bootstrap-marker.sh, no migrate.php invocation needed"
    else
        harness_bad "A1: fresh bootstrap establishes schema_migrations automatically" "expected 2 rows, got '${ROWS}'"
    fi
    CHECK_OUT="$(iso exec -T app php /usr/local/bin/migrate.php --check 2>&1)"; CHECK_RC=$?
    if [ "$CHECK_RC" -eq 0 ] && printf '%s' "$CHECK_OUT" | grep -q "SCHEMA_CURRENT"; then
        harness_ok "A2: migrate.php --check reports SCHEMA_CURRENT on fresh install" "$CHECK_OUT"
    else
        harness_bad "A2: migrate.php --check reports SCHEMA_CURRENT on fresh install" "exit $CHECK_RC: $CHECK_OUT"
    fi
    iso restart db >&2
    if harness_retry 30 2 -- db_healthy_iso; then
        ROWS_AFTER="$(db_root_query "SELECT COUNT(*) FROM schema_migrations;")"
        [ "$ROWS_AFTER" = "2" ] \
            && harness_ok "A3: schema_migrations survives a db restart" "still 2 row(s)" \
            || harness_bad "A3: schema_migrations survives a db restart" "expected 2 rows, got '${ROWS_AFTER}'"
    else
        harness_bad "A3: schema_migrations survives a db restart" "db did not become healthy again"
    fi
else
    harness_bad "A: fresh bootstrap" "db/app did not become healthy"
fi
teardown_isolated

# =============================================================================
# B. Partial bootstrap failure proof
# =============================================================================
log "==> B: partial bootstrap failure (deliberate mid-import failure)"
BROKEN_IMPORT="$WORKDIR/00-import-snep-schema.sh"
cat > "$BROKEN_IMPORT" <<EOF
#!/bin/bash
set -euo pipefail
echo "[test-init] importing schema.sql only, then deliberately failing before system_data.sql"
mysql --init-command="SET SESSION sql_mode='';" -u"\${MARIADB_USER}" -p"\${MARIADB_PASSWORD}" "\${MARIADB_DATABASE}" < /docker-entrypoint-initdb.d/snep-install/schema.sql
false
EOF
chmod +x "$BROKEN_IMPORT"
cat > "$WORKDIR/override-broken.yaml" <<EOF
networks:
  mag:
    ipam:
      config:
        - subnet: 172.32.0.0/16
services:
  db:
    volumes:
      - $BROKEN_IMPORT:/docker-entrypoint-initdb.d/00-import-snep-schema.sh:ro
EOF
isob() { $COMPOSE -p "$ISOLATED_PROJECT" -f "$REPO_ROOT/compose.yaml" -f "$WORKDIR/override-broken.yaml" "$@"; }

isob up -d db >&2 2>&1 || true
# Every service in compose.yaml sets `restart: unless-stopped` -- the
# container's own "exited" state after the deliberate failure is a
# genuinely SUB-SECOND transient (Docker's restart policy fires almost
# immediately), not a stable state this suite's own 2s polling interval
# can reliably observe (confirmed live during this task's own
# validation: widening the bound to 120s never once caught "exited").
# `RestartCount` is the correct, race-free proof instead -- a persistent
# counter, not a point-in-time state, so it is unaffected by how fast
# the automatic restart happens.
db_restarted_iso() {
    local cid count
    cid="$(isob ps -aq db 2>/dev/null)"
    [ -z "$cid" ] && return 1
    count="$(docker inspect "$cid" --format '{{.RestartCount}}' 2>/dev/null)"
    [ -n "$count" ] && [ "$count" -ge 1 ] 2>/dev/null
}
harness_retry 30 2 -- db_restarted_iso
B1_CID="$(isob ps -aq db 2>/dev/null)"
B1_COUNT="$(docker inspect "$B1_CID" --format '{{.RestartCount}}' 2>/dev/null)"
if [ -n "$B1_COUNT" ] && [ "$B1_COUNT" -ge 1 ] 2>/dev/null; then
    harness_ok "B1: injected failure crashes the container (not a silent partial success), Docker's own restart policy takes over" "RestartCount=$B1_COUNT"
else
    harness_bad "B1: injected failure crashes the container (not a silent partial success), Docker's own restart policy takes over" "RestartCount='$B1_COUNT' (expected >=1)"
fi

isob up -d db >&2 2>&1 || true
# The container itself comes back "Up" immediately (docker-entrypoint-
# initdb.d never runs again against a non-empty datadir -- no import to
# wait for this time) -- bounded-wait for the healthcheck to actually
# settle on a stable verdict (not "starting") before asserting on it.
db_health_settled_iso() { local h; h="$(isob ps db --format '{{.Health}}' 2>/dev/null)"; [ "$h" = "healthy" ] || [ "$h" = "unhealthy" ]; }
harness_retry 30 2 -- db_health_settled_iso
B2_HEALTH="$(isob ps db --format '{{.Health}}' 2>/dev/null)"
B2_OUT="$(isob exec -T db bash /usr/local/bin/healthcheck-db.sh 2>&1)"; B2_RC=$?
if [ "$B2_RC" -ne 0 ] && printf '%s' "$B2_OUT" | grep -q "bootstrap incomplete"; then
    harness_ok "B2: restart never retries the failed import, healthcheck stays FAIL (never falsely READY)" "health=$B2_HEALTH; $B2_OUT"
else
    harness_bad "B2: restart never retries the failed import, healthcheck stays FAIL (never falsely READY)" "health=$B2_HEALTH exit=$B2_RC: $B2_OUT"
fi
B3_MARKER="$(isob exec -T db sh -c "read -r PW; MYSQL_PWD=\"\$PW\" mariadb -uroot \"$DB_NAME\" -N -e \"SHOW TABLES LIKE 'schema_migrations';\"" <<< "$DB_ROOT_PASSWORD" 2>/dev/null)"
if [ -z "$B3_MARKER" ]; then
    harness_ok "B3: bootstrap-completion marker never created on a failed import" "schema_migrations absent, as expected"
else
    harness_bad "B3: bootstrap-completion marker never created on a failed import" "schema_migrations unexpectedly present"
fi

log "==> B4: genuine repair -- wipe and re-bootstrap cleanly"
isob down -v >/dev/null 2>&1
if wait_db_then_start_app iso; then
    B4_OUT="$(iso exec -T db bash /usr/local/bin/healthcheck-db.sh 2>&1)"; B4_RC=$?
    ROWS="$(db_root_query "SELECT COUNT(*) FROM schema_migrations;")"
    if [ "$B4_RC" -eq 0 ] && [ "$ROWS" = "2" ]; then
        harness_ok "B4: a genuinely clean re-bootstrap succeeds and is recognized READY" "$B4_OUT"
    else
        harness_bad "B4: a genuinely clean re-bootstrap succeeds and is recognized READY" "exit=$B4_RC rows=$ROWS: $B4_OUT"
    fi
else
    harness_bad "B4: a genuinely clean re-bootstrap succeeds and is recognized READY" "db/app did not become healthy"
fi
teardown_isolated

# =============================================================================
# C. Older-schema fixture upgrade path proof
# =============================================================================
log "==> C: older-schema fixture (schema as of git HEAD, pre-migration-0001, no bootstrap marker at all)"
OLD_SCHEMA="$WORKDIR/old-schema.sql"
if ! git -C "$REPO_ROOT" show HEAD:snep/install/database/schema.sql > "$OLD_SCHEMA" 2>/dev/null; then
    harness_blocked "could not extract the pre-task schema.sql via 'git show HEAD:...' -- cannot build the older-schema fixture"
fi
NOOP_MARKER="$WORKDIR/99-noop.sh"
printf '#!/bin/bash\ntrue\n' > "$NOOP_MARKER"
chmod +x "$NOOP_MARKER"
cat > "$WORKDIR/override-older.yaml" <<EOF
networks:
  mag:
    ipam:
      config:
        - subnet: 172.32.0.0/16
services:
  db:
    volumes:
      - $OLD_SCHEMA:/docker-entrypoint-initdb.d/snep-install/schema.sql:ro
      - $NOOP_MARKER:/docker-entrypoint-initdb.d/99-bootstrap-marker.sh:ro
EOF
isoc() { $COMPOSE -p "$ISOLATED_PROJECT" -f "$REPO_ROOT/compose.yaml" -f "$WORKDIR/override-older.yaml" "$@"; }

if wait_db_then_start_app isoc; then
    C1_MARKER="$(isoc exec -T db sh -c "read -r PW; MYSQL_PWD=\"\$PW\" mariadb -uroot \"$DB_NAME\" -N -e \"SHOW TABLES LIKE 'schema_migrations';\"" <<< "$DB_ROOT_PASSWORD" 2>/dev/null)"
    if [ -z "$C1_MARKER" ]; then
        harness_ok "C1: fixture genuinely predates the migration tracker" "schema_migrations absent, simulating a real pre-TASK-0033F install"
    else
        harness_bad "C1: fixture genuinely predates the migration tracker" "schema_migrations unexpectedly present -- fixture setup is wrong"
    fi
    C2_OUT="$(isoc exec -T app php /usr/local/bin/migrate.php --check 2>&1)"; C2_RC=$?
    if [ "$C2_RC" -eq 3 ] && printf '%s' "$C2_OUT" | grep -q "0001-add-cdr-uniqueid-index" && printf '%s' "$C2_OUT" | grep -q "Baselined 0000-baseline"; then
        harness_ok "C2: existing-install baselining recognizes 0000 as present, 0001 as genuinely pending" "$C2_OUT"
    else
        harness_bad "C2: existing-install baselining recognizes 0000 as present, 0001 as genuinely pending" "exit=$C2_RC: $C2_OUT"
    fi
    C3_OUT="$(isoc exec -T app php /usr/local/bin/migrate.php 2>&1)"; C3_RC=$?
    C3_INDEX="$(isoc exec -T db sh -c "read -r PW; MYSQL_PWD=\"\$PW\" mariadb -uroot \"$DB_NAME\" -N -e \"SHOW INDEX FROM cdr WHERE Key_name='uniqueid';\"" <<< "$DB_ROOT_PASSWORD" 2>/dev/null)"
    if [ "$C3_RC" -eq 0 ] && [ -n "$C3_INDEX" ]; then
        harness_ok "C3: applying the real pending migration converges the older schema to current" "$C3_OUT"
    else
        harness_bad "C3: applying the real pending migration converges the older schema to current" "exit=$C3_RC index='$C3_INDEX': $C3_OUT"
    fi
    C4_OUT="$(isoc exec -T app php /usr/local/bin/migrate.php --check 2>&1)"; C4_RC=$?
    if [ "$C4_RC" -eq 0 ] && printf '%s' "$C4_OUT" | grep -q "SCHEMA_CURRENT"; then
        harness_ok "C4: upgraded fixture reports SCHEMA_CURRENT" "$C4_OUT"
    else
        harness_bad "C4: upgraded fixture reports SCHEMA_CURRENT" "exit=$C4_RC: $C4_OUT"
    fi
else
    harness_bad "C: older-schema fixture bootstrap" "db/app did not become healthy"
fi
teardown_isolated

# =============================================================================
# D. Mid-migration failure + retry proof
# =============================================================================
log "==> D: mid-migration failure (A succeeds, B fails, C never attempted), then repair + retry"
TESTMIG_DIR="$WORKDIR/migrations"
mkdir -p "$TESTMIG_DIR"
cp "$REPO_ROOT"/snep/install/database/migrations/*.sql "$TESTMIG_DIR"/
cat > "$TESTMIG_DIR/0002-test-a.sql" <<'EOF'
-- TASK-0033F test fixture only -- never shipped in the real migrations/
-- directory. See scripts/db-migration-failure-smoke-test.sh Phase D.
CREATE TABLE IF NOT EXISTS _migration_test_marker_a (id INT);
EOF
cat > "$TESTMIG_DIR/0003-test-b-fail.sql" <<'EOF'
-- TASK-0033F test fixture only -- deliberately invalid SQL.
THIS IS NOT VALID SQL;
EOF
cat > "$TESTMIG_DIR/0004-test-c.sql" <<'EOF'
-- TASK-0033F test fixture only -- never shipped in the real migrations/
-- directory. Must never be attempted while 0003 remains unfixed.
CREATE TABLE IF NOT EXISTS _migration_test_marker_c (id INT);
EOF
cat > "$WORKDIR/override-testmig.yaml" <<EOF
networks:
  mag:
    ipam:
      config:
        - subnet: 172.32.0.0/16
services:
  app:
    volumes:
      - $TESTMIG_DIR:/var/www/html/snep/install/database/migrations
EOF
isod() { $COMPOSE -p "$ISOLATED_PROJECT" -f "$REPO_ROOT/compose.yaml" -f "$WORKDIR/override-testmig.yaml" "$@"; }

if wait_db_then_start_app isod; then
    D1_OUT="$(isod exec -T app php /usr/local/bin/migrate.php 2>&1)"; D1_RC=$?
    D1_A="$(isod exec -T db sh -c "read -r PW; MYSQL_PWD=\"\$PW\" mariadb -uroot \"$DB_NAME\" -N -e \"SHOW TABLES LIKE '_migration_test_marker_a';\"" <<< "$DB_ROOT_PASSWORD" 2>/dev/null)"
    D1_C="$(isod exec -T db sh -c "read -r PW; MYSQL_PWD=\"\$PW\" mariadb -uroot \"$DB_NAME\" -N -e \"SHOW TABLES LIKE '_migration_test_marker_c';\"" <<< "$DB_ROOT_PASSWORD" 2>/dev/null)"
    D1_RECORDED="$(isod exec -T db sh -c "read -r PW; MYSQL_PWD=\"\$PW\" mariadb -uroot \"$DB_NAME\" -N -e \"SELECT id FROM schema_migrations WHERE id LIKE '0002%' OR id LIKE '0003%' OR id LIKE '0004%';\"" <<< "$DB_ROOT_PASSWORD" 2>/dev/null)"
    if [ "$D1_RC" -eq 1 ] && [ -n "$D1_A" ] && [ -z "$D1_C" ] && [ "$D1_RECORDED" = "0002-test-a" ] && printf '%s' "$D1_OUT" | grep -q "0003-test-b-fail failed"; then
        harness_ok "D1: A applied+recorded, B failed+unrecorded, C never attempted" "$D1_OUT"
    else
        harness_bad "D1: A applied+recorded, B failed+unrecorded, C never attempted" "exit=$D1_RC a='$D1_A' c='$D1_C' recorded='$D1_RECORDED': $D1_OUT"
    fi

    cat > "$TESTMIG_DIR/0003-test-b-fail.sql" <<'EOF'
-- TASK-0033F test fixture only -- repaired.
CREATE TABLE IF NOT EXISTS _migration_test_marker_b (id INT);
EOF
    D2_OUT="$(isod exec -T app php /usr/local/bin/migrate.php 2>&1)"; D2_RC=$?
    D2_B="$(isod exec -T db sh -c "read -r PW; MYSQL_PWD=\"\$PW\" mariadb -uroot \"$DB_NAME\" -N -e \"SHOW TABLES LIKE '_migration_test_marker_b';\"" <<< "$DB_ROOT_PASSWORD" 2>/dev/null)"
    D2_C="$(isod exec -T db sh -c "read -r PW; MYSQL_PWD=\"\$PW\" mariadb -uroot \"$DB_NAME\" -N -e \"SHOW TABLES LIKE '_migration_test_marker_c';\"" <<< "$DB_ROOT_PASSWORD" 2>/dev/null)"
    if [ "$D2_RC" -eq 0 ] && [ -n "$D2_B" ] && [ -n "$D2_C" ] && printf '%s' "$D2_OUT" | grep -q "SCHEMA_CURRENT"; then
        harness_ok "D2: repairing the cause and retrying converges correctly, in order" "$D2_OUT"
    else
        harness_bad "D2: repairing the cause and retrying converges correctly, in order" "exit=$D2_RC b='$D2_B' c='$D2_C': $D2_OUT"
    fi
else
    harness_bad "D: mid-migration failure fixture bootstrap" "db/app did not become healthy"
fi

# =============================================================================
# E. Concurrent migration locking proof
# =============================================================================
log "==> E: concurrent migration locking (bounded refusal, never an unbounded wait)"
isod exec -T db sh -c "read -r PW; MYSQL_PWD=\"\$PW\" mariadb -uroot \"$DB_NAME\" -e \"SELECT GET_LOCK('senma_schema_migrations', 5); DO SLEEP(20); SELECT RELEASE_LOCK('senma_schema_migrations');\"" <<< "$DB_ROOT_PASSWORD" >/dev/null 2>&1 &
LOCK_HOLDER_PID=$!
lock_actually_held() {
    local held
    held="$(isod exec -T db sh -c "read -r PW; MYSQL_PWD=\"\$PW\" mariadb -uroot \"$DB_NAME\" -N -e \"SELECT IS_USED_LOCK('senma_schema_migrations');\"" <<< "$DB_ROOT_PASSWORD" 2>/dev/null)"
    [ -n "$held" ] && [ "$held" != "NULL" ]
}
harness_retry 15 1 -- lock_actually_held
E_START=$(date +%s)
E_OUT="$(isod exec -T app php /usr/local/bin/migrate.php --check 2>&1)"; E_RC=$?
E_ELAPSED=$(( $(date +%s) - E_START ))
kill "$LOCK_HOLDER_PID" >/dev/null 2>&1 || true
wait "$LOCK_HOLDER_PID" 2>/dev/null || true
if [ "$E_RC" -eq 5 ] && [ "$E_ELAPSED" -le 15 ] && printf '%s' "$E_OUT" | grep -qi "already in progress"; then
    harness_ok "E: a held lock causes bounded refusal, never an unbounded wait" "exit=5 after ${E_ELAPSED}s: $E_OUT"
else
    harness_bad "E: a held lock causes bounded refusal, never an unbounded wait" "exit=$E_RC after ${E_ELAPSED}s: $E_OUT"
fi
# Let the lock holder's own RELEASE_LOCK/connection-close happen before teardown.
sleep 3

harness_complete
