#!/bin/bash
#
# Focused regression coverage for TASK-0034D (closing TASK-0034 Finding
# CH-9 -- release-artifact versioning/image provenance). See docs/tasks/
# 0034d-release-artifact-versioning-image-provenance.md.
#
# Included in `make regression` -- placed right after
# compose-profile-isolation-smoke (both are lightweight, non-destructive,
# Docker-identity-adjacent checks). Depends on `up` (needs the real
# app/asterisk images `up` just built, which always carry real
# GIT_COMMIT/BUILD_TIMESTAMP labels per the Makefile's own RELEASE_VERSION/
# GIT_COMMIT/BUILD_TIMESTAMP export -- see the Makefile's own header
# comment above that export) but never rebuilds, restarts, recreates, or
# mutates any container/volume itself. Every temporary file this script
# writes lives under a throwaway TMPDIR and/or is cleaned up via
# harness_register_cleanup; if a real release-manifest.json already
# exists at the repo root (a pilot operator's own, or a previous `make
# release-build` run), it is backed up and restored, never clobbered.
#
# Proves (Phase 42):
#   1. version/revision OCI label metadata is present on both the app
#      and asterisk images `up` just built, and the revision equals the
#      current HEAD commit (Phase 24/25's "self-verify" contract, proven
#      here from a second, independent reader -- not release-build.sh's
#      own self-check).
#   2. version/revision agree between the app and asterisk images (Phase
#      28 multi-image consistency, real values).
#   3. `scripts/release-build.sh` refuses an uncommitted-changes working
#      tree (Phase 13) -- fails fast, before attempting any Docker build.
#   4. `scripts/release-info.sh` reports MATCH for both services against
#      a manifest constructed from their own real, currently-running
#      values (Phase 18).
#   5. `scripts/release-info.sh` reports DRIFT for both services against
#      a manifest deliberately recording the wrong image id (Phase 26).
#   6. `scripts/release-info.sh` reports UNKNOWN_FATAL (fail-closed,
#      non-zero exit) when no release-manifest.json exists -- never a
#      soft UNKNOWN/exit-0 that can print "no drift detected" without
#      evidence (TASK-0035E4 / I4).
#   7. release_image_label() (scripts/lib/release-lib.sh), the primitive
#      release-info.sh's own label inspection is built on, returns
#      empty -- not an error -- for the third-party `db` image's absent
#      org.opencontainers.image.revision label (Phase 27/29). Note: the
#      official mariadb image DOES carry its own, unrelated
#      org.opencontainers.image.version label -- confirmed live -- so
#      this proof specifically targets .revision, the SENMA-specific
#      field db genuinely lacks, not .version.
#   8. release_versions_mixed() (Phase 28/45) correctly flags a
#      synthetic app/asterisk version disagreement and correctly clears
#      a synthetic agreement -- exercised directly with synthetic
#      inputs, deliberately NOT by building a real mismatched image pair
#      (Phase 45's own text: "do not leave the main dev environment
#      mixed afterward" -- the real MATCH/DRIFT/UNKNOWN_FATAL proofs
#      above already exercise every other part of the same code path
#      against real containers).
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
# shellcheck source=lib/release-lib.sh
source "$SCRIPT_DIR/lib/release-lib.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
log() { harness_log "$@"; }

cd "$REPO_ROOT" || harness_blocked "could not cd into repo root $REPO_ROOT"
harness_require_containers app asterisk db

REAL_MANIFEST="$REPO_ROOT/release-manifest.json"
BACKUP_MANIFEST=""
if [ -f "$REAL_MANIFEST" ]; then
    BACKUP_MANIFEST="$(mktemp "${TMPDIR:-/tmp}/release-manifest.backup.XXXXXX")"
    cp "$REAL_MANIFEST" "$BACKUP_MANIFEST"
    harness_register_cleanup "restore pre-existing release-manifest.json" "cp '$BACKUP_MANIFEST' '$REAL_MANIFEST'; rm -f '$BACKUP_MANIFEST'"
else
    harness_register_cleanup "remove test-written release-manifest.json" "rm -f '$REAL_MANIFEST'"
fi

CURRENT_HEAD="$(git rev-parse HEAD 2>/dev/null)"

# --- gather real, currently-running values ---------------------------------
APP_IMAGE_ID="$(release_container_image_id app)"
APP_REPO_TAG="$(release_container_repo_tag app)"
APP_VERSION="$(release_image_label "$APP_IMAGE_ID" org.opencontainers.image.version)"
APP_REVISION="$(release_image_label "$APP_IMAGE_ID" org.opencontainers.image.revision)"

ASTERISK_IMAGE_ID="$(release_container_image_id asterisk)"
ASTERISK_REPO_TAG="$(release_container_repo_tag asterisk)"
ASTERISK_VERSION="$(release_image_label "$ASTERISK_IMAGE_ID" org.opencontainers.image.version)"
ASTERISK_REVISION="$(release_image_label "$ASTERISK_IMAGE_ID" org.opencontainers.image.revision)"

