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
 * Logs Controller
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2014 OpenS Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 */
class LogsController extends Zend_Controller_Action {

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
     * indexAction - filter logs of system
     */
    public function indexAction() {

        $this->view->breadcrumb = $this->view->translate("System Logs ");
        $config = Zend_Registry::get('config');

        $locale = Snep_Locale::getInstance()->getLocale();
        $now = Zend_Date::now();

        if ($locale == 'en_US') {
            $now = $now->toString('YYYY-MM-dd HH:mm');
        } else {
            $now = $now->toString('dd/MM/YYYY HH:mm');
        }
        
        $this->view->datepicker_locale =  Snep_Locale::getDatePickerLocale($locale) ;
        
        if ($this->_request->getPost()) {
            $this->viewAction();
        }
    }

    /**
     * initLogFile - init file log
     * @return <object> \Snep_Log
     */
    private function initLogFile() {
        $log = new Snep_Log(Zend_Registry::get('config')->system->path->log, 'full');
        return $log;
    }

    /**
     * viewAction - List log system
     */
    public function viewAction() {

         $formData = $this->_request->getParams();
        
        $this->view->breadcrumb = $this->view->translate("System Logs ");
        $this->view->exibition_mode = $this->view->translate("Exibition mode:");
        $this->view->normal = $this->view->translate("Normal");
        $this->view->terminal = $this->view->translate("Terminal");
        $this->view->contrast = $this->view->translate("Contrast");

        // Normal search mode
        if ($formData['real_time'] === 'no') {

            $init_day = explode(" ", $formData['init_day']);
            $final_day = explode(" ", $formData['end_day']);

            $formated_init_day = new Zend_Date($init_day[0]);
            $formated_init_day = ucfirst($formated_init_day->toString('YYYY-MM-dd'));
            $formated_init_time = $init_day[1];

            $formated_final_day = new Zend_Date($final_day[0]);
            $formated_final_day = ucfirst($formated_final_day->toString('YYYY-MM-dd'));
            $formated_final_time = $final_day[1];

            $log = $this->initLogFile();

            if ($log != 'error') {

                $result = $log->grepLog($formated_init_day, $formated_final_day, $formated_init_time, $formated_final_time, $formData['verbose'], $formData['others']);

                if ($result != 'error') {
                    
                        $this->view->period = $this->view->translate("Period: "). $formData['init_day'] . " " . $this->view->translate("to") . " " . $formData['end_day']; 
                        $this->view->file = $result;
                        $this->view->mode = 'normal';
                        $this->_helper->viewRenderer('view');
                    
                } else {

                    $this->view->error_message = $this->view->translate("No entries found!");
                    $this->renderScript('error/sneperror.phtml');
                }

            } else {

                $this->view->error_message = $this->view->translate("The log file cannot be open!");
                $this->renderScript('error/sneperror.phtml');
            }
        
        } else {    // Tail log mode

            $this->view->mode = 'tail';
            $this->_helper->viewRenderer('view');
        }
    }

/**
     * viewAction - List log system
     */
    public function getlogfileAction() {
        }

}
