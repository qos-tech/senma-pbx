# Initial scaffold; adjust after auditing the legacy runtime.
FROM php:8.4-apache

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash ca-certificates curl git libicu-dev libzip-dev mariadb-client unzip \
    && docker-php-ext-install mysqli pdo pdo_mysql intl zip \
    && a2enmod rewrite \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html/mag
COPY docker/apache-mag.conf /etc/apache2/sites-available/000-default.conf
EXPOSE 80
