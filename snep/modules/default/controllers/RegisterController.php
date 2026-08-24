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

/**
 * Controller for register
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2015 OpenS Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 */
class RegisterController extends Zend_Controller_Action {

    /**
     * indexAction
     */
    public function indexAction() {

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Register Snep")));

        $data = Snep_Register_Manager::get();

        //Checks that user is already registered.
        if($data['registered_itc'] == "1"){

            // Get configuration properties from Zend_Registry
            $config = Zend_Registry::get('config');

            $url = trim($config->system->itc_address)."scostumers?client_key=".$data['client_key']."&api_key=".$data['api_key']."&device_uuid=".$data['uuid'];

            $http = curl_init($url);
            curl_setopt($http, CURLOPT_SSL_VERIFYPEER, false);
            $status = curl_getinfo($http, CURLINFO_HTTP_CODE);
            curl_setopt($http, CURLOPT_RETURNTRANSFER,1);
            curl_setopt($http, CURLOPT_TIMEOUT,3);
            curl_setopt($http, CURLOPT_CONNECTTIMEOUT, 3);
            $http_response = curl_exec($http);
            $httpcode = curl_getinfo($http, CURLINFO_HTTP_CODE);
            curl_close($http);

            switch ($httpcode) {
                case 200:
                    $response = json_decode($http_response);
                    $this->view->data = $response;
                    $this->view->client_key = $data['client_key'];
                    $this->view->api_key = $data['api_key'];
                    $this->view->uuid = $data['uuid'];
                    $distributions = $response->details->distributions;

                    // Update distributions in database
                    Snep_Register_Manager::removeDistributions();
                    Snep_Register_Manager::addDistributions($distributions);
                    break;
                case 500:
                    $this->view->error_message = $this->view->translate("Internal Server Error. Please try later.");
                    $this->renderScript('error/sneperror.phtml');
                    break;
                case 401:
                    // different keys. Required login for update
                    $layout = Zend_Layout::getMvcInstance();
                    $layout->setLayout('loginregister');
                    break;
                case 404:
                    // device not exists in itc
                    $layout = Zend_Layout::getMvcInstance();
                    $layout->setLayout('loginregister');
                    break;
                case false:
                    $this->view->error_message = $this->view->translate("Without internet connection.");
                    $this->renderScript('error/sneperror.phtml');
                    break;
                default:
                    $this->view->error_message = $this->view->translate("Erro: ".$httpcode.". Please contact the administrator.");
                    $this->renderScript('error/sneperror.phtml');
                    break;
            }

            if ($this->_request->isPost()) {

                // login and update data
                if($_POST['save'] == 'login'){

                    unset($_POST['save']);

                    $data = $_POST;

                    $data['device_type_id'] = 1;
                    $data['device_uuid'] = $_SESSION["uuid"];

                    $content = json_encode($data);

                    $url = trim($config->system->itc_address) . "auth/login";
                    //$url = trim($config->system->itc_address) . "auth/slogin";
                    $curl = curl_init($url);
                    curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);
                    curl_setopt($curl, CURLOPT_HEADER, false);
                    curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
                    curl_setopt($http, CURLOPT_TIMEOUT,3);
                    curl_setopt($http, CURLOPT_CONNECTTIMEOUT, 3);
                    curl_setopt($curl, CURLOPT_HTTPHEADER,array("Content-type: application/json"));
                    curl_setopt($curl, CURLOPT_POST, true);
                    curl_setopt($curl, CURLOPT_POSTFIELDS, $content);

                    $json_response = curl_exec($curl);
                    $httpcode = curl_getinfo($curl, CURLINFO_HTTP_CODE);
                    curl_close($curl);

                    switch ($httpcode) {
                        case 200:
                            // update data
                            $data = json_decode($json_response);

                            $api_key = $data->details->api_key;
                            $client_key = $data->details->client_key;

                            $distributions = $data->details->distributions;
                            Snep_Register_Manager::removeDistributions();
                            Snep_Register_Manager::addDistributions($distributions);
                            Snep_Register_Manager::registerITC($api_key,$client_key);
                            $this->view->registerd = true;
                            break;
                        case 500:
                            $this->view->error = $this->view->translate("Internal Server Error. Please try later");
                            break;
                        case 401:
                            $this->view->error = $this->view->translate("User or password incorrect.");
                            break;
                        case false:
                            $this->view->error = $this->view->translate("Without internet connection.");
                            break;
                        default:
                            $this->view->error = $this->view->translate("Error: " .$httpcode. ". Please contact the administrator.");
                            break;
                    }

                    $layout = Zend_Layout::getMvcInstance();
                    $layout->setLayout('register');

                }
            }

        }else{

            // option register
            $_SESSION['noregister'] = false;
            $this->_redirect('/');

        }

    }


}
