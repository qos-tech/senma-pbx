#!/bin/bash
#
# Shared backup/restore helpers (TASK-0033A).
#
# Sourced by scripts/backup.sh, scripts/restore.sh, scripts/backup-smoke-test.sh
# and scripts/backup-restore-dr-smoke-test.sh. Bash-3.2 compatible on purpose
# (same host-shell constraint as scripts/lib/harness.sh -- no associative
# arrays, no `readarray`, no `${var,,}`).
#
# Artifact format (single portable .tar.gz, contract version 1):
#   senma-backup-<UTC timestamp>.tar.gz
#     manifest.txt         -- flat KEY=value + component=... lines, no
#                              credentials (see blib_write_manifest)
#     checksums.sha256      -- sha256sum-format list of every other file
#     db/dump.sql.gz         -- mariadb-dump --single-transaction output
#     fs/setup.conf           -- snep/includes/setup.conf (host bind mount)
#     fs/arquivos.tar.gz       -- snep/arquivos/ (host bind mount)
#     fs/asterisk-etc.tar.gz    -- the whole /etc/asterisk named volume
#     fs/astdb.sqlite3           -- /var/lib/asterisk/astdb.sqlite3
#
# Deliberately excluded (see docs/tasks/0033a-backup-restore-disaster-recovery-foundation.md
# STATE INVENTORY for the full classification): Asterisk logs/spool
# (EPHEMERAL/diagnostic, not provisioning state), mag-asterisk-var's
# agi-bin/documentation (REGENERABLE, rebuilt every boot), the `provider`
# service's own volumes (TEST_ONLY fixture, not part of a real
# installation), Docker image layers (REGENERABLE from git + Dockerfiles).

BACKUP_FORMAT_VERSION=1

blib_log() { printf '%s\n' "$*" >&2; }

blib_die() {
    blib_log "ERROR: $*"
    exit 1
}

# blib_sha256 <file> -- portable checksum: prefers GNU coreutils
# sha256sum (Linux, most CI), falls back to the BSD/macOS shasum -a 256
# (confirmed present on this project's macOS host shell; sha256sum is
# not guaranteed there). Same portability pattern as harness_timeout in
# scripts/lib/harness.sh.
blib_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        blib_die "neither sha256sum nor shasum is available on this host"
    fi
}

# blib_sha256_check <file> <expected-hash> -- returns 0/1, no output.
blib_sha256_check() {
    [ "$(blib_sha256 "$1" 2>/dev/null)" = "$2" ]
}

# blib_volume_name <compose-short-name> -- resolves the actual
# project-prefixed Docker volume name (e.g. "mag-db" -> "mag-pbx_mag-db")
# via the labels Compose v2 itself attaches, so this never has to guess
# or hardcode a project-name prefix. Requires COMPOSE_PROJECT_NAME to be
# set (sourced from .env by every caller, same convention as the rest of
# scripts/).
blib_volume_name() {
    local short="$1" name
    : "${COMPOSE_PROJECT_NAME:?COMPOSE_PROJECT_NAME must be set (source .env first)}"
    name="$(docker volume ls -q \
        --filter "label=com.docker.compose.project=${COMPOSE_PROJECT_NAME}" \
        --filter "label=com.docker.compose.volume=${short}")"
    [ -n "$name" ] || blib_die "could not resolve Docker volume name for '${short}' in project '${COMPOSE_PROJECT_NAME}' -- is it created yet?"
    echo "$name"
}

