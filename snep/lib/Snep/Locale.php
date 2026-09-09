<?php
/**
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

require_once("Snep/Config.php");
require_once("Zend/Registry.php");
require_once("Zend/Locale.php");
require_once("Zend/Locale/Format.php");
require_once("Zend/Translate.php");
require_once("Zend/Translate/Adapter/Array.php");
require_once("Zend/Validate/Abstract.php");

define("TRANSLATIONS_PATH", APPLICATION_PATH . DIRECTORY_SEPARATOR . "lang");

/**
 * Singleton class to control the localization and internationalization features
 * of snep.
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2010 OpenS Tecnologia
 * @author    Henrique Grolli Bassotto
 */
class Snep_Locale {
    private static $supportedLanguages = array('en', 'pt_BR', 'es');

    /**
     * TASK-0034K: the $_SESSION key an anonymous/pre-auth "view this page
     * in my language" choice is stored under. Deliberately NEVER written
     * to setup.conf and NEVER passed to setExtensionsLanguage() -- see
     * resolveUiLanguage() below and AuthController::loginAction(). This is
     * a per-viewer UI preference, not the PBX_DEFAULT_CALL_LANGUAGE
     * authority (that remains setup.conf's system.language, changed only
     * through ParametersController's authenticated, CSRF-protected
     * actions). See docs/tasks/0034k-call-language-authority-pre-auth-
     * locale-hardening.md.
     */
    const UI_LANGUAGE_SESSION_KEY = 'snep_ui_language';

    public static function isSupportedLanguage($language) {
        return is_string($language) && in_array($language, self::$supportedLanguages, true);
    }

    /**
     * TASK-0034K: resolves the UI translation language for the CURRENT
     * request/viewer. A session-scoped override (set only by
     * AuthController::loginAction()'s pre-auth language links, or mirrored
     * by ParametersController when an authenticated admin changes the
     * global default -- see those callers) always wins over the
     * persisted, global setup.conf value when present and still
     * allowlisted; otherwise falls back to $configuredLanguage
     * (setup.conf's system.language, the PBX_DEFAULT_CALL_LANGUAGE
     * authority). Never consulted by setExtensionsLanguage() -- a UI-only
     * override must never influence the dialplan/call-language authority.
     *
     * @param string $configuredLanguage setup.conf's system.language
     * @return string
     */
    private static function resolveUiLanguage($configuredLanguage) {
        if (isset($_SESSION[self::UI_LANGUAGE_SESSION_KEY])
            && self::isSupportedLanguage($_SESSION[self::UI_LANGUAGE_SESSION_KEY])) {
            return $_SESSION[self::UI_LANGUAGE_SESSION_KEY];
        }
        return $configuredLanguage;
    }

    /**
     * Singleton instance.
     *
     * @return Snep_Locale
     */
    protected static $instance;

    /**
     * The current system locale
     * 
     * @var string locale
     */
    protected $locale;

    /**
     * The current system language
     *
     * @var string language
     */
    protected $language;

    /**
     * Current system Timezone
     *
     * @var string timezone
     */
    protected $timezone;

    /**
     * The Zend Translate object for string translations.
     *
     * @var Zend_Translate
     */
    protected $zendTranslate;

    /**
     * Zend Locale object for locale management.
     *
     * @var Zend_Locale
     */
    protected $zendLocale;

    /**
     * @var array Available languages
     */
    protected $availableLanguages = array();

