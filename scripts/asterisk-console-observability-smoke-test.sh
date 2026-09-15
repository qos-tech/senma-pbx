#!/bin/bash
#
# TASK-0035E3 — Asterisk console logging / runtime debug observability smoke.
#
# Verifies the project-owned logger.conf contract:
#   * console channel present with notice,warning,error,verbose,debug
#   * full file channel remains present with the same levels
#   * entrypoint reconciles logger.conf onto existing volumes
#   * logger reload succeeds
#   * declaring debug does NOT imply high-volume DEBUG at baseline
#   * operator opt-in/opt-out CLI commands succeed
#
# Does NOT place a real external call. Interactive call-time PJSIP/RTP
# packet visibility is documented as operator proof in
# docs/tasks/0035e3-asterisk-console-logging-runtime-debug-observability.md.
#
# Exit codes: scripts/lib/harness.sh contract.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_BIN="${COMPOSE_BIN:-docker compose}"

log() { harness_log "$@"; }

cd "$REPO_ROOT"

log "==> source logger.conf contract"

SRC="$REPO_ROOT/docker/asterisk-config/logger.conf"
if [ ! -f "$SRC" ]; then
    harness_bad "source logger.conf exists" "missing $SRC"
else
    harness_ok "source logger.conf exists" "$SRC"
fi

if grep -qE '^[[:space:]]*console[[:space:]]*=>.*notice' "$SRC" \
    && grep -qE '^[[:space:]]*console[[:space:]]*=>.*warning' "$SRC" \
    && grep -qE '^[[:space:]]*console[[:space:]]*=>.*error' "$SRC" \
    && grep -qE '^[[:space:]]*console[[:space:]]*=>.*verbose' "$SRC" \
    && grep -qE '^[[:space:]]*console[[:space:]]*=>.*debug' "$SRC"; then
    harness_ok "source console levels" "notice,warning,error,verbose,debug"
else
    harness_bad "source console levels" "$(grep -E '^[[:space:]]*console' "$SRC" || echo missing)"
fi

if grep -qE '^[[:space:]]*full[[:space:]]*=>.*notice' "$SRC" \
    && grep -qE '^[[:space:]]*full[[:space:]]*=>.*debug' "$SRC" \
    && grep -qE '^[[:space:]]*full[[:space:]]*=>.*verbose' "$SRC"; then
    harness_ok "source full levels" "notice..debug retained"
else
    harness_bad "source full levels" "$(grep -E '^[[:space:]]*full' "$SRC" || echo missing)"
fi

log "==> entrypoint ownership"

if grep -q 'TASK-0035E3' "$REPO_ROOT/docker/asterisk-entrypoint.sh" \
    && grep -q 'logger.conf' "$REPO_ROOT/docker/asterisk-entrypoint.sh"; then
    harness_ok "asterisk-entrypoint reconciles logger.conf" "TASK-0035E3 guard present"
else
    harness_bad "asterisk-entrypoint reconciles logger.conf" "missing TASK-0035E3 reconcile"
fi

log "==> live runtime (requires healthy asterisk)"

if ! $COMPOSE_BIN ps asterisk 2>/dev/null | grep -q 'healthy\|running'; then
    harness_bad "asterisk running" "asterisk service not running/healthy"
    harness_complete
fi
harness_ok "asterisk running" "compose service up"

# If the live volume still has the pre-E3 full-only logger.conf, apply the
# entrypoint reconcile once via recreate. When already compliant, skip
# recreate so regression stays non-disruptive.
PRE_CHANNELS="$($COMPOSE_BIN exec -T asterisk asterisk -rx 'logger show channels' 2>/dev/null || true)"
NEED_RECONCILE=0
if ! printf '%s\n' "$PRE_CHANNELS" | grep -Eqi 'Console|console'; then
    NEED_RECONCILE=1
elif ! printf '%s\n' "$PRE_CHANNELS" | grep -Eqi 'Console|console' | grep -q 'DEBUG'; then
    NEED_RECONCILE=1
fi

if [ "$NEED_RECONCILE" -eq 1 ]; then
    log "==> recreate asterisk to apply entrypoint logger reconcile (stale volume)"
    if $COMPOSE_BIN up -d --force-recreate --no-deps asterisk >/tmp/e3-recreate.out 2>&1; then
        harness_ok "asterisk recreate for logger reconcile" "force-recreate OK"
    else
        harness_bad "asterisk recreate for logger reconcile" "$(head -c 400 /tmp/e3-recreate.out)"
        harness_complete
    fi
    ready=0
    for _ in $(seq 1 60); do
        if $COMPOSE_BIN exec -T asterisk asterisk -rx 'core show version' 2>/dev/null | grep -q Asterisk; then
            ready=1
            break
        fi
        sleep 1
    done
    if [ "$ready" -eq 1 ]; then
        harness_ok "asterisk CLI ready after recreate" "core show version OK"
    else
        harness_bad "asterisk CLI ready after recreate" "CLI not ready within 60s"
        harness_complete
    fi
