#!/bin/bash
#
# TASK-0026G session-fixation/cookie/CSRF hardening focused security smoke
# test.
#
# Exercises the confirmed F18-F20 findings from
# docs/tasks/0026-pre-pilot-security-release-audit.md (re-traced and
# remediated in docs/tasks/0026g-session-cookie-csrf-hardening.md):
#
#   F18 (session fixation): a session identifier held before login must
#   not remain valid as the authenticated identifier afterward, and
#   logout must invalidate the session outright.
#
#   F19 (cookie policy): the session cookie must be HttpOnly and
#   SameSite=Lax unconditionally, and Secure whenever the request is
#   actually HTTPS (direct, or via an explicitly trusted reverse proxy) --
#   never breaking the documented local HTTP dev workflow.
#
#   F20 (CSRF): every authenticated, state-changing POST must carry a
#   valid session-bound token (Snep_CsrfPlugin) -- missing, invalid, or
#   foreign-session tokens fail closed with HTTP 403 -- while GETs and
#   the standalone Basic-auth API remain unaffected.
#
# Every payload below is harmless: real disposable fixture users/
# extensions/trunks this script owns, never a real account, never a
# destructive or exfiltrating action.
#
# Deliberately separate from `make smoke` -- never run implicitly by it.
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE="${SMOKE_COMPOSE:-docker compose}"
BASE_URL="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
ADMIN_USER="admin"
ADMIN_PASSWORD="SmokeTest123!"

log() { harness_log "$@"; }

db_query() {
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
        "${DB_NAME:-snep}" -N -e "$1"
}

app_exec() {
    $COMPOSE exec -T app sh -c "$1"
}

fatal_count() {
    local n
    n="$(app_exec 'grep -c "Fatal error" /var/log/apache2/mag-error.log 2>/dev/null' | tr -d '\r\n ')"
    echo "${n:-0}"
}

BODY=""
HEADERS=""
# request <jar> GET|POST <path> [postdata] -- like every other suite's own
# request() helper (authorization-smoke-test.sh, sql-security-smoke-test.sh).
request() {
    local jar="$1" method="$2" path="$3" data="${4:-}"
    if [ "$method" = POST ]; then
        curl -sS -b "$jar" -c "$jar" -D "$HEADERS" -o "$BODY" -w '%{http_code}' -d "$data" "${BASE_URL}${path}"
    else
        curl -sS -b "$jar" -c "$jar" -D "$HEADERS" -o "$BODY" -w '%{http_code}' "${BASE_URL}${path}"
    fi
}

# raw_request <cookie-header-or-empty> <path> -- no jar, full control over
# the literal Cookie header sent, for the session-fixation checks below
# (which must reuse a specific, known PHPSESSID value across requests,
# not whatever a jar auto-manages).
#
# RAW_HEADERS/RAW_BODY are allocated ONCE, up front, and reused by every
# call (curl's -D/-o simply overwrite them each time) -- NOT allocated
# inside these functions, since every caller invokes them via command
# substitution ("code=$(raw_request ...)"), which forks a subshell; a
# variable assignment made inside that subshell (e.g. RAW_HEADERS="$(mktemp)")
# never reaches the parent shell, so the caller would be left reading an
# empty path.
RAW_HEADERS="$(mktemp)"
RAW_BODY="$(mktemp)"
harness_register_best_effort_cleanup "raw-request temp files" "rm -f '$RAW_HEADERS' '$RAW_BODY'"
raw_request() {
    local cookie="$1" path="$2"
    if [ -n "$cookie" ]; then
        curl -sS -D "$RAW_HEADERS" -o "$RAW_BODY" -w '%{http_code}' -H "Cookie: PHPSESSID=${cookie}" "${BASE_URL}${path}"
    else
        curl -sS -D "$RAW_HEADERS" -o "$RAW_BODY" -w '%{http_code}' "${BASE_URL}${path}"
    fi
}

# raw_login <cookie-header-or-empty> <user> <password> -- same as
# raw_request but POSTs the login form under a specific literal PHPSESSID.
raw_login() {
    local cookie="$1" user="$2" pass="$3"
    if [ -n "$cookie" ]; then
        curl -sS -D "$RAW_HEADERS" -o "$RAW_BODY" -w '%{http_code}' -H "Cookie: PHPSESSID=${cookie}" \
            --data-urlencode "user=${user}" --data-urlencode "password=${pass}" "${BASE_URL}/index.php/auth/login"
    else
        curl -sS -D "$RAW_HEADERS" -o "$RAW_BODY" -w '%{http_code}' \
            --data-urlencode "user=${user}" --data-urlencode "password=${pass}" "${BASE_URL}/index.php/auth/login"
    fi
}

extract_sid() {
    grep -io 'Set-Cookie: PHPSESSID=[^;]*' "$1" | tail -1 | sed -e 's/[Ss]et-[Cc]ookie: PHPSESSID=//' -e 's/[[:space:]]*$//'
}

# --- 0. Preflight ------------------------------------------------------

harness_require_containers app db
harness_require_env DB_USER DB_PASSWORD DB_NAME

BODY="$(mktemp)"
HEADERS="$(mktemp)"
harness_register_best_effort_cleanup "request temp files" "rm -f '$BODY' '$HEADERS'"

