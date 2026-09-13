#!/bin/bash
# TASK-0034P: notification dismiss ownership + authorization boundary.
#
# Contract (schema + code evidence):
#   core_notifications = shared PBX-wide vendor-notice cache (no user_id).
#   Snep_Notifications::setRead()/removeNotification() key the vendor API
#   on installation $_SESSION['uuid'], not on the acting user.
#   Therefore dismiss is AUTHENTICATED_GLOBAL_WRITE, not per-user
#   self-service acknowledgement.
#
#   GET  /default/notifications            -> authenticated-open (alwaysAllow)
#   POST /default/notifications/mark-read  -> default_notifications_write + CSRF
#   GET/POST /default/notifications/remove -> default_notifications_write (+ CSRF on POST)
#
# Deliberately separate from `make smoke` and from authorization-smoke.
# See docs/tasks/0034p-notification-dismiss-authorization-boundary-audit-hardening.md.

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
ZERO_USER=task0034p-notif-zeroperm
ZERO_PASSWORD='Task0034pNotifZeroperm!'
RO_USER=task0034p-notif-readonly
RO_PASSWORD='Task0034pNotifReadonly!'
WRITER_USER=task0034p-notif-writer
WRITER_PASSWORD='Task0034pNotifWriter!'

FIXTURE_PREFIX='task0034p-notif'
ID_A=9034
ID_B=9035
ID_C=9036

TMPDIR_N="$(mktemp -d)"
harness_register_best_effort_cleanup "temp working dir" "rm -rf '$TMPDIR_N'"
harness_register_best_effort_cleanup "fixture notifications" \
  "$COMPOSE exec -T db mariadb -u'$DB_USER' -p'$DB_PASSWORD' '$DB_NAME' -e \"DELETE FROM core_notifications WHERE title LIKE '${FIXTURE_PREFIX}%';\" >/dev/null 2>&1 || true"

ADMIN_JAR="$TMPDIR_N/admin.cookies"
ZERO_JAR="$TMPDIR_N/zero.cookies"
RO_JAR="$TMPDIR_N/ro.cookies"
WRITER_JAR="$TMPDIR_N/writer.cookies"
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

snap_fixture() {
    mysql_q "SELECT CONCAT(IFNULL(id_itc,''),':',IFNULL(\`read\`,0),':',IFNULL(title,'')) FROM core_notifications WHERE title LIKE '${FIXTURE_PREFIX}%' ORDER BY id_itc;"
}

seed_fixtures() {
    mysql_x "DELETE FROM core_notifications WHERE title LIKE '${FIXTURE_PREFIX}%';"
    mysql_x "INSERT INTO core_notifications (id_itc,title,\`from\`,message,creation_date,\`read\`,reading_date) VALUES
      (${ID_A},'${FIXTURE_PREFIX}-a','Opens','fixture-a',NOW(),0,'0000-00-00 00:00:00'),
      (${ID_B},'${FIXTURE_PREFIX}-b','Opens','fixture-b',NOW(),0,'0000-00-00 00:00:00'),
      (${ID_C},'${FIXTURE_PREFIX}-c','Opens','fixture-c',NOW(),0,'0000-00-00 00:00:00');"
}

row_read() {
    mysql_q "SELECT IFNULL(\`read\`,0) FROM core_notifications WHERE id_itc=${1} AND title LIKE '${FIXTURE_PREFIX}%' LIMIT 1;"
}

row_exists() {
    mysql_q "SELECT COUNT(*) FROM core_notifications WHERE id_itc=${1} AND title LIKE '${FIXTURE_PREFIX}%';"
}

echo "==> TASK-0034P notification dismiss authorization smoke"

ensure_admin_password
ZERO_ID="$(provision_user "$ZERO_USER" "$ZERO_PASSWORD")"
RO_ID="$(provision_user "$RO_USER" "$RO_PASSWORD")"
WRITER_ID="$(provision_user "$WRITER_USER" "$WRITER_PASSWORD")"
harness_register_best_effort_cleanup "fixture users" \
  "$COMPOSE exec -T db mariadb -u'$DB_USER' -p'$DB_PASSWORD' '$DB_NAME' -e \"DELETE FROM users_permissions WHERE user_id IN (${ZERO_ID},${RO_ID},${WRITER_ID}); DELETE FROM users WHERE id IN (${ZERO_ID},${RO_ID},${WRITER_ID});\" >/dev/null 2>&1 || true"

