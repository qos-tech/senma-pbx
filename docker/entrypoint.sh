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
else
    # TASK-0033C: this volume/bind-mount was already provisioned by an
    # earlier boot, so the block above -- the only place DB_PASSWORD/
    # AMI_PASSWORD from the environment ever reach setup.conf -- does
    # NOT run again, by this file's own first-boot-only design. If an
    # operator has since changed DB_PASSWORD/AMI_PASSWORD in .env
    # without running an explicit rotation, starting normally here would
    # leave the app silently talking to whichever credential is already
    # persisted while reporting healthy -- exactly the silent rotation
    # failure TASK-0033's own audit identified as a production blocker.
    # Fail fast and clearly instead of guessing which side is right; see
    # docs/tasks/0033c-secret-rotation-contract.md STARTUP POLICY.
    _senma_secret_coherent() {
        local declared="$1" sed_pattern="$2" label="$3" persisted dh ph
        persisted="$(sed -n "$sed_pattern" "$SETUP_CONF" | tr -d '\r\n')"
        # An empty/unmatched extraction means this line's own shape
        # changed for an unrelated reason -- not this task's concern,
        # and not something to block boot over.
        [ -z "$persisted" ] && return 0
        dh="$(printf '%s' "$declared" | sha256sum | awk '{print $1}')"
        ph="$(printf '%s' "$persisted" | sha256sum | awk '{print $1}')"
        if [ "$dh" != "$ph" ]; then
            echo "[entrypoint] ROTATION_PENDING_EXPLICIT_ACTION: declared ${label} (.env) does not match the value already persisted in includes/setup.conf." >&2
            echo "[entrypoint] Run 'make rotate-secrets' (or the matching per-secret target) to reconcile, or revert .env if this change was not intended." >&2
            echo "[entrypoint] Refusing to start on a stale/ambiguous credential -- see docs/tasks/0033c-secret-rotation-contract.md." >&2
            return 1
        fi
        return 0
    }
    _SENMA_COHERENT=1
    _senma_secret_coherent "${DB_PASSWORD}" 's/^db\.password = "\(.*\)"$/\1/p' "DB_PASSWORD" || _SENMA_COHERENT=0
    if [ -n "${ASTERISK_HOST:-}" ]; then
        _senma_secret_coherent "${AMI_PASSWORD}" 's/^pass_sock = "\(.*\)"$/\1/p' "AMI_PASSWORD" || _SENMA_COHERENT=0
    fi
    [ "$_SENMA_COHERENT" = "1" ] || exit 1
fi

# The web UI (e.g. ParametersController) writes recording-path settings back
# into this file at runtime, so it must stay writable by the Apache user.
chown www-data:www-data "$SETUP_CONF"
chmod 664 "$SETUP_CONF"

# TASK-0034O / TASK-0034I: System Status (inspectors/AGI.php) requires the
# bind-mounted AGI source tree to be writable by www-data. Host-side
# umask/ownership drift after recreate must not leave the directory
# read-only for the app user -- that falsely reds "Environment for AGI
# SNEP" and fails system-status-runtime-smoke mid-regression.
AGI_DIR=/var/www/html/snep/agi
if [ -d "$AGI_DIR" ]; then
    chown -R www-data:www-data "$AGI_DIR" || true
    chmod u+rwX "$AGI_DIR" || true
fi

# TASK-0026H (F27): idempotent -- only acts while the seeded admin row
# still holds the install-time sentinel (see
# snep/install/database/system_data.sql and docker/bootstrap-admin.php's
# own docblock). Runs on every start, not just first boot, so a database
# that only just became reachable (or was restored separately from the
# app container's own first run) still gets bootstrapped.
php /usr/local/bin/bootstrap-admin.php || echo "[entrypoint] bootstrap-admin.php failed (non-fatal, see above)"

# TASK-0033D: bounded-growth watcher for mag-error.log/ui.log -- no
# cron/systemd exists in this image, so this is backgrounded here as a
# sibling process to Apache (still under this container's PID 1 once
# `exec` below replaces the shell) rather than left unbounded. See
# docker/log-rotate-app.sh and docs/tasks/
# 0033d-diagnostics-logging-storage-lifecycle.md LOG LIFECYCLE.
/usr/local/bin/log-rotate-app.sh &

# TASK-0035A: public WSS/HTTPS certificate material for the Apache TLS
# vhost. Operators may bind-mount real cert/key over these paths (or set
# PUBLIC_WSS_CERT_FILE / PUBLIC_WSS_KEY_FILE to existing in-container
# paths). When absent, mint a DEV-ONLY self-signed fixture so local
# `make up` can exercise the proxy path without a public CA. Pilot
# acceptance still requires a non-fixture trusted certificate -- see
# scripts/wss-cert-check.sh --pilot and
# docs/tasks/0035a-reverse-proxy-wss-tls-termination-pilot-realignment.md.
SENMA_PUBLIC_CERT_DIR=/etc/senma/certs
SENMA_PUBLIC_CERT="${PUBLIC_WSS_CERT_FILE:-$SENMA_PUBLIC_CERT_DIR/public-wss.crt}"
SENMA_PUBLIC_KEY="${PUBLIC_WSS_KEY_FILE:-$SENMA_PUBLIC_CERT_DIR/public-wss.key}"
mkdir -p "$SENMA_PUBLIC_CERT_DIR"
if [ -n "${PUBLIC_WSS_CERT_FILE:-}" ] && [ -n "${PUBLIC_WSS_KEY_FILE:-}" ]; then
    if [ "$PUBLIC_WSS_CERT_FILE" != "$SENMA_PUBLIC_CERT_DIR/public-wss.crt" ]; then
        cp -f "$PUBLIC_WSS_CERT_FILE" "$SENMA_PUBLIC_CERT_DIR/public-wss.crt"
    fi
    if [ "$PUBLIC_WSS_KEY_FILE" != "$SENMA_PUBLIC_CERT_DIR/public-wss.key" ]; then
        cp -f "$PUBLIC_WSS_KEY_FILE" "$SENMA_PUBLIC_CERT_DIR/public-wss.key"
    fi
    SENMA_PUBLIC_CERT="$SENMA_PUBLIC_CERT_DIR/public-wss.crt"
    SENMA_PUBLIC_KEY="$SENMA_PUBLIC_CERT_DIR/public-wss.key"
fi
if [ ! -f "$SENMA_PUBLIC_CERT" ] || [ ! -f "$SENMA_PUBLIC_KEY" ]; then
    echo "[entrypoint] generating DEV-ONLY public WSS TLS fixture at $SENMA_PUBLIC_CERT_DIR (TASK-0035A)"
    _pub_host="${WSS_PUBLIC_HOSTNAME:-localhost}"
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "$SENMA_PUBLIC_KEY" \
        -out "$SENMA_PUBLIC_CERT" \
        -days 825 \
        -subj "/CN=senma-public-wss-dev" \
        -addext "subjectAltName=DNS:${_pub_host},DNS:localhost,DNS:app" \
        >/dev/null 2>&1
fi
chmod 644 "$SENMA_PUBLIC_CERT"
chmod 600 "$SENMA_PUBLIC_KEY"
chown www-data:www-data "$SENMA_PUBLIC_CERT" "$SENMA_PUBLIC_KEY" || true

exec "$@"
