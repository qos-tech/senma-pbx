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
 * Classe to manager a log rules.
 *
 * @see Snep_Route
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2014 OpenS Tecnologia
 * @author    Tiago Zimmermann <tiago.zimmermann@opens.com.br>
 * 
 */
class Snep_Route {

    public function __construct() {
        
    }

    /**
     * getRegra - Get data in the route
     * @param <int> $id - Code route
     * @return <array> $regra - data of rout
     */
    function getRegra($id) {

        $db = Zend_Registry::get("db");

        $select = $db->select()
                ->from("regras_negocio")
                ->where("regras_negocio.id = ?", $id);
        $stmt = $db->query($select);
        $regra = $stmt->fetch();

        $select = $db->select()
                ->from("regras_negocio_actions")
                ->where("regras_negocio_actions.regra_id = ?", $id);
        $stmt = $db->query($select);
        $acoes = $stmt->fetchall();

        $select = $db->select()
                ->from("regras_negocio_actions_config")
                ->where("regras_negocio_actions_config.regra_id = ?", $id);
        $stmt = $db->query($select);
        $valores = $stmt->fetchall();

        foreach ($acoes as $item => $acao) {
            foreach ($valores as $key => $valor) {

                $regra["acoes"][$item]["prio"] = $acao["prio"];
                $regra["acoes"][$item]["action"] = $acao["action"];
                if ($acao["prio"] == $valor["prio"]) {

                    $regra["acoes"][$item]["key"] .= $valor["key"] . " | ";
                    $regra["acoes"][$item]["value"] .= $valor["value"] . " | ";
                }
            }
        }
        return $regra;
    }

    /**
     * insertLogRegra - insert log on table logs_regra
     * @param <array> $add
     */
    function insertLogRegra($acao, $add) {

        $db = Zend_Registry::get("db");

        $ip = $_SERVER['REMOTE_ADDR'];
        $auth = Zend_Auth::getInstance();
        $username = $auth->getIdentity();

        if ($acao == "Adicionou Regra") {
            $valor = "ADD";
        } else if ($acao == "Excluiu Regra") {
            $valor = "DEL";
        } else {
            $valor = "DPL";
        }

        $actions_add = $add['acoes'];

        //add historico
        foreach ($actions_add as $number => $item) {

            // Pega somente nome da ação. Ex: DiscarRamal de PBX_Rule_Action_DiscarRamal
            if (strpos($item['action'], "_") !== false) {
                $action = $item['action'];
                $action = explode("_", $action);
                $action = $action[3];
            } else {
                // Ação ARS não possui PBX_Rule_Action_ no nome da ação
                $action = $item['action'];
            }

            $insert_data = array('id_regra' => $add["id"],
                'hora' => date('Y-m-d H:i:s'),
                'ip' => $ip,
                'idusuario' => $username,
                'acao' => $acao,
                'prio' => $add["prio"],
                'desc' => $add["desc"],
                'src' => $add["origem"],
                'dst' => $add["destino"],
                'validade' => $add["validade"],
                'days' => $add["diasDaSemana"],
                'record' => $add["record"],
                'ativa' => $add["ativa"],
                'action' => $action,
                'prio_action' => $item["prio"],
                'campo' => $item["key"],
                'valores' => $item["value"],
                'tipo' => $valor);

            $db->insert('logs_regra', $insert_data);
        }
    }
    
    /**
     * getLastId - get id of last route
     * @return <int> $regra - Id last route
     */
    function getLastId() {

        $db = Zend_Registry::get("db");
        
        $select = $db->select()
                ->from("regras_negocio")
                ->order("regras_negocio.id DESC")
                ->limit(1);
        $stmt = $db->query($select);
        $result = $stmt->fetch();
                        
        return $result["id"];
    }
    
    /**
     * getActions - Monta array com ações da regra
     * @param <int> $id
     * @return <array> Array de ações
     */
    function getActions($id) {

        $db = Zend_Registry::get("db");
        $sql = "SELECT action from regras_negocio_actions where regras_negocio_actions.regra_id = '$id' ";
        $stmt = $db->query($sql);
        $acao = $stmt->fetchAll();

        foreach ($acao as $item => $value) {
            $acao .= "," . $value["action"];
        }
        $exacao = explode(",", $acao);

        return $exacao;
    }

}

?>
