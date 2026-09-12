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

# TASK-0026G: every authenticated POST below now needs a valid
# snep_csrf_token (Snep_CsrfPlugin) -- fetched once per jar right after
# that jar's own login succeeded, since the token is a stable per-session
# value, not one-shot/rotating.
ADMIN_CSRF="$(harness_csrf_token "$ADMIN_JAR" "$BASE_URL")"
if [ -z "$ADMIN_CSRF" ]; then harness_blocked "could not read the admin session's CSRF token"; fi

code="$(request "$RESTRICTED_JAR" GET /index.php/index/add)"
if [ "$code" = 200 ] && grep -q 'var controller = "index"' "$BODY"; then pass 'restricted basic dashboard works' "HTTP $code"; else fail 'restricted basic dashboard works' "HTTP $code"; fi

code="$(request "$RESTRICTED_JAR" GET /index.php/default/parameters/language)"
if [ "$code" = 302 ] && redirects_to_permission_error; then pass 'restricted direct F16 action fails closed' "HTTP $code, Location: permission/error"; else fail 'restricted direct F16 action fails closed' "HTTP $code"; fi

code="$(request "$RESTRICTED_JAR" GET /index.php/default/nonexistent-sensitive-action)"
if [ "$code" = 302 ] && redirects_to_permission_error; then pass 'unknown/unregistered action fails closed' "HTTP $code, Location: permission/error"; else fail 'unknown/unregistered action fails closed' "HTTP $code"; fi

echo '==> Supported UI grant/revoke lifecycle'
code="$(request "$ADMIN_JAR" POST /index.php/default/users/permission/id/$id "user=$id&$READ_PERMISSION=1&$AJAX_PERMISSION=1&snep_csrf_token=$ADMIN_CSRF")"
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
code="$(request "$ADMIN_JAR" POST /index.php/default/users/permission/id/$id "user=$id&snep_csrf_token=$ADMIN_CSRF")"
if [ "$code" = 302 ]; then pass 'admin UI revokes permissions' "HTTP $code"; else fail 'admin UI revokes permissions' "HTTP $code"; fi
code="$(request "$RESTRICTED_JAR" GET /index.php/default/errors-tdm)"
if [ "$code" = 302 ] && redirects_to_permission_error; then pass 'permission removal revokes access' "HTTP $code, Location: permission/error"; else fail 'permission removal revokes access' "HTTP $code"; fi

code="$(request "$ADMIN_JAR" GET /index.php/default/users/permission/id/$id)"
if [ "$code" = 200 ] && grep -q 'name="user"' "$BODY"; then pass 'admin privileged path works' "HTTP $code"; else fail 'admin privileged path works' "HTTP $code"; fi

echo '==> TASK-0034L: ParametersController::indexAction() POST authorization boundary'
# Reproduces and closes the read-permission-gates-write gap TASK-0034J
# (D3 follow-up) flagged: before this task, Snep_PermissionPlugin
# classified ANY action literally named "index" as 'read', regardless of
# HTTP method -- so a user granted only default_parameters_read could
# still POST through ParametersController::indexAction() and rewrite
# setup.conf (13+ fields, including DB/AMI credentials) and propagate the
# PBX call language. This is distinct from the F16 check above, which
# only ever proved the ZERO-permission case against the sibling
# languageAction() -- never the read-permission-granted case against
# indexAction(). See docs/tasks/0034l-parameters-controller-authorization-
# boundary-hardening.md. $id/$RESTRICTED_JAR are reset to zero
# permissions by the revoke immediately above, a clean baseline.
CFG=/var/www/html/snep/includes/setup.conf
EMP_BEFORE="$($COMPOSE exec -T app grep '^emp_nome' "$CFG")"

