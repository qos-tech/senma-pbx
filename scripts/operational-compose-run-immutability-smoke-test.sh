#!/bin/bash
#
# TASK-0035E4A — operational compose-run immutability.
#
# Proves operational helpers never implicitly build release-tagged images
# when the required image is absent locally (real-pilot I4 regression:
# backup.sh + RELEASE_VERSION=v0.1.0-rc.7 built senma-asterisk with
# revision=unknown).
#
# Platform note: Docker Compose 2.40.x `run` has no `--no-build`. When a
# service declares `build:` and `image:` is missing, `run` builds even
# with `--pull never`. Hardening is therefore:
#   senma_compose_run → local image preflight + `run --pull never`
#
# Deterministic proofs (no destructive restore, no real RC mutation):
#   1. Static: operational scripts never bare-compose-run; use
#      senma_compose_run (allowlisted DEV/TEST exceptions)
#   2. Missing fake release image → senma_require_local_image fails closed
#   3. Missing fake release image → backup.sh fails before creating it
#   4. After failed backup attempt, fake image remains absent
#   5. Missing fake release image → senma_compose_run fails and does not
#      create the image
#   6. Present :dev images → backup still works (non-destructive)
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
FAKE_VER="v0.0.0-immutability-test"
FAKE_APP="senma-app:${FAKE_VER}"
FAKE_AST="senma-asterisk:${FAKE_VER}"

# Strip "N:" prefixes from grep -n so comment/code classification works.
_e4a_code_lines() {
    local path="$1"
    local pat='$COMPOSE|docker compose'
    # shellcheck disable=SC2016
    grep -nE "(${pat})[[:space:]]+run([[:space:]]|$)" "$path" 2>/dev/null \
      | while IFS= read -r line; do
            local content="${line#*:}"
            # Skip full-line comments (after line-number prefix).
            if printf '%s' "$content" | grep -qE '^[[:space:]]*#'; then
                continue
            fi
            printf '%s\n' "$line"
        done
}

# ---------------------------------------------------------------------------
# 1. Static operational compose-run gate
# ---------------------------------------------------------------------------
log "==> 1: operational scripts must not bare-compose-run (use senma_compose_run)"

# Files classified OPERATIONAL/RUNTIME (must use senma_compose_run only).
OPERATIONAL_FILES=(
    scripts/backup.sh
    scripts/restore.sh
    scripts/lib/secrets-lib.sh
)

STATIC_FAIL=0
for f in "${OPERATIONAL_FILES[@]}"; do
    path="$REPO_ROOT/$f"
    [ -f "$path" ] || { harness_bad "1: $f exists" "missing"; STATIC_FAIL=1; continue; }
    BAD_LINES="$(_e4a_code_lines "$path")"
    if [ -n "$BAD_LINES" ]; then
        harness_bad "1: $f bare compose run" "$BAD_LINES"
        STATIC_FAIL=1
    else
        harness_ok "1: $f compose-run hardened" "no bare compose run; uses senma_compose_run"
    fi
    if grep -q 'senma_compose_run' "$path"; then
        harness_ok "1: $f calls senma_compose_run" "present"
    else
        harness_bad "1: $f calls senma_compose_run" "missing senma_compose_run usage"
        STATIC_FAIL=1
    fi
done

# Helper must preflight + --pull never (Compose run has no --no-build).
HELPER="$REPO_ROOT/scripts/lib/compose-runtime.sh"
if grep -q 'senma_compose_run' "$HELPER" \
   && grep -q 'senma_require_local_image' "$HELPER" \
   && grep -q 'senma_require_runtime_images' "$HELPER" \
   && grep -qE 'run --pull never' "$HELPER"; then
    harness_ok "1: shared helpers present" "senma_compose_run + require_* + --pull never"
else
    harness_bad "1: shared helpers present" "helpers incomplete in compose-runtime.sh"
    STATIC_FAIL=1
fi