mysql_x "INSERT INTO users_permissions (user_id,permission_id,allow,created,updated) VALUES (${WRITER_ID},'default_notifications_write',1,NOW(),NOW());"
mysql_x "INSERT INTO users_permissions (user_id,permission_id,allow,created,updated) VALUES (${RO_ID},'default_extensions_read',1,NOW(),NOW());"

seed_fixtures
SNAP0="$(snap_fixture)"
if [ -z "$SNAP0" ]; then harness_blocked "fixture notifications were not inserted"; fi

rm -f "$ADMIN_JAR" "$ZERO_JAR" "$RO_JAR" "$WRITER_JAR" "$NONE_JAR"
code="$(request "$ADMIN_JAR" POST /index.php/auth/login "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}")"
if [ "$code" = 302 ]; then pass 'admin login' "HTTP $code"; else harness_blocked "admin login did not return 302 (HTTP $code)"; fi
code="$(request "$ZERO_JAR" POST /index.php/auth/login "user=${ZERO_USER}&password=${ZERO_PASSWORD}")"
if [ "$code" = 302 ]; then pass 'zero-perm login' "HTTP $code"; else harness_blocked "zero-perm login HTTP $code"; fi
code="$(request "$RO_JAR" POST /index.php/auth/login "user=${RO_USER}&password=${RO_PASSWORD}")"
if [ "$code" = 302 ]; then pass 'read-only login' "HTTP $code"; else harness_blocked "read-only login HTTP $code"; fi
code="$(request "$WRITER_JAR" POST /index.php/auth/login "user=${WRITER_USER}&password=${WRITER_PASSWORD}")"
if [ "$code" = 302 ]; then pass 'writer login' "HTTP $code"; else harness_blocked "writer login HTTP $code"; fi

ADMIN_CSRF="$(harness_csrf_token "$ADMIN_JAR" "$BASE_URL")"
ZERO_CSRF="$(harness_csrf_token "$ZERO_JAR" "$BASE_URL")"
RO_CSRF="$(harness_csrf_token "$RO_JAR" "$BASE_URL")"
WRITER_CSRF="$(harness_csrf_token "$WRITER_JAR" "$BASE_URL")"
if [ -z "$ADMIN_CSRF" ] || [ -z "$ZERO_CSRF" ] || [ -z "$RO_CSRF" ] || [ -z "$WRITER_CSRF" ]; then
    harness_blocked "could not read one or more session CSRF tokens"
fi

# --- unauthenticated ---
code="$(request "$NONE_JAR" GET '/index.php/default/notifications?id=all')"
if [ "$code" = 200 ] && is_login_page; then
    pass 'unauthenticated GET notifications serves login' "HTTP $code"
else
    fail 'unauthenticated GET notifications serves login' "HTTP $code"
fi
BEFORE="$(snap_fixture)"
code="$(request "$NONE_JAR" POST /index.php/default/notifications/mark-read "id=${ID_A}&snep_csrf_token=deadbeef")"
AFTER="$(snap_fixture)"
if { [ "$code" = 200 ] && is_login_page; } || [ "$code" = 302 ]; then
    if [ "$BEFORE" = "$AFTER" ]; then
        pass 'unauthenticated POST mark-read does not mutate' "HTTP $code, snapshot unchanged"
    else
        fail 'unauthenticated POST mark-read does not mutate' "HTTP $code before=$BEFORE after=$AFTER"
    fi
else
    fail 'unauthenticated POST mark-read does not mutate' "HTTP $code"
fi

# --- authenticated read stays open ---
code="$(request "$ZERO_JAR" GET '/index.php/default/notifications?id=all')"
if [ "$code" = 200 ]; then
    pass 'zero-perm GET notifications list allowed' "HTTP $code"
else
    fail 'zero-perm GET notifications list allowed' "HTTP $code"
