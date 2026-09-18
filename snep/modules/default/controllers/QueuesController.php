<?php

/**
 *  This file is part of SNEP.
 *
 *  SNEP is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  SNEP is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with SNEP.  If not, see <http://www.gnu.org/licenses/>.
 */

/**
 * Queues Controller
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2014 OpenS Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 */
class QueuesController extends Zend_Controller_Action {

    /**
     * Initial settings of the class
     */

    public function init() {
        $this->view->url = $this->getFrontController()->getBaseUrl() . '/' . $this->getRequest()->getControllerName();

        $this->view->lineNumber = Zend_Registry::get('config')->ambiente->linelimit;

        $this->language = Zend_Registry::get('config')->system->language;
        $this->path_sounds = Zend_Registry::get('config')->system->path->asterisk->sounds."/".$this->language ;


        $sections = new Zend_Config_Ini('/etc/asterisk/snep/snep-musiconhold.conf');
        $_section = array_keys($sections->toArray());
        $this->section = array();
        foreach ($_section as $value) {
            $this->section[$value] = $value;
        }
        $this->strategies = array('ringall' => $this->view->translate('For all agents available (ringall)'),
                        'roundrobin' => $this->view->translate('Search for a available agent (roundrobin)'),
                        'leastrecent' => $this->view->translate('For the agent idle for the most time (leastrecent)'),
                        'random' => $this->view->translate('Randomly (random)'),
                        'fewestcalls' => $this->view->translate('For the agent that answerd less calls (fewestcalls)'),
                        'rrmemory' => $this->view->translate('Equally (rrmemory)'));

        $this->view->baseUrl = Zend_Controller_Front::getInstance()->getBaseUrl();
        $this->view->key = Snep_Dashboard_Manager::getKey(
            Zend_Controller_Front::getInstance()->getRequest()->getModuleName(),
            Zend_Controller_Front::getInstance()->getRequest()->getControllerName(),
            Zend_Controller_Front::getInstance()->getRequest()->getActionName());
    }

    /**
     * indexAction - List all Queues
     */
    public function indexAction() {

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Queues")));

        $db = Zend_Registry::get('db');

        $select = "SELECT `queues`.*,COALESCE(COUNT(uniqueid),0) as members FROM `queues` left join `queue_members` on queues.name = queue_members.queue_name group by queues.name";

        $stmt = $db->query($select);
        $queues = $stmt->fetchAll();
        
        $this->view->queues = $queues;

    }

    /**
     * TASK-0034I-R5: complete ADD-mode default model for addedit.phtml.
     * Empty strings for optional text/sound selects; radio defaults match
     * the historical ADD UI (ringinuse already defaulted to No) plus the
     * same No/no selections for the other radios that previously had no
     * ADD initialization at all.
     *
     * @return array
     */
    protected function defaultQueueFormModel() {
        return array(
            'name' => '',
            'musiconhold' => '',
            'announce' => '',
            'context' => '',
            'timeout' => '',
            'queue_youarenext' => '',
            'queue_thereare' => '',
            'queue_callswaiting' => '',
            'queue_thankyou' => '',
            'announce_frequency' => '',
            'retry' => '',
            'wrapuptime' => '',
            'maxlen' => '',
            'servicelevel' => '',
            'strategy' => '',
            'joinempty' => 'no',
            'leavewhenempty' => '0',
            'reportholdtime' => '0',
            'memberdelay' => '',
            'weight' => '',
            'ringinuse' => '0',
        );
    }

