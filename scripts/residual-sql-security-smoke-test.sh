#!/bin/bash
#
# TASK-0026J residual SQL boundary closure focused security smoke test.
#
# Exercises the two SQL-injection sinks TASK-0026Z's own closure static
# sweep found outside every prior TASK-0026A-I/F1 task's scope
# (docs/tasks/0026z-security-audit-closure.md Sec.5), now remediated by
# TASK-0026J (docs/tasks/0026j-residual-sql-boundary-closure.md):
#
#   BLOCKER A -- Snep_InterfaceConf::loadConfFromDb()'s legacy chan_sip/
#     iax2 trunk lookup (`where("name = {$peer['name']}")`, raw
#     interpolation) -- flagged as deferred debt during TASK-0026E,
#     never fixed until now.
#   BLOCKER B -- CallsReportController::getselect()'s report-filter SQL
#     construction (date range, contact group/id filters, src/dst,
#     duration, cost center, clausulepeer) -- the MVC twin of the
#     already-hardened API CallsReportService.php (TASK-0026F1), never
#     itself in scope until now.
#
# TASK-0026K extends this same suite (per its own Phase 6 instruction:
# "extend ... rather than creating another one-off SQL suite") to close
# the two sibling report-controller findings TASK-0026J's own Phase 8
# sweep discovered but explicitly left unfixed:
#
#   BLOCKER C -- RankingReportController::getData()'s report-filter SQL
#     construction (date range, clausulepeer) -- the MVC twin of the
#     already-hardened API RankingReportService.php (TASK-0026F1).
#   BLOCKER D -- ServicesReportController::getData()'s report-filter SQL
#     construction (date range, clausulepeer) -- the MVC twin of the
#     already-hardened API ServicesReportService.php (TASK-0026F1).
#
# TASK-0026L extends this suite again to close the two sibling findings
# TASK-0026K's own Phase 9 final static closure sweep discovered but
# explicitly left unfixed (docs/tasks/0026k-report-controller-sql-closure.md,
# "Security handoff"):
#
#   BLOCKER E -- Snep_PickupGroups_Manager::get($id) (and 7 sibling
#     methods sharing the exact same raw-interpolation pattern:
#     delete(), getValidation(), edit()/editGroup(), addExtensionsGroup(),
#     getFilter(), getGroup()) -- reachable via
#     PickupGroupsController::editAction()/removeAction().
#   BLOCKER F -- Snep_Queues_Manager::getValidation($id) (and 7 sibling
#     methods: edit() [second-order, mass-assignable name], remove(),
#     removeQueues(), removeUserPermission(), removeQueuePeers(),
#     removeAllMembers(), removeMember()) -- reachable via
#     QueuesController::removeAction()/editAction()/membersAction().
#
# BLOCKER E/F coverage uses two verification paths:
#   - Where the real controller action is reachable via HTTP, the suite
#     drives it exactly like BLOCKER A-D (real authenticated request).
#   - Where it is NOT (see below), the suite invokes the now-fixed
#     Manager method directly inside the app container, through a small
#     CLI bootstrap that replicates snep/index.php's registry setup
#     without dispatching a controller -- the same real PHP code path,
#     same Zend_Db adapter, just without the broken HTTP entry point in
#     front of it. This mirrors TASK-0026C's own established precedent
#     for ProfilesController::addAction() (F8): "routes around [a
#     pre-existing, unrelated PHP 8.4 bug] by creating its fixture
#     profile directly via Snep_Profiles_Manager::add() and exercising
#     the real vulnerable sink through editAction() instead."
#
# Three pre-existing, unrelated PHP 8.4 compatibility bugs were
# discovered while reconstructing these two boundaries (documented in
# docs/tasks/0026l-pickup-queues-sql-closure.md, not fixed here per
# CLAUDE.md's "do not fix unrelated legacy bugs opportunistically"):
#   - PickupGroupsController::removeAction() calls the PHP-7-removed
#     mysql_escape_string() unconditionally on line 216, before any
#     Manager call -- every request to this action (GET or POST, any
#     id) fatals immediately. delete()/getValidation() are therefore
#     verified via direct Manager invocation, not HTTP.
#   - PickupGroupsController::addAction()/editAction()'s POST branch
#     both run `count(Snep_PickupGroups_Manager::getName($name))`, which
#     is a TypeError under PHP 8 whenever getName() returns false (i.e.
#     whenever the submitted name does not already exist) -- the same
#     bug class TASK-0026C already documented for
#     ProfilesController::addAction() (F8), never extended here. Brand
#     new pickup groups therefore cannot be created via the real
#     addAction() HTTP flow; fixtures are created via
#     Snep_PickupGroups_Manager::addGroup() directly. editGroup()/
#     addExtensionsGroup() are likewise verified via direct invocation.
#   - QueuesController::addAction() has the identical
#     count(Snep_Queues_Manager::getName($name)) bug -- brand new queues
#     cannot be created via the real addAction() HTTP flow either;
#     fixtures are created via Snep_Queues_Manager::add() directly.
#     QueuesController::removeAction()/editAction()/membersAction() have
#     no equivalent bug and are exercised via real HTTP, once a fixture
#     exists.
#
# Every payload below is a harmless, non-destructive, syntax-shaped
# string or boolean-oracle value applied only to fixtures this script
# owns -- never a real exploit chain, never password/hash/schema
# extraction, matching this project's own established smoke-suite
# constraints.
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
ADMIN_USER="admin"
ADMIN_PASSWORD="SmokeTest123!"
MARKER="task0026j"

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

