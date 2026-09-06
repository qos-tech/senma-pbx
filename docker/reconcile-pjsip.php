<?php
/**
 * TASK-0033B: operator-facing CLI entrypoint for DB -> PJSIP runtime
 * reconciliation. Invoked via `make reconcile` / `make reconcile-check`
 * (docker compose exec app php /usr/local/bin/reconcile-pjsip.php [--check]).
 *
 * This is a standalone script, same category as docker/bootstrap-admin.php
 * -- not part of the normal HTTP request path. Unlike bootstrap-admin.php
 * (which only needs a raw PDO connection), Snep_Pjsip_Reconciler calls
 * straight into Snep_PjsipConf/Snep_PjsipTrunkConf/Snep_PjsipTransportConf,
 * which assume the same Zend_Registry('config')/autoloader setup every
 * real request already has. This replicates the minimal subset of
 * snep/index.php's own bootstrap needed for that -- config, DB registry,
 * locale (so a translated exception message never itself crashes on a
 * missing translator), module path, and the Snep_/PBX_/Asterisk_
 * autoloader namespaces. Deliberately skips Zend_Application's full MVC
 * bootstrap (front controller, routing, session) -- none of that applies
 * to a CLI invocation with no HTTP request behind it, same reasoning
 * snep/agi/Bootstrap.php already established for AGI scripts.
 *
 * Exit codes:
 *   0 = RECONCILED / IN_SYNC (check mode) -- fully successful
 *   1 = a real failure occurred (see the FAILURE TAXONOMY in
 *       docs/tasks/0033b-pjsip-configuration-reconciliation.md)
 *   2 = RUNTIME_RESTART_REQUIRED / FILES_RECONCILED_RUNTIME_UNAVAILABLE --
 *       files are correct, but the runtime needs separate operator
 *       attention (a restart, or Asterisk simply being down); distinct
 *       from 0 so a scripted caller cannot mistake this for full success,
 *       and distinct from 1 since nothing here indicates a defect
 *   3 = DRIFTED (check mode only) -- no error, but not in sync
 */

defined('APPLICATION_PATH') || define('APPLICATION_PATH', '/var/www/html/snep');

set_include_path(implode(PATH_SEPARATOR, array(
    APPLICATION_PATH . '/lib',
    get_include_path(),
)));

require_once 'Snep/Config.php';

try {
    Snep_Config::setConfigFile(APPLICATION_PATH . '/includes/setup.conf');
} catch (Exception $ex) {
    fwrite(STDERR, "[reconcile-pjsip] could not load setup.conf: " . $ex->getMessage() . "\n");
    exit(1);
}

$config = Snep_Config::getConfig();

require_once 'Snep/Modules.php';
Snep_Modules::getInstance()->addPath($config->system->path->base . '/modules');

require_once 'Zend/Loader/Autoloader.php';
Zend_Loader_Autoloader::getInstance()->registerNamespace(array('Snep_', 'PBX_', 'Asterisk_'));

require_once 'Zend/Registry.php';
Zend_Registry::set('config', $config);

// Best-effort locale/translator setup -- Snep_PjsipConf::reload() etc.
// only ever call $view->translate() on an already-failing path; this
// just ensures that secondary call itself cannot throw a *different*,
// more confusing exception if it does fire.
try {
    require_once 'Snep/Locale.php';
    $locale = Snep_Locale::getInstance();
    Zend_Registry::set('i18n', $locale->getZendTranslate());
} catch (Exception $ex) {
    fwrite(STDERR, "[reconcile-pjsip] warning: locale setup failed (non-fatal): " . $ex->getMessage() . "\n");
}