# Allowlisted DEV/TEST: smokes may mention compose run in comments only.
if grep -RnlE 'docker compose run|\$COMPOSE run' scripts --include='*-smoke-test.sh' >/tmp/e4a-smoke-compose-run.txt 2>/dev/null; then
    while IFS= read -r sf; do
        [ -n "$sf" ] || continue
        BAD="$(_e4a_code_lines "$sf")"
        if [ -n "$BAD" ]; then
            # Exception: compose-runtime's own helper is not a smoke.
            harness_bad "1: smoke $sf bare compose run" "$BAD (classify DEV/TEST or harden)"
            STATIC_FAIL=1
        fi
    done < /tmp/e4a-smoke-compose-run.txt
fi
harness_register_best_effort_cleanup "e4a smoke compose list" "rm -f /tmp/e4a-smoke-compose-run.txt"

# ---------------------------------------------------------------------------
# 2. Fail-closed helper when image missing
# ---------------------------------------------------------------------------
log "==> 2: senma_require_local_image fails closed for ${FAKE_AST}"
docker image rm -f "$FAKE_APP" "$FAKE_AST" >/dev/null 2>&1 || true
if docker image inspect "$FAKE_AST" >/dev/null 2>&1; then
    harness_blocked "2: could not ensure ${FAKE_AST} is absent"
fi
OUT="$(senma_require_local_image "$FAKE_AST" 2>&1)" && RC=0 || RC=$?
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -qiE 'not available locally|release-build'; then
    harness_ok "2: missing image fails closed" "$OUT"
else
    harness_bad "2: missing image fails closed" "rc=$RC out=$OUT"
fi

# ---------------------------------------------------------------------------
# 3–4. Backup with fake RELEASE_VERSION must not create the image
# ---------------------------------------------------------------------------
log "==> 3: backup.sh with missing release image fails without building"
BEFORE_INSPECT="$(docker image inspect "$FAKE_AST" >/dev/null 2>&1 && echo PRESENT || echo ABSENT)"
if [ "$BEFORE_INSPECT" != "ABSENT" ]; then
    harness_blocked "3: ${FAKE_AST} unexpectedly present before test"
fi

# backup requires Up containers — use real bridge :dev stack but override
# RELEASE_VERSION so image preflight trips before compose-run.
set -a
# shellcheck disable=SC1091
[ -f "$REPO_ROOT/.env" ] && . "$REPO_ROOT/.env"
set +a
COMPOSE_BIN="${SMOKE_COMPOSE:-docker compose}"
if ! $COMPOSE_BIN ps -q app >/dev/null 2>&1 || [ -z "$($COMPOSE_BIN ps -q app 2>/dev/null)" ]; then
    harness_blocked "3: needs a running bridge stack (make up) for backup preflight proof"
fi

TMP_DEST="$(mktemp -d)"
harness_register_best_effort_cleanup "e4a backup dest" "rm -rf '$TMP_DEST'"
BACKUP_OUT="$(
  unset SENMA_RUNTIME_MODE RESTORE_RUNTIME_MODE SMOKE_COMPOSE COMPOSE_FILES
  export RELEASE_VERSION="$FAKE_VER"
  # Force bridge so resolve does not demand pilot overlay for this probe.
  export SENMA_RUNTIME_MODE=bridge
  export SENMA_ALLOW_HOST_DEV=1
  bash "$SCRIPT_DIR/backup.sh" --dest "$TMP_DEST" 2>&1
)" && BACKUP_RC=0 || BACKUP_RC=$?

AFTER_INSPECT="$(docker image inspect "$FAKE_AST" >/dev/null 2>&1 && echo PRESENT || echo ABSENT)"
AFTER_APP_INSPECT="$(docker image inspect "$FAKE_APP" >/dev/null 2>&1 && echo PRESENT || echo ABSENT)"

if [ "${BACKUP_RC:-0}" -ne 0 ] \
   && printf '%s' "$BACKUP_OUT" | grep -qiE 'not available locally|release-build|aborted'; then
    harness_ok "3: backup fails closed without release image" "rc=$BACKUP_RC"
else
    harness_bad "3: backup fails closed without release image" "rc=${BACKUP_RC:-?} out=$(printf '%s' "$BACKUP_OUT" | tail -c 400)"
