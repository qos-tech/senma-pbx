<?php

/*
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
* Extension Controller
*
* @category  Snep
* @package   Snep
* @copyright Copyright (c) 2014 OpenS Tecnologia
* @author    Opens Tecnologia <desenvolvimento@opens.com.br>
*/
class ExtensionsController extends Zend_Controller_Action {

  /**
  *
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


  /**
  * Initial settings of the class
  */
  public function init() {

    $this->view->url = $this->getFrontController()->getBaseUrl() . '/' . $this->getRequest()->getControllerName();
    $this->view->lineNumber = Zend_Registry::get('config')->ambiente->linelimit;
    $this->view->peers_digits =  Zend_Registry::get('config')->canais->peers_digits;

    $this->extenGroups = Snep_ExtensionsGroups_Manager::getAll();

    $this->pickupGroups = Snep_PickupGroups_Manager::getAll();

    $this->view->baseUrl = Zend_Controller_Front::getInstance()->getBaseUrl();
    $this->view->key = Snep_Dashboard_Manager::getKey(
      Zend_Controller_Front::getInstance()->getRequest()->getModuleName(),
      Zend_Controller_Front::getInstance()->getRequest()->getControllerName(),
      Zend_Controller_Front::getInstance()->getRequest()->getActionName());
    }


    /**
    * indexAction - List extensions
    */

