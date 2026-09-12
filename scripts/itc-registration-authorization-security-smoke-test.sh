#!/bin/bash
# TASK-0034O: ITC optional-integration + authorization-boundary regression.
#
# Architecture (revised product contract):
#
#   SENMA core = standalone
#   ITC / future vendor portal = optional (setup.conf itc_enabled=true)
#
# Default (itc_enabled absent/false):
#   login -> normal authenticated landing (dashboard / dashboard-edit)
#   no registration interstitial
#   no outbound ITC HTTP required
#   RegisterController redirects home without mutating state
#
# When explicitly enabled (itc_enabled=true), the historical interstitial
# and RegisterController write surfaces remain, but POSTs still require
# default_index_write / default_register_write (PermissionPlugin
# $writeOnPostIndex) and CSRF. Register GET must not rewrite
# itc_consumers.
#
# Deliberately separate from `make smoke` and from authorization-smoke.
# See docs/tasks/0034o-itc-vendor-registration-authorization-boundary-audit-hardening.md.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

BASE_URL="${AUTHORIZATION_SMOKE_BASE_URL:-http://127.0.0.1:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
COMPOSE="${SMOKE_COMPOSE:-docker compose}"
DB_USER="${DB_USER:-snep}"
DB_PASSWORD="${DB_PASSWORD:-change-me-for-local-development}"
DB_NAME="${DB_NAME:-snep}"
SETUP_CONF="${ITC_SMOKE_SETUP_CONF:-$SCRIPT_DIR/../snep/includes/setup.conf}"
ADMIN_USER=admin
ADMIN_PASSWORD=SmokeTest123!
ZERO_USER=task0034o-itc-zeroperm
ZERO_PASSWORD='Task0034oItcZeroperm!'
RO_USER=task0034o-itc-readonly
RO_PASSWORD='Task0034oItcReadonly!'
WRITER_USER=task0034o-itc-writer
WRITER_PASSWORD='Task0034oItcWriter!'

TMPDIR_ITC="$(mktemp -d)"
harness_register_best_effort_cleanup "temp working dir" "rm -rf '$TMPDIR_ITC'"
ADMIN_JAR="$TMPDIR_ITC/admin.cookies"
ZERO_JAR="$TMPDIR_ITC/zero.cookies"
RO_JAR="$TMPDIR_ITC/ro.cookies"
WRITER_JAR="$TMPDIR_ITC/writer.cookies"
NONE_JAR="$TMPDIR_ITC/none.cookies"
BODY="$TMPDIR_ITC/body"
HEADERS="$TMPDIR_ITC/headers"

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

post_form() {
    local jar="$1" path="$2" data="$3"
    curl -sS -b "$jar" -c "$jar" -D "$HEADERS" -o "$BODY" -w '%{http_code}' -d "$data" "$BASE_URL$path"
}

redirects_to_permission_error() { grep -qi '^Location:.*permission/error' "$HEADERS"; }

mysql_q() { $COMPOSE exec -T db mariadb -N -s -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "$1" | tr -d '\r'; }
mysql_x() { $COMPOSE exec -T db mariadb -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "$1" >/dev/null; }

provision_user() {
    local user="$1" password="$2" hash id
    hash="$($COMPOSE exec -T app php -r "echo md5('${password}');" | tr -d '\r\n')"
    if [ -z "$hash" ]; then harness_blocked "could not compute password hash for $user via the app container"; fi
    id="$(mysql_q "SELECT id FROM users WHERE name='${user}' LIMIT 1;")"
    if [ -z "$id" ]; then
        mysql_x "INSERT INTO users (name,password,email,dashboard,profile_id,created,updated) VALUES ('${user}','${hash}','${user}@example.test','',1,NOW(),NOW());"
        id="$(mysql_q "SELECT id FROM users WHERE name='${user}' LIMIT 1;")"
    else
        mysql_x "UPDATE users SET password='${hash}' WHERE id=${id};"
    fi
    if [ -z "$id" ]; then harness_blocked "could not provision or find test user ${user}"; fi
    mysql_x "DELETE FROM users_permissions WHERE user_id=${id};"
    printf '%s' "$id"
}

