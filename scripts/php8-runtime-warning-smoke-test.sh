#!/bin/bash
# TASK-0034I-R3 focused regression: PHP 8 runtime warnings observed on
# real v0.1.0-rc.13 pilot navigation (TEXTE-PBX-001).
#
# Covers three families only (not a repository-wide PHP 8 sweep):
#   A) System Status widget indexData['apt'] (global async statusbar)
#   B) CallsReportController session/user period access
#   C) Zend_View_Helper_HeadLink compact() undefined $extras
#
# See docs/tasks/0034i-r3-php8-runtime-warning-sweep.md.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

BASE_URL="${PHP8_RUNTIME_SMOKE_BASE_URL:-http://127.0.0.1:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
COMPOSE="${SMOKE_COMPOSE:-docker compose}"
ADMIN_USER=admin
ADMIN_PASSWORD="SmokeTest123!"
DB_USER="${DB_USER:-snep}"
DB_PASSWORD="${DB_PASSWORD:-change-me-for-local-development}"
DB_NAME="${DB_NAME:-snep}"

TMPDIR_R3="$(mktemp -d)"
harness_register_best_effort_cleanup "temp working dir" "rm -rf '$TMPDIR_R3'"
JAR="$TMPDIR_R3/admin.cookies"
BODY="$TMPDIR_R3/body"
HEADERS="$TMPDIR_R3/headers"

request() {
    local method="$1" path="$2" data="${3:-}"
    if [ "$method" = POST ]; then
        curl -sS -b "$JAR" -c "$JAR" -D "$HEADERS" -o "$BODY" -w '%{http_code}' -d "$data" "$BASE_URL$path"
    else
        curl -sS -b "$JAR" -c "$JAR" -D "$HEADERS" -o "$BODY" -w '%{http_code}' "$BASE_URL$path"
    fi
}

echo '==> Preflight'
harness_require_containers app db

VIEW="$REPO_ROOT/snep/modules/default/views/scripts/systemstatus/index.phtml"
CTRL="$REPO_ROOT/snep/modules/default/controllers/CallsReportController.php"
HEADLINK="$REPO_ROOT/snep/lib/Zend/View/Helper/HeadLink.php"
REPORTS="$REPO_ROOT/snep/lib/Snep/Reports.php"

