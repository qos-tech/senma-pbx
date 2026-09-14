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
        // Dashboard GET (and the pre-ITC-registration interstitial GET) stay
        // open to every authenticated user. TASK-0034O: POST mutations on
        // indexAction (ITC register/confirm/login/opensnep/noregister) are
        // NOT covered by this bypass anymore -- see $writeOnPostIndex.
        'default_index'          => true,
        'default_auth'           => true, // login/logout/redefine/recuperation must stay reachable (pre-existing hardcoded bypass)
        'default_error'          => true, // shared error-rendering partial used by every other controller's failure paths (pre-existing hardcoded bypass)
        'default_installer'      => true, // no backing controller exists; kept only for behavioral parity with the previous bypass list
        'default_permission'     => true, // this plugin's own "access denied" landing page -- must stay reachable or every denial becomes a redirect loop
        'default_systemstatus'   => true, // TASK-0022: restartDispatchAction() is independently self-gated via Snep_Permission_Manager; index/restartStatusAction/statusbarAction are deliberately open to all authenticated users per that task's own decision
        'default_docs'           => true, // read-only local documentation viewer, no PBX/account data
        'default_information'    => true, // dashboard greeting widget ("Welcome to Snep, <user>")
        'default_newversion'     => true, // read-only vendor version-check display, content-hardened by TASK-0024/0025
        // TASK-0034P: authenticated-open READ of the shared vendor-notice
        // feed only. Mutations (mark-read / remove) are NOT covered by this
        // bypass anymore -- see $writeActionsOnAlwaysAllow. The previous
        // "self-service dismiss" claim was factually wrong: core_notifications
        // has no user_id, and setRead/removeNotification key the vendor API
        // on the installation $_SESSION['uuid'], so dismiss is shared
        // PBX-wide state, not per-user acknowledgement.
        'default_notifications'  => true,
        // ITC registration status page: GET remains authenticated-open so
        // any logged-in user can view status. TASK-0034O corrected the
        // previous "read-only" claim -- POST (and the former GET-side
        // distribution rewrite, now removed from GET) require
        // default_register_write via $writeOnPostIndex.
        'default_register'       => true,
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

    /**
     * TASK-0034L: controllers whose "index" action ALSO processes a
     * mutating POST -- not a read-only filter/search submission -- so
     * "index" cannot blanket-default to 'read' for them the way it safely
     * does everywhere else. Checked ONLY when the actual request is a
     * POST; a GET to the same action is still 'read', identical to every
     * other controller's index action, completely unchanged. Key:
     * "<module>_<controller>".
     *
     * ParametersController::indexAction()'s POST branch rewrites
     * setup.conf (13+ fields, including DB and AMI credentials) and
     * propagates the PBX call language via
     * Snep_Locale::setExtensionsLanguage() -- confirmed live-reachable by
     * a user granted only default_parameters_read (TASK-0034J's D3
     * follow-up finding; see docs/tasks/0034l-parameters-controller-
     * authorization-boundary-hardening.md). default_parameters_write
     * already exists and is already correctly required by
     * ParametersController::languageAction() (added by TASK-0026A
     * specifically for that sibling action -- see resources.xml's own
     * comment on the "parameters" resource) -- reused here, not a new
     * permission.
     *
     * Deliberately NOT a blanket "POST to any index action requires
     * write" rule: a full-repo scan (TASK-0034L) found many other
     * controllers whose indexAction() also reads $_request->getPost()
     * (reports/audit/logs/etc.), but only ever as a read-only filter/
     * search submission -- none evidenced as a real mutation, and
     * reclassifying them without individually verifying each one first
     * was explicitly out of this task's scope (would risk locking
     * existing read-permission users out of legitimate filter/search
     * forms). Adding a controller here must be individually justified,
     * the same way each entry in $readActions above already is.
     *
     * TASK-0034M: docs/tasks/0034m-controller-write-authorization-audit-
     * cnl-boundary-hardening.md re-audited every remaining
     * indexAction()+POST controller (precisely 17, confirmed by scanning
     * strictly within each indexAction() function body, not merely
     * anywhere in the file) and found four more with this exact
     * read-implies-write shape -- each is its own narrow, individually
     * justified entry below, using the corresponding resources.xml
     * "write" child (added alongside "parameters"'s, or already present
     * for "conference-rooms"). Every other indexAction()+POST controller
     * audited by that task (audit/calls-report/docs/export-data/khomp-
     * links/logs/ranking-report/services-report/simulator/tdm-links) was
     * verified to be read-only filter/search/report/navigation/simulation
     * with no persistent or runtime mutation, and is deliberately NOT
     * listed here.
     */
    private static $writeOnPostIndex = array(
        'default_parameters' => true,
        // CnlController::indexAction()'s POST branch (country=76) imports
        // a dialing-prefix ZIP into core_cnl_state/core_cnl_city/
        // core_cnl_prefix -- a real DB mutation. Identified as concrete
        // FOLLOW_UP_DEBT by TASK-0034L; closed here.
        'default_cnl' => true,
        // ModuleSettingsController::indexAction()'s POST branch writes
        // arbitrary module configuration rows (Snep_ModuleSettings_
        // Manager::addConfig()/updateConfig()), including SMTP
        // credentials -- a real DB mutation, same shape as "cnl".
        'default_module-settings' => true,
        // ErrorsKhompController::indexAction()'s POST branch clears the
        // live Khomp links-errors AMI counters (AsteriskInfo::
        // status_asterisk("khomp links errors clear", ...)) -- a real
        // runtime/telephony mutation, same shape as "cnl". Consulted:
        // senma-telephony-architect (no PJSIP/chan_sip implication --
        // Khomp is TDM hardware; no reload/runtime-contract change, only
        // the caller's authorization boundary is tightened).
        'default_errors-khomp' => true,
        // ErrorsTdmController::indexAction()'s POST branch mirrors
        // ErrorsKhompController's AMI clear-counters mutation exactly --
        // same reason, same telephony-architect consultation.
        'default_errors-tdm' => true,
        // ConferenceRoomsController::indexAction()'s POST branch rewrites
        // /etc/asterisk/snep/snep-conferences.conf and
        // snep-authconferences.conf directly (conference room definitions
        // and MD5 lock passwords, both read by the dialplan) -- a real
        // file/telephony-config mutation. Unlike the others above, this
        // resource ALREADY had an explicit "write" child (pre-existing,
        // unused by this action); no resources.xml change was needed,
        // only this classification entry. Consulted: senma-telephony-
        // architect (no runtime-contract change; only the caller's
        // authorization boundary is tightened).
        'default_conference-rooms' => true,
        // TASK-0034O: IndexController::indexAction()'s POST branch (while
        // $_SESSION['registered']!=true && $_SESSION['noregister']!=true)
        // writes system-wide ITC vendor-registration state via
        // Snep_Register_Manager::registerITC()/addDistributions()/
        // noregister() and Snep_Notifications::addNotification(). The
        // controller is on $alwaysAllow (dashboard GET must stay open to
        // every authenticated user); this entry exists so the alwaysAllow
        // short-circuit below still demands default_index_write for POST.
        // default_index had no write child before this task -- added in
        // resources.xml alongside this entry. Empty grants + non-superuser
        // => deny (same fresh-install shape as parameters/cnl).
        'default_index' => true,
        // TASK-0034O: RegisterController::indexAction()'s POST branch
        // re-authenticates against the vendor ITC and rewrites
        // itc_register api/client keys plus itc_consumers rows. Same
        // alwaysAllow + writeOnPostIndex shape as default_index above.
        // The previous $alwaysAllow comment ("read-only") was factually
        // wrong; GET no longer mutates (controller change in this task).
        'default_register' => true,
    );

    /**
     * TASK-0034P: alwaysAllow controllers whose specific non-index
     * actions still mutate shared/global state and therefore must demand
     * the matching "<module>_<controller>_write" grant. Values are the
     * action names Zend may report for the route (hyphenated URL form
     * and the compressed coverage-inventory form). Controllers listed
     * here remain authenticated-open for every action NOT named below
     * (notifications index GET stays open). Same fall-through shape as
     * $writeOnPostIndex above.
     *
     * Key: "<module>_<controller>", value: list of action names.
     */
    private static $writeActionsOnAlwaysAllow = array(
        // Shared vendor-notice board: local core_notifications is a
        // PBX-wide cache (no user ownership column); vendor mutations
        // use the installation ITC uuid. Any authenticated zero-grant
        // user previously could mark-read/delete notices for everyone.
        'default_notifications' => array('mark-read', 'markread', 'remove'),
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

        // TASK-0034O/P: $alwaysAllow still means "any authenticated user
        // may REACH this controller" for ordinary GET/read traffic, but
        // opt-in write gates can still require write for:
        //   - POST to index ($writeOnPostIndex, TASK-0034O), or
        //   - named mutating actions ($writeActionsOnAlwaysAllow, TASK-0034P).
        // Controllers on $alwaysAllow not listed in either map remain
        // fully open when authenticated (docs, simulator, etc.).
        if (isset(self::$alwaysAllow[$key])) {
            $writeOnPostIndex = ($action == 'index' && $request->isPost()
                && isset(self::$writeOnPostIndex[$key]));
            $writeNamedAction = (isset(self::$writeActionsOnAlwaysAllow[$key])
                && in_array($action, self::$writeActionsOnAlwaysAllow[$key], true));
            if (!$writeOnPostIndex && !$writeNamedAction) {
                return;
            }
            // Fall through: classify as write and enforce below.
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

        if ($action == 'index' && $request->isPost() && isset(self::$writeOnPostIndex[$key])) {
            // TASK-0034L: see $writeOnPostIndex's own docblock above.
            // TASK-0034O: also reached for alwaysAllow controllers that
            // opted into $writeOnPostIndex (default_index / default_register).
            $type = 'write';
        } elseif ($action == 'index') {
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
