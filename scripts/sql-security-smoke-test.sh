#!/bin/bash
#
# TASK-0026C SQL boundary hardening focused security smoke test.
#
# Exercises every confirmed F7-F11 SQL-injection boundary from
# docs/tasks/0026-pre-pilot-security-release-audit.md (re-traced and
# expanded in docs/tasks/0026c-sql-boundary-hardening.md), through
# SENMA's own real, authenticated HTTP application flows -- never a
# direct database connection, never a raw exploit. For each boundary:
#   1. a normal valid request still works exactly as before;
#   2. a SQL-shaped "always false" value behaves as inert literal data;
#   3. a SQL-shaped "always true" / boolean-oracle value behaves as
#      inert literal data too -- proven by a CANARY fixture that must
#      remain completely unaffected;
#   4. cleanup, via the same supported application paths used elsewhere
#      in this project's smoke suites.
#
# Every payload below is a harmless, non-destructive, syntax-shaped
# string (quotes, boolean-always-true/false fragments) applied only to
# fixtures this script itself owns -- never a real exploit chain, never
# password/schema/account extraction, matching this task's own explicit
# "do not extract secrets, do not use destructive payloads" instruction.
#
# Deliberately separate from `make smoke` -- never run implicitly by it.
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
BASE_URL="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
TEST_USER="admin"
TEST_PASSWORD="SmokeTest123!"
FIXTURE_MARKER="task0026c-sql"

log() { harness_log "$@"; }

db_query() {
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
        "${DB_NAME:-snep}" -N -e "$1"
}

COOKIEJAR=""
RESTRICTED_JAR=""

http_login() {
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null \
        -d "user=${TEST_USER}&password=${TEST_PASSWORD}" "${BASE_URL}/index.php/auth/login"
}

# request <jar> <method> <path> [postdata] -- returns HTTP code, leaves
# the response body in $BODY and headers in $HEADERS (globals, like
# authorization-smoke-test.sh's own request() helper).
BODY=""
HEADERS=""
request() {
    local jar="$1" method="$2" path="$3" data="${4:-}"
    if [ "$method" = POST ]; then
        curl -sS -b "$jar" -c "$jar" -D "$HEADERS" -o "$BODY" -w '%{http_code}' -d "$data" "${BASE_URL}${path}"
    else
        curl -sS -b "$jar" -c "$jar" -D "$HEADERS" -o "$BODY" -w '%{http_code}' "${BASE_URL}${path}"
    fi
}

redirects_to_permission_error() {
    grep -qi '^Location:.*permission/error' "$HEADERS"
}

fatal_count() {
    local n
    n="$($COMPOSE exec -T app sh -c 'grep -c "Fatal error" /var/log/apache2/mag-error.log 2>/dev/null' 2>/dev/null | tr -d '\r\n ')"
    echo "${n:-0}"
}

# --- 0. Preflight ------------------------------------------------------

harness_require_containers app db
harness_require_env DB_USER DB_PASSWORD DB_NAME

BODY="$(mktemp)"
HEADERS="$(mktemp)"
harness_register_best_effort_cleanup "request temp files" "rm -f '$BODY' '$HEADERS'"

COOKIEJAR="$(mktemp)"
harness_register_best_effort_cleanup "admin cookie jar" "rm -f '$COOKIEJAR'"
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${TEST_PASSWORD}');" 2>/dev/null | tr -d '\r')"
if [ -z "$TEST_HASH" ]; then
    harness_blocked "could not compute the ${TEST_USER} password hash via the app container"
fi
db_query "UPDATE users SET password = '${TEST_HASH}' WHERE name = '${TEST_USER}';" >&2
http_login

# TASK-0026G: every authenticated POST below now needs a valid
# snep_csrf_token (Snep_CsrfPlugin) -- fetched once, reused for the rest
# of this script's run (the token is a stable per-session value, not
# one-shot/rotating). RESTRICTED_JAR only ever performs GETs in this
# script, so it needs no token.
ADMIN_CSRF="$(harness_csrf_token "$COOKIEJAR" "$BASE_URL")"
if [ -z "$ADMIN_CSRF" ]; then harness_blocked "could not read the admin session's CSRF token"; fi

FATALS_BEFORE="$(fatal_count)"
log "==> baseline PHP Fatal Error count: ${FATALS_BEFORE}"

# --- 0b. A zero-permission user is still denied on every boundary below -
# (Phase 6: prove authorization stays intact -- not re-testing TASK-0026A
# itself, just confirming this task didn't accidentally weaken it.)

RESTRICTED_USER="task0026c-restricted"
RESTRICTED_PASSWORD="Task0026cRestricted!"
RID="$(db_query "SELECT id FROM users WHERE name='${RESTRICTED_USER}';")"
RESTRICTED_HASH="$($COMPOSE exec -T app php -r "echo md5('${RESTRICTED_PASSWORD}');" 2>/dev/null | tr -d '\r')"
if [ -z "$RID" ]; then
    db_query "INSERT INTO users (name,password,email,dashboard,profile_id,created,updated) VALUES ('${RESTRICTED_USER}','${RESTRICTED_HASH}','${RESTRICTED_USER}@example.test','',1,NOW(),NOW());"
    RID="$(db_query "SELECT id FROM users WHERE name='${RESTRICTED_USER}';")"
