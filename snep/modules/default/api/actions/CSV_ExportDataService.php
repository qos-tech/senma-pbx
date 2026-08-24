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

require_once '../../../includes/functions.php';

/**
 * Export Table Data Service
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2015 OpenS Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 */
class CSV_ExportDataService implements SnepService {

    /**
     * Performs the actions of the service
     * @param <String> $table - Name of table
     * @param <Array> - table field list
     * @param <String> - order by
     * @return <Array> - data of the table
     */
    public function execute() {

        // Verify parameters
        $table = $_GET['table'];
        $fields= $_GET['fields'];
        $order = $_GET['order'];
        if (!isset($table)) {
            error($this->view->translate('Invalid table name.'));
        }
        if (!isset($fields)) {
            error($this->view->translate('No fields was informed.'))  ; 
        } 
        if (!isset($order)) {
            $order = '' ;
        }

        // Get table data
        $db = Zend_Registry::get('db');

        $select = "SELECT ". $fields . " FROM " . $table . " ORDER BY " . $order;
                
        $stmt = $db->query($select);
        $values = $stmt->fetchAll();

        return $values;

    }

}
        
