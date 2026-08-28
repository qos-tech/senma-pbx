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
 * @edited    TASK-0026A - default-deny rewrite, see
 *            docs/tasks/0026a-authorization-default-deny.md
 *
 */
class Snep_PermissionPlugin extends Zend_Controller_Plugin_Abstract {

    /**
     * Controllers that receive no per-permission check once a user is
     * authenticated -- every action on them is available to any logged-in
     * user, exactly as before this task, but now as an explicit, reviewed
     * allowlist instead of a side effect of the controller never having
     * been registered in resources.xml. Key: "<module>_<controller>".
     * Each entry is individually justified in
     * docs/tasks/0026a-authorization-default-deny.md.
     */
    private static $alwaysAllow = array(
        'default_index'          => true, // dashboard; open to all authenticated users (pre-existing hardcoded bypass)
        'default_auth'           => true, // login/logout/redefine/recuperation must stay reachable (pre-existing hardcoded bypass)
        'default_error'          => true, // shared error-rendering partial used by every other controller's failure paths (pre-existing hardcoded bypass)
        'default_installer'      => true, // no backing controller exists; kept only for behavioral parity with the previous bypass list
        'default_permission'     => true, // this plugin's own "access denied" landing page -- must stay reachable or every denial becomes a redirect loop
        'default_systemstatus'   => true, // TASK-0022: restartDispatchAction() is independently self-gated via Snep_Permission_Manager; index/restartStatusAction/statusbarAction are deliberately open to all authenticated users per that task's own decision
        'default_docs'           => true, // read-only local documentation viewer, no PBX/account data
        'default_information'    => true, // dashboard greeting widget ("Welcome to Snep, <user>")
        'default_newversion'     => true, // read-only vendor version-check display, content-hardened by TASK-0024/0025
        'default_notifications'  => true, // low-stakes, self-service vendor notice feed (view/dismiss only, no PBX or account data); gating it would silently break for every non-superuser profile today since profiles_permissions has zero rows
        'default_register'       => true, // read-only install/registration status display
        'default_simulator'      => true, // read-only dialplan simulation against already-existing routing rules
        'default_snep'           => true, // legacy dead redirect to "/", no real behavior
    );

    /**
     * Controllers whose only job is to serve an existing, already-registered
     * resource's page (an AJAX fragment or REST helper) under a different
     * controller name. They are authorized against the TARGET resource's
     * permission so that a user already granted the parent feature does not
     * lose the fragment it depends on. Key: "<module>_<controller>", value:
     * array($targetModule, $targetController).
     */
    private static $aliasResource = array(
        'default_khomp-links' => array('default', 'tdm-links'), // AJAX status fragment loaded from the "TDM boards" page
        'default_route-form'  => array('default', 'route'),     // REST helper (GET-only) used by the route rule editor UI
    );

    /**
     * Non-"index" actions that only ever read data, for registered
     * resources that also expose write actions. Any action not listed here
     * (and not "index") defaults to requiring the resource's "write"
     * permission -- the safe default, since it is the more restrictive of
     * the two tiers. Key: "<module>_<controller>", value: array of action
     * names.
     */
    private static $readActions = array(
        'default_audit'           => array('view'),
        'default_logs'            => array('view', 'getlogfile'),
        'default_ranking-report'  => array('view'),
        'default_services-report' => array('view'),
        'default_tdm-links'       => array('view'),
        'default_export-data'     => array('export'),
        'default_music-on-hold'   => array('file'),
    );

    public function __construct() {

    }

    /**
     * preDispatch - Verifica se o usuario tem permissão para acesso a view,
     * Se não tiver permissão é redirecionado e força o zend a finaliziar imediatamente
     *
     * TASK-0026A rewrite: the previous implementation only checked
     * permissions for a hardcoded set of seven action names
     * (index/add/remove/edit/duplicate/multiremove/multiadd) on a
     * registered resource, and silently allowed EVERYTHING else --
     * any other action name, and any controller that had no
     * resources.xml entry at all -- for any authenticated user
     * regardless of their granted permissions. See
     * docs/tasks/0026a-authorization-default-deny.md for the full
     * investigation and design.
     *
     * The model is now: explicit PUBLIC/authenticated-open allowlist,
     * then explicit alias resolution for AJAX/REST helper controllers,
     * then default DENY for anything not registered as a resource --
     * replacing the previous default ALLOW for anything not on the old
     * seven-name list.
     *
     * @param Zend_Controller_Request_Abstract $request
     * @return void
     */
    public function preDispatch(Zend_Controller_Request_Abstract $request) {

        if ($_SESSION['id_user'] == "1") {
            return; // documented superuser bypass, unchanged from before this task
        }

        $module = $request->getModuleName() ? $request->getModuleName() : "default";
        $controller = $request->getControllerName();
        $action = $request->getActionName();
        $key = $module . '_' . $controller;

        if (isset(self::$alwaysAllow[$key])) {
            return;
        }

        if (isset(self::$aliasResource[$key])) {
            list($targetModule, $targetController) = self::$aliasResource[$key];
        } else {
            $targetModule = $module;
            $targetController = $controller;
        }

        if (!isset(Snep_Modules::$resources[$targetModule][$targetController])) {
            // Fail closed: no resources.xml entry exists for this
            // controller (or its alias target) at all, under any action
            // name. Previously this silently allowed every action here.
            $this->deny();
            return;
        }

        if ($action == 'index') {
            $type = 'read';
        } elseif (isset(self::$readActions[$key]) && in_array($action, self::$readActions[$key], true)) {
            $type = 'read';
        } else {
            $type = 'write';
        }

        $resource = $targetModule . '_' . $targetController . '_' . $type;

        $group = Snep_Profiles_Manager::getIdProfile($_SESSION['id_user']);
        $result = Snep_Permission_Manager::get($group, $resource);

        $user = Snep_Permission_Manager::getUser($_SESSION['id_user'], $resource);
        // Verifica se usuario possui permissao individuais
        if ($user != false) {
            $result = $user;
        }

        if (!$result || !$result['allow']) {
            $this->deny();
        }
    }

    /**
     * deny - Redirects to the existing "access denied" page and stops
     * dispatch, exactly as this plugin already did for a permission
     * check that failed -- reused unchanged so every denial (old or
     * newly-enforced) looks identical to the user.
     *
     * @return void
     */
    private function deny() {
        $redirect = new Zend_Controller_Action_Helper_Redirector();
        $redirect->gotoSimpleAndExit("error", "permission", "default");
    }

}