# emp_nome (company display name) is a harmless, reversible field --
# deliberately not language, which TASK-0034K already exercised
# end-to-end; this proves the boundary itself, not the language pipeline.
parameters_save() {
    # $1=jar $2=emp_nome value $3=csrf token
    request "$1" POST /index.php/default/parameters/index \
        "emp_nome=$2&debug=&show_help=&hide_routes=&language=en&locale=pt_BR&timezone=America%2FSao_Paulo&peers_digits=4&ip_sock=senma-ami&user_sock=snep&pass_sock=change-me-for-local-development&mail=noreply%40sneplivre.com.br&linelimit=50&conference_app=C&db_dbname=snep&db_host=db&db_username=snep&db_password=change-me-for-local-development&application=mixmonitor&flag=b&record_mp3=&record_format=wav&path_voz=%2Fvar%2Fwww%2Fhtml%2Fsnep%2Farquivos%2F&path_voz_bkp=%2Fvar%2Fwww%2Fhtml%2Fsnep%2Farquivos%2F&valor_controle_qualidade=250&snep_csrf_token=$3"
}

code="$(request "$ADMIN_JAR" POST /index.php/default/users/permission/id/$id "user=$id&default_parameters_read=1&snep_csrf_token=$ADMIN_CSRF")"
if [ "$code" = 302 ]; then pass 'admin grants read-only Parameters permission' "HTTP $code"; else fail 'admin grants read-only Parameters permission' "HTTP $code"; fi

code="$(request "$RESTRICTED_JAR" GET /index.php/default/parameters)"
RESTRICTED_CSRF="$(grep -o 'name="csrf-token" content="[^"]*"' "$BODY" | sed -E 's/.*content="([^"]*)".*/\1/')"
if [ "$code" = 200 ] && [ -n "$RESTRICTED_CSRF" ]; then pass 'read-only user can render Parameters' "HTTP $code"; else fail 'read-only user can render Parameters' "HTTP $code"; fi

code="$(parameters_save "$RESTRICTED_JAR" 'TASK0034L-SHOULD-BE-DENIED' "$RESTRICTED_CSRF")"
EMP_AFTER_DENIED="$($COMPOSE exec -T app grep '^emp_nome' "$CFG")"
if [ "$code" = 302 ] && redirects_to_permission_error && [ "$EMP_BEFORE" = "$EMP_AFTER_DENIED" ]; then
    pass 'read-only user cannot mutate Parameters via indexAction POST' "HTTP $code, Location: permission/error, setup.conf unchanged"
else
    fail 'read-only user cannot mutate Parameters via indexAction POST' "HTTP $code, setup.conf before=[$EMP_BEFORE] after=[$EMP_AFTER_DENIED]"
fi

# GET must not mutate, regardless of permission -- structural
# (indexAction() only ever processes $this->_request->getPost()), proven
# here with the fully-privileged admin session so a failure could only be
# the GET/POST branch itself, not an authorization side effect.
code="$(request "$ADMIN_JAR" GET "/index.php/default/parameters/index?emp_nome=TASK0034L-GET-SHOULD-NOT-APPLY")"
EMP_AFTER_GET="$($COMPOSE exec -T app grep '^emp_nome' "$CFG")"
if [ "$code" = 200 ] && [ "$EMP_BEFORE" = "$EMP_AFTER_GET" ]; then
    pass 'GET to parameters/index never mutates' "HTTP $code, setup.conf unchanged"
else
    fail 'GET to parameters/index never mutates' "HTTP $code, setup.conf before=[$EMP_BEFORE] after=[$EMP_AFTER_GET]"
fi

code="$(request "$ADMIN_JAR" POST /index.php/default/users/permission/id/$id "user=$id&default_parameters_read=1&default_parameters_write=1&snep_csrf_token=$ADMIN_CSRF")"
if [ "$code" = 302 ]; then pass 'admin grants Parameters write permission' "HTTP $code"; else fail 'admin grants Parameters write permission' "HTTP $code"; fi

