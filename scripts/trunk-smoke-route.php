<?php
/**
 * TASK-0015: creates/removes the outbound route fixture make
 * trunk-smoke needs, through SENMA's own PBX_Rule/PBX_Rules domain API
 * (the same objects RouteController::addAction()/removeAction()
 * themselves build from a parsed POST) rather than a raw SQL insert.
 *
 * Not exposed as a web action: RouteController's own add/edit flow is a
 * dynamic, JS-driven multi-widget form whose POST contract
 * (actions_order, action_<n>[...] nested per-action config, built
 * client-side) is impractical to reverse-engineer reliably for a test
 * fixture -- see docs/tasks/0015-pjsip-trunk-provisioning.md for why
 * this is the highest-level stable interface used instead of a raw
 * INSERT, matching TASK-0011/TASK-0015A's own precedent of using a
 * real, stable, non-HTTP application API when the HTTP form itself is
 * impractical to drive directly.
 *
 * Usage:
 *   php trunk-smoke-route.php create <trunk_id> <destination> <desc>
 *   php trunk-smoke-route.php remove <rule_id>
 */

define('APPLICATION_PATH', '/var/www/html/snep');
set_include_path(implode(PATH_SEPARATOR, array(
    APPLICATION_PATH . '/lib',
    get_include_path(),
)));

require_once "Snep/Config.php";
Snep_Config::setConfigFile(APPLICATION_PATH . '/includes/setup.conf');
$config = Snep_Config::getConfig();

require_once "Zend/Registry.php";
Zend_Registry::set("config", $config);

require_once "Snep/Db.php";
Zend_Registry::set("db", Snep_Db::getInstance());

require_once "PBX/Rule/Action.php";
require_once "PBX/Rule/Plugin.php";
require_once "PBX/Rule/Plugin/Broker.php";
require_once "PBX/Rule.php";
require_once "PBX/Rules.php";
require_once "PBX/Trunks.php";
require_once APPLICATION_PATH . "/modules/default/actions/DiscarTronco.php";

// DiscarTronco::getName()/getDesc() call $this->i18n->translate() --
// needs a translator present in the registry even though this script
// never renders a UI.
require_once "Snep/Locale.php";
Zend_Registry::set("Zend_Translate", Snep_Locale::getInstance()->getZendTranslate());

require_once "Zend/Log.php";
require_once "Zend/Log/Writer/Null.php";
Zend_Registry::set("log", new Zend_Log(new Zend_Log_Writer_Null()));

$action = isset($argv[1]) ? $argv[1] : null;

if ($action === "create") {
    $trunkId = (int) $argv[2];
    $destination = $argv[3];
    $desc = $argv[4];

    $rule = new PBX_Rule();
    $rule->setDesc($desc);
    $rule->setPriority(10);
    $rule->setTypeRule("outgoing");
    foreach (array("sun", "mon", "tue", "wed", "thu", "fri", "sat") as $day) {
        $rule->addWeekDay($day);
    }
    $rule->addValidTime("00:00:00-23:59:59");
    // X: any origin -- the destination match alone (an exact regex on
    // the reserved test number) is already deterministic/collision-safe
    // (see docker/provider-config/extensions.conf), so no source
    // restriction is needed.
    $rule->addSrc(array("type" => "X", "value" => ""));
    // RX: Asterisk-rule-to-regex exact match (PBX_Rule::astrule2regex()
    // passes a bare literal like "600" through unchanged as ^600$) --
    // not "X" (any destination), which would also swallow real internal
    // extension-to-extension test traffic.
    $rule->addDst(array("type" => "RX", "value" => $destination));

    $tronco = new DiscarTronco();
    $tronco->setConfig(array("tronco" => $trunkId));
    $rule->addAction($tronco);

    PBX_Rules::register($rule);
    echo $rule->getId() . "\n";
} else if ($action === "remove") {
    $ruleId = (int) $argv[2];
    PBX_Rules::delete($ruleId);
    echo "removed\n";
} else {
    fwrite(STDERR, "usage: php trunk-smoke-route.php create <trunk_id> <destination> | remove <rule_id>\n");
    exit(1);
}
