#!/bin/bash
# TASK-0034I focused regression: proves the System Status ("Inspector",
# /index.php/inspector, resources.xml resource id "inspector") dependency
# checks reflect the real, current SENMA runtime after this task's fixes
# (snep/inspectors/{AGI,Permissions,PHPExtensions}.php, the
# mag-asterisk-var app-container mount, and the Asterisk-side MOH/sounds
# provisioning in docker/asterisk-entrypoint.sh). See docs/tasks/
# 0034i-system-status-dependency-runtime-resource-closure.md.
#
# Reuses this repo's own established local-dev credential-reset
# convention (scripts/smoke-test.sh's TEST_PASSWORD -- the seeded `admin`
# row starts locked behind docker/bootstrap-admin.php's one-time-rotation
# sentinel and has no otherwise-known password; every existing stateful
# smoke script that needs an authenticated admin session resets it the
# same way, e.g. scripts/authorization-smoke-test.sh's identical
# ADMIN_PASSWORD). Local Docker development only.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

BASE_URL="${SYSTEM_STATUS_SMOKE_BASE_URL:-http://127.0.0.1:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
COMPOSE="${SMOKE_COMPOSE:-docker compose}"
ADMIN_USER=admin
ADMIN_PASSWORD="SmokeTest123!"
DB_USER="${DB_USER:-snep}"
DB_PASSWORD="${DB_PASSWORD:-change-me-for-local-development}"
DB_NAME="${DB_NAME:-snep}"

TMPDIR_STATUS="$(mktemp -d)"
harness_register_best_effort_cleanup "temp working dir" "rm -rf '$TMPDIR_STATUS'"
JAR="$TMPDIR_STATUS/admin.cookies"
BODY="$TMPDIR_STATUS/body"
HEADERS="$TMPDIR_STATUS/headers"

request() {
    local method="$1" path="$2" data="${3:-}"
    if [ "$method" = POST ]; then
        curl -sS -b "$JAR" -c "$JAR" -D "$HEADERS" -o "$BODY" -w '%{http_code}' -d "$data" "$BASE_URL$path"
    else
        curl -sS -b "$JAR" -c "$JAR" -D "$HEADERS" -o "$BODY" -w '%{http_code}' "$BASE_URL$path"
    fi
}

# Every currently-registered inspectors/*.php getTestName() label, so a
# genuine regression (a check silently disappearing, e.g. a future
# php.ini fatal in one inspector class aborting Snep_Inspector's whole
# scandir() loop) is caught, not just "no red panel visible".
EXPECTED_PANELS=(
    "Environment for AGI SNEP"
    "Log Files"
    "Extension PHP"
    "File Permissions"
    "Music on Hold class"
)

echo '==> Preflight'
harness_require_containers app asterisk db

echo '==> Resetting the local dev admin password to the known smoke-test value'
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${ADMIN_PASSWORD}');" | tr -d '\r\n')"
if [ -z "$TEST_HASH" ]; then
    harness_blocked "could not compute the admin test password hash via the app container"
fi
$COMPOSE exec -T db mariadb -u"${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" \
    -e "UPDATE users SET password='${TEST_HASH}' WHERE name='${ADMIN_USER}';" >/dev/null 2>&1 \
    || harness_blocked "could not reset the admin test password via the db container"

echo '==> Anonymous access is denied (forwarded to login, no status content)'
code="$(request GET /index.php/inspector)"
if [ "$code" = 200 ] && grep -q 'SNEP - Login' "$BODY" && ! grep -qi 'panel-green\|panel-red' "$BODY"; then
    harness_ok 'anonymous access denied' "HTTP $code, login page rendered, no status panels"
else
    harness_bad 'anonymous access denied' "HTTP $code (expected the login page, no panel-green/panel-red content)"
fi

echo '==> Admin login'
code="$(request POST /index.php/auth/login "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}")"
if [ "$code" = 302 ]; then
    harness_ok 'admin login' "HTTP $code"
else
    harness_blocked "admin login did not return 302 (HTTP $code) -- cannot proceed without an authenticated session"
