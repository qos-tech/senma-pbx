#!/bin/bash
#
# Lightweight, non-destructive backup/restore validation (TASK-0033A).
#
# Included in `make regression` (unlike scripts/backup-restore-dr-smoke-
# -test.sh, which is deliberately kept out of default regression -- see
# that script's own header and docs/tasks/
# 0033a-backup-restore-disaster-recovery-foundation.md's "Regression"
# section for why). This suite never stops a container, never touches a
# volume, and never restores anything into the live stack -- it only:
#   1. runs the real `make backup` path to a throwaway destination and
#      checks the artifact is structurally complete (manifest,
#      checksums, every mandatory component present, all checksums
#      verify);
#   2. exercises restore.sh's own --validate-only path against that good
#      archive (must pass) and against four deliberately corrupted
#      copies of it (must each fail with an explicit diagnostic, per
#      TASK-0033A Phase 11/18) -- all of this is pure local file
#      manipulation, no container/volume access at all;
#   3. confirms the legacy snep/scripts/backup/backup.sh has been marked
#      superseded (a documentation-drift check, not a functional one) so
#      a future change can't silently un-deprecate it without this
#      suite noticing.
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
# shellcheck source=lib/backup-lib.sh
source "$SCRIPT_DIR/lib/backup-lib.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
log() { harness_log "$@"; }

log "==> checking required containers"
harness_require_containers app asterisk db

TMP_DEST="$(mktemp -d)"
harness_register_best_effort_cleanup "temp backup destination" "rm -rf '$TMP_DEST'"

log "==> running scripts/backup.sh --dest $TMP_DEST"
if bash "$SCRIPT_DIR/backup.sh" --dest "$TMP_DEST" >&2; then
    harness_ok "backup.sh exits 0" "backup completed"
else
    harness_blocked "backup.sh failed -- see output above (this suite cannot validate a backup that was never produced)"
fi

ARCHIVE="$(find "$TMP_DEST" -maxdepth 1 -name 'senma-backup-*.tar.gz' | head -1)"
if [ -z "$ARCHIVE" ]; then
    harness_blocked "no senma-backup-*.tar.gz found in $TMP_DEST after a reported-successful backup"
fi
harness_ok "artifact exists" "$(basename "$ARCHIVE")"

# GNU coreutils `stat -f` means --file-system and does NOT fail on Linux,
# so the BSD form must not be tried first (it returns a multi-line
# filesystem dump that is not a mode). Prefer GNU -c, fall back to BSD -f.
if ARCHIVE_MODE="$(stat -c '%a' "$ARCHIVE" 2>/dev/null)" && [ -n "$ARCHIVE_MODE" ]; then
    :
elif ARCHIVE_MODE="$(stat -f '%Lp' "$ARCHIVE" 2>/dev/null)" && [ -n "$ARCHIVE_MODE" ]; then
    :
else
    ARCHIVE_MODE=""
fi
if [ "$ARCHIVE_MODE" = "600" ]; then
    harness_ok "artifact permissions restrictive" "mode 600"
else
    harness_bad "artifact permissions restrictive" "expected mode 600, got '$ARCHIVE_MODE'"
fi

log "==> validating the good archive (restore.sh --validate-only)"
if bash "$SCRIPT_DIR/restore.sh" "$ARCHIVE" --validate-only >&2; then
    harness_ok "restore.sh --validate-only accepts a good archive" "exit 0"
else
    harness_bad "restore.sh --validate-only accepts a good archive" "expected exit 0, got a validation failure"
fi

# --- Failure-mode checks (TASK-0033A Phase 11/18) --------------------------
# Each of these works on a scratch COPY of the good archive, corrupted in
# one specific way, and asserts restore.sh --validate-only rejects it.
# None of this touches any container or volume.

TAMPER_DIR="$(mktemp -d)"
harness_register_best_effort_cleanup "tamper scratch dir" "rm -rf '$TAMPER_DIR'"

check_rejected() {
    local label="$1" archive="$2"
    if bash "$SCRIPT_DIR/restore.sh" "$archive" --validate-only >"$TAMPER_DIR/restore-validate-out" 2>&1; then
        harness_bad "$label" "restore.sh --validate-only incorrectly accepted a corrupted archive"
    else
        if grep -qiE 'corrupt|missing|mismatch|incompat' "$TAMPER_DIR/restore-validate-out"; then
            harness_ok "$label" "rejected with an explicit diagnostic"
        else
            harness_bad "$label" "rejected, but with no explicit diagnostic in the output"
        fi
    fi
    rm -f "$TAMPER_DIR/restore-validate-out"
}