fi
if [ -z "$RID" ]; then
    harness_blocked "could not provision the zero-permission restricted test user"
fi
# TASK-0027-established pattern: a deliberately persistent, reusable
# dev-only fixture (like authorization-smoke-test.sh's own restricted
# user), reset to a known zero-permission baseline every run.
db_query "UPDATE users SET password='${RESTRICTED_HASH}' WHERE id=${RID}; DELETE FROM users_permissions WHERE user_id=${RID};" >/dev/null
harness_register_best_effort_cleanup "restricted user permissions reset to baseline" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}' -e \"DELETE FROM users_permissions WHERE user_id=${RID};\" >/dev/null"

RESTRICTED_JAR="$(mktemp)"
harness_register_best_effort_cleanup "restricted cookie jar" "rm -f '$RESTRICTED_JAR'"
curl -sS -c "$RESTRICTED_JAR" -b "$RESTRICTED_JAR" -o /dev/null \
    -d "user=${RESTRICTED_USER}&password=${RESTRICTED_PASSWORD}" "${BASE_URL}/index.php/auth/login"

for boundary_path in "/index.php/default/extensions" "/index.php/default/users" "/index.php/default/profiles" "/index.php/default/trunks" "/index.php/default/export-data"; do
    code="$(request "$RESTRICTED_JAR" GET "$boundary_path")"
    if [ "$code" = 302 ] && redirects_to_permission_error; then
        harness_ok "authorization intact: ${boundary_path}" "zero-permission user denied (HTTP 302, Location: permission/error)"
    else
        harness_bad "authorization intact: ${boundary_path}" "expected 302+permission/error, got HTTP ${code}"
    fi
done

# =============================================================================
# F7 -- Extensions (ExtensionsController + Snep_Extensions_Manager)
# =============================================================================

log "==> F7: Extensions boundary"

EXT_F7=1085
EXT_F7_SECRET="${FIXTURE_MARKER}-f7"
EXT_F7_CANARY=1084
EXT_F7_CANARY_SECRET="${FIXTURE_MARKER}-f7-canary"

for ext in "$EXT_F7" "$EXT_F7_CANARY"; do
    existing="$(db_query "SELECT canal FROM peers WHERE name='${ext}';")"
    if [ -n "$existing" ]; then
        harness_blocked "peers row for extension '${ext}' already exists -- refusing to overwrite. Remove it manually first."
    fi
done

create_extension() {
    local ext="$1" secret="$2" name="$3"
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$BODY" -w '%{http_code}' \
        --data-urlencode "name=${name}" \
        --data-urlencode "exten=${ext}" \
        --data-urlencode "technology=pjsip" \
        --data-urlencode "password=${secret}" \
        --data-urlencode "passwordpadlock=" \
        --data-urlencode "calllimit=1" \
        --data-urlencode "email=" \
        --data-urlencode "exten_group[]=1" \
        --data-urlencode "pickup_group=" \
        --data-urlencode "nat_force_rport=1" \
        --data-urlencode "nat_comedia=1" \
        --data-urlencode "qualify=1" \
        --data-urlencode "type=friend" \
        --data-urlencode "directmedia=no" \
        --data-urlencode "dtmf=rfc2833" \
        --data-urlencode "codec=alaw" \
        --data-urlencode "codec1=ulaw" \
        --data-urlencode "codec2=gsm" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/extensions/add"
}

delete_extension() {
    local ext="$1" httpcode
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "id=${ext}" --data-urlencode "delete=Delete" --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/extensions/remove")"
    [ "$httpcode" = "302" ]
}

# 1. Valid request works.
httpcode="$(create_extension "$EXT_F7" "$EXT_F7_SECRET" "SENMA sql-smoke ${EXT_F7}")"
if [ "$httpcode" = "302" ]; then
    harness_register_cleanup "extension ${EXT_F7} (F7 fixture)" "delete_extension ${EXT_F7}"
    harness_ok "F7 valid: create extension" "HTTP 302, extension ${EXT_F7} created via the real UI flow"
else
    harness_blocked "F7 fixture creation failed (HTTP $httpcode) -- see $BODY"
fi
httpcode="$(create_extension "$EXT_F7_CANARY" "$EXT_F7_CANARY_SECRET" "SENMA sql-smoke canary ${EXT_F7_CANARY}")"
if [ "$httpcode" = "302" ]; then
    harness_register_cleanup "extension ${EXT_F7_CANARY} (F7 canary fixture)" "delete_extension ${EXT_F7_CANARY}"
    harness_ok "F7 valid: create canary extension" "HTTP 302, extension ${EXT_F7_CANARY} created (must survive every injection attempt below)"
else
    harness_blocked "F7 canary fixture creation failed (HTTP $httpcode) -- see $BODY"
fi

