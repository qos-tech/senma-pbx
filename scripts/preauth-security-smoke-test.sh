#!/bin/bash
# TASK-0026B pre-authentication security hardening regression harness.
#
# Verifies the finite-domain language allowlist (F1) and the parameterized
# BINARY username comparison (F6) hold, without ever touching a real
# vendor or leaving the dev environment's setup.conf mutated.
#
# TASK-0027: rebuilt on scripts/lib/harness.sh. `set -e` was removed --
# it previously meant an infrastructure hiccup (e.g. the app container
# not running when the initial `cp` backup runs) would abort the script
# silently before any PASS/FAIL/summary line was printed. The setup.conf
# backup/restore is unconditional and re-captured at the top of every run
# (before any mutation), so a stale backup file from a prior interrupted
# run can never corrupt a later run.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

BASE_URL="http://127.0.0.1:${SENMA_HTTP_PORT:-8080}"
COMPOSE="${SMOKE_COMPOSE:-docker compose}"
CFG=/var/www/html/snep/includes/setup.conf
BACKUP=/tmp/task0026b-setup.conf
TEST_USER="admin"
TEST_PASSWORD="SmokeTest123!"

harness_require_containers app db asterisk
harness_require_env DB_USER DB_PASSWORD DB_NAME

# TASK-0034: this suite's own "admin login" check below assumes
# $TEST_USER's password is already $TEST_PASSWORD, but -- unlike every
# sibling security suite (sql-security-smoke-test.sh,
# residual-sql-security-smoke-test.sh, etc.) -- it never set that
# password itself. That made it depend on suite ORDER/history (only
# passing if some earlier suite/session had already run this exact
# UPDATE), and it is the third suite `make regression` runs -- before
# any suite that does set it. Confirmed live: on a stack freshly brought
# up via `make reset && make dev` (no other suite/session run against it
# yet), this suite's own "admin login" check failed (HTTP 200, not 302)
# for exactly this reason, breaking the canonical regression gate's
# determinism from a genuinely fresh install. Mirrors
# sql-security-smoke-test.sh's own established pattern exactly.
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${TEST_PASSWORD}');" 2>/dev/null | tr -d '\r')"
if [ -z "$TEST_HASH" ]; then
    harness_blocked "could not compute the ${TEST_USER} password hash via the app container"
fi
$COMPOSE exec -T db mariadb -u"${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" -N \
    -e "UPDATE users SET password = '${TEST_HASH}' WHERE name = '${TEST_USER}';" >&2

tmp="$(mktemp -d)"
harness_register_best_effort_cleanup "temp working dir" "rm -rf '$tmp'"

if ! $COMPOSE exec -T app cp "$CFG" "$BACKUP"; then
    harness_blocked "could not back up setup.conf inside the app container before mutating it"
fi
harness_register_cleanup "setup.conf restored to its pre-test state" \
    "$COMPOSE exec -T app cp '$BACKUP' '$CFG'"

for lang in en pt_BR es; do
    code=$(curl -sS -o /dev/null -w '%{http_code}' "$BASE_URL/index.php/default/auth/login?indexChooseLanguage=$lang")
    if [ "$code" = 302 ]; then harness_ok "valid language $lang" "HTTP $code"; else harness_bad "valid language $lang" "HTTP $code"; fi
done

# TASK-0034K: AuthController::loginAction()'s indexChooseLanguage handler
# used to write setup.conf's global system.language AND call
# Snep_Locale::setExtensionsLanguage() (rewriting extensions.conf's
# SNEP_LANGUAGE + forcing a live Asterisk dialplan reload) directly from
# this same unauthenticated GET -- reachable by any anonymous visitor, no
# CSRF applicability (no session exists yet), no authorization check. See
# docs/tasks/0034k-call-language-authority-pre-auth-locale-hardening.md
# for the live reproduction that found this. It is now a pure
# session-scoped UI_LOCALE preference (Snep_Locale::resolveUiLanguage()):
# this proves (a) the choice actually lands in the session, and (b)
# setup.conf, extensions.conf and the live Asterisk global are all
# byte-for-byte untouched by a VALID language choice too -- the loop just
# above only ever checked HTTP 302, and the invalid-language check further
# below predates this task and only ever covered the *invalid* case (a
# valid one used to legitimately mutate all three).
EXT_CONF=/etc/asterisk/extensions.conf
ANON_JAR="$tmp/anon.cookies"
$COMPOSE exec -T app cp "$CFG" /tmp/task0034k-before-setup.conf
$COMPOSE exec -T asterisk cp "$EXT_CONF" /tmp/task0034k-before-extensions.conf
GLOBALS_BEFORE="$($COMPOSE exec -T asterisk asterisk -rx 'dialplan show globals' 2>&1)"

