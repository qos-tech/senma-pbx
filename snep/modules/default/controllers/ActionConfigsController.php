<?php
/*
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
 * Configuration Controller
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2014 OpenS Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 */
class ActionConfigsController extends Zend_Controller_Action {

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
     */
    public function indexAction() {

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Default Configs")
        ));

        $actionsDisp = PBX_Rule_Actions::getInstance();
        $infoActions = array();

        foreach ($actionsDisp->getInstalledActions() as $actionTmp) {
            $action = new $actionTmp;
            if ($action->getDefaultConfigXML() != "") {
                $infoActions[] = array(
                    "id" => $actionTmp,
                    "name" => $action->getName(),
                    "description" => $action->getDesc()
                );
            }
        }
        $this->view->infoAcoes = $infoActions;
    }

    /**
     * editAction
     * @throws PBX_Exception_BadArg
     */
    public function editAction() {

        $idAction = $this->getRequest()->getParam('id');
        $this->view->idAction = $idAction;

        if (!class_exists($idAction)) {
            throw new PBX_Exception_BadArg("Invalid Argument");
        } else {
            $action = new $idAction();
            $registry = PBX_Registry::getInstance($idAction);


            if ($action->getDefaultConfigXML() != "") {
            
                $actionConfig = new PBX_Rule_ActionConfig($action->getDefaultConfigXML());

                if ($this->getRequest()->isPost()) {

                    $newConfig = $actionConfig->parseConfig($_POST);

                    foreach ($newConfig as $key => $value) {
                        $registry->{$key} = $value;
                        $registry->setContext(get_class($action));
                    }

                    // Cleaning values no longer used
                    $previousValues = $registry->getAllValues();
                    foreach ($previousValues as $key => $value) {
                        if (!key_exists($key, $newConfig)) {
                            unset($registry->{$key});
                        }
                    }
                    $this->view->success = true;
                    $this->_redirect($this->getRequest()->getControllerName());
                }

                $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Default Configs"),
                    $this->view->translate("Edit"),
                    $this->view->translate($action->getName())));

                
                
                $actionConfig = new PBX_Rule_ActionConfig($action->getDefaultConfigXML());
                $actionForm = $actionConfig->getForm();
                $this->view->dialtimeout = $actionForm->getValue('dial_timeout');
                
                $this->view->values = $registry->getAllValues();
                


            
            } else {
                throw new PBX_Exception_BadArg("No Configurable Action");
            }
        }
    }

}