# 2/3. SQL-shaped values in execAdd()'s UPDATE path (name/callerid/email/
# blf/directmedia/controltype all reach the same hand-built-turned-
# parameterized column set) -- a literal single quote plus a
# boolean-always-true fragment, applied via an EDIT of the fixture.
SQLI_NAME="O'Brien' OR '1'='1"
before_fatals="$(fatal_count)"
httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$BODY" -w '%{http_code}' \
    --data-urlencode "name=${SQLI_NAME}" \
    --data-urlencode "exten=${EXT_F7}" \
    --data-urlencode "technology=pjsip" \
    --data-urlencode "password=${EXT_F7_SECRET}" \
    --data-urlencode "passwordpadlock=" \
    --data-urlencode "calllimit=1" \
    --data-urlencode "email=" \
    --data-urlencode "exten_group[]=1" \
    --data-urlencode "pickup_group=" \
    --data-urlencode "nat_force_rport=1" \
    --data-urlencode "nat_comedia=1" \
    --data-urlencode "qualify=1" \
    --data-urlencode "type=friend" \
    --data-urlencode "directmedia=no" \
    --data-urlencode "dtmf=rfc2833" \
    --data-urlencode "codec=alaw" \
    --data-urlencode "codec1=ulaw" \
    --data-urlencode "codec2=gsm" \
    --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
    "${BASE_URL}/index.php/default/extensions/edit/id/${EXT_F7}")"
after_fatals="$(fatal_count)"
stored_name="$(db_query "SELECT callerid FROM peers WHERE name='${EXT_F7}';")"
canary_untouched="$(db_query "SELECT canal FROM peers WHERE name='${EXT_F7_CANARY}';")"
# editAction() always appends "<exten>" to the posted name before saving
# (a pre-existing, intentional SIP-style "Display Name<extension>"
# caller-ID convention, unrelated to this task) -- expected verbatim,
# not stripped.
if [ "$httpcode" = "302" ] && [ "$before_fatals" = "$after_fatals" ] \
    && [ "$stored_name" = "${SQLI_NAME}<${EXT_F7}>" ] \
    && [ "$canary_untouched" = "PJSIP/${EXT_F7_CANARY}" ]; then
    harness_ok "F7: SQL-shaped callerid becomes literal data" "HTTP 302, no new fatals, callerid stored verbatim ('${stored_name}'), canary extension untouched"
else
    harness_bad "F7: SQL-shaped callerid becomes literal data" "HTTP ${httpcode}, fatals ${before_fatals}->${after_fatals}, stored='${stored_name}', canary='${canary_untouched}'"
fi

# 3b. Boolean-always-true DELETE-shaped id targeting removeAction()'s raw
# lookup -- must not delete (or otherwise affect) the canary fixture.
before_count="$(db_query "SELECT COUNT(*) FROM peers WHERE name IN ('${EXT_F7}','${EXT_F7_CANARY}');")"
httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$BODY" -w '%{http_code}' \
    --data-urlencode "id=${EXT_F7_CANARY}' OR '1'='1" \
    --data-urlencode "delete=Delete" \
    --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
    "${BASE_URL}/index.php/default/extensions/remove")"
after_count="$(db_query "SELECT COUNT(*) FROM peers WHERE name IN ('${EXT_F7}','${EXT_F7_CANARY}');")"
if [ "$before_count" = "$after_count" ] && [ "$after_count" = "2" ]; then
    harness_ok "F7: boolean-injection-shaped delete id has no effect" "HTTP ${httpcode}, both fixtures still present (count ${before_count} -> ${after_count})"
else
    harness_bad "F7: boolean-injection-shaped delete id has no effect" "HTTP ${httpcode}, count ${before_count} -> ${after_count} -- an always-true condition affected real rows"
fi

# 4. Legitimate delete still works (cleanup is exercised for real, not
# just registered).
if delete_extension "$EXT_F7"; then
    harness_ok "F7: legitimate delete still works" "extension ${EXT_F7} removed via the real HTTP flow"
else
    harness_bad "F7: legitimate delete still works" "HTTP delete of ${EXT_F7} did not return 302"
fi

# =============================================================================
# F8 -- Users/Profiles (mass-assignment privilege-escalation boundary)
# =============================================================================

log "==> F8: Users/Profiles boundary"

USER_A="${FIXTURE_MARKER}-f8-user-a"
USER_B="${FIXTURE_MARKER}-f8-user-b"
USER_PW="Task0026cF8Test!"
PROFILE_NAME="${FIXTURE_MARKER}-f8-profile"

for existing_name in "$USER_A" "$USER_B" "$PROFILE_NAME"; do
    if [ -n "$(db_query "SELECT id FROM users WHERE name='${existing_name}';")" ] || [ -n "$(db_query "SELECT id FROM profiles WHERE name='${existing_name}';")" ]; then
        harness_blocked "a user or profile named '${existing_name}' already exists -- refusing to overwrite. Remove it manually first."
    fi
done

create_user() {
    local name="$1"
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$BODY" -w '%{http_code}' \
        --data-urlencode "name=${name}" \
        --data-urlencode "email=${name}@example.test" \
        --data-urlencode "password=${USER_PW}" \
        --data-urlencode "profile_id=1" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/users/add"
}

# 1. Valid requests: two disposable users, both starting on profile_id=1.
for u in "$USER_A" "$USER_B"; do
    httpcode="$(create_user "$u")"
    if [ "$httpcode" = "302" ]; then
        uid="$(db_query "SELECT id FROM users WHERE name='${u}';")"
        harness_register_cleanup "user ${u} (F8 fixture, id=${uid})" "curl -sS -c '$COOKIEJAR' -b '$COOKIEJAR' -o /dev/null --data-urlencode 'id=${uid}' --data-urlencode 'snep_csrf_token=${ADMIN_CSRF}' '${BASE_URL}/index.php/default/users/remove'"
        harness_ok "F8 valid: create user ${u}" "HTTP 302, id=${uid}, profile_id=1"
    else
        harness_blocked "F8 fixture user '${u}' creation failed (HTTP $httpcode) -- see $BODY"
    fi