    /**
     * TASK-0034I-R5: build the queues row payload from the request without
     * indexing missing optional POST keys. Radios may be absent when the
     * browser submits an incomplete form; fall back to explicit defaults
     * (ADD) or the existing queue values (EDIT).
     *
     * Empty strings for nullable integer columns are normalized to null
     * so MariaDB strict mode does not reject the INSERT/UPDATE
     * (SQLSTATE 22007 / Incorrect integer value: '').
     *
     * @param string $name
     * @param array|null $defaults
     * @return array
     */
    protected function queuePayloadFromRequest($name, $defaults = null) {
        if (!is_array($defaults)) {
            $defaults = $this->defaultQueueFormModel();
        }
        $req = $this->_request;
        $pick = function ($key) use ($req, $defaults) {
            $fallback = array_key_exists($key, $defaults) ? $defaults[$key] : '';
            return $req->getPost($key, $fallback);
        };

        $dados = array(
            'name' => $name,
            'musiconhold' => $pick('musiconhold'),
            'announce' => $pick('announce'),
            'context' => $pick('context'),
            'timeout' => $pick('timeout'),
            'queue_youarenext' => $pick('queue_youarenext'),
            'queue_thereare' => $pick('queue_thereare'),
            'queue_callswaiting' => $pick('queue_callswaiting'),
            'queue_thankyou' => $pick('queue_thankyou'),
            'announce_frequency' => $pick('announce_frequency'),
            'retry' => $pick('retry'),
            'wrapuptime' => $pick('wrapuptime'),
            'maxlen' => $pick('maxlen'),
            'servicelevel' => $pick('servicelevel'),
            'strategy' => $pick('strategy'),
            'joinempty' => $pick('joinempty'),
            'leavewhenempty' => $pick('leavewhenempty'),
            'reportholdtime' => $pick('reportholdtime'),
            'memberdelay' => $pick('memberdelay'),
            'weight' => $pick('weight'),
            'ringinuse' => $pick('ringinuse'),
        );

        return $this->normalizeQueuePayloadIntegers($dados);
    }

    /**
     * Convert blank form values for nullable int columns to SQL NULL.
     *
     * @param array $dados
     * @return array
     */
    protected function normalizeQueuePayloadIntegers(array $dados) {
        $nullableInts = array(
            'timeout',
            'announce_frequency',
            'retry',
            'wrapuptime',
            'maxlen',
            'servicelevel',
            'memberdelay',
            'weight',
        );
        foreach ($nullableInts as $key) {
            if (!array_key_exists($key, $dados)) {
                continue;
            }
            if ($dados[$key] === '' || $dados[$key] === null) {
                $dados[$key] = null;
            }
        }
        // ringinuse is NOT NULL with default 1 — never persist blank.
        if (!array_key_exists('ringinuse', $dados) || $dados['ringinuse'] === '' || $dados['ringinuse'] === null) {
            $dados['ringinuse'] = '0';
        }
        // reportholdtime is tinyint nullable — blank → null
        if (array_key_exists('reportholdtime', $dados) && $dados['reportholdtime'] === '') {
            $dados['reportholdtime'] = null;
        }
        return $dados;
    }

    /**
     * Apply radio "checked" view flags from a queue row / default model.
     *
     * @param array $queue
     */
    protected function applyQueueRadioViewFlags(array $queue) {
        $this->view->joinempty_yes = '';
        $this->view->joinempty_no = '';
        $this->view->joinempty_strict = '';
        if (isset($queue['joinempty']) && $queue['joinempty'] === 'yes') {
            $this->view->joinempty_yes = 'checked';
        } elseif (isset($queue['joinempty']) && $queue['joinempty'] === 'no') {
            $this->view->joinempty_no = 'checked';
        } else {
            $this->view->joinempty_strict = 'checked';
        }

        if (isset($queue['leavewhenempty']) && (string) $queue['leavewhenempty'] === '1') {
            $this->view->leavewhenemptyTrue = 'checked';
            $this->view->leavewhenemptyFalse = '';
        } else {
            $this->view->leavewhenemptyTrue = '';
            $this->view->leavewhenemptyFalse = 'checked';
        }

        if (isset($queue['ringinuse']) && (string) $queue['ringinuse'] === '1') {
            $this->view->ringinuseTrue = 'checked';
            $this->view->ringinuseFalse = '';
        } else {
            $this->view->ringinuseTrue = '';
            $this->view->ringinuseFalse = 'checked';
        }

        if (isset($queue['reportholdtime']) && (string) $queue['reportholdtime'] === '1') {
            $this->view->reportholdtimeTrue = 'checked';
            $this->view->reportholdtimeFalse = '';
        } else {
            $this->view->reportholdtimeTrue = '';
            $this->view->reportholdtimeFalse = 'checked';
        }
    }

