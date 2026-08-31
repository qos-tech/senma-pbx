#!/bin/bash
#
# TASK-0026H authentication and default-install hardening focused
# security smoke test.
#
# Exercises the F21-F24/F27 findings from
# docs/tasks/0026-pre-pilot-security-release-audit.md (re-traced and
# remediated in
# docs/tasks/0026h-authentication-default-install-hardening.md):
#
#   F21 (unsalted MD5 password hashing): every password write path now
#   uses Snep_Security_Password::hash() (password_hash()); a legacy
#   md5() account migrates transparently on its next successful login,
#   via the shared Snep_Auth_Adapter_Password used by both browser login
#   and the standalone API.
#
#   F22 (no login rate limiting): Snep_Security_LoginThrottle throttles
#   repeated failures, scoped by (ip, username) and by ip alone, both
#   auto-expiring, backed by the `login_attempts` table.
#
#   F23 (weak PRNG for password-reset codes): AuthController::aleatorio()
#   now uses random_int().
#
#   F24 (Snep_AuthPlugin's action-name-only bypass check): now also
#   requires $controller == "auth".
#
#   F27 (fresh install ships admin/admin123): the install seed now holds
#   a sentinel that cannot authenticate anything;
#   docker/bootstrap-admin.php (invoked from docker/entrypoint.sh)
#   replaces it with a freshly generated random password_hash()'d
#   credential on first boot.
#
# Every payload below is harmless: real disposable fixture accounts this
# script owns, never a real credential, never a destructive action. The
# shared `admin` dev fixture is touched only for the F27 bootstrap-replay
# check (22) and is unconditionally restored to this project's own
# documented SmokeTest123! dev baseline via a REQUIRED cleanup, matching
# every other TASK-0026x suite's own established convention.
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
API_URL="${BASE_URL}/modules/default/api/index.php"
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

md5_of() {
    app_exec "php -r \"echo md5(\\\$argv[1]);\" -- '$1'" | tr -d '\r'
}

fatal_count() {
    local n
    n="$(app_exec 'grep -c "Fatal error" /var/log/apache2/mag-error.log 2>/dev/null' | tr -d '\r\n ')"
    echo "${n:-0}"
}

# looks_like_modern_hash <value> -- true only for a password_hash()-shaped
# string (starts with "$", e.g. "$2y$..." bcrypt). Deliberately the
# inverse check of Snep_Security_Password::isLegacyMd5() -- both a bare
# hex-32 string and this sentinel-shaped fixture data must fail this.
looks_like_modern_hash() {
    case "$1" in
        '$'*) return 0 ;;
        *) return 1 ;;
    esac
}

looks_like_legacy_md5() {
    printf '%s' "$1" | grep -qE '^[a-f0-9]{32}$'
}

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

# --- 0. Preflight --------------------------------------------------------

harness_require_containers app db
harness_require_env DB_USER DB_PASSWORD DB_NAME

BODY="$(mktemp)"
HEADERS="$(mktemp)"
harness_register_best_effort_cleanup "request temp files" "rm -f '$BODY' '$HEADERS'"

FATALS_BEFORE="$(fatal_count)"
log "==> baseline PHP Fatal Error count: ${FATALS_BEFORE}"

db_query "DELETE FROM login_attempts;" >/dev/null

# Baseline the shared admin fixture, matching every other TASK-0026x
# suite's own established convention -- reset BEFORE use, restored after.
ADMIN_HASH="$(md5_of "$ADMIN_PASSWORD")"
if [ -z "$ADMIN_HASH" ]; then
    harness_blocked "could not compute the admin password hash via the app container"
fi
db_query "UPDATE users SET password='${ADMIN_HASH}' WHERE name='${ADMIN_USER}';" >/dev/null
harness_register_cleanup "admin password restored to the SmokeTest123! dev baseline" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}' -e \"UPDATE users SET password='${ADMIN_HASH}' WHERE name='${ADMIN_USER}';\" >/dev/null"

ADMIN_JAR="$(mktemp)"
harness_register_best_effort_cleanup "admin cookie jar" "rm -f '$ADMIN_JAR'"
request "$ADMIN_JAR" POST /index.php/auth/login "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}" >/dev/null
ADMIN_CSRF="$(harness_csrf_token "$ADMIN_JAR" "$BASE_URL")"
if [ -z "$ADMIN_CSRF" ]; then
    harness_blocked "could not read the admin session's CSRF token"
fi

# =============================================================================
# 1. Modern hashing (checks 1-4) -- new user creation
# =============================================================================

