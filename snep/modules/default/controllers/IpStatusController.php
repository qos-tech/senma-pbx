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
require_once "includes/functions.php";

/**
 * IP Status Controller
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2014 OpenS Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 */
class IpStatusController extends Zend_Controller_Action {

    /**
     * Initial settings of the class
     */
    public function init() {
        $this->view->baseUrl = Zend_Controller_Front::getInstance()->getBaseUrl();
        $this->view->key = Snep_Dashboard_Manager::getKey(
            Zend_Controller_Front::getInstance()->getRequest()->getModuleName(),
            Zend_Controller_Front::getInstance()->getRequest()->getControllerName(),
            Zend_Controller_Front::getInstance()->getRequest()->getActionName());

        // Create String translators for peer and trunks status
        $this->view->translate('Unreachable') ;
        $this->view->translate('Rejected') ;
        $this->view->translate('Auth. Sent') ;
        $this->view->translate('Registered') ;
        $this->view->translate('Request Sent') ;
        $this->view->translate('Unmonitored') ;

        $this->view->translate('UNMONITORED') ;
        $this->view->translate('UNREACHABLE') ;
        $this->view->translate('UNKNOWN') ;

      
    }

    /**
     * indexAction
     * @return type
     */
    public function indexAction() {

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Ip Status")));

        try {
            $astinfo = new AsteriskInfo();
        } catch (Exception $e) {
            $this->view->error_message = $this->view->translate("Error! Failed to connect to server Asterisk.");
            $this->renderScript('error/sneperror.phtml');
            return;
        }

        // SIP/IAX2 TRUNKS
        $like = 'SIP%';
        $troncos_sip = Snep_IpStatus_Manager::getTrunks($like);

        $like = 'IAX%';
        $troncos_iax = Snep_IpStatus_Manager::getTrunks($like);

        $this->view->trunks = array_merge($troncos_sip,$troncos_iax);

        // PEERS 
        $peers = Snep_IpStatus_Manager::getPeers();
        $this->view->peers = $peers ;


        // QUEUES 
        $queues = Snep_IpStatus_Manager::getQueues();
        $this->view->queues = $queues;
        
    }
}