ensure_admin_password() {
    local hash
    hash="$($COMPOSE exec -T app php -r "echo md5('${ADMIN_PASSWORD}');" | tr -d '\r\n')"
    mysql_x "UPDATE users SET password='${hash}' WHERE name='admin';"
}

itc_state() { mysql_q "SELECT CONCAT(IFNULL(registered_itc,0),':',IFNULL(noregister,0)) FROM itc_register LIMIT 1;"; }

# Exact logical snapshot of both ITC tables. Used to prove standalone login
# performs zero ITC DB activity (no INSERT/UPDATE on either table).
itc_snapshot() {
    mysql_q "SELECT CONCAT(
        'R=', (SELECT COUNT(*) FROM itc_register),
        '|C=', (SELECT COUNT(*) FROM itc_consumers),
        '|RH=', IFNULL((SELECT MD5(GROUP_CONCAT(CONCAT_WS('#',uuid,IFNULL(client_key,''),IFNULL(api_key,''),IFNULL(registered_itc,0),IFNULL(noregister,0),IFNULL(created,'')) ORDER BY uuid SEPARATOR '&')) FROM itc_register),''),
        '|CH=', IFNULL((SELECT MD5(GROUP_CONCAT(CONCAT_WS('#',id_distro,id_service,name_service) ORDER BY id_distro,id_service,name_service SEPARATOR '&')) FROM itc_consumers),'')
    );"
}

reset_itc_unregistered() {
    local n
    n="$(mysql_q "SELECT COUNT(*) FROM itc_register;")"
    if [ "$n" = 0 ]; then
        mysql_x "INSERT INTO itc_register (uuid,client_key,api_key,created,registered_itc,noregister) VALUES ('00000000-0000-4000-8000-000000000034','','',NOW(),0,0);"
    else
        mysql_x "UPDATE itc_register SET registered_itc=0, noregister=0, api_key='', client_key='';"
    fi
}

set_itc_enabled() {
    local want="$1"
    if [ ! -f "$SETUP_CONF" ]; then
        harness_blocked "setup.conf not found at $SETUP_CONF"
    fi
    if grep -qE '^itc_enabled\s*=' "$SETUP_CONF"; then
        sed -i -E "s/^itc_enabled\s*=\s*\".*\"/itc_enabled = \"${want}\"/" "$SETUP_CONF"
    elif grep -qE '^itc_required\s*=' "$SETUP_CONF"; then
        sed -i -E "/^itc_required\s*=/i itc_enabled = \"${want}\"" "$SETUP_CONF"
    else
        printf '\nitc_enabled = "%s"\n' "$want" >> "$SETUP_CONF"
    fi
    grep -qE "^itc_enabled\s*=\s*\"${want}\"" "$SETUP_CONF" \
        || harness_blocked "failed to set itc_enabled=${want} in $SETUP_CONF"
    # Host-side sed -i rewrites the bind-mounted file as the host user
    # (uid 1000). System Status "File Permissions" requires setup.conf
    # writable by www-data -- restore the runtime ownership contract.
    restore_setup_conf_ownership
}

# Host sed -i on the bind-mounted setup.conf changes ownership to the
# invoking host user; www-data then fails is_writable() and System Status
# "File Permissions" goes red for every later suite in the same regression.
restore_setup_conf_ownership() {
    $COMPOSE exec -T -u root app sh -c \
        'chown www-data:www-data /var/www/html/snep/includes/setup.conf && chmod 664 /var/www/html/snep/includes/setup.conf' \
        >/dev/null 2>&1 \
        || harness_blocked "could not restore www-data ownership on setup.conf after host-side edit"
}

