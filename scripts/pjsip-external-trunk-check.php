<?php
/**
 * TASK-0028X: small, dedicated bootstrap CLI helper for
 * scripts/pjsip-external-trunk-smoke-test.sh -- the same pattern
 * scripts/trunk-smoke-route.php already established for driving SENMA's
 * real domain API/objects from a bash harness, used here for two direct,
 * non-HTTP, non-log-parsing checks:
 *
 *   dialstring <trunk_id> <destination>
 *     Calls PBX_Trunks::get($id)->getInterface()->getDialStringForDestination($destination)
 *     -- the exact call DiscarTronco::execute() itself makes -- and
 *     prints the resulting dial string. Proves the fixed
 *     PBX_Trunks::get() dispatch produces "PJSIP/<destination>@<endpoint>"
 *     for a pjsip_external trunk, independent of Asterisk log-trace
 *     parsing/timing.
 *
 *   channelowner <channel>
 *     Calls PBX_Interfaces::getChannelOwner($channel) -- the exact
 *     inbound-identification call PBX_Asterisk_AGI_Request itself makes
 *     -- and prints the resolved object's identity. Proves inbound
 *     matching for a pjsip_external trunk row still resolves to the
 *     correct Snep_Trunk after this task's PBX_Trunks::get() change
 *     (getChannelOwner() regexes trunks.id_regex directly from the DB
 *     row and only calls PBX_Trunks::get() once a match is already
 *     found -- this task's fix does not touch that match, only which
 *     interface object is built afterward; see
 *     docs/tasks/0028x-pjsip-external-dialstring-fix.md).
 *
 * Usage:
 *   php pjsip-external-trunk-check.php dialstring <trunk_id> <destination>
 *   php pjsip-external-trunk-check.php channelowner <channel>
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

require_once "PBX/Trunks.php";
require_once "PBX/Interfaces.php";

$action = isset($argv[1]) ? $argv[1] : null;

if ($action === "dialstring") {
    $trunkId = (int) $argv[2];
    $destination = $argv[3];
    $tronco = PBX_Trunks::get($trunkId);
    echo get_class($tronco->getInterface()) . " " . $tronco->getInterface()->getDialStringForDestination($destination) . "\n";
} else if ($action === "channelowner") {
    $channel = $argv[2];
    $owner = PBX_Interfaces::getChannelOwner($channel);
    if ($owner === null) {
        echo "NULL\n";
    } else if ($owner instanceof Snep_Trunk) {
        echo "Snep_Trunk id=" . $owner->getId() . " name=" . $owner->getName() . "\n";
    } else {
        echo get_class($owner) . "\n";
    }
} else {
    fwrite(STDERR, "unknown action: $action\n");
    exit(1);
}
