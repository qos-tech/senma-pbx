#!/bin/bash
#
# SENMA operator-facing AMI network-ACL migration command (TASK-0034F,
# closing TASK-0034 CH-6).
#
# `manager.conf`'s AMI ACL and `setup.conf`'s `ip_sock` are both
# FIRST_BOOT_SEED files (docker/asterisk-entrypoint.sh / docker/
# entrypoint.sh template them once, from the declared ASTERISK_HOST/
# ASTERISK_AMI_ACL_SUBNET, and never touch them again on a subsequent
# boot -- see docs/tasks/0033c-secret-rotation-contract.md's own
# established precedent for this exact class of file). An installation
# provisioned BEFORE TASK-0034F already has both files populated with
# the old, broad `mag`-network values (ASTERISK_HOST=asterisk,
# ASTERISK_AMI_ACL_SUBNET=172.28.0.0/16) baked in -- updating `.env`
# alone, or even recreating the app/asterisk containers, does NOT change
# either file's actual content. This command reconciles the values
# currently DECLARED in `.env` into both files, on an EXISTING
# installation, without a destructive volume reset -- see docs/tasks/
# 0034f-production-ami-acl-scoping.md PHASE 31/MIGRATION for the full
# contract.
#
# Deliberately reuses scripts/lib/secrets-lib.sh's own
# slib_remote_template_line (atomic, backed-up, ENVIRON-only value
# passing -- never a CLI argument, never a bare `sed -i` this script
# duplicates) -- the EXACT same helper scripts/rotate-secrets.sh's own
# rotate_ami_password() already uses for manager.conf's `secret =`/
# setup.conf's `pass_sock =` lines. One generation/templating mechanism
# for every FIRST_BOOT_SEED credential/network-identity line in this
# project, not a second hand-rolled one (see this project's own
# "one generation path" rule).
#
# Usage:
#   scripts/ami-acl-migrate.sh
#
# Idempotent: if manager.conf's permit= and setup.conf's ip_sock already
# match the currently-declared ASTERISK_AMI_ACL_SUBNET/ASTERISK_HOST,
# this is a no-op that still reports success (matching
# rotate-secrets.sh's own "already current" convention) -- safe to run
# more than once, safe to run on an installation that never needed it.
#
# Exit code: 0 on success (including "already current"), 1 on rejection
# (any change already applied in this run is rolled back before exit).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/secrets-lib.sh
source "$SCRIPT_DIR/lib/secrets-lib.sh"

COMPOSE="${SMOKE_COMPOSE:-docker compose}"

SETUP_CONF=/var/www/html/snep/includes/setup.conf
MANAGER_CONF=/etc/asterisk/manager.conf

slib_require_env() {
    local missing="" v
    for v in "$@"; do
        eval "[ -n \"\${$v:-}\" ]" || missing="$missing $v"
    done
    [ -z "$missing" ] || slib_die "required environment variable(s) not set:$missing (source .env first)"
}
slib_require_env ASTERISK_HOST ASTERISK_AMI_ACL_SUBNET
slib_require_containers() {
    local svc
    for svc in "$@"; do
        $COMPOSE ps "$svc" 2>/dev/null | grep -q "Up" || slib_die "required container not Up: $svc (run 'make up' first)"
    done
}
slib_require_containers app asterisk

# TASK-0034F Phase 29: same validation asterisk-entrypoint.sh applies at
# first boot -- an existing install migrating to a new value must be
# held to the identical safety bar a fresh install already is, not a
# looser one just because this is the "existing install" path.
case "$ASTERISK_AMI_ACL_SUBNET" in
    [0-9]*.[0-9]*.[0-9]*.[0-9]*/[0-9]*) : ;;
    *) slib_die "ASTERISK_AMI_ACL_SUBNET='$ASTERISK_AMI_ACL_SUBNET' is not a valid IPv4 CIDR (expected e.g. 172.29.0.0/24)" ;;
esac
if [ "$ASTERISK_AMI_ACL_SUBNET" = "0.0.0.0/0" ] && [ "${AMI_ACL_ALLOW_UNSAFE_SUBNET:-0}" != "1" ]; then
    slib_die "ASTERISK_AMI_ACL_SUBNET=0.0.0.0/0 would permit AMI from any address -- refusing to migrate to it. Set AMI_ACL_ALLOW_UNSAFE_SUBNET=1 only for a deliberate, isolated development experiment."
fi