FATALS_BEFORE="$(fatal_count)"
log "==> baseline PHP Fatal Error count: ${FATALS_BEFORE}"

# =============================================================================
# 0b. Static inventory proof -- the centralized mechanism actually covers
# the rest of the app, not just the surfaces exercised live below.
# =============================================================================

log "==> Static inventory: centralized CSRF enforcement wiring"

BOOTSTRAP_FILE="$REPO_ROOT/snep/Bootstrap.php"
CSRF_PLUGIN_FILE="$REPO_ROOT/snep/modules/default/model/CsrfPlugin.php"

if grep -q 'registerPlugin(new Snep_CsrfPlugin())' "$BOOTSTRAP_FILE" \
    && grep -q 'registerPlugin(new Snep_PermissionPlugin())' "$BOOTSTRAP_FILE"; then
    harness_ok "Snep_CsrfPlugin registered alongside Snep_PermissionPlugin" "both registered in Bootstrap::_initPermission(), same authenticated-only boundary"
else
    harness_bad "Snep_CsrfPlugin registered alongside Snep_PermissionPlugin" "expected registerPlugin() calls not found in snep/Bootstrap.php"
fi

if [ -f "$CSRF_PLUGIN_FILE" ] && grep -q "if (!\$request->isPost())" "$CSRF_PLUGIN_FILE"; then
    harness_ok "Snep_CsrfPlugin gates on POST, not an action-name allowlist" "every authenticated POST is inspected by default -- only an explicit exemption skips it"
else
    harness_bad "Snep_CsrfPlugin gates on POST, not an action-name allowlist" "expected isPost() gate not found"
fi

EXEMPT_COUNT="$(grep -c "=> true," "$CSRF_PLUGIN_FILE" 2>/dev/null || echo 0)"
if [ "${EXEMPT_COUNT:-0}" = "1" ]; then
    harness_ok "CSRF exemption list stays minimal and explicit" "exactly 1 entry (default_systemstatus_restart-dispatch, its own pre-existing independently-audited token)"
else
    harness_bad "CSRF exemption list stays minimal and explicit" "expected exactly 1 exemption entry, found ${EXEMPT_COUNT}"
fi

# Reset the admin fixture password to the known baseline BEFORE any login
# attempt below (including the raw session-fixation logins) -- matches
# every other suite's own established convention (sql-security-smoke-
# test.sh, shell-security-smoke-test.sh, ...), since a prior suite could
# have left it in an unrelated state.
ADMIN_HASH="$(app_exec "php -r \"echo md5('${ADMIN_PASSWORD}');\"" | tr -d '\r')"
if [ -z "$ADMIN_HASH" ]; then
    harness_blocked "could not compute the ${ADMIN_USER} password hash via the app container"
fi
db_query "UPDATE users SET password = '${ADMIN_HASH}' WHERE name = '${ADMIN_USER}';" >&2

# =============================================================================
# 1. Session fixation (F18) -- checks 1-7
# =============================================================================

log "==> F18: session fixation"

# 1. Anonymous session id.
code="$(raw_request "" /index.php/auth/login)"
PRE_LOGIN_SID="$(extract_sid "$RAW_HEADERS")"
if [ "$code" = "200" ] && [ -n "$PRE_LOGIN_SID" ]; then
    harness_ok "1: anonymous session id obtained" "HTTP $code, PHPSESSID issued"
else
    harness_blocked "could not obtain an anonymous session id (HTTP $code) -- cannot proceed with session-fixation checks"
fi

# 2/3. Log in while presenting that SAME pre-chosen session id -- the
# exact live-proven F18 attack setup -- then prove the id CHANGED.
code="$(raw_login "$PRE_LOGIN_SID" "$ADMIN_USER" "$ADMIN_PASSWORD")"
POST_LOGIN_SID="$(extract_sid "$RAW_HEADERS")"
if [ "$code" = "302" ] && [ -n "$POST_LOGIN_SID" ] && [ "$POST_LOGIN_SID" != "$PRE_LOGIN_SID" ]; then
    harness_ok "2/3: session id changes on successful login" "HTTP 302, PHPSESSID ${PRE_LOGIN_SID} -> ${POST_LOGIN_SID} (regenerated)"
else
    harness_blocked "login did not return 302 with a new session id (HTTP $code, pre=${PRE_LOGIN_SID}, post=${POST_LOGIN_SID:-none}) -- cannot proceed"
fi

# Phase 2 failure-path checks: a failed login must never authenticate.
code="$(raw_login "" "$ADMIN_USER" "wrong-password-entirely")"
if [ "$code" = "200" ] && grep -qi 'user or password invalid\|authentication failure\|login' "$RAW_BODY"; then
    harness_ok "2b: wrong password does not authenticate" "HTTP $code, login page re-rendered, not the authenticated dashboard"
else
    harness_bad "2b: wrong password does not authenticate" "HTTP $code"
fi

code="$(raw_login "" "task0026g-nonexistent-user" "whatever-password")"
if [ "$code" = "200" ] && grep -qi 'user or password invalid\|authentication failure\|login' "$RAW_BODY"; then
    harness_ok "2c: nonexistent user does not authenticate" "HTTP $code, login page re-rendered"
else
    harness_bad "2c: nonexistent user does not authenticate" "HTTP $code"
fi