echo '==> Static guards against exact pilot unsafe forms'
# A: exact pilot form echo $this->indexData["apt"] without empty() gate
if grep -nE 'echo[[:space:]]+\$this->indexData\[["'\'']apt["'\'']\]' "$VIEW" >/dev/null; then
    harness_bad 'no unsafe apt indexData access' 'found unguarded echo of indexData[apt]'
else
    harness_ok 'no unsafe apt indexData access' 'pilot echo form removed; apt gated by empty()'
fi
if grep -qE "indexData\[['\"]snep['\"]\]" "$VIEW"; then
    harness_ok 'SNEP version still rendered via snep key' 'Server Status snep row present'
else
    harness_bad 'SNEP version still rendered via snep key' 'indexData[snep] missing from view'
fi
# Require empty()/isset gate if apt is still referenced at all
if grep -qF "indexData['apt']" "$VIEW" || grep -qF 'indexData["apt"]' "$VIEW"; then
    if grep -qF "empty(\$this->indexData['apt'])" "$VIEW" \
        || grep -qF 'empty($this->indexData["apt"])' "$VIEW" \
        || grep -qF "isset(\$this->indexData['apt'])" "$VIEW"; then
        harness_ok 'apt access existence-gated when present' 'empty()/isset around apt'
    else
        harness_bad 'apt access existence-gated when present' 'apt referenced without empty/isset gate'
    fi
fi

# B: bare $_SESSION[$user['name']]['period'] boolean/index without helper
if grep -nE "\\\$_SESSION\[\\\$user\[['\\\"]name['\\\"]\]\]\[['\\\"]period['\\\"]\]" "$CTRL" >/dev/null; then
    harness_bad 'no unsafe CallsReport session period indexing' 'found $_SESSION[$user[name]][period] direct access'
else
    harness_ok 'no unsafe CallsReport session period indexing' 'CallsReport uses Snep_Reports helpers'
fi
grep -q 'getSavedPeriod\|setSavedPeriod' "$CTRL" \
    && harness_ok 'CallsReport uses period helpers' 'getSavedPeriod/setSavedPeriod call sites' \
    || harness_bad 'CallsReport uses period helpers' 'helper call sites missing'

# C: compact(...extras) without prior $extras = array()
if grep -nE "\\\$extras = array\(\);" "$HEADLINK" >/dev/null \
    && grep -nE "compact\([^)]*'extras'[^)]*\)" "$HEADLINK" >/dev/null; then
    harness_ok 'HeadLink initializes \$extras before compact' 'PHP 8 compact guard present'
else
    harness_bad 'HeadLink initializes \$extras before compact' 'missing \$extras = array() before compact'
fi

echo '==> Fixture: apt view semantics (absent / empty / present)'
APT_OUT="$($COMPOSE exec -T app php -d display_errors=1 -d error_reporting=E_ALL -r "
\$w = array();
set_error_handler(function (\$n, \$s) use (&\$w) { \$w[] = \$s; return true; });
\$render = function (\$indexData) {
    ob_start();
    // Mirror the TASK-0034I-R3 gated apt block.
    if (!empty(\$indexData['apt'])) {
        echo '[' . htmlspecialchars((string) \$indexData['apt'], ENT_QUOTES, 'UTF-8') . ']';
    }
    return ob_get_clean();
};
echo 'apt_absent=' . \$render(array()) . PHP_EOL;
echo 'apt_empty=' . \$render(array('apt' => '')) . PHP_EOL;
echo 'apt_present=' . \$render(array('apt' => 'legacy-1.2.3')) . PHP_EOL;
echo 'warn_count=' . count(\$w) . PHP_EOL;
" 2>&1 | tr -d '\r')"

echo "$APT_OUT" | grep -q '^apt_absent=$' \
    && harness_ok 'apt key absent -> no output, no warning' 'apt_absent empty' \
    || harness_bad 'apt key absent -> no output, no warning' "$APT_OUT"
echo "$APT_OUT" | grep -q '^apt_empty=$' \
    && harness_ok 'apt key empty -> omitted' 'apt_empty empty' \
    || harness_bad 'apt key empty -> omitted' "$APT_OUT"
echo "$APT_OUT" | grep -q '^apt_present=\[legacy-1.2.3\]$' \
    && harness_ok 'apt key present -> rendered' 'apt_present=[legacy-1.2.3]' \
    || harness_bad 'apt key present -> rendered' "$APT_OUT"
echo "$APT_OUT" | grep -q '^warn_count=0$' \
    && harness_ok 'apt fixtures emit no PHP warnings' 'warn_count=0' \
    || harness_bad 'apt fixtures emit no PHP warnings' "$APT_OUT"

echo '==> Fixture: CallsReport period helpers'
PERIOD_OUT="$($COMPOSE exec -T app php -d display_errors=1 -d error_reporting=E_ALL -r "
require_once '/var/www/html/snep/lib/Snep/Reports.php';
\$w = array();
set_error_handler(function (\$n, \$s) use (&\$w) { \$w[] = \$s; return true; });
\$j = function (\$v) { return \$v === null ? 'NULL' : \$v; };

\$userOk = array('id' => 1, 'name' => 'admin');
\$saved = array('admin' => array('period' => '01/01/2026 00:00 - 31/01/2026 23:59'));
echo 'valid_period=' . \$j(Snep_Reports::getSavedPeriod(\$userOk, \$saved)) . PHP_EOL;
echo 'no_session=' . \$j(Snep_Reports::getSavedPeriod(\$userOk, array())) . PHP_EOL;
echo 'ns_no_period=' . \$j(Snep_Reports::getSavedPeriod(\$userOk, array('admin' => array('other' => 1)))) . PHP_EOL;
echo 'user_false=' . \$j(Snep_Reports::getSavedPeriod(false, \$saved)) . PHP_EOL;
echo 'user_null=' . \$j(Snep_Reports::getSavedPeriod(null, \$saved)) . PHP_EOL;
echo 'user_no_name=' . \$j(Snep_Reports::getSavedPeriod(array('id' => 1), \$saved)) . PHP_EOL;

\$sess = array();
\$ok = Snep_Reports::setSavedPeriod(\$userOk, \$sess, '01/02/2026 00:00 - 28/02/2026 23:59');
echo 'set_ok=' . (\$ok ? '1' : '0') . ' period=' . \$sess['admin']['period'] . PHP_EOL;
\$sess2 = array();
\$bad = Snep_Reports::setSavedPeriod(false, \$sess2, 'x');
echo 'set_false_user=' . (\$bad ? '1' : '0') . ' keys=' . count(\$sess2) . PHP_EOL;
echo 'warn_count=' . count(\$w) . PHP_EOL;
if (count(\$w)) { echo 'warns=' . implode('|', \$w) . PHP_EOL; }
" 2>&1 | tr -d '\r')"

echo "$PERIOD_OUT" | grep -q '^valid_period=01/01/2026 00:00 - 31/01/2026 23:59$' \
    && harness_ok 'valid user + saved period' 'period restored' \
    || harness_bad 'valid user + saved period' "$PERIOD_OUT"
echo "$PERIOD_OUT" | grep -q '^no_session=NULL$' \
    && harness_ok 'valid user + no session key -> default' 'no_session=NULL' \
    || harness_bad 'valid user + no session key -> default' "$PERIOD_OUT"
echo "$PERIOD_OUT" | grep -q '^ns_no_period=NULL$' \
    && harness_ok 'namespace without period -> default' 'ns_no_period=NULL' \
    || harness_bad 'namespace without period -> default' "$PERIOD_OUT"
echo "$PERIOD_OUT" | grep -q '^user_false=NULL$' \
    && harness_ok 'getName false -> safe default' 'user_false=NULL' \
    || harness_bad 'getName false -> safe default' "$PERIOD_OUT"
echo "$PERIOD_OUT" | grep -q '^user_null=NULL$' \
    && harness_ok 'getName null -> safe default' 'user_null=NULL' \
    || harness_bad 'getName null -> safe default' "$PERIOD_OUT"
echo "$PERIOD_OUT" | grep -q '^user_no_name=NULL$' \
    && harness_ok 'getName missing name -> safe default' 'user_no_name=NULL' \
    || harness_bad 'getName missing name -> safe default' "$PERIOD_OUT"
echo "$PERIOD_OUT" | grep -q '^set_ok=1 period=01/02/2026 00:00 - 28/02/2026 23:59$' \
    && harness_ok 'setSavedPeriod persists for valid user' 'set_ok' \
    || harness_bad 'setSavedPeriod persists for valid user' "$PERIOD_OUT"
echo "$PERIOD_OUT" | grep -q '^set_false_user=0 keys=0$' \
    && harness_ok 'setSavedPeriod skips invalid user (no fabricate)' 'no session write' \
    || harness_bad 'setSavedPeriod skips invalid user (no fabricate)' "$PERIOD_OUT"
echo "$PERIOD_OUT" | grep -q '^warn_count=0$' \
    && harness_ok 'CallsReport period fixtures emit no PHP warnings' 'warn_count=0' \
    || harness_bad 'CallsReport period fixtures emit no PHP warnings' "$PERIOD_OUT"

echo '==> Fixture: HeadLink createDataStylesheet / Alternate'
HL_OUT="$($COMPOSE exec -T app php -d display_errors=1 -d error_reporting=E_ALL -r "
set_include_path('/var/www/html/snep/lib' . PATH_SEPARATOR . get_include_path());
require_once 'Zend/View/Helper/HeadLink.php';
\$w = array();
set_error_handler(function (\$n, \$s) use (&\$w) {
    // Count Warnings only — E_DEPRECATED noise in ZF1 is out of R3 scope.
    if (\$n === E_WARNING || \$n === E_USER_WARNING) {
        \$w[] = \$s;
    }
    return true;
});
\$hl = new Zend_View_Helper_HeadLink();
\$hl->getContainer()->exchangeArray(array());
\$noExtras = \$hl->createDataStylesheet(array('/css/a.css'));
\$htmlNo = \$hl->itemToString(\$noExtras);
\$hl->getContainer()->exchangeArray(array());
\$withExtras = \$hl->createDataStylesheet(array('/css/b.css', 'screen', false, array('id' => 'theme-b')));
\$htmlWith = \$hl->itemToString(\$withExtras);
\$alt = \$hl->createDataAlternate(array('/feed.rss', 'application/rss+xml', 'Feed'));
\$htmlAlt = \$hl->itemToString(\$alt);
echo 'html_no=' . \$htmlNo . PHP_EOL;
echo 'html_with=' . \$htmlWith . PHP_EOL;
echo 'html_alt=' . \$htmlAlt . PHP_EOL;
echo 'warn_count=' . count(\$w) . PHP_EOL;
if (count(\$w)) { echo 'warns=' . implode('|', \$w) . PHP_EOL; }
" 2>&1 | tr -d '\r')"

echo "$HL_OUT" | grep -q 'rel="stylesheet"' \
    && echo "$HL_OUT" | grep -q 'href="/css/a.css"' \
    && harness_ok 'HeadLink no-extras stylesheet HTML preserved' "$(echo "$HL_OUT" | grep '^html_no=' | head -1)" \
    || harness_bad 'HeadLink no-extras stylesheet HTML preserved' "$HL_OUT"
echo "$HL_OUT" | grep -q 'href="/css/b.css"' \
    && echo "$HL_OUT" | grep -q 'id="theme-b"' \
    && harness_ok 'HeadLink with-extras stylesheet HTML preserved' "$(echo "$HL_OUT" | grep '^html_with=' | head -1)" \
    || harness_bad 'HeadLink with-extras stylesheet HTML preserved' "$HL_OUT"
echo "$HL_OUT" | grep -q 'rel="alternate"' \
    && harness_ok 'HeadLink alternate without extras HTML preserved' "$(echo "$HL_OUT" | grep '^html_alt=' | head -1)" \
    || harness_bad 'HeadLink alternate without extras HTML preserved' "$HL_OUT"
echo "$HL_OUT" | grep -q '^warn_count=0$' \
    && harness_ok 'HeadLink fixtures emit no PHP warnings' 'warn_count=0' \
    || harness_bad 'HeadLink fixtures emit no PHP warnings' "$HL_OUT"

echo '==> Live authenticated pages: no pilot warning disclosure'
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${ADMIN_PASSWORD}');" | tr -d '\r\n')"
[ -n "$TEST_HASH" ] || harness_blocked "could not compute admin test password hash"
$COMPOSE exec -T db mariadb -u"${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" \
    -e "UPDATE users SET password='${TEST_HASH}' WHERE name='${ADMIN_USER}';" >/dev/null 2>&1 \
    || harness_blocked "could not reset admin password"

code="$(request POST /index.php/auth/login "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}")"
[ "$code" = 302 ] && harness_ok 'admin login' "HTTP $code" || harness_blocked "admin login HTTP $code"

