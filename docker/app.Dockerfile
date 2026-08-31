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
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
EXPOSE 80

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
