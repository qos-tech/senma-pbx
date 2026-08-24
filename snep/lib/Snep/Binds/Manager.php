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
 * Classe to manager a bound.
 *
 * @see Snep_Binds_Manager
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2015 OpenS Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 *
 * PHP 8 compatibility: every call site invokes these methods statically
 * (Snep_Binds_Manager::method(...)); the class is never instantiated, and
 * no method uses $this. Calling a non-static method statically is a fatal
 * Error since PHP 8.0. All methods below declared static to match actual
 * usage (TASK-0002 P1-A). See
 * docs/tasks/0002-php84-compatibility-baseline.md.
 */
class Snep_Binds_Manager {

    public function __construct() {

    }

    /**
     * getBond - Method to get user bond
     * @param <int> $id
     * @return <array> $peers
     */
    static function getBond($id) {

        $db = Zend_Registry::get("db");

        $select = $db->select()
                ->from("core_binds")
                ->where("core_binds.user_id = ?", $id);


        $stmt = $db->query($select);
        $peers = $stmt->fetchAll();

        return $peers;
    }

    /**
     * getBondException - Method to get user bond
     * @param <int> $id
     * @return <array> $peers
     */
    public static function getBondException($id) {

        $db = Zend_Registry::get("db");

        $select = $db->select()
                ->from("core_binds_exceptions")
                ->where("core_binds_exceptions.user_id = ?", $id);


        $stmt = $db->query($select);
        $exceptions = $stmt->fetchAll();

        return $exceptions;
    }


    /**
     * addBond - Method to add bond a user
     * @param <int> $id
     * @param <string> $bond
     * @param <int> $peer
     */
    public static function addBond($id,$bond,$peer) {

        $db = Zend_Registry::get('db');

        $insert_data = array('user_id' => $id,
            'peer_name' => $peer,
            'type' => $bond,
            'created' => date('Y-m-d H:i:s'),
            'updated' => date('Y-m-d H:i:s'));

        $db->insert('core_binds', $insert_data);
    }

    /**
     * addBond - Method to add bond exception a user
     * @param <int> $id
     * @param <int> $exception
     */
    public static function addBondException($id,$exception) {

        $db = Zend_Registry::get('db');

        $insert_data = array('user_id' => $id,
            'exception' => trim($exception),
            'created' => date('Y-m-d H:i:s'),
            'updated' => date('Y-m-d H:i:s'));

        $db->insert('core_binds_exceptions', $insert_data);
    }

    /**
     * removeBond - Method to remove bond a user
     * @param <int> $id
     */
    public static function removeBond($id) {

        $db = Zend_Registry::get('db');

        $db->beginTransaction();
        $db->delete('core_binds', "user_id = '$id'");

        try {
            $db->commit();
        } catch (Exception $e) {
            $db->rollBack();
        }
    }

    /**
     * removeBondByPeer - Method to remove bond a user
     * @param <int> $id
     */
    public static function removeBondByPeer($peer) {

        $db = Zend_Registry::get('db');

        $db->beginTransaction();
        $db->delete('core_binds', "peer_name = '$peer'");

        try {
            $db->commit();
        } catch (Exception $e) {
            $db->rollBack();
        }
    }

    /**
     * removeBond - Method to remove bond exception a user
     * @param <int> $id
     */
    public static function removeBondException($id) {

        $db = Zend_Registry::get('db');

        $db->beginTransaction();
        $db->delete('core_binds_exceptions', "user_id = '$id'");

        try {
            $db->commit();
        } catch (Exception $e) {
            $db->rollBack();
        }
    }

    /**
     * ResultBinds - validates array as links
     * @param <int> $id_user
     * @param <array> $row
     */
    public static function ResultBinds($id_user, $row){

    	$bond = self::getBond($id_user);

        if(!empty($bond)){
            $typeBond = $bond[0]["type"];

            // check bind user
            foreach($bond as $key => $peer){
                $binds[] = $peer["peer_name"];
            }

            foreach($row as $key => $call){
                foreach($binds as $x => $value){

                    // Allow
                    if($typeBond == 'bound'){

                        if (!in_array($call['src'], $binds)) {
                            unset($row[$key]);
                        }

                    // No allow
                    }else{

                        if($value == $call['src'] || $value == $call['dst']){
                            unset($row[$key]);
                        }
                    }
                }

            }

            return $row;
        }

        return;

    }


}