code="$(request GET /index.php/default/systemstatus)"
if [ "$code" = 200 ] \
    && ! grep -qiE 'Undefined array key ["'\'']apt|PHP Warning' "$BODY" \
    && grep -qiE 'Server Status|SNEP' "$BODY"; then
    harness_ok 'systemstatus live: no apt warning; snep/status present' "HTTP $code"
else
    harness_bad 'systemstatus live: no apt warning; snep/status present' "HTTP $code body=$(head -c 200 "$BODY")"
fi

code="$(request GET /index.php/default/calls-report)"
if [ "$code" = 200 ] \
    && ! grep -qiE 'Undefined array key ["'\'']admin|Trying to access array offset on null|PHP Warning' "$BODY"; then
    harness_ok 'calls-report live: no period/user warning' "HTTP $code"
else
    harness_bad 'calls-report live: no period/user warning' "HTTP $code body=$(head -c 300 "$BODY")"
fi

# Any authenticated layout page exercises HeadLink stylesheets.
# Prefer a known 200 controller (root /index.php/ may 302 to a default route).
code="$(request GET /index.php/default/extensions)"
if [ "$code" = 200 ] \
    && ! grep -qiE 'compact\(\): Undefined variable \$extras|Undefined variable \$extras|PHP Warning' "$BODY"; then
    harness_ok 'layout live: no HeadLink extras warning' "HTTP $code"
else
    harness_bad 'layout live: no HeadLink extras warning' "HTTP $code"
fi

# Secret disclosure guard on fixture outputs
if printf '%s\n%s\n%s\n' "$APT_OUT" "$PERIOD_OUT" "$HL_OUT" | grep -qiE 'pass_sock|DB_PASSWORD|AMI_PASSWORD|password='; then
    harness_bad 'no secret disclosure in fixtures' 'secret-like token in fixture output'
else
    harness_ok 'no secret disclosure in fixtures' 'clean fixture output'
fi

harness_require_containers app db
harness_complete