# Accept dashboard/edit (200) or empty-dashboard redirect to index/add (302).
# Reject the registration interstitial.
landing_is_core_not_interstitial() {
    local jar="$1" code="$2"
    if grep -qE 'noregisterForm|name="save" value="noregister"|I am already registered' "$BODY"; then
        return 1
    fi
    if [ "$code" = 200 ] && grep -qiE 'Dashboard|snep-panel-dashboard|System Diagnosis' "$BODY"; then
        return 0
    fi
    if [ "$code" = 302 ] && grep -qiE 'Location:.*index/add' "$HEADERS"; then
        local hop
        hop="$(curl -sS -b "$jar" -c "$jar" -o "$BODY" -w '%{http_code}' "$BASE_URL/index.php/default/index/add")"
        if [ "$hop" = 200 ] && grep -qiE 'Dashboard|System Diagnosis|Edit' "$BODY" \
            && ! grep -q 'noregisterForm' "$BODY"; then
            return 0
        fi
    fi
    return 1
}

echo '==> Preflight'
harness_require_containers app db
ensure_admin_password
reset_itc_unregistered
set_itc_enabled false
harness_register_best_effort_cleanup "restore itc_enabled=false (standalone default) + setup.conf ownership" \
    "sed -i -E 's/^itc_enabled[[:space:]]*=[[:space:]]*\".*\"/itc_enabled = \"false\"/' '$SETUP_CONF'; $COMPOSE exec -T -u root app sh -c 'chown www-data:www-data /var/www/html/snep/includes/setup.conf && chmod 664 /var/www/html/snep/includes/setup.conf' >/dev/null 2>&1 || true"

ORIG_ADDR="$(grep -E '^itc_address\s*=' "$SETUP_CONF" | head -1 || true)"
sed -i -E 's|^itc_address\s*=\s*".*"|itc_address = "http://127.0.0.1:1/api/v1/"|' "$SETUP_CONF"
restore_setup_conf_ownership
harness_register_best_effort_cleanup "restore itc_address + setup.conf ownership" \
    "sed -i -E 's|^itc_address[[:space:]]*=[[:space:]]*\".*\"|${ORIG_ADDR:-itc_address = \"https://api.opens.com.br/api/v1/\"}|' '$SETUP_CONF'; $COMPOSE exec -T -u root app sh -c 'chown www-data:www-data /var/www/html/snep/includes/setup.conf && chmod 664 /var/www/html/snep/includes/setup.conf' >/dev/null 2>&1 || true"

echo '==> Test identities'
ZERO_ID="$(provision_user "$ZERO_USER" "$ZERO_PASSWORD")"
RO_ID="$(provision_user "$RO_USER" "$RO_PASSWORD")"
WRITER_ID="$(provision_user "$WRITER_USER" "$WRITER_PASSWORD")"
harness_register_best_effort_cleanup "ITC test user permissions reset to baseline" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}' -e \"DELETE FROM users_permissions WHERE user_id IN (${ZERO_ID},${RO_ID},${WRITER_ID});\" >/dev/null"
harness_register_best_effort_cleanup "ITC register row restored to unregistered baseline" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}' -e \"UPDATE itc_register SET registered_itc=0, noregister=0, api_key='', client_key=''; DELETE FROM itc_consumers WHERE name_service='task0034o-marker';\" >/dev/null"