log "==> Modern hashing: new user creation"

NEW_USER="task0026h-created"
NEW_PASSWORD="CreatedUser2026!"
db_query "DELETE FROM users WHERE name='${NEW_USER}';" >/dev/null

httpcode="$(curl -sS -c "$ADMIN_JAR" -b "$ADMIN_JAR" -o "$BODY" -w '%{http_code}' \
    --data-urlencode "name=${NEW_USER}" \
    --data-urlencode "password=${NEW_PASSWORD}" \
    --data-urlencode "email=${NEW_USER}@example.test" \
    --data-urlencode "profile_id=1" \
    --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
    "${BASE_URL}/index.php/default/users/add")"
NEW_USER_ID="$(db_query "SELECT id FROM users WHERE name='${NEW_USER}';")"
if [ "$httpcode" != "302" ] || [ -z "$NEW_USER_ID" ]; then
    harness_blocked "could not create fixture user ${NEW_USER} via the real UsersController::addAction() HTTP flow (HTTP ${httpcode})"
fi
harness_register_cleanup "fixture user ${NEW_USER} (id=${NEW_USER_ID})" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}' -e \"DELETE FROM users WHERE id=${NEW_USER_ID};\" >/dev/null"

STORED_HASH="$(db_query "SELECT password FROM users WHERE id=${NEW_USER_ID};")"

# 1. New user password is not stored as raw MD5.
if ! looks_like_legacy_md5 "$STORED_HASH" && looks_like_modern_hash "$STORED_HASH"; then
    harness_ok "1: new user password is not stored as raw MD5" "stored value is password_hash()-shaped, not a bare 32-hex-char digest"
else
    harness_bad "1: new user password is not stored as raw MD5" "stored='${STORED_HASH}'"
fi

# 2. Modern stored hash verifies correctly. A FRESH, unauthenticated jar
# -- $ADMIN_JAR is already authenticated, and Snep_CsrfPlugin (correctly)
# requires a token on ANY authenticated POST, including one that happens
# to target /auth/login.
VERIFY_JAR="$(mktemp)"
harness_register_best_effort_cleanup "new-user verify cookie jar" "rm -f '$VERIFY_JAR'"
code="$(request "$VERIFY_JAR" POST /index.php/auth/login "user=${NEW_USER}&password=${NEW_PASSWORD}")"
if [ "$code" = "302" ]; then
    harness_ok "2: modern stored hash verifies correctly" "HTTP $code"
else
    harness_bad "2: modern stored hash verifies correctly" "HTTP $code"
fi

# 3. Wrong password rejected.
FRESH_JAR="$(mktemp)"
harness_register_best_effort_cleanup "fresh cookie jar" "rm -f '$FRESH_JAR'"
code="$(request "$FRESH_JAR" POST /index.php/auth/login "user=${NEW_USER}&password=totally-wrong-password")"
if [ "$code" = "200" ] && ! grep -q 'var controller = "index"' "$BODY"; then
    harness_ok "3: wrong password rejected" "HTTP $code, not authenticated"
else
    harness_bad "3: wrong password rejected" "HTTP $code"
fi

# 4. The stored hash itself submitted as the password is rejected
# (pass-the-hash).
code="$(curl -sS -c "$FRESH_JAR" -b "$FRESH_JAR" -o "$BODY" -w '%{http_code}' --data-urlencode "user=${NEW_USER}" --data-urlencode "password=${STORED_HASH}" "${BASE_URL}/index.php/auth/login")"
if [ "$code" = "200" ] && ! grep -q 'var controller = "index"' "$BODY"; then
    harness_ok "4: stored hash submitted as password rejected" "HTTP $code, pass-the-hash does not authenticate"
else
    harness_bad "4: stored hash submitted as password rejected" "HTTP $code"
fi

# =============================================================================
# 2. Legacy migration (checks 5-8)
# =============================================================================

log "==> Legacy MD5 migration"

LEGACY_USER="task0026h-legacy"
LEGACY_PASSWORD="LegacyFixture2026!"
LEGACY_HASH="$(md5_of "$LEGACY_PASSWORD")"
db_query "DELETE FROM users WHERE name='${LEGACY_USER}';" >/dev/null
db_query "INSERT INTO users (name,password,email,dashboard,profile_id,created,updated) VALUES ('${LEGACY_USER}','${LEGACY_HASH}','${LEGACY_USER}@example.test','',1,NOW(),NOW());" >/dev/null
LEGACY_ID="$(db_query "SELECT id FROM users WHERE name='${LEGACY_USER}';")"
if [ -z "$LEGACY_ID" ]; then
    harness_blocked "could not provision the legacy-MD5 fixture user"
