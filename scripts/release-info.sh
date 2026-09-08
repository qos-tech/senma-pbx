#!/bin/bash
#
# SENMA release identity inspection (TASK-0034D, closing TASK-0034
# Finding CH-9). Read-only -- never builds, starts, stops, or mutates
# anything. Answers, for the currently running deployment:
#   - What SENMA version is this?
#   - Which Git commit produced it?
#   - Which exact container image is running?
#   - Has the running deployment drifted from the release artifact
#     `make release-build` recorded?
#
# Reused by:
#   - `make release-info` (this script's full table output)
#   - scripts/doctor.sh's "Release artifact identity" check (--summary,
#     one line per service -- Phase 19: no second inspection
#     implementation)
#   - scripts/release-artifact-smoke-test.sh (Phase 42 regression proof)
#
# Classification per SENMA-built service (app, asterisk):
#   MATCH       release-manifest.json exists AND the running container's
#               image labels (version, revision) AND its bound image id
#               all agree with what the manifest recorded.
#   DRIFT       a manifest exists but ANY of the above disagree -- this
#               is deliberately strict: even a label-only match with a
#               different image id is reported as DRIFT, not MATCH,
#               because this repository's images are not proven
#               bit-for-bit reproducible (mutable base-image tags --
#               see docs/tasks/0034d-... "BUILD REPRODUCIBILITY
#               BOUNDARY"/"BASE IMAGE AUDIT"). A label-only comparison
#               would silently hide that gap.
#   UNKNOWN     no manifest exists yet (a plain dev build -- expected,
#               not a fault), or the running image carries no
#               org.opencontainers.image.* labels at all (Phase 27 --
#               never a crash).
#   NOT_RUNNING no container for that service right now.
#
# `db` is reported for inventory only (Phase 29): it is a third-party
# image (mariadb), never a SENMA release artifact, and is never
# classified MATCH/DRIFT/UNKNOWN.
#
# Multi-image consistency (Phase 28): if both app and asterisk resolve
# to real labels, their version+revision must agree -- disagreement is
# reported as its own MIXED_VERSION line and counts as a failure.
#
# Exit code: 0 if no SENMA-built service is DRIFT and app/asterisk are
# not MIXED_VERSION; 1 otherwise. UNKNOWN/NOT_RUNNING never fail this
# script on their own -- callers (doctor vs. a pilot operator running
# `make release-info` directly) decide how much to make of "no manifest
# yet" in their own context.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/release-lib.sh
source "$SCRIPT_DIR/lib/release-lib.sh"

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
MODE="full"
case "${1:-}" in
    --summary) MODE="summary" ;;
esac

FAIL=0

classify_service() {
    local svc="$1" repo_tag_key="$2" image_id_key="$3" label_version_key="$4" label_revision_key="$5"
    local cid actual_image_id actual_repo_tag actual_version actual_revision
    local expected_repo_tag expected_image_id expected_version expected_revision
    local state=""

    # Fields below are joined with "|" -- repo tags ("senma-app:v1.0.0")
    # and image ids ("sha256:...") both legitimately contain ":", so ":"
    # cannot be the record delimiter here; "|" never appears in any of
    # these values (Docker tags/ids) or in the detail text this function
    # writes itself.
    cid="$($COMPOSE ps -q "$svc" 2>/dev/null)"
    if [ -z "$cid" ]; then
        echo "${svc}|NOT_RUNNING||||no container for this service"
        return
    fi

    actual_image_id="$(release_container_image_id "$svc")"
    actual_repo_tag="$(release_container_repo_tag "$svc")"
    actual_version="$(release_image_label "$actual_image_id" org.opencontainers.image.version)"
    actual_revision="$(release_image_label "$actual_image_id" org.opencontainers.image.revision)"

    if [ -z "$actual_version" ] && [ -z "$actual_revision" ]; then
        echo "${svc}|UNKNOWN|${actual_repo_tag}|${actual_image_id}||no OCI image labels present"
        return
    fi

    if [ ! -f "$RELEASE_MANIFEST" ]; then
        echo "${svc}|UNKNOWN|${actual_repo_tag}|${actual_image_id}|${actual_version}/${actual_revision}|no release-manifest.json -- run 'make release-build VERSION=vX.Y.Z' to record one"
        return
    fi

    expected_repo_tag="$(manifest_get "$RELEASE_MANIFEST" "$repo_tag_key")"
    expected_image_id="$(manifest_get "$RELEASE_MANIFEST" "$image_id_key")"
    expected_version="$(manifest_get "$RELEASE_MANIFEST" "$label_version_key")"
    expected_revision="$(manifest_get "$RELEASE_MANIFEST" "$label_revision_key")"

    if [ "$actual_version" = "$expected_version" ] && [ "$actual_revision" = "$expected_revision" ] && [ "$actual_image_id" = "$expected_image_id" ]; then
        state="MATCH"
        echo "${svc}|${state}|${actual_repo_tag}|${actual_image_id}|${actual_version}/${actual_revision}|matches recorded release ${expected_repo_tag}"
    else
        state="DRIFT"
        echo "${svc}|${state}|${actual_repo_tag}|${actual_image_id}|${actual_version}/${actual_revision}|expected ${expected_repo_tag} (${expected_version}/${expected_revision}, ${expected_image_id})"
    fi
}