// Asterisk_AMI::log() (snep/lib/Asterisk/AMI.php, the base class
// PBX_Asterisk_AMI extends) unconditionally calls
// Snep_Logger::getInstance()->log(...) on every AMI event it receives --
// confirmed live during this task's own validation: with zero writers
// attached, Zend_Log itself throws "No writers were added" the first
// time an AMI response actually arrives, which made every reconcile
// run fail as if Asterisk were unreachable when it was not. The full
// Zend_Application MVC bootstrap (a normal HTTP request) attaches a
// writer via its own resource config; this minimal CLI bootstrap must
// do the same. A single stderr writer is enough -- this is a CLI tool,
// not a request with a per-caller log file to write into (contrast
// snep/agi/Bootstrap.php's startLogger(), which needs a real
// agi_callerid/agi_extension-scoped file because AGI runs from live
// call context).
require_once 'Snep/Logger.php';
require_once 'Zend/Log/Writer/Stream.php';
Snep_Logger::getInstance()->addWriter(new Zend_Log_Writer_Stream('php://stderr'));

require_once 'Snep/Pjsip/Reconciler.php';

$checkOnly = in_array('--check', $argv, true);

if ($checkOnly) {
    $result = Snep_Pjsip_Reconciler::check();
    echo "SENMA PJSIP reconciliation -- CHECK\n";
    echo "====================================\n";
    echo "status: {$result['status']}\n";
    if (!empty($result['files'])) {
        echo "files:\n";
        foreach ($result['files'] as $name => $state) {
            echo "  $name: $state\n";
        }
    }
    if (!empty($result['problems'])) {
        echo "problems:\n";
        foreach ($result['problems'] as $p) {
            echo "  - $p\n";
        }
    }
    switch ($result['status']) {
        case Snep_Pjsip_Reconciler::CHECK_IN_SYNC:
            exit(0);
        case Snep_Pjsip_Reconciler::CHECK_DRIFTED:
            exit(3);
        default:
            exit(1);
    }
}

$result = Snep_Pjsip_Reconciler::reconcile();

echo "SENMA PJSIP reconciliation\n";
echo "===========================\n";
echo "status: {$result['status']}\n";

if ($result['db_validation'] && !empty($result['db_validation']['problems'])) {
    echo "db validation problems:\n";
    foreach ($result['db_validation']['problems'] as $p) {
        echo "  - $p\n";
    }
}

if ($result['generation'] && !empty($result['generation']['warnings'])) {
    echo "generation warnings (treated as invalid persisted state for a full reconcile):\n";
    foreach ($result['generation']['warnings'] as $w) {
        echo "  - $w\n";
    }
}

if ($result['staging_validation'] && !empty($result['staging_validation']['problems'])) {
    echo "staged content problems:\n";
    foreach ($result['staging_validation']['problems'] as $p) {
        echo "  - $p\n";
    }
}

if ($result['publish']) {
    echo "files published: " . implode(', ', $result['publish']['files']) . "\n";
    if (!empty($result['publish']['problems'])) {
        foreach ($result['publish']['problems'] as $p) {
            echo "  publish problem: $p\n";
        }
    }
}

if ($result['apply']) {
    echo "runtime apply: res_pjsip=" . ($result['apply']['res_pjsip_reloaded'] ? 'reloaded' : 'FAILED')
        . " http=" . ($result['apply']['http_reloaded'] ? 'reloaded' : 'FAILED') . "\n";
}

if ($result['verification']) {
    echo "runtime verification: " . ($result['verification']['ok'] ? 'OK' : 'FAILED')
        . ($result['verification']['restart_required'] ? ' (restart required for at least one transport)' : '') . "\n";
    if (!empty($result['verification']['problems'])) {
        foreach ($result['verification']['problems'] as $p) {
            echo "  - $p\n";
        }
    }
}

if (!empty($result['external_dependencies'])) {
    echo "external dependencies (pjsip_external -- not managed, not repaired by reconcile):\n";
    foreach ($result['external_dependencies'] as $name => $state) {
        echo "  $name: $state\n";
    }
}

switch ($result['status']) {
    case Snep_Pjsip_Reconciler::RESULT_RECONCILED:
        exit(0);
    case Snep_Pjsip_Reconciler::RESULT_RUNTIME_RESTART_REQUIRED:
    case Snep_Pjsip_Reconciler::RESULT_FILES_RECONCILED_RUNTIME_UNAVAILABLE:
        exit(2);
    default:
        exit(1);
}
