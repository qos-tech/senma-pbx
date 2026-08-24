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
 * Error Khomp Controller
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2014 OpenS Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 */
class ErrorsTdmController extends Zend_Controller_Action {

    /**
     * Initial settings of the class
     */
    public function init() {
        $this->view->baseUrl = Zend_Controller_Front::getInstance()->getBaseUrl();
        $this->view->key = Snep_Dashboard_Manager::getKey(
            Zend_Controller_Front::getInstance()->getRequest()->getModuleName(),
            Zend_Controller_Front::getInstance()->getRequest()->getControllerName(),
            Zend_Controller_Front::getInstance()->getRequest()->getActionName());
    }

    /**
     * indexAction
     * @return type
     * @throws ErrorException
     */
    public function indexAction() {

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
            $this->view->translate("Status"),
            $this->view->translate("TDM links errors")));


        try {
            $astinfo = new AsteriskInfo();
        } catch (Exception $e) {
            $this->view->error_message = $this->view->translate("Error! Failed to connect to server Asterisk.");
            $this->renderScript('error/sneperror.phtml');
            return;
        }

        // Read list of khomp boards

        $data = $astinfo->status_asterisk("khomp summary concise", "", True);

        if (!isset($data)) {
            $error_message['khomp'] = $this->view->translate("No khomp boards installed.");
        }else{
          $lines = explode("\n", $data);
          $kchannels = array();

          if (trim(substr($lines['1'], 10, 16)) === "Error" || strpos($lines['1'], "such command") > 0) {

              $error_message['khomp'] = $this->view->translate("No khomp boards installed.");

          }else{
            while (list($key, $val) = each($lines)) {

                $lin = explode(";", $val);

                if (preg_match("/^<K> [0-9][0-9]$/",$lin[0])) {

                    $kchannels[(int)substr($lin[0], 3)] = $lin[1] . " (".$lin[2].") - ".(substr($lin[1],0,3)==="EBS" ? $lin[5] : $this->view->translate("On board"));
                }
            }
          }

        }

        if($error_message && count())
        // Read khomp erros list
        if (!$data = $astinfo->status_asterisk("khomp links errors concise", "", True)) {

            $this->view->error_message = $this->view->translate("No boards whith links was detected.");
            $this->renderScript('error/sneperror.phtml');

        } else {

            $lines = explode("\n", $data);
            $kstatus = array();

            while (list($key, $val) = each($lines)) {

                $lin = explode(":", $val);

                if (substr($lin[0], 0, 3) == "<K>") {

                    $placa = substr($lin[0], 3);
                    $link = $lin[1];
                    $sts_name = $lin[2];
                    $sts_val = $lin[3];
                    $kstatus[(int)$placa][(int)$link][$sts_name] = $sts_val;
                }
            }

            // Adjust array
            foreach ($kchannels as $key => $value) {

                if (!isset($kstatus[$key])) {
                    $kstatus[$key][0] = NULL ;
                }
            }

            if (is_null($kchannels) ) {
                $this->view->error_message = $this->view->translate("No boards whith links was detected.");
                $this->renderScript('error/sneperror.phtml');
            } else {
                $this->view->canais = $kchannels;
                $this->view->status = $kstatus;

                if ($this->_request->getPost()) {
                    try {
                        require_once "includes/AsteriskInfo.php";
                        $astinfo = new AsteriskInfo();
                        $astinfo->status_asterisk("khomp links errors clear", "", "");
                    } catch (Exception $e) {
                        $this->view->error_message =  $this->view->translate("Error! Failed to connect to server Asterisk.");
                        $this->renderScript('error/sneperror.phtml');

                    }

                    $this->_redirect($this->getRequest()->getControllerName());

                }
            }
        }
    }

}