redirects_to_permission_error() {
    grep -qi '^Location:.*permission/error' "$HEADERS"
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

# post_fields <jar> <path> <key=value> [<key=value> ...] -- curl
# --data-urlencode per field, matching TASK-0026E's own established
# convention for values that must survive on the wire byte-for-byte.
post_fields() {
    local jar="$1" path="$2"
    shift 2
    local curl_args=()
    for kv in "$@"; do
        curl_args+=(--data-urlencode "$kv")
    done
    curl -sS -b "$jar" -c "$jar" -D "$HEADERS" -o "$BODY" -w '%{http_code}' \
        "${curl_args[@]}" "${BASE_URL}${path}"
}

# run_manager_php <php-code> -- BLOCKER E/F. Writes <php-code> to a local
# temp file (prefixed with a CLI bootstrap that replicates
# snep/index.php's registry setup -- Snep_Config, Zend_Application,
# Zend_Registry 'config'/'db' -- without dispatching a controller),
# copies it into the app container, and executes it with
# warnings/deprecations suppressed. Used only for the sub-boundaries
# whose real HTTP entry point is blocked by one of the three pre-existing,
# unrelated PHP 8.4 bugs documented in this script's header comment --
# every other check below drives the real controller over HTTP.
CLI_BOOTSTRAP_REMOTE="/tmp/task0026l_cli_bootstrap.php"
CLI_BOOTSTRAP_LOCAL="$(mktemp)"
cat > "$CLI_BOOTSTRAP_LOCAL" <<'BOOTSTRAP_EOF'
<?php
error_reporting(0);
ini_set('display_errors', '0');
defined('APPLICATION_PATH') || define('APPLICATION_PATH', '/var/www/html/snep');
set_include_path(implode(PATH_SEPARATOR, array(APPLICATION_PATH . '/lib', get_include_path())));
require_once 'Snep/Config.php';
Snep_Config::setConfigFile(APPLICATION_PATH . '/includes/setup.conf');
$config = Snep_Config::getConfig();
defined('SNEP_VENDOR') || define('SNEP_VENDOR', $config->ambiente->emp_nome);
defined('SNEP_VERSION') || define('SNEP_VERSION', trim(file_get_contents(APPLICATION_PATH . '/configs/snep_version')));
defined('APPLICATION_ENV') || define('APPLICATION_ENV', 'production');
require_once 'Snep/Modules.php';
Snep_Modules::getInstance()->addPath(APPLICATION_PATH . '/modules');
require_once 'Zend/Application.php';
require_once 'Zend/Config/Ini.php';
$application = new Zend_Application(APPLICATION_ENV, APPLICATION_PATH . '/application.ini');
$application->setAutoloaderNamespaces(array('Asterisk_', 'PBX_', 'Snep_'));
require_once 'Zend/Registry.php';
Zend_Registry::set('config', $config);
Zend_Registry::set('db', Snep_Db::getInstance());
$application->bootstrap();
error_reporting(0);
ini_set('display_errors', '0');
BOOTSTRAP_EOF
$COMPOSE cp "$CLI_BOOTSTRAP_LOCAL" app:"$CLI_BOOTSTRAP_REMOTE" >/dev/null 2>&1
harness_register_best_effort_cleanup "local CLI bootstrap temp file" "rm -f '$CLI_BOOTSTRAP_LOCAL'"
harness_register_best_effort_cleanup "CLI bootstrap file in app container" "$COMPOSE exec -T app rm -f '$CLI_BOOTSTRAP_REMOTE'"
harness_register_best_effort_cleanup "run_manager_php scratch file in app container" "$COMPOSE exec -T app rm -f /tmp/task0026l_run.php"

run_manager_php() {
    local code="$1" f
    f="$(mktemp)"
    { printf '<?php\n'; printf "require '%s';\n" "$CLI_BOOTSTRAP_REMOTE"; printf '%s\n' "$code"; } > "$f"
    $COMPOSE cp "$f" app:/tmp/task0026l_run.php >/dev/null 2>&1
    rm -f "$f"
    app_exec "php -d display_errors=0 /tmp/task0026l_run.php"
}

# assert_marker <label> <marker> <output> -- looks for a line
# "<marker>:OK" in <output> (produced by a run_manager_php call); anything
# else (BAD, EXCEPTION:..., or a missing marker) is a FAIL with the
# actual line as detail.
assert_marker() {
    local label="$1" marker="$2" output="$3" line
    line="$(echo "$output" | grep "^${marker}:" | head -1)"
    if [ "$line" = "${marker}:OK" ]; then
        harness_ok "$label" "$line"
    else
        harness_bad "$label" "expected ${marker}:OK, got: ${line:-<no marker found>}"
    fi
}

# --- 0. Preflight --------------------------------------------------------

harness_require_containers app asterisk db
harness_require_env DB_USER DB_PASSWORD DB_NAME

BODY="$(mktemp)"
HEADERS="$(mktemp)"
harness_register_best_effort_cleanup "request temp files" "rm -f '$BODY' '$HEADERS'"

ADMIN_JAR="$(mktemp)"
harness_register_best_effort_cleanup "admin cookie jar" "rm -f '$ADMIN_JAR'"
ADMIN_HASH="$(app_exec "php -r \"echo md5('${ADMIN_PASSWORD}');\"" | tr -d '\r')"
if [ -z "$ADMIN_HASH" ]; then
    harness_blocked "could not compute the ${ADMIN_USER} password hash via the app container"
fi
db_query "UPDATE users SET password = '${ADMIN_HASH}' WHERE name = '${ADMIN_USER}';" >&2
request "$ADMIN_JAR" POST /index.php/auth/login "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}" >/dev/null

FATALS_BEFORE="$(fatal_count)"
log "==> baseline PHP Fatal Error count: ${FATALS_BEFORE}"

CONF_DIR_APP="/etc/asterisk/snep"
LEGACY_SIP_CONF="${CONF_DIR_APP}/snep-sip.conf"

RESTRICTED_USER="task0026j-restricted"
RESTRICTED_PASSWORD="Task0026jRestricted!"
RID="$(db_query "SELECT id FROM users WHERE name='${RESTRICTED_USER}';")"
RESTRICTED_HASH="$(app_exec "php -r \"echo md5('${RESTRICTED_PASSWORD}');\"" | tr -d '\r')"
if [ -z "$RID" ]; then
    db_query "INSERT INTO users (name,password,email,dashboard,profile_id,created,updated) VALUES ('${RESTRICTED_USER}','${RESTRICTED_HASH}','${RESTRICTED_USER}@example.test','',1,NOW(),NOW());"
    RID="$(db_query "SELECT id FROM users WHERE name='${RESTRICTED_USER}';")"
fi
if [ -z "$RID" ]; then
    harness_blocked "could not provision the zero-permission restricted test user"
fi
db_query "UPDATE users SET password='${RESTRICTED_HASH}' WHERE id=${RID}; DELETE FROM users_permissions WHERE user_id=${RID};" >/dev/null
harness_register_best_effort_cleanup "restricted user permissions reset to baseline" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}' -e \"DELETE FROM users_permissions WHERE user_id=${RID};\" >/dev/null"

RESTRICTED_JAR="$(mktemp)"
harness_register_best_effort_cleanup "restricted cookie jar" "rm -f '$RESTRICTED_JAR'"
request "$RESTRICTED_JAR" POST /index.php/auth/login "user=${RESTRICTED_USER}&password=${RESTRICTED_PASSWORD}" >/dev/null

ADMIN_CSRF="$(harness_csrf_token "$ADMIN_JAR" "$BASE_URL")"
if [ -z "$ADMIN_CSRF" ]; then harness_blocked "could not read the admin session's CSRF token"; fi
RESTRICTED_CSRF="$(harness_csrf_token "$RESTRICTED_JAR" "$BASE_URL")"
if [ -z "$RESTRICTED_CSRF" ]; then harness_blocked "could not read the restricted session's CSRF token"; fi

for boundary_path in "/index.php/default/trunks/add" "/index.php/default/calls-report" "/index.php/default/ranking-report" "/index.php/default/services-report" "/index.php/default/pickup-groups" "/index.php/default/queues"; do
    code="$(request "$RESTRICTED_JAR" GET "$boundary_path")"
    if [ "$code" = 302 ] && redirects_to_permission_error; then
        harness_ok "authorization intact: ${boundary_path}" "zero-permission user denied (HTTP 302, Location: permission/error)"
    else
        harness_bad "authorization intact: ${boundary_path}" "expected 302+permission/error, got HTTP ${code}"
    fi
done

code="$(request "$ADMIN_JAR" POST /index.php/default/users/permission/id/$RID "user=$RID&default_trunks_write=1&default_calls-report_read=1&default_ranking-report_read=1&default_services-report_read=1&default_pickup-groups_write=1&default_queues_write=1&snep_csrf_token=${ADMIN_CSRF}")"
if [ "$code" = 302 ]; then
    harness_ok "admin grants exactly the six required permissions" "HTTP $code (trunks-write, calls-report-read, ranking-report-read, services-report-read, pickup-groups-write, queues-write)"
else
    harness_blocked "granting permissions to the restricted user failed (HTTP $code) -- cannot proceed"
fi

# =============================================================================
# BLOCKER A -- Snep_InterfaceConf legacy chan_sip trunk lookup
# =============================================================================

log "==> BLOCKER A: Snep_InterfaceConf chan_sip trunk-lookup boundary"