echo '==> Logins'
code="$(request "$ADMIN_JAR" POST /index.php/auth/login "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}")"
if [ "$code" = 302 ]; then pass 'admin login' "HTTP $code"; else harness_blocked "admin login did not return 302 (HTTP $code)"; fi
code="$(request "$ZERO_JAR" POST /index.php/auth/login "user=${ZERO_USER}&password=${ZERO_PASSWORD}")"
if [ "$code" = 302 ]; then pass 'zero-permission login' "HTTP $code"; else harness_blocked "zero-permission login did not return 302 (HTTP $code)"; fi
code="$(request "$RO_JAR" POST /index.php/auth/login "user=${RO_USER}&password=${RO_PASSWORD}")"
if [ "$code" = 302 ]; then pass 'read-only login' "HTTP $code"; else harness_blocked "read-only login did not return 302 (HTTP $code)"; fi
code="$(request "$WRITER_JAR" POST /index.php/auth/login "user=${WRITER_USER}&password=${WRITER_PASSWORD}")"
if [ "$code" = 302 ]; then pass 'writer login' "HTTP $code"; else harness_blocked "writer login did not return 302 (HTTP $code)"; fi

ADMIN_CSRF="$(harness_csrf_token "$ADMIN_JAR" "$BASE_URL")"
if [ -z "$ADMIN_CSRF" ]; then harness_blocked "could not read the admin session's CSRF token"; fi

echo '==> Grants (via real Users > Permission UI)'
code="$(request "$ADMIN_JAR" POST /index.php/default/users/permission/id/$RO_ID "user=$RO_ID&default_extensions_read=1&snep_csrf_token=$ADMIN_CSRF")"
if [ "$code" = 302 ]; then pass 'admin grants unrelated read-only permission' "HTTP $code"; else fail 'admin grants unrelated read-only permission' "HTTP $code"; fi
code="$(request "$ADMIN_JAR" POST /index.php/default/users/permission/id/$WRITER_ID "user=$WRITER_ID&default_index_write=1&snep_csrf_token=$ADMIN_CSRF")"
if [ "$code" = 302 ]; then pass 'admin grants default_index_write' "HTTP $code"; else fail 'admin grants default_index_write' "HTTP $code"; fi

ZERO_CSRF="$(harness_csrf_token "$ZERO_JAR" "$BASE_URL")"
RO_CSRF="$(harness_csrf_token "$RO_JAR" "$BASE_URL")"
WRITER_CSRF="$(harness_csrf_token "$WRITER_JAR" "$BASE_URL")"
if [ -z "$ZERO_CSRF" ] || [ -z "$RO_CSRF" ] || [ -z "$WRITER_CSRF" ]; then
    harness_blocked "could not read a session CSRF token for one or more fixtures"
fi

echo '==> Standalone core (itc_enabled=false): no interstitial, no ITC required'
# itc_address was forced to an unreachable local port above -- core must
# still land without an external ITC round-trip or registration DB state.
reset_itc_unregistered
# Plant a distinctive consumer marker so equality asserts cover BOTH tables.
mysql_x "DELETE FROM itc_consumers WHERE name_service='task0034o-login-marker';"
mysql_x "INSERT INTO itc_consumers (id_distro,id_service,name_service) VALUES (34,340,'task0034o-login-marker');"
mysql_x "UPDATE itc_register SET api_key='task0034o-prelogin', client_key='task0034o-prelogin-client', registered_itc=0, noregister=0;"
SNAP_BEFORE="$(itc_snapshot)"
rm -f "$ADMIN_JAR" "$ZERO_JAR"
code="$(request "$ADMIN_JAR" POST /index.php/auth/login "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}")"
if [ "$code" = 302 ]; then
    pass 'standalone login succeeds with ITC disabled' "HTTP $code"
else
    fail 'standalone login succeeds with ITC disabled' "HTTP $code"
fi
code="$(request "$ADMIN_JAR" GET /index.php/default/index)"
SNAP_AFTER="$(itc_snapshot)"
if landing_is_core_not_interstitial "$ADMIN_JAR" "$code" && [ "$SNAP_BEFORE" = "$SNAP_AFTER" ]; then
    pass 'standalone admin landing skips ITC interstitial' "HTTP $code, snapshot unchanged"
    pass 'core available with unreachable itc_address (failure isolation)' "HTTP $code, itc_address=127.0.0.1:1"
    pass 'standalone login leaves itc_register/itc_consumers unchanged' "snapshot=$SNAP_AFTER"
