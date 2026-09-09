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

# TASK-0034I: SOUNDS SEEDING. /var/lib/asterisk/sounds did not exist at
# all before this task (confirmed live) -- this Docker build never
# installed Asterisk's core sound prompts anywhere, unlike the legacy
# (non-Docker) SNEP installer, which extracted these same vendored
# tarballs (snep/install/sounds/*.tar.gz, part of the original SNEP 3.07
# import) into astvarlibdir. Consequence, also confirmed live: the
# generated dialplan (snep-features.conf's *21/*22/*23 do-not-disturb/
# call-forward toggles, *33XXXX recording beep) calls Playback() of
# named prompts (do-not-disturb, activated, de-activated, beep) that
# silently resolve to nothing without this content -- Asterisk logs a
# missing-sound warning and continues, so this was never a fatal error,
# just silent audio. SYSTEM_PROVIDED/IMAGE_IMMUTABLE content (the
# official Asterisk sound packages, not customer data), so it is seeded
# the same guarded, first-boot-only, non-destructive way as the XML
# documentation immediately above -- never re-extracted over an already
# -seeded (and potentially operator-customized, see
# Snep_SoundFiles_Manager's "AST"-type sounds) directory. "en" (a fully
# first-class SENMA-supported language -- Snep_Locale::$supportedLanguages,
# snep/lang/en.mo -- not merely optional) and "pt_BR" (the vendored
# dialplan's own [globals] default, extensions.conf) are seeded; "es" is
# NOT (POST_PILOT debt: also a supported UI language, but not this
# deployment's default/active one, and this repo vendors no "es-extra"
# package at all, so full Spanish prompt coverage is not achievable from
# vendored content alone -- see docs/tasks/
# 0034j-runtime-resource-follow-up-debt-closure.md D2).
#
# TASK-0034J (D2) correction of a TASK-0034I finding: `astcc-unavail` is
# NOT called by any deployed dialplan (confirmed via grep across
# snep/install/etc/asterisk/snep/*.conf) -- 0034I's own inventory of
# snep-features.conf's Playback() targets was wrong to include it, and
# it is irrelevant to English/Spanish coverage either way. The prompts
# actually Playback()'d are `beep` (present in the "core" en package,
# seeded immediately below) and `do-not-disturb`/`activated`/
# `de-activated` (absent from the "core" en package, confirmed via
# `tar tzf`, but present in the vendored "extra sounds" en superset) --
# those three are seeded individually further below rather than the
# whole ~1400-file/36MB extra package, matching this task's own "no
# large media bundle without justification" instruction.
SENMA_SOUNDS_SRC=/snep-sounds-src
ASTERISK_SOUNDS_DIR=/var/lib/asterisk/sounds
# Bare (no language subdirectory) is Asterisk's own convention for its
# default/fallback language -- matches how the vendored en tarball's
# members are laid out (flat *.wav, no leading directory, verified via
# `tar tzf`). Group-writable so Snep_SoundFiles_Manager's own "AST" sound
# uploads (which always target $sound_path/$lang, i.e. this exact
# directory when the configured language is "en") can add files here,
# same as every operator-writable path in this script.
if [ ! -d "$ASTERISK_SOUNDS_DIR" ]; then
    echo "[asterisk-entrypoint] seeding Asterisk core sound prompts (en) into the astvarlibdir volume"
    mkdir -p "$ASTERISK_SOUNDS_DIR"
    tar -xzf "$SENMA_SOUNDS_SRC/asterisk-core-sounds-en-wav-current.tar.gz" -C "$ASTERISK_SOUNDS_DIR"
    chgrp "$SENMA_CONFIG_GROUP" "$ASTERISK_SOUNDS_DIR"
    chmod 2775 "$ASTERISK_SOUNDS_DIR"
fi

# TASK-0034J (D2): the three English prompts snep-features.conf actually
# calls that the "core" package above does not carry. Per-file guard
# (not nested inside the directory-existence check above) so an already-
# seeded volume from before this task also retrofits them on its next
# boot, matching the tmp/backup retrofit pattern further below.
for prompt in do-not-disturb activated de-activated; do
    if [ ! -f "$ASTERISK_SOUNDS_DIR/$prompt.wav" ]; then
        echo "[asterisk-entrypoint] seeding missing English prompt: $prompt.wav (asterisk-extra-sounds-en)"
        tar -xzf "$SENMA_SOUNDS_SRC/asterisk-extra-sounds-en-wav-current.tar.gz" -C "$ASTERISK_SOUNDS_DIR" "$prompt.wav"
        chgrp "$SENMA_CONFIG_GROUP" "$ASTERISK_SOUNDS_DIR/$prompt.wav"
        chmod 664 "$ASTERISK_SOUNDS_DIR/$prompt.wav"
    fi
