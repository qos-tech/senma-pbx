#!/bin/bash
#
# SENMA operator-facing secret-rotation command (TASK-0033C).
#
# Reconciles the value(s) currently DECLARED in `.env` into every place
# a supported credential is persisted/consumed, on an EXISTING
# installation (already-provisioned DB/asterisk-etc volumes, already
# generated setup.conf) -- not just a fresh one. See docs/tasks/
# 0033c-secret-rotation-contract.md for the full contract.
#
# Every secret this script touches ends in exactly one outcome:
#   ROTATED_SUCCESSFULLY -- declared value is now active everywhere
#                           (including the trivial case where it already
#                           was, and --force was not given).
#   ROTATION_REJECTED    -- a precondition or verification step failed;
#                           any change already applied in this run was
#                           rolled back to the previous coherent state.
# A secret already MATCHing (see scripts/secrets-check.sh) is skipped
# unless --force is given, and reported ROTATED_SUCCESSFULLY (nothing to
# do -- the invariant already holds).
#
# Usage:
#   scripts/rotate-secrets.sh [--only db-password,db-root-password,ami-password] [--force]
#
# Order (fixed, not selectable): db-root-password, db-password,
# ami-password -- see docs/tasks/0033c-secret-rotation-contract.md
# ROTATION ORDERING for why. DB app password rotation authenticates as
# root using the CURRENTLY DECLARED DB_ROOT_PASSWORD -- if an operator
# changes DB_PASSWORD and DB_ROOT_PASSWORD in .env in the same edit,
# root must be rotated to its new value FIRST, or db-password rotation
# would try to authenticate with a root password that isn't active yet
# and correctly reject (confirmed live during this task's own
# validation). Rotating root first costs nothing when only DB_PASSWORD
# actually changed: root's own "already current" check short-circuits
# before any prompt. AMI rotation has no dependency on either DB secret
# and stays last.
#
# Exit code: 0 if every selected secret ends ROTATED_SUCCESSFULLY, 1 if
# any ends ROTATION_REJECTED. Never reports overall success on a partial
# failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/secrets-lib.sh
source "$SCRIPT_DIR/lib/secrets-lib.sh"

COMPOSE="${SMOKE_COMPOSE:-docker compose}"

SETUP_CONF=/var/www/html/snep/includes/setup.conf
RES_ODBC_CONF=/etc/asterisk/res_odbc.conf
MANAGER_CONF=/etc/asterisk/manager.conf

ONLY="db-password,db-root-password,ami-password"
FORCE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --only) ONLY="$2"; shift 2 ;;
        --only=*) ONLY="${1#--only=}"; shift ;;
        --force) FORCE=1; shift ;;
        *) slib_die "unknown argument: $1 (usage: rotate-secrets.sh [--only LIST] [--force])" ;;
    esac
done

selected() {
    case ",$ONLY," in
        *",$1,"*) return 0 ;;
        *) return 1 ;;
    esac
}

slib_require_env() {
    local missing="" v
    for v in "$@"; do
        eval "[ -n \"\${$v:-}\" ]" || missing="$missing $v"
    done
    [ -z "$missing" ] || slib_die "required environment variable(s) not set:$missing (source .env first)"
}

slib_require_env DB_USER DB_PASSWORD DB_ROOT_PASSWORD AMI_USER AMI_PASSWORD
# Only `db` is a hard precondition -- deliberately NOT `app`/`asterisk`.
# This command's whole purpose includes recovering an installation
# where `app` or `asterisk` is CRASH-LOOPING precisely because of the
# drift being rotated away (docker/entrypoint.sh's/
# docker/asterisk-entrypoint.sh's own ROTATION_PENDING_EXPLICIT_ACTION
# fail-fast, TASK-0033C STARTUP POLICY) -- requiring those to already be
# "Up" here would make this tool unable to fix the exact situation it
# exists for. Every file-touching step below reaches `app`/`asterisk`
# through `docker compose run --rm --entrypoint sh` (slib_run_sh),
# which works regardless of the named container's current state; a
# step that genuinely needs the LIVE Asterisk process (AMI reload/
# verify, ODBC reload/verify) checks asterisk_is_up itself and brings
# it up first if it is not (see below).
slib_require_containers db