    /**
     * Returns the singleton instance of this class.
     *
     * @return Snep_Locale
     */
    public static function getInstance() {
        if(!isset(self::$instance)) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    public function __construct() {
        $config = Snep_Config::getConfig();
        $locale = $this->locale = $config->system->locale;
        $language = $this->language = self::resolveUiLanguage($config->system->language);
        $timezone = $this->timezone = $config->system->timezone;

        if(!Zend_Locale::isLocale($locale)) {
            throw new Exception("Fatal: '$locale' is not a valid locale", 500);
        }

        setlocale(LC_COLLATE, $locale . ".utf8");
        Zend_Locale::setDefault($locale);
        $this->zendLocale = $zendLocale = new Zend_Locale($locale);
        Zend_Registry::set('Zend_Locale', $zendLocale);
        Zend_Locale_Format::setOptions(array("locale"=> $locale));

        if(!Zend_Locale::isLocale($language)) {
            throw new Exception("Fatal: '$language' is not a valid language locale", 500);
        }

        if( !self::isTimezone($timezone) ) {
            throw new Exception("Fatal: '$timezone' is not a valid timezone", 500);
        }
        date_default_timezone_set($timezone);

        $language_alt = substr($language, 0, strpos($language, "_"));
        if(file_exists(TRANSLATIONS_PATH . DIRECTORY_SEPARATOR . "$language.mo")) {
            $translate = new Zend_Translate('gettext', TRANSLATIONS_PATH . DIRECTORY_SEPARATOR . "$language.mo", $language);
        }
        else if(file_exists(TRANSLATIONS_PATH . DIRECTORY_SEPARATOR . "$language_alt.mo")) {
            $translate = new Zend_Translate('gettext', TRANSLATIONS_PATH . DIRECTORY_SEPARATOR . "$language_alt.mo", $language);
        }
        else {
            $translate = new Zend_Translate('gettext', null, $language);
        }

        $this->zendTranslate = $translate;
        Zend_Registry::set("Zend_Translate", $translate);

        $lang_dirs = scandir(TRANSLATIONS_PATH . "/Zend_Validate/");
        if(in_array($language, $lang_dirs)) {
            $validate_locale = $language;
        }
        else if(in_array($language_alt, $lang_dirs)) {
            $validate_locale = $language_alt;
        }
        else {
            $validate_locale = "us";
        }

        $zend_validate_translator = new Zend_Translate_Adapter_Array(
            TRANSLATIONS_PATH . "/Zend_Validate/$validate_locale/Zend_Validate.php",
            $language
        );
        Zend_Validate_Abstract::setDefaultTranslator($zend_validate_translator);
    }

    /**
     * Assert if a timezone identifier is valid or not.
     *
     * @param string $timezone Timezone identifier
     * @return boolean is timezone
     */
    public static function isTimezone($timezone) {
        return key_exists($timezone, Zend_Locale::getTranslationList("territorytotimezone"));
    }

    /**
     * @return string System locale identifier
     */
    public function getLocale() {
        return self::$instance->locale;
    }

    /**
     * @return string System language identifier
     */
    public function getLanguage() {
        return $this->language;
    }

    /**
     * @return string System timezone identifier
     */
    public function getTimezone() {
        return $this->timezone;
    }

    /**
     * @return Zend_Translate Default system translator
     */
    public function getZendTranslate() {
        return $this->zendTranslate;
    }

    /**
     * @return Zend_Locale Default system locale
     */
    public function getZendLocale() {
        return $this->zendLocale;
    }

    /**
     * Return all the languages available on the system.
     *
     * @return array available languages
     */
    public function getAvailableLanguages() {
        if (count($this->availableLanguages) === 0) {
            foreach( scandir(TRANSLATIONS_PATH) as $filename ) {
                if( preg_match("/.*\.mo$/", $filename) ) {
                    $this->availableLanguages[] = basename($filename, '.mo');
                }
            }
        }
        return $this->availableLanguages;
    }

    /**
     *  Adjuste Asterisk GLOBAL variable for Language
     * @param <string> $lang - Language
     *
     * PHP 8 compatibility (TASK-0002 P1-B): Snep_Locale is an overall
     * stateful singleton (locale/language/timezone set in __construct()),
     * but this one method uses no $this/self::$instance -- it only shells
     * out and talks to the separate PBX_Asterisk_AMI singleton. Verified
     * and declared static to match its existing :: call sites
     * (AuthController.php, ParametersController.php). See
     * docs/tasks/0002-php84-compatibility-baseline.md.
     *
     * TASK-0034K: this is the ONE supported mechanism that mutates the
     * global PBX_DEFAULT_CALL_LANGUAGE authority (setup.conf's
     * system.language propagated into extensions.conf's SNEP_LANGUAGE
     * global, then a live Asterisk dialplan reload). Two changes from the
     * original implementation:
     *   1. hasIdentity() guard -- structural enforcement that this can
     *      only ever run for an authenticated caller, so a future call
     *      site added without first checking auth fails closed instead of
     *      silently reopening the pre-auth global-mutation defect this
     *      task closes (AuthController::loginAction() no longer calls
     *      this at all -- see its own docblock).
     *   2. the extensions.conf rewrite is now an in-place
     *      file_get_contents()/file_put_contents() pair instead of a
     *      shelled-out `sed ... > file.dpkg-new; mv file.dpkg-new file`.
     *      Root cause: that temp-file+rename pattern needs *directory*
     *      write permission on /etc/asterisk, which TASK-0009 deliberately
     *      never grants www-data (only /etc/asterisk/snep is
     *      senma-config-group-writable, by design -- see
     *      docker/asterisk-entrypoint.sh). It silently no-oped under every
     *      Docker topology this method has ever shipped with (confirmed
     *      live: `exec()`'s return value/stderr were never checked, so the
     *      permission-denied sed/mv failure was never surfaced -- see
     *      docs/tasks/0034k-call-language-authority-pre-auth-locale-
     *      hardening.md's pre-auth reproduction). An in-place rewrite of
     *      an already-existing file only needs *file* write permission,
     *      which docker/asterisk-entrypoint.sh now grants narrowly (same
     *      chgrp senma-config/chmod 664 pattern already used for
     *      $ASTERISK_ETC/snep/*.conf) without widening the rest of
     *      /etc/asterisk -- preserving TASK-0009's boundary. Failures are
     *      now also reported (bool return) instead of swallowed.
     *
     * @param string $lang
     * @return bool true if the language was validated, persisted and
     *   propagated; false otherwise (unsupported value, no authenticated
     *   identity, or the extensions.conf rewrite failed).
     */
    public static function setExtensionsLanguage($lang) {
        if (!self::isSupportedLanguage($lang)) {
            return false;
        }
        if (!Zend_Auth::getInstance()->hasIdentity()) {
            return false;
        }

        $config = "/etc/asterisk/extensions.conf";
        $contents = file_get_contents($config);
        if ($contents === false) {
            return false;
        }

        $updated = preg_replace('/^SNEP_LANGUAGE *=.*$/m', 'SNEP_LANGUAGE=' . $lang, $contents, 1, $replacements);
        if ($updated === null || $replacements !== 1) {
            return false;
        }

        if (file_put_contents($config, $updated) === false) {
            return false;
        }

        // Forcing asterisk to reload the configs
        $asteriskAmi = PBX_Asterisk_AMI::getInstance();
        $asteriskAmi->Command("dialplan reload");

        return true;
    }

     /**
     * Returns the locale in datepicker format
     *
     * @param <string>  Zend locale
     * @return <string> Date Picker Locale
     */
    public static function getDatePickerLocale($locale) {
        switch ($locale) {
            case "pt_BR":
                return "pt-br";
                break;
            case "es" :
                return "es";
                break;
            default :
                return "";
                break;

        }
    }

    protected function __clone() {}
}
