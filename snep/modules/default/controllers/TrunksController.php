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
require_once "includes/AsteriskInfo.php";

/**
 * Trunk Controller
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2014 OpenS Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 */
class TrunksController extends Zend_Controller_Action {

  /**
  * @var Zend_Form
  */
  protected $boardData;

  /**
  * preDispatch
  */
  public function preDispatch() {

    // Test Asterisk connection
    try {
      $astinfo = new AsteriskInfo();
      // Read Khomp links
      try {
        $data = $astinfo->status_asterisk("khomp links show concise", "", True) ;
      } catch (Exception $e) {
        $this->view->error_message = $this->view->translate("Socket connection to the server is not available at the moment.");
        $this->renderScript('error/sneperror.phtml');;
      }
    } catch (Exception $e) {
      $this->view->error_message =  $this->view->translate("Error! Failed to connect to server Asterisk.");
      $this->renderScript('error/sneperror.phtml');
    }

  }

  public function init() {
    $this->view->url = $this->getFrontController()->getBaseUrl() . '/' . $this->getRequest()->getControllerName();
    $this->view->lineNumber = Zend_Registry::get('config')->ambiente->linelimit;

    // Add dashboard button
    $this->view->baseUrl = Zend_Controller_Front::getInstance()->getBaseUrl();
    $this->view->key = Snep_Dashboard_Manager::getKey(Zend_Controller_Front::getInstance()->getRequest()->getModuleName(),
    Zend_Controller_Front::getInstance()->getRequest()->getControllerName(),
    Zend_Controller_Front::getInstance()->getRequest()->getActionName());

    // Informações de placas khomp
    try {
      $khomp_info = new PBX_Khomp_Info();
      $khomp_boards = array();
      if ($khomp_info->hasWorkingBoards()) {
        foreach ($khomp_info->boardInfo() as $board) {
          if (!preg_match("/FXS/", $board['model'])) {
            $khomp_boards["b" . $board['id']] = "{$board['id']} - " . $this->view->translate("Board") . " {$board['model']}";
            $id = "b" . $board['id'];
            if (preg_match("/E1/", $board['model'])) {
              for ($i = 0; $i < $board['links']; $i++)
              $khomp_boards["b" . $board['id'] . "l$i"] = $board['model'] . " - " . $this->view->translate("Link") . " $i";
            } else {
              for ($i = 0; $i < $board['channels']; $i++)
              $khomp_boards["b" . $board['id'] . "c$i"] = $board['model'] . " - " . $this->view->translate("Channel") . " $i";
            }
          }
        }
        $this->khompBoards = $khomp_boards;
      }
    } catch (Exception $e) {

    }
  }

  /**
  * indexAction
  */
  public function indexAction() {

    $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array($this->view->translate("Trunks")));

    $db = Zend_Registry::get('db');
    $select = "SELECT t.id, t.callerid, t.name, t.technology, t.trunktype, t.time_chargeby, t.time_total,t.disabled,
    (SELECT th.used FROM time_history AS th WHERE th.owner = t.id AND th.owner_type='T' ORDER BY th.changed DESC limit 1) as used,
    (SELECT th.changed FROM time_history AS th WHERE th.owner = t.id AND th.owner_type='T' ORDER BY th.changed DESC limit 1) as changed FROM trunks as t ";

    $datasql = $db->query($select);
    $trunks = $datasql->fetchAll();

    foreach ($trunks as $id => $val) {
      
      $trunks[$id]['saldo'] = null;

      if (!is_null($val['time_total'] )) {
        $call = $val['changed'];
        $callYear = substr($call, 0, 4);
        $callMonth = substr($call, 5, 2);
        $callDay = substr($call, 8, 2);

        $sale = 0;
        $val['time_total'] = $val['time_total']*60; // converter minutos for seconds
        
        switch ($val['time_chargeby']) {
          case 'Y':
          if ($callYear == date('Y')) {
            $sale = $val['time_total'] - $val['used'];
            if ($val['used'] >= $val['time_total']) {
              $sale = 0;
            }
          } else {
            $sale = $val['time_total'];
          }
          break;
          case 'M':
            $sale = $val['time_total'] - $val['used'];
            if ($val['used'] >= $val['time_total']) {
              $sale = 0;
            }
          break;
          case 'D':
          if ($callYear == date('Y') && $callMonth == date('m') && $callDay == date('d')) {

            $sale = $val['time_total'] - $val['used'];
          } else {
            $sale = $val['time_total'];
          }

          break;
        }

        if($sale < 0){
          $trunks[$id]['saldo'] = 0;
        }else{
          $trunks[$id]['saldo'] = round($sale/60); // converter seconds for minutos
        }
      }
    }

    // TASK-0029B: one bulk AMI query for every PJSIP/PJSIP_EXTERNAL
    // trunk on this page (Phase 17) -- see Snep_PjsipStatus_Manager.
    // Legacy chan_sip/IAX trunks get no runtime_status; that technology
    // is IpStatusController's own separate, pre-existing scope.
    $runtimeStatus = Snep_PjsipStatus_Manager::getTrunkStatuses();
    foreach ($trunks as $idx => $val) {
      $trunks[$idx]['runtime_status'] = isset($runtimeStatus[$val['id']]) ? $runtimeStatus[$val['id']] : null;
    }

