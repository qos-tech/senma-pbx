<?php

/**
 *  This file is part of SNEP.
 *
 *  SNEP is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Lesser General Public License as
 *  published by the Free Software Foundation, either version 3 of
 *  the License, or (at your option) any later version.
 *
 *  SNEP is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Lesser General Public License for more details.
 *
 *  You should have received a copy of the GNU Lesser General Public License
 *  along with SNEP.  If not, see <http://www.gnu.org/licenses/lgpl.txt>.
 */

/**
 * PJSIP transport CRUD (TASK-0018).
 *
 * A focused controller for exactly one concern -- unlike Trunks/
 * Extensions, a transport has no secondary table, no codec/NAT
 * translation, no dial-plan side effects. Create/edit/delete each
 * trigger Snep_PjsipTransportConf::loadConfFromDb() plus (per
 * docs/tasks/0017-pjsip-transports-and-templates-architecture.md §4's
 * cross-generator consistency requirement) the other two generators,
 * since a transport rename changes the `transport=<name>` text they
 * embed.
 *
 * @category  Snep
 * @package   Snep
 */
class PjsipTransportsController extends Zend_Controller_Action {

    /**
     * indexAction - list all transports with usage/status info.
     */
    public function indexAction() {
        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array($this->view->translate("PJSIP Transports")));

        $transports = Snep_PjsipTransports_Manager::getAll();

        // TASK-0020 item 6 / investigation §17: runtime-state visibility
        // derived fresh on every list view -- one `pjsip show transports`
        // call, cross-referenced against enabled/disabled DB rows. Never
        // persisted, never inferred from `enabled` alone (the investigation
        // proved enabled=1 is NOT sufficient proof of an active runtime
        // object -- a collision, or a rename never followed by a restart,
        // both leave an enabled=1 row with no live runtime counterpart).
        $runtimeNames = Snep_PjsipTransportConf::getRuntimeTransportNames();
        foreach ($transports as &$transport) {
            $inRuntime = in_array($transport['name'], $runtimeNames, true);
            if ($transport['enabled']) {
                // enabled and live -> active. enabled but absent from
                // Asterisk's own runtime -> exactly the RESTART REQUIRED/
                // RUNTIME MISMATCH state the investigation's §K/§6/§8
                // findings prove is real and silent otherwise.
                $transport['runtime_state'] = $inRuntime ? 'active' : 'restart_required';
            } else {
                // disabled, but Asterisk still has it loaded -> the
                // proven-real "socket may still be bound" case (§9) --
                // do not claim it is fully gone.
                $transport['runtime_state'] = $inRuntime ? 'restart_required' : 'disabled';
            }
        }
        unset($transport);
        $this->view->transports = $transports;

        // TASK-0020 items 2-4: surface whatever the last create/edit/
        // delete on this page determined (see reportApplyResult()) --
        // FlashMessenger, not a new persistence mechanism (item 21: no
        // schema change). Already-vendored, standard Zend Framework 1
        // action helper (snep/lib/Zend/Controller/Action/Helper/
        // FlashMessenger.php) -- never used elsewhere in this app before,
        // but exactly the framework's own intended tool for a one-shot,
        // post-redirect message, so this is not a new pattern invented
        // for this task.
        $flash = $this->_helper->FlashMessenger;
        $this->view->restart_required_messages = $flash->getMessages('restart_required');
        $this->view->apply_failed_messages = $flash->getMessages('apply_failed');

        // TASK-0019 item 12/§0: disabling a referenced transport is a
        // deliberately allowed admin action (unlike delete), but the
        // resulting invalid state (a dangling transport=<name> reference
        // the generator will now refuse to emit -- see
        // Snep_PjsipConf::resolveTransportName()) must be surfaced
        // clearly, not just logged. Reusing the exact same
        // view->alert_message convention ExtensionsController::indexAction()
        // already uses for its own weak-password warning.
        $staleWarnings = array();
        foreach ($transports as $transport) {
            if (!$transport['enabled'] && $transport['usage_count'] > 0) {
                $staleWarnings[] = $this->view->translate(
                    "Transport %s is disabled but still explicitly referenced by %s object(s). Affected extensions/trunks will NOT be generated until this is fixed.",
                    $transport['name'], $transport['usage_count']
                );
            }
        }
        if (count($staleWarnings) > 0) {
            $this->view->alert_message = implode("<br />\n", $staleWarnings);
        }
        $this->view->url = "{$this->getFrontController()->getBaseUrl()}/{$this->getRequest()->getControllerName()}";

        $config = Zend_Registry::get('config');
        $this->view->lineNumber = $config->ambiente->linelimit;

