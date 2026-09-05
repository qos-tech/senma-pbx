#!/bin/bash
#
# SENMA operator-facing backup command (TASK-0033A).
#
# Produces one portable, inspectable, bit-identical-operational-backup
# artifact covering every BACKUP_REQUIRED persistent-state path
# identified by TASK-0033's operational-readiness audit and TASK-0033A's
# own re-confirmed inventory -- see docs/tasks/
# 0033a-backup-restore-disaster-recovery-foundation.md STATE INVENTORY.
#
# "Bit-identical", not "DB-truth-consistent": TASK-0033B (DB->PJSIP
# runtime reconciliation) does not exist yet, so this backs up the
# *generated* Asterisk config/secrets/certificates directly (the whole
# asterisk-etc volume) rather than assuming they can be safely
# regenerated from the database alone on restore.
#
# Consistency model: all four SENMA services may remain RUNNING during
# backup.
#   - MariaDB: every table is InnoDB (confirmed live in this task's own
#     audit) -- `mariadb-dump --single-transaction` gives a consistent
#     snapshot with no locking, no downtime, no risk of a torn read.
#   - setup.conf / arquivos / asterisk-etc: low-frequency-write
#     config/data paths (config changes happen through occasional admin
#     actions, not continuous writes) -- a live `tar`/`cp` read is
#     accepted as a small, documented risk of picking up a config change
#     mid-write, not a correctness requirement to stop services for.
#   Order: the DB dump is taken first (establishing the instant of DB
#   truth), then filesystem state immediately after -- if anything
#   changes between the two, the filesystem side is "as new or newer"
#   than the DB dump, never older, which is the safer direction (no
#   restore can end up referencing a DB row that doesn't exist in the
#   restored filesystem state).
#
# Usage:
#   scripts/backup.sh [--dest DIR]
#
# Exit code: 0 on a complete, verified backup; 1 on any failure. Never
# leaves a partial artifact at the canonical destination path (staged
# under a .tmp name, renamed into place only after every step and the
# checksum manifest itself succeed).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/backup-lib.sh
source "$SCRIPT_DIR/lib/backup-lib.sh"

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
DEST="${REPO_ROOT}/backups"

while [ $# -gt 0 ]; do
    case "$1" in
        --dest) DEST="$2"; shift 2 ;;
        --dest=*) DEST="${1#--dest=}"; shift ;;
        *) blib_die "unknown argument: $1 (usage: backup.sh [--dest DIR])" ;;
    esac
done

: "${COMPOSE_PROJECT_NAME:?COMPOSE_PROJECT_NAME must be set (source .env first)}"
: "${DB_NAME:?DB_NAME must be set (source .env first)}"
: "${DB_ROOT_PASSWORD:?DB_ROOT_PASSWORD must be set (source .env first)}"

STAGE_ROOT=""
FINAL_ARCHIVE=""
cleanup_staging() {
    [ -n "$STAGE_ROOT" ] && [ -d "$STAGE_ROOT" ] && rm -rf "$STAGE_ROOT"
}
trap cleanup_staging EXIT

blib_log "==> checking required containers"
for svc in app asterisk db; do
    $COMPOSE ps "$svc" 2>/dev/null | grep -q "Up" || blib_die "service '$svc' is not Up -- run 'make up' first (backup reads live container state)"
done

mkdir -p "$DEST" || blib_die "could not create destination directory: $DEST"
[ -w "$DEST" ] || blib_die "destination directory is not writable: $DEST"

# Rough space check: sum of the four live volumes/paths this backup
# reads from, x3 safety margin (staging copy + gzip working set +
# the final archive existing briefly alongside the staging dir).
blib_log "==> checking free space at $DEST"
# docker system df's human-readable sizes are awkward to sum reliably
# across docker versions; use `du` inside a throwaway container against
# each volume instead -- exact, portable, no format-parsing fragility.
vol_size_kb() {
    local vol; vol="$(blib_volume_name "$1" 2>/dev/null)" || { echo 0; return; }
    docker run --rm -v "${vol}:/vol:ro" alpine du -sk /vol 2>/dev/null | awk '{print $1}'
}
ARQUIVOS_KB="$(du -sk "$REPO_ROOT/snep/arquivos" 2>/dev/null | awk '{print $1}')"
REQUIRED_KB=$(( ($(vol_size_kb mag-db) + $(vol_size_kb asterisk-etc) + $(vol_size_kb mag-asterisk-var) + ${ARQUIVOS_KB:-0} + 1024) * 3 ))
blib_check_free_space "$DEST" "$REQUIRED_KB"

TS="$(date -u +%Y%m%d-%H%M%SZ)"
STAGE_ROOT="$(mktemp -d)"
STAGE_DIR="$STAGE_ROOT/senma-backup-${TS}"
mkdir -p "$STAGE_DIR/db" "$STAGE_DIR/fs"
blib_secure_path "$STAGE_ROOT"
blib_secure_path "$STAGE_DIR"

FAILED=0
step() {
    local desc="$1"; shift
    blib_log "==> $desc"
    if ! "$@"; then
        blib_log "FAILED: $desc"
        FAILED=1
        return 1
    fi
}

# --- 1. Database dump (see header for the --single-transaction rationale) --
dump_db() {
    $COMPOSE exec -T db mariadb-dump \
        --single-transaction --routines --triggers --add-drop-table \
        -uroot -p"${DB_ROOT_PASSWORD}" "${DB_NAME}" \
        | gzip -c > "$STAGE_DIR/db/dump.sql.gz"
    # mariadb-dump's own exit status is lost across the pipe to gzip;
    # PIPESTATUS is bash-specific but every script in this repo already
    # requires bash (shebang), not /bin/sh.
    [ "${PIPESTATUS[0]}" -eq 0 ] || return 1
    [ -s "$STAGE_DIR/db/dump.sql.gz" ] || return 1
}
step "dumping database ($DB_NAME)" dump_db || true