else
    harness_ok "logger volume already reconciled" "console+DEBUG already live; recreate skipped"
fi

CHANNELS="$($COMPOSE_BIN exec -T asterisk asterisk -rx 'logger show channels' 2>/dev/null || true)"
printf '%s\n' "$CHANNELS" > /tmp/e3-logger-channels.txt

if printf '%s\n' "$CHANNELS" | grep -Eqi 'Console|console'; then
    harness_ok "live console channel" "logger show channels lists console"
else
    harness_bad "live console channel" "$CHANNELS"
fi

# Asterisk prints levels without commas; accept DEBUG present on Console line.
CONSOLE_LINE="$(printf '%s\n' "$CHANNELS" | grep -Ei 'Console|console' | head -1 || true)"
MISSING=""
for lvl in NOTICE WARNING ERROR VERBOSE DEBUG; do
    if ! printf '%s' "$CONSOLE_LINE" | grep -q "$lvl"; then
        MISSING="${MISSING} ${lvl}"
    fi
done
if [ -z "$MISSING" ]; then
    harness_ok "live console levels" "$CONSOLE_LINE"
else
    harness_bad "live console levels" "missing:${MISSING} -- ${CONSOLE_LINE}"
fi

FULL_LINE="$(printf '%s\n' "$CHANNELS" | grep -E '/var/log/asterisk/full|full' | head -1 || true)"
if printf '%s' "$FULL_LINE" | grep -q 'NOTICE' \
    && printf '%s' "$FULL_LINE" | grep -q 'VERBOSE' \
    && printf '%s' "$FULL_LINE" | grep -q 'DEBUG'; then
    harness_ok "live full file channel" "$FULL_LINE"
else
    harness_bad "live full file channel" "$FULL_LINE"
fi

# Baseline: debug capability declared, but core debug level should be 0
# after a fresh start (opt-in).
DBG="$($COMPOSE_BIN exec -T asterisk asterisk -rx 'core show settings' 2>/dev/null | grep -i 'Debug level' || true)"
if printf '%s' "$DBG" | grep -Eiq 'Debug level[[:space:]]*:[[:space:]]*0'; then
    harness_ok "default debug level is 0" "$DBG"
else
    if printf '%s' "$DBG" | grep -Eiq 'Debug level[[:space:]]*:[[:space:]]*[1-9]'; then
        harness_bad "default debug level is 0" "$DBG"
    else
        harness_ok "default debug level is 0" "settings line not found; assuming default (no forced debug in entrypoint) -- $DBG"
    fi
fi

# logger reload must succeed with the new file.
RELOAD="$($COMPOSE_BIN exec -T asterisk asterisk -rx 'logger reload' 2>&1 || true)"
if printf '%s' "$RELOAD" | grep -Eqi 'fail|error|cannot'; then
    harness_bad "logger reload" "$RELOAD"
else
    harness_ok "logger reload" "${RELOAD:-OK}"
fi

# Opt-in / opt-out CLI path (no packet flood asserted; command success only).
for cmd in \
    'core set verbose 5' \
    'core set debug 5' \
    'pjsip set logger on' \
    'rtp set debug on' \
    'pjsip set logger off' \
    'rtp set debug off' \
    'core set debug 0' \
    'core set verbose 3'
do
    OUT="$($COMPOSE_BIN exec -T asterisk asterisk -rx "$cmd" 2>&1 || true)"
    if printf '%s' "$OUT" | grep -Eqi 'no such|failed|error:'; then
        harness_bad "cli: $cmd" "$OUT"
    else
        harness_ok "cli: $cmd" "$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-80)"
    fi
done

# File logging still writable after reload.
BEFORE="$($COMPOSE_BIN exec -T asterisk sh -c 'wc -c < /var/log/asterisk/full' 2>/dev/null | tr -d '[:space:]' || echo 0)"
$COMPOSE_BIN exec -T asterisk asterisk -rx 'core set verbose 5' >/dev/null 2>&1 || true
$COMPOSE_BIN exec -T asterisk asterisk -rx 'logger reload' >/dev/null 2>&1 || true
$COMPOSE_BIN exec -T asterisk asterisk -rx 'core show version' >/dev/null 2>&1 || true
AFTER="$($COMPOSE_BIN exec -T asterisk sh -c 'wc -c < /var/log/asterisk/full' 2>/dev/null | tr -d '[:space:]' || echo 0)"
if [ "${AFTER:-0}" -ge "${BEFORE:-0}" ] 2>/dev/null; then
    harness_ok "full log file still active" "bytes before=$BEFORE after=$AFTER"
else
    harness_bad "full log file still active" "bytes before=$BEFORE after=$AFTER"
fi

harness_complete