done
UID_A="$(db_query "SELECT id FROM users WHERE name='${USER_A}';")"
UID_B="$(db_query "SELECT id FROM users WHERE name='${USER_B}';")"

# Create the disposable profile via Snep_Profiles_Manager::add()
# directly (the domain API, matching scripts/trunk-smoke-route.php's own
# established pattern for a fixture with no practical HTTP path) rather
# than ProfilesController::addAction(): that action has a genuine,
# pre-existing, PHP-8.4-only bug unrelated to this task --
# Snep_Profiles_Manager::getName() returns `false` for a brand-new name
# (the normal case), and `count(false)` is a fatal TypeError since PHP
# 8.0 (the exact bug class TASK-0023 already fixed for
# UsersController::addAction(), never extended to ProfilesController).
# Confirmed live during this task's own testing (PHP Fatal error,
# ProfilesController.php:105) -- documented as separate debt in
# docs/tasks/0026c-sql-boundary-hardening.md, not fixed here. The actual
# F8 sink under test (Snep_Users_Manager::addProfileByName(), reached via
# ProfilesController::editAction()'s duallistbox_profile[] loop) is
# unaffected by this and is exercised for real below.
$COMPOSE exec -T app php -r '
    define("APPLICATION_PATH", "/var/www/html/snep");
    set_include_path(implode(PATH_SEPARATOR, array(APPLICATION_PATH . "/lib", get_include_path())));
    require_once "Snep/Config.php";
    Snep_Config::setConfigFile(APPLICATION_PATH . "/includes/setup.conf");
    require_once "Zend/Registry.php";
    Zend_Registry::set("config", Snep_Config::getConfig());
    require_once "Snep/Db.php";
    Zend_Registry::set("db", Snep_Db::getInstance());
    require_once "Snep/Profiles/Manager.php";
    Snep_Profiles_Manager::add(array("name" => $argv[1]));
' -- "$PROFILE_NAME" >&2
NEW_PROFILE_ID="$(db_query "SELECT id FROM profiles WHERE name='${PROFILE_NAME}';")"
if [ -z "$NEW_PROFILE_ID" ]; then
    harness_blocked "could not provision the F8 fixture profile via Snep_Profiles_Manager::add()"
fi
harness_register_cleanup "profile ${PROFILE_NAME} (F8 fixture, id=${NEW_PROFILE_ID})" "curl -sS -c '$COOKIEJAR' -b '$COOKIEJAR' -o /dev/null --data-urlencode 'id=${NEW_PROFILE_ID}' --data-urlencode 'snep_csrf_token=${ADMIN_CSRF}' '${BASE_URL}/index.php/default/profiles/remove'"

# 2/3. Submit ProfilesController::editAction() (the real vulnerable
# route) with a boolean-always-true duallistbox_profile[] entry instead
# of a real username -- Snep_Users_Manager::addProfileByName() is the
# exact mass-privilege-escalation sink the audit named (F8). If
# vulnerable, this single request would reassign every user's
# profile_id. `name` is resubmitted unchanged (matching the just-created
# profile) so editAction()'s own name-collision check takes its
# safe "same name" branch, not its "assign to a new name" branch.
before_a="$(db_query "SELECT profile_id FROM users WHERE id=${UID_A};")"
before_b="$(db_query "SELECT profile_id FROM users WHERE id=${UID_B};")"
httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$BODY" -w '%{http_code}' \
    --data-urlencode "name=${PROFILE_NAME}" \
    --data-urlencode "duallistbox_profile[]=nonexistent' OR '1'='1" \
    --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
    "${BASE_URL}/index.php/default/profiles/edit/id/${NEW_PROFILE_ID}")"
after_a="$(db_query "SELECT profile_id FROM users WHERE id=${UID_A};")"
after_b="$(db_query "SELECT profile_id FROM users WHERE id=${UID_B};")"
if [ "$httpcode" = "302" ] && [ "$before_a" = "$after_a" ] && [ "$before_b" = "$after_b" ]; then
    harness_ok "F8: boolean-injection-shaped duallistbox_profile has no effect" "HTTP 302, user A profile_id ${before_a}->${after_a}, user B profile_id ${before_b}->${after_b} (both unchanged -- a real vulnerability would have reassigned both to ${NEW_PROFILE_ID})"
else
    harness_bad "F8: boolean-injection-shaped duallistbox_profile has no effect" "HTTP ${httpcode}, user A ${before_a}->${after_a}, user B ${before_b}->${after_b} -- an always-true condition reassigned real users"
fi

# 4. Legitimate assignment still works: assign the REAL user A to this
# profile by name, verify it (and only it) takes effect.
httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$BODY" -w '%{http_code}' \
    --data-urlencode "name=${PROFILE_NAME}" \
    --data-urlencode "duallistbox_profile[]=${USER_A}" \
    --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
    "${BASE_URL}/index.php/default/profiles/edit/id/${NEW_PROFILE_ID}")"
