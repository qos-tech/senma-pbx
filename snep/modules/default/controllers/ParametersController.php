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
 * Paramenters Controller - System settings controller
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2014 OpenS Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 */
class ParametersController extends Zend_Controller_Action {


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
                    $this->view->translate("Parameters")));

        // Get configuration properties from Zend_Registry/exceptio
        $config = Zend_Registry::get('config');

        // Include Inpector class, for permission test
        include_once( $config->system->path->base . "/inspectors/Permissions.php" );
        $test = new Permissions();
        $response = $test->getTests();
        // Verify if there's any error, and if it's related to the setup.conf file
        if ($response['error'] && strpos($response['message'], "setup.conf") > 0) {
            // seta variavel verificada no template
            $this->view->error_message = $this->view->translate("The File includes/setup.conf does not have permission to be modified.");
            $this->renderScript('error/sneperror.phtml');
        }


        $this->view->config = $config;

        $this->view->debug = false;
        $this->view->hide_routes = false;
        if($config->system->debug == "1"){
            $this->view->debug = true;
        }
        $this->view->show_help = false;
        if($config->system->show_help === "true" || $config->system->show_help === true){
            $this->view->show_help = true;
        }

        if($config->system->hide_routes == "1"){
            $this->view->hide_routes = true;
        }
        
        $old_param = array();
        $old_param["emp_nome"] = $config->ambiente->emp_nome;
        $old_param["debug"] = $config->system->debug;
        $old_param["show_help"] = $config->system->show_help;
        $old_param["hide_routes"] = $config->system->hide_routes;
        $old_param["ip_sock"] = $config->ambiente->ip_sock;
        $old_param["user_sock"] = $config->ambiente->user_sock;
        $old_param["email"] = $config->system->mail;
        $old_param["linelimit"] = $config->ambiente->linelimit;
        $old_param['peers_digits'] =  $config->canais->peers_digits;

        $old_param["db.dbname"] = $config->ambiente->db->dbname;
        $old_param["db.host"] = $config->ambiente->db->host;
        $old_param["db.username"] = $config->ambiente->db->username;
        $old_param["db.password"] = $config->ambiente->db->password;


        $conference[$config->ambiente->conference_app] = "";
        if(isset($conference['C'])){
            $conference['C'] = "Conference";
            $conference['M'] = "Meetme";
        }else{
            $conference['M'] = "Meetme";
            $conference['C'] = "Conference";
        }

        $this->view->conference = $conference;

        $old_param["conference_app"] = $config->ambiente->conference_app;

        $locale = Snep_Locale::getInstance()->getZendLocale();
        $locales = array();
        foreach ($locale->getTranslationList("territory", Snep_Locale::getInstance()->getLanguage(), 2) as $ccode => $country) {
            $locales[$country] = $locale->getLocaleToTerritory($ccode);
        }
        ksort($locales, SORT_LOCALE_STRING);

        $localeDefault = $config->system->locale;
        foreach($locales as $x => $default){
            if($default == $localeDefault){
                $localeAll[$x] = $localeDefault;
            }
        }

        foreach($locales as $key => $locale){

            if($localeDefault != $locale){
                $localeAll[$key] = $locale;
            }else{
                $localeAll[$localeDefault] = $locale;
            }
        }

        $this->view->locales = $localeAll;

        $locale = Snep_Locale::getInstance()->getZendLocale();

        foreach ($locale->getTranslationList("territorytotimezone", Snep_Locale::getInstance()->getLanguage()) as $timezone => $territory) {
            $timezones[$timezone] = $timezone;
        }

        array_unshift($timezones, $config->system->timezone);
        $this->view->timezones = $timezones;

        $available_languages = Snep_Locale::getInstance()->getAvailableLanguages();

        foreach ($locale->getTranslationList("language", Snep_Locale::getInstance()->getLanguage()) as $lcode => $language) {

            if (in_array($lcode, $available_languages)) {
                $languages[$lcode] = $language;
            }
        }

        $languageDefault = $config->system->language;

        foreach($languages as $key => $language){
            if($key == $languageDefault){
                $languageAll[$key] = $language;
            }
        }

        foreach($languages as $key => $language){
            $languageAll[$key] = $language;
        }

        $this->view->languages = $languageAll;

        $this->view->mixmonitor = "";
        $this->view->monitor = "";
        $this->view->krecord = "";
        $value = $config->general->record->application;
        $this->view->$value = "selected";

        $old_param["application"] = $config->general->record->application;
        $old_param["flag"] = $config->general->record->flag;

        $this->view->true = "";
        $this->view->false = "";

        $old_param["path_voz"] = $config->ambiente->path_voz;
        $old_param["path_voz_bkp"] = $config->ambiente->path_voz_bkp;
        $old_param["valor_controle_qualidade"] = $config->ambiente->valor_controle_qualidade;



        // Verify if the request is a post
        if ($this->_request->getPost()) {

            $formData = $this->getRequest()->getParams();

            // Get country code
            $db = Snep_Db::getInstance();
            $country_code = $db->query("select id from core_cnl_country where locale='".$formData['language']."'")->fetch();

            $configFile = APPLICATION_PATH . "/includes/setup.conf";
            $config = new Zend_Config_Ini($configFile, null, true);

            $config->ambiente->emp_nome = $formData['emp_nome'];

            if($formData['debug'] == 'on'){
                $config->system->debug = 1;
            }else{
                $config->system->debug = 0;
            }
            if($formData['show_help'] == 'on'){
                $config->system->show_help = "true";
            }else{
                $config->system->show_help = "false";
            }
            if($formData['hide_routes'] == 'on'){
                $config->system->hide_routes = 1;
            }else{
                $config->system->hide_routes = 0;
            }
            $config->system->language = $formData['language'];
            $config->system->locale = $formData['locale'];
            $config->system->timezone = $formData['timezone'];
            $config->system->country_code = $country_code['id'];

            $config->canais->peers_digits = $formData['peers_digits'];

            $config->ambiente->ip_sock = $formData['ip_sock'];
            $config->ambiente->user_sock = $formData['user_sock'];
            $config->ambiente->pass_sock = $formData['pass_sock'];
            $config->system->mail = $formData['mail'];
            $config->ambiente->linelimit = $formData['linelimit'];
            $config->ambiente->conference_app = $formData['conference_app'];

            $config->ambiente->db->dbname = $formData['db_dbname'];
            $config->ambiente->db->host = $formData['db_host'];
            $config->ambiente->db->username = $formData['db_username'];
            $config->ambiente->db->password = $formData['db_password'];

            $config->general->record->application = $formData['application'];
            $config->general->record->flag = $formData['flag'];
            $config->general->record_mp3 = $formData['record_mp3'];
            $config->general->record->format = $formData['record_format'];

            $config->ambiente->path_voz = $formData['path_voz'];
            $config->ambiente->path_voz_bkp = $formData['path_voz_bkp'];

            $config->ambiente->valor_controle_qualidade = $formData['valor_controle_qualidade'];

            $writer = new Zend_Config_Writer_Ini(array('config' => $config,
                'filename' => $configFile));

            $writer->write();
            Snep_Locale::setExtensionsLanguage($formData['language']) ;

            // redirect
            $this->_redirect('/');
        }

    }

    /**
     * languageAction - Modify language
     */
    public function languageAction() {

        $configFile = APPLICATION_PATH . "/includes/setup.conf";
        $config = new Zend_Config_Ini($configFile, null, true);
        $config->system->language = $_GET["language"];
        $writer = new Zend_Config_Writer_Ini(array('config' => $config,
            'filename' => $configFile));
        $writer->write();

        Snep_Locale::setExtensionsLanguage($_GET["language"]) ;

        $module = $_GET["module"];
        $this->_redirect($module);
    }



}
