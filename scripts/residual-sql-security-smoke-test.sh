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
# TASK-0026M extends this suite again to close the 11 confirmed
# supported-surface sinks TASK-0026L's own Phase 7 final sweep discovered
# but explicitly left unfixed (docs/tasks/0026l-pickup-queues-sql-closure.md,
# "Security handoff"), spanning the Contacts, ContactGroups, CostCenter,
# DatesAliases, ExpressionAliases, ExtensionsGroups, SoundFiles, Billing
# and Telcos Managers (plus every sibling method in the same files sharing
# the identical raw-interpolation pattern, and PBX_ExpressionAliases -- a
# closely-related twin class for the same expr_alias feature/table). See
# docs/tasks/0026m-manager-layer-residual-sql-closure.md for the full
# inventory. Billing_Manager/Telcos_Manager's every mutating action is
# currently HTTP-unreachable (a pre-existing, unrelated PHP 8.4
# "non-static method called statically" fatal, confirmed live -- the same
# bug class TASK-0026L documented for PickupGroupsController) and is
# verified via direct Manager invocation only, matching that task's own
# established precedent.
#
# TASK-0026N extends this suite again to close the four confirmed sinks
# TASK-0026M's own Phase 9 final sweep discovered but explicitly left
# unfixed (docs/tasks/0026m-manager-layer-residual-sql-closure.md,
# "Security handoff"): PBX_Rule::checkExpr()'s 'CG'/'G' cases,
# PBX_Usuarios::hasExtenGroup(), and PBX_Rules::delete() -- see
# docs/tasks/0026n-pbx-rule-sql-closure.md for the full inventory,
# including the sibling sites (PBX_Rule::getValidAliasDateById(),
# PBX_Usuarios::get(), PBX_Rules::get()/update()) fixed alongside them.
#
# TASK-0026O extends this suite again to close the two confirmed sinks
# TASK-0026N's own Phase 8 final sweep discovered but explicitly left
# unfixed (docs/tasks/0026n-pbx-rule-sql-closure.md, "Security handoff"):
#
#   O1 -- RouteController::indexAction()'s own inline SQL
#     (`where("type = '$type'")`, raw $_GET['type']) -- reachable on the
#     route list page itself. regras_negocio.type is a MariaDB
#     enum('incoming','outgoing','others') column (schema.sql), so this
#     was closed with a strict allowlist (not just parameterization) --
#     see docs/tasks/0026o-route-binds-sql-closure.md.
#   O2/O3 -- Snep_Binds_Manager::removeBond()/removeBondException()
#     (`delete('core_binds'/'core_binds_exceptions', "user_id = '$id'")`)
#     -- reachable via UsersController::removeAction() (route id) and
#     ::bondAction() (POST id).
#
# Sibling audit additionally found and fixed removeBondByPeer() (identical
# `delete('core_binds', "peer_name = '$peer'")` pattern) -- reachable via
# ExtensionsController::removeAction() with the raw, unvalidated $_POST['id']
# (Snep_Extensions_Manager::getPeer() returns false, not an exception, for a
# non-matching id, so execution reaches removeBondByPeer() with the raw
# value regardless of whether it matches a real extension).
#
# TASK-0026P extends this suite again to close the one confirmed sink
# TASK-0026O's own Phase 7 final sweep discovered but explicitly left
# unfixed (docs/tasks/0026o-route-binds-sql-closure.md, "Security
# handoff"):
#
#   P1 -- Snep_ModuleSettings_Manager::getConfig()
#     (`where("config_name = '$module'")`) -- reachable via
#     ModuleSettingsController::indexAction()'s own POST field-NAME
#     parsing, gated only by a read-level permission (no "write"
#     resource exists for this controller at all) -- see
#     docs/tasks/0026p-module-settings-sql-closure.md.
#
# Sibling audit additionally found and fixed get() (identical pattern,
# not independently confirmed exploitable, fixed for defense in depth)
# and delConfig() (identical pattern, zero callers anywhere in the tree,
# fixed anyway as an exact-pattern sibling). A genuine regression --
# Zend_Db_Select::_where() skips its own quoteInto() call when its value
# argument is null, leaving a raw unbound '?' in the SQL -- was found and
# fixed during this task's own development; see that doc for the full
# explanation.
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
require_once 'Zend/Log.php';
Zend_Registry::set('log', new Zend_Log());
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

for boundary_path in "/index.php/default/trunks/add" "/index.php/default/calls-report" "/index.php/default/ranking-report" "/index.php/default/services-report" "/index.php/default/pickup-groups" "/index.php/default/queues" "/index.php/default/contacts" "/index.php/default/contact-groups" "/index.php/default/dates-alias" "/index.php/default/expression-alias" "/index.php/default/cost-center" "/index.php/default/extensions-groups" "/index.php/default/sound-files" "/index.php/billing/billing" "/index.php/billing/telcos" "/index.php/default/route" "/index.php/default/users" "/index.php/default/module-settings"; do
    code="$(request "$RESTRICTED_JAR" GET "$boundary_path")"
    if [ "$code" = 302 ] && redirects_to_permission_error; then
        harness_ok "authorization intact: ${boundary_path}" "zero-permission user denied (HTTP 302, Location: permission/error)"
    else
        harness_bad "authorization intact: ${boundary_path}" "expected 302+permission/error, got HTTP ${code}"
    fi
done

# TASK-0026N: default_simulator is on the authenticated-open allowlist
# (Snep_PermissionPlugin::$readActions -- see PermissionPlugin.php) --
# unlike every resource above, a zero-permission session must be ALLOWED
# in, not denied. This is exactly the property that makes the CG/G
# findings severe: no specific grant is needed at all.
code="$(request "$RESTRICTED_JAR" GET "/index.php/default/simulator")"
if [ "$code" = 200 ]; then
    harness_ok "authenticated-open confirmed: /index.php/default/simulator" "zero-permission user still allowed in (HTTP 200) -- default_simulator requires no specific grant"
else
    harness_bad "authenticated-open confirmed: /index.php/default/simulator" "expected HTTP 200 for a zero-permission session, got HTTP ${code}"
fi

code="$(request "$ADMIN_JAR" POST /index.php/default/users/permission/id/$RID "user=$RID&default_trunks_write=1&default_calls-report_read=1&default_ranking-report_read=1&default_services-report_read=1&default_pickup-groups_write=1&default_queues_write=1&default_contacts_write=1&default_contact-groups_write=1&default_dates-alias_write=1&default_expression-alias_write=1&default_cost-center_write=1&default_extensions-groups_write=1&default_sound-files_write=1&billing_billing_write=1&billing_telcos_write=1&default_route_write=1&default_route_read=1&default_users_write=1&default_module-settings_read=1&snep_csrf_token=${ADMIN_CSRF}")"
if [ "$code" = 302 ]; then
    harness_ok "admin grants the required TASK-0026M/N/O/P permissions" "HTTP $code (contacts/contact-groups/dates-alias/expression-alias/cost-center/extensions-groups/sound-files write, billing/telcos write, route write+read, users write, module-settings read, plus the six TASK-0026J-L permissions)"
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