# 4. The OLD (pre-login) id must NOT be authenticated.
code="$(raw_request "$PRE_LOGIN_SID" /index.php/index/add)"
if [ "$code" = "200" ] && grep -q 'SNEP - Login' "$RAW_BODY"; then
    harness_ok "4: pre-login session id cannot access an authenticated page" "HTTP $code, login page rendered -- old id never became authenticated"
else
    harness_bad "4: pre-login session id cannot access an authenticated page" "HTTP $code"
fi

# 5. The NEW (post-login) id DOES work.
code="$(raw_request "$POST_LOGIN_SID" /index.php/index/add)"
if [ "$code" = "200" ] && grep -q 'var controller = "index"' "$RAW_BODY"; then
    harness_ok "5: new session id is authenticated" "HTTP $code, dashboard rendered"
else
    harness_bad "5: new session id is authenticated" "HTTP $code"
fi

# 6. Logout using the new id.
code="$(raw_request "$POST_LOGIN_SID" /index.php/auth/logout)"
if [ "$code" = "302" ]; then
    harness_ok "6: logout invalidates the session" "HTTP $code"
else
    harness_bad "6: logout invalidates the session" "HTTP $code"
fi

# 7. The now-logged-out id must NOT access a protected page anymore.
code="$(raw_request "$POST_LOGIN_SID" /index.php/index/add)"
if [ "$code" = "200" ] && grep -q 'SNEP - Login' "$RAW_BODY"; then
    harness_ok "7: logged-out session no longer accesses protected pages" "HTTP $code, login page rendered"
else
    harness_bad "7: logged-out session no longer accesses protected pages" "HTTP $code"
fi

# =============================================================================
# 2. Cookie policy (F19) -- checks 8-10
# =============================================================================

log "==> F19: cookie policy"

# Fresh login (real jar this time) to inspect the actual Set-Cookie
# header the app issues over this suite's own HTTP dev environment.
LOGIN_HEADERS="$(mktemp)"
harness_register_best_effort_cleanup "login header temp file" "rm -f '$LOGIN_HEADERS'"
curl -sS -D "$LOGIN_HEADERS" -o /dev/null --data-urlencode "user=${ADMIN_USER}" --data-urlencode "password=${ADMIN_PASSWORD}" \
    "${BASE_URL}/index.php/auth/login"
SET_COOKIE_LINE="$(grep -i '^Set-Cookie: PHPSESSID=' "$LOGIN_HEADERS" | tail -1)"

# 8. HttpOnly.
if echo "$SET_COOKIE_LINE" | grep -qi 'HttpOnly'; then
    harness_ok "8: session cookie is HttpOnly" "$SET_COOKIE_LINE"
else
    harness_bad "8: session cookie is HttpOnly" "Set-Cookie line: $SET_COOKIE_LINE"
fi

# 9. SameSite=Lax.
if echo "$SET_COOKIE_LINE" | grep -qi 'SameSite=Lax'; then
    harness_ok "9: session cookie SameSite policy is present and Lax" "$SET_COOKIE_LINE"
else
    harness_bad "9: session cookie SameSite policy is present and Lax" "Set-Cookie line: $SET_COOKIE_LINE"
fi

# 10a. Secure must be ABSENT over this suite's own plain-HTTP dev
# environment -- must not break `make dev`.
if ! echo "$SET_COOKIE_LINE" | grep -qi 'Secure'; then
    harness_ok "10a: Secure is off over local HTTP (make dev stays usable)" "$SET_COOKIE_LINE"
else
    harness_bad "10a: Secure is off over local HTTP (make dev stays usable)" "Set-Cookie line: $SET_COOKIE_LINE"
fi

