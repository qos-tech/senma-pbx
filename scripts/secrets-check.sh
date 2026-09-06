#!/bin/bash
#
# SENMA operator-facing, non-mutating secret-consistency check (TASK-0033C).
#
# Answers exactly one question per supported rotatable credential: does
# the value currently DECLARED in `.env` match the value actually ACTIVE
# in every place that credential is persisted/consumed? Never writes to
# disk, never touches a database account, never restarts/reloads
# anything. Safe to run at any time, including as part of `make
# regression` (see scripts/secrets-consistency-smoke-test.sh).
#
# See docs/tasks/0033c-secret-rotation-contract.md for the full contract
# this implements (SECRET INVENTORY, SOURCE OF TRUTH, CONSUMER MAP,
# DRIFT MODEL).
#
# Output contract: for every (secret, consumer) pair, exactly one of
#   MATCH    -- declared value is active there right now
#   DRIFT    -- declared value differs from what's active there
#   UNKNOWN  -- could not be determined (consumer unreachable/missing)
# Never the secret value itself, on either side, in any output line.
#
# Exit code: 0 if every secret is fully MATCH, 3 if any secret shows
# DRIFT on at least one consumer (mirrors `reconcile-pjsip.php --check`'s
# own 0/3 vocabulary, TASK-0033B), 1 if any consumer could not be
# determined (UNKNOWN) or a precondition failed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/secrets-lib.sh
source "$SCRIPT_DIR/lib/secrets-lib.sh"

COMPOSE="${SMOKE_COMPOSE:-docker compose}"

slib_require_env() {
    local missing="" v
    for v in "$@"; do
        eval "[ -n \"\${$v:-}\" ]" || missing="$missing $v"
    done
    [ -z "$missing" ] || slib_die "required environment variable(s) not set:$missing (source .env first)"
}

slib_require_env DB_USER DB_PASSWORD DB_ROOT_PASSWORD AMI_USER AMI_PASSWORD
# Only `db` is a hard precondition. `app`/`asterisk` are deliberately
# NOT required here: file-based checks below reach their config through
# `docker compose run --rm --entrypoint sh` (slib_run_sh), which works
# regardless of whether the named `app`/`asterisk` container is
# currently healthy, crash-looping, or stopped -- exactly the situation
# an operator most needs this diagnostic to work in. A live check
# (AMI login) against an unreachable asterisk degrades to UNKNOWN on
# its own (see slib_ami_auth_check) rather than aborting the whole
# report.
slib_require_containers db

SETUP_CONF=/var/www/html/snep/includes/setup.conf
RES_ODBC_CONF=/etc/asterisk/res_odbc.conf
MANAGER_CONF=/etc/asterisk/manager.conf

# Extraction snippets are FIXED, non-secret shell text (grep/sed
# patterns + literal paths only) -- see slib_compare's own contract.
DB_PW_SETUP_SNIPPET='sed -n '"'"'s/^db\.password = "\(.*\)"$/\1/p'"'"' '"$SETUP_CONF"
DB_PW_ODBC_SNIPPET='sed -n '"'"'s/^password => \(.*\)$/\1/p'"'"' '"$RES_ODBC_CONF"
AMI_PW_MANAGER_SNIPPET='sed -n '"'"'s/^secret = \(.*\)$/\1/p'"'"' '"$MANAGER_CONF"' | head -1'
AMI_PW_SETUP_SNIPPET='sed -n '"'"'s/^pass_sock = "\(.*\)"$/\1/p'"'"' '"$SETUP_CONF"

ROWS=()          # "SECRET|CONSUMER|STATUS"
SECRET_STATUS=() # one aggregated STATUS per secret, same order as SECRET_NAMES
SECRET_NAMES=()

add_row() { ROWS+=("$1|$2|$3"); }

