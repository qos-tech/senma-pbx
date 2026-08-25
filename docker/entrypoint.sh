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

    # TASK-0005: AMI connection details. ip_sock must resolve to the
    # Compose service name, not the legacy default of 127.0.0.1 -- Asterisk
    # is a separate container now, not co-located on the same host.
    # user_sock/pass_sock are sourced from the same AMI_USER/AMI_PASSWORD
    # env vars asterisk-entrypoint.sh uses to template manager.conf, so
    # both sides are guaranteed to agree without hand-copying a value into
    # two places.
    if [ -n "${ASTERISK_HOST:-}" ]; then
        sed -i \
            -e "s|^ip_sock = .*|ip_sock = \"${ASTERISK_HOST}\"|" \
            -e "s|^user_sock = .*|user_sock = \"${AMI_USER}\"|" \
            -e "s|^pass_sock = .*|pass_sock = \"${AMI_PASSWORD}\"|" \
            "$SETUP_CONF"
    fi

    # TASK-0012: path.web is the application's web base URL (distinct
    # from path.base, the filesystem path, untouched). Defaults to ""
    # (root deployment, this project's actual Docker topology -- see
    # docs/tasks/0012-web-base-path-cleanup.md for why setup.conf.dist's
    # own inherited "/snep" default was wrong here). Set
    # SENMA_WEB_BASE_PATH (e.g. "/snep") only for a genuine subdirectory
    # deployment; never both a leading path here and root in reality.
    sed -i \
        -e "s|^path\.web = .*|path.web = \"${SENMA_WEB_BASE_PATH:-}\"|" \
        "$SETUP_CONF"
fi

# The web UI (e.g. ParametersController) writes recording-path settings back
# into this file at runtime, so it must stay writable by the Apache user.
chown www-data:www-data "$SETUP_CONF"
chmod 664 "$SETUP_CONF"

exec "$@"