done

if [ ! -d "$ASTERISK_SOUNDS_DIR/pt_BR" ]; then
    echo "[asterisk-entrypoint] seeding Asterisk core sound prompts (pt_BR) into the astvarlibdir volume"
    mkdir -p "$ASTERISK_SOUNDS_DIR/pt_BR"
    tar -xzf "$SENMA_SOUNDS_SRC/asterisk-core-sounds-pt_BR-wav.tgz" -C "$ASTERISK_SOUNDS_DIR/pt_BR"
    chgrp "$SENMA_CONFIG_GROUP" "$ASTERISK_SOUNDS_DIR/pt_BR"
    chmod 2775 "$ASTERISK_SOUNDS_DIR/pt_BR"
fi
# SoundFilesController::addAction()/editAction() need <lang-root>/tmp
# and <lang-root>/backup to exist (upload staging + edit-history backup
# -- "en" treated as Asterisk's own no-subdirectory default, so its
# lang-root IS the bare $ASTERISK_SOUNDS_DIR, confirmed by reading that
# controller). Deliberately UNCONDITIONAL/idempotent, not nested inside
# the seed guards above: a volume already seeded by an earlier version
# of this script (before these two subfolders were added here) would
# otherwise never retrofit them, since the outer directory already
# exists and its own guard would short-circuit. mkdir -p is a no-op if
# already present; chgrp/chmod are cheap enough to reapply every boot
# and self-heal ownership if anything else ever created these first.
for lang_root in "$ASTERISK_SOUNDS_DIR" "$ASTERISK_SOUNDS_DIR/pt_BR"; do
    mkdir -p "$lang_root/tmp" "$lang_root/backup"
    chgrp "$SENMA_CONFIG_GROUP" "$lang_root/tmp" "$lang_root/backup"
    chmod 2775 "$lang_root/tmp" "$lang_root/backup"
done

# TASK-0034I: MOH DIRECTORY. CUSTOMER_MANAGED, starts empty -- no default
# MOH audio is seeded (no MOH-specific tarball is vendored in this repo,
# and inventing/bundling arbitrary music is explicitly out of scope; see
# the task doc's MOH DECISION). This only provisions the directory
# snep-musiconhold.conf's own [default] class already points at
# (directory=/var/lib/asterisk/moh, written by
# Snep_SoundFiles_Manager::addClass()) plus the tmp/backup subfolders
# every MOH class directory needs (inspectors/Sounds.php's own
# requirement -- see snep/lib/Snep/SoundFiles/Manager.php's addClass(),
# which creates these same two subfolders for every class an admin adds
# through the UI). Group-owned senma-config/2775, matching the identical
# $ASTERISK_ETC/snep pattern below -- this directory is the one
# astvarlibdir path www-data (via the app container's own
# mag-asterisk-var mount, see compose.yaml) must be able to write into.
ASTERISK_MOH_DIR=/var/lib/asterisk/moh
if [ ! -d "$ASTERISK_MOH_DIR" ]; then
    echo "[asterisk-entrypoint] provisioning the default Music-on-Hold class directory"
    mkdir -p "$ASTERISK_MOH_DIR/tmp" "$ASTERISK_MOH_DIR/backup"
    chgrp -R "$SENMA_CONFIG_GROUP" "$ASTERISK_MOH_DIR"
    chmod 2775 "$ASTERISK_MOH_DIR" "$ASTERISK_MOH_DIR/tmp" "$ASTERISK_MOH_DIR/backup"
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

