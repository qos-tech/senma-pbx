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

require_once "includes/ParseDown.php";

/**
 * Controller for users
 * 
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2018 Opens Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 * 
 */
class DocsController extends Zend_Controller_Action {

    /**
     * TASK-0026I (F28): explicit allowlist of the only documents this
     * viewer may ever serve -- request-parameter NAME (as sent by
     * index.phtml's buttons, e.g. name="changelog") mapped to the exact
     * on-disk filename under snep/docs/. Replaces free-form
     * strtoupper($key).'.md' path construction, which let a POST
     * parameter NAME containing "../" traverse outside snep/docs/
     * (contained only by the unconditional ".md" suffix). See
     * docs/tasks/0026i-disclosure-path-traversal-hardening.md.
     */
    private static $allowedDocs = array(
        'changelog'             => 'CHANGELOG.md',
        'install_guide'         => 'INSTALL_GUIDE.md',
        'practical_guide'       => 'PRACTICAL_GUIDE.md',
        'realtime_disable'      => 'REALTIME_DISABLE.md',
        'register_error'        => 'REGISTER_ERROR.md',
        'repository_snep_guide' => 'REPOSITORY_SNEP_GUIDE.md',
        'translation'           => 'TRANSLATION.md',
    );

    /**
     * Initial settings of the class
     */
     public function init() {
        $this->view->url = $this->getFrontController()->getBaseUrl() . '/' . $this->getRequest()->getControllerName();
        $this->view->lineNumber = Zend_Registry::get('config')->ambiente->linelimit;

        // Add dashboard button
        $this->view->baseUrl = Zend_Controller_Front::getInstance()->getBaseUrl();
        $this->view->key = Snep_Dashboard_Manager::getKey(Zend_Controller_Front::getInstance()->getRequest()->getModuleName(),
                                              Zend_Controller_Front::getInstance()->getRequest()->getControllerName(),
                                              Zend_Controller_Front::getInstance()->getRequest()->getActionName());

        $this->profiles = Snep_Profiles_Manager::getAll();
    }

    /**
     * indexAction - List all users
     */
    public function indexAction() {

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Documentation")));

        if ($this->_request->getPost()) {

            $data = $this->_request->getParams();
            unset($data["controller"]);
            unset($data["action"]);
            unset($data["module"]);

            // TASK-0026I (F28): $key here is a REQUEST PARAMETER NAME, not
            // a value -- it must never reach the filesystem directly.
            // Resolve it against the fixed allowlist above; any name not
            // in the map (including any traversal payload) is ignored,
            // exactly as an unrecognized button name always was.
            $docsRoot = realpath(APPLICATION_PATH . '/docs');
            foreach ($data as $key => $value) {
                if (!isset(self::$allowedDocs[$key])) {
                    continue;
                }

                $docPath = realpath($docsRoot . '/' . self::$allowedDocs[$key]);
                if ($docPath === false || strpos($docPath, $docsRoot . DIRECTORY_SEPARATOR) !== 0) {
                    continue;
                }

                $html = file_get_contents($docPath);
                $Parsedown = new Parsedown();
                $this->view->doc = $Parsedown->text($html);
            }

        }

    }

}