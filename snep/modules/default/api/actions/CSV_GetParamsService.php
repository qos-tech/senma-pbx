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
 * Get Params to Export Table Data Service
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2015 OpenS Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 */
class CSV_GetParamsService implements SnepService {

    /**
     * Performs the actions of the service
     * @param <String> $option - table or fields
     * @param <String> $table - table name
     * @return <Array> - tables or fields of table
     */
    public function execute() {

        // Verify parameters
        $option = $_GET['option'];
        $table = (isset($_GET['table']) ? $_GET['table'] : "");
        if (!isset($option) ||  ($option != 'tables' && $option != 'fields')) {
            return array('status' => 'fail' , 'message' => 'Invalid option. Inform: table or fields.') ;
        }
        if ($option == 'fields' && !isset($table)) {
            return array('status' => 'fail' , 'message' => 'Table name not informed')   ;
        } 

        if ($option === 'tables') {
            return $this->getAllTables() ;
        } else {
            return $this->getFieldsTable($table) ;
        }


    }

    /**
     * Get list of the tables 
     * @return <Array> - list of tables
     */
    public static function getAllTables() {
        return array('users' => "Users",
                        'peers' => "Extensions",
                        'ccustos' => "Tag",
                        'trunks' => "Trunks",
                        'queues' => "Queues");
    }

    /**
     * Get fields list of the table 
     * @param string $table - name of table
     * @return <Array> - table fields
     */
    public static function getFieldsTable($table) {

        switch ($table) {
            case 'users':
                return array('id' => "Code",
                        'name' => "Name",
                        'email' => "Email",
                        'created' => "Created",
                        'updated' => "Updated");
                break;

            case 'peers':
                return array('name' => "Code",
                       'callerid' => "Callerid",
                       'dtmfmode' => "DTMF Mode",
                       'allow' => "Codec",
                       'canal' => "Channel");
                break;

            case 'ccustos' : 
                return array('codigo' => "Code",
                         'tipo' => "Type",
                         'nome' => "Name",
                         'descricao' => "Description");
                break ;

            case 'trunks' :
                return array('name' => "Code",
                        'callerid' => "Callerid",
                        'allow' => "Codecs");
                break ;

            case 'queues' : 
                return array('id' => "Code",
                        'name' => "Name",
                        'musiconhold' => "Musiconhold");
                break ;

            default :
                return array('id' => 'Table '.$table.' not found.');
                break ;
        }
    }
}
        
