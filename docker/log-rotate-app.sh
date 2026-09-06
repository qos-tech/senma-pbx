#!/bin/bash
#
# TASK-0033D: bounded-growth watcher for the app container's own
# file-based logs (Apache's mag-error.log, SENMA's Zend_Log ui.log).
#
# No cron/systemd/logrotate binary exists in this minimal image
# (confirmed live) -- backgrounded from docker/entrypoint.sh alongside
# `exec apache2-foreground`, running as a sibling process for the
# container's whole lifetime. See docs/tasks/
# 0033d-diagnostics-logging-storage-lifecycle.md LOG LIFECYCLE.
#
# Rotation strategy: copytruncate (copy current content aside, then
# truncate the original file IN PLACE -- same inode, same owner/mode,
# no rename). This is deliberately NOT a rename-based rotation:
# mag-error.log is fed by a `tee` process (docker/apache-mag.conf) that
# holds the file open continuously for the container's whole lifetime
# -- renaming out from under it would leave `tee` writing to a
# now-unlinked-by-name inode while a NEW empty file sits at the old
# path, invisible to `tee`. Copytruncate avoids needing to signal/
# restart `tee` (or Apache) at all: truncating a file a process holds
# open for append-only writes is safe on POSIX (the next write lands
# at the now-current end of file, offset 0). ui.log doesn't strictly
# need this (SENMA's Zend_Log/Snep_Logger reopens it by path on every
# PHP request, so a plain rename would also be safe there), but using
# the same mechanism for both keeps this script simple and uniform.
#
# Conservative defaults, overridable via environment for testing (see
# scripts/doctor-failure-smoke-test.sh's live rotation proof) --
# SENMA_LOG_MAX_SIZE_BYTES, SENMA_LOG_CHECK_INTERVAL, SENMA_LOG_KEEP.
# 50 MiB / 15 minutes / 5 generations: app-side logs (PHP fatals,
# Apache access, AMI-event noise) grow far slower than Asterisk's own
# verbose log in this project's own observed traffic, so a smaller
# threshold than the Asterisk watcher's 100 MiB still comfortably
# avoids rotating healthy, low-volume logs while catching runaway
# growth (e.g. a logging loop bug) well before it threatens disk space.

set -uo pipefail

MAX_SIZE_BYTES=${SENMA_LOG_MAX_SIZE_BYTES:-52428800}
CHECK_INTERVAL=${SENMA_LOG_CHECK_INTERVAL:-900}
KEEP=${SENMA_LOG_KEEP:-5}
LOG_FILES="/var/log/apache2/mag-error.log /var/log/snep/ui.log"

log() { printf '[log-rotate-app] %s\n' "$*" >&2; }

rotate_copytruncate() {
    local f="$1" ts dest
    ts="$(date -u +%Y%m%d%H%M%S)"
    dest="${f}.${ts}"
    cp -p "$f" "$dest" 2>/dev/null || { log "could not copy $f aside -- skipping rotation this cycle"; return 1; }
    : > "$f"
    gzip -f "$dest" 2>/dev/null
}

prune() {
    local f="$1" old
    # shellcheck disable=SC2012
    ls -t "${f}".*.gz 2>/dev/null | tail -n "+$((KEEP + 1))" | while IFS= read -r old; do
        rm -f "$old"
    done
}

log "started (max_size=${MAX_SIZE_BYTES} bytes, interval=${CHECK_INTERVAL}s, keep=${KEEP})"

while true; do
    sleep "$CHECK_INTERVAL"
    for f in $LOG_FILES; do
        [ -f "$f" ] || continue
        size=$(stat -c %s "$f" 2>/dev/null || echo 0)
        if [ "$size" -ge "$MAX_SIZE_BYTES" ]; then
            log "$f is ${size} bytes (>= ${MAX_SIZE_BYTES}) -- rotating (copytruncate)"
            rotate_copytruncate "$f"
        fi
        prune "$f"
    done
done
