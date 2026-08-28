#!/bin/bash
# TASK-0026A authorization regression harness.  Local Docker development
# only; it creates/reuses one disposable account and restores it to denied.

set -euo pipefail

BASE_URL="${AUTHORIZATION_SMOKE_BASE_URL:-http://127.0.0.1:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
COMPOSE="${SMOKE_COMPOSE:-docker compose}"
ADMIN_USER=admin
ADMIN_PASSWORD=SmokeTest123!
RESTRICTED_USER=task0026a-restricted
RESTRICTED_PASSWORD=Task0026aRestricted!
READ_PERMISSION=default_errors-tdm_read
AJAX_PERMISSION=default_tdm-links_read

TMPDIR_AUTH="$(mktemp -d)"
ADMIN_JAR="$TMPDIR_AUTH/admin.cookies"
RESTRICTED_JAR="$TMPDIR_AUTH/restricted.cookies"
BODY="$TMPDIR_AUTH/body"
HEADERS="$TMPDIR_AUTH/headers"
cleanup() { rm -rf "$TMPDIR_AUTH"; }
trap cleanup EXIT

PASS=0
FAIL=0
row() { printf '%-44s %s\n' "$1" "$2"; }
pass() { row "$1" PASS; PASS=$((PASS + 1)); }
fail() { row "$1" "FAIL: $2"; FAIL=$((FAIL + 1)); }

request() {
    local jar="$1" method="$2" path="$3" data="${4:-}"
    if [ "$method" = POST ]; then
        curl -sS -b "$jar" -c "$jar" -D "$HEADERS" -o "$BODY" -w '%{http_code}' -d "$data" "$BASE_URL$path"
    else
        curl -sS -b "$jar" -c "$jar" -D "$HEADERS" -o "$BODY" -w '%{http_code}' "$BASE_URL$path"
    fi
}

permission_page() {
    local code
    code="$(request "$RESTRICTED_JAR" GET /index.php/permission/error)"
    [ "$code" = 200 ] && rg -qi 'You do not have permission|você não tem permissão|voce nao tem permissao' "$BODY"
}

echo '==> Static authorization coverage inventory'
if bash "$(dirname "$0")/authorization-coverage-check.sh"; then
    pass 'controller/action authorization inventory'
else
    fail 'controller/action authorization inventory' 'unclassified or unreviewed controller/action'
fi

echo '==> Local test-user setup'
hash="$($COMPOSE exec -T app php -r "echo md5('${RESTRICTED_PASSWORD}');" | tr -d '\r\n')"
id="$($COMPOSE exec -T db mariadb -N -s -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" "${DB_NAME:-snep}" -e "SELECT id FROM users WHERE name='${RESTRICTED_USER}' LIMIT 1")"
if [ -z "$id" ]; then
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" "${DB_NAME:-snep}" -e "INSERT INTO users (name,password,email,dashboard,profile_id,created,updated) VALUES ('${RESTRICTED_USER}','${hash}','${RESTRICTED_USER}@example.test','',1,NOW(),NOW());"
    id="$($COMPOSE exec -T db mariadb -N -s -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" "${DB_NAME:-snep}" -e "SELECT id FROM users WHERE name='${RESTRICTED_USER}' LIMIT 1")"
fi
$COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" "${DB_NAME:-snep}" -e "UPDATE users SET password='${hash}' WHERE id=${id}; DELETE FROM users_permissions WHERE user_id=${id};" >/dev/null

echo '==> Anonymous boundary'
code="$(request "$ADMIN_JAR" GET /index.php/auth/login)"
if [ "$code" = 200 ] && rg -q 'SNEP - Login' "$BODY"; then pass 'anonymous login works'; else fail 'anonymous login works' "HTTP $code"; fi
code="$(request "$ADMIN_JAR" GET /index.php/default/users)"
if [ "$code" = 200 ] && rg -q 'SNEP - Login' "$BODY"; then pass 'anonymous privileged GET denied'; else fail 'anonymous privileged GET denied' "HTTP $code"; fi
code="$(request "$ADMIN_JAR" POST /index.php/default/users/permission/id/$id 'user='$id)"
if [ "$code" = 200 ] && rg -q 'SNEP - Login' "$BODY"; then pass 'anonymous privileged POST denied'; else fail 'anonymous privileged POST denied' "HTTP $code"; fi

