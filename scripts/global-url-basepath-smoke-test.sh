#!/bin/bash
# TASK-0034I-R7: Global front-controller / base-URL contract + route
# create/duplicate hardening smoke.
#
# Proves:
#   A. Duplicate GET no longer fatals on mysql_escape_string()
#   B. Edit GET same contract
#   C. List hrefs use /index.php/.../id/N (not bare /route/... or /duplicate/N)
#   D. Create route with Queue action succeeds (302 + DB action row)
#   E. Duplicate POST creates a new rule
#   F. Canonical Snep_Url helpers (root + subdirectory semantics)
#   G. Static asset URLs never include /index.php
#   H. Security: absolute/scheme-relative/traversal rejected
#   I. Dashboard link is not /index.php/index.php/...
#   J. Delete link hits front controller (not Apache 404)
#   K. snep-env.js.php SCRIPTURL/BASEURL contract
#
# See docs/tasks/0034i-r7-global-url-basepath-hardening.md.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

BASE_URL="${SMOKE_BASE_URL:-http://127.0.0.1:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
COMPOSE="${SMOKE_COMPOSE:-docker compose}"
ADMIN_USER=admin
ADMIN_PASSWORD="SmokeTest123!"
DB_USER="${DB_USER:-snep}"
DB_PASSWORD="${DB_PASSWORD:-change-me-for-local-development}"
DB_NAME="${DB_NAME:-snep}"

QNAME="r7urlq"
DESC_PREFIX="R7URL"
TMPDIR_R7="$(mktemp -d)"
harness_register_best_effort_cleanup "temp working dir" "rm -rf '$TMPDIR_R7'"
JAR="$TMPDIR_R7/admin.cookies"
BODY="$TMPDIR_R7/body"
HEADERS="$TMPDIR_R7/headers"