# Pre-existing, already-documented (TASK-0026C/E) hazard: preparePost()
# auto-generates a new trunk's name as MAX(existing trunk name)+1, or "1"
# if the trunks table is empty -- colliding with any orphaned
# peer_type='T' peers row left over from an earlier interrupted run.
# Swept via the same supported extensions/remove HTTP path this
# project's other smoke suites already use, never a raw SQL delete.
sweep_orphaned_trunk_peers() {
    # NOTE: this suite's own BLOCKER A payload deliberately mass-assigns
    # a peers.name value containing spaces/SQL syntax (e.g. "0 OR
    # id=<n>") -- unlike every prior TASK-0026x suite's orphan sweep
    # (whose names are always a single plain digit), such a name breaks
    # unquoted `for x in $(...)` word-splitting, silently fragmenting one
    # real orphaned row into several nonexistent ones and never actually
    # removing it. A newline-delimited `while read` loop and a properly
    # urlencoded post_fields() call (not a raw `-d` string) are required
    # here specifically because of that.
    local orphan_name
    db_query "SELECT p.name FROM peers p LEFT JOIN trunks t ON t.name = p.name WHERE p.peer_type='T' AND t.id IS NULL;" | while IFS= read -r orphan_name; do
        [ -z "$orphan_name" ] && continue
        log "found an orphaned trunk-type peers row (name='${orphan_name}') with no matching trunks row -- removing via the supported extensions/remove HTTP path"
        post_fields "$ADMIN_JAR" /index.php/default/extensions/remove "id=${orphan_name}" "snep_csrf_token=${ADMIN_CSRF}" >/dev/null
    done
}
sweep_orphaned_trunk_peers
harness_register_cleanup "orphaned trunk-type peers row sweep (BLOCKER A fixture side effect)" "sweep_orphaned_trunk_peers"

# 1. Normal supported lookup: a legitimate technology=sip trunk (CANARY)
# creates and renders correctly, carrying its own distinguishing context.
CANARY_CALLERID="Task0026j Canary"
CANARY_CONTEXT="${MARKER}-canary-ctx"
code="$(post_fields "$RESTRICTED_JAR" /index.php/default/trunks/add \
    "technology=sip" "peer_type=friend" "domain=" "callerid=${CANARY_CALLERID}" "username=task0026jcanary" "secret=Sup3rSecret" \
    "host=sip.example.test" "dtmfmode=rfc2833" "dialmethod=INVITE" "context=${CANARY_CONTEXT}" "reverse_auth=" "map_extensions=" \
    "dtmf_dial=" "codec=ulaw" "codec1=alaw" "codec2=gsm" "qualify=yes" "transport_id=" "snep_csrf_token=${RESTRICTED_CSRF}")"
CANARY_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${CANARY_CALLERID}' ORDER BY id DESC LIMIT 1;")"
if [ "$code" = 302 ] && [ -n "$CANARY_ID" ]; then
    harness_ok "InterfaceConf: create a legitimate technology=sip trunk (CANARY)" "HTTP $code, trunk id=${CANARY_ID}"
else
    harness_bad "InterfaceConf: create a legitimate technology=sip trunk (CANARY)" "HTTP $code, trunk id present='${CANARY_ID}'"
fi
harness_register_cleanup "trunk id=${CANARY_ID:-none} (BLOCKER A CANARY fixture)" \
    "[ -n '${CANARY_ID}' ] && request \"\$RESTRICTED_JAR\" POST /index.php/default/trunks/remove \"id=${CANARY_ID}&delete=1&snep_csrf_token=${RESTRICTED_CSRF}\" >/dev/null; true"

if [ -n "$CANARY_ID" ]; then
    GENERATED_SIP="$(app_exec "cat '$LEGACY_SIP_CONF' 2>/dev/null")"
    if echo "$GENERATED_SIP" | grep -qF "[task0026jcanary]" && echo "$GENERATED_SIP" | grep -qF "context=${CANARY_CONTEXT}"; then
        harness_ok "InterfaceConf: generated legacy config has expected section/context" "snep-sip.conf contains [task0026jcanary] with context=${CANARY_CONTEXT}"
    else
        harness_bad "InterfaceConf: generated legacy config has expected section/context" "expected section/context not found in generated snep-sip.conf"
    fi
fi

if [ -z "${CANARY_ID:-}" ]; then
    harness_blocked "could not create the CANARY trunk fixture -- cannot proceed with the injection proof"
fi

# 2. SQL-shaped value cannot alter lookup semantics: MALICIOUS's own
# `name` field is mass-assigned (TrunksController::preparePost() merges
# the whole POST body; `name` is in both $trunk_fields and $ip_fields,
# and is NOT covered by validateConfigFields()) to an unquoted-numeric-
# context boolean-always-true payload that, if the fix were absent,
# would make the vulnerable `where("name = {$peer['name']}")` lookup
# match CANARY's row by primary key regardless of table contents/order.
MAL_CALLERID="Task0026j Malicious"
MAL_CONTEXT="${MARKER}-malicious-ctx"
INJECTED_NAME="0 OR id=${CANARY_ID}"
code="$(post_fields "$RESTRICTED_JAR" /index.php/default/trunks/add \
    "technology=sip" "peer_type=friend" "domain=" "callerid=${MAL_CALLERID}" "username=task0026jmalicious" "secret=Sup3rSecret2" \
    "host=sip2.example.test" "dtmfmode=rfc2833" "dialmethod=INVITE" "context=${MAL_CONTEXT}" "name=${INJECTED_NAME}" "reverse_auth=" "map_extensions=" \
    "dtmf_dial=" "codec=ulaw" "codec1=alaw" "codec2=gsm" "qualify=yes" "transport_id=" "snep_csrf_token=${RESTRICTED_CSRF}")"
MAL_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${MAL_CALLERID}' ORDER BY id DESC LIMIT 1;")"
MAL_PEER_NAME="$(db_query "SELECT name FROM peers WHERE defaultuser='task0026jmalicious' ORDER BY id DESC LIMIT 1;")"
if [ "$code" = 302 ] && [ -n "$MAL_ID" ] && [ "$MAL_PEER_NAME" = "$INJECTED_NAME" ]; then
    harness_ok "InterfaceConf: mass-assigned SQL-shaped 'name' is stored as literal data" "peers.name='${MAL_PEER_NAME}', trunk id=${MAL_ID}"
else
    harness_bad "InterfaceConf: mass-assigned SQL-shaped 'name' is stored as literal data" "HTTP $code, trunk id='${MAL_ID}', peers.name='${MAL_PEER_NAME}'"
fi
if [ -n "$MAL_ID" ]; then
    harness_register_cleanup "trunk id=${MAL_ID} (BLOCKER A MALICIOUS fixture)" \
        "request \"\$RESTRICTED_JAR\" POST /index.php/default/trunks/remove \"id=${MAL_ID}&delete=1&snep_csrf_token=${RESTRICTED_CSRF}\" >/dev/null; true"
fi

# 3. The core proof: MALICIOUS's own generated block must reflect only
# its own (safe) attributes -- never CANARY's, which the pre-fix,
# unquoted `where("name = 0 OR id=<CANARY_ID>")` lookup would otherwise
# have matched (an order-independent, primary-key-targeted boolean-true
# injection -- not dependent on table row order/content).
GENERATED_SIP_AFTER="$(app_exec "cat '$LEGACY_SIP_CONF' 2>/dev/null")"
MAL_BLOCK="$(echo "$GENERATED_SIP_AFTER" | awk '/^\[task0026jmalicious\]$/{f=1;next}/^\[/{f=0}f')"
if echo "$MAL_BLOCK" | grep -qF "context=${MAL_CONTEXT}" && ! echo "$MAL_BLOCK" | grep -qF "${CANARY_CONTEXT}"; then
    harness_ok "InterfaceConf: SQL-shaped 'name' cannot cross-leak another trunk's data" "MALICIOUS's own generated block carries only its own context (${MAL_CONTEXT}), never CANARY's (${CANARY_CONTEXT})"
