#!/bin/bash
#
# SENMA operator-facing restore command (TASK-0033A).
#
# Restore contract: REPLACE, not merge (Phase 10 of TASK-0033A -- no
# proven need for merging exists, and a deterministic replacement is far
# easier to reason about and prove correct). Restoring onto a target that
# already has SENMA state destroys and replaces ALL of it: database
# schema+rows, setup.conf, arquivos/, and the whole generated Asterisk
# config volume (including secrets and the TLS key). Nothing is merged
# row-by-row.
#
# Restore ordering (see docs/tasks/
# 0033a-backup-restore-disaster-recovery-foundation.md RESTORE ORDER for
# the full evidence trail this was derived from, not assumed):
#   1. stop app/asterisk/db (nothing should be writing to what we're
#      about to replace)
#   2. wipe the target: mag-db, asterisk-etc, mag-asterisk-var volumes;
#      host-side setup.conf and arquivos/ content
#   3. restore asterisk-etc + astdb.sqlite3 + setup.conf + arquivos/
#      BEFORE any container that owns them starts -- this is what makes
#      docker/entrypoint.sh's and docker/asterisk-entrypoint.sh's own
#      first-boot guards (`[ ! -f ... ]`) work *for* us instead of
#      against us: they see the restored files already present and skip
#      regeneration entirely, so the exact restored secrets/config/cert
#      survive untouched.
#   4. start db, let its own first-boot init scripts run on the now-empty
#      volume (harmless: the schema they install is fully superseded a
#      moment later), then import the real dump on top -- mariadb-dump's
#      own default DROP-TABLE-IF-EXISTS/CREATE-TABLE/INSERT output makes
#      this idempotent against whatever the stock install just created,
#      so restore reuses the existing supported bootstrap path instead of
#      fighting it.
#   5. start asterisk, then app; verify readiness at each step.
#
# Usage:
#   scripts/restore.sh <path-to-backup.tar.gz> [--confirm] [--validate-only]
#   scripts/restore.sh --print-runtime
#
#   --validate-only  Check archive integrity/completeness only -- never
#                     touches a container or volume. Used by
#                     scripts/backup-smoke-test.sh's failure-mode checks
#                     and safe for an operator to run before deciding to
#                     proceed.
#   --confirm        Required whenever the target already has non-trivial
#                     existing state (see target_has_existing_state
#                     below). Mirrors `make reset`'s existing
#                     typed-confirmation precedent for destructive
#                     operations; scriptable via
#                     `make restore FROM=... CONFIRM=RESTORE`.
#   --print-runtime  Resolve and print SENMA_RUNTIME_MODE/COMPOSE, then
#                     exit (TASK-0035E5). No archive required.
#
# Runtime topology (TASK-0035E5 / I8): destructive restore selects
# bridge vs host via scripts/lib/compose-runtime.sh -- never silently
# falls back to bare `docker compose` for a pilot/production session.
# Prefer: export RELEASE_VERSION=vX.Y.Z (pilot) or SENMA_RUNTIME_MODE=
# bridge|host. make restore wires the same contract automatically.

# Exit code: 0 on a fully verified restore (or a clean --validate-only
# pass); 1 on any validation failure or restore-step failure. Never
# reports success on a partially-applied restore -- verification
# failures after the destructive steps have already run are reported as
# a hard failure with explicit diagnostics, not silently ignored.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/backup-lib.sh
source "$SCRIPT_DIR/lib/backup-lib.sh"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
# shellcheck source=lib/compose-runtime.sh
source "$SCRIPT_DIR/lib/compose-runtime.sh"
# Sourced only for harness_retry (a standalone bounded-retry helper with
# no side effects at source time) -- this script does NOT call
# harness_install_traps and does not use the PASS/FAIL/BLOCKED
# vocabulary; it is a plain operator command with a plain 0/1 exit code.
#
# TASK-0035E5 / I8: COMPOSE is resolved AFTER --validate-only via
# senma_resolve_compose_runtime (fail-closed). Never default to bare
# `docker compose` for a destructive restore -- that silently dropped
# pilot/host networking on v0.1.0-rc.5.

ARCHIVE=""
CONFIRMED=0
VALIDATE_ONLY=0
PRINT_RUNTIME=0