# TASK-0028Z: self-signed TEST-ONLY TLS certificate for the http.conf
# WSS listener (docker/asterisk-config/http.conf's tlscertfile/
# tlsprivatekey). Generated once, at first boot, directly into the
# persistent asterisk-etc volume -- guarded independently of the
# asterisk.conf check below so an existing dev volume created before
# this task also gets a cert on its next start without re-seeding
# anything else. Never committed to git, never baked into the image.
# Full certificate lifecycle management (customer-supplied certs, CA
# config, rotation, an upload UI) is reserved for TASK-0029A; this is
# only the minimal fixture needed to prove the WSS platform path works.
ASTERISK_TLS_KEY_DIR="$ASTERISK_ETC/keys"
if [ ! -f "$ASTERISK_TLS_KEY_DIR/wss-test-cert.pem" ]; then
    echo "[asterisk-entrypoint] generating self-signed TEST-ONLY TLS certificate for WSS (see TASK-0028Z; TASK-0029A must supply real certificate management)"
    mkdir -p "$ASTERISK_TLS_KEY_DIR"
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "$ASTERISK_TLS_KEY_DIR/wss-test-key.pem" \
        -out "$ASTERISK_TLS_KEY_DIR/wss-test-cert.pem" \
        -days 3650 \
        -subj "/CN=senma-wss-test" \
        -addext "subjectAltName=DNS:asterisk,DNS:localhost"
    chmod 600 "$ASTERISK_TLS_KEY_DIR/wss-test-key.pem"
    chmod 644 "$ASTERISK_TLS_KEY_DIR/wss-test-cert.pem"
fi

# TASK-0028Z: http.conf needs the same independent-guard treatment as
# the TLS certificate above -- a dev volume created before this task
# already has asterisk.conf populated, so the first-boot block below
# (gated on asterisk.conf's own existence) will never run again on it,
# and it would otherwise never receive http.conf at all.
if [ ! -f "$ASTERISK_ETC/http.conf" ]; then
    echo "[asterisk-entrypoint] seeding http.conf (WSS platform enablement, TASK-0028Z)"
    cp "$ASTERISK_CONFIG_SRC/http.conf" "$ASTERISK_ETC/http.conf"
fi

# TASK-0034I: same independent-guard treatment as http.conf above -- an
# existing dev/pilot volume already has asterisk.conf populated, so the
# first-boot block below never runs again on it, and it would otherwise
# never receive musiconhold.conf at all (this is the exact root cause of
# "moh show classes" being empty and "No music on hold classes
# configured, disabling music on hold." on every boot, confirmed live,
# even though /etc/asterisk/snep/snep-musiconhold.conf's own [default]
# class was present and correct the whole time -- nothing ever
# #included it). See docs/tasks/
# 0034i-system-status-dependency-runtime-resource-closure.md.
if [ ! -f "$ASTERISK_ETC/musiconhold.conf" ]; then
    echo "[asterisk-entrypoint] seeding musiconhold.conf (TASK-0034I, closes the MOH #include gap)"
    cp "$ASTERISK_CONFIG_SRC/musiconhold.conf" "$ASTERISK_ETC/musiconhold.conf"
fi

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

    # TASK-0015: Snep_PjsipTrunkConf::loadConfFromDb() writes here -- same
    # pre-create-and-chmod reasoning as senma-pjsip.conf immediately above.
    touch "$ASTERISK_ETC/snep/senma-pjsip-trunks.conf"
    chmod 664 "$ASTERISK_ETC/snep/senma-pjsip-trunks.conf"

    # TASK-0018: Snep_PjsipTransportConf::loadConfFromDb() writes here --
    # same pre-create-and-chmod reasoning as senma-pjsip.conf above. This
    # is now the FIRST #include in pjsip.conf (docker/asterisk-config/
    # pjsip.conf) -- the static [transport-udp] stanza it replaces is gone.
    touch "$ASTERISK_ETC/snep/senma-pjsip-transports.conf"
    chmod 664 "$ASTERISK_ETC/snep/senma-pjsip-transports.conf"

    # TASK-0029A: Snep_PjsipTransportConf::writeHttpTlsConf() writes
    # here -- same pre-create-and-chmod reasoning as senma-pjsip.conf
    # above. #include'd from docker/asterisk-config/http.conf's
    # [general] section.
    touch "$ASTERISK_ETC/snep/senma-http-tls.conf"
    chmod 664 "$ASTERISK_ETC/snep/senma-http-tls.conf"

    : "${AMI_USER:?AMI_USER must be set}"
    : "${AMI_PASSWORD:?AMI_PASSWORD must be set}"
    : "${ASTERISK_AMI_ACL_SUBNET:?ASTERISK_AMI_ACL_SUBNET must be set}"

    # TASK-0034F (Phase 29): fail fast, clearly, on an unsafe or
    # malformed AMI ACL rather than let a typo/misconfiguration silently
    # widen (or simply break) manager.conf's own trust boundary. Plain
    # regex, not a full IPv4-semantics validator (no octet-range check)
    # -- deliberately narrow scope: this exists to catch "not a CIDR at
    # all" and the one specific unsafe value below, not to be a general
    # network-config linter.
    case "$ASTERISK_AMI_ACL_SUBNET" in
        [0-9]*.[0-9]*.[0-9]*.[0-9]*/[0-9]*) : ;;
        *)
            echo "[asterisk-entrypoint] FATAL: ASTERISK_AMI_ACL_SUBNET='${ASTERISK_AMI_ACL_SUBNET}' is not a valid IPv4 CIDR (expected e.g. 172.29.0.0/24)" >&2
            exit 1
            ;;
    esac
    if [ "$ASTERISK_AMI_ACL_SUBNET" = "0.0.0.0/0" ] && [ "${AMI_ACL_ALLOW_UNSAFE_SUBNET:-0}" != "1" ]; then
        echo "[asterisk-entrypoint] FATAL: ASTERISK_AMI_ACL_SUBNET=0.0.0.0/0 would permit AMI from any address -- never a safe pilot/production default." >&2
        echo "[asterisk-entrypoint] Set the real dedicated-network subnet instead (see .env.example). Set AMI_ACL_ALLOW_UNSAFE_SUBNET=1 only for a deliberate, isolated development experiment -- never on a pilot/production host." >&2
        exit 1
    fi

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