else
    harness_bad "InterfaceConf: SQL-shaped 'name' cannot cross-leak another trunk's data" "MALICIOUS block: $(echo "$MAL_BLOCK" | tr '\n' ' ')"
fi

# 4. PJSIP baseline remains unaffected by this legacy-generator boundary.
PJSIP_MODULE="$($COMPOSE exec -T asterisk asterisk -rx 'module show like res_pjsip.so' 2>/dev/null)"
if echo "$PJSIP_MODULE" | grep -q "Running"; then
    harness_ok "InterfaceConf: PJSIP baseline unaffected" "res_pjsip.so still Running"
else
    harness_bad "InterfaceConf: PJSIP baseline unaffected" "res_pjsip.so not reported Running: $PJSIP_MODULE"
fi

FATALS_AFTER_A="$(fatal_count)"
if [ "$FATALS_AFTER_A" = "$FATALS_BEFORE" ]; then
    harness_ok "BLOCKER A: application remained healthy" "PHP Fatal Error count unchanged (${FATALS_BEFORE})"
else
    harness_bad "BLOCKER A: application remained healthy" "PHP Fatal Error count changed: ${FATALS_BEFORE} -> ${FATALS_AFTER_A}"
fi

# =============================================================================
# BLOCKER B -- CallsReportController report-filter SQL construction
# =============================================================================

log "==> BLOCKER B: CallsReportController report-filter boundary"

# Pre-existing, unrelated PHP 8.4 compatibility bug discovered while
# building this suite (not fixed here, per this task's own scope
# boundary and CLAUDE.md's "do not fix unrelated legacy bugs
# opportunistically"): getselect() (CallsReportController.php:402)
# runs `count($stmt)` on the Zend_Db_Statement_Pdo object $db->query()
# returns -- not Countable/array under PHP 8 -- an uncaught TypeError on
# EVERY report request, legitimate or malicious, regardless of this
# task's own SQL fix (confirmed: the line immediately above it,
# $db->query($select), already completed by the time this throws, so
# the vulnerable/now-fixed boundary this suite exists to prove IS
# exercised before the crash). Every check below therefore expects
# exactly this ONE known crash signature and treats any OTHER fatal
# (in particular a SQLSTATE/syntax-error-shaped one, which is exactly
# what an unquoted apostrophe or broken-out-of-context value would have
# produced pre-fix) as a genuine failure -- proving the submitted value
# never reached SQL syntax position, which is the actual security
# property this suite exists to verify. See
# docs/tasks/0026j-residual-sql-boundary-closure.md for the
# Product-Readiness handoff of this bug.
KNOWN_BUG_MARK="CallsReportController.php:402"

known_bug_count() {
    local n
    n="$(app_exec "grep -c '${KNOWN_BUG_MARK}' /var/log/apache2/mag-error.log 2>/dev/null" | tr -d '\r\n ')"
    echo "${n:-0}"
}

# calls_report_check <label> <field=value>... -- POSTs to calls-report
# and classifies strictly against the known pre-existing crash signature
# above. PASS means the query layer raised no SQL/syntax error at all.
calls_report_check() {
    local label="$1"
    shift
    local before_total before_known after_total after_known tail_text total_delta known_delta
    before_total="$(fatal_count)"
    before_known="$(known_bug_count)"
    post_fields "$RESTRICTED_JAR" /index.php/default/calls-report "$@" >/dev/null
    after_total="$(fatal_count)"
    after_known="$(known_bug_count)"
    tail_text="$(app_exec 'tail -c 4000 /var/log/apache2/mag-error.log 2>/dev/null')"
    total_delta=$((after_total - before_total))
    known_delta=$((after_known - before_known))
    if [ "$total_delta" -eq "$known_delta" ] && [ "$known_delta" -ge 1 ] && ! echo "$tail_text" | grep -qi "SQLSTATE\|syntax error"; then
        harness_ok "$label" "only the known, pre-existing CallsReportController.php:402 count()/Countable PHP 8.4 bug fired -- the query itself completed with no SQL/syntax error"
    else
        harness_bad "$label" "unexpected fatal signature: total_delta=${total_delta} known_delta=${known_delta}"
    fi
}

WIDE_PERIOD="01/01/2000 00:00 - 31/12/2030 23:59"

# 6/7. A legitimate request and an ordinary nonexistent filter value both
# reach the database layer cleanly (item 12's "no unexpected PHP Fatal"
# requirement is folded into calls_report_check's own signature check).
calls_report_check "CallsReport: legitimate synthetic report request reaches the DB layer cleanly" \
    "report_type=synthetic" "period=${WIDE_PERIOD}" "selectContactGroupSrc=0" "selectContactSrc=0" "selectSrc=0" \
    "groupSrc=" "order_src=equal" "selectContactGroupDst=0" "selectContactDst=0" "selectDst=0" "groupDst=" "order_dst=equal" \
    "ANSWERED=on" "NOANSWER=on" "BUSY=on" "FAILED=on" "duration_init=" "duration_end=" "snep_csrf_token=${RESTRICTED_CSRF}"

calls_report_check "CallsReport: ordinary nonexistent filter value behaves normally" \
    "report_type=synthetic" "period=${WIDE_PERIOD}" "selectContactGroupSrc=0" "selectContactSrc=0" "selectSrc=0" \
    "groupSrc=99999999999" "order_src=equal" "selectContactGroupDst=0" "selectContactDst=0" "selectDst=0" "groupDst=" "order_dst=equal" \
    "ANSWERED=on" "NOANSWER=on" "BUSY=on" "FAILED=on" "duration_init=" "duration_end=" "snep_csrf_token=${RESTRICTED_CSRF}"

# 8/9. Always-false vs always-true SQL-shaped duration_init cannot alter
# semantics -- (int) casting collapses "... OR 1=1" to a plain integer
# (a real, harmless duration value), never executable SQL syntax.
calls_report_check "CallsReport: always-false SQL-shaped duration_init cannot alter semantics" \
    "report_type=synthetic" "period=${WIDE_PERIOD}" "selectContactGroupSrc=0" "selectContactSrc=0" "selectSrc=0" \
    "groupSrc=" "order_src=equal" "selectContactGroupDst=0" "selectContactDst=0" "selectDst=0" "groupDst=" "order_dst=equal" \
    "ANSWERED=on" "NOANSWER=on" "BUSY=on" "FAILED=on" "duration_init=0 AND 1=2" "duration_end=" "snep_csrf_token=${RESTRICTED_CSRF}"

calls_report_check "CallsReport: always-true SQL-shaped duration_init cannot alter semantics" \
    "report_type=synthetic" "period=${WIDE_PERIOD}" "selectContactGroupSrc=0" "selectContactSrc=0" "selectSrc=0" \
    "groupSrc=" "order_src=equal" "selectContactGroupDst=0" "selectContactDst=0" "selectDst=0" "groupDst=" "order_dst=equal" \
    "ANSWERED=on" "NOANSWER=on" "BUSY=on" "FAILED=on" "duration_init=99999999 OR 1=1" "duration_end=" "snep_csrf_token=${RESTRICTED_CSRF}"