    /**
     *  AddAction - Add Queue
     */
    public function addAction() {

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Queues"),
                    $this->view->translate("Add Queues")));


        // PHP 8 compatibility: getSounds() uses $this internally, so it
        // must be called on an instance (TASK-0002 P1-B). See
        // docs/tasks/0002-php84-compatibility-baseline.md.
        $this->view->sounds = (new Snep_SoundFiles_Manager())->getSounds(true);

        // Music on Hold available
        $musiconhold = "";
        foreach($this->section as $key => $session){
            $musiconhold .= "<option value='".$key . "'>".$session." </option>\n";
        }
        $this->view->musiconhold = $musiconhold;

        // Queue Stratgies available
        $strategy = "";
        foreach($this->strategies as $key => $strateg){
            $strategy .=  "<option value='".$key . "'>".$strateg." </option>\n";

        }
        $this->view->strategy = $strategy;

        // After POST — process before rendering so a successful create
        // redirects without re-rendering the empty ADD form, and so
        // optional POST keys are never read via bare $_POST[...] .
        if ($this->_request->getPost()) {

            $name = (string) $this->_request->getPost('name', '');
            $dados = $this->queuePayloadFromRequest($name);

            // getName(): false = not found (allow); array = duplicate (reject).
            // Do not count(); false is not Countable under PHP 8.
            $existing = Snep_Queues_Manager::getName($name);

            if ($existing !== false) {
                $message = $this->view->translate("Name already exists.");
                $this->_helper->redirector('sneperror','error',null,array('error_message'=>$message));
                return;
            }

            $id = Snep_Queues_Manager::add($dados);

            //audit
            Snep_Audit_Manager::SaveLog("Added", 'queues', $id, $this->view->translate("Queues") . " " . $name);

            $this->_redirect($this->getRequest()->getControllerName());
            return;
        }

        // ADD GET: explicit default model + radio selections (TASK-0034I-R5).
        $defaults = $this->defaultQueueFormModel();
        $this->view->queue = $defaults;
        $this->applyQueueRadioViewFlags($defaults);
        $this->view->disabled = '';

        //Define the action and others and load form
        $this->view->action = "add" ;
        $this->renderScript( $this->getRequest()->getControllerName().'/addedit.phtml' );

    }

    /**
     * editAction - Edit Queues
     */
    public function editAction() {

        $db = Zend_Registry::get('db');
        $id = $this->_request->getParam("id");

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Queues"),
                    $this->view->translate("Edit")));

        $queue = Snep_Queues_Manager::get($id);

        // PHP 8 compatibility: getSounds() uses $this internally, so it
        // must be called on an instance (TASK-0002 P1-B). See
        // docs/tasks/0002-php84-compatibility-baseline.md.
        $this->view->sounds = (new Snep_SoundFiles_Manager())->getSounds(true);

        if ($queue === false || !is_array($queue)) {
            $message = $this->view->translate("Queue not found.");
            $this->_helper->redirector('sneperror', 'error', null, array('error_message' => $message));
            return;
        }

        // After POST — same optional-field hardening as addAction.
        if ($this->_request->getPost()) {

            $dados = $this->queuePayloadFromRequest($queue['name'], $queue);

            Snep_Queues_Manager::edit($dados);

            //audit (use the looked-up queue id; edit payload has no id key)
            Snep_Audit_Manager::SaveLog("Updated", 'queues', $queue['id'], $this->view->translate("Queue") . " " . $queue['name']);

            $this->_redirect($this->getRequest()->getControllerName());
            return;
        }

        $this->view->queue = $queue;

        // Music On Hold available x registered
        $musiconhold = "";
        foreach($this->section as $key => $session){
            $musiconhold .= ($key == $queue['musiconhold']) ? "<option value='".$key . "' selected >".$session." </option>\n": "<option value='".$key . "'>".$session." </option>\n";
        }

        $this->view->musiconhold = $musiconhold;

        // Queue strategy available x registered
        $strategy = "";
        foreach($this->strategies as $key => $strateg){
            $strategy .= ($key == $queue['strategy']) ? "<option value='".$key . "' selected >".$strateg." </option>\n": "<option value='".$key . "'>".$strateg." </option>\n";
        }

        $this->view->strategy = $strategy;

        $this->applyQueueRadioViewFlags($queue);

        //Define the action and load form
        $this->view->action = "edit" ;
        $this->view->disabled = "disabled";

        $this->renderScript( $this->getRequest()->getControllerName().'/addedit.phtml' );

    }

    /**
     * removeAction - Remove a queue
     */
    public function removeAction() {

         $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Queue"),
                    $this->view->translate("Delete")));

        $id = $this->_request->getParam('id');

        // check if the queues is used in the rule or have members
        $exten_members = Snep_Queues_Manager::getValidationPeers($id);
        $agent_members = Snep_Queues_Manager::getValidationAgent($id);
        $info = Snep_Queues_Manager::get($id);

        if (count($exten_members) > 0 || count($agent_members) > 0) {
            $msg = $this->view->translate("The following members make use of this queue, remove before deleting:") . "<br />\n";

            if (count($exten_members) > 0) {

                foreach ($exten_members as $membros) {
                    $member = explode("/", $membros['membername']);
                    $member = $member[1];
                    $msg .= $this->view->translate("Extension:") . $member . "<br/>\n";
                }
            }

            if (count($agent_members) > 0) {

                foreach ($agent_members as $member_agent) {
                    $msg .= $this->view->translate("Agent:") . $member_agent['agent_id'] . "<br/>\n";
                }
            }
            $error = true;
            $this->view->error_message = $msg;
            $this->renderScript('error/sneperror.phtml');
        }

        $regras = Snep_Queues_Manager::getValidation($id);
        if (count($regras) > 0) {
            $error = true;
            $this->view->error_message = $this->view->translate("Cannot remove. The following routes are using this queues: ") . "<br />";
            foreach ($regras as $regra) {

                $this->view->error_message .= $regra['id'] . " - " . $regra['desc'] . "<br />\n";
            }
            $this->renderScript('error/sneperror.phtml');

        } elseif(!$error) {

            $this->view->id = $id;
            $this->view->name = $info['id'];
            $this->view->remove_title = $this->view->translate('Delete Queue.');
            $this->view->remove_message = $this->view->translate('The queue will be deleted. After that, you have no way get it back.');
            $this->view->remove_form = 'queues';
            $this->renderScript('remove/remove.phtml');

            if ($this->_request->getPost()) {
                
                $queue = Snep_Queues_Manager::get($_POST['id']);
                
                Snep_Queues_Manager::removeUserPermission($_POST['name']);
                Snep_Queues_Manager::removeQueuePeers($_POST['id']);
                Snep_Queues_Manager::remove($_POST['id']);
                Snep_Queues_Manager::removeQueues($_POST['id']);

                 
                

                //audit
                Snep_Audit_Manager::SaveLog("Deleted", 'queues', $id, $this->view->translate("Queues") . " " . $queue['name']);

                $this->_redirect($this->getRequest()->getControllerName());
            }
        }
    }

    /**
     * membersAction - Set member queue
     */
    public function membersAction() {

        $queue = $this->_request->getParam("id");

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Queues"),
                    $this->view->translate("Members")));

        $members = Snep_Queues_Manager::getMembers($queue);
        $mem = array();
        foreach ($members as $m) {
            $mem[$m['interface']] = $m['interface'];
        }

        $_allMembers = Snep_Queues_Manager::getAllMembers();
        $notMem = array();
        foreach ($_allMembers as $row) {
            $cd = explode(";", $row['canal']);
            foreach ($cd as $canal) {
                if (strlen($canal) > 0) {
                    if (!array_key_exists($canal, $mem)) {
                        $notMem[$canal] = $row['callerid'] . " ($canal)";
                    }
                }
            }
        }

        $this->view->notMembers = $notMem;
        $this->view->members = $mem;

        if ($this->_request->getPost()) {

            Snep_Queues_Manager::removeAllMembers($queue);

            if (isset($_POST['duallistbox_group'])) {

                foreach ($_POST['duallistbox_group'] as $add) {
                    Snep_Queues_Manager::insertMember($queue, $add);
                }
            }

            $this->_redirect($this->getRequest()->getControllerName() . '/');
        }
    }

}