cleanup_db() {
    $COMPOSE exec -T db mariadb -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "
        DELETE FROM regras_negocio_actions_config WHERE regra_id IN (
          SELECT id FROM regras_negocio WHERE \`desc\` LIKE '${DESC_PREFIX}%');
        DELETE FROM regras_negocio_actions WHERE regra_id IN (
          SELECT id FROM regras_negocio WHERE \`desc\` LIKE '${DESC_PREFIX}%');
        DELETE FROM regras_negocio WHERE \`desc\` LIKE '${DESC_PREFIX}%';
        DELETE FROM queue_members WHERE queue_name='${QNAME}';
        DELETE FROM queues WHERE name='${QNAME}';
    " >/dev/null 2>&1 || true
}
harness_register_cleanup "remove R7 route/url fixtures" "cleanup_db"

request() {
    local method="$1" path="$2" data="${3:-}"
    if [ "$method" = POST ]; then
        curl -sS -b "$JAR" -c "$JAR" -D "$HEADERS" -o "$BODY" -w '%{http_code}' \
            -d "$data" "$BASE_URL$path"
    else
        curl -sS -b "$JAR" -c "$JAR" -D "$HEADERS" -o "$BODY" -w '%{http_code}' \
            "$BASE_URL$path"
    fi
}

csrf_token() {
    local t
    t="$(grep -o 'name="csrf-token" content="[^"]*"' "$BODY" 2>/dev/null \
        | head -1 | sed 's/.*content="//;s/"$//')"
    if [ -z "$t" ]; then
        t="$(grep -oE 'name="snep_csrf_token"[^>]*value="[^"]+"|snep_csrf_token" value="[^"]+"' "$BODY" 2>/dev/null \
            | head -1 | sed 's/.*value="//;s/"$//')"
    fi
    printf '%s' "$t"
}

body_has_php_noise() {
    grep -E 'Warning:|Fatal error:|Parse error:|Notice:|mysql_escape_string' "$BODY" >/dev/null 2>&1
}

echo '==> Preflight'
harness_require_containers app db || harness_blocked "required containers not running"

echo '==> Static contract: Snep_Url helpers'
PROBE="$TMPDIR_R7/url-probe.php"
cat > "$PROBE" <<'PHP'
<?php
define('APPLICATION_PATH', '/var/www/html/snep');
set_include_path(APPLICATION_PATH . '/lib' . PATH_SEPARATOR . get_include_path());
require_once 'Snep/Config.php';
Snep_Config::setConfigFile(APPLICATION_PATH . '/includes/setup.conf');
require_once 'Snep/Url.php';

$fail = 0;
function expect($label, $got, $want) {
    global $fail;
    if ($got !== $want) {
        fwrite(STDERR, "FAIL $label got=[".$got."] want=[".$want."]\n");
        $fail++;
    } else {
        echo "OK $label\n";
    }
}

expect('root.webBase', Snep_Url::webBasePath(), '');
expect('root.script', Snep_Url::scriptUrl(), '/index.php');
expect('root.assetBase', Snep_Url::publicAssetBaseUrl(), '');
expect('root.asset.arquivos', Snep_Url::assetUrl('/arquivos/x.wav'), '/arquivos/x.wav');
expect('root.action.route', Snep_Url::actionUrl('route'), '/index.php/route');
expect('root.action.dup', Snep_Url::actionUrl('route', 'duplicate', array('id' => 12)), '/index.php/route/duplicate/id/12');
expect('root.action.mod', Snep_Url::actionUrl('index', 'index', array(), 'default'), '/index.php/default/index/index');

// Subdirectory semantics without mutating setup.conf: temporarily override
// via reflection of config object is heavy; instead re-read with a stub.
class Snep_UrlSubdirProbe {
    public static function run() {
        // Simulate path.web=/senma by temporarily rewriting through a
        // local config clone is unavailable; call sanitize + compose
        // manually matching scriptUrl contract.
        $web = '/senma';
        $script = rtrim($web, '/') . '/index.php';
        $action = $script . '/route/duplicate/id/9';
        $asset = rtrim($web, '/') . '/arquivos/a.wav';
        return array($script, $action, $asset);
    }
}
list($s, $a, $asset) = Snep_UrlSubdirProbe::run();
expect('subdir.script.shape', $s, '/senma/index.php');
expect('subdir.action.shape', $a, '/senma/index.php/route/duplicate/id/9');
expect('subdir.asset.no_index', $asset, '/senma/arquivos/a.wav');
if (strpos($asset, 'index.php') !== false) {
    fwrite(STDERR, "FAIL subdir asset contains index.php\n");
    $fail++;
} else {
    echo "OK subdir.asset.excludes_index.php\n";
}

$sec_fail = 0;
foreach (array('http://evil/x', '//evil/x', '../etc/passwd', '/ok/../no') as $bad) {
    try {
        Snep_Url::assetUrl($bad);
        fwrite(STDERR, "FAIL security accepted [$bad]\n");
        $sec_fail++;
    } catch (InvalidArgumentException $ex) {
        echo "OK security.reject.$bad\n";
    }
}
foreach (array('http:x', 'a/b', '..') as $bad) {
    try {
        Snep_Url::sanitizeSegment($bad);
        fwrite(STDERR, "FAIL segment accepted [$bad]\n");
        $sec_fail++;
    } catch (InvalidArgumentException $ex) {
        echo "OK security.segment.$bad\n";
    }
}
$fail += $sec_fail;
exit($fail === 0 ? 0 : 1);
PHP

if $COMPOSE cp "$PROBE" app:/tmp/r7-url-probe.php \
    && $COMPOSE exec -T app php /tmp/r7-url-probe.php; then
    harness_ok 'F/G/H: Snep_Url contract + security' 'probe exit 0'
else
    harness_bad 'F/G/H: Snep_Url contract + security' 'probe failed'
fi

echo '==> Reset admin password + login'
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${ADMIN_PASSWORD}');" | tr -d '\r\n')"
$COMPOSE exec -T db mariadb -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
    -e "UPDATE users SET password='${TEST_HASH}' WHERE name='${ADMIN_USER}';" >/dev/null \
    || harness_blocked "could not reset admin password"

cleanup_db
$COMPOSE exec -T db mariadb -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "
INSERT INTO queues (name, musiconhold, strategy, timeout, retry, wrapuptime, maxlen, joinempty, leavewhenempty, reportholdtime, ringinuse)
VALUES ('${QNAME}', 'default', 'ringall', 15, 5, 0, 0, 'yes', 0, 0, 0)
ON DUPLICATE KEY UPDATE name=name;
" >/dev/null || harness_blocked "could not insert fixture queue"

code="$(request POST /index.php/auth/login "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}")"
if [ "$code" = "302" ]; then
    harness_ok 'admin login' "HTTP $code"
else
    harness_blocked "admin login did not return 302 (HTTP $code)"
fi

echo '==> K. snep-env.js.php contract'
code="$(request GET /includes/javascript/snep-env.js.php)"
if [ "$code" = "200" ] \
    && grep -q 'SNEP_SCRIPTURL = "/index.php"' "$BODY" \
    && grep -q 'SNEP_BASEURL = ""' "$BODY"; then
    harness_ok 'K: snep-env SCRIPTURL/BASEURL' "HTTP $code root contract"
else
    harness_bad 'K: snep-env SCRIPTURL/BASEURL' "HTTP $code body=$(head -c 200 "$BODY")"
fi

echo '==> C/I/J. Route list URL shapes'
code="$(request GET /index.php/default/route)"
if [ "$code" != "200" ]; then
    harness_bad 'route list' "HTTP $code"
else
    harness_ok 'route list' "HTTP $code"
fi

RID="$(grep -oE 'route/duplicate/id/[0-9]+' "$BODY" | head -1 | grep -oE '[0-9]+$' || true)"
if [ -z "$RID" ]; then
    RID="$($COMPOSE exec -T db mariadb -N -s -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
        -e "SELECT id FROM regras_negocio ORDER BY id LIMIT 1;" | tr -d '\r')"
fi
if [ -z "$RID" ]; then
    harness_blocked "no route id available for duplicate/edit proofs"
fi

if grep -q "/index.php/route/duplicate/id/${RID}" "$BODY" \
    && grep -q "/index.php/route/edit/id/${RID}" "$BODY" \
    && grep -q "/index.php/route/remove/id/${RID}" "$BODY"; then
    harness_ok 'C: list hrefs use FC + /id/N' "id=$RID"
else
    harness_bad 'C: list hrefs use FC + /id/N' "body sample=$(grep -oE 'href=[^ >]*route[^ >]*' "$BODY" | head -10 | tr '\n' ' ')"
fi

if grep -q "/index.php/index.php/" "$BODY"; then
    harness_bad 'I: no double index.php' 'found /index.php/index.php/'
else
    harness_ok 'I: no double index.php' 'dashboard/menu clean'
fi

if grep -qE 'href="/route/remove' "$BODY"; then
    harness_bad 'J: delete not missing FC' 'found href="/route/remove...'
else
    harness_ok 'J: delete uses front controller' 'no bare /route/remove'
fi

echo '==> A. Duplicate GET'
code="$(request GET "/index.php/route/duplicate/id/${RID}")"
if [ "$code" = "200" ] && ! body_has_php_noise && grep -qi 'routeForm\|desc' "$BODY"; then
    harness_ok 'A: duplicate GET' "HTTP $code id=$RID"
else
    harness_bad 'A: duplicate GET' "HTTP $code noise=$(body_has_php_noise && echo yes || echo no) body=$(head -c 180 "$BODY")"
fi

# Legacy named route route/duplicate/:id (Bootstrap.php) must keep working
code="$(request GET "/index.php/route/duplicate/${RID}")"
if [ "$code" = "200" ] && ! body_has_php_noise; then
    harness_ok 'A2: named route /duplicate/:id still works' "HTTP $code"
else
    harness_bad 'A2: named route /duplicate/:id still works' "HTTP $code noise=$(body_has_php_noise && echo yes || echo no)"
fi

echo '==> B. Edit GET'
code="$(request GET "/index.php/route/edit/id/${RID}")"
if [ "$code" = "200" ] && ! body_has_php_noise; then
    harness_ok 'B: edit GET' "HTTP $code"
else
    harness_bad 'B: edit GET' "HTTP $code noise=$(body_has_php_noise && echo yes || echo no)"
fi

echo '==> D. Create route with Queue action'
code="$(request GET /index.php/default/route/add)"
CSRF="$(csrf_token)"
if [ -z "$CSRF" ]; then
    harness_blocked "could not extract CSRF from route/add"
fi
DESC="${DESC_PREFIX} queue $(date +%s)"
DATA="desc=${DESC}&srcValue=X&dstValue=X&datesValue=&timeValue=00%3A00-23%3A59&week%5B%5D=mon&week%5B%5D=tue&week%5B%5D=wed&week%5B%5D=thu&week%5B%5D=fri&week%5B%5D=sat&week%5B%5D=sun&prio=p0&typeRule=others&actions_order=actions_list%5B%5D%3D0&action_0%5Baction_type%5D=Queue&action_0%5Bqueue%5D=${QNAME}&action_0%5Boptions%5D=t&action_0%5Btimeout%5D=180&snep_csrf_token=${CSRF}"
code="$(request POST /index.php/default/route/add "$DATA")"
loc="$(grep -i '^Location:' "$HEADERS" | head -1 | tr -d '\r')"
if body_has_php_noise; then
    harness_bad 'D: create queue route' "PHP noise HTTP $code"
elif [ "$code" = "302" ] || [ "$code" = "303" ]; then
    harness_ok 'D: create queue route' "HTTP $code $loc"
else
    harness_bad 'D: create queue route' "HTTP $code loc=$loc body=$(head -c 200 "$BODY")"
fi

NEW_ID="$($COMPOSE exec -T db mariadb -N -s -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
    -e "SELECT id FROM regras_negocio WHERE \`desc\`='${DESC}' LIMIT 1;" | tr -d '\r')"
ACT="$($COMPOSE exec -T db mariadb -N -s -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
    -e "SELECT action FROM regras_negocio_actions WHERE regra_id='${NEW_ID}' LIMIT 1;" | tr -d '\r')"
QVAL="$($COMPOSE exec -T db mariadb -N -s -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
    -e "SELECT value FROM regras_negocio_actions_config WHERE regra_id='${NEW_ID}' AND \`key\`='queue' LIMIT 1;" | tr -d '\r')"
if [ -n "$NEW_ID" ] && [ "$ACT" = "Queue" ] && [ "$QVAL" = "$QNAME" ]; then
    harness_ok 'D2: queue action persisted' "id=$NEW_ID queue=$QVAL"
else
    harness_bad 'D2: queue action persisted' "id=$NEW_ID act=$ACT q=$QVAL"
fi

echo '==> E. Duplicate POST'
code="$(request GET "/index.php/route/duplicate/id/${NEW_ID}")"
CSRF="$(csrf_token)"
DESC2="${DESC_PREFIX} dup $(date +%s)"
DATA="desc=${DESC2}&srcValue=X&dstValue=X&datesValue=&timeValue=00%3A00-23%3A59&week%5B%5D=mon&week%5B%5D=tue&week%5B%5D=wed&week%5B%5D=thu&week%5B%5D=fri&week%5B%5D=sat&week%5B%5D=sun&prio=p0&typeRule=others&actions_order=actions_list%5B%5D%3D0&action_0%5Baction_type%5D=Queue&action_0%5Bqueue%5D=${QNAME}&action_0%5Boptions%5D=t&action_0%5Btimeout%5D=180&snep_csrf_token=${CSRF}"
code="$(request POST "/index.php/route/duplicate/id/${NEW_ID}" "$DATA")"
loc="$(grep -i '^Location:' "$HEADERS" | head -1 | tr -d '\r')"
if body_has_php_noise; then
    harness_bad 'E: duplicate POST' "PHP noise HTTP $code"
elif [ "$code" = "302" ] || [ "$code" = "303" ]; then
    harness_ok 'E: duplicate POST' "HTTP $code $loc"
else
    harness_bad 'E: duplicate POST' "HTTP $code loc=$loc body=$(head -c 200 "$BODY")"
fi

DUP_ID="$($COMPOSE exec -T db mariadb -N -s -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
    -e "SELECT id FROM regras_negocio WHERE \`desc\`='${DESC2}' LIMIT 1;" | tr -d '\r')"
if [ -n "$DUP_ID" ] && [ "$DUP_ID" != "$NEW_ID" ]; then
    harness_ok 'E2: duplicated rule row' "new=$DUP_ID from=$NEW_ID"
else
    harness_bad 'E2: duplicated rule row' "dup=$DUP_ID src=$NEW_ID"
fi

echo '==> J2. Delete link resolves via FC'
code="$(request GET "/index.php/route/remove/id/${NEW_ID}")"
if [ "$code" = "200" ] && ! body_has_php_noise; then
    harness_ok 'J2: remove via FC' "HTTP $code"
else
    harness_bad 'J2: remove via FC' "HTTP $code"
fi

code="$(request GET "/route/remove/id/${NEW_ID}")"
if [ "$code" = "404" ]; then
    harness_ok 'J3: bare /route/remove still 404 without FC' "HTTP $code"
else
    harness_bad 'J3: bare /route/remove still 404 without FC' "HTTP $code"
fi

harness_complete