aggregate() {
    # aggregate <statuses...> -- DRIFT beats UNKNOWN beats MATCH.
    local s has_unknown=0
    for s in "$@"; do
        [ "$s" = "DRIFT" ] && { echo "DRIFT"; return; }
        [ "$s" = "UNKNOWN" ] && has_unknown=1
    done
    [ "$has_unknown" = "1" ] && { echo "UNKNOWN"; return; }
    echo "MATCH"
}

slib_log "==> DB_PASSWORD (application DB user '${DB_USER}')"
s1="$(slib_compare "$DB_PASSWORD" app "$DB_PW_SETUP_SNIPPET")"
s2="$(slib_compare "$DB_PASSWORD" asterisk "$DB_PW_ODBC_SNIPPET")"
s3="$(slib_db_user_auth_check db "$DB_USER" "$DB_PASSWORD")"
add_row "DB_PASSWORD" "setup.conf (app)" "$s1"
add_row "DB_PASSWORD" "res_odbc.conf (asterisk)" "$s2"
add_row "DB_PASSWORD" "live DB account auth" "$s3"
SECRET_NAMES+=("DB_PASSWORD"); SECRET_STATUS+=("$(aggregate "$s1" "$s2" "$s3")")

slib_log "==> DB_ROOT_PASSWORD (MariaDB root account)"
s4="$(slib_db_root_auth_check db "$DB_ROOT_PASSWORD")"
add_row "DB_ROOT_PASSWORD" "live DB root account auth" "$s4"
add_row "DB_ROOT_PASSWORD" "(no persisted file consumer -- root is never templated into a config file in this stack)" "N/A"
SECRET_NAMES+=("DB_ROOT_PASSWORD"); SECRET_STATUS+=("$(aggregate "$s4")")

slib_log "==> AMI_PASSWORD (Asterisk manager user '${AMI_USER}')"
s5="$(slib_compare "$AMI_PASSWORD" asterisk "$AMI_PW_MANAGER_SNIPPET")"
s6="$(slib_compare "$AMI_PASSWORD" app "$AMI_PW_SETUP_SNIPPET")"
s7="$(slib_ami_auth_check asterisk "$AMI_USER" "$AMI_PASSWORD")"
add_row "AMI_PASSWORD" "manager.conf (asterisk)" "$s5"
add_row "AMI_PASSWORD" "setup.conf pass_sock (app)" "$s6"
add_row "AMI_PASSWORD" "live AMI login" "$s7"
SECRET_NAMES+=("AMI_PASSWORD"); SECRET_STATUS+=("$(aggregate "$s5" "$s6" "$s7")")

echo
echo "================================================================"
printf "%-40s %-8s\n" "SECRET" "STATUS"
echo "----------------------------------------------------------------"
i=0
while [ "$i" -lt "${#SECRET_NAMES[@]}" ]; do
    printf "%-40s %-8s\n" "${SECRET_NAMES[$i]}" "${SECRET_STATUS[$i]}"
    i=$((i + 1))
done
echo "----------------------------------------------------------------"
echo "detail (secret|consumer|status):"
for r in "${ROWS[@]}"; do
    echo "  $r"
done
echo "================================================================"

OVERALL="MATCH"
for s in "${SECRET_STATUS[@]}"; do
    [ "$s" = "DRIFT" ] && OVERALL="DRIFT_DETECTED"
done
if [ "$OVERALL" != "DRIFT_DETECTED" ]; then
    for s in "${SECRET_STATUS[@]}"; do
        [ "$s" = "UNKNOWN" ] && OVERALL="UNKNOWN"
    done
fi

echo "OVERALL: $OVERALL"
echo "================================================================"

case "$OVERALL" in
    MATCH) exit 0 ;;
    DRIFT_DETECTED)
        echo "One or more declared secrets in .env do not match their active/" >&2
        echo "persisted value. Run 'make rotate-secrets' to reconcile, or revert" >&2
        echo ".env if this drift was not intended." >&2
        exit 3
        ;;
    *) exit 1 ;;
esac