fi
harness_register_cleanup "fixture user ${LEGACY_USER} (id=${LEGACY_ID})" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}' -e \"DELETE FROM users WHERE id=${LEGACY_ID};\" >/dev/null"

STORED_BEFORE="$(db_query "SELECT password FROM users WHERE id=${LEGACY_ID};")"
if [ "$STORED_BEFORE" != "$LEGACY_HASH" ]; then
    harness_blocked "legacy fixture setup did not store the expected md5() value"
fi

# 5. Controlled legacy-MD5 fixture authenticates with correct plaintext.
LEGACY_JAR="$(mktemp)"
harness_register_best_effort_cleanup "legacy fixture cookie jar" "rm -f '$LEGACY_JAR'"
code="$(request "$LEGACY_JAR" POST /index.php/auth/login "user=${LEGACY_USER}&password=${LEGACY_PASSWORD}")"
if [ "$code" = "302" ]; then
    harness_ok "5: legacy-MD5 fixture authenticates with correct plaintext" "HTTP $code"
else
    harness_bad "5: legacy-MD5 fixture authenticates with correct plaintext" "HTTP $code"
fi

# 6. DB representation changes to modern hash after successful login.
STORED_AFTER="$(db_query "SELECT password FROM users WHERE id=${LEGACY_ID};")"
if ! looks_like_legacy_md5 "$STORED_AFTER" && looks_like_modern_hash "$STORED_AFTER" && [ "$STORED_AFTER" != "$STORED_BEFORE" ]; then
    harness_ok "6: DB representation changes to modern hash after successful login" "before='${STORED_BEFORE:0:12}...' after='${STORED_AFTER:0:12}...'"
else
    harness_bad "6: DB representation changes to modern hash after successful login" "stored='${STORED_AFTER}'"
fi

# 7. Migrated account still logs in afterward (now against the modern hash).
LEGACY_JAR2="$(mktemp)"
harness_register_best_effort_cleanup "legacy fixture second cookie jar" "rm -f '$LEGACY_JAR2'"
code="$(request "$LEGACY_JAR2" POST /index.php/auth/login "user=${LEGACY_USER}&password=${LEGACY_PASSWORD}")"
if [ "$code" = "302" ]; then
    harness_ok "7: migrated account still logs in afterward" "HTTP $code, now verified via password_verify()"
else
    harness_bad "7: migrated account still logs in afterward" "HTTP $code"
fi

# 8. Wrong password does not trigger migration -- a second, fresh legacy
# fixture, attacked with a wrong password, must remain untouched (still
# the exact original md5() value).
LEGACY_USER2="task0026h-legacy-untouched"
LEGACY_PASSWORD2="LegacyUntouched2026!"
LEGACY_HASH2="$(md5_of "$LEGACY_PASSWORD2")"
db_query "DELETE FROM users WHERE name='${LEGACY_USER2}';" >/dev/null
db_query "INSERT INTO users (name,password,email,dashboard,profile_id,created,updated) VALUES ('${LEGACY_USER2}','${LEGACY_HASH2}','${LEGACY_USER2}@example.test','',1,NOW(),NOW());" >/dev/null
LEGACY_ID2="$(db_query "SELECT id FROM users WHERE name='${LEGACY_USER2}';")"
if [ -z "$LEGACY_ID2" ]; then
    harness_blocked "could not provision the second legacy-MD5 fixture user"
fi
harness_register_cleanup "fixture user ${LEGACY_USER2} (id=${LEGACY_ID2})" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}' -e \"DELETE FROM users WHERE id=${LEGACY_ID2};\" >/dev/null"

WRONG_JAR="$(mktemp)"
harness_register_best_effort_cleanup "wrong-password cookie jar" "rm -f '$WRONG_JAR'"
request "$WRONG_JAR" POST /index.php/auth/login "user=${LEGACY_USER2}&password=definitely-not-it" >/dev/null
STORED_UNTOUCHED="$(db_query "SELECT password FROM users WHERE id=${LEGACY_ID2};")"
if [ "$STORED_UNTOUCHED" = "$LEGACY_HASH2" ]; then
    harness_ok "8: wrong password does not trigger migration" "stored value unchanged (still the original md5())"
else
    harness_bad "8: wrong password does not trigger migration" "stored='${STORED_UNTOUCHED}', expected unchanged '${LEGACY_HASH2}'"