else
    fail 'standalone admin landing skips ITC interstitial' "HTTP $code before=$SNAP_BEFORE after=$SNAP_AFTER"
    fail 'core available with unreachable itc_address (failure isolation)' "HTTP $code before=$SNAP_BEFORE after=$SNAP_AFTER"
    fail 'standalone login leaves itc_register/itc_consumers unchanged' "before=$SNAP_BEFORE after=$SNAP_AFTER"
fi

# Strong isolation: empty ITC tables must not be re-seeded by login when
# ITC is disabled. Backup → truncate → login → assert still empty → restore.
mysql_x "CREATE TABLE IF NOT EXISTS _task0034o_itc_register_bak LIKE itc_register;"
mysql_x "CREATE TABLE IF NOT EXISTS _task0034o_itc_consumers_bak LIKE itc_consumers;"
mysql_x "DELETE FROM _task0034o_itc_register_bak; DELETE FROM _task0034o_itc_consumers_bak;"
mysql_x "INSERT INTO _task0034o_itc_register_bak SELECT * FROM itc_register;"
mysql_x "INSERT INTO _task0034o_itc_consumers_bak SELECT * FROM itc_consumers;"
harness_register_best_effort_cleanup "restore ITC rows after empty-table login proof" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}' -e \"DELETE FROM itc_consumers; DELETE FROM itc_register; INSERT INTO itc_register SELECT * FROM _task0034o_itc_register_bak; INSERT INTO itc_consumers SELECT * FROM _task0034o_itc_consumers_bak; DROP TABLE IF EXISTS _task0034o_itc_register_bak; DROP TABLE IF EXISTS _task0034o_itc_consumers_bak;\" >/dev/null 2>&1 || true"
mysql_x "DELETE FROM itc_consumers; DELETE FROM itc_register;"
EMPTY_BEFORE="$(itc_snapshot)"
rm -f "$ADMIN_JAR"
code="$(request "$ADMIN_JAR" POST /index.php/auth/login "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}")"
code="$(request "$ADMIN_JAR" GET /index.php/default/index)"
EMPTY_AFTER="$(itc_snapshot)"
if landing_is_core_not_interstitial "$ADMIN_JAR" "$code" \
    && [ "$EMPTY_BEFORE" = "$EMPTY_AFTER" ] \
    && [ "$EMPTY_AFTER" = "R=0|C=0|RH=|CH=" ]; then
    pass 'standalone login does not depend on ITC rows (empty tables)' "HTTP $code, snapshot=$EMPTY_AFTER"
else
    fail 'standalone login does not depend on ITC rows (empty tables)' "HTTP $code before=$EMPTY_BEFORE after=$EMPTY_AFTER"
fi
# Restore immediately so later checks see a normal unregistered row.
mysql_x "DELETE FROM itc_consumers; DELETE FROM itc_register;"
mysql_x "INSERT INTO itc_register SELECT * FROM _task0034o_itc_register_bak;"
mysql_x "INSERT INTO itc_consumers SELECT * FROM _task0034o_itc_consumers_bak;"
mysql_x "DROP TABLE IF EXISTS _task0034o_itc_register_bak; DROP TABLE IF EXISTS _task0034o_itc_consumers_bak;"

code="$(request "$ZERO_JAR" POST /index.php/auth/login "user=${ZERO_USER}&password=${ZERO_PASSWORD}")"
code="$(request "$ZERO_JAR" GET /index.php/default/index)"
if landing_is_core_not_interstitial "$ZERO_JAR" "$code"; then
    pass 'standalone zero-perm landing skips ITC interstitial' "HTTP $code"
else
    fail 'standalone zero-perm landing skips ITC interstitial' "HTTP $code"
fi

