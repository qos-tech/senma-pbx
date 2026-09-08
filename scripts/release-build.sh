#!/bin/bash
#
# SENMA release build (TASK-0034D, closing TASK-0034 Finding CH-9).
#
# Builds the two SENMA-owned production images (app, asterisk -- never
# `provider`, the TASK-0034C dev/test-only trunk-simulator fixture, TASK-
# 0034D Phase 30) with an explicit release version, stamps both with the
# same OCI labels (org.opencontainers.image.version/.revision/.created --
# docker/app.Dockerfile, docker/asterisk.Dockerfile), self-verifies the
# labels actually landed (Phase 24/25 "build from exact commit" /
# "version propagation" proof), and records release-manifest.json -- a
# generated, gitignored build receipt, not a second source of truth (Git
# tags remain authoritative for the version identity itself -- see docs/
# tasks/0034d-release-artifact-versioning-image-provenance.md Phase 11).
#
# Usage:
#   make release-build VERSION=v1.0.0
#   make release-build VERSION=v1.0.0-rc.1 RC=1
#   make release-build VERSION=v1.0.0 ALLOW_DIRTY=1   # explicit dev override only
#
# Contract:
#   - Refuses an uncommitted-changes working tree (`git status
#     --porcelain` non-empty) unless ALLOW_DIRTY=1 is explicitly passed
#     (Phase 13) -- a real release must never be built from an unknown
#     dirty tree. ALLOW_DIRTY=1 is recorded in the manifest
#     ("dirty": true) so it can never be silently mistaken for a clean
#     release later.
#   - Without RC=1 ("formal release" mode), HEAD must be exactly the Git
#     tag named VERSION (`git describe --tags --exact-match HEAD`) --
#     Phase 4/14's "release version = annotated Git tag" contract. With
#     RC=1 ("release-candidate" mode, Phase 33), no tag is required --
#     VERSION + the current commit is an explicit, deliberate pairing.
#   - Never pushes an image anywhere (no registry is configured in this
#     repository -- Phase 34 LOCAL_ONLY/35 push separation).
#   - Never builds `provider` or touches `db` (Phase 29/30) -- both are
#     recorded in the manifest/evidence table for inventory only,
#     `provider` is entirely absent from it.
#
# Exit code: 0 on a successful, self-verified build+manifest; 1 on any
# guard failure (usage, dirty tree, version/tag mismatch, build failure,
# label self-check mismatch).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/release-lib.sh
source "$SCRIPT_DIR/lib/release-lib.sh"

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
cd "$REPO_ROOT" || { echo "ERROR: could not cd into repo root $REPO_ROOT" >&2; exit 1; }

VERSION="${VERSION:-}"
RC="${RC:-}"
ALLOW_DIRTY="${ALLOW_DIRTY:-}"

fail() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "$*"; }

[ -n "$VERSION" ] || fail "VERSION is required -- usage: make release-build VERSION=vX.Y.Z [RC=1] [ALLOW_DIRTY=1]"

# --- Phase 3: version format (SemVer, optional -rc.N prerelease) -----------
if ! printf '%s' "$VERSION" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$'; then
    fail "VERSION '$VERSION' does not match the SENMA release-version contract vX.Y.Z or vX.Y.Z-rc.N"
fi

# --- Phase 13: dirty-tree protection ---------------------------------------
DIRTY="false"
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    if [ "$ALLOW_DIRTY" = "1" ]; then
        log "WARNING: working tree has uncommitted/untracked changes -- proceeding only because ALLOW_DIRTY=1 was explicitly set. This is a development override; never use it for a real release. The manifest will record \"dirty\": true."
        DIRTY="true"
    else
        fail "working tree is not clean ($(git status --porcelain | wc -l | tr -d ' ') changed/untracked path(s)). Commit or stash first, or pass ALLOW_DIRTY=1 for an explicit development-only override (never for a real release). See 'git status --short'."
    fi
fi

GIT_COMMIT="$(git rev-parse HEAD 2>/dev/null)"
[ -n "$GIT_COMMIT" ] || fail "could not resolve HEAD via 'git rev-parse HEAD' -- is this a Git repository?"

# --- Phase 4/14: version/tag consistency -----------------------------------
if [ "$RC" = "1" ]; then
    log "RC mode (RC=1): building $VERSION from commit $GIT_COMMIT without requiring a matching Git tag (Phase 33 release-candidate contract -- explicit version + commit pairing)."
else
    TAG_AT_HEAD="$(git describe --tags --exact-match HEAD 2>/dev/null || true)"
    if [ "$TAG_AT_HEAD" != "$VERSION" ]; then
        fail "HEAD is not tagged '$VERSION' (found: '${TAG_AT_HEAD:-<no exact tag>}'). A formal release requires an annotated Git tag at HEAD matching VERSION exactly -- create it first: git tag -a $VERSION -m 'Release $VERSION', or pass RC=1 for a release-candidate build (explicit version+commit, no tag required)."
    fi
    TAG_TYPE="$(git cat-file -t "$VERSION" 2>/dev/null || true)"
    if [ "$TAG_TYPE" != "tag" ]; then
        log "WARNING: '$VERSION' is a lightweight tag, not an annotated one (Phase 4 prefers annotated tags for release identity). Proceeding -- the commit mapping is still exact."
    fi
