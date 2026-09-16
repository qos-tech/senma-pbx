#!/bin/bash
#
# Shared Compose runtime topology selection (TASK-0035E5 / I8).
#
# Distinguishes data restore from runtime topology:
#   bridge  — compose.yaml alone (dev / regression)
#   host    — compose.yaml + compose.pilot.yaml (alias of compose.host.yaml;
#             Linux pilot / production)
#
# Sourced by scripts/restore.sh (and focused smokes). Callers must set
# REPO_ROOT before sourcing. This library never builds images.
#
# Public API:
#   senma_resolve_compose_runtime
#       Sets COMPOSE (unquoted-safe command words) and SENMA_RUNTIME_MODE
#       (bridge|host). Fails closed when the topology cannot be proven.
#   senma_compose_cmd_for_mode <bridge|host>
#       Prints the compose command for that mode (no side effects).
#   senma_running_network_mode <service>
#       Prints docker NetworkMode for a running compose service, or empty.
#   senma_verify_host_runtime_topology
#       Asserts app/asterisk/db are network_mode=host with no published
#       ports. Returns 0 on success, 1 with diagnostics on failure.
#   senma_verify_bridge_runtime_topology
#       Asserts app/asterisk/db are NOT host-networked. Returns 0/1.
#   senma_compose_run …
#       Operational/ephemeral `compose run` via senma_compose_run (TASK-0035E4A).
#   senma_require_local_image <repo:tag>
#       Fail closed when a release image is not present locally.
#   senma_require_release_images_if_tagged
#       When RELEASE_VERSION != dev, require senma-app/asterisk tags.

# shellcheck disable=SC2034
# (COMPOSE / SENMA_RUNTIME_MODE are intentionally exported for callers)

senma_compose_cmd_for_mode() {
    local mode="$1"
    case "$mode" in
        bridge|dev)
            printf '%s\n' "docker compose"
            ;;
        host|pilot|production)
            printf '%s\n' "docker compose -f compose.yaml -f compose.pilot.yaml"
            ;;
        *)
            echo "ERROR: unknown runtime mode '$mode' (expected bridge|host)" >&2
            return 1
            ;;
    esac
}

senma_running_network_mode() {
    local svc="$1" cid mode
    # Prefer the already-resolved COMPOSE when set; otherwise probe the
    # base project (dev/regression default). Never invent a topology.
    if [ -n "${COMPOSE:-}" ]; then
        cid="$($COMPOSE ps -q "$svc" 2>/dev/null || true)"
    else
        cid="$(docker compose ps -q "$svc" 2>/dev/null || true)"
    fi
    [ -n "$cid" ] || return 0
    mode="$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$cid" 2>/dev/null || true)"
    printf '%s\n' "$mode"
}

senma_infer_mode_from_running() {
    local app_mode ast_mode db_mode
    app_mode="$(senma_running_network_mode app)"
    ast_mode="$(senma_running_network_mode asterisk)"
    db_mode="$(senma_running_network_mode db)"

    # No running core services → cannot infer.
    if [ -z "$app_mode" ] && [ -z "$ast_mode" ] && [ -z "$db_mode" ]; then
        return 1
    fi

    # Normalize: Docker reports "host" for host networking; bridge appears
    # as a network name (e.g. mag-pbx_mag) or literal "bridge"/"default".
    _is_host() { [ "$1" = "host" ]; }

    local host_n=0 bridge_n=0
    for m in "$app_mode" "$ast_mode" "$db_mode"; do
        [ -n "$m" ] || continue
        if _is_host "$m"; then
            host_n=$((host_n + 1))
        else
            bridge_n=$((bridge_n + 1))
        fi
    done

    if [ "$host_n" -gt 0 ] && [ "$bridge_n" -gt 0 ]; then
        echo "ERROR: mixed runtime topology detected (some services host, some bridge)." >&2
        echo "  app=${app_mode:-absent} asterisk=${ast_mode:-absent} db=${db_mode:-absent}" >&2
        echo "Refuse to guess. Set SENMA_RUNTIME_MODE=host or SENMA_RUNTIME_MODE=bridge explicitly." >&2
        return 2
    fi
    if [ "$host_n" -gt 0 ]; then
        printf '%s\n' "host"
        return 0
    fi
    if [ "$bridge_n" -gt 0 ]; then
        printf '%s\n' "bridge"
        return 0
    fi
    return 1
}

