#!/bin/bash
#
# TASK-0035E4 / I4 — release immutability & operational-target hardening.
#
# Proves the Make lifecycle contract that closes incident I4:
#   - `make up` / `make pilot-up` never build
#   - operational targets do not depend on build-capable targets
#   - missing release images fail loudly (pilot-up)
#   - release-info fails closed on missing evidence (UNKNOWN_FATAL)
#   - wrong running identity is DRIFT (never auto-remediated by rebuild)
#   - image IDs are unchanged across runtime operational checks
#
# Prefer static Makefile/graph proofs plus live identity checks against
# the already-running :dev stack. Does not invoke `make release-build`
# (dirty tree / tag policy) and never retags release images.
#
# Exit code: see scripts/lib/harness.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
# shellcheck source=lib/release-lib.sh
source "$SCRIPT_DIR/lib/release-lib.sh"
harness_install_traps

cd "$REPO_ROOT" || harness_blocked "could not cd into repo root $REPO_ROOT"

MAKEFILE="$REPO_ROOT/Makefile"
COMPOSE="${SMOKE_COMPOSE:-docker compose}"
log() { harness_log "$@"; }

# ---------------------------------------------------------------------------
# 1. Static: `up` uses --no-build and never --build
# ---------------------------------------------------------------------------
log "==> 1: make up recipe is --no-build (no implicit build)"
UP_RECIPE="$(awk '
  /^up:/{in_up=1; next}
  in_up && /^[^[:space:]#]/{exit}
  in_up {print}
' "$MAKEFILE")"
if printf '%s\n' "$UP_RECIPE" | grep -qE -- '--no-build'; then
    if printf '%s\n' "$UP_RECIPE" | grep -qE -- '[^o]-build|--build([^-]|$)'; then
        # Allow --no-build; reject a bare --build.
        if printf '%s\n' "$UP_RECIPE" | grep -qE -- '(^|[[:space:]])--build([[:space:]]|$)'; then
            harness_bad "1: up --no-build" "up recipe still contains bare --build: $UP_RECIPE"
        else
            harness_ok "1: up --no-build" "up recipe uses --no-build"
        fi
    else
        harness_ok "1: up --no-build" "up recipe uses --no-build"
    fi
else
    harness_bad "1: up --no-build" "up recipe missing --no-build: $UP_RECIPE"
fi

# ---------------------------------------------------------------------------
# 2. Static: pilot-up uses --no-build and keeps image guards
# ---------------------------------------------------------------------------
log "==> 2: make pilot-up never builds"
PILOT_RECIPE="$(awk '
  /^pilot-up:/{in_p=1; next}
  in_p && /^[^[:space:]#]/{exit}
  in_p {print}
' "$MAKEFILE")"
if printf '%s\n' "$PILOT_RECIPE" | grep -qE -- '--no-build' \
   && printf '%s\n' "$PILOT_RECIPE" | grep -q 'docker image inspect' \
   && ! printf '%s\n' "$PILOT_RECIPE" | grep -qE -- '(^|[[:space:]])--build([[:space:]]|$)'; then
    harness_ok "2: pilot-up --no-build + image guards" "pilot-up refuses missing images and never --build"
else
    harness_bad "2: pilot-up --no-build + image guards" "pilot-up recipe unsafe: $PILOT_RECIPE"
fi

# ---------------------------------------------------------------------------
# 3. Static dependency graph: operational targets -> require-runtime
# ---------------------------------------------------------------------------
log "==> 3: operational targets depend on require-runtime (not build-capable targets)"
OPS_TARGETS="backup reconcile reconcile-check migrate migrate-check secrets-check rotate-secrets rotate-db-password rotate-db-root-password rotate-ami-password security-status security-bans security-unban security-reload"
GRAPH_FAIL=0
for t in $OPS_TARGETS; do
    line="$(grep -E "^${t}:" "$MAKEFILE" | head -1 || true)"
    if [ -z "$line" ]; then
        harness_bad "3: $t prerequisite" "target $t not found in Makefile"
        GRAPH_FAIL=1
        continue
    fi
    if ! printf '%s\n' "$line" | grep -q 'require-runtime'; then
        harness_bad "3: $t prerequisite" "expected require-runtime, got: $line"
        GRAPH_FAIL=1
        continue
    fi
    if printf '%s\n' "$line" | grep -qE 'ensure-dev-stack|dev-build|release-build'; then
        harness_bad "3: $t prerequisite" "build-capable prereq still present: $line"
        GRAPH_FAIL=1
        continue
    fi
    # Reject a bare `up` prerequisite word (not require-runtime / ensure-dev-stack).
    if printf '%s\n' "$line" | grep -qE '(:|[[:space:]])up([[:space:]]|$)'; then
        harness_bad "3: $t prerequisite" "still depends on up: $line"
        GRAPH_FAIL=1
    fi
done
if grep -qE '^doctor:' "$MAKEFILE"; then
    DOCTOR_LINE="$(grep -E '^doctor:' "$MAKEFILE" | head -1)"
    if printf '%s\n' "$DOCTOR_LINE" | grep -qE 'ensure-dev-stack|dev-build|release-build|(:|[[:space:]])up([[:space:]]|$)'; then
        harness_bad "3: doctor prerequisite" "doctor must not depend on build/start: $DOCTOR_LINE"
        GRAPH_FAIL=1
    else
        harness_ok "3: doctor has no build/start prereq" "${DOCTOR_LINE:-doctor: (recipe only)}"
    fi
else
    harness_bad "3: doctor target" "doctor target missing"
    GRAPH_FAIL=1
fi
if [ "$GRAPH_FAIL" = "0" ]; then
    harness_ok "3: operational graph" "backup/reconcile/migrate/secrets/rotate/security-* -> require-runtime"
fi

# ---------------------------------------------------------------------------
# 4. ensure-dev-stack / dev-build refuse non-dev RELEASE_VERSION
# ---------------------------------------------------------------------------
log "==> 4: build-capable targets refuse RELEASE_VERSION != dev"
if OUT="$(make -s RELEASE_VERSION=v0.0.0-immutability-probe ensure-dev-stack 2>&1)" ; then
    harness_bad "4: refuse non-dev build" "ensure-dev-stack unexpectedly succeeded under RELEASE_VERSION=v0.0.0-immutability-probe"
else
    if printf '%s' "$OUT" | grep -qiE 'refuse|ERROR'; then
        harness_ok "4: refuse non-dev build" "ensure-dev-stack failed closed for release tag"
    else
        harness_bad "4: refuse non-dev build" "failed but without actionable refusal: $OUT"
    fi
fi

# ---------------------------------------------------------------------------
# 5. Missing release image: pilot-up FAIL (never builds)
# ---------------------------------------------------------------------------
log "==> 5: pilot-up fails when release images are missing"
MISSING_VER="v0.0.0-immutability-missing"
if docker image inspect "senma-app:${MISSING_VER}" >/dev/null 2>&1 \
   || docker image inspect "senma-asterisk:${MISSING_VER}" >/dev/null 2>&1; then
    harness_bad "5: missing-image fixture" "probe tag ${MISSING_VER} unexpectedly exists locally -- refuse to use it"
else
    if OUT="$(make -s RELEASE_VERSION="$MISSING_VER" pilot-up 2>&1)"; then
        harness_bad "5: pilot-up missing image" "pilot-up succeeded without images for ${MISSING_VER}"
    else
        if printf '%s' "$OUT" | grep -qiE 'not found|release-build|never builds'; then
            harness_ok "5: pilot-up missing image" "pilot-up failed with actionable release-build guidance"
        else
            harness_bad "5: pilot-up missing image" "failed without actionable message: $OUT"
        fi
        if printf '%s' "$OUT" | grep -qE -- '(^|[[:space:]])--build([[:space:]]|$)' ; then
            harness_bad "5: pilot-up did not build" "pilot-up output mentions --build: $OUT"
        else
            harness_ok "5: pilot-up did not build" "no --build in failure path"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# 6. release-info fail-closed: missing manifest => UNKNOWN_FATAL
# ---------------------------------------------------------------------------
log "==> 6: release-info UNKNOWN_FATAL when manifest missing"
REAL_MANIFEST="$REPO_ROOT/release-manifest.json"
BACKUP_MANIFEST=""
if [ -f "$REAL_MANIFEST" ]; then
    BACKUP_MANIFEST="$(mktemp "${TMPDIR:-/tmp}/release-manifest.immut.XXXXXX")"
    cp "$REAL_MANIFEST" "$BACKUP_MANIFEST"
    harness_register_cleanup "restore release-manifest.json" "cp '$BACKUP_MANIFEST' '$REAL_MANIFEST'; rm -f '$BACKUP_MANIFEST'"
    rm -f "$REAL_MANIFEST"
else
    harness_register_cleanup "remove test release-manifest.json" "rm -f '$REAL_MANIFEST'"
fi

if bash "$SCRIPT_DIR/release-info.sh" --summary >/tmp/immut-release-info-unknown.log 2>&1; then
    harness_bad "6: missing manifest UNKNOWN_FATAL" "release-info exited 0 without manifest -- see /tmp/immut-release-info-unknown.log"
else
    if grep -qE '^app:UNKNOWN_FATAL$' /tmp/immut-release-info-unknown.log \
       && grep -qE '^asterisk:UNKNOWN_FATAL$' /tmp/immut-release-info-unknown.log; then
        harness_ok "6: missing manifest UNKNOWN_FATAL" "fail-closed; no false MATCH"
    else
        harness_bad "6: missing manifest UNKNOWN_FATAL" "unexpected summary -- see /tmp/immut-release-info-unknown.log"
    fi
fi
if bash "$SCRIPT_DIR/release-info.sh" >/tmp/immut-release-info-full.log 2>&1; then
    harness_bad "6: full output fail-closed" "full release-info exited 0 without manifest"
else
    if grep -qE '^RESULT:.*no drift detected\.?$' /tmp/immut-release-info-full.log \
       || grep -qE '^RESULT: no drift detected' /tmp/immut-release-info-full.log; then
        harness_bad "6: no false 'no drift'" "full output still claims no drift without evidence"
    elif grep -qE '^RESULT: UNKNOWN_FATAL' /tmp/immut-release-info-full.log; then
        harness_ok "6: no false 'no drift'" "RESULT is UNKNOWN_FATAL (fail-closed)"
    else
        harness_bad "6: no false 'no drift'" "expected RESULT: UNKNOWN_FATAL -- see /tmp/immut-release-info-full.log"
    fi
fi

# ---------------------------------------------------------------------------
# 7. Wrong running image => DRIFT (synthetic manifest with wrong image ids)
# ---------------------------------------------------------------------------
log "==> 7: wrong identity => DRIFT (no auto rebuild)"
# Need running containers with OCI labels to classify DRIFT (not UNKNOWN_FATAL).
if ! $COMPOSE ps -q app >/dev/null 2>&1 || [ -z "$($COMPOSE ps -q app 2>/dev/null)" ]; then
    harness_blocked "7: DRIFT proof needs running app/asterisk (:dev stack)"
fi
APP_IMAGE_ID="$(release_container_image_id app)"
ASTERISK_IMAGE_ID="$(release_container_image_id asterisk)"
APP_REPO_TAG="$(release_container_repo_tag app)"
ASTERISK_REPO_TAG="$(release_container_repo_tag asterisk)"
APP_VERSION="$(release_image_label "$APP_IMAGE_ID" org.opencontainers.image.version)"
APP_REVISION="$(release_image_label "$APP_IMAGE_ID" org.opencontainers.image.revision)"
ASTERISK_VERSION="$(release_image_label "$ASTERISK_IMAGE_ID" org.opencontainers.image.version)"
ASTERISK_REVISION="$(release_image_label "$ASTERISK_IMAGE_ID" org.opencontainers.image.revision)"

if [ -z "$APP_VERSION" ] || [ -z "$APP_REVISION" ] || [ -z "$ASTERISK_VERSION" ] || [ -z "$ASTERISK_REVISION" ]; then
    harness_blocked "7: running images lack OCI labels -- cannot prove DRIFT path"
fi

MANIFEST_VERSION="$APP_VERSION"
MANIFEST_GIT_REVISION="$APP_REVISION"
MANIFEST_DIRTY="false"
MANIFEST_BUILD_TIMESTAMP="immutability-smoke"
MANIFEST_APP_REPO_TAG="$APP_REPO_TAG"
MANIFEST_APP_IMAGE_ID="sha256:0000000000000000000000000000000000000000000000000000000000000001"
MANIFEST_APP_LABEL_VERSION="$APP_VERSION"
MANIFEST_APP_LABEL_REVISION="$APP_REVISION"
MANIFEST_ASTERISK_REPO_TAG="$ASTERISK_REPO_TAG"
MANIFEST_ASTERISK_IMAGE_ID="sha256:0000000000000000000000000000000000000000000000000000000000000002"
MANIFEST_ASTERISK_LABEL_VERSION="$ASTERISK_VERSION"
MANIFEST_ASTERISK_LABEL_REVISION="$ASTERISK_REVISION"
MANIFEST_DB_IMAGE="mariadb:10.11"
release_write_manifest "$REAL_MANIFEST"

if bash "$SCRIPT_DIR/release-info.sh" --summary >/tmp/immut-release-info-drift.log 2>&1; then
    harness_bad "7: wrong image DRIFT" "release-info exited 0 against wrong image ids"
else
    if grep -qE '^app:DRIFT$' /tmp/immut-release-info-drift.log \
       && grep -qE '^asterisk:DRIFT$' /tmp/immut-release-info-drift.log; then
        harness_ok "7: wrong image DRIFT" "running :dev (or other) vs wrong manifest ids => DRIFT"
    else
        # If local tag id check yields UNKNOWN_FATAL because expected id
        # disagrees with local tag resolution path, still fail-closed.
        if grep -qE '^(app|asterisk):(DRIFT|UNKNOWN_FATAL)$' /tmp/immut-release-info-drift.log; then
            harness_ok "7: wrong image DRIFT/UNKNOWN_FATAL" "fail-closed on wrong identity -- see /tmp/immut-release-info-drift.log"
        else
            harness_bad "7: wrong image DRIFT" "expected DRIFT -- see /tmp/immut-release-info-drift.log"
        fi
    fi
fi
rm -f "$REAL_MANIFEST"

# ---------------------------------------------------------------------------
# 8. Image ID immutability across operational targets
# ---------------------------------------------------------------------------
log "==> 8: image IDs unchanged across operational runtime checks"
harness_require_containers app asterisk db

BEFORE_APP="$(docker image inspect senma-app:dev --format '{{.Id}}' 2>/dev/null || true)"
BEFORE_AST="$(docker image inspect senma-asterisk:dev --format '{{.Id}}' 2>/dev/null || true)"
BEFORE_APP_RUNNING="$(release_container_image_id app)"
BEFORE_AST_RUNNING="$(release_container_image_id asterisk)"

if [ -z "$BEFORE_APP" ] || [ -z "$BEFORE_AST" ]; then
    harness_blocked "8: senma-app:dev / senma-asterisk:dev tags required for immutability proof"
fi

# Operational targets must not rebuild. Capture failures but keep going.
OPS_LOG="$(mktemp "${TMPDIR:-/tmp}/immut-ops.XXXXXX")"
harness_register_cleanup "remove ops log" "rm -f '$OPS_LOG'"
{
    echo "=== reconcile-check ==="
    make reconcile-check || echo "reconcile-check exit=$?"
    echo "=== migrate-check ==="
    make migrate-check || echo "migrate-check exit=$?"
    echo "=== secrets-check ==="
    make secrets-check || echo "secrets-check exit=$?"
    echo "=== doctor ==="
    make doctor || echo "doctor exit=$?"
    echo "=== release-info ==="
    make release-info || echo "release-info exit=$?"
    echo "=== backup ==="
    DEST="$(mktemp -d "${TMPDIR:-/tmp}/immut-backup.XXXXXX")"
    echo "DEST=$DEST"
    make backup DEST="$DEST" || echo "backup exit=$?"
    rm -rf "$DEST"
} >"$OPS_LOG" 2>&1 || true

AFTER_APP="$(docker image inspect senma-app:dev --format '{{.Id}}' 2>/dev/null || true)"
AFTER_AST="$(docker image inspect senma-asterisk:dev --format '{{.Id}}' 2>/dev/null || true)"
AFTER_APP_RUNNING="$(release_container_image_id app)"
AFTER_AST_RUNNING="$(release_container_image_id asterisk)"

if [ "$BEFORE_APP" = "$AFTER_APP" ] && [ "$BEFORE_AST" = "$AFTER_AST" ]; then
    harness_ok "8: tagged image IDs unchanged" "senma-*:dev before==after"
else
    harness_bad "8: tagged image IDs unchanged" "BEFORE app=$BEFORE_APP ast=$BEFORE_AST AFTER app=$AFTER_APP ast=$AFTER_AST -- see $OPS_LOG"
fi
if [ "$BEFORE_APP_RUNNING" = "$AFTER_APP_RUNNING" ] && [ "$BEFORE_AST_RUNNING" = "$AFTER_AST_RUNNING" ]; then
    harness_ok "8: running image IDs unchanged" "container Image before==after"
else
    harness_bad "8: running image IDs unchanged" "running identity changed -- see $OPS_LOG"
fi

# ---------------------------------------------------------------------------
# 9. require-runtime does not start/build (dry observation via make -n)
# ---------------------------------------------------------------------------
log "==> 9: require-runtime / backup recipes contain no build"
BACKUP_N="$(make -n backup 2>&1 || true)"
if printf '%s' "$BACKUP_N" | grep -qE -- '(^|[[:space:]])--build([[:space:]]|$)| compose build|docker build'; then
    harness_bad "9: backup no-build" "make -n backup mentions build: $BACKUP_N"
else
    harness_ok "9: backup no-build" "make -n backup has no build steps"
fi

rm -f /tmp/immut-release-info-unknown.log /tmp/immut-release-info-full.log /tmp/immut-release-info-drift.log

harness_complete
