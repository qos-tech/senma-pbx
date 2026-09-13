#!/bin/bash
# TASK-0034Q: dashboard preference ownership + method/CSRF boundary.
#
# Contract (schema + code evidence):
#   users.dashboard is a per-user TEXT column (PHP-serialized panel ids).
#   Snep_Dashboard_Manager::get()/set()/add() always key on
#   $_SESSION['id_user'] → users.id. The request cannot name another user.
#   Therefore preference mutation is AUTHENTICATED_SELF_WRITE (Model A),
#   not shared/admin state. No default_index_write RBAC for these paths.
#
#   GET  /default/index[?dashboard_add=...]  -> authenticated-open read;
#        ?dashboard_add= MUST NOT mutate (TASK-0034Q hardening)
#   POST /default/index/dashboard-add        -> self-service + CSRF
#   GET  /default/index/add                  -> self-service form
#   POST /default/index/add                  -> self-service + CSRF
#
# Deliberately separate from `make smoke` and from authorization-smoke.
# See docs/tasks/0034q-dashboard-preferences-authorization-boundary-audit-hardening.md.

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

ADMIN_USER=admin
ADMIN_PASSWORD=SmokeTest123!
USER_A=task0034q-dash-a
PASS_A='Task0034qDashA!'
USER_B=task0034q-dash-b
PASS_B='Task0034qDashB!'
ZERO_USER=task0034q-dash-zeroperm
ZERO_PASSWORD='Task0034qDashZeroperm!'
RO_USER=task0034q-dash-readonly
RO_PASSWORD='Task0034qDashReadonly!'

# Valid panel ids from snep/configs/dashboard.xml order
# (0=IP Status, 1=System Diagnosis). 15=Extensions index.
PANEL_A=0
PANEL_B=1
PANEL_EXT=15
PANEL_UNKNOWN=999001

TMPDIR_N="$(mktemp -d)"
harness_register_best_effort_cleanup "temp working dir" "rm -rf '$TMPDIR_N'"

ADMIN_JAR="$TMPDIR_N/admin.cookies"
A_JAR="$TMPDIR_N/a.cookies"
B_JAR="$TMPDIR_N/b.cookies"
ZERO_JAR="$TMPDIR_N/zero.cookies"
RO_JAR="$TMPDIR_N/ro.cookies"
NONE_JAR="$TMPDIR_N/none.cookies"
BODY="$TMPDIR_N/body"
HEADERS="$TMPDIR_N/headers"

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
is_login_page() { grep -qi 'SNEP - Login\|auth/login\|name="password"' "$BODY"; }

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
        mysql_x "UPDATE users SET password='${hash}', dashboard='' WHERE id=${id};"
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

dash_of() {
    mysql_q "SELECT IFNULL(dashboard,'') FROM users WHERE id=${1} LIMIT 1;"
}

set_dash() {
    mysql_x "UPDATE users SET dashboard='${2}' WHERE id=${1};"
}

echo "==> TASK-0034Q dashboard preferences authorization smoke"

ensure_admin_password
ADMIN_ID="$(mysql_q "SELECT id FROM users WHERE name='admin' LIMIT 1;")"
if [ -z "$ADMIN_ID" ]; then harness_blocked "admin user row not found"; fi
ADMIN_DASH_ORIG="$(dash_of "$ADMIN_ID")"
# Escape single quotes for SQL restore; fixture never invents admin content.
ADMIN_DASH_ORIG_SQL="$(printf "%s" "$ADMIN_DASH_ORIG" | sed "s/'/''/g")"
harness_register_best_effort_cleanup "restore admin dashboard" \
  "$COMPOSE exec -T db mariadb -u'$DB_USER' -p'$DB_PASSWORD' '$DB_NAME' -e \"UPDATE users SET dashboard='${ADMIN_DASH_ORIG_SQL}' WHERE id=${ADMIN_ID};\" >/dev/null 2>&1 || true"

