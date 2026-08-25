#!/bin/bash
set -euo pipefail

# TASK-0005: assembles /etc/asterisk (a named volume, empty on first boot)
# from two sources:
#   1. docker/asterisk-config/*.conf -- the small, Docker-native subset of
#      files that genuinely need Docker-specific values (paths, non-root
#      user, container-network ACL, env-sourced AMI credentials). Bind-
#      mounted read-only into this container at /asterisk-config-src.
#   2. snep/install/etc/asterisk/snep/ -- the SNEP-specific config PHP
#      reads directly (snep-musiconhold.conf, etc.), copied verbatim,
#      unmodified, from the same vendored source of truth the PHP app
#      itself is built from. Bind-mounted read-only at
#      /snep-asterisk-config-src.
# This mirrors docker/entrypoint.sh's existing setup.conf.dist -> setup.conf
# generate-once-on-first-boot pattern, applied to a whole directory instead
# of a single file. Asterisk owns read-write on /etc/asterisk after this;
# re-running only re-templates if the volume is empty (idempotent, same
# guard as the app entrypoint).
#
# See docs/tasks/0005-asterisk-container-bootstrap.md.

ASTERISK_CONFIG_SRC=/asterisk-config-src
SNEP_ASTERISK_CONFIG_SRC=/snep-asterisk-config-src
ASTERISK_ETC=/etc/asterisk
ASTERISK_DOCS_BAKED=/usr/share/asterisk-documentation
ASTERISK_DOCS_DEST=/var/lib/asterisk/documentation

# TASK-0007: /etc/odbc.ini (the DSN definition) is a system path outside
# the /etc/asterisk volume -- unlike that volume's contents, it carries no
# user-editable state and nothing else depends on it persisting, so it's
# simplest to regenerate it deterministically every start rather than
# gate it behind a first-boot check. Driver referenced by the "MariaDB
# Unicode" name already registered in /etc/odbcinst.ini by the
# odbc-mariadb package at image-build time -- no architecture-specific
# driver path anywhere. Only Server/Database are templated (not
# secrets); actual DB credentials live in res_odbc.conf, templated below.
: "${DB_HOST:?DB_HOST must be set}"
: "${DB_NAME:?DB_NAME must be set}"
cat > /etc/odbc.ini <<EOF
[snep]
Description = SENMA MariaDB DSN
Driver = MariaDB Unicode
Server = ${DB_HOST}
Port = ${DB_PORT:-3306}
Database = ${DB_NAME}
Charset = utf8mb4
EOF

# /var/lib/asterisk is a named volume (for astdb/key persistence); an
# empty volume shadows the documentation baked into the image at build
# time (see docker/asterisk.Dockerfile). Stasis refuses to start without
# it, so this has to happen before "exec asterisk" every time the volume
# is empty, not just alongside the /etc/asterisk first-boot block below.
if [ ! -d "$ASTERISK_DOCS_DEST" ]; then
    echo "[asterisk-entrypoint] seeding XML documentation into the astvarlibdir volume"
    mkdir -p "$ASTERISK_DOCS_DEST"
    cp -r "$ASTERISK_DOCS_BAKED"/. "$ASTERISK_DOCS_DEST/"
fi

if [ ! -f "$ASTERISK_ETC/asterisk.conf" ]; then
    echo "[asterisk-entrypoint] /etc/asterisk not yet populated, assembling from vendored config"

    cp "$ASTERISK_CONFIG_SRC"/*.conf "$ASTERISK_ETC/"

    mkdir -p "$ASTERISK_ETC/snep"
    cp "$SNEP_ASTERISK_CONFIG_SRC"/*.conf "$ASTERISK_ETC/snep/"

    : "${AMI_USER:?AMI_USER must be set}"
    : "${AMI_PASSWORD:?AMI_PASSWORD must be set}"
    : "${ASTERISK_AMI_ACL_SUBNET:?ASTERISK_AMI_ACL_SUBNET must be set}"

    sed -i \
        -e "s|__AMI_USER__|${AMI_USER}|g" \
        -e "s|__AMI_PASSWORD__|${AMI_PASSWORD}|g" \
        -e "s|__AMI_ACL_SUBNET__|${ASTERISK_AMI_ACL_SUBNET}|g" \
        "$ASTERISK_ETC/manager.conf"

    # TASK-0007: same DB_USER/DB_PASSWORD the app container's own DB
    # connection already uses (docker/entrypoint.sh) -- one source of
    # truth for the "snep" MariaDB credentials, not a second hand-copied
    # pair.
    : "${DB_USER:?DB_USER must be set}"
    : "${DB_PASSWORD:?DB_PASSWORD must be set}"

    sed -i \
        -e "s|__DB_USER__|${DB_USER}|g" \
        -e "s|__DB_PASSWORD__|${DB_PASSWORD}|g" \
        "$ASTERISK_ETC/res_odbc.conf"
fi

exec "$@"