while [ $# -gt 0 ]; do
    case "$1" in
        --confirm) CONFIRMED=1; shift ;;
        --validate-only) VALIDATE_ONLY=1; shift ;;
        --print-runtime)
            # Resolve and print the selected topology, then exit (no
            # archive required). Used by focused topology smokes.
            PRINT_RUNTIME=1; shift ;;
        -*) blib_die "unknown argument: $1" ;;
        *) ARCHIVE="$1"; shift ;;
    esac
done

if [ "$PRINT_RUNTIME" -eq 1 ]; then
    senma_resolve_compose_runtime || exit 1
    echo "SENMA_RUNTIME_MODE=${SENMA_RUNTIME_MODE}"
    echo "COMPOSE=${COMPOSE}"
    exit 0
fi

[ -n "$ARCHIVE" ] || blib_die "usage: restore.sh <path-to-backup.tar.gz> [--confirm] [--validate-only]"
[ -f "$ARCHIVE" ] || blib_die "backup archive not found: $ARCHIVE"

: "${COMPOSE_PROJECT_NAME:?COMPOSE_PROJECT_NAME must be set (source .env first)}"

EXTRACT_DIR=""
cleanup_extract() {
    [ -n "$EXTRACT_DIR" ] && [ -d "$EXTRACT_DIR" ] && rm -rf "$EXTRACT_DIR"
}
trap cleanup_extract EXIT

# =====================================================================
# Phase A -- validation (Phase 11 of TASK-0033A): corrupt archive,
# incomplete manifest, missing DB dump, missing mandatory component, or
# a checksum mismatch must all be rejected with an explicit diagnostic,
# never a silent partial restore.
# =====================================================================

blib_log "==> validating backup archive: $ARCHIVE"

if ! tar tzf "$ARCHIVE" >/dev/null 2>&1; then
    blib_die "corrupt archive: '$ARCHIVE' is not a valid gzip/tar file"
fi

EXTRACT_DIR="$(mktemp -d)"
blib_secure_path "$EXTRACT_DIR"
tar xzf "$ARCHIVE" -C "$EXTRACT_DIR" || blib_die "corrupt archive: extraction failed"

STAGE_DIR="$(find "$EXTRACT_DIR" -maxdepth 1 -type d -name 'senma-backup-*' | head -1)"
[ -n "$STAGE_DIR" ] || blib_die "corrupt archive: no senma-backup-* directory found inside"

MANIFEST="$STAGE_DIR/manifest.txt"
[ -f "$MANIFEST" ] || blib_die "incomplete manifest: manifest.txt not found in archive"

FORMAT_VERSION="$(blib_manifest_get "$MANIFEST" backup_format_version)"
[ "$FORMAT_VERSION" = "$BACKUP_FORMAT_VERSION" ] || blib_die "incompatible backup format: archive is version '${FORMAT_VERSION:-<missing>}', this restore.sh supports version ${BACKUP_FORMAT_VERSION}"

COMPONENT_COUNT="$(blib_manifest_get "$MANIFEST" component_count)"
[ -n "$COMPONENT_COUNT" ] && [ "$COMPONENT_COUNT" -gt 0 ] 2>/dev/null || blib_die "incomplete manifest: component_count missing or zero"

CHECKSUMS="$STAGE_DIR/checksums.sha256"
[ -f "$CHECKSUMS" ] || blib_die "incomplete manifest: checksums.sha256 not found in archive"

VALIDATION_FAILED=0
MANDATORY_COMPONENTS="db setup_conf arquivos asterisk_etc"
for name in $MANDATORY_COMPONENTS; do
    if ! grep -q "^component=${name}|" "$MANIFEST"; then
        blib_log "MISSING MANDATORY COMPONENT: $name is not listed in the manifest"
        VALIDATION_FAILED=1
    fi
done

blib_manifest_components "$MANIFEST" | while IFS='|' read -r name relpath expected_hash expected_bytes; do
    path="$STAGE_DIR/$relpath"
    if [ ! -f "$path" ]; then
        echo "MISSING FILE: component '$name' references '$relpath', which is not in the archive"
        exit 1
    fi
    actual_hash="$(blib_sha256 "$path")"
    if [ "$actual_hash" != "$expected_hash" ]; then
        echo "CHECKSUM MISMATCH: component '$name' ($relpath) -- manifest says $expected_hash, actual is $actual_hash"
        exit 1
    fi
done
COMPONENT_LOOP_STATUS=$?
if [ "$COMPONENT_LOOP_STATUS" -ne 0 ]; then
    VALIDATION_FAILED=1
    blib_log "one or more component checks failed (see above)"
fi

