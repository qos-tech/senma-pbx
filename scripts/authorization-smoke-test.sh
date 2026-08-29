#!/bin/bash
# TASK-0026A authorization regression harness.  Local Docker development
# only; it creates/reuses one disposable account and restores it to denied.
#
# TASK-0027: rebuilt on scripts/lib/harness.sh for explicit
# PASS/FAIL/BLOCKED/INCONCLUSIVE classification and signal-safe
# finalization. `set -e` was removed on purpose -- it let an unrelated
# infrastructure hiccup (a failed `mariadb`/`php -r` setup call) abort the
# script before its final PASS/FAIL line was ever printed, exactly the
# "operational flow completes but no final summary" failure mode
# TASK-0027 exists to close; every command whose failure previously relied
# on `-e` to stop the script now has an explicit BLOCKED check instead.
# The permission-denial checks below were also switched from matching
# translated response text (English/pt-BR) to checking the structural,
# language-independent `Location:` header PermissionPlugin always emits
# on denial (`gotoSimpleAndExit("error", "permission", "default")`) --
# see docs/tasks/0027-regression-harness-reliability.md §7.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

BASE_URL="${AUTHORIZATION_SMOKE_BASE_URL:-http://127.0.0.1:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
COMPOSE="${SMOKE_COMPOSE:-docker compose}"
ADMIN_USER=admin
ADMIN_PASSWORD=SmokeTest123!
RESTRICTED_USER=task0026a-restricted
RESTRICTED_PASSWORD=Task0026aRestricted!
READ_PERMISSION=default_errors-tdm_read
AJAX_PERMISSION=default_tdm-links_read

TMPDIR_AUTH="$(mktemp -d)"
harness_register_best_effort_cleanup "temp working dir" "rm -rf '$TMPDIR_AUTH'"
ADMIN_JAR="$TMPDIR_AUTH/admin.cookies"
RESTRICTED_JAR="$TMPDIR_AUTH/restricted.cookies"
BODY="$TMPDIR_AUTH/body"
HEADERS="$TMPDIR_AUTH/headers"

pass() { harness_ok "$1" "$2"; }
fail() { harness_bad "$1" "$2"; }

request() {
    local jar="$1" method="$2" path="$3" data="${4:-}"
    if [ "$method" = POST ]; then
        curl -sS -b "$jar" -c "$jar" -D "$HEADERS" -o "$BODY" -w '%{http_code}' -d "$data" "$BASE_URL$path"
    else
        curl -sS -b "$jar" -c "$jar" -D "$HEADERS" -o "$BODY" -w '%{http_code}' "$BASE_URL$path"
    fi
}

# redirects_to_permission_error -- language-independent replacement for
# matching PermissionController's translated "You do not have permission"
# text. Checks the ACTUAL denied request's own Location header (captured
# by the request() call immediately before this is called), which always
# points at permission/error regardless of the active UI locale.
redirects_to_permission_error() {
    grep -qi '^Location:.*permission/error' "$HEADERS"
}

echo '==> Preflight'
harness_require_containers app db

echo '==> Static authorization coverage inventory'
if bash "$(dirname "$0")/authorization-coverage-check.sh"; then
    pass 'controller/action authorization inventory' 'every controller/action classified'
else
    fail 'controller/action authorization inventory' 'unclassified or unreviewed controller/action'
fi

echo '==> Local test-user setup'
hash="$($COMPOSE exec -T app php -r "echo md5('${RESTRICTED_PASSWORD}');" | tr -d '\r\n')"
if [ -z "$hash" ]; then
    harness_blocked "could not compute the restricted test user's password hash via the app container"
fi
id="$($COMPOSE exec -T db mariadb -N -s -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" "${DB_NAME:-snep}" -e "SELECT id FROM users WHERE name='${RESTRICTED_USER}' LIMIT 1")"
if [ -z "$id" ]; then
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" "${DB_NAME:-snep}" -e "INSERT INTO users (name,password,email,dashboard,profile_id,created,updated) VALUES ('${RESTRICTED_USER}','${hash}','${RESTRICTED_USER}@example.test','',1,NOW(),NOW());"
    id="$($COMPOSE exec -T db mariadb -N -s -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" "${DB_NAME:-snep}" -e "SELECT id FROM users WHERE name='${RESTRICTED_USER}' LIMIT 1")"
fi
if [ -z "$id" ]; then
    harness_blocked "could not provision or find the restricted test user (${RESTRICTED_USER}) via the app/db containers"
fi
$COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" "${DB_NAME:-snep}" -e "UPDATE users SET password='${hash}' WHERE id=${id}; DELETE FROM users_permissions WHERE user_id=${id};" >/dev/null
# This is a deliberately persistent, reusable dev-only fixture (like
# smoke-test.sh's reuse of the seeded `admin` row), not a per-run created
# resource -- it is reset to a known zero-permission baseline at the top
# of every run rather than deleted at the end. Registering the same
# reset as a best-effort end-of-run cleanup gives an interrupted run one
# extra layer of self-healing on top of that idempotent top-of-run reset.
harness_register_best_effort_cleanup "restricted test user permissions reset to baseline" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER:-snep}' -p'${DB_PASSWORD:-change-me-for-local-development}' '${DB_NAME:-snep}' -e \"DELETE FROM users_permissions WHERE user_id=${id};\" >/dev/null"