code="$(request "$RESTRICTED_JAR" GET /index.php/default/parameters)"
RESTRICTED_CSRF="$(grep -o 'name="csrf-token" content="[^"]*"' "$BODY" | sed -E 's/.*content="([^"]*)".*/\1/')"
code="$(parameters_save "$RESTRICTED_JAR" 'TASK0034L-SHOULD-SUCCEED' "$RESTRICTED_CSRF")"
EMP_AFTER_WRITE="$($COMPOSE exec -T app grep '^emp_nome' "$CFG")"
if [ "$code" = 302 ] && printf '%s' "$EMP_AFTER_WRITE" | grep -q 'TASK0034L-SHOULD-SUCCEED'; then
    pass 'write-authorized user can mutate Parameters via indexAction POST' "HTTP $code, setup.conf updated"
else
    fail 'write-authorized user can mutate Parameters via indexAction POST' "HTTP $code, setup.conf=[$EMP_AFTER_WRITE]"
fi

ORIGINAL_EMP_NOME="$(printf '%s' "$EMP_BEFORE" | sed -E 's/^emp_nome = "(.*)"$/\1/')"
code="$(parameters_save "$RESTRICTED_JAR" "$ORIGINAL_EMP_NOME" "$RESTRICTED_CSRF")"
EMP_RESTORED="$($COMPOSE exec -T app grep '^emp_nome' "$CFG")"
if [ "$EMP_BEFORE" = "$EMP_RESTORED" ]; then pass 'emp_nome restored to its original value' "$EMP_RESTORED"; else fail 'emp_nome restored to its original value' "expected [$EMP_BEFORE] got [$EMP_RESTORED]"; fi

code="$(request "$ADMIN_JAR" POST /index.php/default/users/permission/id/$id "user=$id&snep_csrf_token=$ADMIN_CSRF")"
if [ "$code" = 302 ]; then pass 'Parameters permissions revoked back to baseline' "HTTP $code"; else fail 'Parameters permissions revoked back to baseline' "HTTP $code"; fi

echo '==> TASK-0034M: same-shape indexAction()+POST write-boundary hardening'
# TASK-0034L's own HIDDEN-WRITER INVENTORY named CnlController as a
# concretely-verified carry-forward of the exact same read-implies-write
# shape closed above for Parameters; TASK-0034M's own re-audit of the
# ~20 other candidate controllers found three more with the identical
# mechanism (ModuleSettingsController, ErrorsKhompController,
# ErrorsTdmController) plus one (ConferenceRoomsController) that already
# had an unused "write" child. CnlController itself gets its own
# dedicated, more extensive suite (upload/CSRF/zip-slip/legitimate-import)
# in scripts/cnl-upload-authorization-security-smoke-test.sh; this block
# only proves the shared PermissionPlugin::$writeOnPostIndex boundary for
# the other four, reusing the same $id/$RESTRICTED_JAR fixture (reset to
# zero permissions by the revoke immediately above).
module_settings_post() { # $1=jar $2=csrf
    request "$1" POST /index.php/default/module-settings "signup=1&snep_csrf_token=$2"
}
errors_khomp_post() { request "$1" POST /index.php/default/errors-khomp "dummy=1&snep_csrf_token=$2"; }
errors_tdm_post()   { request "$1" POST /index.php/default/errors-tdm   "dummy=1&snep_csrf_token=$2"; }
conference_rooms_post() {
    request "$1" POST /index.php/default/conference-rooms \
        "costCenter=&activate=&password=&rec=&snep_csrf_token=$2"
}

