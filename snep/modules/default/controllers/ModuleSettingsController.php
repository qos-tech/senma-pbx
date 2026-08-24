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
 * Module Settings Controller - System settings controller
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2014 OpenS Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 */
class ModuleSettingsController extends Zend_Controller_Action {


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
     * indexAction - List parameters
     */
    public function indexAction() {

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
            $this->view->translate("Module Settings")));

        $config = Zend_Registry::get('config');

        $path = $config->system->path->base."/modules";

        $directory = scandir($path);
        $data = array();
        $cont_modules = count($directory);
        $all_modules = "";

        // receives the form parameter through json file of modules
        foreach($directory as $dir => $folder){

            if($folder != '.' &&  $folder != '..'){
                $filename = $path."/".$folder."/configs/config.json";

                if(file_exists($filename)){
                    $data[$dir] = file_get_contents($filename);
                }
            }
        }

        if(empty($data)){
            if($cont_modules > 3){
                // It has modules without setting
                $this->view->error_message = $this->view->translate("Its modules do not require extra settings");
            }else{
                // No modules
                $this->view->error_message = $this->view->translate("Your Snep not have additional modules");
            }

        }else{

            // mounts array with form data
            $cont = 0;
            foreach ($data as $module => $json) {

                $values = json_decode($json);
                $view[$cont]["name"] = $values->nome;
                $module_name = $values->nome;
                $all_modules .= "#".$values->nome.",";
                unset($values->nome);

                foreach($values as $key => $value){

                    $view[$cont]["view"][$key]["type"] = $value->type;
                    $view[$cont]["view"][$key]["key"] = $module_name."_x_".$value->key;
                    $view[$cont]["view"][$key]["label"] = $this->view->translate($value->label);
                    if($value->data_intro){
                        $view[$cont]["view"][$key]["data_intro"] = $this->view->translate($value->data_intro);
                    }


                    switch ($value->type) {
                        case 'select':

                            foreach($value->option as $x => $option){
                                $view[$cont]["view"][$key]["select"][$x]["label"] = $this->view->translate($option->label);
                                $view[$cont]["view"][$key]["select"][$x]["key"] = $option->key;
                                if(isset($option->selected)){
                                    $view[$cont]["view"][$key]["select"][$x]["selected"] = true;
                                }else{
                                    $view[$cont]["view"][$key]["select"][$x]["selected"] = "";
                                }
                            }
                            break ;

                        case 'multi_checkbox':

                            $view[$cont]["view"][$key]["fieldset"] = $this->view->translate($value->fieldset);
                            foreach($value->option as $x => $option){
                                $view[$cont]["view"][$key]["checkbox"][$x]["label"] = $this->view->translate($option->label);
                                $view[$cont]["view"][$key]["checkbox"][$x]["key"] = $option->key;
                                $view[$cont]["view"][$key]["checkbox"][$x]["checked"] = $option->checked;
                            }
                            break;

                        case 'separator' :
                            $view[$cont]["view"][$key]["type"] = $value->type;
                            break ;

                        case 'text_ro' :

                            break;

                        default :

                            (isset($value->placeholder))? $view[$cont]["view"][$key]["placeholder"] = $this->view->translate($value->placeholder) : $view[$cont]["view"][$key]["placeholder"] = "";
                            (isset($value->default))? $view[$cont]["view"][$key]["value"] = $value->default : $view[$cont]["view"][$key]["value"] = "";
                            break;
                    }
                }
                $cont++;
            }

            // get specfic data in database - Userfield
            // IMPORTANT - verify:
            // - agi/snep.php
            // - lib/Snep/ModuleSettings/Manager.php
            // - modules/default/views/scripts/module-settings/index.phtml
            $mod_default = Snep_ModuleSettings_Manager::get("default");
            foreach ($mod_default as $key => $value) {
                if ($value['config_name'] === 'userfield') {
                    $userfield = $value["config_value"];
                } elseif ($value['config_name'] === 'userfield_ud') {
                    $userfield_ud = $value["config_value"];
                }

            }
            $subject=array("TS","AA","MM","DD","HH","ii","SR","DS","UD");
            $uf_check = array() ;

            for ($i=0 ; $i <=strlen($userfield) ; $i++){
                $CHAR = substr($userfield, $i,1) ;
                if ($CHAR === "_" ) {
                    array_push($uf_check,'_') ;
                } elseif ($CHAR === "-" ) {
                    array_push($uf_check,'-') ;
                } else {
                    $A = substr($userfield, $i,2) ;
                    if (in_array($A,$subject)) {
                        array_push($uf_check, $A);
                        $i ++ ;
                    }
                }
            }

            //get generic data in database
            foreach($view as $i => $val){

                $records = Snep_ModuleSettings_Manager::get($val["name"]);

                if(!empty($records)){

                    foreach($val["view"] as $x => $form){

                        $exp = explode("_x_", $form["key"]);
                        foreach($records as $y => $database){
                            if($form["type"] === "text" || $form["type"] === "password" || $form["type"] === "text_ro"){
                                if($exp[1] === $database["config_name"]){
                                    $view[$i]["view"][$x]["value"] = $database["config_value"];
                                }

                            }elseif($form["type"] === "select"){
                                if($exp[1] === $database["config_name"]){
                                    $view[$i]["view"][$x]["selected"] = $database["config_value"];
                                }

                            }elseif($form["type"] === "checkbox"){
                                if($exp[1] === $database["config_name"]){

                                    if($database["config_value"] == "on"){
                                        $view[$i]["view"][$x]["checked"] = true;
                                    }
                                }
                            }elseif($form["type"] === "multi_checkbox"){
                                if ($exp[1] === "userfield_compose") {
                                    foreach ($form['checkbox'] as $uf_key => $uf_val) {

                                        if (in_array($uf_val['key'],$uf_check)) {
                                            $view[$i]['view'][$x]['checkbox'][$uf_key]['checked'] = "true" ;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            $this->view->data = $view;
            $this->view->allModules = substr($all_modules,0,-1);
        }

        // Verify if the request is a post
        if ($this->_request->getPost()) {

            $formData = $this->getRequest()->getParams();

            unset($formData["controller"]);
            unset($formData["action"]);
            unset($formData["module"]);
            unset($formData["signup"]);

            // capture model name
            foreach($formData as $key => $value){
                $res = explode("_",$key);
            }


            // Insert key and value
            foreach($formData as $key => $value){

                $res = explode("_x_",$key);

                if($res[1] === 'smtp_password'){
                  $value = base64_encode($value);
                }
                $config_key = array(
                    'config_module = ? ' => $res[0],
                    'config_name = ? ' => $res[1]
                    );
                $config_value = array("config_value" => $value);
                $exist_config = Snep_ModuleSettings_Manager::getConfig($res[1]);

                if($exist_config != false && count($exist_config) > 0){
                  Snep_ModuleSettings_Manager::updateConfig($config_key,$config_value);
                }else if(isset($value) && isset($res[0]) && isset($res[1])){
                  $config = array(
                    "config_module" => $res[0],
                    "config_name" => $res[1],
                    "config_value" => $value
                  );
                  Snep_ModuleSettings_Manager::addConfig($config);
                }


            }

            // redirect
            $this->_redirect('/');
        }

    }

}