fi

# =============================================================================
# 3. User-management paths (checks 9-12)
# =============================================================================

log "==> User-management password paths"

# 9. New user creation creates a modern password (re-states check 1
# against the SAME fixture from section 1, per the Phase 15 checklist's
# own separate numbering).
if ! looks_like_legacy_md5 "$STORED_HASH" && looks_like_modern_hash "$STORED_HASH"; then
    harness_ok "9: new user creation creates modern password" "same evidence as check 1"
else
    harness_bad "9: new user creation creates modern password" "stored='${STORED_HASH}'"
fi

# 10. Password change (edit) creates a modern password -- change the
# legacy-untouched fixture's password via the real editAction() HTTP flow.
CHANGED_PASSWORD="ChangedViaEdit2026!"
httpcode="$(curl -sS -c "$ADMIN_JAR" -b "$ADMIN_JAR" -o "$BODY" -w '%{http_code}' \
    --data-urlencode "name=${LEGACY_USER2}" \
    --data-urlencode "password=${CHANGED_PASSWORD}" \
    --data-urlencode "email=${LEGACY_USER2}@example.test" \
    --data-urlencode "profile_id=1" \
    --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
    "${BASE_URL}/index.php/default/users/edit/id/${LEGACY_ID2}")"
STORED_EDITED="$(db_query "SELECT password FROM users WHERE id=${LEGACY_ID2};")"
if [ "$httpcode" = "302" ] && ! looks_like_legacy_md5 "$STORED_EDITED" && looks_like_modern_hash "$STORED_EDITED"; then
    harness_ok "10: password change (edit) creates modern password" "HTTP $httpcode, stored value is now password_hash()-shaped"
else
    harness_bad "10: password change (edit) creates modern password" "HTTP $httpcode, stored='${STORED_EDITED}'"
fi
NEW_EDIT_JAR="$(mktemp)"
harness_register_best_effort_cleanup "edited-user cookie jar" "rm -f '$NEW_EDIT_JAR'"
code="$(request "$NEW_EDIT_JAR" POST /index.php/auth/login "user=${LEGACY_USER2}&password=${CHANGED_PASSWORD}")"
if [ "$code" = "302" ]; then
    harness_ok "10b: the newly-set edited password actually works" "HTTP $code"
else
    harness_bad "10b: the newly-set edited password actually works" "HTTP $code"
fi

# 11. Editing without a password change preserves the existing hash
# exactly (a blank password field must not rehash a hash).
STORED_BEFORE_NOCHANGE="$(db_query "SELECT password FROM users WHERE id=${LEGACY_ID2};")"
httpcode="$(curl -sS -c "$ADMIN_JAR" -b "$ADMIN_JAR" -o "$BODY" -w '%{http_code}' \
    --data-urlencode "name=${LEGACY_USER2}" \
    --data-urlencode "password=" \
    --data-urlencode "email=${LEGACY_USER2}-renamed@example.test" \
    --data-urlencode "profile_id=1" \
    --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
    "${BASE_URL}/index.php/default/users/edit/id/${LEGACY_ID2}")"
STORED_AFTER_NOCHANGE="$(db_query "SELECT password FROM users WHERE id=${LEGACY_ID2};")"
EMAIL_AFTER="$(db_query "SELECT email FROM users WHERE id=${LEGACY_ID2};")"
if [ "$httpcode" = "302" ] && [ "$STORED_AFTER_NOCHANGE" = "$STORED_BEFORE_NOCHANGE" ] && [ "$EMAIL_AFTER" = "${LEGACY_USER2}-renamed@example.test" ]; then
    harness_ok "11: editing without a password change preserves the existing hash exactly" "HTTP $httpcode, hash byte-identical, email field did update"
else
    harness_bad "11: editing without a password change preserves the existing hash exactly" "HTTP $httpcode, before='${STORED_BEFORE_NOCHANGE}' after='${STORED_AFTER_NOCHANGE}' email='${EMAIL_AFTER}'"
fi

