<?php
/*
 *  This file is part of SNEP.
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

require_once 'Zend/Controller/Action.php';

/**
 * Authentication Controller
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2014 OpenS Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 */
class AuthController extends Zend_Controller_Action {

    /**
     * loginAction - Login on system
     */
    public function loginAction() {


        $this->view->headTitle($this->view->translate("Login"));
        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Login")));
        $this->view->hideMenu = true;
        $this->view->PAGE = "{$this->getFrontController()->getBaseUrl()}/{$this->getRequest()->getModuleName()}/{$this->getRequest()->getControllerName()}/redefine";

        $config = Zend_Registry::get('config');
        $this->view->language = $config->system->language;
        if (isset($_GET["recuperation"])) {
            $this->view->message = $this->view->translate("Password successfully recovered");
            $this->view->msgclass = 'sucess';
        }



         if (isset($_GET["indexChooseLanguage"]) && Snep_Locale::isSupportedLanguage($_GET["indexChooseLanguage"])) {

            $configFile = APPLICATION_PATH . "/includes/setup.conf";
            $config = new Zend_Config_Ini($configFile, null, true);
            $config->system->language = $_GET["indexChooseLanguage"];
            $writer = new Zend_Config_Writer_Ini(array('config' => $config,
                'filename' => $configFile));
            $writer->write();

            Snep_Locale::setExtensionsLanguage($_GET["indexChooseLanguage"]) ;

            $this->_redirect('/');

         }


        // If you are already logged
        $auth = Zend_Auth::getInstance();
        if ($auth->hasIdentity()) {
            $this->_redirect('/');
        }

        if ($this->_request->isPost()) {

            // Filter information of user
            $f = new Zend_Filter_StripTags();
            $username = $f->filter($this->_request->getPost('user'));
            $password = $this->_request->getPost('password');
            // TASK-0026H (F22): REMOTE_ADDR, matching the exact same
            // convention SystemstatusController::logRestartAuthorizationDenied()
            // already established for this codebase.
            $ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';

            // TASK-0026H: previously merged with "user not found" below
            // (empty($username) || empty($case)), which made "unknown
            // user" and "blank username field" produce a DIFFERENT
            // message than "wrong password" -- a username-enumeration
            // oracle. This branch now only ever fires for a genuinely
            // blank submission, unrelated to whether any user exists.
            if ($username === '' || $username === null) {
                $this->view->message = $this->view->translate("Please enter a username");
                $this->view->msgclass = 'failure';
            } else {
                $db = Zend_Registry::get('db');

                // TASK-0026H (F22): must run BEFORE credential
                // verification -- a throttled request never computes a
                // password comparison at all.
                if (Snep_Security_LoginThrottle::isThrottled($db, $username, $ip)) {
                    $this->view->message = $this->view->translate('Too many failed login attempts. Please try again later.');
                    $this->view->msgclass = 'failure';
                } else {

                    // TASK-0026H (F21): Zend_Auth_Adapter_DbTable compared
                    // the credential in SQL ("WHERE password = ?"), which
                    // only ever worked for a deterministic hash like
                    // md5(). password_hash()'s salted, non-deterministic
                    // output must be verified in PHP instead -- see
                    // Snep_Auth_Adapter_Password's own docblock. This
                    // adapter also absorbs the case-sensitive identity
                    // lookup Snep_Acl::getCaseSensitive() used to do as a
                    // separate pre-check.
                    $authAdapter = new Snep_Auth_Adapter_Password($db, $username, $password);

                    // Autentication
                    $auth = Zend_Auth::getInstance();
                    $result = $auth->authenticate($authAdapter);

                    switch ($result->getCode()) {
                        case Zend_Auth_Result::FAILURE_IDENTITY_NOT_FOUND:
                        case Zend_Auth_Result::FAILURE_CREDENTIAL_INVALID:
                            // TASK-0026H (F22): identical outcome/message
                            // for "unknown user" and "wrong password" --
                            // see the enumeration note above.
                            Snep_Security_LoginThrottle::recordFailure($db, $username, $ip);
                            $this->view->message = $this->view->translate('User or password invalid');
                            $this->view->msgclass = 'failure';
                            break;
                        case Zend_Auth_Result::SUCCESS:
                            // TASK-0026H (F22): a legitimate login clears
                            // this (ip, username) pair's own failure
                            // history -- see Snep_Security_LoginThrottle's
                            // own docblock for why the broader per-IP
                            // counter is deliberately left alone here.
                            Snep_Security_LoginThrottle::clearAccount($db, $username, $ip);

                            $auth->getStorage()->write($result->getIdentity());

                            // TASK-0026G (F18): a session identifier the client
                            // held BEFORE authenticating must never remain valid
                            // as the AUTHENTICATED session identifier afterward
                            // -- this was live-proven exploitable as a full
                            // admin-account-takeover session-fixation path (see
                            // docs/tasks/0026-pre-pilot-security-release-audit.md
                            // F18). Zend_Session::regenerateId() is this
                            // codebase's own wrapper around
                            // session_regenerate_id(true): it keeps the
                            // just-written identity/session data but swaps the
                            // id and invalidates the old one server-side. Called
                            // here, before any output has been sent, per that
                            // method's own requirement. Never called on
                            // ordinary authenticated requests -- only here, once
                            // per successful login.
                            Zend_Session::regenerateId();
                            // TASK-0026G (F20): mint a fresh CSRF token bound to
                            // the NEW session id, so nothing pre-login could
                            // have seeded a token an attacker already knows.
                            Snep_Security_Csrf::rotate();

                            // TASK-0026H (F8-class SQLi, same code block
                            // being rewritten): was raw string
                            // interpolation of $username into SQL syntax.
                            $extension = $db->fetchRow(
                                $db->select()->from('users', array('id', 'name'))->where('name = ?', $username)
                            );
                            // TASK-0026H (Password handling invariant):
                            // this codebase's own AES-encrypted-plaintext
                            // session fields ($_SESSION['ENCRYPTION_KEY'],
                            // $_SESSION['http_authorization'], "Retaining
                            // the old verifica.php") persisted the
                            // plaintext password outside the hash (a
                            // reversible cipher whose key was ALSO stored
                            // in the same session) and had no reader
                            // anywhere else in the current codebase
                            // (confirmed by a full-repo grep) -- removed
                            // rather than carried forward.
                            $_SESSION['id_user'] = $extension['id'];
                            $_SESSION['name_user'] = $username;
                            $_SESSION['active_user'] = $extension['name'];
                            $_SESSION['vinculos_user'] = "";

                            $registered = $db->query("SELECT uuid,registered_itc,noregister FROM itc_register")->fetch();

                            $_SESSION['registered'] = $registered['registered_itc'];
                            $_SESSION['uuid'] = $registered['uuid'];
                            $_SESSION['noregister'] = $registered['noregister'];

                            if(!isset($_SESSION['uuid'])){

                                $v4uuid = self::v4();
                                $_SESSION['uuid'] = $v4uuid;
                                Snep_Auth_Manager::adduuid($v4uuid);

                            }

                            $this->_redirect('/');
                            break;
                        default:
                            Snep_Security_LoginThrottle::recordFailure($db, $username, $ip);
                            $this->view->message = $this->view->translate('Authentication failure');
                            $this->view->msgclass = 'failure';
                            break;
                    }
                }
            }
        }

        $layout = Zend_Layout::getMvcInstance();
        $layout->setLayout('login');

    }

