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

harness_require_containers app db
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