else
    # TASK-0033C: this asterisk-etc volume was already provisioned by an
    # earlier boot, so the block above -- the only place AMI_PASSWORD/
    # DB_PASSWORD from the environment ever reach manager.conf/
    # res_odbc.conf -- does NOT run again, by this file's own
    # first-boot-only design (guarded on asterisk.conf's existence). If
    # an operator has since changed AMI_PASSWORD/DB_PASSWORD in .env
    # without running an explicit rotation, starting normally here would
    # leave Asterisk silently running with whichever credential is
    # already persisted while reporting healthy -- exactly the silent
    # rotation failure TASK-0033's own audit identified as a production
    # blocker. Fail fast and clearly instead; see docs/tasks/
    # 0033c-secret-rotation-contract.md STARTUP POLICY.
    _senma_secret_coherent() {
        local declared="$1" sed_pattern="$2" file="$3" label="$4" persisted dh ph
        persisted="$(sed -n "$sed_pattern" "$file" | head -1 | tr -d '\r\n')"
        [ -z "$persisted" ] && return 0
        dh="$(printf '%s' "$declared" | sha256sum | awk '{print $1}')"
        ph="$(printf '%s' "$persisted" | sha256sum | awk '{print $1}')"
        if [ "$dh" != "$ph" ]; then
            echo "[asterisk-entrypoint] ROTATION_PENDING_EXPLICIT_ACTION: declared ${label} (.env) does not match the value already persisted in ${file}." >&2
            echo "[asterisk-entrypoint] Run 'make rotate-secrets' (or the matching per-secret target) to reconcile, or revert .env if this change was not intended." >&2
            echo "[asterisk-entrypoint] Refusing to start on a stale/ambiguous credential -- see docs/tasks/0033c-secret-rotation-contract.md." >&2
            return 1
        fi
        return 0
    }
    _SENMA_COHERENT=1
    _senma_secret_coherent "${AMI_PASSWORD:-}" 's/^secret = \(.*\)$/\1/p' "$ASTERISK_ETC/manager.conf" "AMI_PASSWORD" || _SENMA_COHERENT=0
    _senma_secret_coherent "${DB_PASSWORD:-}" 's/^password => \(.*\)$/\1/p' "$ASTERISK_ETC/res_odbc.conf" "DB_PASSWORD" || _SENMA_COHERENT=0
    [ "$_SENMA_COHERENT" = "1" ] || exit 1
fi

# TASK-0033D: bounded-growth watcher for /var/log/asterisk/{full,queue_log}
# -- no cron/systemd exists in this image, so this is backgrounded here
# as a sibling process to Asterisk (still under this container's PID 1
# once `exec` below replaces the shell) rather than left unbounded. See
# docker/log-rotate-asterisk.sh and docs/tasks/
# 0033d-diagnostics-logging-storage-lifecycle.md LOG LIFECYCLE.
/usr/local/bin/log-rotate-asterisk.sh &

exec "$@"