senma_resolve_compose_runtime() {
    local mode="" explicit="" inferred="" rv
    rv="${RELEASE_VERSION:-dev}"

    # 1) Explicit operator/test override (authoritative).
    explicit="${SENMA_RUNTIME_MODE:-${RESTORE_RUNTIME_MODE:-}}"
    case "$explicit" in
        host|pilot|production) mode="host" ;;
        bridge|dev) mode="bridge" ;;
        "") ;;
        *)
            echo "ERROR: invalid SENMA_RUNTIME_MODE='$explicit' (use host|bridge)." >&2
            return 1
            ;;
    esac

    # 2) Explicit COMPOSE_FILES from Makefile/pilot operator session.
    if [ -z "$mode" ] && [ -n "${COMPOSE_FILES:-}" ]; then
        case " ${COMPOSE_FILES} " in
            *" compose.pilot.yaml "*|*" compose.host.yaml "*) mode="host" ;;
            *)
                # Non-empty COMPOSE_FILES without host overlay → treat as
                # custom bridge-shaped compose; still build command from it.
                mode="bridge"
                COMPOSE="${COMPOSE:-docker compose} ${COMPOSE_FILES}"
                COMPOSE="$(printf '%s' "$COMPOSE" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
                SENMA_RUNTIME_MODE="bridge"
                export COMPOSE SENMA_RUNTIME_MODE
                echo "SENMA runtime topology: bridge (from COMPOSE_FILES=${COMPOSE_FILES})"
                return 0
                ;;
        esac
    fi

    # 3) SMOKE_COMPOSE already carries file flags (tests / advanced ops).
    if [ -z "$mode" ] && [ -n "${SMOKE_COMPOSE:-}" ]; then
        case " ${SMOKE_COMPOSE} " in
            *" compose.pilot.yaml "*|*" compose.host.yaml "*) mode="host" ;;
            *)
                # Bare "docker compose" or other bridge-shaped override.
                COMPOSE="$SMOKE_COMPOSE"
                SENMA_RUNTIME_MODE="bridge"
                export COMPOSE SENMA_RUNTIME_MODE
                echo "SENMA runtime topology: bridge (from SMOKE_COMPOSE)"
                return 0
                ;;
        esac
    fi

    # 4) RELEASE_VERSION policy BEFORE inference from running containers.
    #    A pilot operator session keeps RELEASE_VERSION exported (runbook).
    #    That must win even if a prior broken restore left bridge containers
    #    running -- otherwise I8 would self-perpetuate.
    if [ -z "$mode" ]; then
        if [ -n "$rv" ] && [ "$rv" != "dev" ]; then
            mode="host"
        fi
    fi

    # 5) Infer from currently running containers (pre-wipe evidence).
    if [ -z "$mode" ]; then
        inferred="$(senma_infer_mode_from_running)" || {
            local rc=$?
            if [ "$rc" = "2" ]; then
                return 1
            fi
            inferred=""
        }
        [ -n "$inferred" ] && mode="$inferred"
    fi

    # 6) Dev default: bridge only when clearly a :dev session.
    if [ -z "$mode" ]; then
        if [ "$rv" = "dev" ] || [ -z "$rv" ]; then
            mode="bridge"
        fi
    fi

    # 7) Fail closed — never invent bridge for an ambiguous production case.
    if [ -z "$mode" ]; then
        echo "ERROR: cannot determine restore runtime topology (TASK-0035E5 / I8)." >&2
        echo "Set one of:" >&2
        echo "  export SENMA_RUNTIME_MODE=host     # pilot/production Linux (compose.pilot.yaml)" >&2
        echo "  export SENMA_RUNTIME_MODE=bridge   # dev/regression (compose.yaml)" >&2
        echo "Or export COMPOSE_FILES=\"-f compose.yaml -f compose.pilot.yaml\" for pilot." >&2
        echo "Refusing to silently recreate the stack on the wrong network mode." >&2
        return 1
    fi

    # Host/pilot path: refuse mutable :dev images (same class of guard as
    # pilot-up), unless an explicit isolated-test override is set.
    if [ "$mode" = "host" ]; then
        if [ -z "$rv" ] || [ "$rv" = "dev" ]; then
            if [ "${SENMA_ALLOW_HOST_DEV:-}" = "1" ]; then
                echo "WARNING: host restore with RELEASE_VERSION=dev (SENMA_ALLOW_HOST_DEV=1) -- test/fixture only, never a real pilot." >&2
            else
                echo "ERROR: host/pilot restore requires RELEASE_VERSION != dev (got '${rv:-empty}')." >&2
                echo "export RELEASE_VERSION=vX.Y.Z to match the active release images, or" >&2
                echo "export SENMA_RUNTIME_MODE=bridge for a deliberate :dev/bridge restore." >&2
                return 1
            fi
        else
            if ! docker image inspect "senma-app:${rv}" >/dev/null 2>&1 \
                || ! docker image inspect "senma-asterisk:${rv}" >/dev/null 2>&1; then
                echo "ERROR: senma-app:${rv} / senma-asterisk:${rv} not found locally." >&2
                echo "Run 'make release-build VERSION=${rv}' first -- restore never builds images." >&2
                return 1
            fi
        fi
    fi

    COMPOSE="$(senma_compose_cmd_for_mode "$mode")" || return 1
    # Prefer an already-qualified SMOKE_COMPOSE / COMPOSE_FILES host command.
    if [ "$mode" = "host" ] && [ -n "${SMOKE_COMPOSE:-}" ]; then
        case " ${SMOKE_COMPOSE} " in
            *" compose.pilot.yaml "*|*" compose.host.yaml "*)
                COMPOSE="$SMOKE_COMPOSE"
                ;;
        esac
    fi
    if [ "$mode" = "host" ] && [ -n "${COMPOSE_FILES:-}" ]; then
        case " ${COMPOSE_FILES} " in
            *" compose.pilot.yaml "*|*" compose.host.yaml "*)
                COMPOSE="docker compose ${COMPOSE_FILES}"
                COMPOSE="$(printf '%s' "$COMPOSE" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
                ;;
        esac
    fi

    SENMA_RUNTIME_MODE="$mode"
    export COMPOSE SENMA_RUNTIME_MODE
    echo "SENMA runtime topology: ${SENMA_RUNTIME_MODE} (COMPOSE=${COMPOSE})"
    return 0
}

