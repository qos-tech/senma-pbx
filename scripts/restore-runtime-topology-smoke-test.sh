#!/bin/bash
#
# TASK-0035E5 / I8 — restore runtime topology preservation.
#
# Proves restore distinguishes data contents from runtime topology and
# never silently falls back to bare `docker compose` (bridge) for a
# pilot/production session.
#
# Deterministic proofs (no destructive restore of the live stack):
#   1. compose-runtime host command merges to network_mode=host
#   2. bridge command stays bridge-shaped
#   3. RELEASE_VERSION != dev selects host even if bridge containers run
#   4. SENMA_RUNTIME_MODE=bridge stays bridge under a release tag
#   5. missing release images fail closed for host restore
#   6. make restore wires host when RELEASE_VERSION is a release tag
#   7. restore.sh recipes still use --no-build (E4)
#   8. --validate-only still works without topology mutation
#
# Optional live host-network restore proof remains on the real pilot
# (see docs/tasks/0035e5-restore-runtime-topology-preservation.md).
#
# Exit code: see scripts/lib/harness.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
# shellcheck source=lib/compose-runtime.sh
source "$SCRIPT_DIR/lib/compose-runtime.sh"
harness_install_traps

cd "$REPO_ROOT" || harness_blocked "could not cd into repo root"

log() { harness_log "$@"; }
COMPOSE_BIN="docker compose"

# ---------------------------------------------------------------------------
# 1. Host compose command → network_mode=host for app/asterisk/db
# ---------------------------------------------------------------------------
log "==> 1: host compose command yields network_mode=host"
HOST_CMD="$(senma_compose_cmd_for_mode host)"
HOST_CFG="$(mktemp)"
harness_register_best_effort_cleanup "host cfg" "rm -f '$HOST_CFG'"
if COMPOSE_PROFILES= $HOST_CMD config >"$HOST_CFG" 2>/tmp/e5-host-cfg.err; then
    python3 - "$HOST_CFG" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
ok = True
msgs = []
for name in ("app", "asterisk", "db"):
    s = d["services"][name]
    if s.get("network_mode") != "host":
        ok = False; msgs.append(f"{name} mode={s.get('network_mode')}")
    if s.get("ports"):
        ok = False; msgs.append(f"{name} ports={s.get('ports')}")
open("/tmp/e5-host-py.out", "w").write("OK" if ok else ("FAIL: " + "; ".join(msgs)))
sys.exit(0 if ok else 1)
PY
    if [ "$(cat /tmp/e5-host-py.out 2>/dev/null)" = "OK" ]; then
        harness_ok "1: host compose network_mode=host" "$HOST_CMD"
    else
        harness_bad "1: host compose network_mode=host" "$(cat /tmp/e5-host-py.out 2>/dev/null)"
    fi
else
    harness_bad "1: host compose config" "$(head -c 300 /tmp/e5-host-cfg.err)"
fi

# ---------------------------------------------------------------------------
# 2. Bridge compose remains bridge (no host mode)
# ---------------------------------------------------------------------------
log "==> 2: bridge compose command stays bridge-shaped"
BRIDGE_CMD="$(senma_compose_cmd_for_mode bridge)"
BRIDGE_CFG="$(mktemp)"
harness_register_best_effort_cleanup "bridge cfg" "rm -f '$BRIDGE_CFG'"
if COMPOSE_PROFILES= $BRIDGE_CMD config >"$BRIDGE_CFG" 2>/tmp/e5-bridge-cfg.err; then
    python3 - "$BRIDGE_CFG" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
ok = True
msgs = []
for name in ("app", "asterisk", "db"):
    s = d["services"][name]
    if s.get("network_mode") == "host":
        ok = False; msgs.append(f"{name} unexpectedly host")
open("/tmp/e5-bridge-py.out", "w").write("OK" if ok else ("FAIL: " + "; ".join(msgs)))
sys.exit(0 if ok else 1)
PY
    if [ "$(cat /tmp/e5-bridge-py.out 2>/dev/null)" = "OK" ]; then
        harness_ok "2: bridge compose not host" "$BRIDGE_CMD"
    else
        harness_bad "2: bridge compose not host" "$(cat /tmp/e5-bridge-py.out 2>/dev/null)"
    fi
else
    harness_bad "2: bridge compose config" "$(head -c 300 /tmp/e5-bridge-cfg.err)"
fi