# --- 1. label metadata present, revision == current HEAD -------------------
log "==> 1: version/revision label metadata present on app/asterisk images"
if [ -n "$APP_VERSION" ] && [ -n "$APP_REVISION" ]; then
    harness_ok "1: app labels present" "version=$APP_VERSION revision=$APP_REVISION"
else
    harness_bad "1: app labels present" "app image $APP_REPO_TAG missing version/revision labels"
fi
if [ -n "$ASTERISK_VERSION" ] && [ -n "$ASTERISK_REVISION" ]; then
    harness_ok "1: asterisk labels present" "version=$ASTERISK_VERSION revision=$ASTERISK_REVISION"
else
    harness_bad "1: asterisk labels present" "asterisk image $ASTERISK_REPO_TAG missing version/revision labels"
fi
if [ -n "$CURRENT_HEAD" ] && [ "$APP_REVISION" = "$CURRENT_HEAD" ] && [ "$ASTERISK_REVISION" = "$CURRENT_HEAD" ]; then
    harness_ok "1: revision matches current HEAD" "$CURRENT_HEAD"
else
    harness_bad "1: revision matches current HEAD" "HEAD=$CURRENT_HEAD app_revision=$APP_REVISION asterisk_revision=$ASTERISK_REVISION"
fi

# --- 2. version/revision agree between app and asterisk ---------------------
log "==> 2: app/asterisk version+revision agreement"
if [ "$APP_VERSION/$APP_REVISION" = "$ASTERISK_VERSION/$ASTERISK_REVISION" ]; then
    harness_ok "2: app/asterisk agree" "$APP_VERSION/$APP_REVISION"
else
    harness_bad "2: app/asterisk agree" "app=$APP_VERSION/$APP_REVISION asterisk=$ASTERISK_VERSION/$ASTERISK_REVISION"
fi

# --- 3. dirty-tree rejection (fast: fails before any docker build) ---------
log "==> 3: release-build.sh refuses a dirty working tree"
DIRTY_PROBE="$REPO_ROOT/.release-artifact-smoke-dirty-probe"
: >"$DIRTY_PROBE"
harness_register_cleanup "remove dirty-tree probe file" "rm -f '$DIRTY_PROBE'"
if VERSION=v0.0.0-rc.1 RC=1 ALLOW_DIRTY= bash "$SCRIPT_DIR/release-build.sh" >/tmp/release-build-dirty-probe.log 2>&1; then
    harness_bad "3: dirty tree rejected" "release-build.sh unexpectedly succeeded with an untracked file present -- see /tmp/release-build-dirty-probe.log"
else
    if grep -qi "not clean" /tmp/release-build-dirty-probe.log; then
        harness_ok "3: dirty tree rejected" "release-build.sh exited non-zero citing a non-clean working tree"
    else
        harness_bad "3: dirty tree rejected" "release-build.sh exited non-zero but not for the expected dirty-tree reason -- see /tmp/release-build-dirty-probe.log"
    fi
fi
rm -f "$DIRTY_PROBE"

# --- 4. MATCH: manifest built from the real, running values ----------------
log "==> 4: release-info.sh reports MATCH against the real running values"
MANIFEST_VERSION="$APP_VERSION"
MANIFEST_GIT_REVISION="$APP_REVISION"
MANIFEST_DIRTY="false"
MANIFEST_BUILD_TIMESTAMP="unknown"
MANIFEST_APP_REPO_TAG="$APP_REPO_TAG"
MANIFEST_APP_IMAGE_ID="$APP_IMAGE_ID"
MANIFEST_APP_LABEL_VERSION="$APP_VERSION"
MANIFEST_APP_LABEL_REVISION="$APP_REVISION"
MANIFEST_ASTERISK_REPO_TAG="$ASTERISK_REPO_TAG"
MANIFEST_ASTERISK_IMAGE_ID="$ASTERISK_IMAGE_ID"
MANIFEST_ASTERISK_LABEL_VERSION="$ASTERISK_VERSION"
MANIFEST_ASTERISK_LABEL_REVISION="$ASTERISK_REVISION"
MANIFEST_DB_IMAGE="mariadb:10.11"
release_write_manifest "$REAL_MANIFEST"

if bash "$SCRIPT_DIR/release-info.sh" --summary >/tmp/release-info-match.log 2>&1; then
    if grep -q "^app:MATCH$" /tmp/release-info-match.log && grep -q "^asterisk:MATCH$" /tmp/release-info-match.log; then
        harness_ok "4: MATCH reported" "both app and asterisk report MATCH"
    else
        harness_bad "4: MATCH reported" "expected app:MATCH and asterisk:MATCH -- see /tmp/release-info-match.log"
    fi
else
    harness_bad "4: MATCH reported" "release-info.sh exited non-zero against a manifest built from real running values -- see /tmp/release-info-match.log"
fi

# --- 5. DRIFT: manifest deliberately records the wrong image id ------------
log "==> 5: release-info.sh reports DRIFT against a deliberately wrong manifest"
MANIFEST_APP_IMAGE_ID="sha256:0000000000000000000000000000000000000000000000000000000000000000"
MANIFEST_ASTERISK_IMAGE_ID="sha256:0000000000000000000000000000000000000000000000000000000000000000"
release_write_manifest "$REAL_MANIFEST"