fi

# --- zero-perm cannot mark-read ---
BEFORE="$(snap_fixture)"
code="$(post_form "$ZERO_JAR" /index.php/default/notifications/mark-read "id=${ID_A}&snep_csrf_token=${ZERO_CSRF}")"
AFTER="$(snap_fixture)"
if [ "$code" = 302 ] && redirects_to_permission_error && [ "$BEFORE" = "$AFTER" ] && [ "$(row_read "$ID_A")" = 0 ]; then
    pass 'zero-perm POST mark-read denied; DB unchanged' "HTTP $code"
else
    fail 'zero-perm POST mark-read denied; DB unchanged' "HTTP $code before=$BEFORE after=$AFTER loc=$(grep -i Location "$HEADERS" | tr -d '\r')"
fi

# --- read-only cannot mark-read ---
BEFORE="$(snap_fixture)"
code="$(post_form "$RO_JAR" /index.php/default/notifications/mark-read "id=${ID_A}&snep_csrf_token=${RO_CSRF}")"
AFTER="$(snap_fixture)"
if [ "$code" = 302 ] && redirects_to_permission_error && [ "$BEFORE" = "$AFTER" ]; then
    pass 'read-only POST mark-read denied; DB unchanged' "HTTP $code"
else
    fail 'read-only POST mark-read denied; DB unchanged' "HTTP $code before=$BEFORE after=$AFTER"
fi

# --- CSRF required for writer ---
BEFORE="$(snap_fixture)"
code="$(post_form "$WRITER_JAR" /index.php/default/notifications/mark-read "id=${ID_A}")"
AFTER="$(snap_fixture)"
if [ "$code" = 403 ] && [ "$BEFORE" = "$AFTER" ]; then
    pass 'writer mark-read without CSRF rejected; DB unchanged' "HTTP $code"
else
    fail 'writer mark-read without CSRF rejected; DB unchanged' "HTTP $code before=$BEFORE after=$AFTER"
fi

# --- GET mark-read remains non-mutating ---
BEFORE="$(snap_fixture)"
code="$(request "$WRITER_JAR" GET /index.php/default/notifications/mark-read)"
AFTER="$(snap_fixture)"
if [ "$code" = 405 ] && [ "$BEFORE" = "$AFTER" ]; then
    pass 'GET mark-read rejected (405); DB unchanged' "HTTP $code"
else
    fail 'GET mark-read rejected (405); DB unchanged' "HTTP $code before=$BEFORE after=$AFTER"
fi

# --- writer with default_notifications_write may mark-read ---
BEFORE="$(snap_fixture)"
code="$(post_form "$WRITER_JAR" /index.php/default/notifications/mark-read "id=${ID_A}&snep_csrf_token=${WRITER_CSRF}")"
AFTER="$(snap_fixture)"
if [ "$code" = 200 ] && [ "$(row_read "$ID_A")" = 1 ] && [ "$(row_read "$ID_B")" = 0 ]; then
    pass 'writer mark-read updates shared row only' "HTTP $code read(A)=1 read(B)=0"
else
    fail 'writer mark-read updates shared row only' "HTTP $code before=$BEFORE after=$AFTER readA=$(row_read "$ID_A") readB=$(row_read "$ID_B")"
fi

if [ "$(row_read "$ID_A")" = 1 ]; then
    pass 'shared cache visible across users after mark-read' "id_itc=${ID_A} read=1 for all operators"
else
    fail 'shared cache visible across users after mark-read' "read=$(row_read "$ID_A")"
fi

# --- zero-perm cannot remove ---
BEFORE="$(snap_fixture)"
code="$(request "$ZERO_JAR" GET /index.php/default/notifications/remove/id/${ID_B})"
if [ "$code" = 302 ] && redirects_to_permission_error; then
    pass 'zero-perm GET remove form denied' "HTTP $code"
else
    fail 'zero-perm GET remove form denied' "HTTP $code loc=$(grep -i Location "$HEADERS" | tr -d '\r')"