# --- 2. setup.conf (host bind mount, plain copy) ---------------------------
copy_setup_conf() {
    local src="$REPO_ROOT/snep/includes/setup.conf"
    [ -f "$src" ] || { blib_log "setup.conf not found at $src"; return 1; }
    cp "$src" "$STAGE_DIR/fs/setup.conf"
}
step "copying snep/includes/setup.conf" copy_setup_conf || true

# --- 3. arquivos/ (host bind mount, tar) ------------------------------------
tar_arquivos() {
    tar czf "$STAGE_DIR/fs/arquivos.tar.gz" -C "$REPO_ROOT/snep" arquivos
}
step "archiving snep/arquivos/" tar_arquivos || true

# --- 4. asterisk-etc (named volume, tar via a throwaway container using ----
#        the real `asterisk` service's own image/user/mounts, entrypoint
#        overridden so the real bootstrap logic never runs) -----------------
tar_asterisk_etc() {
    $COMPOSE run --rm --no-deps -T \
        -v "$STAGE_DIR/fs:/backup-output" \
        --entrypoint sh asterisk -c \
        'tar czf /backup-output/asterisk-etc.tar.gz -C /etc/asterisk .'
}
step "archiving asterisk-etc volume" tar_asterisk_etc || true

# --- 5. astdb.sqlite3 (named volume, single file) ---------------------------
copy_astdb() {
    $COMPOSE run --rm --no-deps -T \
        -v "$STAGE_DIR/fs:/backup-output" \
        --entrypoint sh asterisk -c \
        'test -f /var/lib/asterisk/astdb.sqlite3 && cp /var/lib/asterisk/astdb.sqlite3 /backup-output/astdb.sqlite3 || echo "[backup] astdb.sqlite3 not present yet -- skipping (not fatal, Asterisk creates it lazily)"'
}
step "copying astdb.sqlite3" copy_astdb || true

if [ "$FAILED" -eq 1 ]; then
    blib_die "one or more backup steps failed -- aborting before writing manifest/checksums (no partial artifact left at $DEST)"
fi

# --- 6. Manifest + checksums -------------------------------------------------
blib_log "==> writing manifest"
BLIB_ASTERISK_VERSION="$($COMPOSE exec -T asterisk asterisk -rx "core show version" 2>/dev/null | head -1 | tr -d '\r')"
BLIB_MARIADB_VERSION="$($COMPOSE exec -T db mariadb --version 2>/dev/null | tr -d '\r')"
export BLIB_ASTERISK_VERSION BLIB_MARIADB_VERSION
blib_write_manifest "$STAGE_DIR/manifest.txt" "$STAGE_DIR" \
    "db|db/dump.sql.gz" \
    "setup_conf|fs/setup.conf" \
    "arquivos|fs/arquivos.tar.gz" \
    "asterisk_etc|fs/asterisk-etc.tar.gz" \
    $( [ -f "$STAGE_DIR/fs/astdb.sqlite3" ] && echo "asterisk_astdb|fs/astdb.sqlite3" ) \
    || blib_die "writing manifest failed"

blib_log "==> writing checksums"
: > "$STAGE_DIR/checksums.sha256"
CHECKSUM_FILES="$(cd "$STAGE_DIR" && find . -type f ! -name checksums.sha256 | sed 's#^\./##' | sort)"
while IFS= read -r relpath; do
    [ -z "$relpath" ] && continue
    printf '%s  %s\n' "$(blib_sha256 "$STAGE_DIR/$relpath")" "$relpath" >> "$STAGE_DIR/checksums.sha256"
done <<< "$CHECKSUM_FILES"
[ -s "$STAGE_DIR/checksums.sha256" ] || blib_die "writing checksums failed (no files found to checksum)"

# --- 7. Final archive: tar+gzip the staging dir, atomic rename into place --
blib_log "==> assembling final archive"
FINAL_ARCHIVE="$DEST/senma-backup-${TS}.tar.gz"
TMP_ARCHIVE="${FINAL_ARCHIVE}.tmp"
( cd "$STAGE_ROOT" && tar czf "$TMP_ARCHIVE" "senma-backup-${TS}" ) \
    || blib_die "assembling final archive failed"
blib_secure_path "$TMP_ARCHIVE"
mv "$TMP_ARCHIVE" "$FINAL_ARCHIVE" || blib_die "could not finalize archive at $FINAL_ARCHIVE"

SIZE_HUMAN="$(du -h "$FINAL_ARCHIVE" | awk '{print $1}')"
echo
echo "================================================================"
echo "SENMA backup complete: $FINAL_ARCHIVE ($SIZE_HUMAN)"
echo "Contains: full database dump, setup.conf, arquivos/, the complete"
echo "Asterisk generated-config volume (including TLS private key and"
echo "AMI/DB credentials), and astdb.sqlite3 if present."
echo
echo "THIS ARTIFACT IS SENSITIVE -- it contains database rows, SIP"
echo "secrets, and a TLS private key. Mode is already restricted to 600"
echo "(owner read/write only). Do not copy it anywhere without applying"
echo "at least the same protection. See docs/tasks/"
echo "0033a-backup-restore-disaster-recovery-foundation.md SECURITY."
echo "================================================================"