if bash "$SCRIPT_DIR/release-info.sh" --summary >/tmp/release-info-drift.log 2>&1; then
    harness_bad "5: DRIFT reported" "release-info.sh exited 0 (PASS) against a manifest with a deliberately wrong image id -- see /tmp/release-info-drift.log"
else
    if grep -q "^app:DRIFT$" /tmp/release-info-drift.log && grep -q "^asterisk:DRIFT$" /tmp/release-info-drift.log; then
        harness_ok "5: DRIFT reported" "both app and asterisk report DRIFT"
    else
        harness_bad "5: DRIFT reported" "expected app:DRIFT and asterisk:DRIFT -- see /tmp/release-info-drift.log"
    fi
fi

# --- 6. UNKNOWN_FATAL: no manifest at all (TASK-0035E4 fail-closed) ---------
# Soft UNKNOWN + exit 0 previously printed "RESULT: no drift detected"
# when evidence was missing -- that is unsafe. Missing manifest must now
# be UNKNOWN_FATAL with a non-zero exit (never a false MATCH/no-drift).
log "==> 6: release-info.sh reports UNKNOWN_FATAL (fail-closed) with no manifest present"
rm -f "$REAL_MANIFEST"
if bash "$SCRIPT_DIR/release-info.sh" --summary >/tmp/release-info-unknown.log 2>&1; then
    harness_bad "6: UNKNOWN_FATAL reported" "release-info.sh exited 0 with no manifest present -- missing evidence must fail closed (TASK-0035E4) -- see /tmp/release-info-unknown.log"
else
    if grep -q "^app:UNKNOWN_FATAL$" /tmp/release-info-unknown.log && grep -q "^asterisk:UNKNOWN_FATAL$" /tmp/release-info-unknown.log; then
        harness_ok "6: UNKNOWN_FATAL reported" "both app and asterisk report UNKNOWN_FATAL with no manifest; exit non-zero (no false 'no drift')"
    else
        harness_bad "6: UNKNOWN_FATAL reported" "expected app:UNKNOWN_FATAL and asterisk:UNKNOWN_FATAL -- see /tmp/release-info-unknown.log"
    fi
fi

# --- 7. release_image_label() on a real image with no SENMA revision label -
# The official mariadb image DOES carry its own
# org.opencontainers.image.version label (confirmed live: e.g.
# "10.11.19", MariaDB's own upstream version, coincidentally the same
# OCI key name) -- so "version" is the wrong field to prove this on.
# It carries no org.opencontainers.image.revision at all (that field is
# specific to this repository's own build-arg/LABEL contract,
# docker/app.Dockerfile / docker/asterisk.Dockerfile) -- a real,
# non-synthetic case of a real image missing SENMA-specific metadata,
# which is exactly what release-info.sh's own UNKNOWN classification
# depends on this primitive handling without error.
log "==> 7: release_image_label() handles a real image missing the SENMA revision label"
DB_IMAGE_ID="$(release_container_image_id db 2>/dev/null || true)"
if [ -z "$DB_IMAGE_ID" ]; then
    harness_bad "7: db image inspected" "db container is not running -- cannot exercise the missing-label case"
else
    DB_REVISION_VALUE="$(release_image_label "$DB_IMAGE_ID" org.opencontainers.image.revision)"
    DB_REVISION_RC=$?
    DB_VERSION_VALUE="$(release_image_label "$DB_IMAGE_ID" org.opencontainers.image.version)"
    if [ "$DB_REVISION_RC" = "0" ] && [ -z "$DB_REVISION_VALUE" ]; then
        harness_ok "7: missing-label case handled" "release_image_label() returned empty (not an error) for db's absent revision label; db's own foreign version label is present ('$DB_VERSION_VALUE') and correctly ignored by release-info.sh, which never classifies db against SENMA identity"
    else
        harness_bad "7: missing-label case handled" "expected empty revision with exit 0, got rc=$DB_REVISION_RC value='$DB_REVISION_VALUE'"
    fi
fi

# --- 8. release_versions_mixed() unit-style proof (Phase 28/45) ------------
log "==> 8: release_versions_mixed() detects disagreement and agreement"
if release_versions_mixed "v1.0.0" "aaa111" "v1.0.1" "aaa111"; then
    harness_ok "8: mixed version detected" "v1.0.0/aaa111 vs v1.0.1/aaa111 correctly flagged as mixed"
else
    harness_bad "8: mixed version detected" "v1.0.0/aaa111 vs v1.0.1/aaa111 was NOT flagged as mixed"
fi
if release_versions_mixed "v1.0.0" "aaa111" "v1.0.0" "aaa111"; then
    harness_bad "8: agreement not flagged" "v1.0.0/aaa111 vs itself was incorrectly flagged as mixed"
else
    harness_ok "8: agreement not flagged" "v1.0.0/aaa111 vs itself correctly not flagged as mixed"
fi

rm -f /tmp/release-build-dirty-probe.log /tmp/release-info-match.log /tmp/release-info-drift.log /tmp/release-info-unknown.log

harness_complete