A_ID="$(provision_user "$USER_A" "$PASS_A")"
B_ID="$(provision_user "$USER_B" "$PASS_B")"
ZERO_ID="$(provision_user "$ZERO_USER" "$ZERO_PASSWORD")"
RO_ID="$(provision_user "$RO_USER" "$RO_PASSWORD")"
harness_register_best_effort_cleanup "fixture users" \
  "$COMPOSE exec -T db mariadb -u'$DB_USER' -p'$DB_PASSWORD' '$DB_NAME' -e \"DELETE FROM users_permissions WHERE user_id IN (${A_ID},${B_ID},${ZERO_ID},${RO_ID}); DELETE FROM users WHERE id IN (${A_ID},${B_ID},${ZERO_ID},${RO_ID});\" >/dev/null 2>&1 || true"

mysql_x "INSERT INTO users_permissions (user_id,permission_id,allow,created,updated) VALUES (${RO_ID},'default_extensions_read',1,NOW(),NOW());"

# Deterministic starting prefs: A has panel 0 only; B has panel 1 only; others empty.
set_dash "$A_ID" "a:1:{i:0;i:${PANEL_A};}"
set_dash "$B_ID" "a:1:{i:0;i:${PANEL_B};}"
set_dash "$ZERO_ID" ""
set_dash "$RO_ID" ""

rm -f "$ADMIN_JAR" "$A_JAR" "$B_JAR" "$ZERO_JAR" "$RO_JAR" "$NONE_JAR"
code="$(request "$ADMIN_JAR" POST /index.php/auth/login "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}")"
if [ "$code" = 302 ]; then pass 'admin login' "HTTP $code"; else harness_blocked "admin login did not return 302 (HTTP $code)"; fi
code="$(request "$A_JAR" POST /index.php/auth/login "user=${USER_A}&password=${PASS_A}")"
if [ "$code" = 302 ]; then pass 'user A login' "HTTP $code"; else harness_blocked "user A login HTTP $code"; fi
code="$(request "$B_JAR" POST /index.php/auth/login "user=${USER_B}&password=${PASS_B}")"
if [ "$code" = 302 ]; then pass 'user B login' "HTTP $code"; else harness_blocked "user B login HTTP $code"; fi
code="$(request "$ZERO_JAR" POST /index.php/auth/login "user=${ZERO_USER}&password=${ZERO_PASSWORD}")"
if [ "$code" = 302 ]; then pass 'zero-perm login' "HTTP $code"; else harness_blocked "zero-perm login HTTP $code"; fi
code="$(request "$RO_JAR" POST /index.php/auth/login "user=${RO_USER}&password=${RO_PASSWORD}")"
if [ "$code" = 302 ]; then pass 'read-only login' "HTTP $code"; else harness_blocked "read-only login HTTP $code"; fi

A_CSRF="$(harness_csrf_token "$A_JAR" "$BASE_URL")"
B_CSRF="$(harness_csrf_token "$B_JAR" "$BASE_URL")"
ZERO_CSRF="$(harness_csrf_token "$ZERO_JAR" "$BASE_URL")"
RO_CSRF="$(harness_csrf_token "$RO_JAR" "$BASE_URL")"
ADMIN_CSRF="$(harness_csrf_token "$ADMIN_JAR" "$BASE_URL")"
if [ -z "$A_CSRF" ] || [ -z "$B_CSRF" ] || [ -z "$ZERO_CSRF" ] || [ -z "$RO_CSRF" ] || [ -z "$ADMIN_CSRF" ]; then
    harness_blocked "could not read one or more session CSRF tokens"
fi

# --- unauthenticated cannot mutate ---
BEFORE_A="$(dash_of "$A_ID")"
code="$(request "$NONE_JAR" GET "/index.php/default/index/index?dashboard_add=${PANEL_B}")"
AFTER_A="$(dash_of "$A_ID")"
if { [ "$code" = 200 ] && is_login_page; } || [ "$code" = 302 ]; then
    if [ "$BEFORE_A" = "$AFTER_A" ]; then
        pass 'unauthenticated GET dashboard_add does not mutate' "HTTP $code"
    else
        fail 'unauthenticated GET dashboard_add does not mutate' "HTTP $code before=$BEFORE_A after=$AFTER_A"
    fi