CONF_FILE=/etc/asterisk/snep/snep-conferences.conf
AUTHCONF_FILE=/etc/asterisk/snep/snep-authconferences.conf
CONF_BACKUP="$TMPDIR_AUTH/snep-conferences.conf.bak"
AUTHCONF_BACKUP="$TMPDIR_AUTH/snep-authconferences.conf.bak"
$COMPOSE exec -T app cat "$CONF_FILE" > "$CONF_BACKUP"
$COMPOSE exec -T app cat "$AUTHCONF_FILE" > "$AUTHCONF_BACKUP"
CONF_BEFORE_MD5="$(md5sum "$CONF_BACKUP" | awk '{print $1}')"
AUTHCONF_BEFORE_MD5="$(md5sum "$AUTHCONF_BACKUP" | awk '{print $1}')"
# `docker compose cp` writes the destination as root, dropping the
# original owner/group/mode (confirmed live: it left both files
# 501:dialout/644 instead of the app image's own 997:senma-config/664 --
# harmless to this file's own content, but Snep_Inspector's "Environment
# for AGI SNEP" check independently verifies these two paths are
# is_writable() by the web server's own group, so a dropped ownership
# silently breaks an unrelated System Status panel). Captured once here
# and re-applied after every cp restore below, cp restore included.
CONF_OWNER_MODE="$($COMPOSE exec -T app stat -c '%u:%g %a' "$CONF_FILE" | tr -d '\r')"
AUTHCONF_OWNER_MODE="$($COMPOSE exec -T app stat -c '%u:%g %a' "$AUTHCONF_FILE" | tr -d '\r')"
restore_conference_files() {
    $COMPOSE cp "$CONF_BACKUP" app:"$CONF_FILE"
    $COMPOSE cp "$AUTHCONF_BACKUP" app:"$AUTHCONF_FILE"
    $COMPOSE exec -T -u root app chown "${CONF_OWNER_MODE%% *}" "$CONF_FILE"
    $COMPOSE exec -T -u root app chmod "${CONF_OWNER_MODE##* }" "$CONF_FILE"
    $COMPOSE exec -T -u root app chown "${AUTHCONF_OWNER_MODE%% *}" "$AUTHCONF_FILE"
    $COMPOSE exec -T -u root app chmod "${AUTHCONF_OWNER_MODE##* }" "$AUTHCONF_FILE"
}
harness_register_best_effort_cleanup "restore snep-conferences.conf/snep-authconferences.conf" \
    "restore_conference_files"

for entry in \
    'module-settings|module_settings_post' \
    'errors-khomp|errors_khomp_post' \
    'errors-tdm|errors_tdm_post' \
    'conference-rooms|conference_rooms_post'
do
    slug="${entry%%|*}"
    poster="${entry##*|}"
    resource="default_${slug}"

    code="$(request "$ADMIN_JAR" POST /index.php/default/users/permission/id/$id "user=$id&${resource}_read=1&snep_csrf_token=$ADMIN_CSRF")"
    if [ "$code" = 302 ]; then pass "admin grants read-only $slug permission" "HTTP $code"; else fail "admin grants read-only $slug permission" "HTTP $code"; fi

    code="$(request "$RESTRICTED_JAR" GET /index.php/default/$slug)"
    RESTRICTED_CSRF="$(grep -o 'name="csrf-token" content="[^"]*"' "$BODY" | sed -E 's/.*content="([^"]*)".*/\1/')"
    if [ "$code" != 302 ]; then pass "read-only user can reach $slug (not permission-denied)" "HTTP $code"; else fail "read-only user can reach $slug (not permission-denied)" "HTTP $code"; fi

    code="$("$poster" "$RESTRICTED_JAR" "$RESTRICTED_CSRF")"
    if [ "$code" = 302 ] && redirects_to_permission_error; then
        pass "read-only user cannot mutate $slug via indexAction POST" "HTTP $code, Location: permission/error"
    else
        fail "read-only user cannot mutate $slug via indexAction POST" "HTTP $code"
    fi

    code="$(request "$ADMIN_JAR" POST /index.php/default/users/permission/id/$id "user=$id&${resource}_read=1&${resource}_write=1&snep_csrf_token=$ADMIN_CSRF")"
    if [ "$code" = 302 ]; then pass "admin grants $slug write permission" "HTTP $code"; else fail "admin grants $slug write permission" "HTTP $code"; fi

    code="$(request "$RESTRICTED_JAR" GET /index.php/default/$slug)"
    RESTRICTED_CSRF="$(grep -o 'name="csrf-token" content="[^"]*"' "$BODY" | sed -E 's/.*content="([^"]*)".*/\1/')"
    code="$("$poster" "$RESTRICTED_JAR" "$RESTRICTED_CSRF")"
    if [ "$code" != 302 ] || ! redirects_to_permission_error; then
        pass "write-authorized user can mutate $slug via indexAction POST" "HTTP $code (not permission-denied)"
    else
        fail "write-authorized user can mutate $slug via indexAction POST" "HTTP $code"
    fi

    code="$(request "$ADMIN_JAR" POST /index.php/default/users/permission/id/$id "user=$id&snep_csrf_token=$ADMIN_CSRF")"
    if [ "$code" = 302 ]; then pass "$slug permissions revoked back to baseline" "HTTP $code"; else fail "$slug permissions revoked back to baseline" "HTTP $code"; fi