# 12. Reset/redefinition path (AuthController::recuperationAction()) uses
# modern hashing. Exercises the real HTTP endpoint with a directly-seeded
# password_recovery row (redefineAction()'s own job is only to mint that
# row and email it -- not re-tested here, unrelated to password
# representation).
RECOVERY_USER="task0026h-recovery"
RECOVERY_OLD_PASSWORD="RecoveryOld2026!"
RECOVERY_NEW_PASSWORD="RecoveryNew2026!"
RECOVERY_HASH="$(md5_of "$RECOVERY_OLD_PASSWORD")"
db_query "DELETE FROM users WHERE name='${RECOVERY_USER}';" >/dev/null
db_query "INSERT INTO users (name,password,email,dashboard,profile_id,created,updated) VALUES ('${RECOVERY_USER}','${RECOVERY_HASH}','${RECOVERY_USER}@example.test','',1,NOW(),NOW());" >/dev/null
RECOVERY_ID="$(db_query "SELECT id FROM users WHERE name='${RECOVERY_USER}';")"
if [ -z "$RECOVERY_ID" ]; then
    harness_blocked "could not provision the password-recovery fixture user"
fi
harness_register_cleanup "fixture user ${RECOVERY_USER} (id=${RECOVERY_ID})" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}' -e \"DELETE FROM password_recovery WHERE user_id=${RECOVERY_ID}; DELETE FROM users WHERE id=${RECOVERY_ID};\" >/dev/null"

RECOVERY_CODE="TASK0026H"
db_query "DELETE FROM password_recovery WHERE user_id=${RECOVERY_ID};" >/dev/null
db_query "INSERT INTO password_recovery (user_id, code, created, expiration) VALUES (${RECOVERY_ID}, '${RECOVERY_CODE}', NOW(), DATE_ADD(NOW(), INTERVAL 1 HOUR));" >/dev/null

RECOVERY_JAR="$(mktemp)"
harness_register_best_effort_cleanup "recovery cookie jar" "rm -f '$RECOVERY_JAR'"
httpcode="$(curl -sS -c "$RECOVERY_JAR" -b "$RECOVERY_JAR" -o "$BODY" -w '%{http_code}' \
    --data-urlencode "username=${RECOVERY_USER}" \
    --data-urlencode "password=${RECOVERY_NEW_PASSWORD}" \
    --data-urlencode "newpassword=${RECOVERY_NEW_PASSWORD}" \
    --data-urlencode "code=${RECOVERY_CODE}" \
    "${BASE_URL}/index.php/auth/recuperation")"
STORED_RECOVERY="$(db_query "SELECT password FROM users WHERE id=${RECOVERY_ID};")"
if [ "$httpcode" = "302" ] && ! looks_like_legacy_md5 "$STORED_RECOVERY" && looks_like_modern_hash "$STORED_RECOVERY"; then
    harness_ok "12: reset/redefinition path uses modern hashing" "HTTP $httpcode, stored value is password_hash()-shaped"
else
    harness_bad "12: reset/redefinition path uses modern hashing" "HTTP $httpcode, stored='${STORED_RECOVERY}'"
fi
code="$(request "$RECOVERY_JAR" POST /index.php/auth/login "user=${RECOVERY_USER}&password=${RECOVERY_NEW_PASSWORD}")"
if [ "$code" = "302" ]; then
    harness_ok "12b: the newly-reset password actually works" "HTTP $code"
else
    harness_bad "12b: the newly-reset password actually works" "HTTP $code"
fi

# =============================================================================
# 4. Standalone API (checks 13-15)
# =============================================================================

log "==> Standalone Basic-auth API"

before_fatals="$(fatal_count)"
API_CODE="$(curl -sS -o "$BODY" -w '%{http_code}' -u "${NEW_USER}:${NEW_PASSWORD}" -G "$API_URL" --data-urlencode "service=CallsReport")"
after_fatals="$(fatal_count)"
if [ "$API_CODE" = "200" ] && grep -q '"status":"ok"' "$BODY" && [ "$before_fatals" = "$after_fatals" ]; then
    harness_ok "13: modern account authenticates through the API using plaintext" "HTTP $API_CODE, status=ok"
else
    harness_bad "13: modern account authenticates through the API using plaintext" "HTTP ${API_CODE}, body=$(head -c 200 "$BODY")"
fi

# 14. A legacy account can authenticate (and migrate) through the API --
# a fresh legacy fixture, since check 5-7 already migrated the first one.
LEGACY_USER3="task0026h-legacy-api"
LEGACY_PASSWORD3="LegacyApi2026!"
LEGACY_HASH3="$(md5_of "$LEGACY_PASSWORD3")"
db_query "DELETE FROM users WHERE name='${LEGACY_USER3}';" >/dev/null
db_query "INSERT INTO users (name,password,email,dashboard,profile_id,created,updated) VALUES ('${LEGACY_USER3}','${LEGACY_HASH3}','${LEGACY_USER3}@example.test','',1,NOW(),NOW());" >/dev/null
LEGACY_ID3="$(db_query "SELECT id FROM users WHERE name='${LEGACY_USER3}';")"
if [ -z "$LEGACY_ID3" ]; then
    harness_blocked "could not provision the API legacy-MD5 fixture user"
