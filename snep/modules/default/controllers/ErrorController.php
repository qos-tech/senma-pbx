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
require_once 'Zend/Controller/Action.php';

/**
 * Error Controller
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2014 OpenS Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 */
class ErrorController extends Zend_Controller_Action {
    
    /**
     * errorAction - Error treatment
     */
    public function errorAction() {
        $errors = $this->_getParam('error_handler');

        switch ($errors->type) {
            case Zend_Controller_Plugin_ErrorHandler::EXCEPTION_NO_CONTROLLER:
            case Zend_Controller_Plugin_ErrorHandler::EXCEPTION_NO_ACTION:
                // 404 error -- controller or action not found
                $this->getResponse()->setHttpResponseCode(404);
                $this->view->code = 404;
                $this->view->message = $this->view->translate("The page you are looking for was not found or does not exists.");
                $this->view->title = $this->view->translate("Not Found");
                break;
            default:
                // application error
                $this->getResponse()->setHttpResponseCode(500);
                $this->view->code = 500;
                $this->view->title = $this->view->translate("Internal Error");
                $this->view->sidebar = false;
                $this->view->message = $this->view->translate("Some internal error occured while processing your request. Please contact the system administrator and report this incident.");
                break;
        }

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
            $this->view->translate("Error"),
            $this->view->title
        ));

        $this->view->exception = $errors->exception;
        $this->view->request   = $errors->request;
        // $this->view->hideMenu  = true;
        $this->view->headTitle($this->view->title, 'PREPEND');
    }
    /* 
     * Cass to provide SNEP Error View
     * Parameters: 
     * 
     * error_type : string, optional. Valid: alert | error (default = error)
     * error_title: string, optional. (default  = "Error")
     * error_message: string
     * error_buttons: boolean, optional. (default = True)
     *
     * For instace from a view: 
     *      echo $this->action( 'sneperror', 'error', null, array( 'error_type' => _type_', 
            'error_title' => _title_, 'error_message' => _message_, 'error_butons' => _True/False_) );
     * For instace from a controller: 
     *      $this->view->error_message = $this->view->translate("Name already exists.");
            $this->renderScript('error/sneperror.phtml');
     */
    public function sneperrorAction() {

        $error_type = $this->_request->getParam('error_type') ;
        $error_title = $this->_request->getParam('error_title') ;
        $error_message = $this->_request->getParam('error_message') ;
        $error_buttons = $this->_request->getParam('error_buttons') ;
        
        if (isset($error_type)) {
            $this->view->error_type = $error_type ; 
        }
        if (isset($error_title)) {
            $this->view->error_title = $error_title;
        }
        if (isset($error_message)) {
            $this->view->error_message = $error_message;
        } 
        if (isset($error_buttons)) {
            $this->view->error_buttons = $error_buttons;
        }
    }
}