after_legit_a="$(db_query "SELECT profile_id FROM users WHERE id=${UID_A};")"
after_legit_b="$(db_query "SELECT profile_id FROM users WHERE id=${UID_B};")"
if [ "$httpcode" = "302" ] && [ "$after_legit_a" = "$NEW_PROFILE_ID" ] && [ "$after_legit_b" = "1" ]; then
    harness_ok "F8 valid: legitimate profile assignment by real name works" "user A reassigned to profile ${NEW_PROFILE_ID}, user B still on profile 1"
else
    harness_bad "F8 valid: legitimate profile assignment by real name works" "HTTP ${httpcode}, user A profile_id=${after_legit_a} (expected ${NEW_PROFILE_ID}), user B profile_id=${after_legit_b} (expected 1)"
fi

# =============================================================================
# F9 -- Trunks (second-order name injection + edit/remove boundary)
# =============================================================================

log "==> F9: Trunks boundary"

TRUNK_CALLERID="${FIXTURE_MARKER} f9 trunk"
CANARY_CALLERID="${FIXTURE_MARKER} f9 canary trunk"

for cid in "$TRUNK_CALLERID" "$CANARY_CALLERID"; do
    if [ -n "$(db_query "SELECT id FROM trunks WHERE callerid='${cid}';")" ]; then
        harness_blocked "a trunk with callerid '${cid}' already exists -- refusing to overwrite. Remove it manually first."
    fi
done

: "${TRUNK_TEST_USERNAME:?TRUNK_TEST_USERNAME must be set (source .env first)}"
: "${TRUNK_TEST_SECRET:?TRUNK_TEST_SECRET must be set (source .env first)}"

# Preflight recovery: TrunksController::preparePost() auto-generates a
# new trunk's `name` as MAX(trunks.name)+1 (or "1" if the trunks table
# is currently empty) -- it never looks at `peers` at all. An orphaned
# `peers` row (trunks row gone, its peers row left behind -- the exact
# stale-fixture class documented in
# docs/tasks/0027-regression-harness-reliability.md §5/§6) can therefore
# collide with a brand-new trunk's auto-generated name via peers.name's
# UNIQUE constraint, blocking creation with an unrelated HTTP 500.
# peer_type='T' reliably distinguishes trunk peers from extension peers
# (which use peer_type='R', see
# Snep_Extensions_Manager/ExtensionsController) -- this must never touch
# a real extension's peers row. Removal goes through the supported
# extensions/remove HTTP path (Snep_Extensions_Manager::remove() deletes
# a peers row by name regardless of peer_type, the same mechanism
# TASK-0027's own trunk-smoke stale-recovery already relies on).
#
# Also registered as this section's OWN final cleanup step (see below):
# TrunksController::editAction()'s peers-sync UPDATE has a genuine,
# pre-existing, unrelated logic bug -- it locates the existing peers row
# using the SUBMITTED (new) trunks.name rather than the row's own
# current name, so renaming a trunk (exactly what check 2/3 below does,
# to prove the SQL-shaped name is stored as literal data) leaves the
# peers row's name un-synced; deleting that now-renamed trunk afterward
# then can't find/remove its peers row by the new name either, orphaning
# it (live-confirmed while validating this suite under `make
# regression`). Not a SQL-injection defect -- a WHERE-clause
# target-matching bug -- so intentionally not fixed here (documented in
# docs/tasks/0026c-sql-boundary-hardening.md), but this suite still needs
# to leave the environment clean, so the same sweep runs again at the end
# as a safety net for exactly the residue its own rename test causes.
sweep_orphaned_trunk_peers() {
    local orphan_name
    for orphan_name in $(db_query "SELECT p.name FROM peers p LEFT JOIN trunks t ON t.name = p.name WHERE p.peer_type='T' AND t.id IS NULL;"); do
        log "found an orphaned trunk-type peers row (name='${orphan_name}') with no matching trunks row -- removing via the supported extensions/remove HTTP path"
        curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null --data-urlencode "id=${orphan_name}" --data-urlencode "delete=Delete" --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" "${BASE_URL}/index.php/default/extensions/remove" >/dev/null
        if [ -n "$(db_query "SELECT canal FROM peers WHERE name='${orphan_name}';")" ]; then
            log "WARNING: could not remove orphaned peers row (name='${orphan_name}') via the supported HTTP path -- may need manual cleanup"
            return 1
        fi
    done
    return 0
}
sweep_orphaned_trunk_peers || harness_blocked "an orphaned trunk-type peers row is blocking new trunk creation and could not be removed via the supported HTTP path -- refusing to proceed with a raw SQL fallback"
harness_register_cleanup "orphaned trunk-type peers row sweep (F9 rename-test side effect, see comment above)" "sweep_orphaned_trunk_peers"

create_trunk() {
    local callerid="$1"
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$BODY" -w '%{http_code}' \
        --data-urlencode "callerid=${callerid}" \
        --data-urlencode "technology=pjsip" \
        --data-urlencode "dialmethod=normal" \
        --data-urlencode "username=${TRUNK_TEST_USERNAME}" \
        --data-urlencode "secret=${TRUNK_TEST_SECRET}" \
        --data-urlencode "host=provider" \
        --data-urlencode "fromuser=" \
        --data-urlencode "fromdomain=" \
        --data-urlencode "qualify=yes" \
        --data-urlencode "qualify_value=" \
        --data-urlencode "peer_type=friend" \
        --data-urlencode "domain=" \
        --data-urlencode "insecure=" \
        --data-urlencode "port=5060" \
        --data-urlencode "call-limit=" \
        --data-urlencode "dtmfmode=rfc2833" \
        --data-urlencode "nat_no=1" \
        --data-urlencode "codec=ulaw" \
        --data-urlencode "codec1=alaw" \
        --data-urlencode "codec2=gsm" \
        --data-urlencode "reverse_auth=reverse_auth" \
        --data-urlencode "telco=" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/trunks/add"
}

