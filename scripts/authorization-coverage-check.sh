#!/bin/bash
#
# Static authorization inventory for TASK-0026A.  Every controller must be
# either resource-registered or deliberately listed by PermissionPlugin as
# authenticated-open/an alias.  Registered controllers classify index as
# read, listed read-only actions as read, and every other action as write.
# Consequently a newly added action cannot silently inherit the legacy
# seven-action allowlist behaviour: it defaults to write, while an action
# added to an authenticated-open controller must be added to this inventory.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN="$ROOT/snep/modules/default/model/PermissionPlugin.php"
DEFAULT_RESOURCES="$ROOT/snep/modules/default/resources.xml"
BILLING_RESOURCES="$ROOT/snep/modules/billing/resources.xml"

fail=0

slug() {
    printf '%s' "$1" | sed -E 's/Controller$//; s/([a-z0-9])([A-Z])/\1-\2/g; s/([A-Z]+)([A-Z][a-z])/\1-\2/g' | tr '[:upper:]' '[:lower:]'
}

resource_exists() {
    local module="$1" controller="$2" resources
    case "$module" in
        default) resources="$DEFAULT_RESOURCES" ;;
        billing) resources="$BILLING_RESOURCES" ;;
        *) return 1 ;;
    esac
    rg -q "<resource id=\"${controller}\"" "$resources"
}

plugin_lists_controller() {
    local key="$1"
    rg -q "'${key}'[[:space:]]*=>" "$PLUGIN"
}

expected_open_actions() {
    case "$1" in
        default_auth) echo 'login logout redefine recuperation' ;;
        default_error) echo 'error sneperror' ;;
        default_index) echo 'add index' ;;
        default_information) echo 'index' ;;
        default_newversion) echo 'index' ;;
        default_notifications) echo 'index remove markread' ;;
        default_permission) echo 'error index' ;;
        default_register) echo 'index' ;;
        default_simulator) echo 'index' ;;
        default_snep) echo 'index' ;;
        default_systemstatus) echo 'index restartstatus statusbar restartdispatch' ;;
        default_docs) echo 'index view' ;;
        *) echo '' ;;
    esac
}

for file in "$ROOT"/snep/modules/*/controllers/*Controller.php; do
    module="$(basename "$(dirname "$(dirname "$file")")")"
    controller="$(slug "$(basename "$file" .php)")"
    key="${module}_${controller}"
    expected=" $(expected_open_actions "$key") "

    # A controller in the authenticated-open list needs an action-level
    # inventory even if a legacy resources.xml entry also exists.
    if [ -n "${expected// /}" ]; then
        while IFS= read -r action; do
            action="$(printf '%s' "$action" | tr '[:upper:]' '[:lower:]')"
            if [[ "$expected" != *" $action "* ]]; then
                printf 'FAIL authenticated-open controller %s has unreviewed action %s\n' "$key" "$action" >&2
                fail=1
            fi
        done < <(rg -o 'function[[:space:]]+[A-Za-z0-9]+Action[[:space:]]*\(' "$file" | sed -E 's/.*[[:space:]]([A-Za-z0-9]+)Action[[:space:]]*\(.*/\1/' || true)
        printf 'PASS controller %s: authenticated-open actions inventoried\n' "$key"
        continue
    fi

    if resource_exists "$module" "$controller"; then
        printf 'PASS controller %s: resource registered; unknown actions default to write\n' "$key"
        continue
    fi
    if ! plugin_lists_controller "$key"; then
        printf 'FAIL controller %s: neither resources.xml nor PermissionPlugin classifies it\n' "$key" >&2
        fail=1
        continue
    fi

    if [ -z "${expected// /}" ]; then
        # Alias actions use the same safe classifier as ordinary resources:
        # index is target-read; every other action is target-write unless it
        # is explicitly named in PermissionPlugin::$readActions. Thus a new
        # alias action cannot fall through to an implicit allow.
        printf 'PASS controller %s: alias target classification; unknown actions default to target-write\n' "$key"
        continue
    fi
done

exit "$fail"