BEFORE="$(itc_state)"
code="$(request "$ADMIN_JAR" GET /index.php/default/register)"
AFTER="$(itc_state)"
if [ "$code" = 302 ] && [ "$BEFORE" = "$AFTER" ]; then
    pass 'standalone RegisterController redirects home, no mutation' "HTTP $code, state=$AFTER"
else
    fail 'standalone RegisterController redirects home, no mutation' "HTTP $code before=$BEFORE after=$AFTER loc=$(grep -i Location "$HEADERS" | tr -d '\r')"
fi

code="$(request "$NONE_JAR" GET /index.php/default/index)"
if [ "$code" = 200 ] && grep -q 'SNEP - Login' "$BODY"; then
    pass 'unauthenticated GET index denied' "HTTP $code, login page"
else
    fail 'unauthenticated GET index denied' "HTTP $code"
fi
BEFORE="$(itc_state)"
code="$(post_form "$NONE_JAR" /index.php/default/index "save=noregister")"
AFTER="$(itc_state)"
if [ "$code" = 200 ] && grep -q 'SNEP - Login' "$BODY" && [ "$BEFORE" = "$AFTER" ]; then
    pass 'unauthenticated POST noregister denied' "HTTP $code, state unchanged"
else
    fail 'unauthenticated POST noregister denied' "HTTP $code before=$BEFORE after=$AFTER"
fi

echo '==> Optional ITC mode (itc_enabled=true): authorization matrix'
set_itc_enabled true
reset_itc_unregistered
rm -f "$ADMIN_JAR" "$ZERO_JAR" "$RO_JAR" "$WRITER_JAR"
code="$(request "$ADMIN_JAR" POST /index.php/auth/login "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}")"
code="$(request "$ZERO_JAR" POST /index.php/auth/login "user=${ZERO_USER}&password=${ZERO_PASSWORD}")"
code="$(request "$RO_JAR" POST /index.php/auth/login "user=${RO_USER}&password=${RO_PASSWORD}")"
code="$(request "$WRITER_JAR" POST /index.php/auth/login "user=${WRITER_USER}&password=${WRITER_PASSWORD}")"
ADMIN_CSRF="$(harness_csrf_token "$ADMIN_JAR" "$BASE_URL")"
ZERO_CSRF="$(harness_csrf_token "$ZERO_JAR" "$BASE_URL")"
RO_CSRF="$(harness_csrf_token "$RO_JAR" "$BASE_URL")"
WRITER_CSRF="$(harness_csrf_token "$WRITER_JAR" "$BASE_URL")"

code="$(request "$ZERO_JAR" GET /index.php/default/index)"
if [ "$code" = 200 ] && grep -qiE 'register|noregister' "$BODY"; then
    pass 'optional-ITC zero-perm GET reaches registration interstitial' "HTTP $code"
else
    fail 'optional-ITC zero-perm GET reaches registration interstitial' "HTTP $code"
fi

BEFORE="$(itc_state)"
code="$(post_form "$ZERO_JAR" /index.php/default/index "save=noregister&snep_csrf_token=${ZERO_CSRF}")"
AFTER="$(itc_state)"
if [ "$code" = 302 ] && redirects_to_permission_error && [ "$BEFORE" = "$AFTER" ] && [ "${AFTER##*:}" = 0 ]; then
    pass 'zero-permission POST noregister denied' "HTTP $code, state unchanged ($AFTER)"
else
    fail 'zero-permission POST noregister denied' "HTTP $code before=$BEFORE after=$AFTER loc=$(grep -i Location "$HEADERS" | tr -d '\r')"
fi

BEFORE="$(itc_state)"
code="$(post_form "$RO_JAR" /index.php/default/index "save=noregister&snep_csrf_token=${RO_CSRF}")"
AFTER="$(itc_state)"
if [ "$code" = 302 ] && redirects_to_permission_error && [ "$BEFORE" = "$AFTER" ] && [ "${AFTER##*:}" = 0 ]; then
    pass 'read-only POST noregister denied' "HTTP $code, state unchanged ($AFTER)"
