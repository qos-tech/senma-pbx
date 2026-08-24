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
 * Classe to manager a Tags.
 *
 * @see Snep_CostCenter_Manager
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2011 OpenS Tecnologia
 * @author    Rafael Pereira Bozzetti <rafael@opens.com.br>
 *
 * PHP 8 compatibility: every call site invokes these methods statically
 * (Snep_CostCenter_Manager::method(...)); the class is never instantiated,
 * and no method uses $this. Calling a non-static method statically is a
 * fatal Error since PHP 8.0. All methods below declared static to match
 * actual usage (TASK-0002 P1-A). See
 * docs/tasks/0002-php84-compatibility-baseline.md.
 */
class Snep_CostCenter_Manager {

    public function __construct() {

    }

    /**
     * Method to get all cost centers
     */
    public static function getAll() {

        $db = Zend_registry::get('db');

        $select = $db->select()
                ->from("ccustos", array("codigo", "tipo", "nome", "descricao"));

        $stmt = $db->query($select);
        $allCostCenters = $stmt->fetchAll();

        return $allCostCenters;
    }

    /**
     * Method to get Tag by id
     * @param int $id
     * @return Array
     */
    public static function get($id) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from("ccustos", array("codigo", "tipo", "nome", "descricao"))
                ->where("ccustos.codigo = ?", $id);

        $stmt = $db->query($select);
        $contactGroup = $stmt->fetch();

        return $contactGroup;
    }

    /**
     * Method to add a cost center.
     * @param array $costcenter
     * @return int
     */
    public static function add($costcenter) {

        $db = Zend_Registry::get('db');

        $insert_data = array('codigo' => $costcenter['id'],
            'tipo' => $costcenter['type'],
            'nome' => $costcenter['name'],
            'descricao' => $costcenter['description']);

        $db->insert('ccustos', $insert_data);

        return $db->lastInsertId();
    }

    /**
     * Method to remove a cost center
     * @param int $id
     */
    public static function remove($id) {

        $db = Zend_Registry::get('db');

        $db->beginTransaction();
        $db->delete('ccustos', "codigo = '$id'");

        try {
            $db->commit();
        } catch (Exception $e) {
            $db->rollBack();
        }
    }

    /**
     * Method to update a cost center data
     * @param int $id
     */
    public static function edit($costcenter) {

        $db = Zend_Registry::get('db');

        $update_data = array('codigo' => $costcenter['id'],
            'tipo' => $costcenter['type'],
            'nome' => $costcenter['name'],
            'descricao' => $costcenter['description']);

        $db->update("ccustos", $update_data, "codigo = '{$costcenter['id']}'");
    }

    /**
     * Method to get Tag in cdr by id
     * @param int $id
     * @return Array
     */
    public static function getCdr($id) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from("cdr")
                ->where("cdr.accountcode = ?", $id)
                ->limit(1);

        $stmt = $db->query($select);
        $cc = $stmt->fetch();

        return $cc;
    }

}
