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
 * TASK-0026G (F20): centralized CSRF enforcement for every authenticated,
 * state-changing browser request. See
 * docs/tasks/0026g-session-cookie-csrf-hardening.md for the full
 * architecture writeup; the short version:
 *
 *   - Registered in Bootstrap::_initPermission(), exactly like
 *     Snep_PermissionPlugin, ONLY when Zend_Auth::hasIdentity() is true at
 *     boot time -- so this plugin never even runs for an unauthenticated
 *     request. That structurally exempts AuthController's login/redefine/
 *     recuperation actions (the only actions reachable while
 *     unauthenticated, per Snep_AuthPlugin) without needing a hardcoded
 *     per-action exemption: there is no authenticated session yet for a
 *     forged cross-site request to abuse.
 *   - Registered AFTER Snep_PermissionPlugin (same _initPermission() call),
 *     so an unauthorized request is denied by that check first -- CSRF
 *     validity is never computed for a request that was going to be
 *     rejected anyway, matching the precedent already established by
 *     SystemstatusController::restartDispatchAction() (TASK-0022, "authz
 *     before CSRF").
 *   - Only POST requests are inspected. GET/HEAD are expected to be
 *     read-only in this application; genuinely mutating GET routes are
 *     each addressed individually (see the task doc's "state-changing
 *     GET" inventory) rather than papered over here.
 *   - No superuser bypass: unlike Snep_PermissionPlugin's user-id-1
 *     shortcut (an authorization concern), CSRF protects the request's
 *     *origin*, not the acting user's privilege level -- it applies
 *     equally to every authenticated user, superuser included.
 *
 * @category  Snep
 * @package   Snep
 */
class Snep_CsrfPlugin extends Zend_Controller_Plugin_Abstract {

    /**
     * Authenticated POST actions with their OWN pre-existing, independently
     * audited CSRF mechanism -- exempted here to avoid a field-name
     * collision/behavior change on an endpoint TASK-0021/0022 already
     * hardened and tested. Key: "<module>_<controller>_<action>". Each
     * entry must be individually justified; see the task doc.
     */
    private static $exempt = array(
        // TASK-0021/0022: its own session-bound token
        // ($_SESSION['snep_restart_csrf_token']), validated with
        // hash_equals() before this plugin existed, returning an
        // identical {"ok":false,"error":"forbidden"} JSON body on both
        // authorization AND CSRF failure by design (so a probing attacker
        // learns nothing either way). Re-pointing it at this plugin's
        // shared token/field name would change that already-verified
        // response contract for no security benefit -- see
        // docs/tasks/0026g-session-cookie-csrf-hardening.md.
        'default_systemstatus_restart-dispatch' => true,
    );

    public function __construct() {

    }

    /**
     * preDispatch - rejects an authenticated POST whose CSRF token is
     * missing or invalid, before the controller action ever runs.
     *
     * @param Zend_Controller_Request_Abstract $request
     * @return void
     */
    public function preDispatch(Zend_Controller_Request_Abstract $request) {

        if (!$request->isPost()) {
            return;
        }

        $module = $request->getModuleName() ? $request->getModuleName() : "default";
        $controller = $request->getControllerName();
        $action = $request->getActionName();
        $key = $module . '_' . $controller . '_' . $action;

        if (isset(self::$exempt[$key])) {
            return;
        }

        $token = $request->getPost(Snep_Security_Csrf::FIELD);
        if (empty($token)) {
            $token = $request->getHeader(Snep_Security_Csrf::HEADER);
        }

        if (!Snep_Security_Csrf::isValid($token)) {
            $this->reject();
        }
    }

    /**
     * reject - TASK-0026G Phase 13: deterministic HTTP 403, no token
     * value/session id/stack trace/warning in the body, never a silent
     * redirect to a success-looking page. Mirrors the codebase's own
     * established "send response, then exit" pattern
     * (Zend_Controller_Action_Helper_Redirector::redirectAndExit()) since
     * there is no clean "cancel dispatch" API in this ZF1 plugin
     * lifecycle otherwise.
     *
     * @return void
     */
    private function reject() {
        $response = $this->getResponse();
        $response->clearBody();
        $response->setHttpResponseCode(403);
        $response->setHeader('Content-Type', 'text/plain', true);
        $response->appendBody('Forbidden: missing or invalid CSRF token.');
        $response->sendResponse();
        exit;
    }

}