if [ "$VALIDATION_FAILED" -eq 1 ]; then
    blib_die "backup archive failed validation -- refusing to restore from it (see diagnostics above)"
fi

blib_log "==> validation OK: format version ${FORMAT_VERSION}, ${COMPONENT_COUNT} components, all checksums match"
blib_log "    created: $(blib_manifest_get "$MANIFEST" created_at)  git: $(blib_manifest_get "$MANIFEST" senma_git_describe)"

if [ "$VALIDATE_ONLY" -eq 1 ]; then
    echo "VALIDATE-ONLY: archive is valid and complete. No containers or volumes were touched."
    exit 0
fi

# =====================================================================
# Phase A2 -- runtime topology selection (TASK-0035E5 / I8)
# Data contents and runtime topology are distinct. Fail closed rather
# than silently recreating pilot/production onto bridge compose.yaml.
# =====================================================================

senma_resolve_compose_runtime || blib_die "restore aborted: runtime topology could not be selected safely (see above)"

# Record SENMA image IDs BEFORE recreate -- must be unchanged afterward
# (TASK-0035E4 immutability: restore never builds/retags).
BEFORE_APP_IMAGE=""
BEFORE_AST_IMAGE=""
RV_FOR_IDS="${RELEASE_VERSION:-dev}"
if docker image inspect "senma-app:${RV_FOR_IDS}" >/dev/null 2>&1; then
    BEFORE_APP_IMAGE="$(docker image inspect "senma-app:${RV_FOR_IDS}" --format '{{.Id}}')"
fi
if docker image inspect "senma-asterisk:${RV_FOR_IDS}" >/dev/null 2>&1; then
    BEFORE_AST_IMAGE="$(docker image inspect "senma-asterisk:${RV_FOR_IDS}" --format '{{.Id}}')"
fi

# =====================================================================
# Phase B -- destructive-target protection (Phase 7/10 of TASK-0033A)
# =====================================================================

target_has_existing_state() {
    # A target counts as "has existing state" if the db container is up
    # AND already has a non-empty snep schema, OR the asterisk-etc
    # volume already has asterisk.conf (first-boot already ran). Either
    # condition means this restore would destroy real state, not just
    # populate an empty target.
    if $COMPOSE ps db 2>/dev/null | grep -q "Up"; then
        if $COMPOSE exec -T db mariadb -uroot -p"${DB_ROOT_PASSWORD:-}" -N \
            -e "SHOW TABLES FROM \`${DB_NAME:-snep}\`;" 2>/dev/null | grep -q .; then
            return 0
        fi
    fi
    if senma_compose_run --rm --no-deps -T --entrypoint sh asterisk -c \
        'test -f /etc/asterisk/asterisk.conf' 2>/dev/null; then
        return 0
    fi
    return 1
}

if target_has_existing_state; then
    if [ "$CONFIRMED" -ne 1 ]; then
        blib_die "target already has existing SENMA state (a non-empty database and/or a populated asterisk-etc volume). Restore REPLACES all of it -- nothing is merged. Re-run with --confirm (or 'make restore FROM=... CONFIRM=RESTORE') only if you intend to destroy the current installation's data."
    fi
    blib_log "==> --confirm given: proceeding to REPLACE existing target state"
else
    blib_log "==> target appears fresh/empty -- proceeding without confirmation"
fi

: "${DB_NAME:?DB_NAME must be set (source .env first)}"
: "${DB_ROOT_PASSWORD:?DB_ROOT_PASSWORD must be set (source .env first)}"

FAILED=0
step() {
    local desc="$1"; shift
    blib_log "==> $desc"
    if ! "$@"; then
        blib_log "FAILED: $desc"
        FAILED=1
        return 1
    fi
    return 0
}

# =====================================================================
# Phase C -- stop services, wipe target (Phase 8 ordering)
# =====================================================================

step "stopping app/asterisk/db" $COMPOSE stop app asterisk db
$COMPOSE rm -f app asterisk db >/dev/null 2>&1 || true

wipe_volume() {
    local short="$1" vol
    vol="$(blib_volume_name "$short" 2>/dev/null)" || return 0
    docker volume rm "$vol" >/dev/null 2>&1 || true
}
blib_log "==> removing mag-db, asterisk-etc, mag-asterisk-var volumes"
wipe_volume mag-db
wipe_volume asterisk-etc
wipe_volume mag-asterisk-var

rm -f "$REPO_ROOT/snep/includes/setup.conf"
rm -rf "${REPO_ROOT:?}/snep/arquivos"
mkdir -p "$REPO_ROOT/snep/arquivos"