    $this->view->trunks = $trunks;

  }

  /**
  * addAction - Add trunk
  * @return type
  * @throws ErrorException
  * @throws Exception
  */
  public function addAction() {

    $this->view->breadcrumb = $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array($this->view->translate("Trunks"),$this->view->translate("Add")));

    // Mont codec's list and sets the default codec for each option
    $codecsDefault = array("alaw","ilbc","g729","gsm","h264","h263","h263p","ulaw");
    $codec1 = "";$codec2 = "";$codec3 = "";

    foreach($codecsDefault as $key => $value){
      $codec1 .= '<option value="'.$value.'"'.($value==="alaw" ? " selected " : "").'>'.$value.'</option>\n';
      $codec2 .= '<option value="'.$value.'"'.($value==="ulaw" ? " selected " : "").'>'.$value.'</option>\n';
      $codec3 .= '<option value="'.$value.'"'.($value==="gsm"  ? " selected " : "").'>'.$value.'</option>\n';
    } // END foreach

    $this->view->codec1 = $codec1;
    $this->view->codec2 = $codec2;
    $this->view->codec3 = $codec3;

    $this->view->dtmf_rfc2833 = 'checked' ;

    $this->view->nat_no = 'checked';

    $this->view->type_friend = 'checked';

    // Informações de placas khomp
    $boards = "";
    if (isset($this->khompBoards)) {
      foreach($this->khompBoards as $key => $value){

        $boards .= '<option value="'.$key.'">'.$value.'</option>\n';
      }
    }
    $this->view->boards = $boards;

    if (class_exists("Telcos_Manager")) {
      $this->view->telcos = Telcos_Manager::getAll();
    }else{
      $this->view->telcos = array();
    }

    // TASK-0019: a fresh trunk has no persisted transport_id to
    // preserve -- offer exactly the currently-enabled transports plus
    // Automatic.
    $this->view->transports = Snep_PjsipTransports_Manager::getEnabled();

    //Define the action and load form
    $this->view->action = "add" ;
    $this->view->techType = "pjsip";
    $this->view->pjsip = 'selected' ;
    $this->renderScript( $this->getRequest()->getControllerName().'/addedit.phtml' );

    //After POSt
    if ($this->getRequest()->isPost()) {

      $form_isValid = true;

      // Trunk name validation
      $newId = Snep_Trunks_Manager::getName($_POST['callerid']);

      // TASK-0015A: getName() returns Zend_Db_Statement::fetch()'s raw
      // result -- false when no trunk with this callerid exists yet
      // (the normal case for any new trunk), or a single 2-key
      // associative array (id, callerid) when one does. count($newId)
      // on the false case is a PHP 8 fatal TypeError (count() requires
      // Countable|array); count()==2 on the found case only "worked" by
      // coincidence (counting the row's 2 selected columns, not rows
      // found). A plain truthiness check preserves the exact original
      // intent (a row was found vs. not) without relying on that
      // coincidence. See docs/tasks/0015a-trunk-crud-php84-strict-sql.md.
      if ($newId) {
        $form_isValid = false;
        $message = $this->view->translate("Name already exists.");
        $this->_helper->redirector('sneperror','error',null,array('error_message'=>$message));
      }

      if ($form_isValid) {

        // Mount array whith trunk data
        $trunk_data = $this->preparePost();
        // TASK-0019: preparePost() now returns a translated error string
        // (mirroring ExtensionsController::execAdd()'s own return-a-
        // string-on-failure convention) when the posted transport_id is
        // invalid -- must not fall through to the transaction below.
        if (is_string($trunk_data)) {
          $this->_helper->redirector('sneperror','error',null,array('error_message'=>$trunk_data));
          return;
        }
        if(isset($_POST['trunk_disabled'])){
          $trunk_data['trunk']["disabled"] = true;
        }

        $db = Snep_Db::getInstance();
        $db->beginTransaction();
        try {

          $db->insert("trunks", $trunk_data['trunk']);
          $id = $db->lastInsertId();

          // TASK-0016: PJSIP's id_regex depends on trunks.id, which
          // doesn't exist until the INSERT above returns it -- see the
          // comment in preparePost()'s PJSIP branch. Patched here, still
          // inside the same transaction, before anything else can read
          // this row.
          if ($trunk_data['trunk']['type'] === "PJSIP") {
            $db->update("trunks", array("id_regex" => "PJSIP/trunk-" . $id), "id = $id");
          }

          if($trunk_data['trunk']['trunktype'] == "I") {
            $trunk_data['ip']["name"] = $trunk_data['trunk']["name"];
            $db->insert("peers", $trunk_data['ip']);
          }
          $db->commit();

        } catch (Exception $ex) {
          $db->rollBack();
          throw $ex;
        }
        
        // audit
        Snep_Audit_Manager::SaveLog("Added", 'trunks', $id, $this->view->translate("Trunk") . " {$id} ". $_POST['callerid']);
        
        if(!isset($_POST['trunk_disabled'])){
          Snep_InterfaceConf::loadConfFromDb();
          // TASK-0015: called additively, mirroring ExtensionsController's
          // existing Snep_InterfaceConf+Snep_PjsipConf pairing (TASK-0011).
          // Harmless for non-PJSIP trunks: Snep_PjsipTrunkConf's own query
          // filters to canal LIKE 'PJSIP/%', so a chan_sip/IAX2/KHOMP/
          // VIRTUAL/SNEPSIP/SNEPIAX2 trunk is simply invisible to it.
          // TASK-0018: same reasoning as ExtensionsController -- transports must
          // exist before Snep_PjsipTrunkConf renders a transport=<name> reference.
          Snep_PjsipTransportConf::loadConfFromDb();
          Snep_PjsipTrunkConf::loadConfFromDb();
        }

        $this->_redirect("trunks");
      }
    }

  }

  /**
  * enableAction - Enable trunk
  * @return type
  * @throws ErrorException
  */
  public function enableAction() {

    $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array($this->view->translate("Trunks"),$this->view->translate("Enable")));

    $exten = $this->_request->getParam("id");

    $this->view->id = $exten;
    $this->view->remove_title = $this->view->translate('Enabled Trunk.');
    $this->view->remove_message = $this->view->translate('Are you sure you want to activate the trunk?');
    $this->view->remove_form = 'trunks';
    $this->renderScript('remove/enable.phtml');

    if ($this->_request->getPost()) {

      Snep_Audit_Manager::SaveLog("Enabled", 'trunks', $exten, $this->view->translate("Trunk") ." ". $exten);
      Snep_Trunks_Manager::enable($exten);
      Snep_InterfaceConf::loadConfFromDb();
      // TASK-0015: see the identical addAction() comment above.
      // TASK-0018: same reasoning as ExtensionsController -- transports must
      // exist before Snep_PjsipTrunkConf renders a transport=<name> reference.
      Snep_PjsipTransportConf::loadConfFromDb();
      Snep_PjsipTrunkConf::loadConfFromDb();
      $this->_redirect("trunks");
    }
  }

  /**
  * editAction - Edit trunk
  * @return type
  * @throws ErrorException
  * @throws Exception
  */
  public function editAction() {

    $this->view->breadcrumb = $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
      $this->view->translate("Trunks"),
      $this->view->translate("Edit trunk")));

      // TASK-0015A: mysql_escape_string() was removed entirely in PHP 7
      // -- fatal ("Call to undefined function") on every editAction()
      // load. Zend_Db_Adapter_Abstract::quote() is this codebase's own
      // already-present equivalent (used throughout Zend_Db) and, unlike
      // mysql_escape_string(), returns the value already wrapped in
      // quotes -- so the SQL text below no longer adds its own literal
      // quotes around it. Scoped to this one call site; the identical
      // removed-function call exists in 4 other, unrelated files
      // (RouteController x2, PickupGroupsController,
      // Snep_Parameters_Manager) -- not touched here, see
      // docs/tasks/0015a-trunk-crud-php84-strict-sql.md.
      $idTrunk = $this->getRequest()->getParam("trunk");

      $db = Snep_Db::getInstance();
      $trunk = $db->query("select * from trunks where id=" . $db->quote($idTrunk))->fetch();
      $trunk['qualify_value'] = "";
      if (class_exists("Telcos_Manager")) {
        $this->view->telcos = Telcos_Manager::getAll();
      }else{
        $this->view->telcos = array();
      }

      if ($trunk['trunktype'] == "I") {
        // TASK-0026C (F9): was raw string interpolation of the
        // trunk's own stored `name` (mass-assignable from POST at
        // creation time, see preparePost() below -- a second-order
        // injection triggered simply by viewing this edit page) into
        // SQL syntax.
        $ip_info = $db->select()->from('peers')->where('name = ?', $trunk['name']);
        $ip_info = $db->query($ip_info)->fetch();
        $this->view->infoTrunk = $ip_info;

        $type = $ip_info["type"];
        $label = "type_".$type;
        $this->view->$label = "checked";

        $qualify = $ip_info["qualify"];
        $label = "qualify_".$qualify;
        $this->view->$label = "checked";

        if ( $ip_info['qualify'] != 'yes' && $ip_info['qualify'] != 'no' ) {
          $trunk['qualify_value'] = $ip_info['qualify'] ;
          $this->view->qualify_specify = "checked";
        }

        $array_nat = explode(",",$ip_info['nat']);
        foreach($array_nat as $key => $val) {
          $label = "nat_".$val;
          $this->view->$label = "checked";
        }

      }

      // Trunk technology
      $technologyTrunk = strtolower($trunk['technology']);

      $this->view->pjsip = ($technologyTrunk === "pjsip" ? "selected" : "");
      $this->view->pjsip_external = ($technologyTrunk === "pjsip_external" ? "selected" : "");
      $this->view->techType   = $technologyTrunk; //"selected";
      $this->view->technology = $technologyTrunk;

      $this->view->dtmf_dial = ($trunk['dtmf_dial'] == '0') ? "" : "checked" ;
      $this->view->reverse_auth = ($trunk['reverse_auth'] == '0') ? "" : "checked" ;
      $this->view->map_extensions = ($trunk['map_extensions'] == '0') ? "" : "checked" ;
      $this->view->tempo = ($trunk['time_total'] > 0) ? "checked" : "" ;

      $this->view->name = $trunk['name'];

      $dialmethod = $trunk["dialmethod"];
      $label = "dialmethod_".$dialmethod;
      $this->view->$label = "checked";

      $dtmf = $trunk["dtmfmode"];
      $label = "dtmf_".$dtmf;
      $this->view->$label = "checked";

      $time_chargeby = $trunk['time_chargeby'];
      $label = "chargeby_".$time_chargeby;
      $this->view->$label = "checked";

      $trunk['identifier'] = $trunk['username'];

      $codecsDefault = array("ulaw","alaw","ilbc","g729","gsm","h264","h263","h263p");
      $codecs = explode(";", $trunk['allow']);

      $codec1 = "";
      $codec2 = "";
      $codec3 = "";
      foreach($codecsDefault as $key => $value){

        $codec1 .= ($value == $codecs[0]) ? '<option value="'.$value.'" selected>'.$value.'</option>\n' : '<option value="'.$value.'">'.$value.'</option>\n';
        $codec2 .= ($value == $codecs[1]) ? '<option value="'.$value.'" selected>'.$value.'</option>\n' : '<option value="'.$value.'">'.$value.'</option>\n';
        $codec3 .= ($value == $codecs[2]) ? '<option value="'.$value.'" selected>'.$value.'</option>\n' : '<option value="'.$value.'">'.$value.'</option>\n';

      }

      $this->view->codec1 = $codec1;
      $this->view->codec2 = $codec2;
      $this->view->codec3 = $codec3;

      // Khomp boards
      $boards = "";
      if (isset($this->khompBoards)){
        foreach($this->khompBoards as $key => $value){
          $boards .= ("KHOMP/".$key == $trunk['channel']) ? '<option value="'.$key.'" selected>'.$value.'</option>\n' : '<option value="'.$key.'">'.$value.'</option>\n';
        }
      }

      if($trunk['disabled']){
        $this->view->trunk_disabled = "checked";
      }

      $this->view->boards = $boards;
      $this->view->trunk = $trunk;
      // TASK-0019: item 2's edit-pre-select requirement -- includes the
      // currently-persisted transport even if it has since been
      // disabled (flagged, see
      // Snep_PjsipTransports_Manager::getSelectableWithCurrent()).
      $this->view->transports = Snep_PjsipTransports_Manager::getSelectableWithCurrent($trunk['transport_id']);

      //Define the action and load form
      $this->view->action = "edit" ;
      $this->view->disabled = "disabled" ;
      $this->renderScript( $this->getRequest()->getControllerName().'/addedit.phtml' );

      //After POST
      if ($this->getRequest()->isPost()) {

        $form_isValid = true;

        $newId = Snep_Trunks_Manager::getName($_POST['callerid']);

        // TASK-0015A: same count()-on-false fatal as addAction() above,
        // same fix -- see the comment there and
        // docs/tasks/0015a-trunk-crud-php84-strict-sql.md.
        if ($newId && $_POST['callerid'] != $trunk['callerid']) {
          $form_isValid = false;
          $message = $this->view->translate("Name already exists.");
          $this->_helper->redirector('sneperror','error',null,array('error_message'=>$message));
        }

        if ($form_isValid) {

          // TASK-0016: $idTrunk is already known here (the URL's "trunk"
          // param) -- pass it through so preparePost()'s PJSIP branch
          // can compute the real id_regex directly, no follow-up UPDATE
          // needed (unlike addAction(), where the row doesn't exist yet).
          // TASK-0019: $trunk['transport_id'] (the row loaded above,
          // before this POST was applied) is also passed through, so
          // preparePost() can tell "unchanged" from "newly pinned" when
          // validating a posted transport_id against §4's disabled-
          // transport rule.
          $trunk_data = $this->preparePost(null, $idTrunk, $trunk['transport_id']);
          if (is_string($trunk_data)) {
            $this->_helper->redirector('sneperror','error',null,array('error_message'=>$trunk_data));
            return;
          }

          $db = Snep_Db::getInstance();
          $db->beginTransaction();
          try {
            // TASK-0026C (F9 boundary): $idTrunk is the raw "trunk" route
            // param, and $trunk_data['trunk']['name'] is mass-assigned
            // straight from this same POST body (preparePost() merges
            // the entire $_POST into $trunk_data) -- both were spliced
            // raw into these UPDATE WHERE clauses.
            $db->update("trunks", $trunk_data['trunk'], $db->quoteInto('id = ?', $idTrunk));
            if ($trunk_data['trunk']['trunktype'] === "I") {
              $db->update("peers", $trunk_data['ip'], $db->quoteInto('name = ?', $trunk_data['trunk']['name']) . " AND peer_type = 'T'");
            }
            $db->commit();

          } catch (Exception $ex) {
            $db->rollBack();
            throw $ex;
          }
          //audit
          Snep_Audit_Manager::SaveLog("Updated", 'trunks', $idTrunk, $this->view->translate("Trunk") . " {$idTrunk} ". $_POST['callerid']);
          
          if(!isset($_POST['trunk_disabled'])){
            Snep_InterfaceConf::loadConfFromDb();
            // TASK-0015: see the identical comment in addAction() above.
            // TASK-0018: same reasoning as ExtensionsController -- transports must
            // exist before Snep_PjsipTrunkConf renders a transport=<name> reference.
            Snep_PjsipTransportConf::loadConfFromDb();
            Snep_PjsipTrunkConf::loadConfFromDb();
          }
          
          $this->_redirect("trunks");
        }
      }
    }

    /**
    * removeAction - Remove trunk
    */
    public function removeAction() {

      $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array($this->view->translate("Trunks"), $this->view->translate("Delete")));

      $id = $this->_request->getParam("id");
      $name = $this->_request->getParam("name");

      try {
        $astinfo = new AsteriskInfo();
      } catch (Exception $e) {
        $this->view->error_message = $this->view->translate("Socket connection to the server is not available at the moment.");
        $this->renderScript('error/sneperror.phtml');
        return;
      }
      if (!$data = $astinfo->status_asterisk("khomp links show concise", "", True)) {
        $this->view->error_message = $this->view->translate("Socket connection to the server is not available at the moment.");
        $this->renderScript('error/sneperror.phtml');
      }

      $regras = Snep_Trunks_Manager::getValidation($id);
      $rules_query = Snep_Trunks_Manager::getRules($id);

      foreach ($rules_query as $rule) {
        if (!in_array($rule, $regras)) {
          $regras[] = $rule;
        }
      }

      if (count($regras) > 0) {

        $this->view->error_message = $this->view->translate("Cannot remove. The following routes are using this trunk: ") . "<br />";
        foreach ($regras as $regra) {
          $this->view->error_message .= $regra['id'] . " - " . $regra['desc'] . "<br />\n";
        }
        $this->renderScript('error/sneperror.phtml');
      } else {

        $this->view->id = $id;
        $this->view->name = $name;
        $this->view->remove_title = $this->view->translate('Delete Trunk.');
        $this->view->remove_message = $this->view->translate('The trunk will be deleted. After that, you have no way get it back.');
        $this->view->remove_form = 'trunks';
        $this->renderScript('remove/remove.phtml');

        if ($this->_request->getPost()) {

          //audit
          $loguser = Snep_Trunks_Manager::get($id);
          Snep_Audit_Manager::SaveLog("Deleted", 'trunks', $id, $this->view->translate("Trunk") . " {$id} ". $loguser['callerid']);     

          Snep_Trunks_Manager::remove($_POST['id']);
          Snep_Trunks_Manager::removePeers($_POST['name']);

          Snep_InterfaceConf::loadConfFromDb();
          // TASK-0015: see the identical comment in addAction() above.
          // TASK-0018: same reasoning as ExtensionsController -- transports must
          // exist before Snep_PjsipTrunkConf renders a transport=<name> reference.
          Snep_PjsipTransportConf::loadConfFromDb();
          Snep_PjsipTrunkConf::loadConfFromDb();
          $this->_redirect("trunks");
        }
      }
    }


    /**
    * preparePost
    * @param <string> $post
    * @return type
    */
    protected function preparePost($post = null, $trunkId = null, $currentTransportId = null) {

      $post = $post === null ? $_POST : $post;
      $tech = isset($post['technology']) ? strtolower($post['technology']) : '';
      if (!in_array($tech, array('pjsip', 'pjsip_external'), true)) {
        return $this->view->translate('São permitidos apenas troncos PJSIP provisionados ou endpoints PJSIP externos.');
      }

      // TASK-0028B: o endpoint PJSIP externo pertence ao Asterisk, não ao
      // SENMA. Deliberadamente não há linha em peers, portanto nenhum gerador
      // de configuração pode provisionar, sobrescrever ou recarregar um objeto
      // que não administra. Ignora-se qualquer canal legado/livre e as duas
      // expressões de runtime são derivadas do nome validado do endpoint.
      if ($tech === 'pjsip_external') {
        $endpoint = isset($post['external_endpoint']) ? trim($post['external_endpoint']) : '';
        if (!preg_match('/^[A-Za-z0-9_.-]{1,80}$/', $endpoint)) {
          return $this->view->translate('O nome do endpoint PJSIP externo deve conter de 1 a 80 letras, números, pontos, hífens ou sublinhados.');
        }
        if (!$this->externalPjsipEndpointExists($endpoint)) {
          return $this->view->translate('O endpoint PJSIP externo não existe no runtime ativo do Asterisk.');
        }

        $sql = "SELECT name FROM trunks ORDER BY CAST(name as DECIMAL) DESC LIMIT 1";
        $row = Snep_Db::getInstance()->query($sql)->fetch();
        $trunkData = array(
          'callerid' => isset($post['callerid']) ? $post['callerid'] : '',
          'context' => 'default',
          'dtmfmode' => 'rfc2833',
          'allow' => 'alaw;ulaw;gsm',
          'channel' => 'PJSIP/' . $endpoint,
          'id_regex' => 'PJSIP/' . $endpoint,
          'type' => 'PJSIP_EXTERNAL',
          'trunktype' => 'T',
          'technology' => 'PJSIP_EXTERNAL',
          'username' => $endpoint,
          'domain' => '',
          'dialmethod' => 'NORMAL',
          'map_extensions' => isset($post['map_extensions']) && $post['map_extensions'] === 'map_extensions' ? 1 : 0,
          'dtmf_dial' => isset($post['dtmf_dial']) && $post['dtmf_dial'] === 'dtmf_dial' ? 1 : 0,
          'dtmf_dial_number' => isset($post['dtmf_dial_number']) ? $post['dtmf_dial_number'] : '',
          'reverse_auth' => 0,
          'time_total' => isset($post['tempo']) && $post['tempo'] === 'tempo' ? $post['time_total'] : null,
          'time_chargeby' => isset($post['tempo']) && $post['tempo'] === 'tempo' ? $post['time_chargeby'] : '',
          'time_initial_date' => isset($post['tempo']) && $post['tempo'] === 'tempo' ? $post['time_initial_date'] : null,
          'telco' => empty($post['telco']) ? null : $post['telco'],
          'transport_id' => null,
        );
        if ($this->view->action === 'add') {
          $trunkData['name'] = trim(((int) $row['name']) + 1);
        }
        return array('trunk' => $trunkData, 'ip' => array());
      }

      $trunktype = $post['technology'] = strtoupper($tech);
      // TASK-0015: "pjsip" added -- a PJSIP trunk gets a peers row too
      // (peer_type='T'), same as every other IP-technology trunk;
      // Snep_PjsipTrunkConf reads it via the same canal LIKE 'PJSIP/%'
      // pattern Snep_PjsipConf already uses for extensions.
      $ip_trunks = array("sip", "iax2", "snepsip", "snepiax2", "pjsip");

      // Only allowed fields for trunks table
      $trunk_fields = array(
        "callerid","type","username","secret","host","dtmfmode","reverse_auth","domain","insecure","map_extensions","dtmf_dial","dtmf_dial_number",
        "time_total","time_chargeby","time_initial_date","dialmethod","trunktype","context","name","allow","id_regex","channel","technology","transport_id");

      // Only allowed fields for peers table
      $ip_fields = array(
        "name","callerid","context","secret","type","allow","defaultuser","dtmfmode","fromdomain",
        "fromuser","canal","host","peer_type","trunk","qualify","nat","call-limit","port");

      // Get las trunk id, because trunk.id is autoinccrement and trunk.name not is
      $sql = "SELECT name FROM trunks ORDER BY CAST(name as DECIMAL) DESC LIMIT 1";
      $row = Snep_Db::getInstance()->query($sql)->fetch();

      if ($this->view->action == "add") {
        $trunk_data = array(
          "name" => trim($row['name'] + 1),
          "context" => "default",
          "trunktype" => (in_array($tech, $ip_trunks) ? "I" : "T"),
          "type" => $trunktype,
        );
      } else {
        $trunk_data = array("trunktype" => (in_array($tech, $ip_trunks) ? "I" : "T"),
        "type" => $trunktype,
      );
    }

    foreach ($post as $section_name => $section) {
      $trunk_data[$section_name] = $section;
    }

    // TASK-0015A: was PHP true/false. Zend_Db::insert()/update() bind
    // values via PDO positional parameters with no explicit type, and
    // PDO implicitly binds PHP `false` as the empty string '' (not '0')
    // -- MariaDB's strict mode then rejects '' for these NOT NULL
    // BOOLEAN columns (`Incorrect integer value: ''`). `true` happens to
    // stringify to '1', which strict mode accepts, which is why only the
    // false/unchecked case ever surfaced this. Using 1/0 preserves the
    // exact same boolean meaning while binding as a value MariaDB
    // actually accepts for these columns. See
    // docs/tasks/0015a-trunk-crud-php84-strict-sql.md.
    $trunk_data['dtmf_dial'] = ($post['dtmf_dial'] === "dtmf_dial" ? 1 : 0) ;
    $trunk_data['dtmf_dial_number'] = ($trunk_data['dtmf_dial'] ? $trunk_data['dtmf_dial_number'] : "");

    $trunk_data['map_extensions'] = ($post['map_extensions'] === "map_extensions" ? 1 : 0) ;

    $trunk_data['reverse_auth'] = ($post['reverse_auth'] === "reverse_auth" ? 1 : 0) ;

    $trunk_data['time_total'] = ($post['tempo'] === "tempo" ? $trunk_data['time_total'] : NULL);
    $trunk_data['time_chargeby'] = ($post['tempo'] === "tempo" ? $trunk_data['time_chargeby'] : "");
    // TASK-0015A: was "" (empty string) when unchecked, unlike its
    // sibling time_total two lines above which already correctly uses
    // NULL. time_initial_date is `int(11) default NULL` -- binding ''
    // to it hits the identical strict-mode "Incorrect integer value: ''"
    // failure as the boolean columns above, just via an explicit literal
    // instead of PDO's false-to-string coercion. NULL matches
    // time_total's already-correct, already-nullable handling. See
    // docs/tasks/0015a-trunk-crud-php84-strict-sql.md.
    $trunk_data['time_initial_date'] = ($post['tempo'] === "tempo" ? $trunk_data['time_initial_date'] : NULL);

    // check type Qualify, (yes|no|specify)
    if ($trunk_data['qualify'] === 'specify') {
      $trunk_data['qualify'] = trim($trunk_data['qualify_value']);
      // TASK-0028Y: this value now actually reaches Asterisk
      // (Snep_PjsipTrunkConf::renderTrunk()'s new qualify_frequency=
      // handling, confirmed gap #1 of the PJSIP Completeness
      // Architecture Review, TASK-0028W) -- previously it was stored
      // and never consumed, so no validation existed. A milliseconds
      // interval is the only shape that generator can safely translate;
      // anything else would otherwise skip the whole trunk at
      // generation time with no feedback to the admin at all. Failing
      // fast here, at submission, is the same discipline this
      // controller already applies to other newly-consumed fields (see
      // the PJSIP transport-selection checks above). 1-5 digits: a
      // pre-existing, previously-unenforced boundary --
      // `peers.qualify` is `char(5)` (schema.sql) -- surfaced now as a
      // clear product error instead of a raw SQL fatal on insert/update.
      if (!preg_match('/^\d{1,5}$/', $trunk_data['qualify'])) {
        return $this->view->translate('Qualification time must be a whole number of milliseconds (up to 5 digits).');
      }
    }

    // codecs
    $trunk_data['allow'] = trim(sprintf("%s;%s;%s", $trunk_data['codec'], $trunk_data['codec1'], $trunk_data['codec2']), ";");

    // TASK-0019: transport_id is a PJSIP-only concept -- default to NULL
    // (AUTO) here so every non-PJSIP technology persists NULL
    // unconditionally, regardless of what a stale/hidden form field
    // might carry (the selector is only ever rendered for
    // technology=pjsip). The PJSIP branch below overwrites this with
    // the validated posted value, or returns an error string instead of
    // continuing (mirroring ExtensionsController::execAdd()'s own
    // return-a-string-on-failure convention).
    $trunk_data['transport_id'] = null;

    if ($trunktype == "SIP" || $trunktype == "IAX2") {

      $trunk_data['dialmethod'] = strtoupper($trunk_data['dialmethod']);

      if ($trunk_data['dialmethod'] == 'NOAUTH') {
        $trunk_data['channel'] = $trunktype . "/@" . $trunk_data['host'];
      } else {
        $trunk_data['channel'] = $trunktype . "/" . $trunk_data['username'];
      }

      $trunk_data['id_regex'] = $trunktype . "/" . $trunk_data['username'];

    } else if ($trunktype == "PJSIP") {

      // TASK-0015: outbound-only, register-based model (TASK-0014
      // §4/§17/§20) -- dialmethod is stored but not specially
      // interpreted here; Snep_PjsipTrunkConf's decision to emit a
      // registration object is driven entirely by reverse_auth, not
      // dialmethod. `channel` only needs to start with "PJSIP/" for
      // Snep_PjsipTrunkConf's own filter to find the row; the real
      // Asterisk endpoint/auth/aor object names are computed
      // independently from trunks.id, not parsed back out of this
      // string -- see docs/tasks/0015-pjsip-trunk-provisioning.md.
      $trunk_data['dialmethod'] = strtoupper($trunk_data['dialmethod']);
      $trunk_data['channel'] = "PJSIP/" . $trunk_data['username'];

      // TASK-0016: id_regex is a DIFFERENT concern from `channel` above
      // -- PBX_Interfaces::getChannelOwner() matches an INBOUND
      // Asterisk channel name against id_regex directly (no separate
      // parsing), so it must hold the deterministic SENMA endpoint
      // identity Snep_PjsipTrunkConf/PBX_Trunks::get() actually name
      // the object ("trunk-<trunks.id>", TASK-0014 §10/TASK-0015 §4) --
      // NOT the provider-assigned account username `channel` uses
      // above (the original TASK-0015 bug: a PJSIP trunk's id_regex was
      // "PJSIP/<username>", which could never match the real inbound
      // channel name; see docs/tasks/0016-pjsip-inbound-trunk-routing.md
      // §2.2). trunks.id is an auto-increment column: on edit, the
      // caller already knows it (the URL's "trunk" param) and passes it
      // in as $trunkId; on add, no row exists yet, so it's left unset
      // here and addAction() patches it in a follow-up UPDATE once
      // lastInsertId() is available, in the same transaction, before
      // commit.
      if ($trunkId !== null) {
        $trunk_data['id_regex'] = "PJSIP/trunk-" . $trunkId;
      }

      // TASK-0019: transport selection -- exists + enabled-unless-
      // unchanged (see Snep_PjsipTransports_Manager::validateSelection()'s
      // own docblock). One column drives both the generated endpoint AND
      // registration object identically (Snep_PjsipTrunkConf::renderTrunk()
      // resolves it once) -- no separate selector needed or added.
      $postedTransportId = (isset($post['transport_id']) && $post['transport_id'] !== '') ? (int) $post['transport_id'] : null;
      if ($postedTransportId !== null) {
        $reason = Snep_PjsipTransports_Manager::validateSelection($postedTransportId, $currentTransportId);
        if ($reason === 'not_found') {
          return $this->view->translate('Selected PJSIP transport does not exist.');
        } else if ($reason === 'disabled') {
          return $this->view->translate('Selected PJSIP transport is disabled and cannot be newly assigned.');
        }
      }
      $trunk_data['transport_id'] = $postedTransportId;

    } else if ($trunktype === "SNEPSIP" || $trunktype === "SNEPIAX2") {

      $trunk_data['peer_type'] = $trunktype == "SNEPSIP" ? "peer" : "friend";
      $trunk_data['username'] = $trunktype == "SNEPSIP" ? $trunk_data['host'] : $trunk_data['identifier'];
      $trunk_data['channel'] = $trunk_data['id_regex'] = substr($trunktype, 4) . "/" . $trunk_data['username'];
      $trunk_data['qualify'] = 'yes' ;


    } else if ($trunktype == "KHOMP") {

      $khomp_board = $trunk_data['board'];
      $trunk_data['channel'] = 'KHOMP/' . $khomp_board;
      $b = substr($khomp_board, 1, 1);
      if (substr($khomp_board, 2, 1) == 'c') {
        $config = array(
          "board" => $b,
          "channel" => substr($khomp_board, 3)
        );
      } else if (substr($khomp_board, 2, 1) == 'l') {
        $config = array(
          "board" => $b,
          "link" => substr($khomp_board, 3)
        );
      } else {
        $config = array(
          "board" => $b
        );
      }
      $trunk = new PBX_Asterisk_Interface_KHOMP($config);
      $trunk_data['id_regex'] = $trunk->getIncomingChannel();
    } else { // VIRTUAL
      $trunk_data['id_regex'] = $trunk_data['id_regex'] == "" ? $trunk_data['channel'] : $trunk_data['id_regex'];
    }

    // Filter data and fields to allowed types
    $ip_data = array(
      "canal" => $trunk_data['channel'],
      "type" => $trunk_data['peer_type'],
    );
    foreach ($trunk_data as $field => $value) {

      if ($field === 'username') {
        $ip_data['defaultuser'] = $value ;
      }

      if (in_array($field, $ip_fields) && $field != "type") {
        $ip_data[$field] = $value;
      }

      if (!in_array($field, $trunk_fields)) {
        unset($trunk_data[$field]);
      }
    }

    $ip_data["peer_type"] = "T";
    $nat_types = array('no','comedia','force_rport','auto_comedia','auto_force_rport');
    $nat = "" ;
    foreach ($nat_types as $key => $val) {
      if (isset($post['nat_'.$val])) {
        if ($nat === "") {
          $nat = $val ;
        } else {
          $nat .= ','.$val ;
        }
      }
    }
    if ($nat === "") {
      $nat = 'no';
    }
    $ip_data['nat'] = $nat ;

    // TASK-0015A: peers.password/trunk/lastms are NOT NULL with no
    // schema default; this $ip_data build never included them, so
    // db->insert("peers", $ip_data) fails under strict SQL mode
    // (SQLSTATE[HY000] 1364) before a trunk's peers row can ever exist.
    // Values match ExtensionsController::execAdd()'s own explicit INSERT
    // for the identical columns (the only other, already-working write
    // site for these columns in this codebase): password='' (this
    // column is the unrelated numeric-PIN/padlock feature -- trunks have
    // no such UI field at all, so "" matches a fresh row's "no PIN set"
    // state exactly as it does for extensions); trunk='no' (chan_iax2's
    // native trunk=yes/no directive -- see the still-present but
    // commented-out consumer in Snep_InterfaceConf.php; 'no' is the
    // non-trunking default, matching extensions' own literal value, not
    // an arbitrary placeholder); lastms=0 (the "never qualified"
    // placeholder, identical reasoning to TASK-0011's extensions fix).
    // See docs/tasks/0015a-trunk-crud-php84-strict-sql.md.
    $ip_data['password'] = '';
    $ip_data['trunk'] = 'no';
    $ip_data['lastms'] = 0;

    // TASK-0015A: was the raw posted value verbatim -- "" when no Telco
    // is selected (the form's own "No Telco" option has value=""). Same
    // strict-mode failure as time_initial_date above: trunks.telco is
    // `INT(10) DEFAULT NULL`, and '' is not a valid integer under strict
    // SQL mode. NULL is the column's own correct "no telco" value. See
    // docs/tasks/0015a-trunk-crud-php84-strict-sql.md.
    $trunk_data['telco'] = ($post['telco'] === "" ? NULL : $post['telco']);

    // TASK-0026E (F13): every one of these reaches a raw config VALUE
    // position in Snep_PjsipTrunkConf::renderTrunk() (context=/callerid=/
    // from_user=/from_domain=/password=, plus host inside contact=/
    // client_uri=/server_uri=/match=) or Snep_InterfaceConf's legacy
    // chan_sip/iax2 generator (context=/host=/secret=, plus defaultuser
    // as BOTH a value and, for that legacy generator only, a raw
    // "[defaultuser]" section header) with zero prior validation -- a
    // newline in any of them could terminate the current directive and
    // inject a wholly new object or section. This project's own
    // established $tests_fields-style allowlist controls which POST
    // *keys* survive into $trunk_data/$ip_data; it never validated what
    // characters the *values* themselves may contain. Section identity
    // for the PJSIP generator is unaffected either way -- it is already
    // "trunk-<trunks.id>", an internal auto-increment key, never a
    // user-controlled field (see Snep_PjsipTrunkConf::renderTrunk()'s
    // own class-level doc comment).
    $error = $this->validateConfigFields($ip_data);
    if ($error !== null) {
      return $error;
    }

    return array("trunk" => $trunk_data, "ip" => $ip_data);
  }

  /**
   * Confirma no runtime o endpoint externo antes de persistir sua referência.
   * O identificador é validado antes de compor o comando AMI, e a resposta é
   * conferida pela linha estrutural do CLI, não apenas pela ausência de erro.
   */
  private function externalPjsipEndpointExists($endpoint) {
    try {
      $result = PBX_Asterisk_AMI::getInstance()->Command('pjsip show endpoint ' . $endpoint);
    } catch (Exception $ex) {
      return false;
    }
    $data = isset($result['data']) ? $result['data'] : '';
    // TASK-0028X finding (pre-existing, unrelated to that task's own
    // outbound-dial-string defect -- fixed here as its own narrowly-scoped
    // change): the real "pjsip show endpoint" CLI line is indented with a
    // leading space (" Endpoint:  <name>/<cid>" or, when the endpoint has
    // no configured callerid, " Endpoint:  <name>   <state>" with no
    // slash at all) -- confirmed live via AMI. The previous
    // '/^Endpoint:.../mi' anchor (no leading \s*) never matched that
    // indentation, and the previous unconditional trailing '\/' never
    // matched a callerid-less endpoint either, so this check rejected
    // every real endpoint unconditionally, making pjsip_external trunk
    // creation impossible through the UI. '(?:\/|\s)' after the endpoint
    // name accepts both real forms while still requiring a boundary
    // there, so a name that is merely a prefix of a different endpoint's
    // name (e.g. "foo" vs "foobar") cannot false-positive match.
    return preg_match('/^\s*Endpoint:\s+' . preg_quote($endpoint, '/') . '(?:\/|\s)/mi', $data) === 1;
  }

  /**
   * validateConfigFields - TASK-0026E (F13): the one shared validation
   * pass for every peers-table field that reaches a raw PJSIP/chan_sip
   * config value, applied once here regardless of which technology was
   * selected (rather than duplicated per-branch above). Returns a
   * translated error string on the first unsafe field found, or null if
   * every present field is safe -- mirrors this method's own existing
   * "return a string on failure" convention (see the PJSIP
   * transport-selection checks above).
   * @param array $ip_data
   * @return <string>|null
   */
  private function validateConfigFields(array $ip_data) {
    foreach (array('context', 'callerid', 'fromuser', 'fromdomain', 'secret') as $field) {
      if (isset($ip_data[$field]) && !Snep_PjsipConf::isSafeConfigValue($ip_data[$field])) {
        return $this->view->translate('Trunk field "%s" contains characters that are not allowed.', $field);
      }
    }
    // host: also reaches sip:<host>:<port> URI construction, so this
    // reuses the same IP-or-hostname grammar TASK-0019/0020 already
    // established for PJSIP transport addresses, rather than inventing
    // a second one -- optional, matching that function's own convention
    // (not every trunk technology requires a host).
    if (isset($ip_data['host']) && !Snep_PjsipTransports_Manager::validateIpOrHostname($ip_data['host'])) {
      return $this->view->translate('Invalid trunk host.');
    }
    // defaultuser: the legacy chan_sip/iax2 generator uses this as a
    // raw "[defaultuser]" section header (Snep_InterfaceConf.php), so it
    // gets the stricter identifier grammar already established for
    // PJSIP transport names -- but only when non-empty, since not every
    // trunk technology (e.g. KHOMP/VIRTUAL) necessarily populates it.
    if (isset($ip_data['defaultuser']) && $ip_data['defaultuser'] !== ''
        && !Snep_PjsipTransports_Manager::validateName($ip_data['defaultuser'])) {
      return $this->view->translate('Trunk username must be 1-80 letters, digits, dashes or underscores.');
    }
    return null;
  }

}