else
    fail 'unauthenticated GET dashboard_add does not mutate' "HTTP $code"
fi

BEFORE_A="$(dash_of "$A_ID")"
code="$(request "$NONE_JAR" POST /index.php/default/index/dashboard-add "dashboard_add=${PANEL_B}&snep_csrf_token=deadbeef")"
AFTER_A="$(dash_of "$A_ID")"
if { [ "$code" = 200 ] && is_login_page; } || [ "$code" = 302 ]; then
    if [ "$BEFORE_A" = "$AFTER_A" ]; then
        pass 'unauthenticated POST dashboard-add does not mutate' "HTTP $code"
    else
        fail 'unauthenticated POST dashboard-add does not mutate' "HTTP $code before=$BEFORE_A after=$AFTER_A"
    fi
else
    fail 'unauthenticated POST dashboard-add does not mutate' "HTTP $code"
fi

# --- GET ?dashboard_add= no longer mutates (method hardening) ---
BEFORE_A="$(dash_of "$A_ID")"
BEFORE_B="$(dash_of "$B_ID")"
code="$(request "$A_JAR" GET "/index.php/default/index/index?dashboard_add=${PANEL_B}")"
AFTER_A="$(dash_of "$A_ID")"
AFTER_B="$(dash_of "$B_ID")"
if [ "$BEFORE_A" = "$AFTER_A" ] && [ "$BEFORE_B" = "$AFTER_B" ]; then
    pass 'authenticated GET dashboard_add does not mutate caller or peer' "HTTP $code"
else
    fail 'authenticated GET dashboard_add does not mutate caller or peer' "HTTP $code A:$BEFORE_A->$AFTER_A B:$BEFORE_B->$AFTER_B"
fi

# --- GET dashboard-add returns 405 and does not mutate ---
BEFORE_A="$(dash_of "$A_ID")"
code="$(request "$A_JAR" GET /index.php/default/index/dashboard-add)"
AFTER_A="$(dash_of "$A_ID")"
if [ "$code" = 405 ] && [ "$BEFORE_A" = "$AFTER_A" ]; then
    pass 'GET dashboard-add rejected (405); DB unchanged' "HTTP $code"
else
    fail 'GET dashboard-add rejected (405); DB unchanged' "HTTP $code before=$BEFORE_A after=$AFTER_A"
fi

# --- CSRF required on POST quick-add ---
BEFORE_A="$(dash_of "$A_ID")"
BEFORE_B="$(dash_of "$B_ID")"
code="$(post_form "$A_JAR" /index.php/default/index/dashboard-add "dashboard_add=${PANEL_B}")"
AFTER_A="$(dash_of "$A_ID")"
AFTER_B="$(dash_of "$B_ID")"
if [ "$code" = 403 ] && [ "$BEFORE_A" = "$AFTER_A" ] && [ "$BEFORE_B" = "$AFTER_B" ]; then
    pass 'POST dashboard-add without CSRF rejected; DB unchanged' "HTTP $code"
else
    fail 'POST dashboard-add without CSRF rejected; DB unchanged' "HTTP $code A:$BEFORE_A->$AFTER_A B:$BEFORE_B->$AFTER_B"
fi

# --- legitimate self-service: A can add panel B to own row only ---
A_CSRF="$(harness_csrf_token "$A_JAR" "$BASE_URL")"
BEFORE_A="$(dash_of "$A_ID")"
BEFORE_B="$(dash_of "$B_ID")"
BEFORE_ADMIN="$(dash_of 1)"
code="$(post_form "$A_JAR" /index.php/default/index/dashboard-add "dashboard_add=${PANEL_B}&snep_csrf_token=${A_CSRF}")"
AFTER_A="$(dash_of "$A_ID")"
AFTER_B="$(dash_of "$B_ID")"
AFTER_ADMIN="$(dash_of 1)"
if [ "$code" = 302 ] && [ "$AFTER_A" != "$BEFORE_A" ] && printf '%s' "$AFTER_A" | grep -q "${PANEL_B}" \
    && [ "$AFTER_B" = "$BEFORE_B" ] && [ "$AFTER_ADMIN" = "$BEFORE_ADMIN" ]; then
    pass 'user A POST dashboard-add mutates only A' "HTTP $code A=$AFTER_A"