echo '==> Login sessions'
code="$(request "$ADMIN_JAR" POST /index.php/auth/login "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}")"
if [ "$code" = 302 ]; then pass 'admin login'; else fail 'admin login' "HTTP $code"; fi
code="$(request "$RESTRICTED_JAR" POST /index.php/auth/login "user=${RESTRICTED_USER}&password=${RESTRICTED_PASSWORD}")"
if [ "$code" = 302 ]; then pass 'restricted login'; else fail 'restricted login' "HTTP $code"; fi

code="$(request "$RESTRICTED_JAR" GET /index.php/index/add)"
if [ "$code" = 200 ] && rg -q 'var controller = "index"' "$BODY"; then pass 'restricted basic dashboard works'; else fail 'restricted basic dashboard works' "HTTP $code"; fi

code="$(request "$RESTRICTED_JAR" GET /index.php/default/parameters/language)"
if [ "$code" = 302 ] && permission_page; then pass 'restricted direct F16 action fails closed'; else fail 'restricted direct F16 action fails closed' "HTTP $code"; fi

code="$(request "$RESTRICTED_JAR" GET /index.php/default/nonexistent-sensitive-action)"
if [ "$code" = 302 ] && permission_page; then pass 'unknown/unregistered action fails closed'; else fail 'unknown/unregistered action fails closed' "HTTP $code"; fi

echo '==> Supported UI grant/revoke lifecycle'
code="$(request "$ADMIN_JAR" POST /index.php/default/users/permission/id/$id "user=$id&$READ_PERMISSION=1&$AJAX_PERMISSION=1")"
if [ "$code" = 302 ]; then pass 'admin UI grants exact read permissions'; else fail 'admin UI grants exact read permissions' "HTTP $code"; fi
code="$(request "$RESTRICTED_JAR" GET /index.php/default/errors-tdm)"
if [ "$code" != 302 ] && ! rg -qi 'You do not have permission|você não tem permissão|voce nao tem permissao' "$BODY"; then pass "explicit read grant dispatches intended resource (HTTP $code)"; else fail 'explicit read grant allows intended resource' "HTTP $code"; fi
code="$(request "$RESTRICTED_JAR" GET /index.php/default/khomp-links)"
if [ "$code" = 200 ] && ! rg -qi 'You do not have permission|você não tem permissão|voce nao tem permissao' "$BODY"; then pass 'authorized internal/AJAX alias works'; else fail 'authorized internal/AJAX alias works' "HTTP $code"; fi
code="$(request "$ADMIN_JAR" POST /index.php/default/users/permission/id/$id "user=$id")"
if [ "$code" = 302 ]; then pass 'admin UI revokes permissions'; else fail 'admin UI revokes permissions' "HTTP $code"; fi
code="$(request "$RESTRICTED_JAR" GET /index.php/default/errors-tdm)"
if [ "$code" = 302 ] && permission_page; then pass 'permission removal revokes access'; else fail 'permission removal revokes access' "HTTP $code"; fi

code="$(request "$ADMIN_JAR" GET /index.php/default/users/permission/id/$id)"
if [ "$code" = 200 ] && rg -q 'name="user"' "$BODY"; then pass 'admin privileged path works'; else fail 'admin privileged path works' "HTTP $code"; fi

echo '==> Restart persistence'
$COMPOSE restart app >/dev/null
for _ in $(seq 1 30); do
    if curl -sS -o /dev/null "$BASE_URL/index.php/auth/login"; then break; fi
    sleep 1
done
code="$(request "$RESTRICTED_JAR" GET /index.php/default/errors-tdm)"
if [ "$code" = 302 ] && permission_page; then pass 'authorization remains correct after restart'; else fail 'authorization remains correct after restart' "HTTP $code"; fi

echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