# asterisk_is_up -- true if the asterisk service's current container is
# actually healthy, not merely showing a transient "Up" status text a
# container that is about to crash-loop again can also show for a brief
# moment (confirmed live during this task's own validation: a plain
# "Up" grep raced a container that reported Up and then immediately
# re-crashed on a still-uncorrected second file, making the caller's
# subsequent `docker compose exec` fail with "cannot exec in a stopped
# container"). Checking Docker's own healthcheck state is a strictly
# stronger, already-debounced signal (compose.yaml's healthcheck has
# its own interval/retries) -- see docker-platform-engineer's own
# "running is not ready" principle.
asterisk_is_up() {
    $COMPOSE ps asterisk --format '{{.Health}}' 2>/dev/null | grep -q '^healthy$'
}

# ensure_asterisk_up <timeout_seconds> -- if asterisk isn't already
# healthy, (re)creates it (picking up whatever files were just
# corrected/templated) and polls until it reports healthy or the
# timeout elapses. Used only on the crash-loop-recovery path -- the
# normal "rotate a credential on an already-healthy installation" path
# never calls this (see asterisk_is_up guards at each call site).
ensure_asterisk_up() {
    local timeout="$1" waited=0
    if asterisk_is_up; then
        return 0
    fi
    slib_log "asterisk is not healthy -- (re)creating it with the just-corrected configuration"
    # TASK-0035E4 / I4: never rebuild release-tagged images during rotation.
    $COMPOSE up -d --no-build --no-deps asterisk >/dev/null 2>&1
    while [ "$waited" -lt "$timeout" ]; do
        asterisk_is_up && return 0
        sleep 2
        waited=$((waited + 2))
    done
    return 1
}

RESULT_NAMES=()
RESULT_STATUS=()
RESULT_DETAIL=()
record() { RESULT_NAMES+=("$1"); RESULT_STATUS+=("$2"); RESULT_DETAIL+=("$3"); }