done

# ConferenceRoomsController's write-authorized POST above genuinely
# rewrites both Asterisk conference config files (proving that path is
# reachable is the point of the check above) -- restore the exact
# byte-for-byte snapshot taken before this block ran, so this suite
# never leaves telephony-consumed config mutated, and prove the restore.
restore_conference_files
CONF_AFTER_MD5="$($COMPOSE exec -T app md5sum "$CONF_FILE" | awk '{print $1}')"
AUTHCONF_AFTER_MD5="$($COMPOSE exec -T app md5sum "$AUTHCONF_FILE" | awk '{print $1}')"
if [ "$CONF_AFTER_MD5" = "$CONF_BEFORE_MD5" ] && [ "$AUTHCONF_AFTER_MD5" = "$AUTHCONF_BEFORE_MD5" ]; then
    pass 'snep-conferences.conf/snep-authconferences.conf restored to their original content' "$CONF_AFTER_MD5 / $AUTHCONF_AFTER_MD5"
else
    fail 'snep-conferences.conf/snep-authconferences.conf restored to their original content' "expected [$CONF_BEFORE_MD5 / $AUTHCONF_BEFORE_MD5] got [$CONF_AFTER_MD5 / $AUTHCONF_AFTER_MD5]"
fi
CONF_AFTER_OWNER_MODE="$($COMPOSE exec -T app stat -c '%u:%g %a' "$CONF_FILE" | tr -d '\r')"
AUTHCONF_AFTER_OWNER_MODE="$($COMPOSE exec -T app stat -c '%u:%g %a' "$AUTHCONF_FILE" | tr -d '\r')"
if [ "$CONF_AFTER_OWNER_MODE" = "$CONF_OWNER_MODE" ] && [ "$AUTHCONF_AFTER_OWNER_MODE" = "$AUTHCONF_OWNER_MODE" ]; then
    pass 'snep-conferences.conf/snep-authconferences.conf restored to their original owner/mode' "$CONF_AFTER_OWNER_MODE / $AUTHCONF_AFTER_OWNER_MODE"
else
    fail 'snep-conferences.conf/snep-authconferences.conf restored to their original owner/mode' "expected [$CONF_OWNER_MODE / $AUTHCONF_OWNER_MODE] got [$CONF_AFTER_OWNER_MODE / $AUTHCONF_AFTER_OWNER_MODE]"
fi

echo '==> Restart persistence'
$COMPOSE restart app >/dev/null
for _ in $(seq 1 30); do
    if curl -sS -o /dev/null "$BASE_URL/index.php/auth/login"; then break; fi
    sleep 1
done
code="$(request "$RESTRICTED_JAR" GET /index.php/default/errors-tdm)"
if [ "$code" = 302 ] && redirects_to_permission_error; then pass 'authorization remains correct after restart' "HTTP $code, Location: permission/error"; else fail 'authorization remains correct after restart' "HTTP $code"; fi

harness_complete