# Idempotent by design: this is registered as this fixture's required
# cleanup AND also invoked directly by the "legitimate delete still
# works" check below -- if the trunk is already gone by the time the
# registered cleanup runs, that already satisfies cleanup's real goal
# (the fixture does not exist), so a missing row is success, not
# failure, exactly like ExtensionsController::removeAction()'s own
# forgiving (redirects regardless) behavior for an already-deleted
# extension.
delete_trunk() {
    local id="$1" name
    name="$(db_query "SELECT name FROM trunks WHERE id=${id};")"
    [ -z "$name" ] && return 0
    local httpcode
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "id=${id}" --data-urlencode "name=${name}" --data-urlencode "delete=Delete" --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/trunks/remove")"
    [ "$httpcode" = "302" ]
}

# 1. Valid: two disposable trunks (one under test, one canary).
httpcode="$(create_trunk "$TRUNK_CALLERID")"
if [ "$httpcode" = "302" ]; then
    TRUNK_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${TRUNK_CALLERID}';")"
    harness_register_cleanup "trunk id=${TRUNK_ID} (F9 fixture)" "delete_trunk ${TRUNK_ID}"
    harness_ok "F9 valid: create trunk" "HTTP 302, trunk id=${TRUNK_ID} created via the real UI flow"
else
    harness_blocked "F9 fixture trunk creation failed (HTTP $httpcode) -- see $BODY"
fi
httpcode="$(create_trunk "$CANARY_CALLERID")"
if [ "$httpcode" = "302" ]; then
    CANARY_TRUNK_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${CANARY_CALLERID}';")"
    CANARY_TRUNK_NAME="$(db_query "SELECT name FROM trunks WHERE id=${CANARY_TRUNK_ID};")"
    harness_register_cleanup "trunk id=${CANARY_TRUNK_ID} (F9 canary fixture)" "delete_trunk ${CANARY_TRUNK_ID}"
    harness_ok "F9 valid: create canary trunk" "HTTP 302, trunk id=${CANARY_TRUNK_ID} name=${CANARY_TRUNK_NAME} created (must survive every injection attempt below)"
else
    harness_blocked "F9 canary trunk creation failed (HTTP $httpcode) -- see $BODY"
fi

# 2/3. Mass-assign a SQL-shaped `name` at edit time (preparePost() merges
# the entire POST, `name` is on both the trunk_fields and ip_fields
# allowlists) -- the exact second-order sink the audit named: this
# planted name is later read back raw when the edit page is viewed.
SQLI_TRUNK_NAME="1' OR '1'='1"
before_fatals="$(fatal_count)"
httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$BODY" -w '%{http_code}' \
    --data-urlencode "callerid=${TRUNK_CALLERID}" \
    --data-urlencode "name=${SQLI_TRUNK_NAME}" \
    --data-urlencode "technology=pjsip" \
    --data-urlencode "dialmethod=normal" \
    --data-urlencode "username=${TRUNK_TEST_USERNAME}" \
    --data-urlencode "secret=${TRUNK_TEST_SECRET}" \
    --data-urlencode "host=provider" \
    --data-urlencode "fromuser=" \
    --data-urlencode "fromdomain=" \
    --data-urlencode "qualify=yes" \
    --data-urlencode "qualify_value=" \
    --data-urlencode "peer_type=friend" \
    --data-urlencode "domain=" \
    --data-urlencode "insecure=" \
    --data-urlencode "port=5060" \
    --data-urlencode "call-limit=" \
    --data-urlencode "dtmfmode=rfc2833" \
    --data-urlencode "nat_no=1" \
    --data-urlencode "codec=ulaw" \
    --data-urlencode "codec1=alaw" \
    --data-urlencode "codec2=gsm" \
    --data-urlencode "reverse_auth=reverse_auth" \
    --data-urlencode "telco=" \
    --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
    "${BASE_URL}/index.php/default/trunks/edit/trunk/${TRUNK_ID}")"
after_fatals="$(fatal_count)"
stored_trunk_name="$(db_query "SELECT name FROM trunks WHERE id=${TRUNK_ID};")"
canary_still_there="$(db_query "SELECT id FROM trunks WHERE id=${CANARY_TRUNK_ID};")"
# Viewing the edit page is what actually triggers the second-order read
# (TrunksController.php's `select * from peers where name='{$trunk['name']}'`).
view_code="$(request "$COOKIEJAR" GET "/index.php/default/trunks/edit/trunk/${TRUNK_ID}")"
view_fatals="$(fatal_count)"
if [ "$httpcode" = "302" ] && [ "$stored_trunk_name" = "$SQLI_TRUNK_NAME" ] \
    && [ "$canary_still_there" = "$CANARY_TRUNK_ID" ] \
    && [ "$view_code" = "200" ] && [ "$after_fatals" = "$view_fatals" ]; then
    harness_ok "F9: SQL-shaped mass-assigned name becomes literal data" "trunk name stored verbatim ('${stored_trunk_name}'), edit page still renders (HTTP 200, no new fatals), canary trunk untouched"
