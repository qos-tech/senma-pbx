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

        $this->view->transports = Snep_PjsipTransports_Manager::getAll();
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
            $this->_redirect("pjsip-transports");
        }
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