fi

if [ "$AFTER_INSPECT" = "ABSENT" ] && [ "$AFTER_APP_INSPECT" = "ABSENT" ]; then
    harness_ok "4: fake release images remain absent after blocked backup" "${FAKE_AST}/${FAKE_APP} still ABSENT"
else
    harness_bad "4: fake release images remain absent after blocked backup" "ast=$AFTER_INSPECT app=$AFTER_APP_INSPECT — image was created (I4 regression)"
    docker image rm -f "$FAKE_APP" "$FAKE_AST" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# 5. secrets-lib / senma_compose_run does not build missing release image
# ---------------------------------------------------------------------------
log "==> 5: senma_compose_run with missing release image fails without building"
docker image rm -f "$FAKE_APP" "$FAKE_AST" >/dev/null 2>&1 || true
OUT="$(
  export COMPOSE="docker compose"
  export RELEASE_VERSION="$FAKE_VER"
  export SENMA_RUNTIME_MODE=bridge
  senma_compose_run --rm --no-deps -T --entrypoint sh asterisk -c 'echo SHOULD_NOT_RUN' 2>&1
)" && RC=0 || RC=$?
AFTER2="$(docker image inspect "$FAKE_AST" >/dev/null 2>&1 && echo PRESENT || echo ABSENT)"
if [ "$RC" -ne 0 ] && [ "$AFTER2" = "ABSENT" ] \
   && printf '%s' "$OUT" | grep -qiE 'not available locally|release-build'; then
    harness_ok "5: senma_compose_run fail-closed" "rc=$RC image still ABSENT"
else
    harness_bad "5: senma_compose_run fail-closed" "rc=$RC after=$AFTER2 out=$OUT"
    docker image rm -f "$FAKE_APP" "$FAKE_AST" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# 6. Positive path: backup with present :dev images still works
# ---------------------------------------------------------------------------
log "==> 6: backup succeeds when required images are present (dev)"
if docker image inspect senma-asterisk:dev >/dev/null 2>&1 \
   && docker image inspect senma-app:dev >/dev/null 2>&1; then
    TMP_OK="$(mktemp -d)"
    harness_register_best_effort_cleanup "e4a backup ok dest" "rm -rf '$TMP_OK'"
    OK_OUT="$(
      unset SENMA_RUNTIME_MODE RESTORE_RUNTIME_MODE
      export RELEASE_VERSION=dev
      export SENMA_RUNTIME_MODE=bridge
      bash "$SCRIPT_DIR/backup.sh" --dest "$TMP_OK" 2>&1
    )" && OK_RC=0 || OK_RC=$?
    ARCHIVE="$(find "$TMP_OK" -maxdepth 1 -name 'senma-backup-*.tar.gz' 2>/dev/null | head -1)"
    if [ "${OK_RC:-1}" -eq 0 ] && [ -n "$ARCHIVE" ] && [ -s "$ARCHIVE" ]; then
        MODE="$(stat -c '%a' "$ARCHIVE" 2>/dev/null || stat -f '%OLp' "$ARCHIVE" 2>/dev/null || echo '?')"
        harness_ok "6: backup with present images" "archive=$(basename "$ARCHIVE") mode=$MODE"
    else
        harness_bad "6: backup with present images" "rc=${OK_RC:-?} out=$(printf '%s' "$OK_OUT" | tail -c 400)"
    fi
else
    harness_blocked "6: senma-*:dev images required for positive backup proof"
fi

# Final negative proof snapshot
FINAL="$(docker image inspect "$FAKE_AST" >/dev/null 2>&1 && echo PRESENT || echo ABSENT)"
if [ "$FINAL" = "ABSENT" ]; then
    harness_ok "negative proof: ${FAKE_AST} never created" "ABSENT before and after"
else
    harness_bad "negative proof: ${FAKE_AST} never created" "PRESENT — cleanup and investigate"
    docker image rm -f "$FAKE_AST" "$FAKE_APP" >/dev/null 2>&1 || true
fi

harness_complete
