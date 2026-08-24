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

/**
 * Class to manager a parameters.
 *
 * @see Snep_Parameters_Manager
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2014 OpenS Tecnologia
 * @author    Tiago Zimmermann <tiago.zimmermann@opens.com.br>
 *
 */
class Snep_Parameters_Manager {

    public function __construct() {

    }

    /**
     * insertParameter - insert log of trunks on table logs_trunk
     * @global <int> $id_user
     * @param <array> $add
     */
    function insertParameter($dados) {

        $db = Zend_Registry::get("db");

        $ip = $_SERVER['REMOTE_ADDR'];
        $auth = Zend_Auth::getInstance();
        $username = $auth->getIdentity();

        if ($dados["tipo"] == "OLD") {

            $insert_data = array('hora' => date('Y-m-d H:i:s'),
                'ip' => $ip,
                'idusuario' => $username,
                'emp_nome' => $dados["emp_nome"],
                'debug' => $dados["debug"],
                'ip_sock' => $dados["ip_sock"],
                'user_sock' => $dados["user_sock"],
                'mail' => $dados["email"],
                'linelimit' => $dados["linelimit"],
                'conference_app' => $dados["conference_app"],
                'application' => $dados["application"],
                'flag' => $dados["flag"],
                'path_voz' => $dados["path_voz"],
                'path_voz_bkp' => $dados["path_voz_bkp"],
                'valor_controle_qualidade' => $dados["valor_controle_qualidade"],
                'tipo' => $dados["tipo"]);

            $db->insert('logs_parametros', $insert_data);
        } else {

            $insert_data = array('hora' => date('Y-m-d H:i:s'),
                'ip' => $ip,
                'idusuario' => $username,
                'emp_nome' => $dados['general']['emp_nome'],
                'debug' => $dados['general']['debug'],
                'ip_sock' => $dados['general']['ip_sock'],
                'user_sock' => $dados['general']['user_sock'],
                'mail' => $dados['general']['mail'],
                'linelimit' => $dados['general']['linelimit'],
                'conference_app' => $dados['general']['conference_app'],
                'application' => $dados['gravacao']['application'],
                'flag' => $dados['gravacao']['flag'],
                'path_voz' => $dados['gravacao']['path_voz'],
                'path_voz_bkp' => $dados['gravacao']['path_voz_bkp'],
                'valor_controle_qualidade' => $dados['troncos']['valor_controle_qualidade'],
                'tipo' => $dados["tipo"]);

            $db->insert('logs_parametros', $insert_data);
        }
    }

    /**
     * salvaLog - Insert logs in database
     * @param <string> $acao
     * @param <string> $parameter
     * @return <boolean>
     */
    function salvaLog($acao, $parameter) {
        $db = Zend_Registry::get("db");

        $ip = $_SERVER['REMOTE_ADDR'];
        $auth = Zend_Auth::getInstance();
        $username = $auth->getIdentity();
        $acao = mysql_escape_string($acao);

        $insert_data = array('hora' => date('Y-m-d H:i:s'),
            'ip' => $ip,
            'idusuario' => $username,
            'acao' => $acao,
            'idaction' => $parameter,
            'tipo' => 3,
        );

        $db->insert('logs', $insert_data);
    }

    function change($section, $param, $value){
      $configFile = APPLICATION_PATH . "/includes/setup.conf";
      $config = new Zend_Config_Ini($configFile, null, true);
      $config->{$section}->{$param} = $value;
      $writer = new Zend_Config_Writer_Ini(array('config' => $config,
          'filename' => $configFile));
      return $writer->write();
    }

}
?>
