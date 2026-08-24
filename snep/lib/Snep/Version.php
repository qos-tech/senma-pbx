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

    public static function getNewVersions(){
      $url = Snep_Config::getConfiguration("default","update_server");
      if($url['config_value']){
        $ctx = Snep_Request::http_context(array(), "GET");
        $request = Snep_Request::send_request($url['config_value'] . '/version/latest?version=' . SNEP_VERSION, $ctx);
        if($request['response_code'] == 200){
          $version = json_decode($request['response']);
        }else{
          return null;
        }
      }else{
        return null;
      }

      $compare = self::my_version_compare(SNEP_VERSION, $version->version);

      if($compare == -1){
        return $version->version;
      }else{
        return null;
      }

    }

    public static function getChangelog(){
      $url = Snep_Config::getConfiguration("default","update_server");
      if($url['config_value']){
        $ctx = Snep_Request::http_context(array("version" => SNEP_VERSION), "GET");
        $request = Snep_Request::send_request($url['config_value'] . '/version/latest?version=' . SNEP_VERSION, $ctx);
        $changelog = json_decode($request['response']);
        if($request['response_code'] == 200){
          $changelog = json_decode($request['response']);
          $changelog->changelog = preg_replace("/\n/","<br>", $changelog->changelog);
          return $changelog->changelog;
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
