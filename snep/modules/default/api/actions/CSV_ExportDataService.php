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
// TASK-0026F1: table/fields/order below are identifier positions, not
// value positions -- reuses CSV_GetParamsService's own pre-existing
// table/field allowlist (the same "what is exportable" contract real API
// clients already query via service=CSV_GetParams) rather than a second,
// divergent list. See docs/tasks/0026f1-standalone-api-sql-boundary-
// hardening.md for why this does not reuse ExportDataController's own
// (private, main-MVC-bootstrap-only) allowlist instead.
require_once dirname(__FILE__) . '/CSV_GetParamsService.php';

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

        // Verify parameters -- table/fields/order are identifier
        // positions (SELECT column list, FROM table, ORDER BY column),
        // so Zend_Db parameter binding does not apply; a finite allowlist
        // is the correct control (TASK-0026F1 Phase 4). As a direct
        // consequence, an invalid/missing table or fields value now fails
        // the same allowlist check that used to be a separate, always-
        // broken $this->view->translate() call (pre-existing PHP 8.4
        // crash -- $view was never initialized in this standalone-API
        // context), which resolves that crash as a side effect.
        $table = isset($_GET['table']) ? $_GET['table'] : null;
        $validTables = CSV_GetParamsService::getAllTables();
        if (!is_string($table) || !array_key_exists($table, $validTables)) {
            error('Invalid table name.');
        }

        $validFields = array_keys(CSV_GetParamsService::getFieldsTable($table));
        $requestedFields = isset($_GET['fields']) ? explode(',', $_GET['fields']) : array();
        // array_intersect() preserves $requestedFields' own order, it
        // just drops anything not in $validFields (mirrors
        // ExportDataController::exportAction()'s own established pattern).
        $selectedFields = array_values(array_intersect($requestedFields, $validFields));
        if (empty($selectedFields)) {
            error('No fields was informed.');
        }

        $requestedOrder = isset($_GET['order']) ? $_GET['order'] : '';
        $orderField = in_array($requestedOrder, $validFields, true) ? $requestedOrder : $selectedFields[0];

        // Get table data
        $db = Zend_Registry::get('db');

        $select = $db->select()
            ->from($table, $selectedFields)
            ->order($orderField);

        $stmt = $db->query($select);
        $values = $stmt->fetchAll();

        return $values;

    }

}
        