APP_LINE="$(classify_service app app_repo_tag app_image_id app_label_version app_label_revision)"
ASTERISK_LINE="$(classify_service asterisk asterisk_repo_tag asterisk_image_id asterisk_label_version asterisk_label_revision)"

app_state="$(printf '%s' "$APP_LINE" | cut -d'|' -f2)"
asterisk_state="$(printf '%s' "$ASTERISK_LINE" | cut -d'|' -f2)"

[ "$app_state" = "DRIFT" ] && FAIL=1
[ "$asterisk_state" = "DRIFT" ] && FAIL=1

# --- Phase 28: multi-image (app/asterisk) version/revision agreement ------
MIXED="no"
if [ "$app_state" != "NOT_RUNNING" ] && [ "$app_state" != "UNKNOWN" ] && \
   [ "$asterisk_state" != "NOT_RUNNING" ] && [ "$asterisk_state" != "UNKNOWN" ]; then
    app_v="$(printf '%s' "$APP_LINE" | cut -d'|' -f5 | cut -d/ -f1)"
    app_r="$(printf '%s' "$APP_LINE" | cut -d'|' -f5 | cut -d/ -f2)"
    asterisk_v="$(printf '%s' "$ASTERISK_LINE" | cut -d'|' -f5 | cut -d/ -f1)"
    asterisk_r="$(printf '%s' "$ASTERISK_LINE" | cut -d'|' -f5 | cut -d/ -f2)"
    if release_versions_mixed "$app_v" "$app_r" "$asterisk_v" "$asterisk_r"; then
        MIXED="yes"
        FAIL=1
    fi
fi

# --- db: third-party inventory, never SENMA-versioned ----------------------
DB_REPO_TAG="$(release_container_repo_tag db 2>/dev/null || true)"
DB_REPO_TAG="${DB_REPO_TAG:-not running}"

if [ "$MODE" = "summary" ]; then
    echo "app:${app_state}"
    echo "asterisk:${asterisk_state}"
    echo "mixed_version:${MIXED}"
    echo "db:THIRD_PARTY:${DB_REPO_TAG}"
    exit "$FAIL"
fi

echo "================================================================"
echo "SENMA release identity"
echo "================================================================"
if [ -f "$RELEASE_MANIFEST" ]; then
    echo "manifest: $RELEASE_MANIFEST"
    echo "release version: $(manifest_get "$RELEASE_MANIFEST" version)"
    echo "git revision:     $(manifest_get "$RELEASE_MANIFEST" git_revision)"
    echo "dirty build:      $(manifest_get_bool "$RELEASE_MANIFEST" dirty)"
else
    echo "manifest: none found at $RELEASE_MANIFEST -- this is a dev environment or 'make release-build' was never run"
fi
echo
printf '%-10s %-8s %-28s %s\n' "SERVICE" "STATE" "RUNNING IMAGE" "DETAIL"
for line in "$APP_LINE" "$ASTERISK_LINE"; do
    svc="$(printf '%s' "$line" | cut -d'|' -f1)"
    state="$(printf '%s' "$line" | cut -d'|' -f2)"
    repo_tag="$(printf '%s' "$line" | cut -d'|' -f3)"
    detail="$(printf '%s' "$line" | cut -d'|' -f6-)"
    printf '%-10s %-8s %-28s %s\n' "$svc" "$state" "${repo_tag:-n/a}" "${detail:-}"
done
printf '%-10s %-8s %-28s %s\n' "db" "THIRD_PARTY" "$DB_REPO_TAG" "not a SENMA release artifact (Phase 29) -- recorded for inventory only"
echo
if [ "$MIXED" = "yes" ]; then
    echo "MIXED_VERSION: app and asterisk report different version/revision -- this is a release-integrity failure (Phase 28/45), not a supported deployment state."
fi
if [ "$FAIL" = "1" ]; then
    echo "RESULT: DRIFT detected."
else
    echo "RESULT: no drift detected."
fi
exit "$FAIL"