senma_verify_host_runtime_topology() {
    local svc cid mode ports fail=0
    for svc in app asterisk db; do
        cid="$($COMPOSE ps -q "$svc" 2>/dev/null || true)"
        if [ -z "$cid" ]; then
            echo "ERROR: $svc not running after restore — cannot verify host topology" >&2
            fail=1
            continue
        fi
        mode="$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$cid" 2>/dev/null || true)"
        if [ "$mode" != "host" ]; then
            echo "ERROR: $svc NetworkMode='$mode' (expected host) — pilot topology lost (I8)" >&2
            fail=1
        fi
        ports="$(docker inspect -f '{{json .HostConfig.PortBindings}}' "$cid" 2>/dev/null || true)"
        if [ -n "$ports" ] && [ "$ports" != "null" ] && [ "$ports" != "{}" ]; then
            echo "ERROR: $svc has unexpected PortBindings=$ports under host networking" >&2
            fail=1
        fi
    done
    return "$fail"
}

senma_verify_bridge_runtime_topology() {
    local svc cid mode fail=0
    for svc in app asterisk db; do
        cid="$($COMPOSE ps -q "$svc" 2>/dev/null || true)"
        if [ -z "$cid" ]; then
            echo "ERROR: $svc not running after restore — cannot verify bridge topology" >&2
            fail=1
            continue
        fi
        mode="$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$cid" 2>/dev/null || true)"
        if [ "$mode" = "host" ]; then
            echo "ERROR: $svc NetworkMode=host but restore selected bridge" >&2
            fail=1
        fi
    done
    return "$fail"
}