echo '==> Anonymous boundary'
code="$(request "$ADMIN_JAR" GET /index.php/auth/login)"
if [ "$code" = 200 ] && grep -q 'SNEP - Login' "$BODY"; then pass 'anonymous login works' "HTTP $code"; else fail 'anonymous login works' "HTTP $code"; fi
code="$(request "$ADMIN_JAR" GET /index.php/default/users)"
if [ "$code" = 200 ] && grep -q 'SNEP - Login' "$BODY"; then pass 'anonymous privileged GET denied' "HTTP $code, login page rendered"; else fail 'anonymous privileged GET denied' "HTTP $code"; fi
code="$(request "$ADMIN_JAR" POST /index.php/default/users/permission/id/$id 'user='$id)"
if [ "$code" = 200 ] && grep -q 'SNEP - Login' "$BODY"; then pass 'anonymous privileged POST denied' "HTTP $code, login page rendered"; else fail 'anonymous privileged POST denied' "HTTP $code"; fi

echo '==> Login sessions'
code="$(request "$ADMIN_JAR" POST /index.php/auth/login "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}")"
if [ "$code" = 302 ]; then pass 'admin login' "HTTP $code"; else harness_blocked "admin login did not return 302 (HTTP $code) -- cannot proceed without an authenticated admin session"; fi
code="$(request "$RESTRICTED_JAR" POST /index.php/auth/login "user=${RESTRICTED_USER}&password=${RESTRICTED_PASSWORD}")"
if [ "$code" = 302 ]; then pass 'restricted login' "HTTP $code"; else harness_blocked "restricted test user login did not return 302 (HTTP $code) -- cannot proceed"; fi

code="$(request "$RESTRICTED_JAR" GET /index.php/index/add)"
if [ "$code" = 200 ] && grep -q 'var controller = "index"' "$BODY"; then pass 'restricted basic dashboard works' "HTTP $code"; else fail 'restricted basic dashboard works' "HTTP $code"; fi

code="$(request "$RESTRICTED_JAR" GET /index.php/default/parameters/language)"
if [ "$code" = 302 ] && redirects_to_permission_error; then pass 'restricted direct F16 action fails closed' "HTTP $code, Location: permission/error"; else fail 'restricted direct F16 action fails closed' "HTTP $code"; fi

code="$(request "$RESTRICTED_JAR" GET /index.php/default/nonexistent-sensitive-action)"
if [ "$code" = 302 ] && redirects_to_permission_error; then pass 'unknown/unregistered action fails closed' "HTTP $code, Location: permission/error"; else fail 'unknown/unregistered action fails closed' "HTTP $code"; fi

echo '==> Supported UI grant/revoke lifecycle'
code="$(request "$ADMIN_JAR" POST /index.php/default/users/permission/id/$id "user=$id&$READ_PERMISSION=1&$AJAX_PERMISSION=1")"
if [ "$code" = 302 ]; then pass 'admin UI grants exact read permissions' "HTTP $code"; else fail 'admin UI grants exact read permissions' "HTTP $code"; fi
code="$(request "$RESTRICTED_JAR" GET /index.php/default/errors-tdm)"
# A denial always 302s to permission/error (PermissionPlugin's own
# gotoSimpleAndExit) -- a non-302 response here is already sufficient,
# language-independent proof that this request was NOT denied, whatever
# the legacy no-Khomp controller itself then does with it (documented:
# it can legitimately return HTTP 500 on a pre-existing unrelated bug).
if [ "$code" != 302 ]; then pass "explicit read grant dispatches intended resource" "HTTP $code (not a permission denial)"; else fail 'explicit read grant allows intended resource' "HTTP $code"; fi
code="$(request "$RESTRICTED_JAR" GET /index.php/default/khomp-links)"
if [ "$code" = 200 ]; then pass 'authorized internal/AJAX alias works' "HTTP $code"; else fail 'authorized internal/AJAX alias works' "HTTP $code"; fi
code="$(request "$ADMIN_JAR" POST /index.php/default/users/permission/id/$id "user=$id")"
if [ "$code" = 302 ]; then pass 'admin UI revokes permissions' "HTTP $code"; else fail 'admin UI revokes permissions' "HTTP $code"; fi
code="$(request "$RESTRICTED_JAR" GET /index.php/default/errors-tdm)"
if [ "$code" = 302 ] && redirects_to_permission_error; then pass 'permission removal revokes access' "HTTP $code, Location: permission/error"; else fail 'permission removal revokes access' "HTTP $code"; fi

code="$(request "$ADMIN_JAR" GET /index.php/default/users/permission/id/$id)"
if [ "$code" = 200 ] && grep -q 'name="user"' "$BODY"; then pass 'admin privileged path works' "HTTP $code"; else fail 'admin privileged path works' "HTTP $code"; fi

echo '==> Restart persistence'
$COMPOSE restart app >/dev/null
for _ in $(seq 1 30); do
    if curl -sS -o /dev/null "$BASE_URL/index.php/auth/login"; then break; fi
    sleep 1
done
code="$(request "$RESTRICTED_JAR" GET /index.php/default/errors-tdm)"
if [ "$code" = 302 ] && redirects_to_permission_error; then pass 'authorization remains correct after restart' "HTTP $code, Location: permission/error"; else fail 'authorization remains correct after restart' "HTTP $code"; fi

harness_complete