else
    harness_bad "F9: SQL-shaped mass-assigned name becomes literal data" "save HTTP=${httpcode} stored='${stored_trunk_name}' view HTTP=${view_code} fatals ${after_fatals}->${view_fatals} canary=${canary_still_there}"
fi

# 3b. Boolean-always-true removeAction() fields must not affect the
# canary trunk (Snep_Trunks_Manager::getRules/remove/removePeers).
#
# trunks.id/peers.id are INT columns -- MariaDB's own (unrelated to SQL
# injection) numeric-string comparison rule coerces a string to its
# LEADING numeric prefix when compared to an int column (confirmed live:
# "id = '1abc'" matches id=1 even under STRICT_TRANS_TABLES). A payload
# like "<realid>' OR '1'='1" would therefore match <realid> via ordinary
# type coercion regardless of this task's fix, and is not a meaningful
# injection test against an int column. "999999999' OR '1'='1" instead
# proves the same thing (safely parameterized, no syntax break, no
# match) without that false-positive risk. peers.name (used by
# removePeers()) is VARCHAR, so a boolean-always-true shape against the
# canary's own real trunk name is the correct, meaningful proof for that
# sink specifically.
before_trunk_count="$(db_query "SELECT COUNT(*) FROM trunks WHERE id IN (${TRUNK_ID},${CANARY_TRUNK_ID});")"
before_peers_count="$(db_query "SELECT COUNT(*) FROM peers WHERE name IN ('${TRUNK_ID}','${CANARY_TRUNK_NAME}');")"
curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$BODY" -w '%{http_code}' \
    --data-urlencode "id=999999999' OR '1'='1" \
    --data-urlencode "name=${CANARY_TRUNK_NAME}' OR '1'='1" \
    --data-urlencode "delete=Delete" \
    --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
    "${BASE_URL}/index.php/default/trunks/remove" >/dev/null
after_trunk_count="$(db_query "SELECT COUNT(*) FROM trunks WHERE id IN (${TRUNK_ID},${CANARY_TRUNK_ID});")"
after_peers_count="$(db_query "SELECT COUNT(*) FROM peers WHERE name IN ('${TRUNK_ID}','${CANARY_TRUNK_NAME}');")"
if [ "$before_trunk_count" = "2" ] && [ "$after_trunk_count" = "2" ] \
    && [ "$before_peers_count" = "$after_peers_count" ]; then
    harness_ok "F9: boolean-injection-shaped remove fields have no effect" "both trunk fixtures present (count ${before_trunk_count} -> ${after_trunk_count}), canary trunk's peers row untouched (${before_peers_count} -> ${after_peers_count})"
else
    harness_bad "F9: boolean-injection-shaped remove fields have no effect" "trunks ${before_trunk_count} -> ${after_trunk_count}, peers ${before_peers_count} -> ${after_peers_count} -- an always-true condition affected real rows"
fi

# 4. Legitimate delete still works.
if delete_trunk "$TRUNK_ID"; then
    harness_ok "F9: legitimate delete still works" "trunk id=${TRUNK_ID} removed via the real HTTP flow"
    TRUNK_ID=""
else
    harness_bad "F9: legitimate delete still works" "HTTP delete of trunk id=${TRUNK_ID} did not return 302"
fi

# =============================================================================
# F10 -- CSV import (Snep_CsvIE::import()) -- confirmed unreachable
# through any current controller (see docs/tasks/0026c-sql-boundary-
# hardening.md), so exercised directly via a harness-owned, throwaway
# table (created and dropped entirely within this script -- never a real
# application table) rather than through HTTP.
# =============================================================================

log "==> F10: CSV import boundary (direct exercise -- no HTTP entry point exists)"

CSVIE_TEST_TABLE="task0026c_csvie_test"
db_query "DROP TABLE IF EXISTS ${CSVIE_TEST_TABLE};" >/dev/null
db_query "CREATE TABLE ${CSVIE_TEST_TABLE} (id INT AUTO_INCREMENT PRIMARY KEY, label VARCHAR(255) NOT NULL);" >/dev/null
harness_register_cleanup "throwaway table ${CSVIE_TEST_TABLE} (F10 test scaffold, never a real application table)" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}' -e 'DROP TABLE IF EXISTS ${CSVIE_TEST_TABLE};' >/dev/null"

CSVIE_CSV="$(mktemp)"
harness_register_best_effort_cleanup "F10 CSV fixture file" "rm -f '$CSVIE_CSV'"
{
    echo "label"
    echo "normal-value"
    echo "\"quote' OR '1'='1\""
} > "$CSVIE_CSV"

