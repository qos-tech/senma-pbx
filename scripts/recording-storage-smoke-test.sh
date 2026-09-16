#!/bin/bash
#
# TASK-0035E8 — shared call-recording storage & permissions.
#
# Proves:
#   1. Compose maps host ./snep/arquivos to Asterisk monitor + app path_voz
#   2. Directory exists with non-0777 mode (2770 contract)
#   3. Asterisk identity can create a file under monitor
#   4. Same inode/content visible via app path_voz and on the host
#   5. App identity (www-data) can read the Asterisk-created file
#   6. Backup inventory still includes snep/arquivos
#   7. Restore script re-applies recording directory contract
#   8. Business-rule record flag is not mutated by this smoke
#
# Non-destructive: uses a clearly named temp probe file, then removes it.
# Does not place a live MixMonitor call (record policy stays untouched).
#
# Exit code: see scripts/lib/harness.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

cd "$REPO_ROOT" || harness_blocked "could not cd into repo root"

log() { harness_log "$@"; }
PROBE_NAME="e8-recording-probe-$$.txt"
PROBE_CONTENT="TASK-0035E8 probe $(date -u +%Y-%m-%dT%H:%M:%SZ)"

COMPOSE_BIN="${SMOKE_COMPOSE:-docker compose}"
set -a
# shellcheck disable=SC1091
[ -f "$REPO_ROOT/.env" ] && . "$REPO_ROOT/.env"
set +a

# ---------------------------------------------------------------------------
# 0. Runtime present
# ---------------------------------------------------------------------------
if ! $COMPOSE_BIN ps -q app >/dev/null 2>&1 || [ -z "$($COMPOSE_BIN ps -q app 2>/dev/null)" ]; then
    harness_blocked "needs running bridge stack (make up / ensure-dev-stack)"
fi
if ! $COMPOSE_BIN ps -q asterisk >/dev/null 2>&1 || [ -z "$($COMPOSE_BIN ps -q asterisk 2>/dev/null)" ]; then
    harness_blocked "needs running asterisk container"
fi

# ---------------------------------------------------------------------------
# 1. Static compose mount contract
# ---------------------------------------------------------------------------
log "==> 1: compose.yaml shared recording mounts"
if grep -qE './snep/arquivos:/var/spool/asterisk/monitor' "$REPO_ROOT/compose.yaml" \
   && grep -qE './snep/arquivos:/var/www/html/snep/arquivos' "$REPO_ROOT/compose.yaml"; then
    harness_ok "1: compose mount contract" "host snep/arquivos -> monitor + path_voz"
else
    harness_bad "1: compose mount contract" "missing ./snep/arquivos binds in compose.yaml"
fi

# Pilot overlay must not redefine competing recording mounts.
if [ -f "$REPO_ROOT/compose.pilot.yaml" ]; then
    if grep -qE 'arquivos|/var/spool/asterisk/monitor' "$REPO_ROOT/compose.pilot.yaml"; then
        harness_bad "1: pilot overlay clean" "compose.pilot.yaml must not override recording mounts"
    else
        harness_ok "1: pilot overlay clean" "no competing recording mounts"
    fi
fi

# ---------------------------------------------------------------------------
# 2. Directory existence + mode (no 0777)
# ---------------------------------------------------------------------------
log "==> 2: host recording directory mode"
HOST_DIR="$REPO_ROOT/snep/arquivos"
if [ ! -d "$HOST_DIR" ]; then
    harness_bad "2: host dir exists" "snep/arquivos missing"