        $this->view->key = Snep_Dashboard_Manager::getKey(
            Zend_Controller_Front::getInstance()->getRequest()->getModuleName(),
            Zend_Controller_Front::getInstance()->getRequest()->getControllerName(),
            Zend_Controller_Front::getInstance()->getRequest()->getActionName());
    }

    /**
     * addAction - create a transport.
     */
    public function addAction() {
        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
            $this->view->translate("PJSIP Transports"),
            $this->view->translate("Add")));

        $this->view->action = "add";
        $this->view->transport = array(
            'name' => '',
            'protocol' => 'udp',
            'bind_address' => '0.0.0.0',
            'bind_port' => '5060',
            'domain' => '',
            'external_signaling_address' => '',
            'external_signaling_port' => '',
            'external_media_address' => '',
            'symmetric_transport' => 0,
            'allow_reload' => 1,
            'is_default' => 0,
            'enabled' => 1,
        );
        $this->view->networksText = '';

        if ($this->getRequest()->isPost()) {
            $error = $this->validatePost($_POST);
            $this->view->transport = $_POST;
            $this->view->networksText = $_POST['local_net'];

            if ($error === null) {
                $data = $this->buildData($_POST);
                $networks = $this->parseNetworks($_POST['local_net']);

                Snep_PjsipTransports_Manager::create($data, $networks);
                Snep_Audit_Manager::SaveLog("Added", 'pjsip_transports', $data['name'], $this->view->translate("Transport") . " " . $data['name']);

                $this->regenerateAll();
                // TASK-0020: a create has no "before" state to compare
                // against -- never a rename, never a disable transition.
                $this->reportApplyResult(null, $data);
                $this->_redirect("pjsip-transports");
            } else {
                $this->view->error_message = $error;
            }
        }

        $this->renderScript('pjsip-transports/addedit.phtml');
    }

    /**
     * editAction - edit a transport.
     */
    public function editAction() {
        $id = $this->getRequest()->getParam('id');
        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
            $this->view->translate("PJSIP Transports"),
            $this->view->translate("Edit")));

        $transport = Snep_PjsipTransports_Manager::get($id);
        if (!$transport) {
            throw new Zend_Controller_Action_Exception('Page not found.', 404);
        }

        $this->view->action = "edit";
        $this->view->id = $id;
        $this->view->transport = $transport;
        $this->view->networksText = implode("\n", Snep_PjsipTransports_Manager::getNetworks($id));
        $this->view->usageCount = Snep_PjsipTransports_Manager::getUsageCount($id);

        if ($this->getRequest()->isPost()) {
            $error = $this->validatePost($_POST, $id);
            $this->view->transport = $_POST;
            $this->view->networksText = $_POST['local_net'];

            if ($error === null) {
                $data = $this->buildData($_POST);
                $networks = $this->parseNetworks($_POST['local_net']);

                Snep_PjsipTransports_Manager::update($id, $data, $networks);
                Snep_Audit_Manager::SaveLog("Updated", 'pjsip_transports', $id, $this->view->translate("Transport") . " " . $data['name']);

                $this->regenerateAll();
                // TASK-0020: $transport (loaded above, BEFORE this
                // request's own mutation) is the "before" state --
                // needed to detect a rename or an enabled->disabled
                // transition, neither of which the "after" row alone
                // could reveal.
                $this->reportApplyResult($transport, $data);
                $this->_redirect("pjsip-transports");
            } else {
                $this->view->error_message = $error;
            }
        }

        $this->renderScript('pjsip-transports/addedit.phtml');
    }

    /**
     * removeAction - delete a transport. Blocked while any
     * extension/trunk references it (item 9's explicit requirement) --
     * mirrors RouteController::removeAction()'s simple confirm-then-
     * delete shape, plus TrunksController::removeAction()'s
     * "list what's using it" pattern for the blocked case.
     */
    public function removeAction() {
        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
            $this->view->translate("PJSIP Transports"),
            $this->view->translate("Delete")));

        $id = $this->_request->getParam('id');
        $transport = Snep_PjsipTransports_Manager::get($id);
        if (!$transport) {
            throw new Zend_Controller_Action_Exception('Page not found.', 404);
        }

        $usage = Snep_PjsipTransports_Manager::getUsageDetails($id);

        if ($transport['is_default'] && count(Snep_PjsipTransports_Manager::getAll()) > 1) {
            $this->view->error_message = $this->view->translate("Cannot remove the default transport. Mark a different transport as default first.");
            $this->renderScript('error/sneperror.phtml');
            return;
        }

        if (count($usage) > 0) {
            $this->view->error_message = $this->view->translate("Cannot remove. The following objects are using this transport: ") . "<br />";
            foreach ($usage as $ref) {
                $this->view->error_message .= ($ref['type'] === 'extension' ? $this->view->translate("Extension") : $this->view->translate("Trunk")) . " " . $ref['id'] . " - " . $ref['label'] . "<br />\n";
            }
            $this->renderScript('error/sneperror.phtml');
            return;
        }

        $this->view->id = $id;
        $this->view->remove_title = $this->view->translate('Delete Transport.');
        $this->view->remove_message = $this->view->translate('The transport will be deleted. After that, you have no way get it back.');
        $this->view->remove_form = 'pjsip-transports';
        $this->renderScript('remove/remove.phtml');

        if ($this->_request->getPost()) {
            Snep_PjsipTransports_Manager::remove($id);
            Snep_Audit_Manager::SaveLog("Deleted", 'pjsip_transports', $id, $this->view->translate("Transport") . " " . $transport['name']);
            $this->regenerateAll();
            // TASK-0020 item 3 / investigation §8: delete NEVER actually
            // frees the OS socket via a plain reload -- proven live,
            // no exception found (unchanged /proc/net/{udp,tcp} inode
            // before/after; a later transport on the same bind fails
            // with Asterisk's own "Address already in use"). Unlike a
            // rename or a disable, there is no "after" row left to run
            // isRuntimeActive() against, so this is unconditional, exactly
            // like the rename case.
            $flash = $this->_helper->FlashMessenger;
            $flash->setNamespace('restart_required');
            $flash->addMessage($this->view->translate("Transport '%s' removed. Its previous socket may remain reserved until Asterisk is restarted -- until then, the same address/port cannot be reused by another transport.", $transport['name']));
            $this->_redirect("pjsip-transports");
        }
    }

    /**
     * reportApplyResult - TASK-0020 items 2-4: after a create/edit's own
     * regenerateAll() has already run, determine and report which of
     * the three states (docs/tasks/0020-pjsip-transport-runtime-lifecycle.md
     * §1) actually applies -- never let a bare HTTP 302 imply "active"
     * when the investigation proved that's not always true.
     *
     * @param array|false $before the row as it was BEFORE this save
     *                     (false/null for a create -- nothing to compare)
     * @param array       $after  the just-persisted column values
     *                     ($this->buildData()'s output)
     */
    protected function reportApplyResult($before, array $after) {
        $flash = $this->_helper->FlashMessenger;

        $renamed = ($before && $before['name'] !== $after['name']);
        if ($renamed) {
            // TASK-0020 investigation §6: renaming ALWAYS left the
            // transport unreachable under either name until a restart,
            // with zero exceptions found across every attempt -- this is
            // an unconditional rule, not a "maybe," so it is reported
            // unconditionally too.
            $flash->setNamespace('restart_required');
            $flash->addMessage($this->view->translate("Configuration saved. Asterisk restart required for the transport to become active under its new name ('%s').", $after['name']));
            return;
        }

        $wasEnabled = $before ? (bool) $before['enabled'] : false;
        $nowEnabled = (bool) $after['enabled'];
        if ($wasEnabled && !$nowEnabled) {
            // TASK-0020 investigation §9: disabling was proven to behave
            // exactly like delete at the socket level -- the object
            // disappears from Asterisk's own bookkeeping, but the OS
            // socket was proven to stay bound (unchanged /proc/net
            // inode across disable+re-enable). Only fires on the actual
            // transition, not on every save of an already-disabled row
            // (nothing new happened in that case -- see the docblock on
            // the disabled-and-staying-disabled branch below).
            $flash->setNamespace('restart_required');
            $flash->addMessage($this->view->translate("Configuration saved. Transport '%s' is now disabled, but its previous socket may remain in use until Asterisk is restarted.", $after['name']));
            return;
        }

        if (!$nowEnabled) {
            // Created disabled, or edited while already disabled and
            // staying that way (e.g. the seeded wss placeholder) --
            // nothing to verify, this is the expected, intentionally
            // inert state, not a failure of anything.
            return;
        }

        // TASK-0020 item 4: never trust HTTP 302 / config generation /
        // AMI command submission / "reloaded successfully" as proof of
        // anything -- ask Asterisk directly, by name.
        if (Snep_PjsipTransportConf::isRuntimeActive($after['name'], $after['bind_address'], $after['bind_port'])) {
            return; // ACTIVE -- matches the existing, already-correct silent-redirect behavior
        }

        $flash->setNamespace('apply_failed');
        $flash->addMessage($this->view->translate("Configuration saved, but Asterisk could not apply it (the address/port may already be in use by another transport). The previous configuration may still be active."));
    }

    /**
     * validatePost - item 7's field-by-field validation. Returns null
     * when valid, or a translated error string otherwise.
     */
    protected function validatePost(array $post, $editingId = null) {
        if (!Snep_PjsipTransports_Manager::validateName($post['name'])) {
            return $this->view->translate("Transport name must be 1-80 letters, digits, dashes or underscores.");
        }
        $existing = Snep_PjsipTransports_Manager::getByName($post['name']);
        if ($existing && $existing['id'] != $editingId) {
            return $this->view->translate("A transport with this name already exists.");
        }
        if (!Snep_PjsipTransports_Manager::validateProtocol($post['protocol'])) {
            return $this->view->translate("Invalid protocol.");
        }
        if (!Snep_PjsipTransports_Manager::validateIpOrHostname($post['bind_address']) || $post['bind_address'] === '') {
            return $this->view->translate("Invalid bind address.");
        }
        if (!Snep_PjsipTransports_Manager::validatePort($post['bind_port']) || $post['bind_port'] === '') {
            return $this->view->translate("Invalid bind port.");
        }
        // TASK-0020 item 1: server-side is the ONLY authority here (per
        // the task's own explicit instruction) -- reject a collision
        // BEFORE any DB/config mutation, using the exact socket-identity
        // semantics the investigation proved live (protocol-family +
        // exact bind_address + bind_port; checked against every other
        // row regardless of enabled/disabled, since a disabled row's
        // socket was proven to stay silently bound). Never rely on
        // Asterisk's own log as the validation mechanism -- this must
        // catch it before Asterisk ever sees the config.
        $collision = Snep_PjsipTransports_Manager::findCollision($post['protocol'], $post['bind_address'], $post['bind_port'], $editingId);
        if ($collision) {
            return $this->view->translate("This protocol/address/port is already used by transport '%s'. Choose a different bind address, port, or protocol.", $collision['name']);
        }
        if (!Snep_PjsipTransports_Manager::validateIpOrHostname($post['domain'])) {
            return $this->view->translate("Invalid domain.");
        }
        if (!Snep_PjsipTransports_Manager::validateIpOrHostname($post['external_signaling_address'])) {
            return $this->view->translate("Invalid external signaling address.");
        }
        if (!Snep_PjsipTransports_Manager::validatePort($post['external_signaling_port'])) {
            return $this->view->translate("Invalid external signaling port.");
        }
        if (!Snep_PjsipTransports_Manager::validateIpOrHostname($post['external_media_address'])) {
            return $this->view->translate("Invalid external media address.");
        }
        foreach ($this->parseNetworks($post['local_net']) as $network) {
            if (!Snep_PjsipTransports_Manager::validateCidr($network)) {
                // htmlspecialchars(): this message is rendered
                // unescaped by the view (it may contain markup for
                // other error paths, e.g. the usage list in
                // removeAction()) -- $network is raw user input and
                // must not be echoed back verbatim.
                return $this->view->translate("Invalid local network: %s", htmlspecialchars($network, ENT_QUOTES));
            }
        }
        return null;
    }

    /**
     * buildData - $_POST -> pjsip_transports column array. Deliberately
     * an explicit allow-list (never a raw $_POST passthrough) -- item 15:
     * "do not allow raw pjsip.conf injection through any transport
     * field." Every value here is either enum/type-validated above or a
     * plain scalar with no special meaning in Asterisk's config syntax.
     */
    protected function buildData(array $post) {
        return array(
            'name' => $post['name'],
            'protocol' => $post['protocol'],
            'bind_address' => $post['bind_address'],
            'bind_port' => (int) $post['bind_port'],
            'domain' => $post['domain'] !== '' ? $post['domain'] : null,
            'external_signaling_address' => $post['external_signaling_address'] !== '' ? $post['external_signaling_address'] : null,
            'external_signaling_port' => $post['external_signaling_port'] !== '' ? (int) $post['external_signaling_port'] : null,
            'external_media_address' => $post['external_media_address'] !== '' ? $post['external_media_address'] : null,
            'symmetric_transport' => isset($post['symmetric_transport']) ? 1 : 0,
            'allow_reload' => isset($post['allow_reload']) ? 1 : 0,
            'is_default' => isset($post['is_default']) ? 1 : 0,
            'enabled' => isset($post['enabled']) ? 1 : 0,
        );
    }

    protected function parseNetworks($text) {
        $lines = preg_split('/[\r\n]+/', (string) $text);
        $networks = array();
        foreach ($lines as $line) {
            $line = trim($line);
            if ($line !== '') {
                $networks[] = $line;
            }
        }
        return $networks;
    }

    /**
     * regenerateAll - a transport create/edit/delete must regenerate
     * itself AND the extension/trunk generators, since their output text
     * embeds the transport's current name (TASK-0017 §4's cross-generator
     * consistency requirement -- a rename with no re-run would leave
     * stale transport= references in already-generated files).
     */
    protected function regenerateAll() {
        Snep_PjsipTransportConf::loadConfFromDb();
        Snep_PjsipConf::loadConfFromDb();
        Snep_PjsipTrunkConf::loadConfFromDb();
    }

}