fi
harness_register_cleanup "fixture user ${LEGACY_USER3} (id=${LEGACY_ID3})" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}' -e \"DELETE FROM users WHERE id=${LEGACY_ID3};\" >/dev/null"

API_CODE="$(curl -sS -o "$BODY" -w '%{http_code}' -u "${LEGACY_USER3}:${LEGACY_PASSWORD3}" -G "$API_URL" --data-urlencode "service=CallsReport")"
STORED_API_AFTER="$(db_query "SELECT password FROM users WHERE id=${LEGACY_ID3};")"
if [ "$API_CODE" = "200" ] && grep -q '"status":"ok"' "$BODY" && ! looks_like_legacy_md5 "$STORED_API_AFTER"; then
    harness_ok "14: legacy account authenticates and migrates through the API" "HTTP $API_CODE, stored value now password_hash()-shaped"
else
    harness_bad "14: legacy account authenticates and migrates through the API" "HTTP ${API_CODE}, stored='${STORED_API_AFTER}'"
fi

# 15. Pass-the-hash remains rejected via the API (re-running TASK-0026F's
# own F17-A coverage against this new shared adapter). 401 is reserved
# for "no credentials supplied at all" (index.php's else branch); WRONG
# credentials that WERE supplied -- pass-the-hash included -- fall
# through to error("User or password invalid"), HTTP 200 with a JSON
# error body, matching api-security-smoke-test.sh's own established
# "wrong password rejected" convention for this endpoint.
API_CODE="$(curl -sS -o "$BODY" -w '%{http_code}' -u "${NEW_USER}:${STORED_HASH}" -G "$API_URL" --data-urlencode "service=CallsReport")"
if [ "$API_CODE" = "200" ] && grep -q '"status":"error"' "$BODY"; then
    harness_ok "15: pass-the-hash remains rejected via the API" "HTTP $API_CODE, status=error"
else
    harness_bad "15: pass-the-hash remains rejected via the API" "HTTP ${API_CODE}, body=$(head -c 200 "$BODY")"
fi

# =============================================================================
# 5. Rate limiting (checks 16-20)
# =============================================================================

log "==> Login rate limiting"

db_query "DELETE FROM login_attempts;" >/dev/null

THROTTLE_USER="task0026h-throttle"

# 16. Ordinary failed login rejected (not yet throttled).
RL_JAR="$(mktemp)"
harness_register_best_effort_cleanup "rate-limit cookie jar" "rm -f '$RL_JAR'"
code="$(request "$RL_JAR" POST /index.php/auth/login "user=${THROTTLE_USER}&password=wrong0")"
if [ "$code" = "200" ] && ! grep -qi 'too many' "$BODY"; then
    harness_ok "16: ordinary failed login rejected, not yet throttled" "HTTP $code"
else
    harness_bad "16: ordinary failed login rejected, not yet throttled" "HTTP $code"
fi

# 17. Repeated failures trigger the limiter (MAX_FAILURES_PER_ACCOUNT = 5
# in Snep_Security_LoginThrottle; 1 already recorded by check 16 above).
for i in 2 3 4 5; do
    request "$RL_JAR" POST /index.php/auth/login "user=${THROTTLE_USER}&password=wrong${i}" >/dev/null
done
code="$(request "$RL_JAR" POST /index.php/auth/login "user=${THROTTLE_USER}&password=wrong6")"
if [ "$code" = "200" ] && grep -qi 'too many' "$BODY"; then
    harness_ok "17: repeated failures trigger the limiter" "HTTP $code, throttle message shown"
else
    harness_bad "17: repeated failures trigger the limiter" "HTTP $code, body=$(head -c 200 "$BODY")"
fi

# 18. The limiter survives a brand-new session/cookie -- it is keyed by
# (ip, username) in the database, never by session state.
NOSESSION_JAR="$(mktemp)"
harness_register_best_effort_cleanup "no-session cookie jar" "rm -f '$NOSESSION_JAR'"
code="$(request "$NOSESSION_JAR" POST /index.php/auth/login "user=${THROTTLE_USER}&password=wrong-again-fresh-cookie")"
if [ "$code" = "200" ] && grep -qi 'too many' "$BODY"; then
    harness_ok "18: limiter survives a brand-new session/cookie" "HTTP $code, still throttled from a fresh cookie jar"
