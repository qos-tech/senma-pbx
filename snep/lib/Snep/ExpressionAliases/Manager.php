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
 * Class to manager a expression aliases.
 *
 * @see Snep_ExpressionAliases_Manager
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2015 OpenS Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 *
 */
class Snep_ExpressionAliases_Manager {

    public function __construct() {

    }

     /**
     * delete - Remove expression alias
     * @param <int> $id
     */
    public function delete($id) {
        $db = Zend_Registry::get('db');

        $db->delete("expr_alias", "aliasid='$id'");
    }

    /**
     * getValidation - checks if the regular expression is used in the rule
     * @param <int> $id
     * @return <array>
     */
    public function getValidation($id) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('regras_negocio', array('id', 'desc'))
                ->where("regras_negocio.origem LIKE ?", '%AL:'.$id.'%')
                ->orwhere("regras_negocio.destino LIKE ?", '%AL:'.$id.'%');

        $stmt = $db->query($select);
        $regras = $stmt->fetchall();

        return $regras;
    }
    /**
     * Method to get a Alias from id
     * @param int $id
     * @return Array
     */
    public function get($id) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
            ->from('expr_alias', array('aliasid', 'name'))
            ->where("aliasid = ?", $id);

        $stmt = $db->query($select);
        $alias = $stmt->fetch();

        return $alias;
    }

    /**
     * Method to get all Alias
     * @return Array
     */
    public function getAll() {

        $db = Zend_Registry::get('db');

        $select = $db->select()
            ->from('expr_alias') ;

        $stmt = $db->query($select);
        $alias = $stmt->fetchall();

        return $alias;
    }
}