# 10. Apostrophe-containing value causes no SQL error -- the core proof:
# pre-fix, an unescaped apostrophe here would break out of the LIKE
# '%...%' string literal and produce a genuine SQLSTATE syntax error
# (a DIFFERENT fatal than the known count() bug); calls_report_check
# fails the check if that signature ever appears.
calls_report_check "CallsReport: apostrophe-containing value causes no SQL error" \
    "report_type=synthetic" "period=${WIDE_PERIOD}" "selectContactGroupSrc=0" "selectContactSrc=0" "selectSrc=0" \
    "groupSrc=O'Brien" "order_src=contain" "selectContactGroupDst=0" "selectContactDst=0" "selectDst=0" "groupDst=" "order_dst=equal" \
    "ANSWERED=on" "NOANSWER=on" "BUSY=on" "FAILED=on" "duration_init=" "duration_end=" "snep_csrf_token=${RESTRICTED_CSRF}"

# 11. Analytic report path is also protected (same getselect() boundary,
# different renderer).
calls_report_check "CallsReport: analytic report path is also protected" \
    "report_type=analytic" "period=${WIDE_PERIOD}" "selectContactGroupSrc=0" "selectContactSrc=0" "selectSrc=0" \
    "groupSrc=1' OR '1'='1" "order_src=equal" "selectContactGroupDst=0" "selectContactDst=0" "selectDst=0" "groupDst=" "order_dst=equal" \
    "ANSWERED=on" "NOANSWER=on" "BUSY=on" "FAILED=on" "duration_init=" "duration_end=" "snep_csrf_token=${RESTRICTED_CSRF}"

# 13. CDR timezone semantics (TASK-0027A) remain unchanged: the fix only
# wraps the exact same start_date/end_date string in $db->quote() instead
# of raw interpolation -- the comparison VALUE is byte-identical for any
# legitimate input, so a real CDR row's own calldate-anchored window
# (built the same way TASK-0027A's own harness_cdr_report_window() proves
# for call-smoke/trunk-smoke) must still reach the DB layer with no SQL
# error, midnight-crossing or not.
LATEST_CALLDATE="$(db_query "SELECT calldate FROM cdr ORDER BY calldate DESC LIMIT 1;")"
if [ -n "$LATEST_CALLDATE" ] && harness_cdr_report_window "$LATEST_CALLDATE" 5; then
    ANCHORED_PERIOD="$(echo "$HARNESS_REPORT_START_DATE" | awk -F- '{print $3"/"$2"/"$1}')" # dd/mm/yyyy
    ANCHORED_PERIOD="${ANCHORED_PERIOD} ${HARNESS_REPORT_START_HOUR%:*} - "
    END_DMY="$(echo "$HARNESS_REPORT_END_DATE" | awk -F- '{print $3"/"$2"/"$1}')"
    ANCHORED_PERIOD="${ANCHORED_PERIOD}${END_DMY} ${HARNESS_REPORT_END_HOUR%:*}"
    calls_report_check "CallsReport: CDR timezone semantics (TASK-0027A) unchanged" \
        "report_type=synthetic" "period=${ANCHORED_PERIOD}" "selectContactGroupSrc=0" "selectContactSrc=0" "selectSrc=0" \
        "groupSrc=" "order_src=equal" "selectContactGroupDst=0" "selectContactDst=0" "selectDst=0" "groupDst=" "order_dst=equal" \
        "ANSWERED=on" "NOANSWER=on" "BUSY=on" "FAILED=on" "duration_init=" "duration_end=" "snep_csrf_token=${RESTRICTED_CSRF}"
else
    harness_ok "CallsReport: CDR timezone semantics (TASK-0027A) unchanged" "no existing CDR row available in this environment yet -- skipping the anchored proof, already covered by the other checks above"
fi

# report_check <label> <path> <field=value>... -- POSTs to <path> and
# verifies no NEW PHP Fatal Error is introduced and no SQL/syntax error
# ever appears in the log tail. Unlike calls_report_check above,
# RankingReportController.php and ServicesReportController.php carry no
# known pre-existing crash signature (confirmed: neither runs count() on
# a Zend_Db_Statement_Pdo object) -- PASS here means a fully clean
# response with zero fatal/syntax-error log entries, not merely "only
# the known bug fired".
report_check() {
    local label="$1" path="$2"
    shift 2
    local before_total after_total tail_text total_delta
    before_total="$(fatal_count)"
    post_fields "$RESTRICTED_JAR" "$path" "$@" >/dev/null
    after_total="$(fatal_count)"
    tail_text="$(app_exec 'tail -c 4000 /var/log/apache2/mag-error.log 2>/dev/null')"
    total_delta=$((after_total - before_total))
    if [ "$total_delta" -eq 0 ] && ! echo "$tail_text" | grep -qi "SQLSTATE\|syntax error"; then
        harness_ok "$label" "no PHP Fatal Error, no SQL/syntax error"
    else
        harness_bad "$label" "fatal_delta=${total_delta}; log tail: $(echo "$tail_text" | tr '\n' ' ' | tail -c 300)"
    fi
}

# =============================================================================
# BLOCKER C -- RankingReportController report-filter SQL construction
# =============================================================================

log "==> BLOCKER C: RankingReportController report-filter boundary"

# 14. A legitimate report request reaches the DB layer cleanly.
report_check "RankingReport: legitimate report request reaches the DB layer cleanly" \
    /index.php/default/ranking-report \
    "period=${WIDE_PERIOD}" "type=num" "showsource=10" "showdestiny=10" "out_type=list" \
    "snep_csrf_token=${RESTRICTED_CSRF}"

# 15/16. Always-false / always-true SQL-shaped clausulepeer cannot alter
# semantics -- quote() turns each IN-list token into inert literal data,
# so neither payload's embedded boolean condition is ever evaluated as
# SQL syntax (pre-fix, both produced a genuine SQLSTATE[42000] syntax
# error -- confirmed live during this task's own A/B verification).
report_check "RankingReport: always-false SQL-shaped clausulepeer cannot alter semantics" \
    /index.php/default/ranking-report \
    "period=${WIDE_PERIOD}" "type=num" "showsource=10" "showdestiny=10" "out_type=list" \
    "clausule=somebound" "clausulepeer=0' AND '1'='2" "snep_csrf_token=${RESTRICTED_CSRF}"

report_check "RankingReport: always-true SQL-shaped clausulepeer cannot alter semantics" \
    /index.php/default/ranking-report \
    "period=${WIDE_PERIOD}" "type=num" "showsource=10" "showdestiny=10" "out_type=list" \
    "clausule=somebound" "clausulepeer=1' OR '1'='1" "snep_csrf_token=${RESTRICTED_CSRF}"

# 17. Apostrophe/quote input (embedded in the raw, unvalidated TIME half
# of "period" -- Snep_Reports::fmt_date() only reformats the DATE half)
# causes no SQL error.
report_check "RankingReport: apostrophe-containing period value causes no SQL error" \
    /index.php/default/ranking-report \
    "period=01/01/2000 00:00' - 31/12/2030 23:59" "type=num" "showsource=10" "showdestiny=10" "out_type=list" \
    "snep_csrf_token=${RESTRICTED_CSRF}"

# =============================================================================
# BLOCKER D -- ServicesReportController report-filter SQL construction
# =============================================================================

log "==> BLOCKER D: ServicesReportController report-filter boundary"

# 18. A legitimate report request reaches the DB layer cleanly.
report_check "ServicesReport: legitimate report request reaches the DB layer cleanly" \
    /index.php/default/services-report \
    "period=${WIDE_PERIOD}" "serv_select[]=DND" "group_select=0" "exten_select=" \
    "snep_csrf_token=${RESTRICTED_CSRF}"