else
    harness_bad "18: limiter survives a brand-new session/cookie" "HTTP $code, body=$(head -c 200 "$BODY")"
fi

# 19. Expiration: directly age the recorded failures past the throttle
# window (WINDOW_MINUTES = 15) -- deterministic, no real multi-minute
# sleep. A fresh attempt must then be treated as un-throttled again (a
# wrong password now shows the ordinary failure message, not the
# throttle one; it also re-records itself as ONE fresh recent failure).
db_query "UPDATE login_attempts SET attempted_at = DATE_SUB(NOW(), INTERVAL 20 MINUTE) WHERE username='${THROTTLE_USER}';" >/dev/null
code="$(request "$RL_JAR" POST /index.php/auth/login "user=${THROTTLE_USER}&password=wrong-after-expiry")"
if [ "$code" = "200" ] && ! grep -qi 'too many' "$BODY"; then
    harness_ok "19: throttle expires once the window elapses" "HTTP $code, ordinary rejection again, not throttled"
else
    harness_bad "19: throttle expires once the window elapses" "HTTP $code, body=$(head -c 200 "$BODY")"
fi
db_query "DELETE FROM login_attempts WHERE username='${THROTTLE_USER}';" >/dev/null

# 20. A successful login clears that account's own throttle state, and a
# DIFFERENT username is never blocked by another username's failures from
# the same source -- proving the per-account dimension is scoped by (ip,
# username), never username alone (Phase 8's own explicit "avoid locking
# a victim account indefinitely through username-only abuse"). A true
# different-SOURCE-IP proof is out of reach for a single curl-based
# harness talking to one app instance; this proves the scoping that
# guarantees it.
for i in 1 2 3 4 5; do
    request "$RL_JAR" POST /index.php/auth/login "user=${THROTTLE_USER}&password=wrong-retry${i}" >/dev/null
done
THROTTLE_COUNT="$(db_query "SELECT COUNT(*) FROM login_attempts WHERE username='${THROTTLE_USER}';")"
if [ "${THROTTLE_COUNT:-0}" -lt 5 ]; then
    harness_blocked "could not re-establish a throttled state for check 20 (count=${THROTTLE_COUNT})"
fi
code="$(request "$RL_JAR" POST /index.php/auth/login "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}")"
if [ "$code" = "302" ]; then
    harness_ok "20: an unrelated username from the same source is not blocked" "HTTP $code, admin login succeeds despite ${THROTTLE_USER}'s own throttled state"
else
    harness_bad "20: an unrelated username from the same source is not blocked" "HTTP $code"
fi
ADMIN_REMAINING="$(db_query "SELECT COUNT(*) FROM login_attempts WHERE username='${ADMIN_USER}';")"
if [ "${ADMIN_REMAINING:-0}" = "0" ]; then
    harness_ok "20b: a successful login clears that account's own failure history" "0 login_attempts rows remain for ${ADMIN_USER}"
else
    harness_bad "20b: a successful login clears that account's own failure history" "${ADMIN_REMAINING} rows remain"
fi
db_query "DELETE FROM login_attempts;" >/dev/null

# =============================================================================
# 6. Default installation / F27 (checks 21-23)
# =============================================================================

log "==> Default installation (F27)"

# 21. Install/bootstrap SQL no longer contains an operational admin123
# credential. Checked against the actual INSERT statement only (`grep -v
# '^--'` strips comment lines) -- this task's own explanatory comment
# right above that INSERT deliberately documents the old value by name,
# which must not itself count as "still shipping" it.
SEED_FILE="$REPO_ROOT/snep/install/database/system_data.sql"
if ! grep -v '^--' "$SEED_FILE" | grep -q '0192023a7bbd73250516f069df18b500' \
    && grep -q 'SENMA-BOOTSTRAP-PENDING' "$SEED_FILE"; then
    harness_ok "21: install seed no longer ships the admin123 credential" "old md5('admin123') value absent, bootstrap sentinel present"
else
    harness_bad "21: install seed no longer ships the admin123 credential" "unexpected content in $SEED_FILE"
fi