# =============================================================================
# TASK-0026M -- Manager-layer residual SQL injection closure
# =============================================================================
#
# Closes the 11 confirmed supported-surface SQL-injection sinks TASK-0026L's
# own Phase 7 final sweep discovered but explicitly left unfixed
# (docs/tasks/0026l-pickup-queues-sql-closure.md, "Security handoff"),
# spanning the Contacts, ContactGroups, CostCenter, DatesAliases,
# ExpressionAliases, ExtensionsGroups, SoundFiles, Billing and Telcos
# Managers, plus every sibling method in those same files/classes sharing
# the exact same raw-interpolation pattern (31 sites total across 10
# files -- see docs/tasks/0026m-manager-layer-residual-sql-closure.md for
# the full inventory).
#
# manager_check <label> <path> <field=value>... -- POSTs to <path> via the
# restricted session and verifies no new PHP Fatal Error and no SQL/syntax
# error appears in the log tail. Mirrors report_check() above.
manager_check() {
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

# manager_check_get <label> <path> -- GET twin of manager_check(), for
# request-controlled query-string boundaries (TASK-0026O:
# RouteController::indexAction()'s $_GET['type']). <path> must already be
# fully percent-encoded by the caller (request() issues a plain GET, it
# does not encode the path itself).
manager_check_get() {
    local label="$1" path="$2"
    local before_total after_total tail_text total_delta
    before_total="$(fatal_count)"
    request "$RESTRICTED_JAR" GET "$path" >/dev/null
    after_total="$(fatal_count)"
    tail_text="$(app_exec 'tail -c 4000 /var/log/apache2/mag-error.log 2>/dev/null')"
    total_delta=$((after_total - before_total))
    if [ "$total_delta" -eq 0 ] && ! echo "$tail_text" | grep -qi "SQLSTATE\|syntax error"; then
        harness_ok "$label" "no PHP Fatal Error, no SQL/syntax error"
    else
        harness_bad "$label" "fatal_delta=${total_delta}; log tail: $(echo "$tail_text" | tr '\n' ' ' | tail -c 300)"
    fi
}

# run_manager_php_file <local-php-file> -- like run_manager_php but takes an
# already-written local PHP file (real $ signs, no bash \$ escaping needed)
# instead of a bash string argument -- used for this section's larger
# per-family fixture/verification blocks, where escaping every PHP $variable
# as \$ inside a bash string would be error-prone at this scale.
run_manager_php_file() {
    local src="$1" f
    f="$(mktemp)"
    { printf '<?php\n'; printf "require '%s';\n" "$CLI_BOOTSTRAP_REMOTE"; cat "$src"; } > "$f"
    $COMPOSE cp "$f" app:/tmp/task0026m_run.php >/dev/null 2>&1
    rm -f "$f"
    app_exec "php -d display_errors=0 /tmp/task0026m_run.php"
}
harness_register_best_effort_cleanup "run_manager_php_file scratch file in app container" "$COMPOSE exec -T app rm -f /tmp/task0026m_run.php"

# sweep_task0026m_residue -- best-effort safety net in case any family block
# below exits early (an uncaught exception mid-PHP-block, etc.) before its
# own inline cleanup runs. Every fixture this section creates uses a
# task0026m-prefixed name/value; nothing else in the schema does.
sweep_task0026m_residue() {
    db_query "
DELETE FROM contacts_names WHERE name LIKE 'task0026m-%';
DELETE FROM contacts_group WHERE name LIKE 'task0026m-%';
DELETE FROM date_alias_list WHERE dateid IN (SELECT id FROM date_alias WHERE name LIKE 'task0026m-%');
DELETE FROM date_alias WHERE name LIKE 'task0026m-%';
DELETE FROM expr_alias_expression WHERE aliasid IN (SELECT aliasid FROM expr_alias WHERE name LIKE 'task0026m-%');
DELETE FROM expr_alias WHERE name LIKE 'task0026m-%';
DELETE FROM ccustos WHERE codigo LIKE 't0026m%';
DELETE FROM core_peer_groups WHERE group_id IN (SELECT id FROM core_groups WHERE name LIKE 'task0026m-%');
DELETE FROM core_groups WHERE name LIKE 'task0026m-%';
DELETE FROM sounds WHERE arquivo LIKE 'task0026m-%';
DELETE FROM telcos WHERE name LIKE 'task0026m-%';
DELETE FROM billing WHERE telco IN (SELECT id FROM telcos WHERE name LIKE 'task0026m-%');
" >/dev/null 2>&1
}
harness_register_cleanup "TASK-0026M residual fixture sweep (safety net)" "sweep_task0026m_residue"

log "==> TASK-0026M: Contacts/ContactGroups/DatesAlias/ExpressionAlias/CostCenter/ExtensionsGroups/SoundFiles/Billing/Telcos boundary"

FATALS_BEFORE_M="$(fatal_count)"

# --- Real-HTTP core proof: apostrophe-shaped payload against the primary,
# directly-reachable sink in each of the 7 web-reachable families causes no
# SQL error (matches the exact BLOCKER A-F live-reproduction style). Billing
# and Telcos have no real-HTTP path at all (see below) so are covered
# entirely via direct Manager invocation.

manager_check "Contacts: apostrophe-shaped remove id causes no SQL error" \
    /index.php/default/contacts/remove "id=foo'bar" "snep_csrf_token=${RESTRICTED_CSRF}"

manager_check "ContactGroups: apostrophe-shaped remove id causes no SQL error" \
    /index.php/default/contact-groups/remove/id/1 "id=foo'bar" "snep_csrf_token=${RESTRICTED_CSRF}"

manager_check "DatesAlias: apostrophe-shaped remove id (delete()) causes no SQL error" \
    /index.php/default/dates-alias/remove/id/1 "id=foo'bar" "snep_csrf_token=${RESTRICTED_CSRF}"

code="$(request "$RESTRICTED_JAR" GET "/index.php/default/dates-alias/remove/id/foo%27bar")"
TAIL_DA="$(app_exec 'tail -c 2000 /var/log/apache2/mag-error.log 2>/dev/null')"
if [ "$code" = 200 ] && ! echo "$TAIL_DA" | grep -qi "SQLSTATE\|syntax error"; then
    harness_ok "DatesAlias: apostrophe-shaped route id (GET getValidation()) causes no SQL error" "HTTP $code, no SQL/syntax error"
else
    harness_bad "DatesAlias: apostrophe-shaped route id (GET getValidation()) causes no SQL error" "HTTP $code, log tail: $(echo "$TAIL_DA" | tr '\n' ' ' | tail -c 300)"
fi

manager_check "ExpressionAlias: apostrophe-shaped remove id causes no SQL error" \
    /index.php/default/expression-alias/remove/id/1 "id=foo'bar" "snep_csrf_token=${RESTRICTED_CSRF}"

manager_check "CostCenter: apostrophe-shaped remove id causes no SQL error" \
    /index.php/default/cost-center/remove/id/1 "id=foo'bar" "snep_csrf_token=${RESTRICTED_CSRF}"

manager_check "ExtensionsGroups: apostrophe-shaped remove id causes no SQL error" \
    /index.php/default/extensions-groups/remove/id/1 "id=foo'bar" "snep_csrf_token=${RESTRICTED_CSRF}"

manager_check "SoundFiles: apostrophe-shaped remove id causes no SQL error" \
    /index.php/default/sound-files/remove/arquivo/a-m.wav "id=foo'bar" "snep_csrf_token=${RESTRICTED_CSRF}"

# --- Sibling/second-order coverage via direct Manager invocation (the same
# real PHP code path, same Zend_Db adapter, that the fixtures above exercise
# through HTTP) -- one self-contained, self-cleaning block per family.

CONTACTS_PHP="$(mktemp)"
cat > "$CONTACTS_PHP" <<'PHPEOF'
$cid1 = Snep_Contacts_Manager::getLastId();
Snep_Contacts_Manager::add(['id' => $cid1, 'name' => 'task0026m-contact-canary', 'address' => '', 'email' => '', 'city' => null, 'state' => null, 'zipcode' => '', 'group' => 1]);
$cid2 = $cid1 + 1;
Snep_Contacts_Manager::add(['id' => $cid2, 'name' => 'task0026m-contact-canary2', 'address' => '', 'email' => '', 'city' => null, 'state' => null, 'zipcode' => '', 'group' => 1]);
$c1 = Snep_Contacts_Manager::get($cid1);
echo 'CONTACTS_FIXTURES:' . (($c1 && $c1['name'] === 'task0026m-contact-canary') ? 'OK' : 'BAD') . PHP_EOL;

Snep_Contacts_Manager::edit(['id' => $cid1, 'name' => 'task0026m-contact-canary-renamed', 'address' => '', 'email' => '', 'city' => null, 'state' => null, 'zipcode' => '', 'group' => 1]);
$after = Snep_Contacts_Manager::get($cid1);
echo 'CONTACTS_EDIT_LEGIT:' . (($after && $after['name'] === 'task0026m-contact-canary-renamed') ? 'OK' : 'BAD') . PHP_EOL;

try {
    Snep_Contacts_Manager::edit(['id' => "foo'bar", 'name' => 'x', 'address' => '', 'email' => '', 'city' => null, 'state' => null, 'zipcode' => '', 'group' => 1]);
    echo 'CONTACTS_EDIT_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'CONTACTS_EDIT_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

$before2 = Snep_Contacts_Manager::get($cid2);
try {
    Snep_Contacts_Manager::remove("0 OR id=" . $cid2);
} catch (Exception $e) {
}
$after2 = Snep_Contacts_Manager::get($cid2);
echo 'CONTACTS_REMOVE_BOOLEAN_ISOLATED:' . (($after2 && $after2['name'] === $before2['name']) ? 'OK' : 'BAD') . PHP_EOL;

try {
    Snep_Contacts_Manager::removePhone("foo'bar");
    echo 'CONTACTS_REMOVEPHONE_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'CONTACTS_REMOVEPHONE_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

try {
    Snep_Contacts_Manager::removeGroup("foo'bar");
    echo 'CONTACTS_REMOVEGROUP_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'CONTACTS_REMOVEGROUP_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

try {
    Snep_Contacts_Manager::removeByGroupId("foo'bar");
    echo 'CONTACTS_REMOVEBYGROUP_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'CONTACTS_REMOVEBYGROUP_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}
$still2 = Snep_Contacts_Manager::get($cid2);
echo 'CONTACTS2_STILL_PRESENT:' . ($still2 ? 'OK' : 'BAD') . PHP_EOL;

Snep_Contacts_Manager::remove($cid1);
$gone1 = Snep_Contacts_Manager::get($cid1);
echo 'CONTACTS_REMOVE_LEGIT:' . (!$gone1 ? 'OK' : 'BAD') . PHP_EOL;
Snep_Contacts_Manager::remove($cid2);
$gone2 = Snep_Contacts_Manager::get($cid2);
echo 'CONTACTS_CLEANUP:' . (!$gone2 ? 'OK' : 'BAD') . PHP_EOL;
PHPEOF
CONTACTS_OUT="$(run_manager_php_file "$CONTACTS_PHP")"
rm -f "$CONTACTS_PHP"
for m in CONTACTS_FIXTURES CONTACTS_EDIT_LEGIT CONTACTS_EDIT_APOSTROPHE CONTACTS_REMOVE_BOOLEAN_ISOLATED CONTACTS_REMOVEPHONE_APOSTROPHE CONTACTS_REMOVEGROUP_APOSTROPHE CONTACTS_REMOVEBYGROUP_APOSTROPHE CONTACTS2_STILL_PRESENT CONTACTS_REMOVE_LEGIT CONTACTS_CLEANUP; do
    assert_marker "Contacts: ${m}" "$m" "$CONTACTS_OUT"
done

CONTACTGROUPS_PHP="$(mktemp)"
cat > "$CONTACTGROUPS_PHP" <<'PHPEOF'
$gid1 = Snep_ContactGroups_Manager::add(['group' => 'task0026m-cg-canary']);
$gid2 = Snep_ContactGroups_Manager::add(['group' => 'task0026m-cg-canary2']);
echo 'CONTACTGROUPS_FIXTURES:' . (($gid1 && $gid2) ? 'OK' : 'BAD') . PHP_EOL;

Snep_ContactGroups_Manager::edit(['group' => 'task0026m-cg-canary-renamed', 'id' => $gid1]);
$after = Snep_ContactGroups_Manager::get($gid1);
echo 'CONTACTGROUPS_EDIT_LEGIT:' . (($after && $after['name'] === 'task0026m-cg-canary-renamed') ? 'OK' : 'BAD') . PHP_EOL;

try {
    Snep_ContactGroups_Manager::edit(['group' => 'x', 'id' => "foo'bar"]);
    echo 'CONTACTGROUPS_EDIT_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'CONTACTGROUPS_EDIT_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

$before2 = Snep_ContactGroups_Manager::get($gid2);
try {
    Snep_ContactGroups_Manager::edit(['group' => 'hijacked', 'id' => "0 OR id=" . $gid2]);
} catch (Exception $e) {
}
$after2 = Snep_ContactGroups_Manager::get($gid2);
echo 'CONTACTGROUPS_EDIT_BOOLEAN_ISOLATED:' . (($after2 && $after2['name'] === $before2['name']) ? 'OK' : 'BAD') . PHP_EOL;

try {
    Snep_ContactGroups_Manager::insertContactOnGroup($gid1, "foo'bar");
    echo 'CONTACTGROUPS_INSERTCONTACT_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'CONTACTGROUPS_INSERTCONTACT_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

try {
    Snep_ContactGroups_Manager::removeContactOnGroup("foo'bar");
    echo 'CONTACTGROUPS_REMOVECONTACT_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'CONTACTGROUPS_REMOVECONTACT_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

Snep_ContactGroups_Manager::remove($gid1);
$gone1 = Snep_ContactGroups_Manager::get($gid1);
echo 'CONTACTGROUPS_REMOVE_LEGIT:' . (!$gone1 ? 'OK' : 'BAD') . PHP_EOL;
Snep_ContactGroups_Manager::remove($gid2);
$gone2 = Snep_ContactGroups_Manager::get($gid2);
echo 'CONTACTGROUPS_CLEANUP:' . (!$gone2 ? 'OK' : 'BAD') . PHP_EOL;
PHPEOF
CONTACTGROUPS_OUT="$(run_manager_php_file "$CONTACTGROUPS_PHP")"
rm -f "$CONTACTGROUPS_PHP"
for m in CONTACTGROUPS_FIXTURES CONTACTGROUPS_EDIT_LEGIT CONTACTGROUPS_EDIT_APOSTROPHE CONTACTGROUPS_EDIT_BOOLEAN_ISOLATED CONTACTGROUPS_INSERTCONTACT_APOSTROPHE CONTACTGROUPS_REMOVECONTACT_APOSTROPHE CONTACTGROUPS_REMOVE_LEGIT CONTACTGROUPS_CLEANUP; do
    assert_marker "ContactGroups: ${m}" "$m" "$CONTACTGROUPS_OUT"
done

DATESALIAS_PHP="$(mktemp)"
cat > "$DATESALIAS_PHP" <<'PHPEOF'
$db = Zend_Registry::get('db');
$daId = PBX_DatesAliases::add(['name' => 'task0026m-da-canary', 'date' => ['2030-01-01'], 'timerange' => ['00:00-23:59']]);
echo 'DATESALIAS_FIXTURE:' . ($daId ? 'OK' : 'BAD') . PHP_EOL;

$after = PBX_DatesAliases::get($daId);
echo 'DATESALIAS_GET_LEGIT:' . ((is_array($after) && count($after) > 0) ? 'OK' : 'BAD') . PHP_EOL;

try {
    PBX_DatesAliases::get("foo'bar");
    echo 'DATESALIAS_GET_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'DATESALIAS_GET_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

PBX_DatesAliases::update(['id' => $daId, 'name' => 'task0026m-da-canary-renamed', 'date' => ['2030-02-02'], 'timerange' => ['00:00-23:59']]);
$after2 = PBX_DatesAliases::get($daId);
echo 'DATESALIAS_UPDATE_LEGIT:' . (($after2 && $after2[0]['name'] === 'task0026m-da-canary-renamed') ? 'OK' : 'BAD') . PHP_EOL;

// update()'s own try/catch wraps only commit(), not the insert() that
// throws here on the unrelated int-typed dateid column (pre-existing,
// unrelated transaction-handling gap, not fixed by this task). SQLSTATE
// 22007 (a data-type rejection) is the OK outcome; SQLSTATE 42000 (a
// syntax error, what pre-fix raw interpolation would have produced) is
// the only FAIL signature.
try {
    PBX_DatesAliases::update(['id' => "foo'bar", 'name' => 'x', 'date' => ['2030-01-01'], 'timerange' => ['00:00-23:59']]);
    echo 'DATESALIAS_UPDATE_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    if ($db->getConnection()->inTransaction()) {
        $db->rollBack();
    }
    $msg = $e->getMessage();
    echo 'DATESALIAS_UPDATE_APOSTROPHE:' . ((stripos($msg, 'syntax') === false && stripos($msg, '42000') === false) ? 'OK' : ('EXCEPTION:' . $msg)) . PHP_EOL;
}

try {
    PBX_DatesAliases::getValidation("foo'bar");
    echo 'DATESALIAS_GETVALIDATION_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'DATESALIAS_GETVALIDATION_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

try {
    PBX_DatesAliases::delete("foo'bar");
    echo 'DATESALIAS_DELETE_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'DATESALIAS_DELETE_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}
$still = PBX_DatesAliases::get($daId);
echo 'DATESALIAS_STILL_PRESENT:' . ((is_array($still) && count($still) > 0) ? 'OK' : 'BAD') . PHP_EOL;

PBX_DatesAliases::delete($daId);
$gone = PBX_DatesAliases::get($daId);
echo 'DATESALIAS_CLEANUP:' . ((is_array($gone) && count($gone) === 0) ? 'OK' : 'BAD') . PHP_EOL;
PHPEOF
DATESALIAS_OUT="$(run_manager_php_file "$DATESALIAS_PHP")"
rm -f "$DATESALIAS_PHP"
for m in DATESALIAS_FIXTURE DATESALIAS_GET_LEGIT DATESALIAS_GET_APOSTROPHE DATESALIAS_UPDATE_LEGIT DATESALIAS_UPDATE_APOSTROPHE DATESALIAS_GETVALIDATION_APOSTROPHE DATESALIAS_DELETE_APOSTROPHE DATESALIAS_STILL_PRESENT DATESALIAS_CLEANUP; do
    assert_marker "DatesAlias: ${m}" "$m" "$DATESALIAS_OUT"
done

EXPRESSIONALIAS_PHP="$(mktemp)"
cat > "$EXPRESSIONALIAS_PHP" <<'PHPEOF'
$db = Zend_Registry::get('db');
$eaId = PBX_ExpressionAliases::getInstance()->register(['name' => 'task0026m-ea-canary', 'expressions' => ['_X.']]);
echo 'EXPRESSIONALIAS_FIXTURE:' . ($eaId ? 'OK' : 'BAD') . PHP_EOL;

$after = PBX_ExpressionAliases::getInstance()->get((int) $eaId);
echo 'EXPRESSIONALIAS_GET_LEGIT:' . (($after && $after['name'] === 'task0026m-ea-canary') ? 'OK' : 'BAD') . PHP_EOL;

// Same pre-existing, unrelated update()-transaction gap as PBX_DatesAliases
// above (this class's own closely-related twin), same OK/FAIL split.
try {
    PBX_ExpressionAliases::getInstance()->update(['id' => "foo'bar", 'name' => 'x', 'expressions' => ['_X.']]);
    echo 'EXPRESSIONALIAS_UPDATE_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    if ($db->getConnection()->inTransaction()) {
        $db->rollBack();
    }
    $msg = $e->getMessage();
    echo 'EXPRESSIONALIAS_UPDATE_APOSTROPHE:' . ((stripos($msg, 'syntax') === false && stripos($msg, '42000') === false) ? 'OK' : ('EXCEPTION:' . $msg)) . PHP_EOL;
}

PBX_ExpressionAliases::getInstance()->update(['id' => $eaId, 'name' => 'task0026m-ea-canary-renamed', 'expressions' => ['_X.']]);
$after2 = PBX_ExpressionAliases::getInstance()->get((int) $eaId);
echo 'EXPRESSIONALIAS_UPDATE_LEGIT:' . (($after2 && $after2['name'] === 'task0026m-ea-canary-renamed') ? 'OK' : 'BAD') . PHP_EOL;

try {
    Snep_ExpressionAliases_Manager::delete("foo'bar");
    echo 'EXPRESSIONALIAS_MGRDELETE_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'EXPRESSIONALIAS_MGRDELETE_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

try {
    PBX_ExpressionAliases::getInstance()->delete("foo'bar");
    echo 'EXPRESSIONALIAS_PBXDELETE_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'EXPRESSIONALIAS_PBXDELETE_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

try {
    Snep_ExpressionAliases_Manager::getValidation("foo'bar");
    echo 'EXPRESSIONALIAS_MGRGETVALIDATION_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'EXPRESSIONALIAS_MGRGETVALIDATION_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

$stillThere = PBX_ExpressionAliases::getInstance()->get((int) $eaId);
echo 'EXPRESSIONALIAS_STILL_PRESENT:' . (($stillThere && $stillThere['name'] === 'task0026m-ea-canary-renamed') ? 'OK' : 'BAD') . PHP_EOL;

Snep_ExpressionAliases_Manager::delete($eaId);
$all = PBX_ExpressionAliases::getInstance()->getAll();
echo 'EXPRESSIONALIAS_CLEANUP:' . (!isset($all[$eaId]) ? 'OK' : 'BAD') . PHP_EOL;
PHPEOF
EXPRESSIONALIAS_OUT="$(run_manager_php_file "$EXPRESSIONALIAS_PHP")"
rm -f "$EXPRESSIONALIAS_PHP"
for m in EXPRESSIONALIAS_FIXTURE EXPRESSIONALIAS_GET_LEGIT EXPRESSIONALIAS_UPDATE_APOSTROPHE EXPRESSIONALIAS_UPDATE_LEGIT EXPRESSIONALIAS_MGRDELETE_APOSTROPHE EXPRESSIONALIAS_PBXDELETE_APOSTROPHE EXPRESSIONALIAS_MGRGETVALIDATION_APOSTROPHE EXPRESSIONALIAS_STILL_PRESENT EXPRESSIONALIAS_CLEANUP; do
    assert_marker "ExpressionAlias: ${m}" "$m" "$EXPRESSIONALIAS_OUT"
done

COSTCENTER_PHP="$(mktemp)"
cat > "$COSTCENTER_PHP" <<'PHPEOF'
$ccId1 = 't0026m1';
$ccId2 = 't0026m2';
Snep_CostCenter_Manager::add(['id' => $ccId1, 'type' => 'O', 'name' => 'CC Canary', 'description' => '']);
Snep_CostCenter_Manager::add(['id' => $ccId2, 'type' => 'O', 'name' => 'CC Canary2', 'description' => '']);
$c1 = Snep_CostCenter_Manager::get($ccId1);
echo 'COSTCENTER_FIXTURES:' . (($c1 && $c1['nome'] === 'CC Canary') ? 'OK' : 'BAD') . PHP_EOL;

Snep_CostCenter_Manager::edit(['id' => $ccId1, 'type' => 'O', 'name' => 'CC Canary Renamed', 'description' => '']);
$after = Snep_CostCenter_Manager::get($ccId1);
echo 'COSTCENTER_EDIT_LEGIT:' . (($after && $after['nome'] === 'CC Canary Renamed') ? 'OK' : 'BAD') . PHP_EOL;

try {
    Snep_CostCenter_Manager::edit(['id' => "foo'bar", 'type' => 'O', 'name' => 'x', 'description' => '']);
    echo 'COSTCENTER_EDIT_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'COSTCENTER_EDIT_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

$before2 = Snep_CostCenter_Manager::get($ccId2);
try {
    Snep_CostCenter_Manager::remove("x' OR codigo='" . $ccId2);
} catch (Exception $e) {
}
$after2 = Snep_CostCenter_Manager::get($ccId2);
echo 'COSTCENTER_REMOVE_BOOLEAN_ISOLATED:' . (($after2 && $after2['nome'] === $before2['nome']) ? 'OK' : 'BAD') . PHP_EOL;

Snep_CostCenter_Manager::remove($ccId1);
$gone1 = Snep_CostCenter_Manager::get($ccId1);
echo 'COSTCENTER_REMOVE_LEGIT:' . (!$gone1 ? 'OK' : 'BAD') . PHP_EOL;
Snep_CostCenter_Manager::remove($ccId2);
$gone2 = Snep_CostCenter_Manager::get($ccId2);
echo 'COSTCENTER_CLEANUP:' . (!$gone2 ? 'OK' : 'BAD') . PHP_EOL;
PHPEOF
COSTCENTER_OUT="$(run_manager_php_file "$COSTCENTER_PHP")"
rm -f "$COSTCENTER_PHP"
for m in COSTCENTER_FIXTURES COSTCENTER_EDIT_LEGIT COSTCENTER_EDIT_APOSTROPHE COSTCENTER_REMOVE_BOOLEAN_ISOLATED COSTCENTER_REMOVE_LEGIT COSTCENTER_CLEANUP; do
    assert_marker "CostCenter: ${m}" "$m" "$COSTCENTER_OUT"
done

EXTGROUPS_PHP="$(mktemp)"
cat > "$EXTGROUPS_PHP" <<'PHPEOF'
$egId1 = Snep_ExtensionsGroups_Manager::addGroup(['name' => 'task0026m-eg-canary']);
$egId2 = Snep_ExtensionsGroups_Manager::addGroup(['name' => 'task0026m-eg-canary2']);
echo 'EXTGROUPS_FIXTURES:' . (($egId1 && $egId2) ? 'OK' : 'BAD') . PHP_EOL;

$g1 = Snep_ExtensionsGroups_Manager::get($egId1);
echo 'EXTGROUPS_GET_LEGIT:' . (($g1 && $g1['name'] === 'task0026m-eg-canary') ? 'OK' : 'BAD') . PHP_EOL;

try {
    Snep_ExtensionsGroups_Manager::get("foo'bar");
    echo 'EXTGROUPS_GET_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'EXTGROUPS_GET_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

Snep_ExtensionsGroups_Manager::editGroup(['id' => $egId1, 'name' => 'task0026m-eg-canary-renamed']);
$after = Snep_ExtensionsGroups_Manager::get($egId1);
echo 'EXTGROUPS_EDITGROUP_LEGIT:' . (($after && $after['name'] === 'task0026m-eg-canary-renamed') ? 'OK' : 'BAD') . PHP_EOL;

$before2 = Snep_ExtensionsGroups_Manager::get($egId2);
try {
    Snep_ExtensionsGroups_Manager::editGroup(['id' => "0 OR id=" . $egId2, 'name' => 'hijacked']);
} catch (Exception $e) {
}
$after2 = Snep_ExtensionsGroups_Manager::get($egId2);
echo 'EXTGROUPS_EDITGROUP_BOOLEAN_ISOLATED:' . (($after2 && $after2['name'] === $before2['name']) ? 'OK' : 'BAD') . PHP_EOL;

try {
    Snep_ExtensionsGroups_Manager::deleteGroupExtensions(['peer_id' => "foo'bar", 'group_id' => $egId1]);
    echo 'EXTGROUPS_DELETEGROUPEXT_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'EXTGROUPS_DELETEGROUPEXT_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

try {
    Snep_ExtensionsGroups_Manager::deleteExtensionGroups("foo'bar");
    echo 'EXTGROUPS_DELETEEXTGROUPS_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'EXTGROUPS_DELETEEXTGROUPS_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

Snep_ExtensionsGroups_Manager::delete($egId1);
$gone1 = Snep_ExtensionsGroups_Manager::get($egId1);
echo 'EXTGROUPS_DELETE_LEGIT:' . (!$gone1 ? 'OK' : 'BAD') . PHP_EOL;
Snep_ExtensionsGroups_Manager::delete($egId2);
$gone2 = Snep_ExtensionsGroups_Manager::get($egId2);
echo 'EXTGROUPS_CLEANUP:' . (!$gone2 ? 'OK' : 'BAD') . PHP_EOL;
PHPEOF
EXTGROUPS_OUT="$(run_manager_php_file "$EXTGROUPS_PHP")"
rm -f "$EXTGROUPS_PHP"
for m in EXTGROUPS_FIXTURES EXTGROUPS_GET_LEGIT EXTGROUPS_GET_APOSTROPHE EXTGROUPS_EDITGROUP_LEGIT EXTGROUPS_EDITGROUP_BOOLEAN_ISOLATED EXTGROUPS_DELETEGROUPEXT_APOSTROPHE EXTGROUPS_DELETEEXTGROUPS_APOSTROPHE EXTGROUPS_DELETE_LEGIT EXTGROUPS_CLEANUP; do
    assert_marker "ExtensionsGroups: ${m}" "$m" "$EXTGROUPS_OUT"
done

SOUNDFILES_PHP="$(mktemp)"
cat > "$SOUNDFILES_PHP" <<'PHPEOF'
$sf1 = 'task0026m-sf1.wav';
$sf2 = 'task0026m-sf2.wav';
// Snep_SoundFiles_Manager::add()'s own $insert_data omits 'secao' (a
// NOT-NULL, no-default, primary-key column) -- a pre-existing, unrelated
// strict-SQL-mode compatibility gap affecting the real addAction() flow
// identically, not fixed by this task. Insert the fixture rows directly
// to route around it.
$dbFixture = Zend_Registry::get('db');
$dbFixture->insert('sounds', ['arquivo' => $sf1, 'descricao' => 'canary', 'data' => new Zend_Db_Expr('NOW()'), 'language' => 'pt_BR', 'tipo' => 'AST', 'secao' => '']);
$dbFixture->insert('sounds', ['arquivo' => $sf2, 'descricao' => 'canary2', 'data' => new Zend_Db_Expr('NOW()'), 'language' => 'pt_BR', 'tipo' => 'AST', 'secao' => '']);
$soundMgr = new Snep_SoundFiles_Manager();
$s1 = $soundMgr->get($sf1);
echo 'SOUNDFILES_FIXTURES:' . (($s1) ? 'OK' : 'BAD') . PHP_EOL;

$soundMgr->edit(['arquivo' => $sf1, 'description' => 'canary-renamed']);
$after = $soundMgr->get($sf1);
echo 'SOUNDFILES_EDIT_LEGIT:' . (($after && $after['descricao'] === 'canary-renamed') ? 'OK' : 'BAD') . PHP_EOL;

try {
    $soundMgr->edit(['arquivo' => "foo'bar", 'description' => 'x']);
    echo 'SOUNDFILES_EDIT_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'SOUNDFILES_EDIT_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

$before2 = $soundMgr->get($sf2);
try {
    $soundMgr->edit(['arquivo' => $sf2 . "' OR '1'='1", 'description' => 'hijacked']);
} catch (Exception $e) {
}
$after2 = $soundMgr->get($sf2);
echo 'SOUNDFILES_EDIT_BOOLEAN_ISOLATED:' . (($after2 && $after2['descricao'] === $before2['descricao']) ? 'OK' : 'BAD') . PHP_EOL;

try {
    $soundMgr->remove("foo'bar");
    echo 'SOUNDFILES_REMOVE_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'SOUNDFILES_REMOVE_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}
$still2 = $soundMgr->get($sf2);
echo 'SOUNDFILES2_STILL_PRESENT:' . ($still2 ? 'OK' : 'BAD') . PHP_EOL;

try {
    $soundMgr->editClassFile(['arquivo' => "foo'bar", 'descricao' => 'x', 'secao' => "baz'qux"]);
    echo 'SOUNDFILES_EDITCLASSFILE_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'SOUNDFILES_EDITCLASSFILE_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

$soundMgr->remove($sf1);
$gone1 = $soundMgr->get($sf1);
echo 'SOUNDFILES_REMOVE_LEGIT:' . (!$gone1 ? 'OK' : 'BAD') . PHP_EOL;
$soundMgr->remove($sf2);
$gone2 = $soundMgr->get($sf2);
echo 'SOUNDFILES_CLEANUP:' . (!$gone2 ? 'OK' : 'BAD') . PHP_EOL;
PHPEOF
SOUNDFILES_OUT="$(run_manager_php_file "$SOUNDFILES_PHP")"
rm -f "$SOUNDFILES_PHP"
for m in SOUNDFILES_FIXTURES SOUNDFILES_EDIT_LEGIT SOUNDFILES_EDIT_APOSTROPHE SOUNDFILES_EDIT_BOOLEAN_ISOLATED SOUNDFILES_REMOVE_APOSTROPHE SOUNDFILES2_STILL_PRESENT SOUNDFILES_EDITCLASSFILE_APOSTROPHE SOUNDFILES_REMOVE_LEGIT SOUNDFILES_CLEANUP; do
    assert_marker "SoundFiles: ${m}" "$m" "$SOUNDFILES_OUT"
done

BILLING_PHP="$(mktemp)"
cat > "$BILLING_PHP" <<'PHPEOF'
// Billing_BillingController/Billing_TelcosController's every mutating
// action is currently HTTP-unreachable (a pre-existing, unrelated PHP 8.4
// "non-static method called statically" fatal in Billing_Manager/
// Telcos_Manager, confirmed live -- not fixed here, matching the exact
// class of bug TASK-0026L documented for PickupGroupsController). Both
// Managers' real vulnerable code is still fixed and verified here via
// direct invocation, matching that same task's own established precedent.
$dbFixture = Zend_Registry::get('db');
$tm = new Telcos_Manager();
$m = new Billing_Manager();

$telcoId = $tm->add(['name' => 'task0026m-telco', 'mobile_price' => 1, 'landline_price' => 1, 'start_time' => 0, 'fract' => 0]);
$telco2Id = $tm->add(['name' => 'task0026m-telco2', 'mobile_price' => 1, 'landline_price' => 1, 'start_time' => 0, 'fract' => 0]);
echo 'TELCOS_FIXTURES:' . ((is_int($telcoId) && is_int($telco2Id)) ? 'OK' : 'BAD') . PHP_EOL;

$ok = $tm->update(['id' => $telcoId, 'name' => 'task0026m-telco-renamed', 'mobile_price' => 2, 'landline_price' => 2, 'start_time' => 1, 'fract' => 1]);
$row = $tm->get($telcoId);
echo 'TELCOS_UPDATE_LEGIT:' . (($ok && $row['name'] === 'task0026m-telco-renamed') ? 'OK' : 'BAD') . PHP_EOL;

try {
    $tm->update(['id' => "foo'bar", 'name' => 'x', 'mobile_price' => 1, 'landline_price' => 1, 'start_time' => 1, 'fract' => 1]);
    echo 'TELCOS_UPDATE_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'TELCOS_UPDATE_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

$before2 = $tm->get($telco2Id);
try {
    $tm->update(['id' => "0 OR id={$telco2Id}", 'name' => 'hijacked', 'mobile_price' => 9, 'landline_price' => 9, 'start_time' => 9, 'fract' => 9]);
} catch (Exception $e) {
}
$after2 = $tm->get($telco2Id);
echo 'TELCOS_UPDATE_BOOLEAN_ISOLATED:' . (($after2['name'] === $before2['name']) ? 'OK' : 'BAD') . PHP_EOL;

try {
    $tm->remove("foo'bar");
    echo 'TELCOS_REMOVE_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'TELCOS_REMOVE_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}
$still2 = $tm->get($telco2Id);
echo 'TELCOS2_STILL_PRESENT:' . ($still2 ? 'OK' : 'BAD') . PHP_EOL;

$tm->remove($telcoId);
$gone = $tm->get($telcoId);
echo 'TELCOS_REMOVE_LEGIT:' . (!$gone ? 'OK' : 'BAD') . PHP_EOL;
$tm->remove($telco2Id);
$gone2 = $tm->get($telco2Id);
echo 'TELCOS_CLEANUP:' . (!$gone2 ? 'OK' : 'BAD') . PHP_EOL;

$btype = $dbFixture->fetchOne("SELECT id FROM billing_types LIMIT 1");
$telco3 = $tm->add(['name' => 'task0026m-telco3', 'mobile_price' => 1, 'landline_price' => 1, 'start_time' => 0, 'fract' => 0]);
$billId = $m->add(['area' => 11, 'price' => 1, 'telco' => $telco3, 'billtype' => $btype]);
$bill2Id = $m->add(['area' => 22, 'price' => 2, 'telco' => $telco3, 'billtype' => $btype]);
echo 'BILLING_FIXTURES:' . ((is_int($billId) && is_int($bill2Id)) ? 'OK' : 'BAD') . PHP_EOL;

$ok = $m->update(['id' => $billId, 'area' => 33, 'price' => 3, 'telco' => $telco3, 'billtype' => $btype]);
$row = $m->get($billId);
echo 'BILLING_UPDATE_LEGIT:' . (($ok && $row['area'] == 33) ? 'OK' : 'BAD') . PHP_EOL;

try {
    $m->update(['id' => "foo'bar", 'area' => 1, 'price' => 1, 'telco' => $telco3, 'billtype' => $btype]);
    echo 'BILLING_UPDATE_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'BILLING_UPDATE_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

$before2b = $m->get($bill2Id);
try {
    $m->update(['id' => "0 OR id={$bill2Id}", 'area' => 99, 'price' => 99, 'telco' => $telco3, 'billtype' => $btype]);
} catch (Exception $e) {
}
$after2b = $m->get($bill2Id);
echo 'BILLING_UPDATE_BOOLEAN_ISOLATED:' . (($after2b['area'] == $before2b['area']) ? 'OK' : 'BAD') . PHP_EOL;

try {
    $m->remove("foo'bar");
    echo 'BILLING_REMOVE_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'BILLING_REMOVE_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}
$still2b = $m->get($bill2Id);
echo 'BILLING2_STILL_PRESENT:' . ($still2b ? 'OK' : 'BAD') . PHP_EOL;

$m->remove($billId);
$goneb = $m->get($billId);
echo 'BILLING_REMOVE_LEGIT:' . (!$goneb ? 'OK' : 'BAD') . PHP_EOL;
$m->remove($bill2Id);
$goneb2 = $m->get($bill2Id);
$tm->remove($telco3);
$goneT3 = $tm->get($telco3);
echo 'BILLING_CLEANUP:' . ((!$goneb2 && !$goneT3) ? 'OK' : 'BAD') . PHP_EOL;
PHPEOF
BILLING_OUT="$(run_manager_php_file "$BILLING_PHP")"
rm -f "$BILLING_PHP"
for m in TELCOS_FIXTURES TELCOS_UPDATE_LEGIT TELCOS_UPDATE_APOSTROPHE TELCOS_UPDATE_BOOLEAN_ISOLATED TELCOS_REMOVE_APOSTROPHE TELCOS2_STILL_PRESENT TELCOS_REMOVE_LEGIT TELCOS_CLEANUP BILLING_FIXTURES BILLING_UPDATE_LEGIT BILLING_UPDATE_APOSTROPHE BILLING_UPDATE_BOOLEAN_ISOLATED BILLING_REMOVE_APOSTROPHE BILLING2_STILL_PRESENT BILLING_REMOVE_LEGIT BILLING_CLEANUP; do
    assert_marker "Billing/Telcos: ${m}" "$m" "$BILLING_OUT"
done

FATALS_AFTER_M="$(fatal_count)"
if [ "$FATALS_AFTER_M" = "$FATALS_BEFORE_M" ]; then
    harness_ok "TASK-0026M: application remained healthy" "PHP Fatal Error count unchanged (${FATALS_BEFORE_M})"
else
    harness_bad "TASK-0026M: application remained healthy" "PHP Fatal Error count changed: ${FATALS_BEFORE_M} -> ${FATALS_AFTER_M}"
fi

# =============================================================================
# TASK-0026N -- PBX Rules and Simulator SQL boundary closure
# =============================================================================
#
# Closes the four confirmed SQL-injection sinks TASK-0026M's own Phase 9
# final sweep discovered but explicitly left unfixed
# (docs/tasks/0026m-manager-layer-residual-sql-closure.md, "Security
# handoff"), plus every sibling method in the same three classes sharing
# the exact same raw-interpolation root cause:
#
#   N1/N2 -- PBX_Rule::checkExpr()'s 'CG'/'G' cases -- reachable via
#     SimulatorController::indexAction() (default_simulator is on the
#     authenticated-open allowlist -- ANY logged-in account, no specific
#     permission grant needed).
#   N3   -- PBX_Usuarios::hasExtenGroup() -- reached from the same 'G'
#     case above.
#   N4   -- PBX_Rules::delete() -- reachable via
#     RouteController::removeAction() (default_route_write).
#
# Sibling audit additionally found and fixed:
#   - PBX_Rule::getValidAliasDateById() (unquoted "n.id = $id") --
#     second-order: RouteController's own datesValue POST field is
#     persisted into regras_negocio.dates_alias with zero validation,
#     then re-enters this unquoted numeric-context SQL whenever
#     PBX_Dialplan_Verbose::parse() (the Simulator's own rule-matching
#     engine) evaluates isValidAliasTime() on that rule.
#   - PBX_Usuarios::get() -- was "protected" only by a fragile,
#     CLAUDE.md-forbidden str_replace("'", "\'", ...) escape (confirmed
#     currently effective under this project's actual MariaDB
#     sql_mode/charset, per TASK-0026M's own live verification, but
#     replaced here with proper parameterization for defense in depth).
#   - PBX_Rules::get() (3 statements) / PBX_Rules::update() (2
#     statements) -- reachable via RouteController::toogleAction()
#     (route/toogle, POST, no equivalent unrelated-bug block) and
#     RouteFormController::get_rule_actions() (the route editor's own
#     AJAX action-list endpoint), both feeding a raw route/rule id
#     straight into get()'s/update()'s WHERE clauses.
#
# Pre-existing, unrelated PHP 8.4/strict-SQL-mode bugs discovered while
# reconstructing these boundaries (documented in
# docs/tasks/0026n-pbx-rule-sql-closure.md, not fixed here per CLAUDE.md's
# "do not fix unrelated legacy bugs opportunistically"):
#   - RouteController::editAction()/duplicateAction() both call the
#     PHP-7-removed mysql_escape_string() unconditionally before any
#     Manager call -- every request to either action (GET or POST) fatals
#     immediately, the same bug CLASS TASK-0026L documented for
#     PickupGroupsController::removeAction(). PBX_Rules::get()'s own fix
#     is still exercised and proven live via route/toogle instead (no
#     equivalent block on that action).
#   - PBX_Rules::update()'s own "record" field carries $rule->isRecording()
#     (a PHP bool) uncast -- PDO binds `false` as '' which strict MariaDB
#     rejects for this NOT NULL int column, the exact bug class TASK-0015
#     already fixed for register() but never extended to update(). Every
#     real toogleAction() call past get() hits this; update()'s own SQL
#     fix is instead verified via direct invocation with $rule->record()
#     called first (stringifies to '1', routes around the unrelated bug),
#     matching this program's established precedent.
#
# Every payload below is a harmless, non-destructive, syntax-shaped
# string or boolean-oracle value applied only to fixtures this script
# owns -- never a real exploit chain, never password/hash/schema
# extraction.

log "==> TASK-0026N: PBX_Rule/PBX_Usuarios/PBX_Rules boundary"

FATALS_BEFORE_N="$(fatal_count)"

# --- Real-HTTP core proof -------------------------------------------------

manager_check "PBX_Rules::delete(): apostrophe-shaped remove id causes no SQL error" \
    /index.php/default/route/remove "id=foo'bar" "snep_csrf_token=${RESTRICTED_CSRF}"

# route/toogle's apostrophe-shaped id throws PBX_Exception_NotFound cleanly
# inside get() -- it never reaches update(), so this specific payload does
# NOT hit the unrelated "record" bug documented above; a real SQLSTATE
# 42000 syntax error is the only FAIL signature.
code="$(post_fields "$RESTRICTED_JAR" /index.php/default/route/toogle "route=foo'bar" "snep_csrf_token=${RESTRICTED_CSRF}")"
TAIL_N="$(app_exec 'tail -c 2000 /var/log/apache2/mag-error.log 2>/dev/null')"
if ! echo "$TAIL_N" | grep -qi "SQLSTATE\[42000\]\|syntax error"; then
    harness_ok "PBX_Rules::get(): apostrophe-shaped route/toogle id causes no SQL error" "HTTP $code, no SQL syntax error (clean NotFound)"
else
    harness_bad "PBX_Rules::get(): apostrophe-shaped route/toogle id causes no SQL error" "HTTP $code, log tail: $(echo "$TAIL_N" | tr '\n' ' ' | tail -c 300)"
fi

# Simulator: apostrophe-shaped caller against a real CG-type business rule
# causes no SQL error -- the core checkExpr('CG') proof, driven through
# the real, authenticated HTTP flow. Fixture created/removed via direct
# PBX_Rules::register()/delete() (the real addAction() HTTP flow adds
# unrelated form-validation complexity not needed here).
SIM_FIXTURE_PHP="$(mktemp)"
cat > "$SIM_FIXTURE_PHP" <<'PHPEOF'
$r = new PBX_Rule();
$r->setDesc('task0026n-http-cg-rule');
$r->setPriority(999);
$r->setTypeRule('others');
$r->addSrc(['type' => 'CG', 'value' => '1']);
$r->addDst(['type' => 'X', 'value' => '']);
foreach (['sun','mon','tue','wed','thu','fri','sat'] as $d) { $r->addWeekDay($d); }
$r->addValidTime('00:00-23:59');
$r->record();
PBX_Rules::register($r);
echo 'SIM_FIXTURE_ID:' . $r->getId() . PHP_EOL;
PHPEOF
SIM_FIXTURE_OUT="$(run_manager_php_file "$SIM_FIXTURE_PHP")"
rm -f "$SIM_FIXTURE_PHP"
SIM_RULE_ID="$(echo "$SIM_FIXTURE_OUT" | grep '^SIM_FIXTURE_ID:' | sed 's/SIM_FIXTURE_ID://' | tr -d '\r')"
if [ -n "$SIM_RULE_ID" ]; then
    harness_ok "Simulator: CG-type business rule fixture created" "rule id=${SIM_RULE_ID}"
else
    harness_blocked "could not create the Simulator CG-type rule fixture -- output: $SIM_FIXTURE_OUT"
fi
cleanup_sim_rule_fixture() {
    [ -n "$SIM_RULE_ID" ] || return 0
    SIM_CLEAN_PHP="$(mktemp)"
    printf 'PBX_Rules::delete(%s);\necho "cleaned";\n' "$SIM_RULE_ID" > "$SIM_CLEAN_PHP"
    run_manager_php_file "$SIM_CLEAN_PHP" | grep -q cleaned
    rm -f "$SIM_CLEAN_PHP"
}
harness_register_cleanup "Simulator CG-type rule fixture (id=${SIM_RULE_ID:-none})" "cleanup_sim_rule_fixture"

manager_check "Simulator: apostrophe-shaped caller (CG case) causes no SQL error" \
    /index.php/default/simulator "srcType=" "caller=foo'bar" "dst=100" "trunk=" "ruleDay=" "snep_csrf_token=${RESTRICTED_CSRF}"

manager_check "Simulator: boolean-shaped caller (CG case) cannot alter result" \
    /index.php/default/simulator "srcType=" "caller=x' OR '1'='1" "dst=100" "trunk=" "ruleDay=" "snep_csrf_token=${RESTRICTED_CSRF}"

cleanup_sim_rule_fixture

# --- Direct-invocation coverage (PBX_Rules::get()/update(), no equivalent
# unrelated HTTP-blocking bug for get(); update()'s own unrelated "record"
# bool-cast bug -- documented above -- is routed around by calling
# $rule->record() on every fixture, matching this program's established
# precedent for verifying a real fix behind an unrelated, pre-existing
# crash). ---

RULES_PHP="$(mktemp)"
cat > "$RULES_PHP" <<'PHPEOF'
$canary = new PBX_Rule();
$canary->setDesc('task0026n-canary');
$canary->setPriority(1);
$canary->setTypeRule('others');
$canary->addSrc(['type' => 'X', 'value' => '']);
$canary->addDst(['type' => 'X', 'value' => '']);
$canary->addWeekDay('mon');
$canary->addValidTime('00:00-23:59');
$canary->record();
PBX_Rules::register($canary);
$canaryId = $canary->getId();

$canary2 = new PBX_Rule();
$canary2->setDesc('task0026n-canary2');
$canary2->setPriority(1);
$canary2->setTypeRule('others');
$canary2->addSrc(['type' => 'X', 'value' => '']);
$canary2->addDst(['type' => 'X', 'value' => '']);
$canary2->addWeekDay('mon');
$canary2->addValidTime('00:00-23:59');
$canary2->record();
PBX_Rules::register($canary2);
$canary2Id = $canary2->getId();

echo 'RULES_FIXTURES:' . (($canaryId && $canary2Id) ? 'OK' : 'BAD') . PHP_EOL;

$fetched = PBX_Rules::get($canaryId);
echo 'RULES_GET_LEGIT:' . (($fetched->getDesc() === 'task0026n-canary') ? 'OK' : 'BAD') . PHP_EOL;

try {
    PBX_Rules::get("foo'bar");
    echo 'RULES_GET_APOSTROPHE:BAD (no exception)' . PHP_EOL;
} catch (PBX_Exception_NotFound $e) {
    echo 'RULES_GET_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'RULES_GET_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

$fetched->setDesc('task0026n-canary-renamed');
PBX_Rules::update($fetched);
$after = PBX_Rules::get($canaryId);
echo 'RULES_UPDATE_LEGIT:' . (($after->getDesc() === 'task0026n-canary-renamed') ? 'OK' : 'BAD') . PHP_EOL;

$before2 = PBX_Rules::get($canary2Id);
try {
    $r = new PBX_Rule();
    $r->setId("foo'bar");
    $r->setDesc('x');
    $r->setPriority(1);
    $r->setTypeRule('others');
    $r->addSrc(['type' => 'X', 'value' => '']);
    $r->addDst(['type' => 'X', 'value' => '']);
    $r->addWeekDay('mon');
    $r->addValidTime('00:00-23:59');
    $r->record();
    PBX_Rules::update($r);
    echo 'RULES_UPDATE_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'RULES_UPDATE_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

$r2 = new PBX_Rule();
$r2->setId("0 OR id={$canary2Id}");
$r2->setDesc('hijacked');
$r2->setPriority(1);
$r2->setTypeRule('others');
$r2->addSrc(['type' => 'X', 'value' => '']);
$r2->addDst(['type' => 'X', 'value' => '']);
$r2->addWeekDay('mon');
$r2->addValidTime('00:00-23:59');
$r2->record();
try {
    PBX_Rules::update($r2);
} catch (Exception $e) {
}
$after2 = PBX_Rules::get($canary2Id);
echo 'RULES_UPDATE_BOOLEAN_ISOLATED:' . (($after2->getDesc() === $before2->getDesc()) ? 'OK' : 'BAD') . PHP_EOL;

PBX_Rules::delete($canaryId);
PBX_Rules::delete($canary2Id);
$gone1 = false;
try { PBX_Rules::get($canaryId); } catch (PBX_Exception_NotFound $e) { $gone1 = true; }
$gone2 = false;
try { PBX_Rules::get($canary2Id); } catch (PBX_Exception_NotFound $e) { $gone2 = true; }
echo 'RULES_CLEANUP:' . (($gone1 && $gone2) ? 'OK' : 'BAD') . PHP_EOL;
PHPEOF
RULES_OUT="$(run_manager_php_file "$RULES_PHP")"
rm -f "$RULES_PHP"
for m in RULES_FIXTURES RULES_GET_LEGIT RULES_GET_APOSTROPHE RULES_UPDATE_LEGIT RULES_UPDATE_APOSTROPHE RULES_UPDATE_BOOLEAN_ISOLATED RULES_CLEANUP; do
    assert_marker "PBX_Rules: ${m}" "$m" "$RULES_OUT"
done

# --- Direct-invocation coverage (checkExpr('CG')/('G'), hasExtenGroup(),
# PBX_Usuarios::get()) ---

CGRULE_PHP="$(mktemp)"
cat > "$CGRULE_PHP" <<'PHPEOF'
$cgRule = new PBX_Rule();
$cgRule->setDesc('task0026n-cg-rule');
$cgRule->setPriority(999);
$cgRule->setTypeRule('others');
$cgRule->addSrc(['type' => 'CG', 'value' => '1']);
$cgRule->addDst(['type' => 'X', 'value' => '']);
foreach (['sun','mon','tue','wed','thu','fri','sat'] as $d) { $cgRule->addWeekDay($d); }
$cgRule->addValidTime('00:00-23:59');
$cgRule->record();
PBX_Rules::register($cgRule);
$cgRuleId = $cgRule->getId();
echo 'CG_RULE_FIXTURE:' . ($cgRuleId ? 'OK' : 'BAD') . PHP_EOL;

$loaded = PBX_Rules::get($cgRuleId);

$legit = $loaded->isValidSrc('5551234');
echo 'CG_LEGIT_NO_MATCH:' . (($legit === false) ? 'OK' : 'BAD') . PHP_EOL;

try {
    $loaded->isValidSrc("foo'bar");
    echo 'CG_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'CG_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

try {
    $r = $loaded->isValidSrc("x' OR '1'='1");
    echo 'CG_BOOLEAN_ISOLATED:' . (($r === false) ? 'OK' : 'BAD') . PHP_EOL;
} catch (Exception $e) {
    echo 'CG_BOOLEAN_ISOLATED:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

PBX_Rules::delete($cgRuleId);

$gRule = new PBX_Rule();
$gRule->setDesc('task0026n-g-rule');
$gRule->setPriority(999);
$gRule->setTypeRule('others');
$gRule->addSrc(['type' => 'G', 'value' => '1']);
$gRule->addDst(['type' => 'X', 'value' => '']);
foreach (['sun','mon','tue','wed','thu','fri','sat'] as $d) { $gRule->addWeekDay($d); }
$gRule->addValidTime('00:00-23:59');
$gRule->record();
PBX_Rules::register($gRule);
$gRuleId = $gRule->getId();
echo 'G_RULE_FIXTURE:' . ($gRuleId ? 'OK' : 'BAD') . PHP_EOL;

$legitG = PBX_Usuarios::hasExtenGroup('1', 'nonexistent-peer');
echo 'G_LEGIT_NO_MATCH:' . ((is_array($legitG) && count($legitG) === 0) ? 'OK' : 'BAD') . PHP_EOL;

try {
    PBX_Usuarios::hasExtenGroup("foo'bar", "baz'qux");
    echo 'G_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'G_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

try {
    $r = PBX_Usuarios::hasExtenGroup("0 OR 1=1", "0 OR 1=1");
    echo 'G_BOOLEAN_ISOLATED:' . ((is_array($r) && count($r) === 0) ? 'OK' : 'BAD') . PHP_EOL;
} catch (Exception $e) {
    echo 'G_BOOLEAN_ISOLATED:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

PBX_Rules::delete($gRuleId);

$dbFixture = Zend_Registry::get('db');
$dbFixture->insert('peers', ['name' => 'task0026n-peer', 'password' => 'x', 'host' => 'dynamic', 'port' => '0', 'defaultuser' => 'task0026n-peer', 'ipaddr' => '', 'regexten' => '', 'setvar' => '', 'peer_type' => 'R', 'trunk' => 'no', 'lastms' => 0, 'canal' => 'MANUAL/x']);

$legitUser = PBX_Usuarios::get('task0026n-peer');
echo 'USUARIOS_GET_LEGIT:' . (($legitUser->getNumero() === 'task0026n-peer') ? 'OK' : 'BAD') . PHP_EOL;

try {
    PBX_Usuarios::get("nonexistent' OR name='task0026n-peer");
    echo 'USUARIOS_GET_BOOLEAN_ISOLATED:BAD (injection matched)' . PHP_EOL;
} catch (PBX_Exception_NotFound $e) {
    echo 'USUARIOS_GET_BOOLEAN_ISOLATED:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'USUARIOS_GET_BOOLEAN_ISOLATED:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

try {
    PBX_Usuarios::get("foo'bar");
    echo 'USUARIOS_GET_APOSTROPHE:BAD (no exception)' . PHP_EOL;
} catch (PBX_Exception_NotFound $e) {
    echo 'USUARIOS_GET_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'USUARIOS_GET_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

$dbFixture->delete('peers', $dbFixture->quoteInto('name = ?', 'task0026n-peer'));
$goneCg = false;
try { PBX_Rules::get($cgRuleId); } catch (PBX_Exception_NotFound $e) { $goneCg = true; }
$goneG = false;
try { PBX_Rules::get($gRuleId); } catch (PBX_Exception_NotFound $e) { $goneG = true; }
echo 'CG_G_CLEANUP:' . (($goneCg && $goneG) ? 'OK' : 'BAD') . PHP_EOL;
PHPEOF
CGRULE_OUT="$(run_manager_php_file "$CGRULE_PHP")"
rm -f "$CGRULE_PHP"
for m in CG_RULE_FIXTURE CG_LEGIT_NO_MATCH CG_APOSTROPHE CG_BOOLEAN_ISOLATED G_RULE_FIXTURE G_LEGIT_NO_MATCH G_APOSTROPHE G_BOOLEAN_ISOLATED USUARIOS_GET_LEGIT USUARIOS_GET_BOOLEAN_ISOLATED USUARIOS_GET_APOSTROPHE CG_G_CLEANUP; do
    assert_marker "PBX_Rule/PBX_Usuarios: ${m}" "$m" "$CGRULE_OUT"
done

FATALS_AFTER_N="$(fatal_count)"
if [ "$FATALS_AFTER_N" = "$FATALS_BEFORE_N" ]; then
    harness_ok "TASK-0026N: application remained healthy" "PHP Fatal Error count unchanged (${FATALS_BEFORE_N})"
else
    harness_bad "TASK-0026N: application remained healthy" "PHP Fatal Error count changed: ${FATALS_BEFORE_N} -> ${FATALS_AFTER_N}"
fi

# =============================================================================
# TASK-0026O -- Route list and user binds SQL boundary closure
# =============================================================================
#
# Closes the two confirmed sinks TASK-0026N's own Phase 8 final sweep
# discovered but explicitly left unfixed (docs/tasks/0026n-pbx-rule-sql-closure.md,
# "Security handoff"):
#
#   O1 -- RouteController::indexAction()'s own inline SQL
#     (`where("type = '$type'")`, raw $_GET['type']) -- regras_negocio.type
#     is a MariaDB enum('incoming','outgoing','others') column, so this is
#     closed with a strict allowlist rather than parameterization alone.
#   O2/O3 -- Snep_Binds_Manager::removeBond()/removeBondException()
#     (`delete(..., "user_id = '$id'")`) -- reachable via
#     UsersController::removeAction() (route id) and ::bondAction() (POST
#     id).
#
# Sibling audit additionally found and fixed removeBondByPeer() (identical
# pattern) -- reachable via ExtensionsController::removeAction()'s raw,
# unvalidated $_POST['id'] (Snep_Extensions_Manager::getPeer() returns
# false, not an exception, for a non-matching id, so execution still
# reaches removeBondByPeer() with the raw value).
#
# Discovered while reconstructing the route boundary, documented in
# docs/tasks/0026o-route-binds-sql-closure.md, not itself an SQL defect:
# RouteController::indexAction() and UsersController's remove/bond actions
# both require a distinct "_read"-suffixed permission for the index action
# specifically ("write" alone is not enough for the GET list page) --
# Snep_Modules::loadResources() synthesizes this "read" entry
# automatically for every resource, even ones whose resources.xml only
# ever declares a "write" child, and the permission-management UI shows
# both checkboxes under the exact same visible label (a pre-existing
# UsersController::permissionAction() quirk that copies the "read" label
# onto "write"'s empty one) -- easy for an admin to miss when granting
# access. This preflight now grants default_route_read=1 alongside
# default_route_write=1 for that reason; not fixed, since it is an
# authorization UX ambiguity, not an SQL-injection defect.
log "==> TASK-0026O: RouteController::indexAction() type boundary"

FATALS_BEFORE_O="$(fatal_count)"

# --- O1: RouteController::indexAction() -----------------------------------

code="$(request "$RESTRICTED_JAR" GET /index.php/default/route)"
if [ "$code" = 200 ] && grep -q 'var controller = "route"' "$BODY"; then
    harness_ok "RouteController: legitimate route list works" "HTTP $code"
else
    harness_bad "RouteController: legitimate route list works" "HTTP $code"
fi

code="$(request "$RESTRICTED_JAR" GET "/index.php/default/route?type=incoming")"
if [ "$code" = 200 ] && grep -q 'var controller = "route"' "$BODY"; then
    harness_ok "RouteController: legitimate supported type=incoming works" "HTTP $code"
else
    harness_bad "RouteController: legitimate supported type=incoming works" "HTTP $code"
fi

manager_check_get "RouteController: apostrophe-shaped type causes no SQL error" "/index.php/default/route?type=foo%27bar"

# Canary fixture: a real type=outgoing route with a unique desc marker,
# created directly via PBX_Rules::register() (the real addAction() HTTP
# flow adds unrelated form-validation complexity not needed here, matching
# this program's established fixture-creation precedent).
O_CANARY_PHP="$(mktemp)"
cat > "$O_CANARY_PHP" <<'PHPEOF'
$r = new PBX_Rule();
$r->setDesc('task0026o-canary-route');
$r->setPriority(999);
$r->setTypeRule('outgoing');
$r->addSrc(['type' => 'X', 'value' => '']);
$r->addDst(['type' => 'X', 'value' => '']);
foreach (['sun','mon','tue','wed','thu','fri','sat'] as $d) { $r->addWeekDay($d); }
$r->addValidTime('00:00-23:59');
$r->record();
PBX_Rules::register($r);
echo 'O_CANARY_ID:' . $r->getId() . PHP_EOL;
PHPEOF
O_CANARY_OUT="$(run_manager_php_file "$O_CANARY_PHP")"
rm -f "$O_CANARY_PHP"
O_CANARY_RULE_ID="$(echo "$O_CANARY_OUT" | grep '^O_CANARY_ID:' | sed 's/O_CANARY_ID://' | tr -d '\r')"
if [ -n "$O_CANARY_RULE_ID" ]; then
    harness_ok "RouteController: type=outgoing canary route fixture created" "rule id=${O_CANARY_RULE_ID}"
else
    harness_blocked "could not create the TASK-0026O type=outgoing canary route fixture"
fi
cleanup_o_canary_route() {
    [ -n "$O_CANARY_RULE_ID" ] || return 0
    O_CLEAN_PHP="$(mktemp)"
    printf 'PBX_Rules::delete(%s);\necho "cleaned";\n' "$O_CANARY_RULE_ID" > "$O_CLEAN_PHP"
    run_manager_php_file "$O_CLEAN_PHP" | grep -q cleaned
    rm -f "$O_CLEAN_PHP"
}
harness_register_cleanup "TASK-0026O canary route fixture (id=${O_CANARY_RULE_ID:-none})" "cleanup_o_canary_route"

# Positive control: the canary's own type (outgoing) legitimately shows it.
code="$(request "$RESTRICTED_JAR" GET "/index.php/default/route?type=outgoing")"
if [ "$code" = 200 ] && grep -qF 'task0026o-canary-route' "$BODY"; then
    harness_ok "RouteController: type=outgoing legitimately shows the canary route" "HTTP $code"
else
    harness_bad "RouteController: type=outgoing legitimately shows the canary route" "HTTP $code"
fi

# Negative control: a different legitimate type never shows it.
code="$(request "$RESTRICTED_JAR" GET "/index.php/default/route?type=incoming")"
if [ "$code" = 200 ] && ! grep -qF 'task0026o-canary-route' "$BODY"; then
    harness_ok "RouteController: type=incoming correctly hides the outgoing canary" "HTTP $code"
else
    harness_bad "RouteController: type=incoming correctly hides the outgoing canary" "HTTP $code"
fi

# Core boolean proof: a boolean-shaped, non-allowlisted type cannot bypass
# the filter to leak the canary. Pre-fix, this exact apostrophe-escape
# payload (`where("type = '$type'")`) turns the WHERE clause always-true,
# returning every route regardless of type -- confirmed live during this
# task's own development (see docs/tasks/0026o-route-binds-sql-closure.md).
code="$(request "$RESTRICTED_JAR" GET "/index.php/default/route?type=foo%27%20OR%20%271%27%3D%271")"
if [ "$code" = 200 ] && ! grep -qF 'task0026o-canary-route' "$BODY"; then
    harness_ok "RouteController: boolean-shaped type cannot bypass the type filter" "HTTP $code, canary not leaked"
else
    harness_bad "RouteController: boolean-shaped type cannot bypass the type filter" "HTTP $code"
fi

# Unsupported-but-harmless value: fails safely (no rows, no error),
# matching pre-fix semantics for any value outside the enum domain (no
# regras_negocio row can ever carry a type outside incoming/outgoing/others).
code="$(request "$RESTRICTED_JAR" GET "/index.php/default/route?type=bogus")"
if [ "$code" = 200 ] && ! grep -qF 'task0026o-canary-route' "$BODY"; then
    harness_ok "RouteController: unsupported type value fails safely (no rows, no error)" "HTTP $code"
else
    harness_bad "RouteController: unsupported type value fails safely (no rows, no error)" "HTTP $code"
fi

cleanup_o_canary_route

# --- O2/O3: Snep_Binds_Manager::removeBond()/removeBondException() (plus
# the removeBondByPeer() sibling) -------------------------------------------

log "==> TASK-0026O: Snep_Binds_Manager removeBond()/removeBondException()/removeBondByPeer() boundary"

# Real-HTTP core proof: UsersController::removeAction()'s apostrophe-shaped
# route-param id, exactly as confirmed live pre-fix during this task's own
# development (a genuine SQLSTATE[42000] syntax error).
manager_check "Snep_Binds_Manager::removeBond(): apostrophe-shaped users/remove id causes no SQL error" \
    /index.php/default/users/remove "id=foo'bar" "snep_csrf_token=${RESTRICTED_CSRF}"

# Direct-invocation coverage for the full removeBond()/removeBondException()/
# removeBondByPeer() boundary, including cross-user boolean isolation (a
# `core_binds`/`core_binds_exceptions` row FK-requires a real `users`/`peers`
# row, so this is exercised directly rather than through the two
# unrelated-bug-free but harder-to-fixture HTTP flows).
BINDS_PHP="$(mktemp)"
cat > "$BINDS_PHP" <<'PHPEOF'
$db = Zend_Registry::get('db');
$now = date('Y-m-d H:i:s');

$db->insert('users', ['name' => 'task0026o-bind-victim', 'password' => 'x', 'email' => 'task0026o-bind-victim@example.test', 'dashboard' => '', 'profile_id' => 1, 'created' => $now, 'updated' => $now]);
$victimId = $db->lastInsertId();
$db->insert('users', ['name' => 'task0026o-bind-other', 'password' => 'x', 'email' => 'task0026o-bind-other@example.test', 'dashboard' => '', 'profile_id' => 1, 'created' => $now, 'updated' => $now]);
$otherId = $db->lastInsertId();
$db->insert('peers', ['name' => 'task0026o-bind-peer', 'password' => 'x', 'host' => 'dynamic', 'port' => '0', 'defaultuser' => 'task0026o-bind-peer', 'ipaddr' => '', 'regexten' => '', 'setvar' => '', 'peer_type' => 'R', 'trunk' => 'no', 'lastms' => 0, 'canal' => 'MANUAL/x']);

Snep_Binds_Manager::addBond($victimId, 'bound', 'task0026o-bind-peer');
Snep_Binds_Manager::addBondException($victimId, '5551234');
echo 'BINDS_FIXTURE:' . ((count(Snep_Binds_Manager::getBond($victimId)) === 1 && count(Snep_Binds_Manager::getBondException($victimId)) === 1) ? 'OK' : 'BAD') . PHP_EOL;

// removeBond(): apostrophe-shaped id causes no SQL error, never touches the victim
try {
    Snep_Binds_Manager::removeBond("foo'bar");
    echo 'BOND_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'BOND_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}
echo 'BOND_APOSTROPHE_ISOLATED:' . ((count(Snep_Binds_Manager::getBond($victimId)) === 1) ? 'OK' : 'BAD') . PHP_EOL;

// removeBond(): boolean-shaped id (a real apostrophe-escape attempt --
// confirmed live pre-fix during this task's own development to genuinely
// delete the victim's row) cannot remove/select the victim's own row.
$boolId = "0' OR user_id='" . $victimId;
try {
    Snep_Binds_Manager::removeBond($boolId);
} catch (Exception $e) {
    echo 'BOND_BOOLEAN_EXCEPTION:' . $e->getMessage() . PHP_EOL;
}
echo 'BOND_BOOLEAN_ISOLATED:' . ((count(Snep_Binds_Manager::getBond($victimId)) === 1) ? 'OK' : 'BAD') . PHP_EOL;

// removeBondException(): apostrophe-shaped id causes no SQL error, never touches the victim
try {
    Snep_Binds_Manager::removeBondException("foo'bar");
    echo 'BONDEXC_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'BONDEXC_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}
echo 'BONDEXC_APOSTROPHE_ISOLATED:' . ((count(Snep_Binds_Manager::getBondException($victimId)) === 1) ? 'OK' : 'BAD') . PHP_EOL;

// removeBondException(): boolean-shaped id cannot alter target selection
// (same payload shape confirmed live pre-fix to genuinely delete the
// victim's exception row).
try {
    Snep_Binds_Manager::removeBondException($boolId);
} catch (Exception $e) {
    echo 'BONDEXC_BOOLEAN_EXCEPTION:' . $e->getMessage() . PHP_EOL;
}
echo 'BONDEXC_BOOLEAN_ISOLATED:' . ((count(Snep_Binds_Manager::getBondException($victimId)) === 1) ? 'OK' : 'BAD') . PHP_EOL;

// legitimate flow: removing the victim's own binds by their real id actually works
Snep_Binds_Manager::removeBond($victimId);
echo 'BOND_LEGIT_REMOVE:' . ((count(Snep_Binds_Manager::getBond($victimId)) === 0) ? 'OK' : 'BAD') . PHP_EOL;

Snep_Binds_Manager::removeBondException($victimId);
echo 'BONDEXC_LEGIT_REMOVE:' . ((count(Snep_Binds_Manager::getBondException($victimId)) === 0) ? 'OK' : 'BAD') . PHP_EOL;

// removeBondByPeer() sibling (reachable via ExtensionsController::removeAction()'s
// raw $_POST['id'], which still reaches this call even when getPeer() found no
// matching row -- see this section's header comment).
Snep_Binds_Manager::addBond($otherId, 'bound', 'task0026o-bind-peer');
echo 'BYPEER_FIXTURE:' . ((count(Snep_Binds_Manager::getBond($otherId)) === 1) ? 'OK' : 'BAD') . PHP_EOL;

try {
    Snep_Binds_Manager::removeBondByPeer("foo'bar");
    echo 'BYPEER_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'BYPEER_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}
echo 'BYPEER_APOSTROPHE_ISOLATED:' . ((count(Snep_Binds_Manager::getBond($otherId)) === 1) ? 'OK' : 'BAD') . PHP_EOL;

Snep_Binds_Manager::removeBondByPeer('task0026o-bind-peer');
echo 'BYPEER_LEGIT_REMOVE:' . ((count(Snep_Binds_Manager::getBond($otherId)) === 0) ? 'OK' : 'BAD') . PHP_EOL;

// cleanup
$db->delete('core_binds', $db->quoteInto('peer_name = ?', 'task0026o-bind-peer'));
$db->delete('core_binds_exceptions', $db->quoteInto('user_id = ?', $victimId));
$db->delete('peers', $db->quoteInto('name = ?', 'task0026o-bind-peer'));
$db->delete('users', $db->quoteInto('name = ?', 'task0026o-bind-victim'));
$db->delete('users', $db->quoteInto('name = ?', 'task0026o-bind-other'));
echo 'BINDS_CLEANUP:OK' . PHP_EOL;
PHPEOF
BINDS_OUT="$(run_manager_php_file "$BINDS_PHP")"
rm -f "$BINDS_PHP"
for m in BINDS_FIXTURE BOND_APOSTROPHE BOND_APOSTROPHE_ISOLATED BOND_BOOLEAN_ISOLATED BONDEXC_APOSTROPHE BONDEXC_APOSTROPHE_ISOLATED BONDEXC_BOOLEAN_ISOLATED BOND_LEGIT_REMOVE BONDEXC_LEGIT_REMOVE BYPEER_FIXTURE BYPEER_APOSTROPHE BYPEER_APOSTROPHE_ISOLATED BYPEER_LEGIT_REMOVE BINDS_CLEANUP; do
    assert_marker "Snep_Binds_Manager: ${m}" "$m" "$BINDS_OUT"
done
# Best-effort safety net in case the direct-invocation script above aborted
# before reaching its own inline cleanup (e.g. an unexpected fatal) --
# every prior manager-layer TASK-0026x suite section relies on inline
# cleanup alone; this adds an extra guarantee per this task's own explicit
# Phase 5 "Guarantee cleanup" instruction.
harness_register_best_effort_cleanup "TASK-0026O binds fixture safety net" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}' -e \"DELETE FROM core_binds WHERE peer_name='task0026o-bind-peer'; DELETE FROM core_binds_exceptions WHERE user_id IN (SELECT id FROM users WHERE name IN ('task0026o-bind-victim','task0026o-bind-other')); DELETE FROM peers WHERE name='task0026o-bind-peer'; DELETE FROM users WHERE name IN ('task0026o-bind-victim','task0026o-bind-other');\" >/dev/null 2>&1; true"

FATALS_AFTER_O="$(fatal_count)"
if [ "$FATALS_AFTER_O" = "$FATALS_BEFORE_O" ]; then
    harness_ok "TASK-0026O: application remained healthy" "PHP Fatal Error count unchanged (${FATALS_BEFORE_O})"
else
    harness_bad "TASK-0026O: application remained healthy" "PHP Fatal Error count changed: ${FATALS_BEFORE_O} -> ${FATALS_AFTER_O}"
fi

# =============================================================================
# TASK-0026P -- Module Settings SQL boundary closure
# =============================================================================
#
# Closes the one confirmed sink TASK-0026O's own Phase 7 final sweep
# discovered but explicitly left unfixed
# (docs/tasks/0026o-route-binds-sql-closure.md, "Security handoff"):
#
#   P1 -- Snep_ModuleSettings_Manager::getConfig()
#     (`where("config_name = '$module'")`) -- reachable via
#     ModuleSettingsController::indexAction()'s own POST field-NAME
#     parsing (`explode("_x_", $key)`, $key being an arbitrary attacker-
#     chosen field name, not a value). `module-settings` has no "write"
#     child in resources.xml -- only a `default_module-settings_read`
#     grant exists at all, and this task's own live verification
#     confirmed a read-only grant is sufficient to reach the vulnerable
#     POST-driven code path (index/read and the save/write logic share
#     the same indexAction()).
#
# Sibling audit additionally found and fixed:
#   - Snep_ModuleSettings_Manager::get() -- identical
#     `where("config_module = '$module'")` pattern; its two real call
#     sites are not independently confirmed exploitable (one hardcoded
#     literal, one filesystem-config.json-derived), fixed anyway for
#     defense in depth.
#   - Snep_ModuleSettings_Manager::delConfig() -- identical
#     `delete(..., "config_module='{$module}'")` pattern; zero callers
#     anywhere in the tree (DEAD/UNREACHABLE), fixed anyway as an exact-
#     pattern sibling within the same audited class.
#
# A genuine regression was found and corrected during this task's own
# development: Zend_Db_Select::_where() (snep/lib/Zend/Db/Select.php:1004)
# only calls quoteInto() when its $value argument is not null -- naively
# parameterizing via ->where('col = ?', $module) left a raw, unbound '?'
# in the SQL whenever $module was null, which is a REAL, already-existing
# input shape here: any POST field name without "_x_" in it (e.g. the
# request's own snep_csrf_token field, included in $formData on every
# single request since ModuleSettingsController only unsets
# controller/action/module/signup) makes $res[1] undefined, and
# getConfig($res[1]) is called with null. Pre-fix, PHP's own
# null-to-'' string interpolation made this silently safe (matches
# nothing); a naive value-argument fix would have turned this pre-
# existing, already-live edge case into a new HTTP 500 on every real
# module-settings POST. Fixed by pre-building the condition via
# $db->quoteInto() (which has no such null-value quirk) and passing it
# as the already-safe $cond argument instead.
#
# Every payload below is a harmless, non-destructive, syntax-shaped
# string or boolean-oracle value applied only to fixtures this script
# owns -- never a real exploit chain, never password/hash/schema
# extraction.

log "==> TASK-0026P: Snep_ModuleSettings_Manager module-settings boundary"

FATALS_BEFORE_P="$(fatal_count)"

# --- Real-HTTP core proof ---------------------------------------------------

code="$(request "$RESTRICTED_JAR" GET /index.php/default/module-settings)"
if [ "$code" = 200 ] && grep -q 'defaultForm' "$BODY"; then
    harness_ok "ModuleSettings: legitimate page renders (read-only grant)" "HTTP $code"
else
    harness_bad "ModuleSettings: legitimate page renders (read-only grant)" "HTTP $code"
fi

# The severity-defining property: a read-only grant (no "write" resource
# exists at all for this controller) is sufficient to reach the POST-
# driven save/lookup code path, since indexAction() handles both and
# action=='index' always maps to type='read' (Snep_PermissionPlugin).
manager_check "ModuleSettings: read-only grant reaches the POST-driven save path with no SQL error" \
    /index.php/default/module-settings "task0026psmoke_x_authcheck=1" "snep_csrf_token=${RESTRICTED_CSRF}"

# Legitimate save flow: a real (fixture-namespaced, collision-free)
# module/setting pair persists correctly through the real HTTP flow.
post_fields "$RESTRICTED_JAR" /index.php/default/module-settings \
    "task0026psmoke_x_customsetting=task0026p-legit-value" "snep_csrf_token=${RESTRICTED_CSRF}" >/dev/null
LEGIT_SAVED="$(db_query "SELECT config_value FROM core_config WHERE config_module='task0026psmoke' AND config_name='customsetting';")"
if [ "$LEGIT_SAVED" = "task0026p-legit-value" ]; then
    harness_ok "ModuleSettings: legitimate save flow persists correctly" "config_value='${LEGIT_SAVED}'"
else
    harness_bad "ModuleSettings: legitimate save flow persists correctly" "got config_value='${LEGIT_SAVED}'"
fi
harness_register_cleanup "TASK-0026P module-settings legitimate-save fixture" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}' -e \"DELETE FROM core_config WHERE config_module='task0026psmoke';\" >/dev/null"

# P1 core proof: apostrophe-shaped field NAME (not value) causes no SQL
# error -- exactly the payload confirmed live during this task's own
# reconstruction to produce a genuine SQLSTATE[42000] pre-fix.
manager_check "Snep_ModuleSettings_Manager::getConfig(): apostrophe-shaped field name causes no SQL error" \
    /index.php/default/module-settings "default_x_foo'bar=someval" "snep_csrf_token=${RESTRICTED_CSRF}"

# Malformed field-name structure (no "_x_" separator at all -- the exact
# shape the request's own snep_csrf_token field already carries on every
# request) fails safely, not just for this one extra field.
manager_check "ModuleSettings: malformed field-name structure (no _x_ separator) fails safely" \
    /index.php/default/module-settings "malformedfieldnoseparator=someval" "snep_csrf_token=${RESTRICTED_CSRF}"

# --- Direct-invocation coverage: boolean isolation, siblings, edge cases ---

MODSETTINGS_PHP="$(mktemp)"
cat > "$MODSETTINGS_PHP" <<'PHPEOF'
$db = Zend_Registry::get('db');
$db->insert('core_config', ['config_module' => 'task0026p-victim-module', 'config_name' => 'task0026p-victim-setting', 'config_value' => 'victim-secret-value']);
echo 'VICTIM_FIXTURE:OK' . PHP_EOL;

$legit = Snep_ModuleSettings_Manager::getConfig('task0026p-victim-setting');
echo 'GETCONFIG_LEGIT:' . ((is_array($legit) && ($legit['config_value'] ?? null) === 'victim-secret-value') ? 'OK' : 'BAD') . PHP_EOL;

$legitGet = Snep_ModuleSettings_Manager::get('task0026p-victim-module');
echo 'GET_LEGIT:' . ((is_array($legitGet) && count($legitGet) === 1 && $legitGet[0]['config_value'] === 'victim-secret-value') ? 'OK' : 'BAD') . PHP_EOL;

try {
    Snep_ModuleSettings_Manager::getConfig("foo'bar");
    echo 'GETCONFIG_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'GETCONFIG_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}
try {
    Snep_ModuleSettings_Manager::get("foo'bar");
    echo 'GET_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'GET_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

// boolean-shaped (real apostrophe-escape attempt -- confirmed live
// pre-fix during this task's own development to genuinely cross-match
// the victim row) cannot alter target selection.
$boolPayload = "nonexistent' OR config_name='task0026p-victim-setting";
try {
    $r = Snep_ModuleSettings_Manager::getConfig($boolPayload);
    echo 'GETCONFIG_BOOLEAN_ISOLATED:' . (($r === false) ? 'OK' : 'BAD') . PHP_EOL;
} catch (Exception $e) {
    echo 'GETCONFIG_BOOLEAN_ISOLATED:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}
$boolPayloadModule = "nonexistent' OR config_module='task0026p-victim-module";
try {
    $r = Snep_ModuleSettings_Manager::get($boolPayloadModule);
    echo 'GET_BOOLEAN_ISOLATED:' . ((is_array($r) && count($r) === 0) ? 'OK' : 'BAD') . PHP_EOL;
} catch (Exception $e) {
    echo 'GET_BOOLEAN_ISOLATED:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

// malformed (null) field -- the exact edge case the Zend_Db_Select
// null-value regression above was found and fixed for -- fails safely.
try {
    $r = Snep_ModuleSettings_Manager::getConfig(null);
    echo 'GETCONFIG_NULL:' . (($r === false) ? 'OK' : 'BAD') . PHP_EOL;
} catch (Exception $e) {
    echo 'GETCONFIG_NULL:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}

// unsupported/nonexistent setting behaves normally
$r = Snep_ModuleSettings_Manager::getConfig('task0026p-nonexistent-setting');
echo 'GETCONFIG_NONEXISTENT:' . (($r === false) ? 'OK' : 'BAD') . PHP_EOL;

// delConfig() sibling -- apostrophe-shaped, no error, victim untouched
try {
    Snep_ModuleSettings_Manager::delConfig("foo'bar");
    echo 'DELCONFIG_APOSTROPHE:OK' . PHP_EOL;
} catch (Exception $e) {
    echo 'DELCONFIG_APOSTROPHE:EXCEPTION:' . $e->getMessage() . PHP_EOL;
}
$stillThere = Snep_ModuleSettings_Manager::getConfig('task0026p-victim-setting');
echo 'DELCONFIG_APOSTROPHE_ISOLATED:' . ((is_array($stillThere) && ($stillThere['config_value'] ?? null) === 'victim-secret-value') ? 'OK' : 'BAD') . PHP_EOL;

// legitimate delConfig() removal
Snep_ModuleSettings_Manager::delConfig('task0026p-victim-module');
$gone = Snep_ModuleSettings_Manager::getConfig('task0026p-victim-setting');
echo 'DELCONFIG_LEGIT:' . (($gone === false) ? 'OK' : 'BAD') . PHP_EOL;

echo 'MODSETTINGS_CLEANUP:OK' . PHP_EOL;
PHPEOF
MODSETTINGS_OUT="$(run_manager_php_file "$MODSETTINGS_PHP")"
rm -f "$MODSETTINGS_PHP"
for m in VICTIM_FIXTURE GETCONFIG_LEGIT GET_LEGIT GETCONFIG_APOSTROPHE GET_APOSTROPHE GETCONFIG_BOOLEAN_ISOLATED GET_BOOLEAN_ISOLATED GETCONFIG_NULL GETCONFIG_NONEXISTENT DELCONFIG_APOSTROPHE DELCONFIG_APOSTROPHE_ISOLATED DELCONFIG_LEGIT MODSETTINGS_CLEANUP; do
    assert_marker "Snep_ModuleSettings_Manager: ${m}" "$m" "$MODSETTINGS_OUT"
done
# Best-effort safety net in case the direct-invocation script above
# aborted before reaching its own inline cleanup, per this task's own
# explicit "Guarantee cleanup" instruction.
harness_register_best_effort_cleanup "TASK-0026P module-settings direct-invocation fixture safety net" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}' -e \"DELETE FROM core_config WHERE config_module IN ('task0026p-victim-module','task0026psmoke');\" >/dev/null 2>&1; true"

FATALS_AFTER_P="$(fatal_count)"
if [ "$FATALS_AFTER_P" = "$FATALS_BEFORE_P" ]; then
    harness_ok "TASK-0026P: application remained healthy" "PHP Fatal Error count unchanged (${FATALS_BEFORE_P})"
else
    harness_bad "TASK-0026P: application remained healthy" "PHP Fatal Error count changed: ${FATALS_BEFORE_P} -> ${FATALS_AFTER_P}"
fi

harness_complete