# --- DB_PASSWORD (application DB user) --------------------------------------
rotate_db_password() {
    slib_log "==> DB_PASSWORD"
    if [ "$FORCE" != "1" ]; then
        local cur
        cur="$(slib_db_user_auth_check db "$DB_USER" "$DB_PASSWORD")"
        if [ "$cur" = "MATCH" ]; then
            record "DB_PASSWORD" "ROTATED_SUCCESSFULLY" "already current (declared value already active; use --force to re-apply anyway)"
            return 0
        fi
    fi

    if ! slib_validate_secret "$DB_PASSWORD"; then
        record "DB_PASSWORD" "ROTATION_REJECTED" "declared value fails format validation -- see stderr; no state changed"
        return 1
    fi

    local root_state
    root_state="$(slib_db_root_auth_check db "$DB_ROOT_PASSWORD")"
    if [ "$root_state" != "MATCH" ]; then
        record "DB_PASSWORD" "ROTATION_REJECTED" "DB_ROOT_PASSWORD (declared) does not currently authenticate as root -- rotate it first (make rotate-db-root-password); no state changed"
        return 1
    fi

    # Captured ONLY to support rolling the DB ACCOUNT itself back if a
    # later verification step fails (root's ALTER USER doesn't need the
    # target account's old password, but a *rollback* to it does).
    # Never printed; held in this function's local scope only. setup.conf
    # still holds the pre-rotation value at this point -- it hasn't been
    # touched yet.
    local old_db_password
    old_db_password="$(slib_remote_extract_value app 'sed -n '"'"'s/^db\.password = "\(.*\)"$/\1/p'"'"' '"$SETUP_CONF")"

    if ! slib_db_alter_user_password db "$DB_ROOT_PASSWORD" "$DB_USER" "$DB_PASSWORD"; then
        unset old_db_password
        record "DB_PASSWORD" "ROTATION_REJECTED" "ALTER USER failed (DB unavailable or rejected the statement) -- no file changed, DB account state unchanged"
        return 1
    fi

    # From here on, the DB ACCOUNT has already moved to the new password.
    # Every failure branch below must roll IT back too (not just files) to
    # restore one coherent previous state, using old_db_password captured
    # above -- never leave the account on the new value while any file
    # still says old, or vice versa.
    _rollback_db_account_and_fail() {
        local detail="$1"
        if [ -n "$old_db_password" ] && slib_db_alter_user_password db "$DB_ROOT_PASSWORD" "$DB_USER" "$old_db_password"; then
            record "DB_PASSWORD" "ROTATION_REJECTED" "$detail -- DB account rolled back to its previous password"
        else
            record "DB_PASSWORD" "ROTATION_REJECTED" "$detail -- DB ACCOUNT COULD NOT BE CONFIRMED ROLLED BACK -- DRIFT_DETECTED, run 'make secrets-check' before anything else"
        fi
        unset old_db_password
    }

    local bak_setup
    bak_setup="$(slib_remote_template_line app "$SETUP_CONF" '^db.password = ' '"db.password = \"" ENVIRON["SLIB_NEWVAL"] "\""' "$DB_PASSWORD" "www-data:www-data" "664")"
    if [ -z "$bak_setup" ]; then
        _rollback_db_account_and_fail "setup.conf could not be updated (left untouched)"
        return 1
    fi

    local bak_odbc
    bak_odbc="$(slib_remote_template_line asterisk "$RES_ODBC_CONF" '^password => ' '"password => " ENVIRON["SLIB_NEWVAL"]' "$DB_PASSWORD")"
    if [ -z "$bak_odbc" ]; then
        slib_remote_restore app "$bak_setup" "$SETUP_CONF"
        _rollback_db_account_and_fail "res_odbc.conf could not be updated (setup.conf rolled back)"
        return 1
    fi

    # Normal path (asterisk already Up with the stale credential): a
    # plain module reload picks up the corrected res_odbc.conf with no
    # restart. Recovery path (asterisk crash-looping, e.g. AMI_PASSWORD
    # was ALSO drifted): res_odbc.conf is already fixed above, so
    # bringing asterisk up now lets it pass its own coherence check and
    # boot normally -- no reload needed, it never had a stale config
    # loaded in the first place.
    if asterisk_is_up; then
        $COMPOSE exec -T asterisk asterisk -rx "module reload res_odbc.so" >/dev/null 2>&1
    else
        ensure_asterisk_up 60
    fi

    local app_ok odbc_ok
    app_ok="$(slib_db_user_auth_check db "$DB_USER" "$DB_PASSWORD")"
    sleep 1
    odbc_ok="$($COMPOSE exec -T asterisk asterisk -rx 'odbc show all' 2>&1 | grep -cE 'Number of active connections: [1-9]')"

    if [ "$app_ok" = "MATCH" ] && [ "$odbc_ok" -ge 1 ]; then
        unset old_db_password
        slib_remote_discard_backup app "$bak_setup"
        slib_remote_discard_backup asterisk "$bak_odbc"
        record "DB_PASSWORD" "ROTATED_SUCCESSFULLY" "DB account altered; setup.conf and res_odbc.conf updated; app DB auth and Asterisk ODBC connectivity verified"
        return 0
    fi

    slib_log "post-rotation verification failed (app_ok=$app_ok odbc_active=$odbc_ok) -- rolling back"
    slib_remote_restore app "$bak_setup" "$SETUP_CONF"
    slib_remote_restore asterisk "$bak_odbc" "$RES_ODBC_CONF"
    if asterisk_is_up; then
        $COMPOSE exec -T asterisk asterisk -rx "module reload res_odbc.so" >/dev/null 2>&1
    else
        ensure_asterisk_up 60
    fi
    _rollback_db_account_and_fail "post-rotation verification failed (app DB auth or Asterisk ODBC connectivity); files rolled back"
    return 1
}

