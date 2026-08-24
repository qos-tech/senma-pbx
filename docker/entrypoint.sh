#!/bin/bash
set -euo pipefail

SETUP_CONF=/var/www/html/snep/includes/setup.conf
SETUP_CONF_DIST=/var/www/html/snep/includes/setup.conf.dist

# includes/setup.conf is gitignored and generated here on first boot only, so
# that (a) DB credentials come from the environment instead of being committed,
# and (b) settings the app writes back into this file (e.g. via the web UI)
# survive container restarts. Delete the file (or `make reset`) to regenerate.
if [ ! -f "$SETUP_CONF" ]; then
    echo "[entrypoint] includes/setup.conf not found, generating from setup.conf.dist + environment"
    cp "$SETUP_CONF_DIST" "$SETUP_CONF"
    sed -i \
        -e "s|^db\.host = .*|db.host = \"${DB_HOST}\"|" \
        -e "s|^db\.username = .*|db.username = \"${DB_USER}\"|" \
        -e "s|^db\.password = .*|db.password = \"${DB_PASSWORD}\"|" \
        -e "s|^db\.dbname = .*|db.dbname = \"${DB_NAME}\"|" \
        "$SETUP_CONF"
fi

# The web UI (e.g. ParametersController) writes recording-path settings back
# into this file at runtime, so it must stay writable by the Apache user.
chown www-data:www-data "$SETUP_CONF"
chmod 664 "$SETUP_CONF"

exec "$@"