else
    fail 'user A POST dashboard-add mutates only A' "HTTP $code A:$BEFORE_A->$AFTER_A B:$BEFORE_B->$AFTER_B admin:$BEFORE_ADMIN->$AFTER_ADMIN"
fi

# --- isolation: B cannot alter A ---
B_CSRF="$(harness_csrf_token "$B_JAR" "$BASE_URL")"
BEFORE_A="$(dash_of "$A_ID")"
BEFORE_B="$(dash_of "$B_ID")"
code="$(post_form "$B_JAR" /index.php/default/index/dashboard-add "dashboard_add=${PANEL_A}&snep_csrf_token=${B_CSRF}")"
AFTER_A="$(dash_of "$A_ID")"
AFTER_B="$(dash_of "$B_ID")"
if [ "$code" = 302 ] && [ "$AFTER_A" = "$BEFORE_A" ] && [ "$AFTER_B" != "$BEFORE_B" ] && printf '%s' "$AFTER_B" | grep -q "${PANEL_A}"; then
    pass 'user B POST dashboard-add mutates only B; A unchanged' "HTTP $code B=$AFTER_B"
else
    fail 'user B POST dashboard-add mutates only B; A unchanged' "HTTP $code A:$BEFORE_A->$AFTER_A B:$BEFORE_B->$AFTER_B"
fi

# --- zero-perm self-service still allowed (Model A, no write RBAC) ---
ZERO_CSRF="$(harness_csrf_token "$ZERO_JAR" "$BASE_URL")"
BEFORE_ZERO="$(dash_of "$ZERO_ID")"
BEFORE_A="$(dash_of "$A_ID")"
code="$(post_form "$ZERO_JAR" /index.php/default/index/dashboard-add "dashboard_add=${PANEL_A}&snep_csrf_token=${ZERO_CSRF}")"
AFTER_ZERO="$(dash_of "$ZERO_ID")"
AFTER_A="$(dash_of "$A_ID")"
if [ "$code" = 302 ] && [ "$AFTER_ZERO" != "$BEFORE_ZERO" ] && printf '%s' "$AFTER_ZERO" | grep -q "${PANEL_A}" && [ "$AFTER_A" = "$BEFORE_A" ]; then
    pass 'zero-perm self-service dashboard-add allowed; peers unchanged' "HTTP $code zero=$AFTER_ZERO"
else
    fail 'zero-perm self-service dashboard-add allowed; peers unchanged' "HTTP $code zero:$BEFORE_ZERO->$AFTER_ZERO A:$BEFORE_A->$AFTER_A"
fi

# --- addAction POST CSRF + self-service replace ---
RO_CSRF="$(harness_csrf_token "$RO_JAR" "$BASE_URL")"
BEFORE_RO="$(dash_of "$RO_ID")"
BEFORE_A="$(dash_of "$A_ID")"
code="$(post_form "$RO_JAR" /index.php/default/index/add "dash[${PANEL_B}]=on")"
AFTER_RO="$(dash_of "$RO_ID")"
AFTER_A="$(dash_of "$A_ID")"
if [ "$code" = 403 ] && [ "$AFTER_RO" = "$BEFORE_RO" ] && [ "$AFTER_A" = "$BEFORE_A" ]; then
    pass 'POST add without CSRF rejected; DB unchanged' "HTTP $code"
else
    fail 'POST add without CSRF rejected; DB unchanged' "HTTP $code ro:$BEFORE_RO->$AFTER_RO A:$BEFORE_A->$AFTER_A"
fi

