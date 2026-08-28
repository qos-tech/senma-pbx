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
 * Class contain version control functions
 *
 * @see Snep_Versions
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2017 Opens Tecnologia
 * @author    Opens Tecnologia <desenvolvimentol@opens.com.br>
 *
 * PHP 8 compatibility: every call site invokes these methods statically
 * (Snep_Version::method(...)); the class is never instantiated, and no
 * method uses $this. Calling a non-static method statically is a fatal
 * Error since PHP 8.0. All methods below declared static to match actual
 * usage (TASK-0002 P1-A). See
 * docs/tasks/0002-php84-compatibility-baseline.md.
 */
class Snep_Version {

    public function __construct() {

    }

    const CACHE_TTL_SECONDS = 300;
    const SYNC_CONFIG_MODULE = 'default';
    const SYNC_CONFIG_NAME = 'update_server_synced_at';
    const VERSION_CONFIG_NAME = 'update_server_latest_version';

    /**
     * TASK-0024: getNewVersions() is called directly from
     * SystemstatusController::indexAction() -- i.e. it must never block
     * or fail System Status (and therefore the Asterisk restart
     * controls that page renders, per
     * docs/tasks/0024-external-api-failure-isolation.md §3/§26). Now
     * reads a cached "newer version, or none" result from core_config
     * (the same reused key-value table Snep_Notifications' own TTL
     * marker lives in, §5's "do not duplicate... unnecessarily" --
     * this is the small reusable pattern, not a new class) and only
     * attempts a bounded remote refresh once per CACHE_TTL_SECONDS.
     * @return <string|null> the newer version string, or null if none/unavailable
     */
    public static function getNewVersions(){
      if (!self::cacheIsStale()) {
        return self::getCachedLatestVersion();
      }

      // Same reasoning as Snep_Notifications::getAll() -- record the
      // attempt before calling out, bounding both retry frequency and
      // failure-log frequency to once per TTL window.
      Snep_Config::setConfiguration(self::SYNC_CONFIG_MODULE, self::SYNC_CONFIG_NAME, (string) time());

      $fresh = self::fetchLatestVersionFromVendor();
      if ($fresh !== false) {
        Snep_Config::setConfiguration(self::SYNC_CONFIG_MODULE, self::VERSION_CONFIG_NAME, $fresh === null ? '' : $fresh);
        return $fresh;
      }

      return self::getCachedLatestVersion();
    }

    private static function cacheIsStale() {
      $configs = Snep_Config::getConfiguration(self::SYNC_CONFIG_MODULE, self::SYNC_CONFIG_NAME);
      if (!$configs || $configs['config_value'] === '') {
        return true;
      }
      return (time() - (int) $configs['config_value']) >= self::CACHE_TTL_SECONDS;
    }

    private static function getCachedLatestVersion() {
      $configs = Snep_Config::getConfiguration(self::SYNC_CONFIG_MODULE, self::VERSION_CONFIG_NAME);
      if (!$configs || $configs['config_value'] === '') {
        return null;
      }
      return $configs['config_value'];
    }

    /**
     * fetchLatestVersionFromVendor - the original getNewVersions() body,
     * unchanged in its own success-path logic, isolated into its own
     * method. Returns `false` (never null -- null is a legitimate
     * successful "no newer version" result) on any failure: unconfigured,
     * transport failure, non-200, or a payload missing the expected
     * `version` field.
     * @return <string|null|false>
     */
    private static function fetchLatestVersionFromVendor(){
      $url = Snep_Config::getConfiguration("default","update_server");
      if(!$url || empty($url['config_value'])){
        return false;
      }
      // TASK-0024: explicit 2s bound (was the 3s default) -- this call
      // now only ever runs once per CACHE_TTL_SECONDS, matching
      // Snep_Notifications' own §12 timeout policy.
      $ctx = Snep_Request::http_context(array("timeout" => 2), "GET");
      $request = Snep_Request::send_request($url['config_value'] . '/version/latest?version=' . SNEP_VERSION, $ctx);
      if($request['response_code'] != 200){
        error_log(sprintf(
            'External integration degraded -- integration=version-check category=%s http_status=%s',
            $request['response_code'] > 0 ? 'http_status' : 'transport_failure',
            $request['response_code']
        ));
        return false;
      }
      $version = json_decode($request['response']);
      if(!is_object($version) || !isset($version->version)){
        error_log('External integration degraded -- integration=version-check category=malformed_payload http_status=' . $request['response_code']);
        return false;
      }

      $compare = self::my_version_compare(SNEP_VERSION, $version->version);

      if($compare == -1){
        return $version->version;
      }else{
        return null;
      }

    }

    // TASK-0025: changelog is vendor-controlled free text (the exact
    // same host as Snep_Notifications/Snep_Request). Before this fix
    // the only "formatting" applied was a raw \n -> <br> conversion on
    // UNESCAPED text, i.e. any HTML/script the vendor sent rendered
    // live in newversion/index.phtml's `echo $this->changelog`. The
    // product's only genuine formatting need, confirmed by reading the
    // original transform, is preserving line breaks -- not arbitrary
    // markup (docs/tasks/0025-vendor-content-xss-hardening.md §4/§12
    // default assumption: plain text). Fix: escape first
    // (htmlspecialchars, ENT_QUOTES so this is safe even if ever
    // embedded in a single-quoted context later), THEN apply nl2br() --
    // PHP's own built-in for exactly this, replacing the manual
    // preg_replace(). Intentional UX difference (§19): a vendor
    // changelog containing literal HTML (e.g. a hand-written
    // "<b>important</b>") now displays as literal visible text
    // ("<b>important</b>"), not bold -- the vendor contract never
    // promised markup support (nothing else in this integration
    // accepts formatting), so this is a narrowing to the actual,
    // already-intended behavior (line breaks only), not a feature loss.
    public static function getChangelog(){
      $url = Snep_Config::getConfiguration("default","update_server");
      if($url['config_value']){
        $ctx = Snep_Request::http_context(array("version" => SNEP_VERSION), "GET");
        $request = Snep_Request::send_request($url['config_value'] . '/version/latest?version=' . SNEP_VERSION, $ctx);
        $changelog = json_decode($request['response']);
        if($request['response_code'] == 200 && is_object($changelog) && isset($changelog->changelog)){
          $safe = htmlspecialchars((string) $changelog->changelog, ENT_QUOTES, 'UTF-8');
          return nl2br($safe);
        }else{
          return "No changelog update";
        }
      }else{
        return "No update server configured";
      }

    }

    public static function my_version_compare($ver1, $ver2, $operator = null){
        $p = '#(\.0+)+($|-)#';
        $ver1 = preg_replace($p, '', $ver1);
        $ver2 = preg_replace($p, '', $ver2);
        return isset($operator) ?
            version_compare($ver1, $ver2, $operator) :
            version_compare($ver1, $ver2);
    }

}