else
    MODE="$(stat -c '%a' "$HOST_DIR")"
    OTHER=$((8#${MODE} % 8))
    if [ "$MODE" = "777" ] || [ "$MODE" = "0777" ] || [ "$((OTHER & 2))" -ne 0 ]; then
        harness_bad "2: not world-writable" "mode=$MODE (0777/world-write forbidden)"
    else
        harness_ok "2: not world-writable" "mode=$MODE"
    fi
    # Prefer 2770 contract when entrypoint has run
    if [ "$MODE" = "2770" ]; then
        harness_ok "2: setgid shared mode" "mode 2770"
    else
        harness_bad "2: setgid shared mode" "expected 2770 after entrypoint, got $MODE"
    fi
fi

# ---------------------------------------------------------------------------
# 3–5. Asterisk write → app read → host same inode
# ---------------------------------------------------------------------------
log "==> 3: asterisk can create under /var/spool/asterisk/monitor"
harness_register_best_effort_cleanup "e8 probe host" "sudo rm -f '$HOST_DIR/$PROBE_NAME' 2>/dev/null || true"
harness_register_best_effort_cleanup "e8 probe asterisk" \
  "$COMPOSE_BIN exec -T asterisk rm -f /var/spool/asterisk/monitor/$PROBE_NAME >/dev/null 2>&1 || true"
harness_register_best_effort_cleanup "e8 probe app" \
  "$COMPOSE_BIN exec -T -u www-data app rm -f /var/www/html/snep/arquivos/$PROBE_NAME >/dev/null 2>&1 || true"

if $COMPOSE_BIN exec -T -u asterisk asterisk sh -c \
    "printf '%s\n' '$PROBE_CONTENT' > /var/spool/asterisk/monitor/$PROBE_NAME"; then
    harness_ok "3: asterisk write" "created $PROBE_NAME via monitor path"
else
    harness_bad "3: asterisk write" "asterisk cannot write /var/spool/asterisk/monitor/$PROBE_NAME"
fi

log "==> 4: same file visible on host and via path_voz"
# Directory mode 2770: unprivileged host user (not in GID 3000) cannot
# list/read. Prove host backing via root (sudo) — same path, same inode.
HOST_INODE=""
if sudo test -f "$HOST_DIR/$PROBE_NAME" 2>/dev/null; then
    HOST_INODE="$(sudo stat -c '%i' "$HOST_DIR/$PROBE_NAME")"
    harness_ok "4: host sees probe" "inode=$HOST_INODE (via sudo; dir mode 2770)"
else
    harness_bad "4: host sees probe" "missing $HOST_DIR/$PROBE_NAME even for root"
fi

APP_VIEW="$($COMPOSE_BIN exec -T app sh -c \
    "stat -c '%i' /var/www/html/snep/arquivos/$PROBE_NAME 2>/dev/null" | tr -d '\r')"
MON_VIEW="$($COMPOSE_BIN exec -T asterisk sh -c \
    "stat -c '%i' /var/spool/asterisk/monitor/$PROBE_NAME 2>/dev/null" | tr -d '\r')"
if [ -n "$HOST_INODE" ] && [ "$HOST_INODE" = "$APP_VIEW" ] && [ "$HOST_INODE" = "$MON_VIEW" ]; then
    harness_ok "4: shared inode" "host=app=monitor inode $HOST_INODE"
else
    harness_bad "4: shared inode" "host=$HOST_INODE app=$APP_VIEW monitor=$MON_VIEW"
fi

log "==> 5: www-data can read asterisk-created file"
READ_OUT="$($COMPOSE_BIN exec -T -u www-data app sh -c \
    "cat /var/www/html/snep/arquivos/$PROBE_NAME" 2>/dev/null | tr -d '\r')"
if [ "$READ_OUT" = "$PROBE_CONTENT" ]; then
    harness_ok "5: app read" "www-data read matching content"
else
    harness_bad "5: app read" "got='$READ_OUT' expected='$PROBE_CONTENT'"
fi

# Cleanup probe (host may lack group access — use containers + sudo)
$COMPOSE_BIN exec -T asterisk rm -f "/var/spool/asterisk/monitor/$PROBE_NAME" >/dev/null 2>&1 || true
$COMPOSE_BIN exec -T -u www-data app rm -f "/var/www/html/snep/arquivos/$PROBE_NAME" >/dev/null 2>&1 || true
sudo rm -f "$HOST_DIR/$PROBE_NAME" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 6. Backup includes arquivos
# ---------------------------------------------------------------------------
log "==> 6: backup covers snep/arquivos"
if grep -qE 'snep/arquivos|arquivos\.tar\.gz|archiving snep/arquivos' "$REPO_ROOT/scripts/backup.sh"; then
    harness_ok "6: backup includes arquivos" "backup.sh archives snep/arquivos"
else
    harness_bad "6: backup includes arquivos" "backup.sh missing arquivos coverage"
fi

# ---------------------------------------------------------------------------
# 7. Restore reapplies contract
# ---------------------------------------------------------------------------
log "==> 7: restore reapplies recording permissions"
if grep -q 'restore_recording_dir_contract\|blib_apply_recording_dir_contract\|blib_restore_recording_store\|chmod 2770' "$REPO_ROOT/scripts/restore.sh" \
   && grep -q 'blib_restore_recording_store\|blib_wipe_recording_store' "$REPO_ROOT/scripts/lib/backup-lib.sh"; then
    harness_ok "7: restore permission contract" "restore.sh uses container-aware arquivos restore + 2770 contract"
else
    harness_bad "7: restore permission contract" "restore.sh missing container-aware recording restore contract"
fi

# ---------------------------------------------------------------------------
# 8. Static: no 0777 in recording init paths
# ---------------------------------------------------------------------------
log "==> 8: no chmod 777 in recording init"
BAD777="$(grep -nE 'chmod[[:space:]]+(-R[[:space:]]+)?0?777' \
    "$REPO_ROOT/docker/entrypoint.sh" \
    "$REPO_ROOT/docker/asterisk-entrypoint.sh" \
    "$REPO_ROOT/scripts/restore.sh" 2>/dev/null || true)"
if [ -n "$BAD777" ]; then
    harness_bad "8: no 0777" "$BAD777"
else
    harness_ok "8: no 0777" "recording init paths clean"
fi

# ---------------------------------------------------------------------------
# 9. Business-rule record flag untouched by this smoke
# ---------------------------------------------------------------------------
log "==> 9: record business-rule semantics unchanged by smoke"
# Assert this file never issues DML against the business-rules table.
_dml_hits="$(grep -nE 'UPDATE[[:space:]]+regras_negocio|DELETE[[:space:]]+FROM[[:space:]]+regras_negocio|INSERT[[:space:]]+INTO[[:space:]]+regras_negocio' \
    "$SCRIPT_DIR/recording-storage-smoke-test.sh" || true)"
if [ -n "$_dml_hits" ]; then
    harness_bad "9: no rule mutation" "$_dml_hits"
else
    harness_ok "9: no rule mutation" "no DML against business-rules table in this smoke"
fi

# Entrypoint + AGI markers present
if grep -q 'TASK-0035E8' "$REPO_ROOT/docker/entrypoint.sh" \
   && grep -q 'TASK-0035E8' "$REPO_ROOT/docker/asterisk-entrypoint.sh" \
   && grep -q 'TASK-0035E8' "$REPO_ROOT/snep/agi/snep.php"; then
    harness_ok "9: implementation markers" "entrypoint + AGI carry TASK-0035E8"
else
    harness_bad "9: implementation markers" "missing TASK-0035E8 markers"
fi

harness_complete