# 19/20. Always-false / always-true SQL-shaped clausulepeer cannot alter
# semantics -- same quote() containment as BLOCKER C, applied to the
# "peer IN (...)"/"peer NOT IN (...)" boundary.
report_check "ServicesReport: always-false SQL-shaped clausulepeer cannot alter semantics" \
    /index.php/default/services-report \
    "period=${WIDE_PERIOD}" "serv_select[]=DND" "group_select=0" "exten_select=" \
    "clausule=somebound" "clausulepeer=0' AND '1'='2" "snep_csrf_token=${RESTRICTED_CSRF}"

report_check "ServicesReport: always-true SQL-shaped clausulepeer cannot alter semantics" \
    /index.php/default/services-report \
    "period=${WIDE_PERIOD}" "serv_select[]=DND" "group_select=0" "exten_select=" \
    "clausule=somebound" "clausulepeer=1' OR '1'='1" "snep_csrf_token=${RESTRICTED_CSRF}"

# 21. Apostrophe/quote input (embedded in the raw, unvalidated TIME half
# of "period") causes no SQL error.
report_check "ServicesReport: apostrophe-containing period value causes no SQL error" \
    /index.php/default/services-report \
    "period=01/01/2000 00:00' - 31/12/2030 23:59" "serv_select[]=DND" "group_select=0" "exten_select=" \
    "snep_csrf_token=${RESTRICTED_CSRF}"

# =============================================================================
# BLOCKER E -- Snep_PickupGroups_Manager::get() and siblings
# =============================================================================

log "==> BLOCKER E: Snep_PickupGroups_Manager boundary"

# Fresh snapshot for this section's own health check -- BLOCKER B's own
# already-accounted-for CallsReportController.php:402 count() fatals
# (one per calls-report request, expected and asserted PASS above) would
# otherwise be misattributed to BLOCKER E if compared against the
# script-start $FATALS_BEFORE.
FATALS_BEFORE_E="$(fatal_count)"

# 22. Legitimate lookup: the pre-existing "GERAL" seed group renders via
# the real editAction() GET flow (get()'s legitimate path).
code="$(request "$RESTRICTED_JAR" GET "/index.php/default/pickup-groups/edit/id/1")"
if [ "$code" = 200 ] && grep -qF "GERAL" "$BODY"; then
    harness_ok "PickupGroups: legitimate lookup (id=1, GERAL) renders correctly" "HTTP $code, GERAL found in body"
else
    harness_bad "PickupGroups: legitimate lookup (id=1, GERAL) renders correctly" "HTTP $code, GERAL not found in body"
fi

# 23. Apostrophe-shaped id causes no SQL error -- the core BLOCKER E
# proof. Pre-fix this produced a genuine SQLSTATE[42000] syntax error
# (confirmed live during this task's own A/B verification).
code="$(request "$RESTRICTED_JAR" GET "/index.php/default/pickup-groups/edit/id/foo%27bar")"
TAIL_E="$(app_exec 'tail -c 2000 /var/log/apache2/mag-error.log 2>/dev/null')"
if [ "$code" = 200 ] && ! echo "$TAIL_E" | grep -qi "SQLSTATE\|syntax error"; then
    harness_ok "PickupGroups: apostrophe-shaped id causes no SQL error" "HTTP $code, no SQL/syntax error"
else
    harness_bad "PickupGroups: apostrophe-shaped id causes no SQL error" "HTTP $code, log tail: $(echo "$TAIL_E" | tr '\n' ' ' | tail -c 300)"
fi

# 24. Fixtures: CANARY/MALICIOUS pickup groups, created via direct
# Snep_PickupGroups_Manager::addGroup() invocation --
# PickupGroupsController::addAction() cannot be used here (see this
# script's header comment: count(false) TypeError on any brand-new name).
FIXTURE_OUT="$(run_manager_php "
echo 'FIXTURES:' . Snep_PickupGroups_Manager::addGroup(['nome' => 'task0026l-canary']) . ',' . Snep_PickupGroups_Manager::addGroup(['nome' => 'task0026l-malicious']) . PHP_EOL;
")"
FIXTURE_LINE="$(echo "$FIXTURE_OUT" | grep '^FIXTURES:' | head -1)"
CANARY_ID="$(echo "$FIXTURE_LINE" | sed 's/FIXTURES://' | cut -d, -f1 | tr -d '\r')"
MAL_ID="$(echo "$FIXTURE_LINE" | sed 's/FIXTURES://' | cut -d, -f2 | tr -d '\r')"
if [ -n "$CANARY_ID" ] && [ -n "$MAL_ID" ] && [ "$CANARY_ID" != "$MAL_ID" ]; then
    harness_ok "PickupGroups: CANARY/MALICIOUS fixtures created" "CANARY id=${CANARY_ID}, MALICIOUS id=${MAL_ID}"
else
    harness_blocked "could not create PickupGroups CANARY/MALICIOUS fixtures -- output: $FIXTURE_OUT"
fi
cleanup_pickupgroups_fixtures() {
    run_manager_php "Snep_PickupGroups_Manager::delete(${CANARY_ID}); Snep_PickupGroups_Manager::delete(${MAL_ID}); echo 'cleaned';" | grep -q cleaned
}
harness_register_cleanup "pickup groups CANARY/MALICIOUS fixtures (id=${CANARY_ID}/${MAL_ID})" "cleanup_pickupgroups_fixtures"

# 25. Boolean-shaped id cannot cross-leak another group's data: a
# "0 OR cod_grupo=<CANARY_ID>" id (leading "0" collapses to numeric 0 on
# implicit string->int coercion once bound as literal data, matching no
# real row -- the exact TASK-0026J BLOCKER A payload shape) must not
# render CANARY's own name anywhere in the response.
INJECTED_ID="0 OR cod_grupo=${CANARY_ID}"
INJECTED_ID_ENC="$(printf '%s' "$INJECTED_ID" | sed 's/ /%20/g; s/=/%3D/g')"
code="$(request "$RESTRICTED_JAR" GET "/index.php/default/pickup-groups/edit/id/${INJECTED_ID_ENC}")"
if [ "$code" = 200 ] && ! grep -qF "task0026l-canary" "$BODY"; then
    harness_ok "PickupGroups: boolean-shaped id cannot cross-leak another group" "HTTP $code, CANARY's own name not rendered"
else
    harness_bad "PickupGroups: boolean-shaped id cannot cross-leak another group" "HTTP $code, unexpected CANARY leak in body"
fi

# 26-33. Sibling methods verified via direct invocation of the now-fixed
# Manager code (see this script's header comment for why
# removeAction()/addAction()/editAction()'s POST branch are unreachable
# via HTTP in this environment -- three separate, pre-existing, unrelated
# PHP 8.4 bugs, none fixed by this task).
SIBLING_OUT="$(run_manager_php "
\$db = Zend_Registry::get('db');
\$canaryId = ${CANARY_ID}; \$malId = ${MAL_ID};
\$injected = '0 OR cod_grupo=' . \$canaryId;

\$r = Snep_PickupGroups_Manager::getValidation(\$canaryId);
echo 'GETVALIDATION_LEGIT:' . ((is_array(\$r) && count(\$r) === 0) ? 'OK' : 'BAD') . PHP_EOL;