fi

echo '==> Authenticated System Status: every known check present, none red'
code="$(request GET /index.php/inspector)"
if [ "$code" != 200 ]; then
    harness_bad 'status page loads' "HTTP $code"
else
    harness_ok 'status page loads' "HTTP $code"
fi

if grep -qi 'panel-red' "$BODY"; then
    harness_bad 'no unexplained missing-dependency FAIL' "found panel-red in the authenticated response -- see $BODY"
else
    harness_ok 'no unexplained missing-dependency FAIL' 'zero panel-red blocks'
fi

missing=""
for label in "${EXPECTED_PANELS[@]}"; do
    grep -qF "$label" "$BODY" || missing="$missing|$label"
done
if [ -z "$missing" ]; then
    harness_ok 'every registered check rendered' "${#EXPECTED_PANELS[@]} panels present"
else
    harness_bad 'every registered check rendered' "missing panel(s):${missing}"
fi

echo '==> No PHP error disclosure in the response body'
if grep -qiE 'Fatal error|Stack trace|Uncaught exception|on line [0-9]+ in' "$BODY"; then
    harness_bad 'no PHP error/stack-trace disclosure' 'found a raw PHP error signature in the response body'
else
    harness_ok 'no PHP error/stack-trace disclosure' 'clean response body'
fi

echo '==> Missing-required-fixture detection (owned, isolated: the empty MOH directory this task provisions)'
# TASK-0034I: /var/lib/asterisk/moh is created fresh by this task's own
# asterisk-entrypoint.sh fix and, in a dev/regression environment, holds
# no real customer content -- renaming it away and back is a safe,
# self-contained fixture toggle, not a touch on shared production state.
MOH_HIDDEN=0
if $COMPOSE exec -T asterisk sh -c 'test -d /var/lib/asterisk/moh && mv /var/lib/asterisk/moh /var/lib/asterisk/.senma-moh-smoke-hidden'; then
    MOH_HIDDEN=1
    harness_register_cleanup "restore /var/lib/asterisk/moh" \
        "$COMPOSE exec -T asterisk sh -c 'test -d /var/lib/asterisk/.senma-moh-smoke-hidden && mv /var/lib/asterisk/.senma-moh-smoke-hidden /var/lib/asterisk/moh || true'"

    code="$(request GET /index.php/inspector)"
    if [ "$code" = 200 ] && grep -qi 'panel-red' "$BODY" && grep -qF 'Music on Hold class' "$BODY"; then
        harness_ok 'missing required resource detected' 'Music on Hold class now reports panel-red with the directory hidden'
    else
        harness_bad 'missing required resource detected' "HTTP $code, expected a red 'Music on Hold class' panel with the directory hidden"
    fi
else
    harness_blocked "could not hide /var/lib/asterisk/moh for the missing-fixture proof"
fi

if [ "$MOH_HIDDEN" = 1 ]; then
    $COMPOSE exec -T asterisk sh -c 'mv /var/lib/asterisk/.senma-moh-smoke-hidden /var/lib/asterisk/moh' \
        || harness_blocked "could not restore /var/lib/asterisk/moh after the missing-fixture proof"
    code="$(request GET /index.php/inspector)"
    if [ "$code" = 200 ] && ! grep -qi 'panel-red' "$BODY"; then
        harness_ok 'resource restoration clears the FAIL' 'status is green again after restoring the directory'
    else
        harness_bad 'resource restoration clears the FAIL' "HTTP $code, expected zero panel-red after restoring the directory"
    fi
fi

echo '==> Authorization boundary (resources.xml "inspector" resource, Snep_PermissionPlugin)'
grep -q '<resource id="inspector"' "$SCRIPT_DIR/../snep/modules/default/resources.xml" \
    && harness_ok 'inspector resource registered' 'System Status is gated by the standard ACL, not reachable by an unregistered controller' \
    || harness_bad 'inspector resource registered' 'resources.xml no longer registers the "inspector" resource id'

harness_require_containers app asterisk db

harness_complete
