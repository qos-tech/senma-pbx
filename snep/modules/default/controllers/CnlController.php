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

ini_set("max_execution_time", 180);

/**
 * CNL Controller
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2014 OpenS Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 */
class CnlController extends Zend_Controller_Action {

    /**
     * indexAction
     * @throws Exception
     * @throws ErrorException
     */
    public function indexAction() {

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Configure"),
                    $this->view->translate("CNL Update")));

        $this->view->pathweb = Zend_Registry::get('config')->system->path->web;

        // Get countries
        $countries = Snep_Cnl::getCountries();
        $this->view->countries = $countries ;

        if ($this->_request->getPost()) {

            $data = $this->_request->getPost();
            $country = $data['country'];
            switch ($country){
                case 76:
                    $this->updateAction_76();
                    break;
            }
                        
        }

    }

    /**
     * update Action only for Brazil telephon numbers
     */
    public function updateAction_76() {

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Configure"),
                    $this->view->translate("Updating CNL")));


        $data = $this->_request->getPost();

        $country = $data['country'];
        $c_type  = $data['type'];
        
        $adapter = new Zend_File_Transfer_Adapter_Http();
        $adapter->setDestination('/tmp');

        if (!$adapter->receive()) {
            $this->view->error_message = $adapter->getMessages();
            $this->renderScript('error/sneperror.phtml');
        } else {
            $_fileName = $adapter->getFileName();
            $file_name = str_replace("ZIP", "TXT",$_fileName) ;
            // Verify shell command
            if (`which unzip` && $_fileName != "") {  
                exec("unzip {$_fileName} -d /tmp");   
                $handle = fopen($file_name, "r") ;

                if ($handle) {

                    // Read file line a line and create a array
                    $prefixos = array() ;
                    while (!feof($handle)) {
                        $line = fgets($handle, 4096);
                        if (strlen(trim($line))) {
                            if ($c_type === "F") {
                                $prefix = trim(substr($line,116,7));
                                if (!array_key_exists($prefix, $prefixos)) {
                                    $prefixos[$prefix] = array(
                                        "state"     => trim(substr($line, 0, 2)),
                                        "city"      => trim(substr($line, 61, 50)),
                                        "latitud"   => trim(substr($line, 161, 8)),
                                        "hemispher" => trim(substr($line, 169, 5)),
                                        "longitud"  => trim(substr($line, 174, 8))
                                    ) ;    
                                }
                            } elseif ($c_type === "M") {
                                $prefix = trim(substr($line,0,7));
                                if (!array_key_exists($prefix, $prefixos)) {
                                    $prefixos[$prefix] = array(
                                        "state"     => NULL,
                                        "city"      => NULL,
                                        "latitud"   => NULL,
                                        "hemispher" => NULL,
                                        "longitud"  => NULL
                                    ) ;    
                                }
                            }
                        }
                        
                    } // end while
                    fclose($handle);
                    //Read Array and insert data into tables
                    $log_errors = "" ;

                    if (count($prefixos > 0)) {

                        foreach ($prefixos as $prefix => $value) {
                            if ($c_type === "F") {
                                $state = $value['state'];
                                $city_name = Snep_Cnl::parseName(utf8_encode($value['city'])) ;

                                // Verify if state exist. If not, add
                                if (!Snep_Cnl::getState($state,$country)) {
                                    $log_errors .= $this->view->translate("State : ".$state." not found in database.")."<br />" ;
                                    $res = Snep_Cnl::addState($state,$country) ;
                                    if ($res != "") {
                                        $this->view->error_message = $res;
                                        $this->renderScript('error/sneperror.phtml'); 
                                        break ;
                                    }
                                }
                                // Verify if City exist. If not, add
                                $city_code = Snep_Cnl::getCityCode($state,$city_name) ;
                                if (is_null($city_code)) {
                                    $log_errors .= $this->view->translate("City/State : ".$city_name ."/".$state." not found in database.")."<br />" ;
                                    $city_code = Snep_Cnl::addCity($state,$city_name) ;

                                    if (!is_numeric($city_code)) {
                                        $this->view->error_message = $this->view->translate("City code not foun or invalid.")."<br />".$res;
                                        $this->renderScript('error/sneperror.phtml'); 
                                        break ;
                                    } else {

                                    }
                                } else {
                                    $city_code = $city_code['id'];
                                }
                            } elseif ($c_type === "M") {
                                $city_code = NULL ;
                            }
                            // Verify if Prefix exist. If not, add
                             if (!Snep_Cnl::getPrefix($prefix,$country)) {
                                $res = Snep_Cnl::addPrefix($prefix,$country,$city_code,$value['latitud'],$value['longitud'],$value['hemispher']) ;
                                if ($res != "") {
                                    $this->view->error_message = $res;
                                    $this->renderScript('error/sneperror.phtml'); 
                                    break ;
                                }
                            }
                        }
                       
                    } else {
                        $this->view->error_message = $this->view->translate("No data found in the file");
                        $this->renderScript('error/sneperror.phtml');        
                    }
                }
            } else {
                $this->view->error_message = $this->view->translate("Program 'unzip' not installed or there was a problem with the file transfer");
                $this->renderScript('error/sneperror.phtml');
            }
            $this->_redirect($this->getRequest()->getControllerName());
        }
        

    }

}