# ---------------------------------------------------------------------------
# 3. RELEASE_VERSION != dev selects host (even with bridge containers up)
# ---------------------------------------------------------------------------
log "==> 3: RELEASE_VERSION release tag selects host topology"
if docker image inspect senma-app:v0.1.0-rc.2 >/dev/null 2>&1 \
   && docker image inspect senma-asterisk:v0.1.0-rc.2 >/dev/null 2>&1; then
    OUT="$(
      unset SENMA_RUNTIME_MODE RESTORE_RUNTIME_MODE SMOKE_COMPOSE COMPOSE_FILES
      export RELEASE_VERSION=v0.1.0-rc.2
      bash "$SCRIPT_DIR/restore.sh" --print-runtime 2>&1
    )" || true
    if printf '%s' "$OUT" | grep -q 'SENMA_RUNTIME_MODE=host' \
       && printf '%s' "$OUT" | grep -q 'compose.pilot.yaml'; then
        harness_ok "3: release tag → host" "RESTORE selects compose.pilot.yaml"
    else
        harness_bad "3: release tag → host" "$OUT"
    fi
else
    # Still prove resolver policy without requiring rc.2 images: missing
    # images must fail closed rather than fall back to bridge.
    OUT="$(
      unset SENMA_RUNTIME_MODE RESTORE_RUNTIME_MODE SMOKE_COMPOSE COMPOSE_FILES
      export RELEASE_VERSION=v0.0.0-e5-topology-probe
      bash "$SCRIPT_DIR/restore.sh" --print-runtime 2>&1
    )" && RC=0 || RC=$?
    if [ "${RC:-1}" -ne 0 ] && printf '%s' "$OUT" | grep -qiE 'not found|release-build|never builds'; then
        harness_ok "3: release tag without images fails closed" "no silent bridge fallback"
    else
        harness_bad "3: release tag without images fails closed" "rc=${RC:-?} out=$OUT"
    fi
fi

# ---------------------------------------------------------------------------
# 4. Explicit bridge wins under a release tag (deliberate)
# ---------------------------------------------------------------------------
log "==> 4: SENMA_RUNTIME_MODE=bridge is honored under a release tag"
OUT="$(
  export SENMA_RUNTIME_MODE=bridge RELEASE_VERSION=v0.1.0-rc.2
  unset SMOKE_COMPOSE COMPOSE_FILES
  bash "$SCRIPT_DIR/restore.sh" --print-runtime 2>&1
)" || true
if printf '%s' "$OUT" | grep -q 'SENMA_RUNTIME_MODE=bridge' \
   && ! printf '%s' "$OUT" | grep -q 'compose.pilot.yaml'; then
    harness_ok "4: explicit bridge under release tag" "operator can deliberately select bridge"
else
    harness_bad "4: explicit bridge under release tag" "$OUT"
fi

# ---------------------------------------------------------------------------
# 5. Host + missing images fail closed (never build)
# ---------------------------------------------------------------------------
log "==> 5: host restore fails when release images are missing"
OUT="$(
  export SENMA_RUNTIME_MODE=host RELEASE_VERSION=v0.0.0-e5-missing
  unset SMOKE_COMPOSE COMPOSE_FILES SENMA_ALLOW_HOST_DEV
  bash "$SCRIPT_DIR/restore.sh" --print-runtime 2>&1
)" && RC=0 || RC=$?
if [ "${RC:-1}" -ne 0 ] && printf '%s' "$OUT" | grep -qiE 'not found|release-build|never builds'; then
    harness_ok "5: missing images fail closed" "host restore does not build"
else
    harness_bad "5: missing images fail closed" "rc=${RC:-?} out=$OUT"
fi

# ---------------------------------------------------------------------------
# 6. make restore recipe selects host for RELEASE_VERSION != dev
# ---------------------------------------------------------------------------
log "==> 6: make restore wires host for release RELEASE_VERSION"
MAKE_N="$(make -n restore FROM=/tmp/senma-e5-probe.tar.gz RELEASE_VERSION=v0.1.0-rc.5 2>&1 || true)"
if printf '%s' "$MAKE_N" | grep -q 'SENMA_RUNTIME_MODE=host' \
   && printf '%s' "$MAKE_N" | grep -q 'compose.pilot.yaml'; then
    harness_ok "6: make restore pilot wiring" "RELEASE_VERSION release → host + compose.pilot.yaml"
else
    harness_bad "6: make restore pilot wiring" "$MAKE_N"
