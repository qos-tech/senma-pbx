#!/bin/bash
#
# TASK-0033E: DB readiness contract.
#
# READY means more than "TCP port open" -- it means SENMA can actually
# use this database: MariaDB accepts connections, BOTH the root account
# AND the application account (`snep`) authenticate, and the minimum
# schema this application depends on has actually been imported (not
# just "the server is up", which is all a bare `mariadb-admin ping`
# proves).
#
# Bind-mounted into the stock `mariadb:10.11` image (see compose.yaml)
# rather than baked into a custom image -- this project prefers the
# official image where practical (CLAUDE.md rule 7) and a bind-mounted
# script is enough; no Dockerfile is needed for the `db` service.
#
# Secret safety: every credential is read from this container's OWN
# environment (already set by compose.yaml's `environment:` block for
# `db`), never passed as a healthcheck CLI argument -- `docker inspect
# .Config.Healthcheck.Test` shows the literal command below (`bash
# /usr/local/bin/healthcheck-db.sh`), not a single secret value.
# `MYSQL_PWD` (an env var scoped to the one child mysql/mariadb-admin
# process) is used instead of `-p"$PASSWORD"`, matching TASK-0033C's
# own established non-disclosure convention.
#
# Root-password verification is preserved here deliberately: TASK-
# 0033C's own secret-rotation STARTUP POLICY relies on this exact
# healthcheck already authenticating with the CURRENT declared
# DB_ROOT_PASSWORD on every check to fail-fast on root-password drift
# (no file consumer exists for root's password to check instead) --
# replacing this with an app-credential-only check would silently
# remove that contract.
#
# TASK-0033F: the schema check below asserts `core_config` has at least
# one ROW, not merely that the table exists. Live-reproduced during that
# task, in an isolated Compose project: a bootstrap failure injected
# between schema.sql (creates `core_config`) and system_data.sql (seeds
# it -- 5 rows, always, on any successful full import, historical or
# current) leaves the container reporting "Up" on every subsequent
# restart -- docker-entrypoint-initdb.d never runs again once
# /var/lib/mysql is non-empty -- with `core_config` PRESENT but EMPTY (0
# rows), `users` present but empty (no admin seed), and the PREVIOUS
# version of this exact check (table-existence only) reporting READY
# regardless. See docs/tasks/
# 0033f-database-bootstrap-resilience-upgrade-path.md ROOT CAUSE.
#
# Deliberately NOT gated on the new `schema_migrations` migration
# tracker (docs/tasks/0033f-...md's own MIGRATION METADATA): that table
# does not exist at all on any install provisioned before TASK-0033F,
# and `app`'s hard `depends_on: db: condition: service_healthy` gate
# (TASK-0033E) would deadlock such an install -- `db` never healthy ->
# `app` never starts -> the one container `make migrate` execs into to
# baseline `schema_migrations` never runs. A row-count check against
# `core_config`, a table that has existed since the first Docker-era
# schema, has no such backward-compatibility hazard and is the exact,
# minimal, already-sufficient signal for the actual defect proven above.
# Schema *migration version* (current/behind/ahead) is a separate,
# non-blocking concern surfaced by `make doctor`/`make migrate-check`,
# not this healthcheck -- see that doc's READINESS INTEGRATION section.
#
# Exit 0 + "READY: ..." when every condition holds; exit 1 + a single
# concise "FAIL: <reason>" line otherwise (Docker retains this in
# `docker inspect .State.Health.Log[].Output` -- never a secret value,
# never a large dump).

set -uo pipefail

: "${MARIADB_ROOT_PASSWORD:?MARIADB_ROOT_PASSWORD must be set}"
: "${MARIADB_USER:?MARIADB_USER must be set}"
: "${MARIADB_PASSWORD:?MARIADB_PASSWORD must be set}"
: "${MARIADB_DATABASE:?MARIADB_DATABASE must be set}"

if ! MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb-admin ping -h 127.0.0.1 -uroot --silent >/dev/null 2>&1; then
    echo "FAIL: MariaDB not accepting root connections"
    exit 1
fi

if ! MYSQL_PWD="$MARIADB_PASSWORD" mariadb -h 127.0.0.1 -u"$MARIADB_USER" -e "SELECT 1;" >/dev/null 2>&1; then
    echo "FAIL: application credential ($MARIADB_USER) does not authenticate"
    exit 1
fi

SCHEMA_CHECK="$(MYSQL_PWD="$MARIADB_PASSWORD" mariadb -h 127.0.0.1 -u"$MARIADB_USER" "$MARIADB_DATABASE" -N \
    -e "SHOW TABLES LIKE 'core_config';" 2>/dev/null | tr -d '\r\n')"
if [ "$SCHEMA_CHECK" != "core_config" ]; then
    echo "FAIL: schema not ready (core_config table missing in $MARIADB_DATABASE)"
    exit 1
fi

SEED_ROWS="$(MYSQL_PWD="$MARIADB_PASSWORD" mariadb -h 127.0.0.1 -u"$MARIADB_USER" "$MARIADB_DATABASE" -N \
    -e "SELECT COUNT(*) FROM core_config;" 2>/dev/null | tr -d '\r\n')"
if [ -z "$SEED_ROWS" ] || [ "$SEED_ROWS" -eq 0 ] 2>/dev/null; then
    echo "FAIL: bootstrap incomplete (core_config exists but is empty in $MARIADB_DATABASE -- a prior schema import likely failed partway through, after creating tables but before seeding them; see docs/tasks/0033f-database-bootstrap-resilience-upgrade-path.md PARTIAL-FAILURE RECOVERY)"
    exit 1
fi

echo "READY: root + application auth OK, core_config present with ${SEED_ROWS} row(s) in $MARIADB_DATABASE"
exit 0