fi
ZERO_CSRF="$(harness_csrf_token "$ZERO_JAR" "$BASE_URL")"
code="$(post_form "$ZERO_JAR" /index.php/default/notifications/remove/id/${ID_B} "id=${ID_B}&delete=Delete&snep_csrf_token=${ZERO_CSRF}")"
AFTER="$(snap_fixture)"
if [ "$code" = 302 ] && redirects_to_permission_error && [ "$BEFORE" = "$AFTER" ] && [ "$(row_exists "$ID_B")" = 1 ]; then
    pass 'zero-perm POST remove denied; DB unchanged' "HTTP $code"
else
    fail 'zero-perm POST remove denied; DB unchanged' "HTTP $code before=$BEFORE after=$AFTER existsB=$(row_exists "$ID_B")"
fi

# --- writer remove with CSRF deletes only the targeted shared row ---
WRITER_CSRF="$(harness_csrf_token "$WRITER_JAR" "$BASE_URL")"
BEFORE="$(snap_fixture)"
code="$(post_form "$WRITER_JAR" /index.php/default/notifications/remove/id/${ID_B} "id=${ID_B}&delete=Delete&snep_csrf_token=${WRITER_CSRF}")"
AFTER="$(snap_fixture)"
if [ "$code" = 302 ] && [ "$(row_exists "$ID_B")" = 0 ] && [ "$(row_exists "$ID_C")" = 1 ] && [ "$(row_exists "$ID_A")" = 1 ]; then
    pass 'writer remove deletes only targeted shared row' "HTTP $code existsB=0 existsA=1 existsC=1"
else
    fail 'writer remove deletes only targeted shared row' "HTTP $code before=$BEFORE after=$AFTER existsA=$(row_exists "$ID_A") existsB=$(row_exists "$ID_B") existsC=$(row_exists "$ID_C")"
fi

# --- unknown / arbitrary id must not disturb unrelated fixture rows ---
WRITER_CSRF="$(harness_csrf_token "$WRITER_JAR" "$BASE_URL")"
BEFORE="$(snap_fixture)"
code="$(post_form "$WRITER_JAR" /index.php/default/notifications/mark-read "id=999999001&snep_csrf_token=${WRITER_CSRF}")"
AFTER="$(snap_fixture)"
if [ "$code" = 200 ] && [ "$BEFORE" = "$AFTER" ]; then
    pass 'mark-read unknown id leaves fixtures unchanged' "HTTP $code"
else
    fail 'mark-read unknown id leaves fixtures unchanged' "HTTP $code before=$BEFORE after=$AFTER"
fi

BEFORE="$(snap_fixture)"
code="$(post_form "$WRITER_JAR" /index.php/default/notifications/remove/id/999999002 "id=999999002&delete=Delete&snep_csrf_token=${WRITER_CSRF}")"
AFTER="$(snap_fixture)"
if [ "$code" = 302 ] && [ "$BEFORE" = "$AFTER" ] && [ "$(row_exists "$ID_C")" = 1 ]; then
    pass 'remove unknown id leaves fixtures unchanged' "HTTP $code"
else
    fail 'remove unknown id leaves fixtures unchanged' "HTTP $code before=$BEFORE after=$AFTER"
fi

# --- superuser still supported ---
ADMIN_CSRF="$(harness_csrf_token "$ADMIN_JAR" "$BASE_URL")"
code="$(post_form "$ADMIN_JAR" /index.php/default/notifications/mark-read "id=${ID_C}&snep_csrf_token=${ADMIN_CSRF}")"
if [ "$code" = 200 ] && [ "$(row_read "$ID_C")" = 1 ]; then
    pass 'superuser mark-read still works' "HTTP $code read(C)=1"
else
    fail 'superuser mark-read still works' "HTTP $code readC=$(row_read "$ID_C")"
fi

mysql_x "DELETE FROM core_notifications WHERE title LIKE '${FIXTURE_PREFIX}%';"
mysql_x "DELETE FROM users_permissions WHERE user_id IN (${ZERO_ID},${RO_ID},${WRITER_ID});"
mysql_x "DELETE FROM users WHERE id IN (${ZERO_ID},${RO_ID},${WRITER_ID});"

harness_complete