# 1. Corrupt archive (not a valid gzip/tar at all).
CORRUPT_ARCHIVE="$TAMPER_DIR/corrupt.tar.gz"
echo "not a real archive" > "$CORRUPT_ARCHIVE"
check_rejected "rejects a corrupt archive" "$CORRUPT_ARCHIVE"

# 2. Checksum mismatch -- flip a byte in one component after re-packing.
CKSUM_DIR="$TAMPER_DIR/cksum"
mkdir -p "$CKSUM_DIR"
tar xzf "$ARCHIVE" -C "$CKSUM_DIR"
STAGE_NAME="$(find "$CKSUM_DIR" -maxdepth 1 -type d -name 'senma-backup-*' -exec basename {} \;)"
printf 'x' >> "$CKSUM_DIR/$STAGE_NAME/fs/setup.conf"
CKSUM_ARCHIVE="$TAMPER_DIR/checksum-mismatch.tar.gz"
( cd "$CKSUM_DIR" && tar czf "$CKSUM_ARCHIVE" "$STAGE_NAME" )
check_rejected "rejects a checksum mismatch" "$CKSUM_ARCHIVE"

# 3. Missing mandatory component -- delete asterisk-etc.tar.gz and its
#    manifest/checksum entries stay dangling (manifest still lists it).
MISSING_DIR="$TAMPER_DIR/missing"
mkdir -p "$MISSING_DIR"
tar xzf "$ARCHIVE" -C "$MISSING_DIR"
rm -f "$MISSING_DIR/$STAGE_NAME/fs/asterisk-etc.tar.gz"
MISSING_ARCHIVE="$TAMPER_DIR/missing-component.tar.gz"
( cd "$MISSING_DIR" && tar czf "$MISSING_ARCHIVE" "$STAGE_NAME" )
check_rejected "rejects a missing mandatory component file" "$MISSING_ARCHIVE"

# 4. Incomplete manifest -- truncate manifest.txt to zero bytes.
INCOMPLETE_DIR="$TAMPER_DIR/incomplete"
mkdir -p "$INCOMPLETE_DIR"
tar xzf "$ARCHIVE" -C "$INCOMPLETE_DIR"
: > "$INCOMPLETE_DIR/$STAGE_NAME/manifest.txt"
INCOMPLETE_ARCHIVE="$TAMPER_DIR/incomplete-manifest.tar.gz"
( cd "$INCOMPLETE_DIR" && tar czf "$INCOMPLETE_ARCHIVE" "$STAGE_NAME" )
check_rejected "rejects an incomplete manifest" "$INCOMPLETE_ARCHIVE"

# --- Restore-onto-unsafe-target guard (still non-destructive: the guard --
#     itself must fire and refuse BEFORE any destructive step runs; the
#     live stack is never actually touched by this check) ------------------

log "==> checking restore.sh refuses an unconfirmed restore onto a live target"
harness_require_env DB_NAME DB_ROOT_PASSWORD COMPOSE_PROJECT_NAME
if bash "$SCRIPT_DIR/restore.sh" "$ARCHIVE" >"$TAMPER_DIR/restore-unsafe-out" 2>&1; then
    harness_bad "refuses unconfirmed restore onto existing state" "restore.sh proceeded without --confirm against a live, populated target"
else
    if grep -q "existing SENMA state" "$TAMPER_DIR/restore-unsafe-out"; then
        harness_ok "refuses unconfirmed restore onto existing state" "rejected with the expected existing-state diagnostic, no --confirm given"
    else
        harness_bad "refuses unconfirmed restore onto existing state" "rejected, but not for the expected reason: $(cat "$TAMPER_DIR/restore-unsafe-out")"
    fi
fi
rm -f "$TAMPER_DIR/restore-unsafe-out"
harness_require_containers app asterisk db

# --- Legacy script deprecation marker --------------------------------------

log "==> checking the legacy backup script is marked superseded"
LEGACY_SCRIPT="$SCRIPT_DIR/../snep/scripts/backup/backup.sh"
if [ -f "$LEGACY_SCRIPT" ] && grep -qi "SUPERSEDED" "$LEGACY_SCRIPT"; then
    harness_ok "legacy backup script marked superseded" "deprecation header present in $LEGACY_SCRIPT"
else
    harness_bad "legacy backup script marked superseded" "no SUPERSEDED marker found in $LEGACY_SCRIPT"
fi

harness_complete
