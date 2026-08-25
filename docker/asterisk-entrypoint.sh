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
# TASK-0009: extensions.conf + custom/*.conf -- the vendored dialplan
# itself, never deployed into the container before this task.
SNEP_ASTERISK_DIALPLAN_SRC=/snep-asterisk-dialplan-src
ASTERISK_ETC=/etc/asterisk
# TASK-0009: GID of the senma-config group, created identically (same
# fixed GID, not auto-assigned) in both docker/asterisk.Dockerfile and
# docker/app.Dockerfile. Used below to make /etc/asterisk/snep
# group-writable without widening the rest of /etc/asterisk.
SENMA_CONFIG_GROUP=senma-config
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

# TASK-0009: astagidir (asterisk.conf) stays at the default
# /var/lib/asterisk/agi-bin. extensions.conf/snep-features.conf call AGI
# scripts as "snep/<script>.php" (a "snep/" prefix baked into the
# dialplan), so Asterisk resolves <astagidir>/snep/<script>.php. This
# symlink makes that resolve into the real, bind-mounted AGI tree --
# the same "symlink farm" pattern the legacy (non-Docker) install used
# (see TASK-0001/0008), not a new invention. Unconditional/idempotent
# (ln -sfn), not gated behind the /etc/asterisk first-boot check: this
# lives in the separate astvarlibdir volume, which can be fresh
# independently of /etc/asterisk.
mkdir -p /var/lib/asterisk/agi-bin
ln -sfn /var/www/html/snep/agi /var/lib/asterisk/agi-bin/snep

if [ ! -f "$ASTERISK_ETC/asterisk.conf" ]; then
    echo "[asterisk-entrypoint] /etc/asterisk not yet populated, assembling from vendored config"

    cp "$ASTERISK_CONFIG_SRC"/*.conf "$ASTERISK_ETC/"

    mkdir -p "$ASTERISK_ETC/snep"
    cp "$SNEP_ASTERISK_CONFIG_SRC"/*.conf "$ASTERISK_ETC/snep/"

    # TASK-0009: the real SENMA dialplan, deployed for the first time.
    # Only extensions.conf + its custom/ includes -- not the whole vendored
    # snep/install/etc/asterisk/ tree (that also contains legacy
    # sip.conf/modules.conf/etc. this Docker build deliberately does not
    # use; see docker/asterisk-config/*.conf instead).
    cp "$SNEP_ASTERISK_DIALPLAN_SRC/extensions.conf" "$ASTERISK_ETC/"
    mkdir -p "$ASTERISK_ETC/custom"
    cp "$SNEP_ASTERISK_DIALPLAN_SRC/custom/preagi.conf" \
        "$SNEP_ASTERISK_DIALPLAN_SRC/custom/posagi.conf" \
        "$SNEP_ASTERISK_DIALPLAN_SRC/custom/eof.conf" \
        "$ASTERISK_ETC/custom/"

    # TASK-0009: /etc/asterisk/snep is the one subtree SENMA's own runtime
    # (currently: nothing yet: Snep_InterfaceConf is not invoked by this
    # task) will eventually need to write. setgid so files written by
    # either the asterisk user or the app container's www-data (both
    # members of $SENMA_CONFIG_GROUP) keep the shared group; 2775 keeps
    # the rest of /etc/asterisk (0755, owned solely by asterisk:asterisk,
    # untouched above) as the Asterisk runtime's own exclusive tree.
    chgrp "$SENMA_CONFIG_GROUP" "$ASTERISK_ETC/snep"
    chmod 2775 "$ASTERISK_ETC/snep"

    # TASK-0011: setgid on the directory (above) only propagates group
    # *ownership* to files created AFTER it takes effect -- it does
    # nothing for the snep-{sip,iax2}*.conf files the `cp` above already
    # placed here (they kept mode 0644, group "asterisk", not
    # $SENMA_CONFIG_GROUP). This is why Snep_InterfaceConf::loadConfFromDb()
    # (chan_sip/IAX2 provisioning) turned out to still fail its own
    # is_writable() check for www-data even after TASK-0009 -- a real,
    # pre-existing gap that TASK-0009's own call-only scope never
    # exercised (nothing had tried to *provision* through the real UI
    # yet). Fixed the same way as $ASTERISK_ETC/snep/senma-pjsip.conf
    # below: explicit chgrp+chmod on the already-copied files.
    chgrp "$SENMA_CONFIG_GROUP" "$ASTERISK_ETC/snep"/*.conf
    chmod 664 "$ASTERISK_ETC/snep"/*.conf

    # TASK-0011: Snep_PjsipConf::loadConfFromDb() writes here. Pre-created
    # (not left for PHP to create on first write) because is_writable()
    # returns false for a path that doesn't exist yet -- the generator
    # would fail its own write-permission check on a brand new volume.
    # 0664 (not the 0644 `touch` alone would leave it at): the setgid bit
    # on $ASTERISK_ETC/snep above only propagates *group ownership* to new
    # files, not group *write* permission -- www-data (a senma-config
    # member, not the owner) needs that bit explicitly.
    touch "$ASTERISK_ETC/snep/senma-pjsip.conf"
    chmod 664 "$ASTERISK_ETC/snep/senma-pjsip.conf"

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