fi

BUILD_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

log "==> Building senma-app:$VERSION and senma-asterisk:$VERSION from commit $GIT_COMMIT"
if ! RELEASE_VERSION="$VERSION" GIT_COMMIT="$GIT_COMMIT" BUILD_TIMESTAMP="$BUILD_TIMESTAMP" $COMPOSE build app asterisk; then
    fail "'docker compose build app asterisk' failed -- see build output above"
fi

# --- Phase 24/25: self-verify labels actually landed -----------------------
APP_REPO_TAG="senma-app:$VERSION"
ASTERISK_REPO_TAG="senma-asterisk:$VERSION"

APP_IMAGE_ID="$(release_image_id "$APP_REPO_TAG")"
ASTERISK_IMAGE_ID="$(release_image_id "$ASTERISK_REPO_TAG")"
[ -n "$APP_IMAGE_ID" ] || fail "built image '$APP_REPO_TAG' not found after build -- check compose.yaml's app.image: matches this script's expectation"
[ -n "$ASTERISK_IMAGE_ID" ] || fail "built image '$ASTERISK_REPO_TAG' not found after build -- check compose.yaml's asterisk.image: matches this script's expectation"

APP_LABEL_VERSION="$(release_image_label "$APP_REPO_TAG" org.opencontainers.image.version)"
APP_LABEL_REVISION="$(release_image_label "$APP_REPO_TAG" org.opencontainers.image.revision)"
ASTERISK_LABEL_VERSION="$(release_image_label "$ASTERISK_REPO_TAG" org.opencontainers.image.version)"
ASTERISK_LABEL_REVISION="$(release_image_label "$ASTERISK_REPO_TAG" org.opencontainers.image.revision)"

MISMATCH=0
for pair in \
    "app version:$APP_LABEL_VERSION:$VERSION" \
    "app revision:$APP_LABEL_REVISION:$GIT_COMMIT" \
    "asterisk version:$ASTERISK_LABEL_VERSION:$VERSION" \
    "asterisk revision:$ASTERISK_LABEL_REVISION:$GIT_COMMIT"; do
    name="${pair%%:*}"; rest="${pair#*:}"; actual="${rest%%:*}"; expected="${rest#*:}"
    if [ "$actual" != "$expected" ]; then
        echo "ERROR: label self-check failed for $name -- image label is '$actual', expected '$expected'" >&2
        MISMATCH=1
    fi
done
[ "$MISMATCH" = "0" ] || fail "one or more built images do not carry the version/commit they were built with -- this indicates a build-arg/label plumbing defect, not a release-process problem. Do not deploy these images."

# --- Phase 29: third-party db image, inventory only, never versioned.
# Read directly from compose.yaml (not `docker compose config`'s full
# merged/resolved output) -- db is not started by this script, and this
# avoids depending on the exact shape of Compose's merge output for a
# single static, hardcoded value.
DB_IMAGE="$(grep -A3 '^  db:' compose.yaml | grep -m1 'image:' | awk '{print $2}')"
DB_IMAGE="${DB_IMAGE:-unknown}"

MANIFEST_VERSION="$VERSION"
MANIFEST_GIT_REVISION="$GIT_COMMIT"
MANIFEST_DIRTY="$DIRTY"
MANIFEST_BUILD_TIMESTAMP="$BUILD_TIMESTAMP"
MANIFEST_APP_REPO_TAG="$APP_REPO_TAG"
MANIFEST_APP_IMAGE_ID="$APP_IMAGE_ID"
MANIFEST_APP_LABEL_VERSION="$APP_LABEL_VERSION"
MANIFEST_APP_LABEL_REVISION="$APP_LABEL_REVISION"
MANIFEST_ASTERISK_REPO_TAG="$ASTERISK_REPO_TAG"
MANIFEST_ASTERISK_IMAGE_ID="$ASTERISK_IMAGE_ID"
MANIFEST_ASTERISK_LABEL_VERSION="$ASTERISK_LABEL_VERSION"
MANIFEST_ASTERISK_LABEL_REVISION="$ASTERISK_LABEL_REVISION"
MANIFEST_DB_IMAGE="$DB_IMAGE"
release_write_manifest "$RELEASE_MANIFEST"

echo
echo "================================================================"
echo "SENMA release build: $VERSION"
echo "================================================================"
printf '%-10s %-24s %-16s %s\n' "SERVICE" "IMAGE" "VERSION LABEL" "IMAGE ID"
printf '%-10s %-24s %-16s %s\n' "app" "$APP_REPO_TAG" "$APP_LABEL_VERSION" "$APP_IMAGE_ID"
printf '%-10s %-24s %-16s %s\n' "asterisk" "$ASTERISK_REPO_TAG" "$ASTERISK_LABEL_VERSION" "$ASTERISK_IMAGE_ID"
printf '%-10s %-24s %-16s %s\n' "db" "$DB_IMAGE" "THIRD_PARTY" "n/a (not a SENMA release artifact)"
echo "git_revision: $GIT_COMMIT"
echo "dirty: $DIRTY"
echo "manifest: $RELEASE_MANIFEST"
echo
echo "Next: export RELEASE_VERSION=$VERSION, then 'make pilot-up' (or deploy per docs/operations/production-release-runbook.md)."