fi
MAKE_DEV="$(make -n restore FROM=/tmp/senma-e5-probe.tar.gz RELEASE_VERSION=dev 2>&1 || true)"
if printf '%s' "$MAKE_DEV" | grep -q 'SENMA_RUNTIME_MODE=bridge'; then
    harness_ok "6: make restore bridge wiring" "RELEASE_VERSION=dev → bridge"
else
    harness_bad "6: make restore bridge wiring" "$MAKE_DEV"
fi

# ---------------------------------------------------------------------------
# 7. restore.sh never builds (E4 preserved)
# ---------------------------------------------------------------------------
log "==> 7: restore.sh uses --no-build on recreate"
if grep -qE 'up -d --no-build' "$SCRIPT_DIR/restore.sh" \
   && ! grep -qE 'up -d --build' "$SCRIPT_DIR/restore.sh"; then
    harness_ok "7: restore --no-build" "db/asterisk/app recreate paths use --no-build"
else
    harness_bad "7: restore --no-build" "build flag still present in restore.sh"
fi

# ---------------------------------------------------------------------------
# 8. --validate-only still works (data path unchanged; no topology mutate)
# ---------------------------------------------------------------------------
log "==> 8: --validate-only accepts a good archive without touching topology"
if ! $COMPOSE_BIN ps -q app >/dev/null 2>&1 || [ -z "$($COMPOSE_BIN ps -q app 2>/dev/null)" ]; then
    harness_blocked "8: validate-only proof needs a running stack to produce a backup"
fi
# shellcheck source=lib/backup-lib.sh
source "$SCRIPT_DIR/lib/backup-lib.sh"
TMP_DEST="$(mktemp -d)"
harness_register_best_effort_cleanup "e5 backup dest" "rm -rf '$TMP_DEST'"
BEFORE_APP="$(docker image inspect senma-app:dev --format '{{.Id}}' 2>/dev/null || true)"
BEFORE_AST="$(docker image inspect senma-asterisk:dev --format '{{.Id}}' 2>/dev/null || true)"
if bash "$SCRIPT_DIR/backup.sh" --dest "$TMP_DEST" >/tmp/e5-backup.out 2>&1; then
    ARCHIVE="$(find "$TMP_DEST" -maxdepth 1 -name 'senma-backup-*.tar.gz' | head -1)"
    if [ -n "$ARCHIVE" ] && bash "$SCRIPT_DIR/restore.sh" "$ARCHIVE" --validate-only >/tmp/e5-validate.out 2>&1; then
        harness_ok "8: validate-only" "archive accepted; no restore mutate"
    else
        harness_bad "8: validate-only" "$(tail -c 400 /tmp/e5-validate.out 2>/dev/null)"
    fi
else
    harness_blocked "8: could not create backup for validate-only -- see /tmp/e5-backup.out"
fi
AFTER_APP="$(docker image inspect senma-app:dev --format '{{.Id}}' 2>/dev/null || true)"
AFTER_AST="$(docker image inspect senma-asterisk:dev --format '{{.Id}}' 2>/dev/null || true)"
if [ -n "$BEFORE_APP" ] && [ "$BEFORE_APP" = "$AFTER_APP" ] && [ "$BEFORE_AST" = "$AFTER_AST" ]; then
    harness_ok "8: image ids unchanged across backup/validate-only" "senma-*:dev before==after"
else
    harness_bad "8: image ids unchanged across backup/validate-only" "before app=$BEFORE_APP ast=$BEFORE_AST after app=$AFTER_APP ast=$AFTER_AST"
fi

# ---------------------------------------------------------------------------
# 9. Ambiguous / host+dev without override fails closed
# ---------------------------------------------------------------------------
log "==> 9: host + RELEASE_VERSION=dev fails closed without SENMA_ALLOW_HOST_DEV"
OUT="$(
  export SENMA_RUNTIME_MODE=host RELEASE_VERSION=dev
  unset SENMA_ALLOW_HOST_DEV SMOKE_COMPOSE COMPOSE_FILES
  bash "$SCRIPT_DIR/restore.sh" --print-runtime 2>&1
)" && RC=0 || RC=$?
if [ "${RC:-1}" -ne 0 ] && printf '%s' "$OUT" | grep -qiE 'requires RELEASE_VERSION|REFUSE|ERROR'; then
    harness_ok "9: host+:dev refused" "fail closed"
else
    harness_bad "9: host+:dev refused" "rc=${RC:-?} out=$OUT"
fi

harness_complete