# blib_write_manifest <dest-file> <compose-project-name> <component...>
# Each <component> is "name|relative_path" (checksums/bytes are computed
# here, from files already staged at $STAGE_DIR/<relative_path>).
# Deliberately NOT JSON -- avoids introducing a `jq` dependency on the
# operator's host (see CLAUDE.md rule 6: don't add runtime dependencies
# without documenting why); a flat KEY=value + "component=" table is
# fully machine-parseable with plain grep/cut/read, matching this
# project's existing bash-3.2-first tooling convention.
#
# No credential fields appear anywhere in this manifest -- git hash,
# software versions, relative paths, byte counts and checksums only. The
# secrets live *inside* db/dump.sql.gz and fs/asterisk-etc.tar.gz, which
# is exactly why the whole artifact (not just this file) must be kept at
# restrictive permissions -- see blib_secure_path.
blib_write_manifest() {
    local dest="$1" stage_dir="$2"; shift 2
    local created_at git_commit git_describe asterisk_version mariadb_version
    created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    git_commit="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
    git_describe="$(git describe --tags --always 2>/dev/null || echo unknown)"
    asterisk_version="${BLIB_ASTERISK_VERSION:-unknown}"
    mariadb_version="${BLIB_MARIADB_VERSION:-unknown}"

    {
        echo "# SENMA backup manifest -- see docs/tasks/0033a-backup-restore-disaster-recovery-foundation.md"
        echo "backup_format_version=${BACKUP_FORMAT_VERSION}"
        echo "created_at=${created_at}"
        echo "senma_git_commit=${git_commit}"
        echo "senma_git_describe=${git_describe}"
        echo "asterisk_version=${asterisk_version}"
        echo "mariadb_version=${mariadb_version}"
        echo "compose_project_name=${COMPOSE_PROJECT_NAME:-unknown}"
        echo "component_count=$#"
        echo
        echo "# component=<name>|<relative_path>|<sha256>|<bytes>"
        local comp name relpath hash bytes
        for comp in "$@"; do
            name="${comp%%|*}"
            relpath="${comp#*|}"
            [ -f "$stage_dir/$relpath" ] || blib_die "manifest: staged component file missing: $relpath"
            hash="$(blib_sha256 "$stage_dir/$relpath")"
            bytes="$(wc -c < "$stage_dir/$relpath" | tr -d ' ')"
            echo "component=${name}|${relpath}|${hash}|${bytes}"
        done
    } > "$dest"
}

# blib_manifest_get <manifest-file> <key> -- reads a top-level KEY=value.
blib_manifest_get() {
    grep -E "^$2=" "$1" | head -1 | cut -d= -f2-
}

# blib_manifest_components <manifest-file> -- prints one "name|relpath|hash|bytes"
# per line, for `while read` iteration.
blib_manifest_components() {
    grep -E '^component=' "$1" | cut -d= -f2-
}

# blib_secure_path <path> -- restrictive perms for anything containing
# secrets (backup artifacts, staging dirs). 0700 for directories, 0600
# for files -- never relies on umask.
blib_secure_path() {
    if [ -d "$1" ]; then
        chmod 700 "$1"
    else
        chmod 600 "$1"
    fi
}

# blib_check_free_space <dest-dir> <required-kb> -- KB available via `df -Pk`
# (POSIX output format, portable across the GNU/BSD df this project's
# scripts already have to straddle -- see harness_timeout's own comment
# on the same GNU/BSD split).
blib_check_free_space() {
    local dest="$1" required_kb="$2" avail_kb
    avail_kb="$(df -Pk "$dest" | awk 'NR==2 {print $4}')"
    if [ -z "$avail_kb" ]; then
        blib_log "WARNING: could not determine free space at $dest -- proceeding without a space guarantee"
        return 0
    fi
    if [ "$avail_kb" -lt "$required_kb" ]; then
        blib_die "insufficient free space at $dest: ${avail_kb}KB available, ~${required_kb}KB required. Free up space or choose a different destination (backup.sh --dest)."
    fi
}

# ---------------------------------------------------------------------
# TASK-0035E12: recording store (snep/arquivos) via app container
#
# E8 mode 2770 (www-data:senma-config / GID 3000) intentionally blocks
# unprivileged host uid from traversing/writing the tree. Backup already
# archives through the app container; wipe/restore/normalize must follow
# the same path. Callers MUST source compose-runtime.sh and set COMPOSE
# (and have senma_compose_run available) before calling these helpers.
# ---------------------------------------------------------------------