    public function indexAction() {

      $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
        $this->view->translate("Extensions")));

        $extensions = Snep_Extensions_Manager::getAll();
        
        // verify security password
        $passwordValidate = true;
        $passwordValidateExten = null;
        foreach($extensions as $key => $exten){
          $secure = self::securityPassword($exten["password"]);
          
          if($secure <= 40){
            $passwordValidate = false;
            $passwordValidateExten .= $exten['exten']." ";
          }
        }
        if(!$passwordValidate){
          $this->view->alert_message = $this->view->translate("You have extensions with weak passwords. For security measures it is important to update them.")."(".$passwordValidateExten.")";
        }
        
        $this->view->extensions = $extensions;

      }

      /**
       * Verify security password
       * @param int $password
       * @return int $force
       */
      public function securityPassword($password){

        $force = 0;

        // TASK-0013: was `count(password)` -- a bareword (undefined
        // constant under PHP 8, fatal) that was never valid even as
        // count($password): $password is peers.secret (varchar(80),
        // nullable in schema.sql), a scalar string, not a Countable/array.
        // This function scores password strength by length + character
        // class, so strlen() is the intended check; cast to string since
        // the column can be NULL even though this controller's own
        // execAdd() never writes NULL (isset(...) : "" fallback) -- see
        // docs/tasks/0013-extension-security-password-php84.md.
        $passwordLength = strlen((string)$password);
        if($passwordLength >= 8) $force += 10;
        if($passwordLength >= 16) $force += 10;
        if(preg_match('/[A-Z]/', $password)) $force += 20;
        if(preg_match('/[a-z]/', $password)) $force += 20;
        if(preg_match('/[0-9]/', $password)) $force += 20;
        if(preg_match('/[@?!%#]/', $password)) $force += 20;
                
        return $force;

      }

      /**
      * Generator of complex passwords
      * @param int $size
      * @param bolean $uppercase
      * @param bolean $numbers
      * @param bolean $symbols
      * @return string
      */
      public function generatorPassword($size = 16, $uppercase = true, $numbers = true, $symbols = true) {
        
        $lmin = 'abcdefghijklmnopqrstuvwxyz';
        $lmai = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
        $num = '0123456789';
        $simb = '@?!%#';
        $retorno = '';
        $caracteres = '';

        $caracteres .= $lmin;
          
        if ($numbers) $caracteres .= $num;
        if ($symbols) $caracteres .= $simb;
        if ($uppercase) $caracteres .= $lmai;

        $len = strlen($caracteres);
        for ($n = 1; $n <= $size; $n++) {
          $rand = mt_rand(1, $len);
          $retorno .= $caracteres[$rand-1];
        }
        return $retorno;
      }

      /**
      * addAction - Add extensions
      * @return type
      * @throws ErrorException
      */
      public function addAction() {

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
          $this->view->translate("Extensions"),
          $this->view->translate("Add")));

          $this->view->pickupGroups = $this->pickupGroups;
          $this->view->extenGroups = $this->extenGroups;
          // Set ExtensionGroup  "Default"
          $this->view->extenInGroup = array('1' => "");

          // Mont codec's list and sets the default codec for each option
          $codecsDefault = PBX_Interfaces::getCodecs();
          $codec1 = $codec2 = $codec3 = "";
          foreach($codecsDefault as $key => $value){
            $codec1 .= '<option value="'.$value['format'].'"'.($value['format']==="alaw" ? " selected " : "").'>'.$value['type'].' - '.$value['format'].'</option>\n';
            $codec2 .= '<option value="'.$value['format'].'"'.($value['format']==="ulaw" ? " selected " : "").'>'.$value['type'].' - '.$value['format'].'</option>\n';
            $codec3 .= '<option value="'.$value['format'].'"'.($value['format']==="gsm"  ? " selected " : "").'>'.$value['type'].' - '.$value['format'].'</option>\n';
          } // END foreach
          $this->view->codec1 = $codec1;
          $this->view->codec2 = $codec2;
          $this->view->codec3 = $codec3;

          // Mount trunks list
          $this->view->trunks = Snep_Trunks_Manager::getData();

          // Khomp boards
          $boardList = array();
          $khompInfo = new PBX_Khomp_Info();

          if ($khompInfo->hasWorkingBoards()) {
            foreach ($khompInfo->boardInfo() as $board) {
              if (preg_match("/FXS/", $board['model'])) {
                $channels = range(0, $board['channels']-1);
                foreach($channels as $key => $chan){
                  $boardList['b'.$board['id'].'c'.$chan] =  $board['model'] . ' - b' .$board['id'].'c'.$chan;
                }
              }
            }
          }
          $this->view->boardData = $boardList;


          //Define the action and load form
          $this->view->action = "add" ;
          $this->view->techType = 'sip';
          $this->view->directmedianonat = "checked";
          $this->view->typeFriend = "checked";
          $this->view->dtmfrf = "checked";
          $this->view->nat_force_rport = 'checked' ;
          $this->view->nat_comedia = 'checked' ;
          $this->view->blf = '';
          $extension = array("name" => "",
          "callerid" => "",
          "secret" => "",
          "call-limit" => "1",
          "email" => "",
          "password" => "",
          "usa_vc" => "",
          "cancallforward" => "",
          "authenticate" => 0);
          $extension['qualify'] = 'yes';
          // TASK-0019: no existing extension to preserve a stale
          // reference for -- a fresh add always offers exactly the
          // currently-enabled transports plus Automatic.
          $extension['transport_id'] = '';
          $this->view->extension = $extension;
          $this->view->transports = Snep_PjsipTransports_Manager::getEnabled();

          $this->renderScript( $this->getRequest()->getControllerName().'/addedit.phtml' );

          // After POST
          if ($this->getRequest()->isPost()) {

            $data = $this->_request->getParams();

            if (key_exists('virtual_error', $data)) {
              $this->view->error_message = "There's no trunks registered on the system. Try a different technology";
              $this->renderScript('error/sneperror.phtml');
            }

            $data["name"] = $data["name"] . " <" . $data["exten"].">";
            $ret = $this->execAdd($data);

            if (!is_string($ret)) {
              //audit
              Snep_Audit_Manager::SaveLog("Added", 'peers', $data['exten'], $this->view->translate("Extension") . " {$data['name']} " . $data['exten']);
              
              $this->_redirect('/extensions/');
            } else {
              $message = $ret;
              $this->_helper->redirector('sneperror','error',null,array('error_message'=>$message));
            }

          }
        }

        /**
        * editAction - Edit extensions
        * @return type
        * @throws ErrorException
        */
        public function editAction() {

          $id = $this->_request->getParam("id");
          $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
            $this->view->translate("Extensions"),
            $this->view->translate("Edit")));

            // Load data about exten
            $exten = Snep_Extensions_Manager::getPeer($id);

            $nameValue = explode("<", $exten['callerid']);
            if(count($nameValue) > 1){
              $exten['callerid'] = $nameValue[0];
            };

            $this->view->extension = $exten ;
            // TASK-0019: item 3's edit-pre-select requirement -- includes
            // the currently-persisted transport even if it has since been
            // disabled (flagged, see getSelectableWithCurrent()'s own
            // docblock), so this <select> always reflects what's actually
            // saved instead of silently defaulting to its first option.
            $this->view->transports = Snep_PjsipTransports_Manager::getSelectableWithCurrent($exten['transport_id']);

            // Groups
            $this->view->pickupGroups = $this->pickupGroups;
            $this->view->extenGroups = $this->extenGroups;

            $extenInGroup = array();
            foreach(Snep_ExtensionsGroups_Manager::getGroupsExtensions($exten['id']) as $key => $value){
              $extenInGroup[$value['group_id']] = "";
            }
            $this->view->extenInGroup = $extenInGroup;

            // Tech Type
            if (!$exten["canal"] || $exten["canal"] == 'INVALID' || substr($exten["canal"], 0, strpos($exten["canal"], '/')) == '') {
              $techType = 'manual';
            } else {
              $techType = strtolower(substr($exten["canal"], 0, strpos($exten["canal"], '/')));
            }

            $this->view->sip = "";
            $this->view->iax2 = "";
            $this->view->manual = "";
            $this->view->virtual = "";
            $this->view->khomp = "";
            $this->view->techType   = $techType; //"selected";
            $this->view->$techType = "selected";
            $this->view->technology = $techType;

            $timeTotal = $exten["time_total"];
            if (!empty($timeTotal)) {

              $this->view->timetotal = $timeTotal / 60;
              $this->view->controltype = $exten["time_chargeby"];

              $this->view->Y = "";
              $this->view->M = "";
              $this->view->D = "";
              $this->view->$exten["time_chargeby"] = "checked";
            }

            switch ($techType) {

              // TASK-0011: PJSIP reuses SIP's exact form fields (NAT,
              // direct media, DTMF, codecs) -- only the server-side
              // mapping in execAdd()/Snep_PjsipConf differs. "Type"
              // (peer/user/friend) has no PJSIP meaning; it's still
              // populated here (harmless) but hidden in the view via
              // showDiv()/typeSelector.
              case "sip":
              case "pjsip":

              $this->view->directmediayes = "";
              $this->view->directmedianonat = "";
              $this->view->directmediaupdate = "";
              $this->view->directmediaoutgoing = "";
              switch ($exten['directmedia']) {
                case "yes":
                $this->view->directmediayes = "checked";
                break;
                case "nonat":
                $this->view->directmedianonat = "checked";
                break;
                case "no":
                $this->view->directmedianonat = "checked";
                break;
                case "outgoing":
                $this->view->directmediaoutgoing = "checked";
                break;
                case "update":
                $this->view->directmediaupdate = "checked";
                break;
              }

              $this->view->typePeer = "";
              $this->view->typeFriend = "";
              $this->view->typeUser = "";
              switch ($exten['type']) {
                case "peer" :
                $this->view->typePeer = "checked";
                break ;
                case "friend" :
                $this->view->typeFriend = "checked";
                break ;
                case "user" :
                $this->view->typeUser = "checked";
                break ;
              }

              $this->view->dtmfrf = "";
              $this->view->dtmfinband = "";
              $this->view->dtmfinfo = "";
              if($exten['dtmfmode'] == "rfc2833"){
                $this->view->dtmfrf = "checked";
              }elseif($exten['dtmfmode'] == "inband"){
                $this->view->dtmfinband = "checked";
              }else{
                $this->view->dtmfinfo = "checked";
              }
              if($exten['blf'] == "yes"){
                $this->view->blf = "checked";
              }

              $array_nat = explode(",",$exten['nat']);
              foreach($array_nat as $key => $val) {
                $label = "nat_".$val;
                $this->view->$label = "checked";
              }


              $codecsDefault = array("ulaw","alaw","ilbc","g729","gsm","h264","h263","h263p","all");
              $codecsDefault = PBX_Interfaces::getCodecs();

              $codecs = explode(";", $exten['allow']);

              $codec1 = "";
              $codec2 = "";
              $codec3 = "";
              foreach($codecsDefault as $key => $value){

                $codec1 .= ($value['format'] == $codecs[0]) ? '<option value="'.$value['format'].'" selected>'.$value['type'].' - '.$value['format'].'</option>\n' : '<option value="'.$value['format'].'">'.$value['type'].' - '.$value['format'].'</option>\n';
                $codec2 .= ($value['format'] == $codecs[1]) ? '<option value="'.$value['format'].'" selected>'.$value['type'].' - '.$value['format'].'</option>\n' : '<option value="'.$value['format'].'">'.$value['type'].' - '.$value['format'].'</option>\n';
                $codec3 .= ($value['format'] == $codecs[2]) ? '<option value="'.$value['format'].'" selected>'.$value['type'].' - '.$value['format'].'</option>\n' : '<option value="'.$value['format'].'">'.$value['type'].' - '.$value['format'].'</option>\n';

              }


              $this->view->codec1 = $codec1;
              $this->view->codec2 = $codec2;
              $this->view->codec3 = $codec3;


              break;

              case "iax2":

              $this->view->directmediayes = "";
              $this->view->directmediano = "";
              if($exten['directmedia'] == "yes"){
                $this->view->directmediayes = "checked";
              }else{
                $this->view->directmediano = "checked";
              }

              $this->view->typePeer = "";
              $this->view->typeFriend = "";
              if($exten['type'] == "peer"){
                $this->view->typePeer = "checked";
              }else{
                $this->view->typeFriend = "checked";
              }

              $this->view->dtmfrf = "";
              $this->view->dtmfinband = "";
              $this->view->dtmfinfo = "";
              if($exten['dtmfmode'] == "rfc2833"){
                $this->view->dtmfrf = "checked";
              }elseif($exten['dtmfmode'] == "inband"){
                $this->view->dtmfinband = "checked";
              }else{
                $this->view->dtmfinfo = "checked";
              }

              // $codecsDefault = array("ulaw","alaw","ilbc","g729","gsm","h264","h263","h263p","all");
              $codecsDefault = PBX_Interfaces::getCodecs();
              $codecs = explode(";", $exten['allow']);

              $codec1 = "";
              $codec2 = "";
              $codec3 = "";
              foreach($codecsDefault as $key => $value){

                  $codec1 .= ($value['format'] == $codecs[0]) ? '<option value="'.$value['format'].'" selected>'.$value['type'].' - '.$value['format'].'</option>\n' : '<option value="'.$value['format'].'">'.$value['type'].' - '.$value['format'].'</option>\n';
                  $codec2 .= ($value['format'] == $codecs[1]) ? '<option value="'.$value['format'].'" selected>'.$value['type'].' - '.$value['format'].'</option>\n' : '<option value="'.$value['format'].'">'.$value['type'].' - '.$value['format'].'</option>\n';
                  $codec3 .= ($value['format'] == $codecs[2]) ? '<option value="'.$value['format'].'" selected>'.$value['type'].' - '.$value['format'].'</option>\n' : '<option value="'.$value['format'].'">'.$value['type'].' - '.$value['format'].'</option>\n';

              }

              $this->view->codec1 = $codec1;
              $this->view->codec2 = $codec2;
              $this->view->codec3 = $codec3;

              break;

              case "khomp":

              $khompInfo = substr($exten["canal"], strpos($exten["canal"], '/') + 1);
              $khompBoard = substr($khompInfo, strpos($khompInfo, 'b') + 1, strpos($khompInfo, 'c') - 1);
              $khompChannel = substr($khompInfo, strpos($khompInfo, 'c') + 1);

              $boardList = array();

              $khompInfo = new PBX_Khomp_Info();

              if ($khompInfo->hasWorkingBoards()) {
                foreach ($khompInfo->boardInfo() as $board) {

                  if (preg_match("/FXS/", $board['model'])) {

                    $channels = range(0, $board['channels']-1);

                    foreach($channels as $key => $chan){

                      $boardList['b'.$board['id'].'c'.$chan] =  $board['model'] . ' - b' .$board['id'].'c'.$chan;
                    }
                  }
                }
              }

              $this->view->boardData = $boardList;
              $this->view->khompChecked = 'b'.$khompBoard.'c'.$khompChannel;

              break;

              case "virtual":
              $virtualTrunk = substr($exten["canal"], strpos($exten["canal"], '/') + 1);

              $trunks =  Snep_Trunks_Manager::getData();
              $this->view->trunks = $trunks;
              $this->view->trunkChecked = $virtualTrunk;

              break;

              case "manual":
              $manualComp = substr($exten["canal"], strpos($exten["canal"], '/') + 1);
              $this->view->manual = $manualComp;
              break;
            }

            //Define the action and load form
            $this->view->disabled = 'disabled';
            $this->view->action = "edit" ;

            $this->renderScript( $this->getRequest()->getControllerName().'/addedit.phtml' );

            // After POST
            if ($this->getRequest()->isPost()) {

              $postData = $this->_request->getParams();

              $postData["exten"] = $this->_request->getParam("id");
              $postData['name'] = $postData['name']."<".$postData['exten'].">";


              $ret = $this->execAdd($postData, true);

              if (!is_string($ret)) {
                  //audit
                  Snep_Audit_Manager::SaveLog("Updated", 'peers', $postData['exten'], $this->view->translate("Extension") . " {$postData['name']} " . $postData['exten']);

                $this->_redirect('/extensions/');
              } else {
                $this->view->error_message = $ret;
                $this->renderScript('error/sneperror.phtml');;
              }

            }

          }

          /**
          * execAdd
          * @param <array> $postData
          * @param <boolean> $update
          * @return type
          */
          protected function execAdd($formData, $update = false) {

            $db = Zend_Registry::get('db');
            $exten = $formData["exten"];
            // TASK-0026C (F7): was raw string interpolation of $exten
            // into SQL syntax ("... where name = '$exten'"). Reuses this
            // manager's own already-parameterized lookup.
            $resultGetId = Snep_Extensions_Manager::getPeer($exten);

            if ($resultGetId && !$update) {
              return $this->view->translate('Extension already taken. Please, choose another denomination.');
            } else if ($update) {
              $idExten = $resultGetId['id'];
            }

            $context = 'default';
            $extenPass = $formData["passwordpadlock"];
            $extenName = $formData["name"];
            $extenGroup = $formData["exten_group"];
            $pickup_group = Snep_PickupGroups_Manager::getName($formData["pickup_group"]);

            // TASK-0026C: was the literal string "NULL" (unquoted SQL
            // syntax built by hand); now a plain PHP null so it can be
            // bound as a parameter -- see the INSERT/UPDATE rewrite below.
            $extenPickGrp = $formData["pickup_group"] == '' ? null : $pickup_group["cod_grupo"];
            $peerType = "R";

            $techType = $formData["technology"];

            $secret = (isset($formData["password"]))? $formData["password"]: "";

            $blf = (isset($formData["blf"]))? $formData["blf"]: "";
            $dtmfmode = (isset($formData["dtmf"]))? $formData["dtmf"]: "";
            $directmedia = $formData["directmedia"];
            $callLimit = $formData["calllimit"];

            // TASK-0019: transport_id is a PJSIP-only concept -- every
            // other technology must persist NULL regardless of what a
            // stale/hidden form field might carry (the selector is only
            // ever rendered, and only ever meant to be read, for
            // technology=pjsip). Validated here (exists + enabled-unless-
            // unchanged, see Snep_PjsipTransports_Manager::validateSelection()'s
            // own docblock for the "unless unchanged" reasoning) rather
            // than left for Snep_PjsipConf to discover at generation time.
            $transportId = null;
            if ($techType === 'pjsip' && isset($formData['transport_id']) && $formData['transport_id'] !== '') {
              $transportId = (int) $formData['transport_id'];
              $currentTransportId = ($update && isset($resultGetId['transport_id'])) ? $resultGetId['transport_id'] : null;
              $reason = Snep_PjsipTransports_Manager::validateSelection($transportId, $currentTransportId);
              if ($reason === 'not_found') {
                return $this->view->translate('Selected PJSIP transport does not exist.');
              } else if ($reason === 'disabled') {
                return $this->view->translate('Selected PJSIP transport is disabled and cannot be newly assigned.');
              }
            }
            // TASK-0026C: $transportId itself (already null or a
            // validated int, see above) is bound directly now -- the
            // separate "NULL"-as-string SQL-syntax variable is no longer
            // needed.

            if ($techType == 'sip' || $techType == 'iax2' || $techType == 'pjsip') {
              $nat_types = array('no','comedia','force_rport','auto_comedia','auto_force_rport');
              $nat = "" ;
              foreach ($nat_types as $key => $val) {
                if (isset($formData['nat_'.$val])) {
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
            }

            $qualify = 'no';
            if ($techType == 'sip' || $techType == 'iax2' || $techType == 'pjsip') {
              if (key_exists('qualify', $formData)) {
                $qualify = 'yes';
              }
            }

            // Type: friend, user, peer
            $type = $formData['type'];

            $channel = strtoupper($techType);

            if ($channel == "KHOMP") {

              $board = explode('c', $formData['channel']);

              $khompBoard = substr($board[0], 1);
              $khompChannel = $board[1];

              if ($khompBoard == null || $khompBoard == '') {
                return $this->view->translate('Select a Khomp board from the list');
              }
              if ($khompChannel == null || $khompChannel == '') {
                return $this->view->translate('Select a Khomp channel from the list');
              }
              $channel .= "/b" . $khompBoard . 'c' . $khompChannel;
            } else if ($channel == "VIRTUAL") {
              $channel .= "/" . (int)$formData["board"];
            } else if ($channel == "MANUAL") {
              $manual = $formData['manual'];
              $channel .= "/" . $manual;
            } else {
              $channel .= "/" . $exten;
            }

            $advVoiceMail = 'no';
            if (key_exists("voicemail", $formData)) {
              $advVoiceMail = 'yes';
            }

            if (key_exists("authenticate", $formData)) {
              $advPadLock = 1;
            } else {
              $advPadLock = 0;
            }

            $advCancallforward = 'no';
            if ($formData["cancallforward"]) {
              $advCancallforward = 'yes';
            } else {
              $advCancallforward = 'no';
            }

            //if (key_exists("minute_control", $formData["advanced"])) {
            if ($formData["minute_control"]) {
              $advMinCtrl = true;
              $advTimeTotal = $formData["timetotal"] * 60;
              // TASK-0026C: was the SQL-syntax strings "NULL"/"'123'"
              // built by hand; now a plain PHP null or int for binding.
              $advTimeTotal = $advTimeTotal == 0 ? null : $advTimeTotal;
              $advCtrlType = $formData['controltype'];
            } else {
              $advMinCtrl = false;
              $advTimeTotal = null;
              $advCtrlType = 'N';
            }

            // TASK-0026C: fixed defaults only (no request data), kept as
            // plain PHP values now that they feed an $db->insert() array
            // instead of being spliced into hand-built SQL text.
            $defFielsExten = array(
              "accountcode" => '',
              "amaflags" => '',
              "defaultip" => '',
              "host" => 'dynamic',
              "insecure" => '',
              // TASK-0011: `peers.language` is CHAR(2) DEFAULT 'br'
              // (schema.sql) -- was 'pt_BR' (5 chars), always too long for
              // the column under strict SQL mode (SQLSTATE 22001, another
              // pre-existing, technology-agnostic bug this task's real-UI
              // testing surfaced). Using the column's own correct native
              // default instead of a value that never fit it.
              "language" => 'br',
              "deny" => '',
              "permit" => '',
              "mask" => '',
              "port" => '',
              "restrictcid" => '',
              "rtptimeout" => '',
              "rtpholdtimeout" => '',
              "musiconhold" => 'cliente',
              "regseconds" => 0,
              "ipaddr" => '',
              "regexten" => '',
              "setvar" => '',
              "disallow" => 'all',
              // TASK-0011: `lastms` is NOT NULL with no column default
              // (schema.sql) and was never in this INSERT's column list at
              // all -- a pre-existing bug (unrelated to PJSIP, affects
              // every technology) that silently made extension creation
              // through the real UI impossible under strict SQL mode
              // (SQLSTATE[HY000] 1364), never caught because no existing
              // test exercises the create flow. 0 matches the "never
              // qualified" placeholder chan_sip peers already show before
              // their first real registration.
              "lastms" => 0
            );

            $advEmail = $formData["email"];

            if ($techType == "sip" || $techType == "iax2" || $techType == "pjsip") {
              $allow = sprintf("%s;%s;%s", $formData['codec'], $formData['codec1'], $formData['codec2']);
            } else {
              $allow = "ulaw";
            }

            // TASK-0026C (F7): the entire hand-built "UPDATE peers SET
            // col='$var',..." / "INSERT INTO peers (...) VALUES ('$var',...)"
            // strings below interpolated every one of these fields --
            // most of them raw, unvalidated request data (name, password,
            // callerid, secret, type, dtmfmode, email, directmedia,
            // controltype, blf, and the derived $channel for
            // technology=MANUAL) -- directly into SQL syntax with only a
            // single-quote wrapper and zero escaping. A single quote in
            // any of them broke out of the string literal. Replaced with
            // Zend_Db_Adapter's own parameterized insert()/update(),
            // which bind every value (PDO positional parameters), never
            // splicing request data into SQL text. Column set, defaults,
            // and NULL/int semantics for pickupgroup/callgroup/
            // time_total/transport_id are preserved exactly (see the
            // null-instead-of-"NULL"-string changes made to those
            // variables above).
            $peerData = array(
              "name" => $exten,
              "password" => $extenPass,
              "callerid" => $extenName,
              "context" => $context,
              "mailbox" => $exten,
              "qualify" => $qualify,
              "secret" => $secret,
              "type" => $type,
              "allow" => $allow,
              "defaultuser" => $exten,
              "fullcontact" => '',
              "dtmfmode" => $dtmfmode,
              "email" => $advEmail,
              "call-limit" => $callLimit,
              "outgoinglimit" => 1,
              "incominglimit" => 1,
              "usa_vc" => $advVoiceMail,
              "pickupgroup" => $extenPickGrp,
              "callgroup" => $extenPickGrp,
              "nat" => $nat,
              "canal" => $channel,
              "authenticate" => $advPadLock,
              "directmedia" => $directmedia,
              "time_total" => $advTimeTotal,
              "time_chargeby" => $advCtrlType,
              "cancallforward" => $advCancallforward,
              "blf" => $blf,
              // TASK-0019: written explicitly on every save, including
              // the NULL case -- this is a hand-built column set, so
              // omitting transport_id when switching EXPLICIT->AUTO would
              // silently preserve the old explicit value while the UI
              // claims Automatic was saved.
              "transport_id" => $transportId,
            );

            if ($update) {
              $db->update("peers", $peerData, $db->quoteInto('id = ?', $idExten));
            } else {
              $peerData["peer_type"] = $peerType;
              $peerData["trunk"] = 'no';
              // TASK-0011: `defFielsExten`'s fixed, non-request-derived
              // defaults -- unrelated to the request, appended once here
              // so the array-based insert covers the exact same column
              // set the old hand-built INSERT's $sqlFieldsExten/
              // $sqlDefaultValues did.
              $peerData = array_merge($peerData, $defFielsExten);
              $db->insert("peers", $peerData);
            }
            if (! $update) {
              $idExten = $db->lastInsertId();
            }

            if ($advVoiceMail == 'yes') {
              // TASK-0026C (F7): both the DELETE's WHERE clause and the
              // INSERT below interpolated request data ($exten,
              // $extenName, $advEmail, $extenPass) raw into SQL syntax.
              if ($update) {
                $db->delete("voicemail_users", $db->quoteInto('mailbox = ?', $exten));
              }
              $db->insert("voicemail_users", array(
                "context" => 'default',
                "fullname" => $extenName,
                "email" => $advEmail,
                "mailbox" => $exten,
                "password" => $extenPass,
                "customer_id" => $exten,
                "delete" => 'no',
              ));
            }
            if (isset($extenGroup)) {
              $extensions_group = Snep_ExtensionsGroups_Manager::getGroupsExtensions($idExten);
            } else {
              $extensions_group = array();
            }

            // Update table core_peer_groups
            Snep_ExtensionsGroups_Manager::updateGroupsExtension($idExten,$extensions_group,$extenGroup) ;
            Snep_InterfaceConf::loadConfFromDb();
            // TASK-0011: called unconditionally, like Snep_InterfaceConf
            // above -- each generator filters to its own canal prefix
            // internally (SIP%/IAX2% vs PJSIP/%), so calling both on
            // every write is harmless regardless of which technology this
            // particular extension actually uses (TASK-0010 §3/§11).
            // TASK-0018: transports must exist before Snep_PjsipConf renders a
            // transport=<name> reference to one -- same "call every generator
            // additively" pattern already used for the trunk generator below.
            Snep_PjsipTransportConf::loadConfFromDb();
            Snep_PjsipConf::loadConfFromDb();
          }

          /**
          * removeAction - Remove exetension
          * @return type
          * @throws ErrorException
          */
          public function removeAction() {

            $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
              $this->view->translate("Extensions"),
              $this->view->translate("Delete")));

              $exten = $this->_request->getParam("id");

              //checks if the exten is used in the rule
              $rules = Snep_Extensions_Manager::getValidation($exten);
              $rulesQuery = Snep_Extensions_Manager::getValidationRules($exten);
              $rules = array_merge($rules, $rulesQuery);

              if (count($rules) > 0) {
                $errMsg = $this->view->translate('The following routes use this extension, modify them prior to remove this extension') . ":<br />\n";
                foreach ($rules as $regra) {
                  $errMsg .= $regra['id'] . " - " . $regra['desc'] . "<br />\n";
                }
                $this->view->error_message = $errMsg;
                $this->view->back = $this->view->translate("Back");
                $this->renderScript('error/sneperror.phtml');

              } else {

                $this->view->id = $exten;
                $this->view->remove_title = $this->view->translate('Delete Extension.');
                $this->view->remove_message = $this->view->translate('The extension will be deleted. After that, you have no way get it back.');
                $this->view->remove_form = 'extensions';
                $this->renderScript('remove/remove.phtml');

                if ($this->_request->getPost()) {

                  $exten = $_POST['id'];
                  $db = Zend_Registry::get('db');
                  // TASK-0026C (F7): was raw string interpolation of
                  // $_POST['id'] into SQL syntax.
                  $result = Snep_Extensions_Manager::getPeer($exten);
                  $idExten = $result['id'];

                  try {
                    //audit
                    Snep_Audit_Manager::SaveLog("Deleted", 'peers', $exten, $this->view->translate("Extension") . " {$result['name']} ". $exten);
                    
                    Snep_Binds_Manager::removeBondByPeer($exten);
                    Snep_Extensions_Manager::remove($exten);
                    Snep_Extensions_Manager::removeVoicemail($exten);
                    Snep_ExtensionsGroups_Manager::deleteExtensionGroups($idExten);
                    Snep_InterfaceConf::loadConfFromDb();
                    // TASK-0018: transports must exist before Snep_PjsipConf renders a
                    // transport=<name> reference to one -- same "call every generator
                    // additively" pattern already used for the trunk generator below.
                    Snep_PjsipTransportConf::loadConfFromDb();
                    Snep_PjsipConf::loadConfFromDb();

                  } catch (PDOException $e) {
                    $db->rollBack();
                    $this->view->error_message = $this->view->translate("DB Delete Error: ") . $e->getMessage();
                    $this->view->back = $this->view->translate("Back");
                    $this->renderScript('error/sneperror.phtml');;
                  }

                  $this->_redirect("default/extensions");
                }
              }
            }

          /**
          * disableAction - Disable exetension
          * @return type
          * @throws ErrorException
          */
          public function disableAction() {

            $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
              $this->view->translate("Extensions"),
              $this->view->translate("Disable")));

              $exten = $this->_request->getParam("id");

              //checks if the exten is used in the rule
              $rules = Snep_Extensions_Manager::getValidation($exten);
              $rulesQuery = Snep_Extensions_Manager::getValidationRules($exten);
              $rules = array_merge($rules, $rulesQuery);

              if (count($rules) > 0) {
                $errMsg = $this->view->translate('The following routes use this extension, modify them prior to remove this extension') . ":<br />\n";
                foreach ($rules as $regra) {
                  $errMsg .= $regra['id'] . " - " . $regra['desc'] . "<br />\n";
                }
                $this->view->error_message = $errMsg;
                $this->view->back = $this->view->translate("Back");
                $this->renderScript('error/sneperror.phtml');

              } else {

                $this->view->id = $exten;
                $this->view->remove_title = $this->view->translate('Disabled Extension.');
                $this->view->remove_message = $this->view->translate('Are you sure you want to deactivate the extension? You can turn it on again later.');
                $this->view->remove_form = 'extensions';
                $this->renderScript('remove/disable.phtml');

                if ($this->_request->getPost()) {

                  try {
                    //audit
                    Snep_Audit_Manager::SaveLog("Disabled", 'peers', $exten, $this->view->translate("Extension") . " {$result['name']} ". $exten);
                    
                    Snep_Extensions_Manager::disable($exten);
                    Snep_InterfaceConf::loadConfFromDb();
                    // TASK-0018: transports must exist before Snep_PjsipConf renders a
                    // transport=<name> reference to one -- same "call every generator
                    // additively" pattern already used for the trunk generator below.
                    Snep_PjsipTransportConf::loadConfFromDb();
                    Snep_PjsipConf::loadConfFromDb();

                  } catch (PDOException $e) {
                    $db->rollBack();
                    $this->view->error_message = $this->view->translate("DB Delete Error: ") . $e->getMessage();
                    $this->view->back = $this->view->translate("Back");
                    $this->renderScript('error/sneperror.phtml');;
                  }

                  $this->_redirect("default/extensions");
                }
              }
            }

            /**
            * enableAction - Enable exetension
            * @return type
            * @throws ErrorException
            */
            public function enableAction() {

              $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array($this->view->translate("Extensions"),$this->view->translate("Enable")));

              $exten = $this->_request->getParam("id");

              $this->view->id = $exten;
              $this->view->remove_title = $this->view->translate('Enabled Extension.');
              $this->view->remove_message = $this->view->translate('Are you sure you want to activate the extension?');
              $this->view->remove_form = 'extensions';
              $this->renderScript('remove/enable.phtml');

              if ($this->_request->getPost()) {

                Snep_Audit_Manager::SaveLog("Enabled", 'peers', $exten, $this->view->translate("Extension") . " {$result['name']} ". $exten);
                Snep_Extensions_Manager::enable($exten);
                Snep_InterfaceConf::loadConfFromDb();
                // TASK-0018: transports must exist before Snep_PjsipConf renders a
                // transport=<name> reference to one -- same "call every generator
                // additively" pattern already used for the trunk generator below.
                Snep_PjsipTransportConf::loadConfFromDb();
                Snep_PjsipConf::loadConfFromDb();
                $this->_redirect("default/extensions");
              }
            }

            /**
            * multiremoveAction - Delete Extensions
            */
            public function multiremoveAction() {

              $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                $this->view->translate("Extensions"),
                $this->view->translate("Delete Multiples")));

                if ($this->getRequest()->isPost()) {

                  $data = $this->_request->getParams();
                  $range = array() ;
                  // Mount extensions list
                  if (isset($data['exten'])) {
                    $range = explode(";", $data["exten"]);
                    $data = $data["exten"];
                  }

                  foreach ($range as $exten) {
                    if (is_numeric($exten)) {
                      $extensions[$exten]="" ;
                    }else{
                      $exten = explode(";", $exten);
                      foreach ($exten as $extension) {
                        $rangeToAdd = explode('-', $extension);

                        if (is_numeric($rangeToAdd[0]) && is_numeric($rangeToAdd[1])) {
                          $start = (int) $rangeToAdd[0];
                          $end = (int) $rangeToAdd[1];
                          while ($start <= $end) {
                            $extensions[$start] = "";
                            $start++;
                          }
                        }
                      }
                    }
                  }
                  // checks if the exten is used in the rule
                  $rules = array();
                  foreach ($extensions as $key => $value) {

                    $_rules = Snep_Extensions_Manager::getValidation($key);
                    $rulesQuery = Snep_Extensions_Manager::getValidationRules($key);
                    if (count($_rules) > 0 || count($rulesQuery) > 0 ) {
                      $rules[$key] = array_merge($_rules, $rulesQuery);
                    }
                  }

                  if (count($rules) > 0) {
                    $errMsg = $this->view->translate('The following extensions are in use in routes, modify them prior to remove this extension') . ":<br />\n";
                    foreach ($rules as $ext => $regra) {
                      foreach ($regra as $k => $v) {
                        $errMsg .= $this->view->translate('Extension')." : ".$key." - ";
                        $errMsg .= $this->view->translate('Rule')." : ". $v['id'] . " - " . $v['desc'] . "<br />\n";
                      }
                    }
                    $this->view->error_message = $errMsg;
                    $this->view->back = $this->view->translate("Back");
                    $this->renderScript('error/sneperror.phtml');
                  } else {

                    foreach ($extensions as $key => $value) {
                      $exten = $key;
                      $db = Zend_Registry::get('db');
                      // TASK-0026C (F7 sibling): $exten is already
                      // is_numeric()/int-range validated above, so this
                      // was not independently exploitable, but it shares
                      // the exact same unparameterized construction as
                      // the confirmed F7 sinks in this same controller.
                      $result = Snep_Extensions_Manager::getPeer($exten);
                      $idExten = $result['id'];

                      try {
                        //audit
                        Snep_Audit_Manager::SaveLog("Deleted", 'peers', $exten, $this->view->translate("Extension") . " {$result['name']} " . $exten);

                        Snep_Extensions_Manager::remove($exten);
                        Snep_Extensions_Manager::removeVoicemail($exten);
                        Snep_ExtensionsGroups_Manager::deleteExtensionGroups($idExten);

                      } catch (PDOException $e) {
                        $db->rollBack();
                        $this->view->error_message = $this->view->translate("DB Delete Error: ") . $e->getMessage();
                        $this->view->back = $this->view->translate("Back");
                        $this->renderScript('error/sneperror.phtml');;
                      }

                    }
                    $this->_redirect("default/extensions");
                  }

                }
              }


              /**
              * multiaddAction - Add multi extensions
              * @return type
              * @throws ErrorException
              */
              public function multiaddAction() {

                $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                  $this->view->translate("Extensions"),
                  $this->view->translate("Add Multiples Extensions")));

                  $this->view->pickupGroups = $this->pickupGroups;
                  $this->view->extenGroups = $this->extenGroups;
                  // Set ExtensionGroup  "Default"
                  $this->view->extenInGroup = array('1' => "");

                  $this->view->boardData = $this->boardData;

                  // Monta SELECT de codecs e define o default para cada opcao
                  $codecsDefault = array("alaw","ilbc","g729","gsm","h264","h263","h263p","ulaw","all");
                  $codec1 = $codec2 = $codec3 = "";
                  foreach($codecsDefault as $key => $value){
                    $codec1 .= '<option value="'.$value.'"'.($value==="alaw" ? " selected " : "").'>'.$value.'</option>\n';
                    $codec2 .= '<option value="'.$value.'"'.($value==="ulaw" ? " selected " : "").'>'.$value.'</option>\n';
                    $codec3 .= '<option value="'.$value.'"'.($value==="gsm"  ? " selected " : "").'>'.$value.'</option>\n';
                  }  // END foreach
                  $this->view->codec1 = $codec1;
                  $this->view->codec2 = $codec2;
                  $this->view->codec3 = $codec3;

                  $this->view->trunks = Snep_Trunks_Manager::getData();

                  if ($this->getRequest()->isPost()) {

                    $data = $this->_request->getParams();

                    $range = explode(";", $data["exten"]);
                    $this->view->error = "";

                    foreach ($range as $exten) {

                      if ($this->view->error)
                      break;

                      if (is_numeric($exten)) {

                        $data["exten"] = $exten;
                        $data["password"] = self::generatorPassword();
                        $data["name"] = $this->view->translate("Extension ") ." ".$exten . " <" . $exten.">" ;
                        $data["sip"]["password"] = $exten;
                        $data["iax"]["password"] = $exten;
                        $data["calllimit"] = '1';
                        $data['type'] = 'friend' ;

                        $ret = $this->execAdd($data);

                        //audit
                        Snep_Audit_Manager::SaveLog("Added", 'peers', $data['exten'], $this->view->translate("Extension") . " {$data['name']} " . $data['exten']);

                        if (is_string($ret)) {
                          $this->view->error .= $exten . " - " . $ret;
                          break;
                        }
                      } else {

                        $exten = explode(";", $exten);

                        foreach ($exten as $extension) {
                          $rangeToAdd = explode('-', $extension);

                          if (is_numeric($rangeToAdd[0]) && is_numeric($rangeToAdd[1])) {
                            $i = $rangeToAdd[0];
                            while ($i <= $rangeToAdd[1]) {

                              $data["id"] = $i;
                              $data["exten"] = $i;
                              $data["password"] = self::generatorPassword();;
                              $data["name"] = $this->view->translate("Extension ") ." ".$i . " <" . $i.">" ;
                              $data["sip"]["password"] = $i . $i;
                              $data["iax2"]["password"] = $i . $i;
                              $data["calllimit"] = '1';
                              $data['type'] = 'friend' ;

                              $ret = $this->execAdd($data);

                              if (is_string($ret)) {
                                $this->view->error .= $i . " - " . $ret;
                                break;
                              }
                              //audit
                              Snep_Audit_Manager::SaveLog("Added", 'peers', $data['exten'], $this->view->translate("Extension") . " {$data['name']} " . $data['exten']);
                              $i++;
                            }
                          }
                          if ($this->view->error)
                          break;
                        }
                      }
                    }

                    if ($this->view->error) {
                      $this->view->error_message = $this->view->error ;
                      $this->renderScript('error/sneperror.phtml');
                    } else {
                      $this->_redirect("default/extensions");
                    }
                  }

                }

              }
