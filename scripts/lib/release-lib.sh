#!/bin/bash
#
# Shared release-identity primitives (TASK-0034D, closing TASK-0034
# Finding CH-9). Sourced by scripts/release-build.sh, scripts/
# release-info.sh, and scripts/release-artifact-smoke-test.sh so none of
# them re-implements manifest parsing or image-label inspection on its
# own (see docs/tasks/0034d-release-artifact-versioning-image-provenance.md
# Phase 19's "do not duplicate full Docker inspection logic in multiple
# places").
#
# release-manifest.json is a deliberately FLAT JSON object (no nested
# objects/arrays) -- every key name is unique across the whole file
# (app_*, asterisk_*, not a shared "images.app.*"/"images.asterisk.*"
# shape). This repository's own tooling below reads it with plain
# grep/sed, not a JSON parser (no jq/python dependency is introduced for
# this -- see docs/tasks/0034d-... "REGISTRY POLICY"/build-tooling
# rationale); the flat shape is what makes that safe: a nested schema
# would need every reader to track which "image_id" key it means and
# grep would return whichever occurrence came first. Every value written
# is a known-shape token (a semver-like version, a hex git SHA, an
# RFC3339 timestamp, an "image:tag" string, or a "sha256:..." id/digest)
# -- never arbitrary/untrusted text -- so this is safe without a general
# JSON string-escaping implementation.

RELEASE_MANIFEST="${RELEASE_MANIFEST:-$REPO_ROOT/release-manifest.json}"

# manifest_get <file> <key> -- prints a string-valued field, or nothing
# if the file/key doesn't exist.
manifest_get() {
    local file="$1" key="$2"
    [ -f "$file" ] || return 1
    grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" 2>/dev/null \
        | head -1 \
        | sed -E 's/^"[^"]+"[[:space:]]*:[[:space:]]*"(.*)"$/\1/'
}

# manifest_get_bool <file> <key> -- prints "true"/"false", or nothing.
manifest_get_bool() {
    local file="$1" key="$2"
    [ -f "$file" ] || return 1
    grep -o "\"$key\"[[:space:]]*:[[:space:]]*\(true\|false\)" "$file" 2>/dev/null \
        | head -1 \
        | sed -E 's/^"[^"]+"[[:space:]]*:[[:space:]]*//'
}

# release_write_manifest <file> -- writes the flat manifest. Every value
# is passed as an already-known-safe token (see header) via the named
# variables below; callers set them before calling this.
release_write_manifest() {
    local file="$1"
    cat >"$file" <<EOF
{
  "version": "$MANIFEST_VERSION",
  "git_revision": "$MANIFEST_GIT_REVISION",
  "dirty": $MANIFEST_DIRTY,
  "build_time": "$MANIFEST_BUILD_TIMESTAMP",
  "app_repo_tag": "$MANIFEST_APP_REPO_TAG",
  "app_image_id": "$MANIFEST_APP_IMAGE_ID",
  "app_label_version": "$MANIFEST_APP_LABEL_VERSION",
  "app_label_revision": "$MANIFEST_APP_LABEL_REVISION",
  "asterisk_repo_tag": "$MANIFEST_ASTERISK_REPO_TAG",
  "asterisk_image_id": "$MANIFEST_ASTERISK_IMAGE_ID",
  "asterisk_label_version": "$MANIFEST_ASTERISK_LABEL_VERSION",
  "asterisk_label_revision": "$MANIFEST_ASTERISK_LABEL_REVISION",
  "db_image": "$MANIFEST_DB_IMAGE"
}
EOF
}

# release_image_label <image-ref-or-id> <label-name> -- prints an OCI
# label value from a built image, or nothing if the image or label is
# missing (never errors the caller -- callers classify empty as UNKNOWN,
# see scripts/release-info.sh).
release_image_label() {
    local image="$1" label="$2"
    docker image inspect "$image" --format "{{index .Config.Labels \"$label\"}}" 2>/dev/null
}

# release_image_id <image-ref-or-id> -- prints the image's own content
# id (sha256:...). This is a LOCAL content-addressable id, not a
# registry digest (this repository has no registry configured -- Phase
# 34, LOCAL_ONLY) -- honestly the strongest artifact-identity proof
# available without pushing anywhere; see docs/tasks/0034d-... "DIGEST
# CONTRACT".
release_image_id() {
    docker image inspect "$1" --format '{{.Id}}' 2>/dev/null
}

# release_container_image_id <compose-service> -- prints the image id
# the RUNNING container for this service actually uses (not the tag it
# was started from -- a tag can move, the container's own bound image id
# cannot).
release_container_image_id() {
    local svc="$1" cid
    cid="$($COMPOSE ps -q "$svc" 2>/dev/null)"
    [ -n "$cid" ] || return 1
    docker inspect "$cid" --format '{{.Image}}' 2>/dev/null
}

# release_container_repo_tag <compose-service> -- prints the repo:tag the
# running container's own image config records it started from.
release_container_repo_tag() {
    local svc="$1" cid
    cid="$($COMPOSE ps -q "$svc" 2>/dev/null)"
    [ -n "$cid" ] || return 1
    docker inspect "$cid" --format '{{.Config.Image}}' 2>/dev/null
}

# release_versions_mixed <app_version> <app_revision> <asterisk_version>
# <asterisk_revision> -- true (exit 0) if app and asterisk disagree on
# version+revision (Phase 28/45 multi-image consistency). A standalone
# function (not inlined in release-info.sh) so scripts/
# release-artifact-smoke-test.sh can exercise the exact comparison logic
# used in production with synthetic inputs, without needing two real
# containers actually built with different versions (Phase 45's own
# text: "do not leave the main dev environment mixed afterward").
release_versions_mixed() {
    [ "$1/$2" != "$3/$4" ]
}
