#!/bin/bash
set -euo pipefail

# TASK-0015: minimal first-boot assembly for the local trunk-provider
# simulator. Deliberately NOT docker/asterisk-entrypoint.sh -- that
# script templates AMI/ODBC credentials, deploys the SENMA dialplan, and
# sets up the /etc/asterisk/snep writable subtree, none of which this
# container needs (it never runs SENMA's PHP/AGI/ODBC stack). Reuses the
# same already-built mag-pbx-asterisk image (docker/asterisk.Dockerfile)
# via a different entrypoint/config mount, not a second image build. See
# docs/tasks/0015-pjsip-trunk-provisioning.md.

PROVIDER_CONFIG_SRC=/provider-config-src
ASTERISK_ETC=/etc/asterisk
ASTERISK_DOCS_BAKED=/usr/share/asterisk-documentation
ASTERISK_DOCS_DEST=/var/lib/asterisk/documentation

# Same reasoning as asterisk-entrypoint.sh: astvarlibdir is a named
# volume, empty on first boot, which would otherwise shadow the
# documentation baked into the image -- Stasis refuses to start without
# it.
if [ ! -d "$ASTERISK_DOCS_DEST" ]; then
    echo "[provider-entrypoint] seeding XML documentation into the astvarlibdir volume"
    mkdir -p "$ASTERISK_DOCS_DEST"
    cp -r "$ASTERISK_DOCS_BAKED"/. "$ASTERISK_DOCS_DEST/"
fi

if [ ! -f "$ASTERISK_ETC/asterisk.conf" ]; then
    echo "[provider-entrypoint] /etc/asterisk not yet populated, assembling from docker/provider-config"

    cp "$PROVIDER_CONFIG_SRC"/*.conf "$ASTERISK_ETC/"

    : "${TRUNK_TEST_USERNAME:?TRUNK_TEST_USERNAME must be set}"
    : "${TRUNK_TEST_SECRET:?TRUNK_TEST_SECRET must be set}"

    sed -i \
        -e "s|__TRUNK_TEST_USERNAME__|${TRUNK_TEST_USERNAME}|g" \
        -e "s|__TRUNK_TEST_SECRET__|${TRUNK_TEST_SECRET}|g" \
        "$ASTERISK_ETC/pjsip.conf"
fi

exec "$@"