else
    fail 'read-only POST noregister denied' "HTTP $code before=$BEFORE after=$AFTER"
fi

BEFORE="$(itc_state)"
code="$(post_form "$WRITER_JAR" /index.php/default/index "save=noregister&snep_csrf_token=${WRITER_CSRF}")"
AFTER="$(itc_state)"
if [ "$code" = 302 ] && [ "${AFTER##*:}" = 1 ]; then
    pass 'writer POST noregister allowed' "HTTP $code, state $BEFORE -> $AFTER"
else
    fail 'writer POST noregister allowed' "HTTP $code before=$BEFORE after=$AFTER loc=$(grep -i Location "$HEADERS" | tr -d '\r')"
fi

reset_itc_unregistered
rm -f "$ADMIN_JAR"
code="$(request "$ADMIN_JAR" POST /index.php/auth/login "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}")"
ADMIN_CSRF="$(harness_csrf_token "$ADMIN_JAR" "$BASE_URL")"

BEFORE="$(itc_state)"
code="$(post_form "$ADMIN_JAR" /index.php/default/index "save=noregister&snep_csrf_token=${ADMIN_CSRF}")"
AFTER="$(itc_state)"
if [ "$code" = 302 ] && [ "${AFTER##*:}" = 1 ]; then
    pass 'superuser POST noregister allowed' "HTTP $code, state $BEFORE -> $AFTER"
else
    fail 'superuser POST noregister allowed' "HTTP $code before=$BEFORE after=$AFTER"
fi

reset_itc_unregistered
rm -f "$ADMIN_JAR"
code="$(request "$ADMIN_JAR" POST /index.php/auth/login "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}")"
ADMIN_CSRF="$(harness_csrf_token "$ADMIN_JAR" "$BASE_URL")"

echo '==> CSRF contract (optional ITC, superuser session)'
BEFORE="$(itc_state)"
code="$(post_form "$ADMIN_JAR" /index.php/default/index "save=noregister")"
AFTER="$(itc_state)"
if [ "$code" = 403 ] && [ "$BEFORE" = "$AFTER" ]; then
    pass 'superuser POST noregister without CSRF denied' "HTTP $code"
else
    fail 'superuser POST noregister without CSRF denied' "HTTP $code before=$BEFORE after=$AFTER"
fi
BEFORE="$(itc_state)"
code="$(post_form "$ADMIN_JAR" /index.php/default/index "save=noregister&snep_csrf_token=0000000000000000000000000000000000000000000000000000000000000000")"
AFTER="$(itc_state)"
if [ "$code" = 403 ] && [ "$BEFORE" = "$AFTER" ]; then
    pass 'superuser POST noregister with wrong CSRF denied' "HTTP $code"
else
    fail 'superuser POST noregister with wrong CSRF denied' "HTTP $code before=$BEFORE after=$AFTER"
fi

echo '==> RegisterController GET must not rewrite itc_consumers (optional ITC)'
mysql_x "UPDATE itc_register SET registered_itc=1, noregister=0, api_key='task0034o-api', client_key='task0034o-client';"
mysql_x "DELETE FROM itc_consumers WHERE name_service='task0034o-marker';"
mysql_x "INSERT INTO itc_consumers (id_distro,id_service,name_service) VALUES (9034,9034,'task0034o-marker');"
BEFORE_C="$(mysql_q "SELECT COUNT(*) FROM itc_consumers WHERE name_service='task0034o-marker';")"
rm -f "$ZERO_JAR"
code="$(request "$ZERO_JAR" POST /index.php/auth/login "user=${ZERO_USER}&password=${ZERO_PASSWORD}")"
code="$(request "$ZERO_JAR" GET /index.php/default/register)"
AFTER_C="$(mysql_q "SELECT COUNT(*) FROM itc_consumers WHERE name_service='task0034o-marker';")"
if [ "$BEFORE_C" = 1 ] && [ "$AFTER_C" = 1 ]; then
    pass 'RegisterController GET does not rewrite itc_consumers' "HTTP $code, marker rows=$AFTER_C"
