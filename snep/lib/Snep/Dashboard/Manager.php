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
 * Classe to manager a dashboard
 *
 * @see Snep_Dashboard_Manager
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2011 OpenS Tecnologia 
 */
class Snep_Dashboard_Manager {

    public function __construct() {
        
    }
    
    /**
     * get - Get Dashboard
     * @return <array>
     */
    public function get() {
        $db = Zend_Registry::get('db');

        $dashboard = $db->query("SELECT dashboard FROM users WHERE id='$_SESSION[id_user]'")->fetchObject();
        $array = unserialize($dashboard->dashboard);
        if (is_array($array))
            return $array;
        else
            return array();
    }
    
    /**
     * set - Set dashboard
     * @param <array> $dashboard
     */
    public function set($dashboard) {
        $modelos = Snep_Dashboard_Manager::getModelos();
        $atual = Snep_Dashboard_Manager::get();

        $special = array();
        foreach ($atual as $row) {
            if (is_array($row)) {
                $special[$row['id']] = $row;
            }
        }

        $itens_verificados = array();
        foreach ($dashboard as $value) {
            if (!is_array($value) && $value > 1000 && $special[$value])
                $value = $special[$value];
            if (is_array($value) || $modelos[$value])
                $itens_verificados[] = $value;
        }
        $db = Zend_Registry::get('db');
        $db->update("users", array('dashboard' => serialize($itens_verificados)), "id = '$_SESSION[id_user]'");
    }

    /**
     * add - Add item in the dashboard
     * @param <string> $id
     */
    public function add($id) {
        $dashboard = Snep_Dashboard_Manager::get();
        if (is_array($id)) {
            $id['id'] = time() . rand(0, 100);
            $dashboard[] = $id;
            $dashboard = Snep_Dashboard_Manager::set($dashboard);
        } else if (array_search($id, $dashboard) === FALSE) {
            $dashboard[] = $id;
            $dashboard = Snep_Dashboard_Manager::set($dashboard);
        }
    }
    
    /**
     * getModelos
     * @return type
     */
    public function getModelos() {
        
        $i18n = Zend_Registry::get("i18n");
        $xml = simplexml_load_file('configs/dashboard.xml');
        $result = Array();
        $id = 0;
        
        foreach ( $xml->children() as $child ) {
            
            foreach ( $child->children() as $child2 ) {
                
                $result[$id][$child2->getName()] = $child2;
            } 
            
            $result[$id]["nome"] = $i18n->translate(strval($result[$id]["nome"]));
            $result[$id]["descricao"] = $i18n->translate(strval($result[$id]["descricao"]));
            $id++;
        }
        

        //reads resources.xml from aditional modules
        
        $modulos = Snep_Menu::getMasterInstance()->getChildren();
        $i18n = Zend_Registry::get("i18n");
        $html = "";
        foreach($modulos as $module){
        	$explode = explode("_", $module->getId());
        	if($explode[0] != "default"){
        		
        		foreach($module->getChildren() as $item){
        			
        			
        			$result[$id]["nome"] = $i18n->translate($module->getLabel());
        			$result[$id]["descricao"] = $i18n->translate($item->getLabel());
        			$result[$id]["link"] = str_replace("/snep/index.php/".$explode[0]."/", "", $item->getUri());
        			$result[$id]["icone"] = $item->getFont();
        			$result[$id]["module"] = $explode[0];
        			$id++;

        		}
        	}
        }
        
        return $result;
    }
    
    /**
     * getArray
     * @param <string> $modelos
     * @return type
     */
    public function getArray($modelos = null) {

        $dashboard = Snep_Dashboard_Manager::get();
        $i18n = Zend_Registry::get("i18n");

        if (!$modelos)
            $modelos = Snep_Dashboard_Manager::getModelos();

        if (!is_array($dashboard) || !count($dashboard))
            return array();

        foreach ($dashboard as $key => $value) {
            if (is_array($value)) {
                $dashboard[$key] = $value;
                $dashboard[$key]["nome"] = $i18n->translate(strval($value["nome"]));
                $dashboard[$key]["descricao"] = $i18n->translate(strval($value["descricao"]));
                $dashboard[$key]["modelo"] = $value["id"];
                $dashboard[$key]["link"] = $value["link"] . "/dashboard/" . $value['id'];
            } else {
                $dashboard[$key] = $modelos[$value];
                $dashboard[$key]['modelo'] = $value;
            }
        }

        return $dashboard;
    }
    
    /**
     * getmodelosNotUsed
     * @return type
     */
    public function getModelosNotUsed() {

        $ids_key = array();
        
        $get = Snep_Dashboard_Manager::get();

        foreach ($get as $value) {

            if (!is_array($value)) {
                
                $ids_key[$value] = true;
            
                
            }
        } 
        
        return array_diff_key( Snep_Dashboard_Manager::getModelos() , $ids_key);
    }

    /**
     * getKey - Get id of action
     * @param <string> $nameModule
     * @param <string> $nameController
     * @param <string> $nameAction
     * @return <string> $key
     */
    public function getKey($nameModule,$nameController,$nameAction){

        $dashboard = self::getModelosNotUsed();
        
        foreach ($dashboard as $key => $value) {

            if (!isset($value['module'])) {

                $value['module'] = "";
            }

            if (
                    (
                    $value['module'] && $value['module'] == $nameModule || !$value['module'] && "default" == $nameModule
                    ) && (
                    FALSE !== strpos($value['link'], $nameController . "/" . $nameAction) || $nameController != "index" && $nameAction == "index" && $value['link'] == $nameController
                    )
            ) {
                return $key;
                break;
            }
        }

    }

}