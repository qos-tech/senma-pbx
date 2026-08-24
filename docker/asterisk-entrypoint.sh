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
fi

exec "$@"
