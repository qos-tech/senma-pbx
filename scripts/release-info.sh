#!/bin/bash
#
# SENMA release identity inspection (TASK-0034D + TASK-0035E4 / I4).
# Read-only -- never builds, starts, stops, or mutates anything.
#
# Answers, for the currently running deployment:
#   - What SENMA version is this?
#   - Which Git commit produced it?
#   - Which exact container image is running?
#   - Has the running deployment drifted from the release artifact
#     `make release-build` recorded?
#
# Reused by:
#   - `make release-info` (this script's full table output)
#   - scripts/doctor.sh's "Release artifact identity" check (--summary)
#   - scripts/release-artifact-smoke-test.sh
#   - scripts/release-immutability-smoke-test.sh
#
# Classification per SENMA-built service (app, asterisk):
#   MATCH          release-manifest.json exists AND running image labels
#                  (version, revision) AND bound image id all agree with
#                  the manifest.
#   DRIFT          a manifest exists but ANY of the above disagree.
#   UNKNOWN_FATAL  required evidence is unavailable -- missing manifest,
#                  missing OCI release labels on a running SENMA image,
#                  or expected local release tag absent. TASK-0035E4:
#                  this MUST fail (never a soft "no drift detected").
#   NOT_RUNNING    no container for that service right now.
#
# `db` is reported for inventory only (THIRD_PARTY) -- never MATCH/DRIFT.
#
# Exit code: 0 only when no SENMA-built service is DRIFT or UNKNOWN_FATAL
# and app/asterisk are not MIXED_VERSION. NOT_RUNNING alone does not fail.

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

# Print one pipe-delimited record:
# svc|state|running_repo_tag|running_image_id|version/revision|detail
classify_service() {
    local svc="$1" repo_tag_key="$2" image_id_key="$3" label_version_key="$4" label_revision_key="$5"
    local cid actual_image_id actual_repo_tag actual_version actual_revision
    local expected_repo_tag expected_image_id expected_version expected_revision
    local local_tag_id=""

    cid="$($COMPOSE ps -q "$svc" 2>/dev/null)"
    if [ -z "$cid" ]; then
        echo "${svc}|NOT_RUNNING||||no container for this service"
        return
    fi

    actual_image_id="$(release_container_image_id "$svc")"
    actual_repo_tag="$(release_container_repo_tag "$svc")"
    actual_version="$(release_image_label "$actual_image_id" org.opencontainers.image.version)"
    actual_revision="$(release_image_label "$actual_image_id" org.opencontainers.image.revision)"

    if [ -z "$actual_version" ] || [ -z "$actual_revision" ]; then
        echo "${svc}|UNKNOWN_FATAL|${actual_repo_tag}|${actual_image_id}||missing OCI release labels (org.opencontainers.image.version/revision) -- not a verifiable release image"
        return
    fi

    if [ ! -f "$RELEASE_MANIFEST" ]; then
        echo "${svc}|UNKNOWN_FATAL|${actual_repo_tag}|${actual_image_id}|${actual_version}/${actual_revision}|release-manifest.json missing -- run 'make release-build VERSION=vX.Y.Z' (no false MATCH without a manifest)"
        return
    fi

    expected_repo_tag="$(manifest_get "$RELEASE_MANIFEST" "$repo_tag_key")"
    expected_image_id="$(manifest_get "$RELEASE_MANIFEST" "$image_id_key")"
    expected_version="$(manifest_get "$RELEASE_MANIFEST" "$label_version_key")"
    expected_revision="$(manifest_get "$RELEASE_MANIFEST" "$label_revision_key")"

    if [ -z "$expected_repo_tag" ] || [ -z "$expected_image_id" ] || [ -z "$expected_version" ] || [ -z "$expected_revision" ]; then
        echo "${svc}|UNKNOWN_FATAL|${actual_repo_tag}|${actual_image_id}|${actual_version}/${actual_revision}|release-manifest.json incomplete for ${svc} -- refuse false MATCH"
        return
    fi

    # Local tag presence (EXPECTED IMAGE must resolve locally for a release).
    if docker image inspect "$expected_repo_tag" >/dev/null 2>&1; then
        local_tag_id="$(release_image_id "$expected_repo_tag")"
    else
        echo "${svc}|UNKNOWN_FATAL|${actual_repo_tag}|${actual_image_id}|${actual_version}/${actual_revision}|expected image ${expected_repo_tag} not present locally -- run 'make release-build VERSION=${expected_version}' first"
        return
    fi

    if [ "$actual_version" = "$expected_version" ] && \
       [ "$actual_revision" = "$expected_revision" ] && \
       [ "$actual_image_id" = "$expected_image_id" ] && \
       [ "$local_tag_id" = "$expected_image_id" ]; then
        echo "${svc}|MATCH|${actual_repo_tag}|${actual_image_id}|${actual_version}/${actual_revision}|matches recorded release ${expected_repo_tag}"
    else
        echo "${svc}|DRIFT|${actual_repo_tag}|${actual_image_id}|${actual_version}/${actual_revision}|expected ${expected_repo_tag} (${expected_version}/${expected_revision}, ${expected_image_id}); local_tag_id=${local_tag_id}"
    fi
}