code=$(curl -sS -c "$ANON_JAR" -o /dev/null -w '%{http_code}' "$BASE_URL/index.php/default/auth/login?indexChooseLanguage=es")
SESSID="$(awk '$6=="PHPSESSID"{print $7}' "$ANON_JAR" 2>/dev/null)"
if [ "$code" = 302 ] && [ -n "$SESSID" ]; then
    harness_ok 'anonymous language choice succeeds (UI only)' "HTTP $code"
else
    harness_bad 'anonymous language choice succeeds (UI only)' "HTTP $code, no session cookie issued"
fi

if [ -n "$SESSID" ] && $COMPOSE exec -T app sh -c "grep -q 'snep_ui_language.*\"es\"' /tmp/sess_$SESSID" 2>/dev/null; then
    harness_ok 'anonymous choice is session-scoped, not global' "PHPSESSID=$SESSID's own session carries snep_ui_language=es"
else
    harness_bad 'anonymous choice is session-scoped, not global' "session file for PHPSESSID=$SESSID missing snep_ui_language"
fi

if $COMPOSE exec -T app cmp /tmp/task0034k-before-setup.conf "$CFG"; then
    harness_ok 'anonymous valid-language choice never mutates setup.conf' "byte-identical before/after"
else
    harness_bad 'anonymous valid-language choice never mutates setup.conf' "setup.conf changed after a VALID indexChooseLanguage value"
fi

if $COMPOSE exec -T asterisk cmp /tmp/task0034k-before-extensions.conf "$EXT_CONF"; then
    harness_ok 'anonymous valid-language choice never propagates to extensions.conf' "byte-identical before/after"
else
    harness_bad 'anonymous valid-language choice never propagates to extensions.conf' "extensions.conf changed after an anonymous request"
fi

GLOBALS_AFTER="$($COMPOSE exec -T asterisk asterisk -rx 'dialplan show globals' 2>&1)"
if [ "$GLOBALS_BEFORE" = "$GLOBALS_AFTER" ]; then
    harness_ok 'anonymous valid-language choice never reaches the live dialplan' "SNEP_LANGUAGE global unchanged"
else
    harness_bad 'anonymous valid-language choice never reaches the live dialplan' "dialplan globals changed:\n$GLOBALS_BEFORE\n---\n$GLOBALS_AFTER"
fi

$COMPOSE exec -T app cp "$CFG" /tmp/task0026b-before.conf
code=$(curl -sS -o "$tmp/bad" -w '%{http_code}' "$BASE_URL/index.php/default/auth/login?indexChooseLanguage=invalid-task0026b")
if $COMPOSE exec -T app cmp /tmp/task0026b-before.conf "$CFG"; then
    harness_ok 'invalid language causes no setup.conf mutation' "HTTP $code"
else
    harness_bad 'invalid language causes no setup.conf mutation' "setup.conf changed after an invalid indexChooseLanguage value"
fi
if grep -qi 'Fatal error\|Stack trace' "$tmp/bad"; then
    harness_bad 'invalid language safe response' 'error text leaked into the response body'
else
    harness_ok 'invalid language safe response' "HTTP $code, no error text leaked"
fi

for user in nobody "x' AND 1=0 -- " "x' OR 1=1 -- "; do
    code=$(curl -sS -o "$tmp/login" -w '%{http_code}' --data-urlencode "user=$user" --data-urlencode 'password=wrong' "$BASE_URL/index.php/auth/login")
    if [ "$code" = 200 ] && grep -q 'login' "$tmp/login"; then
        harness_ok 'SQL-shaped/nonexistent username fails literally' "user='$user', HTTP $code"
    else
        harness_bad 'SQL-shaped/nonexistent username fails literally' "user='$user', HTTP $code"
    fi
done

code=$(curl -sS -o /dev/null -w '%{http_code}' --data-urlencode "user=${TEST_USER}" --data-urlencode "password=${TEST_PASSWORD}" "$BASE_URL/index.php/auth/login")
if [ "$code" = 302 ]; then harness_ok 'admin login' "HTTP $code"; else harness_bad 'admin login' "HTTP $code"; fi

harness_complete