# 22. The bootstrap mechanism is enforced, end to end: the sentinel
# cannot authenticate as anything, and re-running the real bootstrap
# script replaces it with a freshly generated, working credential.
db_query "UPDATE users SET password='!SENMA-BOOTSTRAP-PENDING!' WHERE name='${ADMIN_USER}';" >/dev/null
SENTINEL_JAR="$(mktemp)"
harness_register_best_effort_cleanup "sentinel-state cookie jar" "rm -f '$SENTINEL_JAR'"
code_a="$(request "$SENTINEL_JAR" POST /index.php/auth/login "user=${ADMIN_USER}&password=admin123")"
code_b="$(request "$SENTINEL_JAR" POST /index.php/auth/login "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}")"
code_c="$(curl -sS -o /dev/null -w '%{http_code}' --data-urlencode "user=${ADMIN_USER}" --data-urlencode "password=!SENMA-BOOTSTRAP-PENDING!" "${BASE_URL}/index.php/auth/login")"
if [ "$code_a" != "302" ] && [ "$code_b" != "302" ] && [ "$code_c" != "302" ]; then
    harness_ok "22a: the sentinel cannot be logged into with any plaintext" "admin123 -> HTTP $code_a, SmokeTest123! -> HTTP $code_b, sentinel-as-password -> HTTP $code_c, none authenticate"
else
    harness_bad "22a: the sentinel cannot be logged into with any plaintext" "admin123 -> HTTP $code_a, SmokeTest123! -> HTTP $code_b, sentinel-as-password -> HTTP $code_c"
fi

BOOTSTRAP_OUTPUT="$(app_exec "php /usr/local/bin/bootstrap-admin.php" 2>&1)"
GENERATED_PASSWORD="$(printf '%s' "$BOOTSTRAP_OUTPUT" | grep 'password:' | sed -E 's/.*password: *//' | tr -d '\r')"
if [ -z "$GENERATED_PASSWORD" ]; then
    harness_bad "22b: bootstrap-admin.php generates and prints a fresh credential" "no password line found in output: $(printf '%s' "$BOOTSTRAP_OUTPUT" | head -c 300)"
else
    harness_ok "22b: bootstrap-admin.php generates and prints a fresh credential" "credential printed to stdout, ${#GENERATED_PASSWORD} characters"
fi
BOOTSTRAP_JAR="$(mktemp)"
harness_register_best_effort_cleanup "bootstrap-generated cookie jar" "rm -f '$BOOTSTRAP_JAR'"
code="$(request "$BOOTSTRAP_JAR" POST /index.php/auth/login "user=${ADMIN_USER}&password=${GENERATED_PASSWORD}")"
if [ "$code" = "302" ]; then
    harness_ok "22c: the freshly bootstrapped credential actually works" "HTTP $code"
else
    harness_bad "22c: the freshly bootstrapped credential actually works" "HTTP $code"
fi
# Idempotency: running it again while already bootstrapped must not
# regenerate/print a new credential.
REPLAY_OUTPUT="$(app_exec "php /usr/local/bin/bootstrap-admin.php" 2>&1)"
if ! printf '%s' "$REPLAY_OUTPUT" | grep -q 'password:'; then
    harness_ok "22d: bootstrap-admin.php is idempotent" "no second credential generated once already bootstrapped"
else
    harness_bad "22d: bootstrap-admin.php is idempotent" "unexpected second credential output: $(printf '%s' "$REPLAY_OUTPUT" | head -c 300)"
fi

ENTRYPOINT_FILE="$REPO_ROOT/docker/entrypoint.sh"
if grep -q 'bootstrap-admin.php' "$ENTRYPOINT_FILE"; then
    harness_ok "22e: the bootstrap mechanism runs on every container start" "docker/entrypoint.sh invokes bootstrap-admin.php"
else
    harness_bad "22e: the bootstrap mechanism runs on every container start" "docker/entrypoint.sh does not reference bootstrap-admin.php"
fi

# 23. Dev/test known credentials are explicitly separate from the
# production bootstrap path -- the bootstrap script/entrypoint must never
# itself reference this project's own documented dev-only password, and
# this suite's own dev fixture setup (above, top of this script) is what
# actually provisions it, via an explicit, auditable DB reset -- never
# something a fresh production bootstrap does automatically.
BOOTSTRAP_FILE="$REPO_ROOT/docker/bootstrap-admin.php"
if ! grep -qi 'SmokeTest123' "$BOOTSTRAP_FILE" && ! grep -qi 'SmokeTest123' "$ENTRYPOINT_FILE"; then
    harness_ok "23: dev/test known credential is never referenced by the production bootstrap path" "docker/bootstrap-admin.php and docker/entrypoint.sh contain no dev-only credential string"
else
    harness_bad "23: dev/test known credential is never referenced by the production bootstrap path" "found a dev-only credential string in the bootstrap path"
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