# blib_require_compose_run -- fail closed if senma_compose_run is missing.
blib_require_compose_run() {
    if ! command -v senma_compose_run >/dev/null 2>&1; then
        blib_die "senma_compose_run is required for recording-store operations (source scripts/lib/compose-runtime.sh and set COMPOSE first)"
    fi
    if [ -z "${COMPOSE:-}" ]; then
        blib_die "COMPOSE is not set -- resolve runtime before recording-store operations"
    fi
}

# blib_wipe_recording_store -- clear contents of ./snep/arquivos via the
# app container's bind mount. Keeps the directory inode (bind-mount
# target); does not chmod/chown the host tree from the host process.
blib_wipe_recording_store() {
    blib_require_compose_run
    # Use bash (image has it): dash rejects bash-style 8# octal arithmetic.
    senma_compose_run --rm --no-deps -T --entrypoint bash app -c '
        set -euo pipefail
        dir=/var/www/html/snep/arquivos
        mkdir -p "$dir"
        # Clear contents only -- never remove the mount-point directory.
        find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
        chown www-data:senma-config "$dir"
        chmod 2770 "$dir"
    '
}

# blib_restore_recording_store <arquivos.tar.gz> -- extract archive into
# /var/www/html/snep (archive top-level prefix is "arquivos/") via the
# app container, then normalize ownership/modes strictly inside that
# subtree: directories 2770, files 0660, owner www-data:senma-config.
blib_restore_recording_store() {
    local archive="$1"
    [ -n "$archive" ] && [ -f "$archive" ] || blib_die "blib_restore_recording_store: archive missing: ${archive:-<empty>}"
    blib_require_compose_run
    # Mount only the archive directory (read-only) + write through the
    # service's existing ./snep bind. No docker.sock, no privileged.
    local archive_dir archive_base
    archive_dir="$(cd "$(dirname "$archive")" && pwd)"
    archive_base="$(basename "$archive")"
    senma_compose_run --rm --no-deps -T \
        -v "${archive_dir}:/restore-input:ro" \
        --entrypoint bash app -c "
        set -euo pipefail
        umask 0007
        parent=/var/www/html/snep
        dir=\"\$parent/arquivos\"
        mkdir -p \"\$dir\"
        find \"\$dir\" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
        tar xzf /restore-input/${archive_base} -C \"\$parent\"
        # Scope recursive normalization to the restored recording subtree
        # only -- never chown/chmod the rest of ./snep.
        chown -R www-data:senma-config \"\$dir\"
        find \"\$dir\" -type d -exec chmod 2770 {} +
        find \"\$dir\" -type f -exec chmod 0660 {} +
        # Refuse world-writable recording root (other-write bit).
        mode=\$(stat -c '%a' \"\$dir\")
        other=\$((8#\${mode} % 8))
        if [ \$((other & 2)) -ne 0 ]; then
            echo \"ERROR: restored recording directory is world-writable (mode \$mode)\" >&2
            exit 1
        fi
        # Refuse world-readable restored files (other-read bit).
        if find \"\$dir\" -type f -perm -0004 -print -quit | grep -q .; then
            echo \"ERROR: restored recording tree contains world-readable files\" >&2
            exit 1
        fi
    "
}

# blib_apply_recording_dir_contract -- directory-level reaffirmation of
# the E8 contract after restore (root only). Safe if restore already
# normalized the subtree; keeps recording-storage-smoke's contract marker.
blib_apply_recording_dir_contract() {
    blib_require_compose_run
    senma_compose_run --rm --no-deps -T --entrypoint bash app -c '
        set -euo pipefail
        dir=/var/www/html/snep/arquivos
        mkdir -p "$dir"
        chown www-data:senma-config "$dir"
        chmod 2770 "$dir"
        mode=$(stat -c "%a" "$dir")
        other=$((8#${mode} % 8))
        if [ $((other & 2)) -ne 0 ]; then
            echo "ERROR: recording directory is world-writable (mode $mode)" >&2
            exit 1
        fi
    '
}
