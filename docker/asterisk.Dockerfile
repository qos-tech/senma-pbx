# Asterisk 22 LTS, compiled from source (TASK-0005).
#
# Debian 13 (trixie) ships no `asterisk` package at all (verified via
# `apt-cache madison asterisk` against the official trixie repos -- empty
# result), so a from-source build is not a choice made for its own sake, it's
# the only option. Version pinned to 22.10.1, the latest non-prerelease
# Asterisk 22 LTS release as of this task (confirmed against the GitHub
# releases API; 22.11.0 exists only as a release candidate). See
# docs/tasks/0005-asterisk-container-bootstrap.md for the full version
# rationale.
#
# Deliberately minimal module set for hardware/legacy technologies this
# project does not use: no chan_dahdi/Khomp/H323/OSS. Their build
# dependencies are simply not installed below, so Asterisk's own
# ./configure dependency detection excludes those modules automatically --
# the same outcome the legacy installer reached via modules.conf `noload`
# lines, achieved one layer earlier. modules.conf still carries explicit
# `noload` lines too, as a second, explicit gate.
#
# PJSIP (TASK-0009): enabled via Asterisk's bundled pjproject build (see
# --with-pjproject-bundled below) -- Debian 13 ships no system `pjproject`
# package at all (verified: empty apt-cache result), so the bundled build
# is not a choice made for its own sake, it's the only option. See
# docs/tasks/0009-first-pjsip-call.md for the version/reproducibility
# investigation.
FROM debian:13-slim AS build

ARG DEBIAN_FRONTEND=noninteractive
ARG ASTERISK_VERSION=22.10.1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl \
        libedit-dev libjansson-dev libsqlite3-dev libssl-dev libxml2-dev \
        libcurl4-openssl-dev unixodbc-dev uuid-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src
RUN curl -fsSL -o asterisk.tar.gz \
        "https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${ASTERISK_VERSION}.tar.gz" \
    && tar -xzf asterisk.tar.gz \
    && rm asterisk.tar.gz

WORKDIR /usr/src/asterisk-${ASTERISK_VERSION}

# --with-pjproject-bundled (TASK-0009, the default -- explicit here for
# documentation): downloads and builds Asterisk's own vendored pjproject
# copy (2.17). third-party/Makefile.rules fetches
# pjproject-2.17.tar.bz2 from downloads.asterisk.org and verifies it
# against third-party/pjproject/pjproject-2.17.tar.bz2.md5, a checksum
# file physically shipped inside this exact Asterisk 22.10.1 source
# tarball (not fetched from the same server at build time) -- so the
# pjproject version is pinned by, and reproducible from, this Asterisk
# release, not "whatever pjproject is latest" at build time. TASK-0005
# originally disabled this (--without-pjproject-bundled) since PJSIP was
# out of scope then; see docs/tasks/0009-first-pjsip-call.md.
RUN ./configure --with-pjproject-bundled \
    && make menuselect.makeopts \
    && make -j"$(nproc)" \
    && make install \
    && make install-headers \
    && ldconfig

# --- Runtime image -----------------------------------------------------