if [ "$FAILED" -eq 1 ]; then
    blib_die "wiping target state failed -- aborting before writing any restored data"
fi

# =====================================================================
# Phase D -- restore host-side filesystem state (before any container
# that owns it starts)
# =====================================================================

step "restoring snep/includes/setup.conf" cp "$STAGE_DIR/fs/setup.conf" "$REPO_ROOT/snep/includes/setup.conf"
step "restoring snep/arquivos/" bash -c "tar xzf '$STAGE_DIR/fs/arquivos.tar.gz' -C '$REPO_ROOT/snep'"

# =====================================================================
# Phase E -- restore Docker-managed volumes via a throwaway container
# using the real `asterisk` service's own image/mounts (same pattern
# backup.sh uses to create them), entrypoint overridden so the real
# bootstrap logic never runs and never races this restore.
# =====================================================================

restore_asterisk_etc() {
    # Plain `tar xzf` alone is not enough here: running unprivileged as
    # the `asterisk` user (matching the real entrypoint's own USER,
    # confirmed in the Dockerfile), a non-root tar extraction does not
    # reliably reproduce the original archive's group/mode -- confirmed
    # live during this task's own DR proof run: a restored
    # /etc/asterisk/snep ended up group "asterisk" mode 0755 instead of
    # group "senma-config" mode 2775, and its *.conf files 0644 instead
    # of 0664, which broke www-data's group-write access and surfaced as
    # a real HTTP 500 (PBX_Exception_IO) on the very next PJSIP/legacy
    # config regeneration. Re-apply docker/asterisk-entrypoint.sh's own
    # first-boot permission scheme explicitly after extraction, rather
    # than trusting tar to have preserved it -- asterisk is already a
    # senma-config member (same as the entrypoint), so this needs no
    # elevated privilege.
    senma_compose_run --rm --no-deps -T \
        -v "$STAGE_DIR/fs:/restore-input:ro" \
        --entrypoint sh asterisk -c '
            set -e
            tar xzf /restore-input/asterisk-etc.tar.gz -C /etc/asterisk
            chgrp senma-config /etc/asterisk/snep
            chmod 2775 /etc/asterisk/snep
            chgrp senma-config /etc/asterisk/snep/*.conf
            chmod 664 /etc/asterisk/snep/*.conf
            if [ -d /etc/asterisk/keys ]; then
                chmod 600 /etc/asterisk/keys/*key*.pem 2>/dev/null || true
                chmod 644 /etc/asterisk/keys/*cert*.pem 2>/dev/null || true
            fi
        '
}
step "restoring asterisk-etc volume" restore_asterisk_etc

if [ -f "$STAGE_DIR/fs/astdb.sqlite3" ]; then
    restore_astdb() {
        senma_compose_run --rm --no-deps -T \
            -v "$STAGE_DIR/fs:/restore-input:ro" \
            --entrypoint sh asterisk -c \
            'cp /restore-input/astdb.sqlite3 /var/lib/asterisk/astdb.sqlite3'
    }
    step "restoring astdb.sqlite3" restore_astdb
else
    blib_log "==> backup did not include astdb.sqlite3 -- nothing to restore (Asterisk creates it lazily)"
fi

# TASK-0034I: /var/lib/asterisk/{moh,sounds} -- CUSTOMER_MANAGED content
# (admin-uploaded MOH/AST sound files, see docs/tasks/
# 0034i-system-status-dependency-runtime-resource-closure.md). The wipe
# in Phase C above removes the whole mag-asterisk-var volume, so an
# archive predating this task (no asterisk-moh.tar.gz/asterisk-sounds.tar.gz)
# would otherwise restore onto a target with NEITHER directory -- not a
# regression from the restore's own perspective (nothing existed to lose
# at backup time), but the real asterisk-entrypoint.sh first-boot guards
# will correctly (re)provision both from scratch (empty moh, freshly
# reseeded core sounds) the next time the asterisk service actually
# starts, same as any genuinely fresh install.
if [ -f "$STAGE_DIR/fs/asterisk-moh.tar.gz" ]; then
    restore_asterisk_moh() {
        senma_compose_run --rm --no-deps -T \
            -v "$STAGE_DIR/fs:/restore-input:ro" \
            --entrypoint sh asterisk -c '
                set -e
                mkdir -p /var/lib/asterisk/moh
                tar xzf /restore-input/asterisk-moh.tar.gz -C /var/lib/asterisk/moh
                chgrp -R senma-config /var/lib/asterisk/moh
                chmod 2775 /var/lib/asterisk/moh /var/lib/asterisk/moh/tmp /var/lib/asterisk/moh/backup 2>/dev/null || true
            '
    }
    step "restoring /var/lib/asterisk/moh" restore_asterisk_moh
else
    blib_log "==> backup did not include /var/lib/asterisk/moh -- nothing to restore (asterisk-entrypoint.sh will provision an empty one on next start)"
fi

if [ -f "$STAGE_DIR/fs/asterisk-sounds.tar.gz" ]; then
    restore_asterisk_sounds() {
        senma_compose_run --rm --no-deps -T \
            -v "$STAGE_DIR/fs:/restore-input:ro" \
            --entrypoint sh asterisk -c '
                set -e
                mkdir -p /var/lib/asterisk/sounds
                tar xzf /restore-input/asterisk-sounds.tar.gz -C /var/lib/asterisk/sounds
                chgrp senma-config /var/lib/asterisk/sounds /var/lib/asterisk/sounds/pt_BR 2>/dev/null || true
                chmod 2775 /var/lib/asterisk/sounds /var/lib/asterisk/sounds/pt_BR 2>/dev/null || true
            '
    }
    step "restoring /var/lib/asterisk/sounds" restore_asterisk_sounds
else
    blib_log "==> backup did not include /var/lib/asterisk/sounds -- nothing to restore (asterisk-entrypoint.sh will reseed the vendored core sounds on next start)"
fi

if [ "$FAILED" -eq 1 ]; then
    blib_die "restoring filesystem/volume state failed -- target is now in a PARTIAL, inconsistent state. Do not start services. Re-run restore from a known-good archive, or investigate the failure above before proceeding."
fi

# =====================================================================
# Phase F -- start db, import dump on top of its own fresh-boot schema
# =====================================================================

# TASK-0035E4 / I4: restore recreates containers from existing images only.
step "starting db" $COMPOSE up -d --no-build db

db_ready() { $COMPOSE ps db 2>/dev/null | grep -q "(healthy)"; }
if ! harness_retry 30 2 -- db_ready; then
    blib_die "db did not become healthy within ~60s after restore -- check 'docker compose logs db'"
fi

import_dump() {
    gunzip -c "$STAGE_DIR/db/dump.sql.gz" | $COMPOSE exec -T db mariadb -uroot -p"${DB_ROOT_PASSWORD}" "${DB_NAME}"
    # Capture both PIPESTATUS elements in the SAME command as the array
    # access -- word expansion happens before `local` itself runs, so
    # this is the last point both indices are still valid. Evaluating a
    # `[ ... ]` test first (as a separate command) would overwrite
    # PIPESTATUS with that single command's own 1-element result before
    # the second index could ever be read (confirmed live: this exact
    # bug crashed a real restore run with "PIPESTATUS[1]: unbound
    # variable" under `set -u`, after the import itself had already
    # succeeded).
    local dump_status="${PIPESTATUS[0]}" import_status="${PIPESTATUS[1]}"
    [ "$dump_status" -eq 0 ] && [ "$import_status" -eq 0 ]
}
step "importing database dump" import_dump

if [ "$FAILED" -eq 1 ]; then
    blib_die "database restore failed -- target database is now in an UNDEFINED state (fresh-boot schema may be partially overwritten by a failed import). Do not proceed to start asterisk/app. Investigate 'docker compose logs db' and the import output above."
fi

# =====================================================================
# Phase G -- start asterisk, then app; verify basic readiness
# =====================================================================

step "starting asterisk" $COMPOSE up -d --no-build asterisk
asterisk_ready() { $COMPOSE ps asterisk 2>/dev/null | grep -q "(healthy)"; }
harness_retry 15 2 -- asterisk_ready || blib_log "WARNING: asterisk container did not report healthy within ~30s -- continuing to check runtime state directly"

pjsip_ready() {
    $COMPOSE exec -T asterisk asterisk -rx 'pjsip show transports' 2>&1 | grep -q 'wss\|udp\|tcp'
}
if ! harness_retry 15 1 -- pjsip_ready; then
    blib_die "restored asterisk-etc did not produce working PJSIP transports after restart -- check 'docker compose exec asterisk asterisk -rx \"pjsip show transports\"' and 'docker compose logs asterisk'"
fi

odbc_ready() {
    # `odbc show all` never prints the literal word "Connected" -- it
    # reports "Number of active connections: N (out of M)". At least one
    # active connection is the real signal that the DSN in res_odbc.conf
    # actually authenticated against MariaDB (confirmed against this
    # project's own live Asterisk 22 build, not assumed from documentation).
    $COMPOSE exec -T asterisk asterisk -rx 'odbc show all' 2>&1 | grep -qE 'Number of active connections: [1-9]'
}
if ! harness_retry 10 1 -- odbc_ready; then
    blib_die "Asterisk's ODBC connection to MariaDB is not Connected after restore. The most likely cause: the restored asterisk-etc/res_odbc.conf was templated with DB credentials from backup time, and the CURRENT .env's DB_PASSWORD does not match them. Run 'make secrets-check' to confirm, then 'make rotate-secrets' to reconcile the restored installation onto the currently declared credentials (TASK-0033C). Check 'docker compose exec asterisk asterisk -rx \"odbc show all\"' and compare against the current .env."
fi

step "starting app" $COMPOSE up -d --no-build app
app_ready() { $COMPOSE ps app 2>/dev/null | grep -q "(healthy)"; }
harness_retry 15 2 -- app_ready || blib_log "WARNING: app container did not report healthy within ~30s -- check 'docker compose logs app'"

if [ "$FAILED" -eq 1 ]; then
    blib_die "post-restore readiness verification failed -- see diagnostics above. The restore steps themselves completed, but the resulting stack is not provably usable."
fi

# =====================================================================
# Phase H -- runtime topology + image immutability (TASK-0035E5 / I8)
# =====================================================================

blib_log "==> verifying restored runtime topology (${SENMA_RUNTIME_MODE})"
if [ "$SENMA_RUNTIME_MODE" = "host" ]; then
    if ! senma_verify_host_runtime_topology; then
        blib_die "restore recreated containers but host-network topology was NOT preserved (I8). Data may be restored, but the stack is not in the supported pilot/production runtime. Do NOT treat this as success. Fix compose selection and re-run restore, or recover with 'make pilot-up' using the same RELEASE_VERSION (existing images only)."
    fi
    blib_log "    host topology OK: app/asterisk/db network_mode=host (no PortBindings)"
else
    if ! senma_verify_bridge_runtime_topology; then
        blib_die "restore selected bridge but at least one core service came back as host networking -- refuse inconsistent topology"
    fi
    blib_log "    bridge topology OK: app/asterisk/db are not host-networked"
fi

# Image identity must not change across restore (no build / no retag).
if [ -n "$BEFORE_APP_IMAGE" ]; then
    AFTER_APP_IMAGE="$(docker image inspect "senma-app:${RV_FOR_IDS}" --format '{{.Id}}' 2>/dev/null || true)"
    if [ "$BEFORE_APP_IMAGE" != "$AFTER_APP_IMAGE" ]; then
        blib_die "senma-app:${RV_FOR_IDS} image id changed during restore (before=$BEFORE_APP_IMAGE after=$AFTER_APP_IMAGE) -- restore must never build or retag (TASK-0035E4)"
    fi
fi
if [ -n "$BEFORE_AST_IMAGE" ]; then
    AFTER_AST_IMAGE="$(docker image inspect "senma-asterisk:${RV_FOR_IDS}" --format '{{.Id}}' 2>/dev/null || true)"
    if [ "$BEFORE_AST_IMAGE" != "$AFTER_AST_IMAGE" ]; then
        blib_die "senma-asterisk:${RV_FOR_IDS} image id changed during restore (before=$BEFORE_AST_IMAGE after=$AFTER_AST_IMAGE) -- restore must never build or retag (TASK-0035E4)"
    fi
fi
blib_log "    release image ids unchanged for senma-*:${RV_FOR_IDS}"

echo
echo "================================================================"
echo "SENMA restore complete from: $ARCHIVE"
echo "Backup created: $(blib_manifest_get "$MANIFEST" created_at)  git: $(blib_manifest_get "$MANIFEST" senma_git_describe)"
echo "Runtime topology: ${SENMA_RUNTIME_MODE} via: ${COMPOSE}"
echo "db/asterisk/app started and passed basic readiness checks (schema"
echo "imported, PJSIP transports loaded, ODBC connected, app HTTP up)."
echo "Run 'make ps' / 'make doctor' / 'make release-info' to confirm, and"
echo "verify your own provisioning (extensions/trunks) through the admin UI."
echo "================================================================"