RO_CSRF="$(harness_csrf_token "$RO_JAR" "$BASE_URL")"
BEFORE_RO="$(dash_of "$RO_ID")"
BEFORE_B="$(dash_of "$B_ID")"
code="$(post_form "$RO_JAR" /index.php/default/index/add "dash[${PANEL_B}]=on&snep_csrf_token=${RO_CSRF}")"
AFTER_RO="$(dash_of "$RO_ID")"
AFTER_B="$(dash_of "$B_ID")"
if [ "$code" = 302 ] && [ "$AFTER_RO" != "$BEFORE_RO" ] && printf '%s' "$AFTER_RO" | grep -q "${PANEL_B}" && [ "$AFTER_B" = "$BEFORE_B" ]; then
    pass 'read-only POST add mutates only own dashboard' "HTTP $code ro=$AFTER_RO"
else
    fail 'read-only POST add mutates only own dashboard' "HTTP $code ro:$BEFORE_RO->$AFTER_RO B:$BEFORE_B->$AFTER_B"
fi

# --- malformed / unknown panel id does not alter state ---
A_CSRF="$(harness_csrf_token "$A_JAR" "$BASE_URL")"
BEFORE_A="$(dash_of "$A_ID")"
code="$(post_form "$A_JAR" /index.php/default/index/dashboard-add "dashboard_add=${PANEL_UNKNOWN}&snep_csrf_token=${A_CSRF}")"
AFTER_A="$(dash_of "$A_ID")"
if [ "$code" = 302 ] && [ "$AFTER_A" = "$BEFORE_A" ]; then
    pass 'unknown panel id leaves caller dashboard unchanged' "HTTP $code"
else
    fail 'unknown panel id leaves caller dashboard unchanged' "HTTP $code before=$BEFORE_A after=$AFTER_A"
fi

# --- dashboard preference is not an authorization bypass ---
ZERO_CSRF="$(harness_csrf_token "$ZERO_JAR" "$BASE_URL")"
code="$(post_form "$ZERO_JAR" /index.php/default/index/dashboard-add "dashboard_add=${PANEL_EXT}&snep_csrf_token=${ZERO_CSRF}")"
AFTER_ZERO="$(dash_of "$ZERO_ID")"
if ! printf '%s' "$AFTER_ZERO" | grep -q "${PANEL_EXT}"; then
    fail 'seed extensions panel onto zero-perm dashboard' "dash=$AFTER_ZERO"
else
    pass 'seed extensions panel onto zero-perm dashboard' "dash=$AFTER_ZERO"
fi
code="$(request "$ZERO_JAR" GET /index.php/default/extensions)"
if [ "$code" = 302 ] && redirects_to_permission_error; then
    pass 'dashboard panel does not grant extensions backend access' "HTTP $code"
else
    fail 'dashboard panel does not grant extensions backend access' "HTTP $code loc=$(grep -i Location "$HEADERS" | tr -d '\r')"
fi

# --- superuser still supported ---
ADMIN_CSRF="$(harness_csrf_token "$ADMIN_JAR" "$BASE_URL")"
BEFORE_ADMIN="$(dash_of 1)"
BEFORE_A="$(dash_of "$A_ID")"
BEFORE_B="$(dash_of "$B_ID")"
code="$(post_form "$ADMIN_JAR" /index.php/default/index/dashboard-add "dashboard_add=${PANEL_A}&snep_csrf_token=${ADMIN_CSRF}")"
AFTER_ADMIN="$(dash_of 1)"
AFTER_A="$(dash_of "$A_ID")"
AFTER_B="$(dash_of "$B_ID")"
if [ "$code" = 302 ] && [ "$AFTER_A" = "$BEFORE_A" ] && [ "$AFTER_B" = "$BEFORE_B" ]; then
    pass 'superuser POST dashboard-add still works; peers untouched' "HTTP $code admin:$BEFORE_ADMIN->$AFTER_ADMIN"
else
    fail 'superuser POST dashboard-add still works; peers untouched' "HTTP $code admin:$BEFORE_ADMIN->$AFTER_ADMIN A:$BEFORE_A->$AFTER_A B:$BEFORE_B->$AFTER_B"
fi

mysql_x "DELETE FROM users_permissions WHERE user_id IN (${A_ID},${B_ID},${ZERO_ID},${RO_ID});"
mysql_x "DELETE FROM users WHERE id IN (${A_ID},${B_ID},${ZERO_ID},${RO_ID});"

harness_complete