# The php -r process below runs inside the container -- copy the CSV in first.
$COMPOSE cp "$CSVIE_CSV" "app:/tmp/$(basename "$CSVIE_CSV")" >/dev/null 2>&1
CSVIE_RESULT="$($COMPOSE exec -T app php -r '
    define("APPLICATION_PATH", "/var/www/html/snep");
    set_include_path(implode(PATH_SEPARATOR, array(APPLICATION_PATH . "/lib", get_include_path())));
    require_once "Snep/Config.php";
    Snep_Config::setConfigFile(APPLICATION_PATH . "/includes/setup.conf");
    require_once "Zend/Registry.php";
    Zend_Registry::set("config", Snep_Config::getConfig());
    require_once "Snep/Db.php";
    Zend_Registry::set("db", Snep_Db::getInstance());
    require_once "Snep/CsvIE.php";
    $ie = new Snep_CsvIE();
    $f = fopen($argv[1], "r");
    $result = $ie->import($f, array("label"), $argv[2]);
    fclose($f);
    echo json_encode($result) . "\n";
' -- "/tmp/$(basename "$CSVIE_CSV")" "$CSVIE_TEST_TABLE" 2>&1)"
$COMPOSE exec -T app rm -f "/tmp/$(basename "$CSVIE_CSV")" >/dev/null 2>&1

ROW_COUNT="$(db_query "SELECT COUNT(*) FROM ${CSVIE_TEST_TABLE};")"
STORED_QUOTE_ROW="$(db_query "SELECT label FROM ${CSVIE_TEST_TABLE} WHERE label LIKE \"quote%\";")"
if echo "$CSVIE_RESULT" | grep -q "Importa" && [ "${ROW_COUNT:-0}" = "2" ] && [ "$STORED_QUOTE_ROW" = "quote' OR '1'='1" ]; then
    harness_ok "F10: SQL-shaped CSV cell becomes literal data" "2 rows imported (no syntax break), the quote-containing cell stored verbatim: '${STORED_QUOTE_ROW}'"
else
    harness_bad "F10: SQL-shaped CSV cell becomes literal data" "result=${CSVIE_RESULT} rows=${ROW_COUNT} stored='${STORED_QUOTE_ROW}'"
fi

# =============================================================================
# F11 -- Data Export (ExportDataController::exportAction())
# =============================================================================

log "==> F11: Data Export boundary"

# 1. Valid: export the 'users' table (guaranteed non-empty -- the seeded
# admin row always exists, unlike 'queues' in a fresh dev environment)
# with its real allowlisted columns, verify the download succeeds and
# contains exactly the allowlisted columns.
httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$BODY" -w '%{http_code}' \
    --data-urlencode "group=users" \
    --data-urlencode "coluns[users][id]=1" \
    --data-urlencode "coluns[users][name]=1" \
    --data-urlencode "orderby[users]=id" \
    --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
    "${BASE_URL}/index.php/default/export-data/export")"
if [ "$httpcode" = "200" ]; then
    harness_ok "F11 valid: legitimate export selection works" "HTTP 200, confirmation page rendered for table=users"
else
    harness_bad "F11 valid: legitimate export selection works" "HTTP ${httpcode}"
fi

download_code="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$BODY" -w '%{http_code}' \
    "${BASE_URL}/index.php/default/export-data/export/download/true")"
if [ "$download_code" = "200" ] && grep -qi "admin" "$BODY"; then
    harness_ok "F11 valid: legitimate download works" "HTTP 200, CSV content returned for the allowlisted users/id,name selection"
else
    harness_bad "F11 valid: legitimate download works" "HTTP ${download_code}"
fi

# 2/3. Structural injection: an unknown/SQL-shaped table name must be
# rejected before any query is built (no HTTP 500, no data returned);
# an unknown column name must be silently excluded rather than reaching
# ORDER BY/SELECT; the real users table's password column must NOT be
# reachable via a forged column key that isn't in the allowlist.
before_fatals="$(fatal_count)"
httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$BODY" -w '%{http_code}' \
    --data-urlencode "group=users' OR '1'='1" \
    --data-urlencode "coluns[users' OR '1'='1][password]=1" \
    --data-urlencode "orderby[users' OR '1'='1]=password" \
    --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
    "${BASE_URL}/index.php/default/export-data/export")"
after_fatals="$(fatal_count)"
if [ "$after_fatals" = "$before_fatals" ] && ! grep -qi "Fatal error\|Stack trace" "$BODY"; then
    harness_ok "F11: SQL-shaped table name produces no query/no crash" "HTTP ${httpcode}, no new PHP Fatal Errors, no raw SQL error text leaked"
else
    harness_bad "F11: SQL-shaped table name produces no query/no crash" "HTTP ${httpcode}, fatals ${before_fatals}->${after_fatals}"
fi

before_fatals="$(fatal_count)"
httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$BODY" -w '%{http_code}' \
    --data-urlencode "group=users" \
    --data-urlencode "coluns[users][id]=1" \
    --data-urlencode "coluns[users][password]=1" \
    --data-urlencode "orderby[users]=password" \
    --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
    "${BASE_URL}/index.php/default/export-data/export")"
download_code2="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$BODY" -w '%{http_code}' \
    "${BASE_URL}/index.php/default/export-data/export/download/true")"
after_fatals="$(fatal_count)"
if [ "$after_fatals" = "$before_fatals" ] && ! grep -qi "password\|secret" "$BODY"; then
    harness_ok "F11: non-allowlisted column (users.password) is never selected" "HTTP ${download_code2}, no new fatals, the CSV never contains the password column even though it was requested"
else
    harness_bad "F11: non-allowlisted column (users.password) is never selected" "HTTP ${download_code2}, fatals ${before_fatals}->${after_fatals}, response: $(head -c 200 "$BODY")"
fi

harness_complete