try {
    \$r = Snep_PickupGroups_Manager::getValidation(\"foo'bar\");
    echo 'GETVALIDATION_APOSTROPHE:' . (is_array(\$r) ? 'OK' : 'BAD') . PHP_EOL;
} catch (Exception \$e) {
    echo 'GETVALIDATION_APOSTROPHE:EXCEPTION:' . \$e->getMessage() . PHP_EOL;
}

try {
    \$r = Snep_PickupGroups_Manager::getValidation(\$injected);
    echo 'GETVALIDATION_BOOLEAN:' . ((is_array(\$r) && count(\$r) === 0) ? 'OK' : 'BAD') . PHP_EOL;
} catch (Exception \$e) {
    echo 'GETVALIDATION_BOOLEAN:EXCEPTION:' . \$e->getMessage() . PHP_EOL;
}

try {
    Snep_PickupGroups_Manager::editGroup(['name' => 'task0026l-hijacked', 'id' => \$injected]);
    \$after = Snep_PickupGroups_Manager::get(\$canaryId);
    echo 'EDITGROUP_BOOLEAN:' . ((\$after && \$after['nome'] === 'task0026l-canary') ? 'OK' : 'BAD') . PHP_EOL;
} catch (Exception \$e) {
    echo 'EDITGROUP_BOOLEAN:EXCEPTION:' . \$e->getMessage() . PHP_EOL;
}

try {
    Snep_PickupGroups_Manager::editGroup(['name' => 'task0026l-canary-renamed', 'id' => \$canaryId]);
    \$after = Snep_PickupGroups_Manager::get(\$canaryId);
    echo 'EDITGROUP_LEGIT:' . ((\$after && \$after['nome'] === 'task0026l-canary-renamed') ? 'OK' : 'BAD') . PHP_EOL;
} catch (Exception \$e) {
    echo 'EDITGROUP_LEGIT:EXCEPTION:' . \$e->getMessage() . PHP_EOL;
}

try {
    Snep_PickupGroups_Manager::addExtensionsGroup(['extensions' => \"1' OR '1'='1\", 'pickupgroup' => \$malId]);
    echo 'ADDEXTGROUP_SHAPED:OK' . PHP_EOL;
} catch (Exception \$e) {
    echo 'ADDEXTGROUP_SHAPED:EXCEPTION:' . \$e->getMessage() . PHP_EOL;
}

try {
    \$select = Snep_PickupGroups_Manager::getFilter('nome', \"foo' OR '1'='1\");
    \$stmt = \$db->query(\$select);
    \$stmt->fetchAll();
    echo 'GETFILTER_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception \$e) {
    echo 'GETFILTER_APOSTROPHE:EXCEPTION:' . \$e->getMessage() . PHP_EOL;
}

try {
    Snep_PickupGroups_Manager::delete(\"foo'bar\");
    \$after = Snep_PickupGroups_Manager::get(\$canaryId);
    echo 'DELETE_APOSTROPHE:' . (\$after ? 'OK' : 'BAD') . PHP_EOL;
} catch (Exception \$e) {
    echo 'DELETE_APOSTROPHE:EXCEPTION:' . \$e->getMessage() . PHP_EOL;
}
")"

assert_marker "PickupGroups: getValidation() legitimate lookup returns cleanly" "GETVALIDATION_LEGIT" "$SIBLING_OUT"
assert_marker "PickupGroups: getValidation() apostrophe-shaped id causes no exception" "GETVALIDATION_APOSTROPHE" "$SIBLING_OUT"
assert_marker "PickupGroups: getValidation() boolean-shaped id matches nothing" "GETVALIDATION_BOOLEAN" "$SIBLING_OUT"
assert_marker "PickupGroups: editGroup() boolean-shaped id cannot alter CANARY" "EDITGROUP_BOOLEAN" "$SIBLING_OUT"
assert_marker "PickupGroups: editGroup() legitimate rename works" "EDITGROUP_LEGIT" "$SIBLING_OUT"
assert_marker "PickupGroups: addExtensionsGroup() SQL-shaped value causes no exception" "ADDEXTGROUP_SHAPED" "$SIBLING_OUT"
assert_marker "PickupGroups: getFilter() apostrophe-shaped query causes no exception" "GETFILTER_APOSTROPHE" "$SIBLING_OUT"
assert_marker "PickupGroups: delete() apostrophe-shaped id causes no exception, CANARY untouched" "DELETE_APOSTROPHE" "$SIBLING_OUT"

FATALS_AFTER_E="$(fatal_count)"
if [ "$FATALS_AFTER_E" = "$FATALS_BEFORE_E" ]; then
    harness_ok "BLOCKER E: application remained healthy" "PHP Fatal Error count unchanged (${FATALS_BEFORE_E})"
else
    harness_bad "BLOCKER E: application remained healthy" "PHP Fatal Error count changed: ${FATALS_BEFORE_E} -> ${FATALS_AFTER_E}"
fi

# =============================================================================
# BLOCKER F -- Snep_Queues_Manager::getValidation() and siblings
# =============================================================================

log "==> BLOCKER F: Snep_Queues_Manager boundary"

# 34. Fixtures: CANARY/CANARY2/MALICIOUS queues, created via direct
# Snep_Queues_Manager::add() invocation -- QueuesController::addAction()
# cannot be used here (identical count(false) TypeError as PickupGroups').
# SNEP's own field convention throughout QueuesController -- confirmed
# live, preserved exactly as-is, not a bug this task fixes: the
# route/POST "id" field carries the queue's NAME (every Manager lookup
# here keys on name), the POST "name" field carries the queue's real
# numeric database id (used only by removeUserPermission()'s queue_id
# FK lookup).
FIXTURE_OUT_Q="$(run_manager_php "
\$base = ['musiconhold'=>'default','announce'=>'','context'=>'from-queue','timeout'=>15,'queue_youarenext'=>'','queue_thereare'=>'','queue_callswaiting'=>'','queue_thankyou'=>'','announce_frequency'=>0,'retry'=>5,'wrapuptime'=>0,'maxlen'=>0,'servicelevel'=>60,'strategy'=>'ringall','joinempty'=>'yes','leavewhenempty'=>0,'reportholdtime'=>0,'memberdelay'=>0,'weight'=>0,'ringinuse'=>0];
\$c = \$base; \$c['name'] = 'task0026lqcanary';
\$c2 = \$base; \$c2['name'] = 'task0026lqcanary2';
\$m = \$base; \$m['name'] = \"task0026lq-mal's\";
echo 'FIXTURES:' . Snep_Queues_Manager::add(\$c) . ',' . Snep_Queues_Manager::add(\$c2) . ',' . Snep_Queues_Manager::add(\$m) . PHP_EOL;
")"
FIXTURE_LINE_Q="$(echo "$FIXTURE_OUT_Q" | grep '^FIXTURES:' | head -1)"
QCANARY_ID="$(echo "$FIXTURE_LINE_Q" | sed 's/FIXTURES://' | cut -d, -f1 | tr -d '\r')"
QCANARY2_ID="$(echo "$FIXTURE_LINE_Q" | sed 's/FIXTURES://' | cut -d, -f2 | tr -d '\r')"
QMAL_ID="$(echo "$FIXTURE_LINE_Q" | sed 's/FIXTURES://' | cut -d, -f3 | tr -d '\r')"
if [ -n "$QCANARY_ID" ] && [ -n "$QCANARY2_ID" ] && [ -n "$QMAL_ID" ]; then
    harness_ok "Queues: CANARY/CANARY2/MALICIOUS fixtures created" "ids=${QCANARY_ID}/${QCANARY2_ID}/${QMAL_ID}"
else
    harness_blocked "could not create Queues CANARY/CANARY2/MALICIOUS fixtures -- output: $FIXTURE_OUT_Q"
fi
cleanup_queues_fixtures() {
    run_manager_php "
foreach (['task0026lqcanary','task0026lqcanary2',\"task0026lq-mal's\"] as \$n) {
    Snep_Queues_Manager::remove(\$n);
    Snep_Queues_Manager::removeQueues(\$n);
    Snep_Queues_Manager::removeQueuePeers(\$n);
}
foreach ([${QCANARY_ID}, ${QCANARY2_ID}, ${QMAL_ID}] as \$i) {
    Snep_Queues_Manager::removeUserPermission(\$i);
}
echo 'cleaned';
" | grep -q cleaned
}
harness_register_cleanup "queues CANARY/CANARY2/MALICIOUS fixtures (ids=${QCANARY_ID}/${QCANARY2_ID}/${QMAL_ID})" "cleanup_queues_fixtures"

# 35. Legitimate GET removeAction (real name) reaches the DB layer
# cleanly and renders the delete-confirmation page (getValidation()'s
# legitimate path, plus getValidationPeers()/getValidationAgent()/get()).
code="$(request "$RESTRICTED_JAR" GET "/index.php/default/queues/remove/id/task0026lqcanary")"
if [ "$code" = 200 ]; then
    harness_ok "Queues: legitimate removeAction lookup (CANARY) reaches the DB layer cleanly" "HTTP $code"
else
    harness_bad "Queues: legitimate removeAction lookup (CANARY) reaches the DB layer cleanly" "HTTP $code"
fi

# 36. Apostrophe-shaped id causes no SQL error -- the core BLOCKER F
# proof (getValidation()). Pre-fix this produced a genuine
# SQLSTATE[42000] syntax error (confirmed live during this task's own
# A/B verification).
code="$(request "$RESTRICTED_JAR" GET "/index.php/default/queues/remove/id/foo%27bar")"
TAIL_F="$(app_exec 'tail -c 2000 /var/log/apache2/mag-error.log 2>/dev/null')"
if [ "$code" = 200 ] && ! echo "$TAIL_F" | grep -qi "SQLSTATE\|syntax error"; then
    harness_ok "Queues: apostrophe-shaped id causes no SQL error" "HTTP $code, no SQL/syntax error"
else
    harness_bad "Queues: apostrophe-shaped id causes no SQL error" "HTTP $code, log tail: $(echo "$TAIL_F" | tr '\n' ' ' | tail -c 300)"
fi

# 37. Boolean/apostrophe-shaped POST removeAction cannot delete CANARY2 --
# remove()/removeQueues()/removeUserPermission()/removeQueuePeers() are
# all reached with the same neutralized payload; all now bind as literal
# data, matching no real row.
code="$(post_fields "$RESTRICTED_JAR" "/index.php/default/queues/remove/id/x%27%20OR%20%271%27%3D%271" \
    "id=x' OR '1'='1" "name=0 OR queue_id=${QCANARY2_ID}" "snep_csrf_token=${RESTRICTED_CSRF}")"
STILL_THERE="$(db_query "SELECT COUNT(*) FROM queues WHERE name='task0026lqcanary2';")"
if [ "$code" = 302 ] && [ "$STILL_THERE" = "1" ]; then
    harness_ok "Queues: boolean-shaped POST removeAction cannot delete CANARY2" "HTTP $code, CANARY2 still present"
else
    harness_bad "Queues: boolean-shaped POST removeAction cannot delete CANARY2" "HTTP $code, CANARY2 count=${STILL_THERE}"
fi

# 38. Legitimate remove still works end to end: deleting CANARY (real
# name + real numeric id) actually removes it (remove()/removeQueues()/
# removeUserPermission()/removeQueuePeers() all still function correctly
# for legitimate values).
code="$(post_fields "$RESTRICTED_JAR" "/index.php/default/queues/remove/id/task0026lqcanary" \
    "id=task0026lqcanary" "name=${QCANARY_ID}" "snep_csrf_token=${RESTRICTED_CSRF}")"
GONE="$(db_query "SELECT COUNT(*) FROM queues WHERE name='task0026lqcanary';")"
if [ "$code" = 302 ] && [ "$GONE" = "0" ]; then
    harness_ok "Queues: legitimate remove (CANARY) still works end to end" "HTTP $code, CANARY row removed"
else
    harness_bad "Queues: legitimate remove (CANARY) still works end to end" "HTTP $code, CANARY count=${GONE}"
fi

# 39. edit()'s second-order boundary: MALICIOUS's own mass-assignable
# name (containing an apostrophe, stored verbatim by add(), no
# server-side sanitization at creation time) flows back into edit()'s
# WHERE clause on every subsequent legitimate edit -- the exact same
# second-order pattern TASK-0026J's BLOCKER A closed for trunk names.
# Must apply cleanly, no SQL error.
code="$(post_fields "$RESTRICTED_JAR" "/index.php/default/queues/edit/id/task0026lq-mal's" \
    "musiconhold=default" "announce=" "context=from-queue" "timeout=42" "queue_youarenext=" "queue_thereare=" \
    "queue_callswaiting=" "queue_thankyou=" "announce_frequency=0" "retry=5" "wrapuptime=0" "maxlen=0" \
    "servicelevel=60" "strategy=ringall" "joinempty=yes" "leavewhenempty=0" "reportholdtime=0" "memberdelay=0" \
    "weight=0" "ringinuse=0" "snep_csrf_token=${RESTRICTED_CSRF}")"
NEW_TIMEOUT="$(db_query "SELECT timeout FROM queues WHERE id=${QMAL_ID};")"
if [ "$code" = 302 ] && [ "$NEW_TIMEOUT" = "42" ]; then
    harness_ok "Queues: edit() second-order boundary (mass-assignable apostrophe-bearing name) applies cleanly" "HTTP $code, timeout updated to 42"
else
    harness_bad "Queues: edit() second-order boundary (mass-assignable apostrophe-bearing name) applies cleanly" "HTTP $code, timeout=${NEW_TIMEOUT}"
fi

# 40. membersAction()'s removeAllMembers() boundary: SQL-shaped route id
# causes no crash, no SQL error.
code="$(post_fields "$RESTRICTED_JAR" "/index.php/default/queues/members/id/x%27%20OR%20%271%27%3D%271" \
    "snep_csrf_token=${RESTRICTED_CSRF}")"
TAIL_MEMBERS="$(app_exec 'tail -c 2000 /var/log/apache2/mag-error.log 2>/dev/null')"
if [ "$code" = 302 ] && ! echo "$TAIL_MEMBERS" | grep -qi "SQLSTATE\|syntax error"; then
    harness_ok "Queues: membersAction() SQL-shaped id causes no SQL error" "HTTP $code, no SQL/syntax error"
else
    harness_bad "Queues: membersAction() SQL-shaped id causes no SQL error" "HTTP $code, log tail: $(echo "$TAIL_MEMBERS" | tr '\n' ' ' | tail -c 300)"
fi

FATALS_AFTER_F="$(fatal_count)"
if [ "$FATALS_AFTER_F" = "$FATALS_AFTER_E" ]; then
    harness_ok "BLOCKER F: application remained healthy" "PHP Fatal Error count unchanged (${FATALS_AFTER_E})"
else
    harness_bad "BLOCKER F: application remained healthy" "PHP Fatal Error count changed: ${FATALS_AFTER_E} -> ${FATALS_AFTER_F}"
fi

harness_complete
