#!/bin/bash
set -euo pipefail

# TASK-0033F: the fresh-install bootstrap-completion marker.
#
# Runs LAST among /docker-entrypoint-initdb.d/ scripts (lexically after
# 00-import-snep-schema.sh -- MariaDB's official entrypoint executes
# initdb.d scripts in sorted order and aborts the entire container start
# on the first failing script, live-confirmed during this task: a
# deliberate failure injected into an earlier script left this file
# never executed, on this run or any subsequent restart, since
# docker-entrypoint-initdb.d only ever runs against a truly empty
# /var/lib/mysql).
#
# This is therefore the one place a fresh bootstrap can prove, to
# anything outside the container, that EVERY earlier import step
# actually succeeded -- not just that the container is "Up". Before this
# task, docker/healthcheck-db.sh's own schema check only asserted
# `core_config` exists, which is also true after a PARTIAL import
# (schema.sql succeeded, system_data.sql or the billing schema failed
# partway through) -- live-reproduced during this task in an isolated
# Compose project: `core_config` present, 0 rows, `users` present, 0
# rows, yet the existing healthcheck reported READY. See docs/tasks/
# 0033f-database-bootstrap-resilience-upgrade-path.md ROOT CAUSE /
# PARTIAL-FAILURE RECOVERY for the full reproduction.
#
# schema_migrations is the SAME table docker/migrate.php uses for every
# migration applied afterward -- one table serves both the bootstrap-
# completion invariant and the migration ledger, per this task's own
# instruction not to create a second, competing readiness truth.

echo "[db-init] 99-bootstrap-marker: recording fresh-install baseline"

mysql -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" "${MARIADB_DATABASE}" <<'SQL'
CREATE TABLE IF NOT EXISTS schema_migrations (
  id VARCHAR(64) NOT NULL,
  applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  checksum VARCHAR(64) NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
SQL

MIGRATIONS_DIR=/docker-entrypoint-initdb.d/snep-install/migrations
for f in "$MIGRATIONS_DIR"/*.sql; do
    [ -e "$f" ] || continue
    id="$(basename "$f" .sql)"
    checksum="$(sha256sum "$f" | awk '{print $1}')"
    # A fresh install already has this migration's full effect (schema.sql/
    # system_data.sql create it directly, per this task's own "keep schema.sql
    # in sync with every shipped migration" rule) -- record it as baselined,
    # never execute the migration file itself here.
    mysql -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" "${MARIADB_DATABASE}" \
        -e "INSERT IGNORE INTO schema_migrations (id, checksum) VALUES ('${id}', '${checksum}');"
    echo "[db-init] 99-bootstrap-marker: baselined ${id}"
done

echo "[db-init] 99-bootstrap-marker: bootstrap complete"