CURRENT_PERMIT="$(slib_run_sh asterisk "grep '^permit=' '$MANAGER_CONF' | head -1 | sed 's/^permit=//'")"
CURRENT_IP_SOCK="$(slib_run_sh app "grep '^ip_sock = ' '$SETUP_CONF' | head -1 | sed 's/^ip_sock = \"\\(.*\\)\"\$/\\1/'")"

echo "Currently configured:  manager.conf permit=${CURRENT_PERMIT:-<unreadable>}   setup.conf ip_sock=${CURRENT_IP_SOCK:-<unreadable>}"
echo "Declared in .env:      ASTERISK_AMI_ACL_SUBNET=${ASTERISK_AMI_ACL_SUBNET}   ASTERISK_HOST=${ASTERISK_HOST}"

if [ "$CURRENT_PERMIT" = "$ASTERISK_AMI_ACL_SUBNET" ] && [ "$CURRENT_IP_SOCK" = "$ASTERISK_HOST" ]; then
    echo "RESULT: ALREADY_CURRENT -- no change needed"
    exit 0
fi

# Deliberately checks "Up" (container running, docker compose exec
# available), not Docker-reported "healthy": on an existing install, the
# asterisk container is correctly UNHEALTHY right up until this exact
# migration runs -- healthcheck-asterisk.sh's own AMI self-check
# resolves via ASTERISK_HOST (the new senma-ami alias), which the
# not-yet-migrated manager.conf ACL legitimately rejects. Requiring
# "healthy" here would make this command unable to fix the one
# situation it exists for. `docker compose exec` (used below and by
# slib_run_sh/slib_ami_auth_check) only needs the container running, not
# passing its healthcheck -- confirmed live.
asterisk_is_up() {
    $COMPOSE ps asterisk --format '{{.Status}}' 2>/dev/null | grep -q '^Up'
}
if ! asterisk_is_up; then
    slib_die "asterisk container is not running -- this command only migrates an already-running installation (run 'make up' first)"
fi

BAK_MANAGER="$(slib_remote_template_line asterisk "$MANAGER_CONF" '^permit=' '"permit=" ENVIRON["SLIB_NEWVAL"]' "$ASTERISK_AMI_ACL_SUBNET")"
if [ -z "$BAK_MANAGER" ]; then
    echo "RESULT: REJECTED -- manager.conf could not be updated; no state changed" >&2
    exit 1
fi

BAK_SETUP="$(slib_remote_template_line app "$SETUP_CONF" '^ip_sock = ' '"ip_sock = \"" ENVIRON["SLIB_NEWVAL"] "\""' "$ASTERISK_HOST" "www-data:www-data" "664")"
if [ -z "$BAK_SETUP" ]; then
    echo "setup.conf (ip_sock) templating failed -- rolling back manager.conf" >&2
    slib_remote_restore asterisk "$BAK_MANAGER" "$MANAGER_CONF"
    echo "RESULT: REJECTED -- manager.conf was updated but setup.conf could not be (rolled back); no net state change" >&2
    exit 1
fi

# manager reload re-reads manager.conf's ACL without restarting Asterisk
# or affecting active calls -- same live-proven mechanism TASK-0033C's
# own AMI_PASSWORD rotation already relies on, re-verified specifically
# for the permit=/deny= lines by TASK-0034F (see that task doc's RELOAD
# BEHAVIOR section). setup.conf's ip_sock is read fresh by PHP on the
# next request -- no Apache/app restart needed (the same "no restart
# required" property TASK-0033C already established for every other
# setup.conf-templated value).
$COMPOSE exec -T asterisk asterisk -rx "manager reload" >/dev/null 2>&1

NEW_AUTH="$(slib_ami_auth_check asterisk "${AMI_USER:?AMI_USER must be set}" "${AMI_PASSWORD:?AMI_PASSWORD must be set}")"
if [ "$NEW_AUTH" = "MATCH" ]; then
    slib_remote_discard_backup asterisk "$BAK_MANAGER"
    slib_remote_discard_backup app "$BAK_SETUP"
    echo "RESULT: MIGRATED -- manager.conf permit= and setup.conf ip_sock updated; AMI reloaded (non-disruptive, no Asterisk restart); new ACL verified live via the authorized path"
    exit 0
fi

echo "post-migration AMI verification failed via the new ACL/hostname -- rolling back" >&2
slib_remote_restore asterisk "$BAK_MANAGER" "$MANAGER_CONF"
slib_remote_restore app "$BAK_SETUP" "$SETUP_CONF"
$COMPOSE exec -T asterisk asterisk -rx "manager reload" >/dev/null 2>&1
echo "RESULT: REJECTED -- post-migration AMI verification failed; rolled back to the previous ACL/hostname" >&2
exit 1