# --- DB_ROOT_PASSWORD --------------------------------------------------------
rotate_db_root_password() {
    slib_log "==> DB_ROOT_PASSWORD"
    if [ "$FORCE" != "1" ]; then
        local cur
        cur="$(slib_db_root_auth_check db "$DB_ROOT_PASSWORD")"
        if [ "$cur" = "MATCH" ]; then
            record "DB_ROOT_PASSWORD" "ROTATED_SUCCESSFULLY" "already current (declared value already active; use --force to re-apply anyway)"
            return 0
        fi
    fi

    if ! slib_validate_secret "$DB_ROOT_PASSWORD"; then
        record "DB_ROOT_PASSWORD" "ROTATION_REJECTED" "declared value fails format validation -- see stderr; no state changed"
        return 1
    fi

    local current_root
    if [ -n "${ROTATE_SECRETS_CURRENT_ROOT_PASSWORD:-}" ]; then
        # Non-interactive path (used by scripts/secret-rotation-smoke-test.sh
        # only -- an operator terminal always uses the prompt below).
        current_root="$ROTATE_SECRETS_CURRENT_ROOT_PASSWORD"
    else
        echo "DB_ROOT_PASSWORD in .env differs from the currently active root credential." >&2
        echo "Rotating the root account requires authenticating with its CURRENT password" >&2
        echo "once -- it is never read from .env (.env only ever holds the DESIRED value)" >&2
        echo "and is never stored or logged." >&2
        read -r -s -p "Enter the CURRENT DB root password: " current_root
        echo >&2
    fi

    local verify_current
    verify_current="$(slib_db_root_auth_check db "$current_root")"
    unset ROTATE_SECRETS_CURRENT_ROOT_PASSWORD
    if [ "$verify_current" != "MATCH" ]; then
        unset current_root
        record "DB_ROOT_PASSWORD" "ROTATION_REJECTED" "the provided current root password did not authenticate -- no state changed"
        return 1
    fi

    if ! slib_db_alter_root_password db "$current_root" "$DB_ROOT_PASSWORD"; then
        unset current_root
        record "DB_ROOT_PASSWORD" "ROTATION_REJECTED" "ALTER USER failed -- no state changed (root@%/root@localhost update is one statement batch; MariaDB does not commit a partial ALTER USER batch on error before FLUSH PRIVILEGES)"
        return 1
    fi

    local after
    after="$(slib_db_root_auth_check db "$DB_ROOT_PASSWORD")"
    if [ "$after" = "MATCH" ]; then
        unset current_root
        record "DB_ROOT_PASSWORD" "ROTATED_SUCCESSFULLY" "root@% and root@localhost both updated; new value verified live; old value no longer authenticates"
        return 0
    fi

    slib_log "post-rotation root verification failed -- attempting to roll back to the previous root password"
    if slib_db_alter_root_password db "$DB_ROOT_PASSWORD" "$current_root"; then
        unset current_root
        record "DB_ROOT_PASSWORD" "ROTATION_REJECTED" "post-rotation verification failed -- rolled back to the previous root password successfully"
    else
        unset current_root
        record "DB_ROOT_PASSWORD" "ROTATION_REJECTED" "post-rotation verification failed AND rollback failed -- root credential state is UNKNOWN, do not assume either the old or new value works; connect manually to diagnose before any further automation runs"
    fi
    return 1
}

