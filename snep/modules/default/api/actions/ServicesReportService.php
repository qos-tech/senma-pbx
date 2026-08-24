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
 * Services Report Service 
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2015 OpenS Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 */
class ServicesReportService implements SnepService {

    /**
     * Execute action
     */
    public function execute() {

    	$config = Zend_Registry::get('config');
        $db = Zend_registry::get('db');
    	
    	$fromDay = $_GET['start_date'] . " " . $_GET['start_hour'];
        $tillDay = $_GET['end_date'] . " " . $_GET['end_hour'];

        // Binds
        if(isset($_GET['clausulepeer']) && isset($_GET['clausule'])){
            
            $clausulepeer = explode("_", $_GET['clausulepeer']);
            $where_binds = '';
            
            foreach( $clausulepeer as $key => $value){
                $where_binds .= $value.","; 
            }
            $where_binds = substr($where_binds, 0,-1);

            // Not permission
            if($_GET['clausule'] == 'nobound'){ 

                $where_binds = " AND (peer NOT IN (".$where_binds."))";
                                
            }else{

                $where_binds = " AND (peer IN (".$where_binds."))";
            }
        }
    	
    	/* Get peers in group */
    	if(isset($_GET['group_select'])){

	        $groupsrc = $_GET['group_select'];
	   
	        $origens = Snep_ExtensionsGroups_Manager::getExtensionsGroup($groupsrc);
	            
	        if (count($origens) == 0) {
	            return array("status" => "fail", "message" => "No have extensions in group.");
	        } else {
	            $ramalsrc = "";
 
                foreach ($origens as $key => $ramal) {
                    $num = $ramal['name'];
                    if (is_numeric($num)) {
                        $ramalsrc .= $num . ',';
                    }
                }
                $where_options[] = " peer in (" . trim($ramalsrc, ',') . ") ";
            }	
    	} 
    	
    	if(isset($_GET['exten_select'])){
    		$extenList = explode(',', $_GET['exten_select']);
    		$extens = "";

    		foreach($extenList as $key => $value){
    			$num = $value;
                if (is_numeric($num)) {
                    $extens .= $num . ',';
                } 
    		}
    		$where_options[] = " peer in (" . trim($extens, ',') . ") ";
    	} 
 		
        //Services
        $services = array();
        if(isset($_GET['DND'])){
        	array_push($services, 'DND');
        }

		if(isset($_GET['SIGAME'])){
        	array_push($services, 'SIGAME');
        }        
		if(isset($_GET['LOCK'])){
        	array_push($services, 'LOCK');
        }        
		if(isset($_GET['SPY'])){
        	array_push($services, 'SPY');
        }        
		if(isset($_GET['REDIAL'])){
        	array_push($services, 'REDIAL');
        }        
		if(isset($_GET['WHOAMI'])){
        	array_push($services, 'WHOAMI');
        }        
		if(isset($_GET['REC'])){
        	array_push($services, 'REC');
        }        
		if(isset($_GET['RECPLAY'])){
        	array_push($services, 'RECPLAY');
        }        

        $srv = '';

        if (count($services) > 0) {

            foreach ($services as $key => $service) {
               
                $srv .= "'$service',";
            }
            $where_options[] = " service IN (" . substr($srv, 0, -1) . ")";
        }


        if($where_options){
            $where = "";
            foreach($where_options as $key => $option){
                $where .= ' AND ('.$option.') ';
            }
        }

        $selectcount = "SELECT count(*) as tot FROM services_log";
        $selectcount .= " WHERE ( date >= '$fromDay' AND date <= '$tillDay') ";
        $selectcount .= (isset($where_binds)) ? $where_binds : '';
        $selectcount .= (isset($where)) ? $where : '';

        $select = "SELECT * FROM services_log";
        $select .= " WHERE ( date >= '$fromDay' AND date <= '$tillDay') ";
        $select .= (isset($where_binds)) ? $where_binds : '';
        $select .= (isset($where)) ? $where : '';

        $stmt = $db->query($select);
        $services = $stmt->fetchAll();
        
        if(!empty($services)){
        	return array("status" => "ok", "totals" => $services, "select" => $select, "selectcount" => $selectcount);
    	}else{
    		return array("status" => "empty", "message" => "No entries found.");
    	}
    }

}