# 10b. No deterministic HTTPS listener exists in this dev topology (see
# docs/tasks/0026g-session-cookie-csrf-hardening.md) -- so the
# policy-generation helper itself is exercised directly, simulating
# direct HTTPS, an untrusted proxy header, and a deliberately trusted one.
POLICY_RESULT="$(app_exec "php -r '
require \"/var/www/html/snep/lib/Snep/Session/CookiePolicy.php\";
\$out = array();
\$_SERVER = array();
\$out[\"http_plain\"] = Snep_Session_CookiePolicy::isHttps() ? \"true\" : \"false\";
\$_SERVER = array(\"HTTPS\" => \"on\");
\$out[\"direct_https\"] = Snep_Session_CookiePolicy::isHttps() ? \"true\" : \"false\";
\$_SERVER = array(\"HTTP_X_FORWARDED_PROTO\" => \"https\");
\$out[\"untrusted_proxy_header\"] = Snep_Session_CookiePolicy::isHttps() ? \"true\" : \"false\";
putenv(\"SENMA_TRUST_PROXY_HTTPS=1\");
\$_SERVER = array(\"HTTP_X_FORWARDED_PROTO\" => \"https\");
\$out[\"trusted_proxy_header\"] = Snep_Session_CookiePolicy::isHttps() ? \"true\" : \"false\";
echo json_encode(\$out);
'")"
if echo "$POLICY_RESULT" | grep -q '"http_plain":"false"' \
    && echo "$POLICY_RESULT" | grep -q '"direct_https":"true"' \
    && echo "$POLICY_RESULT" | grep -q '"untrusted_proxy_header":"false"' \
    && echo "$POLICY_RESULT" | grep -q '"trusted_proxy_header":"true"'; then
    harness_ok "10b: Secure policy helper is deployment-aware" "plain HTTP=false, direct HTTPS=true, untrusted proxy header=false (ignored by default), explicitly-trusted proxy header=true: ${POLICY_RESULT}"
else
    harness_bad "10b: Secure policy helper is deployment-aware" "unexpected result: ${POLICY_RESULT}"
fi

# =============================================================================
# 3. CSRF (F20) -- checks 11-16, across multiple mutation surfaces
# =============================================================================

log "==> F20: CSRF enforcement"

ADMIN_JAR="$(mktemp)"
harness_register_best_effort_cleanup "admin cookie jar" "rm -f '$ADMIN_JAR'"
request "$ADMIN_JAR" POST /index.php/auth/login "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}" >/dev/null
ADMIN_CSRF="$(harness_csrf_token "$ADMIN_JAR" "$BASE_URL")"
if [ -z "$ADMIN_CSRF" ]; then
    harness_blocked "could not read the admin session's CSRF token"
fi

# A second, independent, authenticated session -- used ONLY to prove its
# own valid token is rejected when submitted against a DIFFERENT
# session's mutation (check 14). Zero permissions needed: token validity
# is a session property, not a privilege.
FOREIGN_USER="task0026g-foreign"
FOREIGN_PASSWORD="Task0026gForeign!"
FOREIGN_HASH="$(app_exec "php -r \"echo md5('${FOREIGN_PASSWORD}');\"" | tr -d '\r')"
FID="$(db_query "SELECT id FROM users WHERE name='${FOREIGN_USER}';")"
if [ -z "$FID" ]; then
    db_query "INSERT INTO users (name,password,email,dashboard,profile_id,created,updated) VALUES ('${FOREIGN_USER}','${FOREIGN_HASH}','${FOREIGN_USER}@example.test','',1,NOW(),NOW());"
    FID="$(db_query "SELECT id FROM users WHERE name='${FOREIGN_USER}';")"
fi
if [ -z "$FID" ]; then
    harness_blocked "could not provision the foreign-session fixture user"
fi
db_query "UPDATE users SET password='${FOREIGN_HASH}' WHERE id=${FID};" >/dev/null
harness_register_best_effort_cleanup "foreign fixture user ${FOREIGN_USER} (id=${FID}) password reset to baseline" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}' -e \"UPDATE users SET password='${FOREIGN_HASH}' WHERE id=${FID};\" >/dev/null"

FOREIGN_JAR="$(mktemp)"
harness_register_best_effort_cleanup "foreign cookie jar" "rm -f '$FOREIGN_JAR'"
request "$FOREIGN_JAR" POST /index.php/auth/login "user=${FOREIGN_USER}&password=${FOREIGN_PASSWORD}" >/dev/null
FOREIGN_CSRF="$(harness_csrf_token "$FOREIGN_JAR" "$BASE_URL")"
if [ -z "$FOREIGN_CSRF" ]; then
    harness_blocked "could not read the foreign session's CSRF token"
fi
if [ "$FOREIGN_CSRF" = "$ADMIN_CSRF" ]; then
    harness_blocked "the foreign session's CSRF token is identical to the admin session's -- fixture setup is broken, cannot prove cross-session rejection"
fi

# --- Surface 1: Extensions (full valid/missing/invalid/foreign matrix) -----

EXT_ID="10979"
EXT_NAME_ORIGINAL="Task0026g Original"
EXT_NAME_EDITED="Task0026g Edited"
EXISTING_EXT="$(db_query "SELECT canal FROM peers WHERE name='${EXT_ID}';")"
if [ -n "$EXISTING_EXT" ]; then
    harness_blocked "peers row for extension '${EXT_ID}' already exists -- refusing to overwrite. Remove it manually first."
fi

create_ext_fields() {
    local name="$1" token="$2"
    curl -sS -c "$ADMIN_JAR" -b "$ADMIN_JAR" -o "$BODY" -w '%{http_code}' \
        --data-urlencode "name=${name}" \
        --data-urlencode "exten=${EXT_ID}" \
        --data-urlencode "technology=pjsip" \
        --data-urlencode "password=Task0026gExtSecret!" \
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
        --data-urlencode "snep_csrf_token=${token}" \
        "${BASE_URL}/index.php/default/extensions/add"
}

# 11. Valid token: legitimate mutation succeeds. addAction() appends
# " <exten>" (WITH a leading space) to the posted name before storing;
# editAction() below appends "<exten>" (no space) -- two different,
# pre-existing, unrelated formatting conventions, confirmed live.
httpcode="$(create_ext_fields "$EXT_NAME_ORIGINAL" "$ADMIN_CSRF")"
stored="$(db_query "SELECT callerid FROM peers WHERE name='${EXT_ID}';")"
STORED_AFTER_ADD="${EXT_NAME_ORIGINAL} <${EXT_ID}>"
if [ "$httpcode" = "302" ] && [ "$stored" = "$STORED_AFTER_ADD" ]; then
    harness_ok "11: authenticated mutation with a valid token succeeds" "HTTP 302, extension ${EXT_ID} created"
else
    harness_blocked "F20 fixture creation failed (HTTP $httpcode, stored='${stored}') -- cannot proceed with the CSRF matrix"
fi
harness_register_cleanup "extension ${EXT_ID} (F20 fixture)" \
    "curl -sS -c '$ADMIN_JAR' -b '$ADMIN_JAR' -o /dev/null --data-urlencode 'id=${EXT_ID}' --data-urlencode 'delete=Delete' --data-urlencode 'snep_csrf_token=${ADMIN_CSRF}' '${BASE_URL}/index.php/default/extensions/remove'"

edit_ext_fields() {
    local name="$1" token_field="$2"
    curl -sS -c "$ADMIN_JAR" -b "$ADMIN_JAR" -o "$BODY" -w '%{http_code}' \
        --data-urlencode "name=${name}" \
        --data-urlencode "exten=${EXT_ID}" \
        --data-urlencode "technology=pjsip" \
        --data-urlencode "password=Task0026gExtSecret!" \
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
        $token_field \
        "${BASE_URL}/index.php/default/extensions/edit/id/${EXT_ID}"
}

# 12. Missing token -> rejected, fails closed, no fatal, name unchanged.
before_fatals="$(fatal_count)"
httpcode="$(edit_ext_fields "$EXT_NAME_EDITED" "")"
after_fatals="$(fatal_count)"
stored="$(db_query "SELECT callerid FROM peers WHERE name='${EXT_ID}';")"
if [ "$httpcode" = "403" ] && [ "$stored" = "$STORED_AFTER_ADD" ] && [ "$before_fatals" = "$after_fatals" ] \
    && ! grep -qi "fatal\|stack trace\|warning" "$BODY"; then
    harness_ok "12: mutation without a token is rejected" "HTTP 403, no new fatals, controlled response body, extension unchanged"
else
    harness_bad "12: mutation without a token is rejected" "HTTP ${httpcode}, stored='${stored}', fatals ${before_fatals}->${after_fatals}"
fi

# 13. Invalid token -> rejected.
httpcode="$(edit_ext_fields "$EXT_NAME_EDITED" '--data-urlencode snep_csrf_token=not-a-real-token-at-all')"
stored="$(db_query "SELECT callerid FROM peers WHERE name='${EXT_ID}';")"
if [ "$httpcode" = "403" ] && [ "$stored" = "$STORED_AFTER_ADD" ]; then
    harness_ok "13: mutation with an invalid token is rejected" "HTTP 403, extension unchanged"
else
    harness_bad "13: mutation with an invalid token is rejected" "HTTP ${httpcode}, stored='${stored}'"
fi

# 14. A token from a genuinely different, currently-valid session ->
# rejected against THIS session's mutation.
httpcode="$(edit_ext_fields "$EXT_NAME_EDITED" "--data-urlencode snep_csrf_token=${FOREIGN_CSRF}")"
stored="$(db_query "SELECT callerid FROM peers WHERE name='${EXT_ID}';")"
if [ "$httpcode" = "403" ] && [ "$stored" = "$STORED_AFTER_ADD" ]; then
    harness_ok "14: a token from another session is rejected" "HTTP 403, extension unchanged (foreign token was itself valid for its OWN session, not this one)"
else
    harness_bad "14: a token from another session is rejected" "HTTP ${httpcode}, stored='${stored}'"
fi

# Legitimate edit still works with the real token (proves 12-14 didn't
# just permanently break the endpoint).
httpcode="$(edit_ext_fields "$EXT_NAME_EDITED" "--data-urlencode snep_csrf_token=${ADMIN_CSRF}")"
stored="$(db_query "SELECT callerid FROM peers WHERE name='${EXT_ID}';")"
if [ "$httpcode" = "302" ] && [ "$stored" = "${EXT_NAME_EDITED}<${EXT_ID}>" ]; then
    harness_ok "extensions surface: legitimate edit still works after the rejected attempts" "HTTP 302, callerid updated to '${stored}'"
else
    harness_bad "extensions surface: legitimate edit still works after the rejected attempts" "HTTP ${httpcode}, stored='${stored}'"
fi

# --- Surface 2: Trunks (valid + missing) ------------------------------------

harness_require_env TRUNK_TEST_USERNAME TRUNK_TEST_SECRET
TRUNK_CALLERID="task0026g trunk fixture"
if [ -n "$(db_query "SELECT id FROM trunks WHERE callerid='${TRUNK_CALLERID}';")" ]; then
    harness_blocked "a trunk with callerid '${TRUNK_CALLERID}' already exists -- refusing to overwrite. Remove it manually first."
fi
# TASK-0027 precedent (sql-security-smoke-test.sh/pjsip-config-security-
# smoke-test.sh): TrunksController::preparePost() auto-generates a new
# trunk's `name` as MAX(trunks.name)+1, colliding with an orphaned
# peers row a prior interrupted run could have left behind. Swept via
# the same supported extensions/remove HTTP path, never raw SQL.
for orphan_name in $(db_query "SELECT p.name FROM peers p LEFT JOIN trunks t ON t.name = p.name WHERE p.peer_type='T' AND t.id IS NULL;"); do
    log "found an orphaned trunk-type peers row (name='${orphan_name}') -- removing via the supported extensions/remove HTTP path"
    curl -sS -c "$ADMIN_JAR" -b "$ADMIN_JAR" -o /dev/null --data-urlencode "id=${orphan_name}" --data-urlencode "delete=Delete" --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" "${BASE_URL}/index.php/default/extensions/remove" >/dev/null
done

create_trunk_fields() {
    local token_field="$1"
    curl -sS -c "$ADMIN_JAR" -b "$ADMIN_JAR" -o "$BODY" -w '%{http_code}' \
        --data-urlencode "callerid=${TRUNK_CALLERID}" \
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
        $token_field \
        "${BASE_URL}/index.php/default/trunks/add"
}

httpcode="$(create_trunk_fields "")"
NO_TOKEN_TRUNK_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${TRUNK_CALLERID}';")"
if [ "$httpcode" = "403" ] && [ -z "$NO_TOKEN_TRUNK_ID" ]; then
    harness_ok "trunks surface: mutation without a token is rejected" "HTTP 403, no trunk row created"
else
    harness_bad "trunks surface: mutation without a token is rejected" "HTTP ${httpcode}, trunk id present='${NO_TOKEN_TRUNK_ID}'"
fi

httpcode="$(create_trunk_fields "--data-urlencode snep_csrf_token=${ADMIN_CSRF}")"
TRUNK_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${TRUNK_CALLERID}';")"
if [ "$httpcode" = "302" ] && [ -n "$TRUNK_ID" ]; then
    harness_ok "trunks surface: legitimate mutation with a valid token succeeds" "HTTP 302, trunk id=${TRUNK_ID} created"
else
    harness_bad "trunks surface: legitimate mutation with a valid token succeeds" "HTTP ${httpcode}, trunk id present='${TRUNK_ID}'"
fi
if [ -n "$TRUNK_ID" ]; then
    TRUNK_NAME="$(db_query "SELECT name FROM trunks WHERE id=${TRUNK_ID};")"
    harness_register_cleanup "trunk id=${TRUNK_ID} (F20 fixture)" \
        "curl -sS -c '$ADMIN_JAR' -b '$ADMIN_JAR' -o /dev/null --data-urlencode 'id=${TRUNK_ID}' --data-urlencode 'name=${TRUNK_NAME}' --data-urlencode 'delete=Delete' --data-urlencode 'snep_csrf_token=${ADMIN_CSRF}' '${BASE_URL}/index.php/default/trunks/remove'"
fi

# --- Surface 3: Users/permission (valid + missing) --------------------------

TARGET_USER="task0026g-target"
TARGET_PASSWORD="Task0026gTarget!"
TARGET_HASH="$(app_exec "php -r \"echo md5('${TARGET_PASSWORD}');\"" | tr -d '\r')"
TID="$(db_query "SELECT id FROM users WHERE name='${TARGET_USER}';")"
if [ -z "$TID" ]; then
    db_query "INSERT INTO users (name,password,email,dashboard,profile_id,created,updated) VALUES ('${TARGET_USER}','${TARGET_HASH}','${TARGET_USER}@example.test','',1,NOW(),NOW());"
    TID="$(db_query "SELECT id FROM users WHERE name='${TARGET_USER}';")"
fi
if [ -z "$TID" ]; then
    harness_blocked "could not provision the users/permission target fixture user"
fi
db_query "DELETE FROM users_permissions WHERE user_id=${TID};" >/dev/null
harness_register_best_effort_cleanup "target fixture user ${TARGET_USER} (id=${TID}) permissions reset" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}' -e \"DELETE FROM users_permissions WHERE user_id=${TID};\" >/dev/null"

PERM="default_errors-tdm_read"
httpcode="$(request "$ADMIN_JAR" POST "/index.php/default/users/permission/id/${TID}" "user=${TID}&${PERM}=1")"
GRANT_COUNT="$(db_query "SELECT COUNT(*) FROM users_permissions WHERE user_id=${TID};")"
if [ "$httpcode" = "403" ] && [ "${GRANT_COUNT:-0}" = "0" ]; then
    harness_ok "users/permission surface: mutation without a token is rejected" "HTTP 403, no permission row created"
else
    harness_bad "users/permission surface: mutation without a token is rejected" "HTTP ${httpcode}, permission rows=${GRANT_COUNT}"
fi

httpcode="$(request "$ADMIN_JAR" POST "/index.php/default/users/permission/id/${TID}" "user=${TID}&${PERM}=1&snep_csrf_token=${ADMIN_CSRF}")"
GRANT_COUNT="$(db_query "SELECT COUNT(*) FROM users_permissions WHERE user_id=${TID};")"
if [ "$httpcode" = "302" ] && [ "${GRANT_COUNT:-0}" -ge "1" ]; then
    harness_ok "users/permission surface: legitimate mutation with a valid token succeeds" "HTTP 302, ${GRANT_COUNT} permission row(s) created"
else
    harness_bad "users/permission surface: legitimate mutation with a valid token succeeds" "HTTP ${httpcode}, permission rows=${GRANT_COUNT}"
fi

# --- 15. Read-only GET still works, with no token anywhere ------------------

code="$(request "$ADMIN_JAR" GET /index.php/default/extensions)"
if [ "$code" = "200" ]; then
    harness_ok "15: read-only GET still works with no CSRF token" "HTTP $code"
else
    harness_bad "15: read-only GET still works with no CSRF token" "HTTP $code"
fi

# --- Bonus: Phase 11 state-changing-GET remediation (RouteController) ------
# route/toogle previously mutated unconditionally on GET with no isPost()
# check at all -- now rejects non-POST outright, and (being POST) is
# itself subject to the same CSRF gate as everything else, independent of
# whether the referenced route id exists.

code="$(request "$ADMIN_JAR" GET /index.php/default/route/toogle/route/999999)"
if [ "$code" = "405" ]; then
    harness_ok "bonus: route/toogle rejects GET (Phase 11 fix)" "HTTP 405"
else
    harness_bad "bonus: route/toogle rejects GET (Phase 11 fix)" "HTTP $code"
fi
code="$(request "$ADMIN_JAR" POST /index.php/default/route/toogle/route/999999 "")"
if [ "$code" = "403" ]; then
    harness_ok "bonus: route/toogle POST without a token is rejected" "HTTP 403"
else
    harness_bad "bonus: route/toogle POST without a token is rejected" "HTTP $code"
fi

# =============================================================================
# 4. Phase 11 follow-up -- ParametersController::languageAction no longer
#    mutates on GET (see docs/tasks/0026g-session-cookie-csrf-hardening.md)
# =============================================================================

log "==> Phase 11 follow-up: language switch (ParametersController)"

get_language() {
    app_exec "grep '^language' /var/www/html/snep/includes/setup.conf" | sed -E 's/^language *= *"?([^"]*)"?.*/\1/'
}

LANG_BASELINE="$(get_language)"
if [ -z "$LANG_BASELINE" ]; then
    harness_blocked "could not read the current system language from setup.conf"
fi
# Restores the baseline using the SAME already-captured ADMIN_CSRF -- safe
# because the token is a stable per-session value, not one-shot/rotating
# (Snep_Security_Csrf), so it is still valid whenever this cleanup runs.
harness_register_cleanup "system language restored to baseline (${LANG_BASELINE})" \
    "curl -sS -c '$ADMIN_JAR' -b '$ADMIN_JAR' -o /dev/null --data-urlencode 'language=${LANG_BASELINE}' --data-urlencode 'snep_csrf_token=${ADMIN_CSRF}' '${BASE_URL}/index.php/default/parameters/language'"

# Deliberately different from the baseline so a no-op false pass is
# impossible.
if [ "$LANG_BASELINE" = "en" ]; then TARGET_LANG="pt_BR"; else TARGET_LANG="en"; fi

# 17. GET with a valid, allowlisted language must NOT mutate anything --
# the dropdown used to link straight here as a plain GET.
code="$(request "$ADMIN_JAR" GET "/index.php/default/parameters/language?language=${TARGET_LANG}")"
AFTER_GET_LANG="$(get_language)"
if [ "$code" = "302" ] && [ "$AFTER_GET_LANG" = "$LANG_BASELINE" ]; then
    harness_ok "17: language switch cannot be performed by GET alone" "HTTP $code, language unchanged (${AFTER_GET_LANG})"
else
    harness_bad "17: language switch cannot be performed by GET alone" "HTTP $code, language now '${AFTER_GET_LANG}' (expected unchanged '${LANG_BASELINE}')"
fi

# 18. POST with no CSRF token -> rejected, unchanged.
code="$(request "$ADMIN_JAR" POST /index.php/default/parameters/language "language=${TARGET_LANG}")"
AFTER_LANG="$(get_language)"
if [ "$code" = "403" ] && [ "$AFTER_LANG" = "$LANG_BASELINE" ]; then
    harness_ok "18: language POST without a token is rejected" "HTTP 403, language unchanged"
else
    harness_bad "18: language POST without a token is rejected" "HTTP $code, language='${AFTER_LANG}'"
fi

# 19. POST with an invalid CSRF token -> rejected, unchanged.
code="$(request "$ADMIN_JAR" POST /index.php/default/parameters/language "language=${TARGET_LANG}&snep_csrf_token=not-a-real-token")"
AFTER_LANG="$(get_language)"
if [ "$code" = "403" ] && [ "$AFTER_LANG" = "$LANG_BASELINE" ]; then
    harness_ok "19: language POST with an invalid token is rejected" "HTTP 403, language unchanged"
else
    harness_bad "19: language POST with an invalid token is rejected" "HTTP $code, language='${AFTER_LANG}'"
fi

# 20. POST with a VALID token but an out-of-allowlist language value ->
# rejected by Snep_Locale::isSupportedLanguage() (TASK-0026B's own
# invariant) -- proves CSRF protection did not loosen that validation.
code="$(request "$ADMIN_JAR" POST /index.php/default/parameters/language "language=xx-not-real&snep_csrf_token=${ADMIN_CSRF}")"
AFTER_LANG="$(get_language)"
if [ "$AFTER_LANG" = "$LANG_BASELINE" ]; then
    harness_ok "20: TASK-0026B language allowlist remains authoritative" "HTTP $code, unsupported language value rejected, system language unchanged"
else
    harness_bad "20: TASK-0026B language allowlist remains authoritative" "HTTP $code, language changed to '${AFTER_LANG}'"
fi

# 21. POST with a valid token and a valid, allowlisted language -> succeeds.
code="$(request "$ADMIN_JAR" POST /index.php/default/parameters/language "language=${TARGET_LANG}&snep_csrf_token=${ADMIN_CSRF}")"
AFTER_LANG="$(get_language)"
if [ "$code" = "302" ] && [ "$AFTER_LANG" = "$TARGET_LANG" ]; then
    harness_ok "21: language change with a valid token succeeds" "HTTP $code, system language now '${AFTER_LANG}'"
else
    harness_bad "21: language change with a valid token succeeds" "HTTP $code, language='${AFTER_LANG}' (expected '${TARGET_LANG}')"
fi

# =============================================================================
# 5. Phase 11 follow-up -- NotificationsController::indexAction no longer
#    mutates on GET; the mutation moved to a dedicated, CSRF-protected
#    markReadAction()
# =============================================================================

log "==> Phase 11 follow-up: notifications (NotificationsController)"

# 22. Source-level proof indexAction() no longer calls
# Snep_Notifications::setRead() as a live side effect of its own GET --
# the authoritative check here, since setRead() itself calls out to an
# external vendor URL this harness cannot observe directly. Filters out
# comment lines first (this task's own explanatory comments mention the
# removed call by name).
NOTIF_CONTROLLER="$REPO_ROOT/snep/modules/default/controllers/NotificationsController.php"
INDEX_BODY="$(sed -n '/public function indexAction/,/public function markReadAction/p' "$NOTIF_CONTROLLER" | grep -v '^\s*//\|^\s*\*')"
if ! echo "$INDEX_BODY" | grep -q 'Snep_Notifications::setRead('; then
    harness_ok "22: notifications GET no longer calls setRead() as a side effect" "indexAction() source contains no live setRead() call outside comments"
else
    harness_bad "22: notifications GET no longer calls setRead() as a side effect" "indexAction() still contains a live setRead() call"
fi

# 23. Behavioral proof: GET a single notification -- read-only, works
# with no CSRF token (as any read-only GET must), and renders the
# markReadAction JS trigger the mutation moved into.
code="$(request "$ADMIN_JAR" GET /index.php/default/notifications?id=1)"
if [ "$code" = "200" ] && grep -q 'notifications/mark-read' "$BODY"; then
    harness_ok "23: notifications GET is read-only and defers the mutation to mark-read" "HTTP $code, no CSRF token needed, mark-read call present in the rendered page"
else
    harness_bad "23: notifications GET is read-only and defers the mutation to mark-read" "HTTP $code"
fi

# 24. The new mark-read endpoint rejects GET outright.
code="$(request "$ADMIN_JAR" GET /index.php/default/notifications/mark-read)"
if [ "$code" = "405" ]; then
    harness_ok "24: notifications mark-read rejects GET" "HTTP 405"
else
    harness_bad "24: notifications mark-read rejects GET" "HTTP $code"
fi

# 25. POST without a token -> rejected.
code="$(request "$ADMIN_JAR" POST /index.php/default/notifications/mark-read "id=1")"
if [ "$code" = "403" ]; then
    harness_ok "25: notifications mark-read POST without a token is rejected" "HTTP 403"
else
    harness_bad "25: notifications mark-read POST without a token is rejected" "HTTP $code"
fi

# 26. POST with a valid token succeeds and dispatches through to the real
# Snep_Notifications::setRead() call -- the vendor call itself is an
# external dependency outside this harness's control (TASK-0024's own
# non-throwing contract already covers that failure mode; no new fatal
# is the proof that matters here).
before_fatals="$(fatal_count)"
code="$(request "$ADMIN_JAR" POST /index.php/default/notifications/mark-read "id=1&snep_csrf_token=${ADMIN_CSRF}")"
after_fatals="$(fatal_count)"
if [ "$code" = "200" ] && [ "$before_fatals" = "$after_fatals" ]; then
    harness_ok "26: notifications mark-read POST with a valid token succeeds" "HTTP $code, no new fatals"
else
    harness_bad "26: notifications mark-read POST with a valid token succeeds" "HTTP $code, fatals ${before_fatals}->${after_fatals}"
fi

# =============================================================================
# 6. Standalone Basic-auth API remains functional without a CSRF token ------
# (F20 must not accidentally require a browser-session token on
# snep/modules/default/api/index.php -- TASK-0026F's separate, unauthenticated-
# bootstrap entry point, never routed through Snep_CsrfPlugin at all.)
# =============================================================================

log "==> standalone API unaffected by CSRF enforcement"

API_URL="${BASE_URL}/modules/default/api/index.php"
API_CODE="$(curl -sS -o "$BODY" -w '%{http_code}' -u "${ADMIN_USER}:${ADMIN_PASSWORD}" -G "$API_URL" --data-urlencode "service=CallsReport")"
if [ "$API_CODE" = "200" ] && grep -q '"status":"ok"' "$BODY"; then
    harness_ok "27: standalone Basic-auth API works with no CSRF token" "HTTP 200, status=ok -- never routed through Snep_CsrfPlugin"
else
    harness_bad "27: standalone Basic-auth API works with no CSRF token" "HTTP ${API_CODE}, body=$(head -c 200 "$BODY")"
fi

# =============================================================================
# Health
# =============================================================================

FATALS_AFTER="$(fatal_count)"
if [ "$FATALS_AFTER" = "$FATALS_BEFORE" ]; then
    harness_ok "application remained healthy" "PHP Fatal Error count unchanged (${FATALS_BEFORE})"
else
    harness_bad "application remained healthy" "PHP Fatal Error count changed: ${FATALS_BEFORE} -> ${FATALS_AFTER}"
fi

harness_complete