# --- AMI_PASSWORD -------------------------------------------------------------
rotate_ami_password() {
    slib_log "==> AMI_PASSWORD"
    if [ "$FORCE" != "1" ]; then
        local cur
        cur="$(slib_ami_auth_check asterisk "$AMI_USER" "$AMI_PASSWORD")"
        if [ "$cur" = "MATCH" ]; then
            record "AMI_PASSWORD" "ROTATED_SUCCESSFULLY" "already current (declared value already active; use --force to re-apply anyway)"
            return 0
        fi
    fi

    if ! slib_validate_secret "$AMI_PASSWORD"; then
        record "AMI_PASSWORD" "ROTATION_REJECTED" "declared value fails format validation -- see stderr; no state changed"
        return 1
    fi

    local bak_manager
    bak_manager="$(slib_remote_template_line asterisk "$MANAGER_CONF" '^secret = ' '"secret = " ENVIRON["SLIB_NEWVAL"]' "$AMI_PASSWORD")"
    if [ -z "$bak_manager" ]; then
        record "AMI_PASSWORD" "ROTATION_REJECTED" "manager.conf could not be updated -- no state changed"
        return 1
    fi

    local bak_setup
    bak_setup="$(slib_remote_template_line app "$SETUP_CONF" '^pass_sock = ' '"pass_sock = \"" ENVIRON["SLIB_NEWVAL"] "\""' "$AMI_PASSWORD" "www-data:www-data" "664")"
    if [ -z "$bak_setup" ]; then
        slib_log "setup.conf (pass_sock) templating failed -- rolling back manager.conf"
        slib_remote_restore asterisk "$bak_manager" "$MANAGER_CONF"
        record "AMI_PASSWORD" "ROTATION_REJECTED" "manager.conf was updated but setup.conf could not be (manager.conf rolled back) -- no net state change"
        return 1
    fi

    # Normal path (asterisk already Up with the stale credential):
    # `manager reload` re-reads manager.conf without restarting Asterisk
    # or affecting active calls (see docs/tasks/
    # 0033c-secret-rotation-contract.md ROTATION AND ACTIVE CALLS).
    # Recovery path (asterisk crash-looping, e.g. this same AMI_PASSWORD
    # was the reason): manager.conf is already fixed above, so bringing
    # asterisk up now lets it pass its own coherence check and boot
    # normally -- no reload needed, it never had a stale config loaded.
    if asterisk_is_up; then
        $COMPOSE exec -T asterisk asterisk -rx "manager reload" >/dev/null 2>&1
    else
        ensure_asterisk_up 60
    fi

    local new_ok
    new_ok="$(slib_ami_auth_check asterisk "$AMI_USER" "$AMI_PASSWORD")"

    if [ "$new_ok" = "MATCH" ]; then
        slib_remote_discard_backup asterisk "$bak_manager"
        slib_remote_discard_backup app "$bak_setup"
        record "AMI_PASSWORD" "ROTATED_SUCCESSFULLY" "manager.conf and setup.conf updated; AMI reloaded (non-disruptive, no Asterisk restart); new credential verified live"
        return 0
    fi

    slib_log "post-rotation AMI verification failed -- rolling back"
    slib_remote_restore asterisk "$bak_manager" "$MANAGER_CONF"
    slib_remote_restore app "$bak_setup" "$SETUP_CONF"
    if asterisk_is_up; then
        $COMPOSE exec -T asterisk asterisk -rx "manager reload" >/dev/null 2>&1
    else
        ensure_asterisk_up 60
    fi
    record "AMI_PASSWORD" "ROTATION_REJECTED" "post-rotation AMI verification failed -- rolled back to previous credential"
    return 1
}

OVERALL_RC=0
selected db-root-password  && { rotate_db_root_password   || OVERALL_RC=1; }
selected db-password       && { rotate_db_password       || OVERALL_RC=1; }
selected ami-password      && { rotate_ami_password       || OVERALL_RC=1; }

echo
echo "================================================================"
printf "%-20s %-24s %s\n" "SECRET" "OUTCOME" "DETAIL"
echo "----------------------------------------------------------------"
i=0
while [ "$i" -lt "${#RESULT_NAMES[@]}" ]; do
    printf "%-20s %-24s %s\n" "${RESULT_NAMES[$i]}" "${RESULT_STATUS[$i]}" "${RESULT_DETAIL[$i]}"
    i=$((i + 1))
done
echo "================================================================"

exit "$OVERALL_RC"