# =========================================================================
# TASK-0035E4A — operational compose-run immutability
# =========================================================================
#
# Real-pilot trigger (E7): `bash scripts/backup.sh` with
# RELEASE_VERSION=v0.1.0-rc.7 while the release image was absent locally.
# Bare `docker compose run` then pulled (failed) and implicitly built
# `senma-asterisk:v0.1.0-rc.7` with revision=unknown.
# That violates I4 / release immutability.
#
# Platform note (Compose 2.40.x): `docker compose run` has NO `--no-build`
# flag (unlike `up`). When a service declares `build:` and the named
# `image:` is missing locally, `run` still builds by default — even with
# `--pull never`. Operational immutability is therefore enforced by:
#   1. fail-closed local image preflight (required), and
#   2. `--pull never` (defense-in-depth against pull).
#
# Contract:
#   Operational/runtime compose run MUST go through senma_compose_run.
#   Missing required image MUST fail closed (never build/pull/fallback).
#   Only `make release-build VERSION=...` may create release-tagged images.

senma_require_local_image() {
    local image="$1"
    if [ -z "$image" ]; then
        echo "ERROR: senma_require_local_image: image argument required" >&2
        return 1
    fi
    if docker image inspect "$image" >/dev/null 2>&1; then
        return 0
    fi
    local ver="${image##*:}"
    echo "ERROR: required image ${image} is not available locally." >&2
    if [ "$ver" = "dev" ]; then
        echo "Build the development images first with:" >&2
        echo "  make ensure-dev-stack" >&2
    else
        echo "Build the exact release first with:" >&2
        echo "  make release-build VERSION=${ver}" >&2
    fi
    echo "Operational commands never build or pull release images (TASK-0035E4A / I4)." >&2
    return 1
}

# Both SENMA images for the active RELEASE_VERSION (default :dev) must
# already exist locally before any operational compose-run.
senma_require_runtime_images() {
    local rv="${RELEASE_VERSION:-dev}"
    if [ -z "$rv" ]; then
        rv=dev
    fi
    senma_require_local_image "senma-app:${rv}" || return 1
    senma_require_local_image "senma-asterisk:${rv}" || return 1
    return 0
}

# Back-compat alias used by backup preflight naming in TASK-0035E4A.
senma_require_release_images_if_tagged() {
    local rv="${RELEASE_VERSION:-dev}"
    if [ -z "$rv" ] || [ "$rv" = "dev" ]; then
        return 0
    fi
    senma_require_runtime_images
}

# Operational ephemeral container helper. Never allows Compose to build
# or pull a missing image: preflight local tags, then `run --pull never`.
# Callers must set COMPOSE first (resolve via senma_resolve_compose_runtime
# or an explicit operator override). Remaining args are forwarded to
# `compose run` after --pull never (e.g. --rm --no-deps -T --entrypoint …).
senma_compose_run() {
    if [ -z "${COMPOSE:-}" ]; then
        echo "ERROR: senma_compose_run: COMPOSE is not set" >&2
        return 1
    fi
    # Fail closed before Compose can attempt pull→build fallback.
    senma_require_runtime_images || return 1
    # shellcheck disable=SC2086
    $COMPOSE run --pull never "$@"
}

SENMA_COMPOSE_RUNTIME_LOADED=1