else
    fail 'RegisterController GET does not rewrite itc_consumers' "HTTP $code before=$BEFORE_C after=$AFTER_C"
fi

echo '==> RegisterController POST requires default_register_write'
ZERO_CSRF="$(harness_csrf_token "$ZERO_JAR" "$BASE_URL")"
BEFORE_K="$(mysql_q "SELECT CONCAT(IFNULL(api_key,''),':',IFNULL(client_key,'')) FROM itc_register LIMIT 1;")"
BEFORE_C="$(mysql_q "SELECT COUNT(*) FROM itc_consumers WHERE name_service='task0034o-marker';")"
code="$(post_form "$ZERO_JAR" /index.php/default/register "save=login&email=task0034o@example.test&password=x&snep_csrf_token=${ZERO_CSRF}")"
AFTER_K="$(mysql_q "SELECT CONCAT(IFNULL(api_key,''),':',IFNULL(client_key,'')) FROM itc_register LIMIT 1;")"
AFTER_C="$(mysql_q "SELECT COUNT(*) FROM itc_consumers WHERE name_service='task0034o-marker';")"
if [ "$code" = 302 ] && redirects_to_permission_error && [ "$BEFORE_K" = "$AFTER_K" ] && [ "$BEFORE_C" = "$AFTER_C" ]; then
    pass 'zero-permission POST register login denied' "HTTP $code, keys/consumers unchanged"
else
    fail 'zero-permission POST register login denied' "HTTP $code before_k=$BEFORE_K after_k=$AFTER_K before_c=$BEFORE_C after_c=$AFTER_C loc=$(grep -i Location "$HEADERS" | tr -d '\r')"
fi
mysql_x "DELETE FROM itc_consumers WHERE name_service='task0034o-marker';"
mysql_x "UPDATE itc_register SET api_key='', client_key='';"
reset_itc_unregistered

echo '==> Optional interstitial emits CSRF meta + csrf.js'
rm -f "$ADMIN_JAR"
code="$(request "$ADMIN_JAR" POST /index.php/auth/login "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}")"
code="$(request "$ADMIN_JAR" GET /index.php/default/index)"
if [ "$code" = 200 ] && grep -q 'name="csrf-token"' "$BODY" && grep -q 'csrf.js' "$BODY"; then
    pass 'registration interstitial emits CSRF meta + csrf.js' "HTTP $code"
else
    fail 'registration interstitial emits CSRF meta + csrf.js' "HTTP $code"
fi

echo '==> Privileged-field injection on noregister does not elevate'
reset_itc_unregistered
rm -f "$ADMIN_JAR"
code="$(request "$ADMIN_JAR" POST /index.php/auth/login "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}")"
ADMIN_CSRF="$(harness_csrf_token "$ADMIN_JAR" "$BASE_URL")"
BEFORE="$(itc_state)"
code="$(post_form "$ADMIN_JAR" /index.php/default/index "save=noregister&registered_itc=1&api_key=pwned&client_key=pwned&snep_csrf_token=${ADMIN_CSRF}")"
AFTER="$(itc_state)"
KEYS="$(mysql_q "SELECT CONCAT(IFNULL(api_key,''),':',IFNULL(client_key,'')) FROM itc_register LIMIT 1;")"
if [ "$code" = 302 ] && [ "${AFTER##*:}" = 1 ] && [ "${AFTER%%:*}" = 0 ] && [ "$KEYS" = ':' ]; then
    pass 'noregister ignores injected privileged fields' "HTTP $code, state=$AFTER keys empty"
else
    fail 'noregister ignores injected privileged fields' "HTTP $code state=$AFTER keys=$KEYS"
fi
reset_itc_unregistered

set_itc_enabled false

harness_complete