APP_LINE="$(classify_service app app_repo_tag app_image_id app_label_version app_label_revision)"
ASTERISK_LINE="$(classify_service asterisk asterisk_repo_tag asterisk_image_id asterisk_label_version asterisk_label_revision)"

app_state="$(printf '%s' "$APP_LINE" | cut -d'|' -f2)"
asterisk_state="$(printf '%s' "$ASTERISK_LINE" | cut -d'|' -f2)"

[ "$app_state" = "DRIFT" ] && FAIL=1
[ "$asterisk_state" = "DRIFT" ] && FAIL=1
[ "$app_state" = "UNKNOWN_FATAL" ] && FAIL=1
[ "$asterisk_state" = "UNKNOWN_FATAL" ] && FAIL=1

MIXED="no"
if [ "$app_state" != "NOT_RUNNING" ] && [ "$app_state" != "UNKNOWN_FATAL" ] && \
   [ "$asterisk_state" != "NOT_RUNNING" ] && [ "$asterisk_state" != "UNKNOWN_FATAL" ]; then
    app_v="$(printf '%s' "$APP_LINE" | cut -d'|' -f5 | cut -d/ -f1)"
    app_r="$(printf '%s' "$APP_LINE" | cut -d'|' -f5 | cut -d/ -f2)"
    asterisk_v="$(printf '%s' "$ASTERISK_LINE" | cut -d'|' -f5 | cut -d/ -f1)"
    asterisk_r="$(printf '%s' "$ASTERISK_LINE" | cut -d'|' -f5 | cut -d/ -f2)"
    if release_versions_mixed "$app_v" "$app_r" "$asterisk_v" "$asterisk_r"; then
        MIXED="yes"
        FAIL=1
    fi
fi

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
    echo
    echo "EXPECTED IMAGE (app):      $(manifest_get "$RELEASE_MANIFEST" app_repo_tag)  id=$(manifest_get "$RELEASE_MANIFEST" app_image_id)"
    echo "EXPECTED IMAGE (asterisk): $(manifest_get "$RELEASE_MANIFEST" asterisk_repo_tag)  id=$(manifest_get "$RELEASE_MANIFEST" asterisk_image_id)"
    echo "OCI VERSION (manifest):    app=$(manifest_get "$RELEASE_MANIFEST" app_label_version) asterisk=$(manifest_get "$RELEASE_MANIFEST" asterisk_label_version)"
    echo "OCI REVISION (manifest):   app=$(manifest_get "$RELEASE_MANIFEST" app_label_revision) asterisk=$(manifest_get "$RELEASE_MANIFEST" asterisk_label_revision)"
else
    echo "manifest: MISSING at $RELEASE_MANIFEST -- required evidence unavailable (TASK-0035E4)"
fi
echo
printf '%-10s %-14s %-28s %s\n' "SERVICE" "STATE" "RUNNING IMAGE" "DETAIL"
for line in "$APP_LINE" "$ASTERISK_LINE"; do
    svc="$(printf '%s' "$line" | cut -d'|' -f1)"
    state="$(printf '%s' "$line" | cut -d'|' -f2)"
    repo_tag="$(printf '%s' "$line" | cut -d'|' -f3)"
    image_id="$(printf '%s' "$line" | cut -d'|' -f4)"
    verrev="$(printf '%s' "$line" | cut -d'|' -f5)"
    detail="$(printf '%s' "$line" | cut -d'|' -f6-)"
    printf '%-10s %-14s %-28s %s\n' "$svc" "$state" "${repo_tag:-n/a}" "${detail:-}"
    if [ -n "$image_id" ]; then
        echo "           RUNNING IMAGE ID: ${image_id}"
    fi
    if [ -n "$verrev" ]; then
        echo "           OCI VERSION/REVISION: ${verrev}"
    fi
    if [ -n "$repo_tag" ] && docker image inspect "$repo_tag" >/dev/null 2>&1; then
        echo "           LOCAL TAG IMAGE ID: $(release_image_id "$repo_tag")"
    fi
done
printf '%-10s %-14s %-28s %s\n' "db" "THIRD_PARTY" "$DB_REPO_TAG" "not a SENMA release artifact -- inventory only"
echo
if [ "$MIXED" = "yes" ]; then
    echo "MIXED_VERSION: app and asterisk report different version/revision -- release-integrity failure."
fi
if [ "$FAIL" = "1" ]; then
    if [ "$app_state" = "UNKNOWN_FATAL" ] || [ "$asterisk_state" = "UNKNOWN_FATAL" ]; then
        echo "RESULT: UNKNOWN_FATAL -- required release evidence unavailable (refusing false MATCH)."
    else
        echo "RESULT: DRIFT detected."
    fi
else
    if [ "$app_state" = "MATCH" ] && [ "$asterisk_state" = "MATCH" ]; then
        echo "RESULT: MATCH -- running images agree with release-manifest.json."
    elif [ "$app_state" = "NOT_RUNNING" ] && [ "$asterisk_state" = "NOT_RUNNING" ]; then
        echo "RESULT: no SENMA services running (nothing to compare)."
    else
        echo "RESULT: no DRIFT/UNKNOWN_FATAL for running SENMA services."
    fi
fi
exit "$FAIL"