FROM debian:13-slim

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates libedit2 libjansson4 libsqlite3-0 libssl3 \
        libxml2 libcurl4 unixodbc odbc-mariadb uuid-runtime \
    # TASK-0009: the real SENMA AGI entrypoints (bind-mounted below, see
    # compose.yaml) now run inside this container for the first time --
    # previously it had no PHP interpreter at all. Traced the actual
    # Bootstrap.php + internal-call code path (Snep_Db's Pdo_Mysql
    # adapter, Snep_Modules' simplexml_load_file() module registration,
    # pcntl_signal signal handling) rather than mirroring app.Dockerfile's
    # extension set wholesale -- ext-intl/ext-zip/ext-mbstring are
    # genuinely unused on this path (verified: no mb_*/Locale::/
    # ZipArchive calls reached from Bootstrap.php or snep.php's dialplan
    # execution) and are deliberately NOT installed here. php8.4-cli
    # provides /usr/bin/php; php8.4-cgi (which depends on php8.4-cli)
    # provides /usr/bin/php-cgi -- both AGI shebangs need to resolve.
    # php8.4-mysql provides pdo_mysql (Snep_Db::getInstance() uses the
    # 'Pdo_Mysql' Zend_Db adapter). php8.4-xml provides simplexml/dom
    # (Snep_Modules::registerModule() parses every modules/*/info.xml and
    # resources.xml on every single AGI invocation, via Bootstrap.php's
    # startModules()). See docs/tasks/0009-first-pjsip-call.md.
        php8.4-cli php8.4-cgi php8.4-mysql php8.4-xml \
    && rm -rf /var/lib/apt/lists/* \
    # Dedicated non-root runtime user, matching current Asterisk packaging
    # convention -- the legacy installer ran Asterisk as root
    # (asterisk.conf's runuser/rungroup were left commented out); that is
    # not replicated here, per this task's explicit instruction.
    && groupadd -r asterisk \
    && useradd -r -g asterisk -d /var/lib/asterisk -s /usr/sbin/nologin asterisk \
    # TASK-0009: shared group for the /etc/asterisk/snep writable subtree
    # (see docker-entrypoint.sh). GID 3000 is deliberately hardcoded
    # identically here and in app.Dockerfile -- not left to groupadd's
    # auto-allocation, which is independent per image and NOT guaranteed
    # to land on the same number in both (this image's own auto-assigned
    # system GIDs already run up to 999, e.g. systemd-journal). 3000 is
    # chosen because it sits above both images' observed auto-assigned
    # system-group range (checked empirically: max auto-assigned GID in
    # either image is 999) and below the conventional "real user" 1000+
    # range some distros/host systems use, minimizing collision risk with
    # both auto-assigned system groups and any host-mapped UID/GID.
    && groupadd -g 3000 senma-config \
    && usermod -aG senma-config asterisk

COPY --from=build /usr/sbin/asterisk /usr/sbin/asterisk
COPY --from=build /usr/sbin/astgenkey /usr/sbin/astgenkey
COPY --from=build /usr/sbin/astversion /usr/sbin/astversion
COPY --from=build /usr/lib/asterisk /usr/lib/asterisk
COPY --from=build /usr/lib/libasteriskssl.so* /usr/lib/
# TASK-0009: libasteriskpj.so.* -- Asterisk's own wrapper around the
# bundled pjproject build, dynamically linked by chan_pjsip.so/res_pjsip*.
# Wasn't needed before this task (no PJPROJECT build existed).
COPY --from=build /usr/lib/libasteriskpj.so* /usr/lib/
RUN ldconfig

RUN mkdir -p /etc/asterisk /var/lib/asterisk /var/spool/asterisk \
        /var/log/asterisk /var/run/asterisk /var/log/snep \
    && chown -R asterisk:asterisk /etc/asterisk /var/lib/asterisk \
        /var/spool/asterisk /var/log/asterisk /var/run/asterisk \
    # TASK-0009: /var/log/snep -- Bootstrap.php's startLogger() (run on
    # every single AGI invocation) unconditionally opens
    # <path.log>/agi.log via Zend_Log_Writer_Stream, independent of
    # Asterisk's own /var/log/asterisk. Matches app.Dockerfile's identical
    # /var/log/snep (docker/entrypoint.sh, TASK-0001) -- same path, same
    # setup.conf path.log value, now needed in this container too since
    # real AGI execution is new as of this task.
    && chown asterisk:asterisk /var/log/snep \
    # TASK-0007: /etc/odbc.ini (the DSN definition, unlike /etc/odbcinst.ini
    # which the odbc-mariadb package already owns/creates) is regenerated by
    # asterisk-entrypoint.sh on every start -- it must be asterisk-writable
    # since the process runs as that non-root user throughout.
    && touch /etc/odbc.ini && chown asterisk:asterisk /etc/odbc.ini

# Core XML documentation -- required at startup: Stasis (Asterisk's
# internal message bus, initialized unconditionally regardless of this
# task's reduced module scope) registers its message types against this
# documentation and refuses to start without it ("Stasis initialization
# failed" was the first real boot failure encountered in this task; see
# docs/tasks/0005-asterisk-container-bootstrap.md). Baked into an
# image-only path, not directly into /var/lib/asterisk/documentation,
# because /var/lib/asterisk is volume-mounted (for astdb/keys
# persistence) and an empty named volume would shadow it on first run;
# asterisk-entrypoint.sh seeds it into the volume on first boot, same
# pattern as /etc/asterisk.
COPY --from=build /var/lib/asterisk/documentation /usr/share/asterisk-documentation
RUN chown -R asterisk:asterisk /usr/share/asterisk-documentation

COPY docker/php-agi.ini /etc/php/8.4/cgi/conf.d/99-senma-agi.ini
COPY docker/php-agi.ini /etc/php/8.4/cli/conf.d/99-senma-agi.ini

COPY docker/asterisk-entrypoint.sh /usr/local/bin/asterisk-entrypoint.sh
RUN chmod +x /usr/local/bin/asterisk-entrypoint.sh

USER asterisk
ENTRYPOINT ["asterisk-entrypoint.sh"]
CMD ["asterisk", "-f", "-vvv"]
