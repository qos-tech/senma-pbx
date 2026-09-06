#!/bin/bash
#
# TASK-0033D: bounded-growth watcher for Asterisk's file-based logs
# (/var/log/asterisk/full, queue_log).
#
# No cron/systemd/logrotate binary exists in this minimal image
# (confirmed live: none of `cron`, `crond`, `logrotate` are present) --
# this script is backgrounded from asterisk-entrypoint.sh alongside
# `exec asterisk`, running as a sibling process for the container's
# whole lifetime. This is the container's own rotation mechanism, not
# an external one; see docs/tasks/
# 0033d-diagnostics-logging-storage-lifecycle.md LOG LIFECYCLE.
#
# Rotation: Asterisk's own `logger rotate` CLI command. Confirmed live
# (this task's own validation) to reopen the log file(s) without
# restarting Asterisk, reloading PJSIP, or dropping active calls --
# `core show uptime` before/after showed the same running process.
# Asterisk's rotation only renames the current file to the lowest
# unused `<name>.<N>` suffix and starts a fresh one -- it never deletes
# or compresses anything itself, so unbounded rotated-file COUNT would
# just replace unbounded single-file SIZE. This script closes that gap:
# after every check, it gzips any not-yet-compressed rotated file, then
# deletes all but the $SENMA_LOG_KEEP most recent (by mtime) compressed
# ones.
#
# Conservative defaults (documented rationale, see the task doc's LOG-
# SIZE THRESHOLDS section): rotate at 100 MiB (this project's actual
# `full` log was observed live at 284-297 MiB with zero rotation ever
# having run -- 100 MiB catches that class of runaway growth without
# rotating on ordinary, healthy verbose-log volume), check every 15
# minutes (frequent enough that a runaway log is caught within one
# check cycle's worth of growth, cheap enough to cost nothing at rest),
# keep 5 compressed generations (bounds total disk to roughly one
# active 100 MiB file + a handful of compressed archives, typically far
# smaller after gzip on repetitive Asterisk verbose output).
#
# All three are overridable via environment for testing (see
# scripts/doctor-failure-smoke-test.sh's live rotation proof) --
# SENMA_LOG_MAX_SIZE_BYTES, SENMA_LOG_CHECK_INTERVAL, SENMA_LOG_KEEP.

set -uo pipefail

LOG_DIR=/var/log/asterisk
MAX_SIZE_BYTES=${SENMA_LOG_MAX_SIZE_BYTES:-104857600}
CHECK_INTERVAL=${SENMA_LOG_CHECK_INTERVAL:-900}
KEEP=${SENMA_LOG_KEEP:-5}
LOG_BASES="full queue_log"

log() { printf '[log-rotate-asterisk] %s\n' "$*" >&2; }

compress_and_prune() {
    local base f old
    for base in $LOG_BASES; do
        for f in "$LOG_DIR/$base".[0-9]*; do
            [ -e "$f" ] || continue
            case "$f" in
                *.gz) ;;
                *) gzip -f "$f" 2>/dev/null ;;
            esac
        done
        # keep the $KEEP most recent compressed generations, delete the rest
        # shellcheck disable=SC2012
        ls -t "$LOG_DIR/$base".*.gz 2>/dev/null | tail -n "+$((KEEP + 1))" | while IFS= read -r old; do
            rm -f "$old"
        done
    done
}

log "started (max_size=${MAX_SIZE_BYTES} bytes, interval=${CHECK_INTERVAL}s, keep=${KEEP})"

while true; do
    sleep "$CHECK_INTERVAL"

    need_rotate=0
    for base in $LOG_BASES; do
        f="$LOG_DIR/$base"
        [ -f "$f" ] || continue
        size=$(stat -c %s "$f" 2>/dev/null || echo 0)
        if [ "$size" -ge "$MAX_SIZE_BYTES" ]; then
            need_rotate=1
            log "$f is ${size} bytes (>= ${MAX_SIZE_BYTES}) -- rotating"
        fi
    done

    if [ "$need_rotate" -eq 1 ]; then
        asterisk -rx "logger rotate" >/dev/null 2>&1 || log "logger rotate failed (Asterisk not reachable yet?)"
    fi

    compress_and_prune
done
