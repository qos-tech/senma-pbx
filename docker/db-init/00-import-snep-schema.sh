#!/bin/bash
set -euo pipefail

# Runs once, only when the MariaDB data directory is first initialized
# (standard docker-entrypoint-initdb.d behavior), so this is safe to leave
# in place across restarts.
#
# Deliberately NOT imported here (see docs/tasks/0001-legacy-runtime-audit.md
# and docs/tasks/0001-docker-bootstrap.md for details):
#
#   - install/database/database.sql: its CREATE DATABASE / GRANT ... TO
#     'snep'@'localhost' statements are superseded by this image's own
#     MARIADB_DATABASE/MARIADB_USER/MARIADB_PASSWORD provisioning, and the
#     localhost-only grant would not allow the app container to connect anyway.
#   - install/database/core-cnl.sql: inserts into core_cnl_state,
#     core_cnl_prefix and core_cnl_city, none of which have a CREATE TABLE
#     anywhere in this checkout (only install/database/update/3.01+ create
#     them, and INSTALL_GUIDE.md's own fresh-install steps never run that
#     update chain either). Importing it as-is aborts partway through.
#   - modules/loguser/install/schema.sql: modules/loguser/ does not exist in
#     this repository snapshot. The one table it would define (logs_users,
#     used by Snep_LogUser / Snep_Audit_Manager) is already created by
#     schema.sql below.
#   - modules/portability/install/routes.sql: inserts into regras_negocio,
#     which has the same missing-table problem as core_cnl_state above.
#
# Reference/lookup data (CNL country-code lookups, portability routing rules)
# is therefore not seeded yet; this does not block the web UI from booting.

SNEP_INSTALL=/docker-entrypoint-initdb.d/snep-install
SNEP_BILLING=/docker-entrypoint-initdb.d/snep-billing

mysql_import() {
    echo "[db-init] importing $1"
    # These dumps were authored against MySQL 5.x's lenient default sql_mode
    # (e.g. NOT NULL text columns with no explicit default in seed INSERTs).
    # MariaDB 10.11 defaults to STRICT_TRANS_TABLES, which rejects that.
    # Clearing sql_mode for the import session reproduces the original
    # target behavior without touching the schema or seed data. (MariaDB's
    # mysql client has no --sql-mode flag, hence --init-command.)
    mysql --init-command="SET SESSION sql_mode='';" -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" "${MARIADB_DATABASE}" < "$1"
}

mysql_import "${SNEP_INSTALL}/schema.sql"
mysql_import "${SNEP_INSTALL}/system_data.sql"
mysql_import "${SNEP_BILLING}/schema.sql"

echo "[db-init] SNEP schema import complete"