    /**
     * v4 - Create hash uuidV4
     */
    public static function v4() {

        return sprintf('%04x%04x-%04x-%04x-%04x-%04x%04x%04x',

          // 32 bits for "time_low"
          mt_rand(0, 0xffff), mt_rand(0, 0xffff),

          // 16 bits for "time_mid"
          mt_rand(0, 0xffff),

          // 16 bits for "time_hi_and_version",
          // four most significant bits holds version number 4
          mt_rand(0, 0x0fff) | 0x4000,

          // 16 bits, 8 bits for "clk_seq_hi_res",
          // 8 bits for "clk_seq_low",
          // two most significant bits holds zero and one for variant DCE1.1
          mt_rand(0, 0x3fff) | 0x8000,

          // 48 bits for "node"
          mt_rand(0, 0xffff), mt_rand(0, 0xffff), mt_rand(0, 0xffff)
        );
    }

    /**
     * recuperationAction - Recuperation of password
     */
    public function recuperationAction() {

        $this->view->headTitle($this->view->translate("Password Recovery"));
        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Password Recovery")));
        $this->view->hideMenu = true;

        $layout = Zend_Layout::getMvcInstance();
        $layout->setLayout('login');

        if (isset($_GET['param'])) {
            $this->view->msgclass = 'sucess';
            $this->view->message = $this->view->translate("We've sent an access code to the email:" ). base64_decode($_GET['param']);
        }

        if ($this->_request->isPost()) {

            $data = array();
            $data['user'] = $_POST['username'];
            $data['password'] = $_POST['password'];
            $data['newpassword'] = $_POST['newpassword'];
            $data['code'] = $_POST['code'];


            if (Snep_Auth_Manager::getUser($data['user']) == false) {
                $this->view->msgclass = 'failure';
                $this->view->message = $this->view->translate("User not registered");
            } else {

                if ($data['password'] != $data['newpassword']) {
                    $this->view->msgclass = 'failure';
                    $this->view->message = $this->view->translate("Passwords do not match");
                } elseif (!Snep_Security_Password::meetsMinimumLength($data['newpassword'])) {
                    // TASK-0026H (F21, Phase 14): server-side enforcement,
                    // same policy as UsersController's add/edit paths.
                    $this->view->msgclass = 'failure';
                    $this->view->message = $this->view->translate("Password must be at least 8 characters.");
                } else {
                    $recuperation = Snep_Auth_Manager::getPassword($data['user']);

                    if ($data['code'] != $recuperation["code"]) {
                        $this->view->msgclass = 'failure';
                        $this->view->message = $this->view->translate("Code invalid");
                    } else {
                        $date = date("Y-m-d H:i:s");
                        $expiration = $recuperation["expiration"];
                        if (strtotime($date) > strtotime($expiration)) {
                            $this->view->msgclass = 'failure';
                            $this->view->message = $this->view->translate("Time of validity of the code was expired");
                        } else {

                            Snep_Auth_Manager::getUpdatePass($data);
                            $this->_redirect("auth/login?recuperation=yes");
                        }
                    }
                }
            }
        }
    }

