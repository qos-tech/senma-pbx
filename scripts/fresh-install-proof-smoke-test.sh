#!/bin/bash
# TASK-0034J (D1): genuinely isolated fresh-install proof.
#
# TASK-0034I attempted this by starting a second Compose project
# CONCURRENTLY with the primary "mag-pbx" dev stack and hit "invalid pool
# request: Pool overlaps with other one on this address space" --
# documented at the time as an unrelated conflict with other concurrent
# projects on the host. Re-investigated for this task with fresh
# evidence: compose.yaml pins the `mag`/`senma-control` networks to fixed
# subnets (172.28.0.0/16, 172.29.0.0/24 -- TASK-0005/TASK-0034F, not
# reversed here) REGARDLESS of Compose project name, so ANY second stack
# using the same compose.yaml unavoidably collides with the already-
# running primary stack's own bound subnet on the same Docker host. This
# is a deterministic self-collision, not a coincidental host-specific
# conflict with unrelated projects.
#
# Fix: docker/compose.fresh-check-override.yaml overlays two currently-
# free subnets for THIS isolated verification project only -- the
# primary stack's own compose.yaml pins are untouched. This script:
#   1. verifies those override subnets and the isolated HTTP port are
#      genuinely free on this host (BLOCKED, not a guess, if not);
#   2. brings up a brand-new Compose project (own containers, network,
#      and -- because nothing named "senma-freshcheck-*" has ever
#      existed before -- brand-new, genuinely empty named volumes);
#   3. waits for real container health (not just "created");
#   4. reuses this repo's own already-validated, SMOKE_COMPOSE-
#      parameterized focused suites against the isolated stack to prove
#      required runtime directories, ownership, System Status, and
#      backup tooling all come up correctly from nothing;
#   5. tears the isolated project down completely (containers, network,
#      volumes) on exit -- success, failure, or interruption alike.
# The primary dev stack (project "mag-pbx") is never stopped, restarted,
# or otherwise touched by this script.
#
# Deliberately NOT part of `make regression` (own heavy ~90s-plus full
# second-stack boot, same rationale as scripts/backup-restore-dr-smoke-
# -test.sh): run standalone via `make fresh-install-smoke`.
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

log() { harness_log "$@"; }

FRESH_PROJECT="senma-freshcheck-$$"
FRESH_PORT="${FRESH_INSTALL_PROOF_PORT:-18080}"
# TASK-0035E9: primary stack also publishes MAG_HTTPS_PORT (default 8443).
# Remap HTTPS for the isolated project so concurrent fresh-install proof
# does not collide on the host TLS port.
FRESH_HTTPS_PORT="${FRESH_INSTALL_PROOF_HTTPS_PORT:-18443}"
OVERRIDE_FILE="$REPO_ROOT/docker/compose.fresh-check-override.yaml"
FRESH_SUBNET_MAG="172.30.0.0/16"
FRESH_SUBNET_CONTROL="172.31.0.0/24"

log '==> Preflight: confirm genuine isolation, not just an assumption'
[ -f "$REPO_ROOT/.env" ] || harness_blocked "$REPO_ROOT/.env not found -- run 'cp .env.example .env' first (same prerequisite as 'make dev')"
[ -f "$OVERRIDE_FILE" ] || harness_blocked "$OVERRIDE_FILE missing"

for subnet in "$FRESH_SUBNET_MAG" "$FRESH_SUBNET_CONTROL"; do
    conflict=""
    for net in $(docker network ls -q); do
        hit="$(docker network inspect "$net" --format '{{range .IPAM.Config}}{{.Subnet}}
{{end}}' 2>/dev/null | grep -Fx "$subnet" || true)"
        if [ -n "$hit" ]; then
            conflict="$(docker network inspect "$net" --format '{{.Name}}' 2>/dev/null)"
            break
        fi
    done
    if [ -n "$conflict" ]; then
        harness_blocked "subnet $subnet (docker/compose.fresh-check-override.yaml) is already claimed by Docker network '$conflict' on this host -- pick a different override subnet or free that network before re-running this proof"
    fi
done
if docker ps --format '{{.Ports}}' 2>/dev/null | grep -q ":${FRESH_PORT}->"; then
    harness_blocked "host port $FRESH_PORT is already published by another container -- set FRESH_INSTALL_PROOF_PORT to a free port"
