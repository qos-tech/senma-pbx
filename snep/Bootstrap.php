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

require_once 'Zend/Session.php';
require_once 'Zend/Application/Bootstrap/Bootstrap.php';
require_once 'Snep/Locale.php';
require_once 'modules/default/model/PermissionPlugin.php';

Zend_Session::start();

/**
 * Bootstrap
 *
 */
class Bootstrap extends Zend_Application_Bootstrap_Bootstrap {
    /*
     * _initLogin - Agendamento de verificação de login
     */

    protected function _initLogin() {
        $front = Zend_Controller_Front::getInstance();
        $front->registerPlugin(new Snep_AuthPlugin());
    }

    /**
     * _initRouter
     */
    protected function _initRouter() {
        $front_controller = Zend_Controller_Front::getInstance();
        $front_controller->setBaseUrl($_SERVER['SCRIPT_NAME']);

        $router = $front_controller->getRouter();
        $router->addRoute('route_edit', new Zend_Controller_Router_Route('route/edit/:id', array('controller' => 'route', 'action' => 'edit'))
        );
        $router->addRoute('route_duplicate', new Zend_Controller_Router_Route('route/duplicate/:id', array('controller' => 'route', 'action' => 'duplicate'))
        );
        $router->addRoute('route_delete', new Zend_Controller_Router_Route('route/delete/:id', array('controller' => 'route', 'action' => 'delete'))
        );
        $router->addRoute('route_permission', new Zend_Controller_Router_Route('permission/:exten', array('controller' => 'permission', 'action' => 'index'))
        );
    }

    /**
     * _initLocale
     */
    protected function _initLocale() {
        $locale = Snep_Locale::getInstance();
        Zend_Registry::set("i18n", $locale->getZendTranslate());
    }

    /**
     * _initViewHelpers - Starts the system view and layout
     * @return Zend_View
     */
    protected function _initViewHelpers() {
        
        // Initialize view
        $this->bootstrap('layout');
        $layout = $this->getResource('layout');
        $view = $layout->getView();

        $view->doctype('HTML5');
        $view->headMeta()->appendHttpEquiv('Content-Type', 'text/html;charset=utf-8');
        

        $view->headTitle()->setSeparator(' - ');
        $view->headTitle('SNEP');

        $view->headLink()->setStylesheet($view->baseUrl() . "/css/systemstatus.css");
        $view->headScript()->appendFile($view->baseUrl() . "/includes/javascript/snep-env.js.php", 'text/javascript');
        $view->headScript()->appendFile($view->baseUrl() . "/includes/javascript/jquery.min.js", 'text/javascript');
        //$view->headScript()->appendFile($view->baseUrl() . "/includes/javascript/geral.js", 'text/javascript');

        //List installed modules to be used on the modules menu
        $systemInfo['modules'] = array();
        $modules = Snep_Modules::getInstance()->getRegisteredModules();
        foreach ($modules as $module) {
            $systemInfo['modules'][] = array(
                "id" => $module->getModuleId(),
                "name" => $module->getName(),
                "version" => $module->getVersion(),
                "description" => $module->getDescription()
            );
        }

        $view->indexData = $systemInfo;
        // Return it, so that it can be stored by the bootstrap
        return $view;
    }

    /**
     * _initCCustos
     */
    protected function _initCCustos() {
        $db = Snep_Db::getInstance();
        $ccustos = Snep_CentroCustos::getInstance();

        $select = $db->select()
                ->from('ccustos')
                ->order("codigo");

        $stmt = $db->query($select);
        $result = $stmt->fetchAll();

        foreach ($result as $ccusto) {
            $ccustos->register(array("codigo" => $ccusto['codigo'], "nome" => $ccusto['nome']));
        }
    }

    /**
     * _initQueues
     */
    protected function _initQueues() {
        $db = Snep_Db::getInstance();
        $queues = Snep_Queues::getInstance();

        $select = $db->select()->from('queues');

        $stmt = $db->query($select);
        $result = $stmt->fetchAll();

        foreach ($result as $queue) {
            $queues->register($queue['name']);
        }
    }

    /**
     * _initLogger
     */
    protected function _initLogger() {
        $log = Snep_Logger::getInstance();

        $config = Snep_Config::getConfig();

        $writer = new Zend_Log_Writer_Stream($config->system->path->log . '/ui.log');
        // Filtramos a 'sujeira' dos logs se não estamos em debug mode.
        if (!$config->system->debug) {
            $filter = new Zend_Log_Filter_Priority(Zend_Log::WARN);
            $writer->addFilter($filter);
        }
        $log->addWriter($writer);
    }

    /*
     * _initPermission - Agendamento de verificação de permissão
     */

    protected function _initPermission() {
        $auth = Zend_Auth::getInstance();
        if ($auth->hasIdentity()) {
            $front = Zend_Controller_Front::getInstance();
            $front->registerPlugin(new Snep_PermissionPlugin());
        }
    }

}
