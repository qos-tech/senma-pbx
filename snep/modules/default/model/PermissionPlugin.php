<?php

/**
 *  This file is part of SNEP.
 *  Para território Brasileiro leia LICENCA_BR.txt
 *  All other countries read the following disclaimer
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
 * Classe para controle de Permissão
 *
 * @see Snep_Permission
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2011 OpenS Tecnologia
 * @author    Iago Uilian Berndt <iagouilian@gmail.com>
 * @edited    Tiago Zimmermann <tiago.zimmermann@opens.com.br>
 *
 */
class Snep_PermissionPlugin extends Zend_Controller_Plugin_Abstract {

    public function __construct() {

    }

    /**
     * preDispatch - Verifica se o usuario tem permissão para acesso a view,
     * Se não tiver permissão é redirecionado e força o zend a finaliziar imediatamente
     * @param Zend_Controller_Request_Abstract $request
     * @return type
     */
    public function preDispatch(Zend_Controller_Request_Abstract $request) {

        $group = Snep_Profiles_Manager::getIdProfile($_SESSION['id_user']);

        if ($_SESSION['id_user'] == "1")
            return;

        if (Snep_Permission_Manager::checkExistenceCurrentResource()) {

            if ($request->getActionName() == 'index') {
                $type = 'read';
            } else {
                $type = 'write';
            }

            if($request->getActionName() == 'index' || $request->getActionName() == 'add' || $request->getActionName() == 'remove' || $request->getActionName() == 'edit'
                || $request->getActionName() == 'duplicate' || $request->getActionName() == 'multiremove' || $request->getActionName() == 'remove' || $request->getActionName() == 'multiadd'){

                $result = Snep_Permission_Manager::get($group, ($request->getModuleName() ? $request->getModuleName() : "default") . '_' . $request->getControllerName() . '_' . $type);

                $user = Snep_Permission_Manager::getUser($_SESSION['id_user'], ($request->getModuleName() ? $request->getModuleName() : "default") . '_' . $request->getControllerName() . '_' . $type);

                // Verifica se usuario possui permissao individuais
                if ($user != false) {
                    $result = $user;
                }

                if ($request->getControllerName() == 'index' || $request->getControllerName() == 'auth' || $request->getControllerName() == 'installer' || $request->getControllerName() == 'error') {
                    return;
                }

                if (!$result) {
                    $redirect = new Zend_Controller_Action_Helper_Redirector();
                    $redirect->gotoSimpleAndExit("error", "permission","default") ;
                } elseif (!$result['allow']) {
                    $redirect = new Zend_Controller_Action_Helper_Redirector();
                    $redirect->gotoSimpleAndExit("error", "permission", "default");

                }
            }
        }
    }

}
