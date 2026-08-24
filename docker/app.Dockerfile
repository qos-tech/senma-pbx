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
    # Suppresses Apache's "Could not reliably determine the server's fully
    # qualified domain name" startup warning (cosmetic, but pollutes logs).
    && echo "ServerName localhost" > /etc/apache2/conf-available/mag-servername.conf \
    && a2enconf mag-servername

WORKDIR /var/www/html/snep
COPY docker/apache-mag.conf /etc/apache2/sites-available/000-default.conf
COPY docker/php-mag.ini /usr/local/etc/php/conf.d/zz-mag.ini
COPY docker/entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
EXPOSE 80

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