fi
if docker ps --format '{{.Ports}}' 2>/dev/null | grep -q ":${FRESH_HTTPS_PORT}->"; then
    harness_blocked "host port $FRESH_HTTPS_PORT is already published by another container -- set FRESH_INSTALL_PROOF_HTTPS_PORT to a free port"
fi
harness_ok 'preflight: isolation is genuinely free' "subnets $FRESH_SUBNET_MAG/$FRESH_SUBNET_CONTROL and ports $FRESH_PORT/$FRESH_HTTPS_PORT unclaimed on this host"

log '==> Bringing up a brand-new, isolated Compose project (fresh containers, network, volumes)'
set -a
# shellcheck source=/dev/null
. "$REPO_ROOT/.env"
set +a
export COMPOSE_PROJECT_NAME="$FRESH_PROJECT"
export MAG_HTTP_PORT="$FRESH_PORT"
export SENMA_HTTP_PORT="$FRESH_PORT"
export MAG_HTTPS_PORT="$FRESH_HTTPS_PORT"
# Note: ASTERISK_AMI_ACL_SUBNET is NOT overridden here -- app/asterisk
# load `env_file: .env` (compose.yaml), which reads the literal file on
# disk and ignores this shell's exported env entirely for that key.
# docker/compose.fresh-check-override.yaml carries an explicit
# `environment:` entry for it instead (Compose gives that precedence
# over env_file for the same key) -- see that file's own header for why.
COMPOSE="docker compose -f $REPO_ROOT/compose.yaml -f $OVERRIDE_FILE"

harness_register_cleanup "tear down isolated fresh-install project ($FRESH_PROJECT): containers, network, volumes" \
    "$COMPOSE down -v --remove-orphans >/dev/null 2>&1"

if ! $COMPOSE up -d app asterisk db >&2; then
    harness_blocked "'docker compose up' failed for the isolated fresh-install project -- see output above"
fi
harness_ok 'isolated stack created' "project=$FRESH_PROJECT port=$FRESH_PORT (app/asterisk/db only, no dev/test fixture)"

log '==> Waiting for the fresh containers to report healthy (not just created/started)'
wait_healthy() {
    local svc="$1" cid status
    cid="$($COMPOSE ps -q "$svc" 2>/dev/null)"
    [ -n "$cid" ] || return 1
    status="$(docker inspect --format '{{.State.Health.Status}}' "$cid" 2>/dev/null)"
    [ "$status" = "healthy" ]
}
for svc in db asterisk app; do
    if harness_retry 30 3 -- wait_healthy "$svc"; then
        harness_ok "$svc healthy on fresh install" "reported healthy"
    else
        harness_bad "$svc healthy on fresh install" "did not report healthy within ~90s -- check '$COMPOSE logs $svc'"
    fi
done
if [ "$_HARNESS_FAIL_COUNT" -gt 0 ]; then
    log 'one or more services never became healthy -- skipping further proof; isolated stack will still be torn down'
    harness_complete
fi

log '==> Required runtime directories / ownership / System Status clean (reuses the TASK-0034I focused suites, isolated stack)'
if SMOKE_COMPOSE="$COMPOSE" SENMA_HTTP_PORT="$FRESH_PORT" bash "$SCRIPT_DIR/system-status-runtime-smoke-test.sh" >&2; then
    harness_ok 'System Status clean on fresh install' 'system-status-runtime-smoke-test.sh PASS'
else
    harness_bad 'System Status clean on fresh install' "system-status-runtime-smoke-test.sh exit=$?"
fi

if SMOKE_COMPOSE="$COMPOSE" bash "$SCRIPT_DIR/asterisk-runtime-storage-smoke-test.sh" >&2; then
    harness_ok 'MOH/sounds directories provisioned+owned on fresh install' 'asterisk-runtime-storage-smoke-test.sh PASS'
else
    harness_bad 'MOH/sounds directories provisioned+owned on fresh install' "asterisk-runtime-storage-smoke-test.sh exit=$?"
fi

log '==> Backup tooling operational against the fresh install'
if SMOKE_COMPOSE="$COMPOSE" bash "$SCRIPT_DIR/backup-smoke-test.sh" >&2; then
    harness_ok 'backup tooling operational on fresh install' 'backup-smoke-test.sh PASS'
else
    harness_bad 'backup tooling operational on fresh install' "backup-smoke-test.sh exit=$?"
fi

harness_complete