    /**
     * refefineAction - Redefine password
     */
    public function redefineAction() {

        $this->view->headTitle($this->view->translate("Password Recovery"));
        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Password Recovery")));
        $this->view->hideMenu = true;
        $this->view->msgclass = 'failure';

        $layout = Zend_Layout::getMvcInstance();
        $layout->setLayout('login');

        if ($this->_request->isPost()) {

            $username = $_POST["username"];

            $user = Snep_Auth_Manager::getUser($username);
            $date = date("Y-m-d H:i:s");

            if ($user == false) {
                $this->view->message = $this->view->translate("User not registered");
            } else {

                $user['code'] = $this->aleatorio();
                $user['expiration'] = date('Y-m-d H:i:s', strtotime('+1 hour', strtotime($date)));
                Snep_Auth_Manager::addCode($user);

                $code = $user['code'];
                $expiration = date('d/m/Y G:i:s', strtotime($user['expiration']));
                $config = Zend_Registry::get('config');
                $client = $config->ambiente->emp_nome;

                $msg = $this->view->translate("You asked for resetting your password the user <b>").$username;
                $msg .= $this->view->translate("</b> on PABX <b>").$client;
                $msg .= $this->view->translate("</b>.<br><br>Need to enter the code below for the redefinition.<br>Access code : <font color= red><b>") . $code;
                $msg .= $this->view->translate("</b></font><br>Your code will expire on: ") . $expiration;
                $msg .= $this->view->translate("<br><br>If you have not requested a redefinition password, please disregard<br><br><i>Team Snep</i>.");

                $subject = $this->view->translate("Redefinition password - SNEP");

                Snep_Auth_Manager::sendEmail($user, $msg, $subject);
                $mail = base64_encode($user['email']);
                $this->_redirect('/auth/recuperation?param=' . $mail);
            }
        }
    }

    /**
     * aleatorio - Riding a random code
     * @return <string>
     */
    public function aleatorio() {
        // TASK-0026H (F23): was srand((double) microtime() * 1000000)
        // seeding rand() -- a legacy, non-cryptographic PRNG whose seed
        // is theoretically narrowable by an attacker who can measure
        // request timing. random_int() is cryptographically secure and
        // has been available since PHP 7.
        $key = "";
        $valor = "ABCDEFGHJKLMNOPQRSTUVWXYZ0123456789";
        $max = strlen($valor) - 1;
        for ($i = 0; $i < 6; $i++) {
            $key .= $valor[random_int(0, $max)];
        }
        return $key;
    }

    /**
     * logoutAction - Logoff on system
     */
    public function logoutAction() {
        if (Zend_Auth::getInstance()->hasIdentity()) {
            Zend_Auth::getInstance()->clearIdentity();
        }
        // TASK-0026G (F18): clearIdentity() above only removes Zend_Auth's
        // own storage namespace within the session -- the rest of
        // $_SESSION (id_user, name_user, http_authorization, the CSRF
        // token, ...) would otherwise survive logout. Destroying the whole
        // session (and its cookie) here means the pre-logout session
        // identifier cannot be reused for anything afterward, not just
        // "no longer has an identity". Must run before any output --
        // Zend_Session::destroy() sends an expired Set-Cookie -- so this
        // stays before the inline <script> below.
        Zend_Session::destroy();
        ?>
        <script>
        clearInterval(system_status_interval); // That's 60 seconds
        </script>
        <?php
        $this->_redirect("/");
    }


}
