FROM php:8.4-apache

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash ca-certificates curl git libicu-dev libzip-dev mariadb-client sox unzip \
    && docker-php-ext-install mysqli pdo pdo_mysql intl zip \
    && a2enmod rewrite \
    && rm -rf /var/lib/apt/lists/* \
    # setup.conf's path.log ("/var/log/snep/") is outside the bind-mounted
    # source tree; Zend_Log fatals on boot if it doesn't exist and is
    # writable by the Apache user. See docs/tasks/0001-docker-bootstrap.md.
    && mkdir -p /var/log/snep \
    && chown www-data:www-data /var/log/snep \
    # TASK-0009: shared group for the /etc/asterisk/snep writable subtree,
    # matching docker/asterisk.Dockerfile's identical, explicitly-pinned
    # GID 3000 (not auto-assigned -- see that file for the full rationale;
    # this container's own auto-assigned system GIDs top out at 100/users
    # well below 3000). www-data does not need this group for TASK-0009
    # itself (Snep_InterfaceConf is not modified/invoked here), only the
    # filesystem architecture is being made valid ahead of that future
    # milestone. See docs/tasks/0009-first-pjsip-call.md.
    && groupadd -g 3000 senma-config \
    && usermod -aG senma-config www-data \
    # Suppresses Apache's "Could not reliably determine the server's fully
    # qualified domain name" startup warning (cosmetic, but pollutes logs).
    && echo "ServerName localhost" > /etc/apache2/conf-available/mag-servername.conf \
    && a2enconf mag-servername

WORKDIR /var/www/html/snep
COPY docker/apache-mag.conf /etc/apache2/sites-available/000-default.conf
COPY docker/php-mag.ini /usr/local/etc/php/conf.d/zz-mag.ini
COPY docker/entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY docker/bootstrap-admin.php /usr/local/bin/bootstrap-admin.php
COPY docker/migrate.php /usr/local/bin/migrate.php
COPY docker/log-rotate-app.sh /usr/local/bin/log-rotate-app.sh
COPY docker/healthcheck-app.sh /usr/local/bin/healthcheck-app.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/log-rotate-app.sh /usr/local/bin/healthcheck-app.sh
EXPOSE 80

# TASK-0034D: release identity (TASK-0034 CH-9), deliberately placed LAST
# -- BUILD_TIMESTAMP changes on every single build invocation (even a
# no-op rebuild of the identical commit/version), and a Docker build
# cache miss on any instruction invalidates every instruction after it.
# Placing this block up near FROM (tried first, live-confirmed) forced
# the entire expensive `apt-get install` layer above to rebuild from
# scratch on every build -- defeating this project's own build cache for
# no reason, and breaking the very image-id continuity `make
# release-build` -> `make pilot-up` is supposed to preserve (see docs/
# tasks/0034d-release-artifact-versioning-image-provenance.md "BUILD
# REPRODUCIBILITY BOUNDARY"). Last-instruction placement means only this
# trivial LABEL layer itself is ever rebuilt for a timestamp change.
# Defaults keep a plain `docker build .`/`make up` (no args passed)
# working exactly as before -- only `make release-build VERSION=...`
# (scripts/release-build.sh) and compose.yaml's own
# `${RELEASE_VERSION:-dev}`/`${GIT_COMMIT:-unknown}` substitution
# actually set these to a real value.
ARG RELEASE_VERSION=dev
ARG GIT_COMMIT=unknown
ARG BUILD_TIMESTAMP=unknown
LABEL org.opencontainers.image.title="SENMA PBX app" \
      org.opencontainers.image.version="${RELEASE_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.created="${BUILD_TIMESTAMP}" \
      org.opencontainers.image.source="https://github.com/qos-tech/mag-pbx" \
      org.opencontainers.image.licenses="GPL-3.0-or-later"

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
