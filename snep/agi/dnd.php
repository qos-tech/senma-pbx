#!/usr/bin/php -q
<?php
/**
 *  This file is part of SNEP.
 *  Para território Brasileiro leia LICENCA_BR.txt
 *  All other countries read the following disclaimer
 *
 *  SNEP is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  SNEP is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with SNEP.  If not, see <http://www.gnu.org/licenses/>.
 *
 * AGIT to provide DND (Do Not Disturbe) function
 */

// Import AGI's configuration
require_once("agi_base.php");

if($argc < 2 && ($argv[1] != "enable" OR $argv[1] != "disable")) {
    $asterisk->verbose("ERROR: This script wait one parameter: enable/disable");
    exit(1);
}

$funcao = $argv[1];

$src = $request->getOriginalCallerid();

if(class_exists('Agents_Manager') ) {
	$extension = Agents_Manager::isLogged($asterisk->request['agi_callerid']);

	// Verify status for DND in agents_config
	$agents_config = Agents_Manager::getConfig() ;
	if (count($agents_config) > 0 ) {
    		$lrec = (int) $agents_config["lockRec"];
	} else {
		$lrec = 1;
	}
} else {
	$extension = $asterisk->request['agi_callerid'] ;
	$lrec = 1 ;
	$agents_config = array() ;
}
if (trim($extension) === "") {
	$extension = $src;
} 
// for Debug
# $asterisk->verbose("Status:  Funcao=$funcao // Src=$src // Extension=$extension // lrec=$lrec // agents_config=".count($agents_config)) ;

try {
	if($funcao === "enable" ) {
		if ($lrec === 1 ) { 
        		$sql = "UPDATE `peers` SET dnd=1 WHERE name='$extension'";
              		$db->query($sql);
     			// Insert LOG
       			$sql = "INSERT INTO `services_log` VALUES(NOW(), '$extension', 'DND', True, 'Nao perturbe ativado')";
       			$db->query($sql);
		}
	} else {
		if ($lrec === 1 ) { 
        		$sql = "UPDATE `peers` SET dnd=0 WHERE name='$extension'";
        		$db->query($sql);
        		// Insert LOG
        		$sql = "INSERT INTO `services_log` VALUES(NOW(), '$extension', 'DND', False, 'Nao perturbe desativado')";
        		$db->query($sql);
        	}
    	}
} catch(Exception $ex) {
    $asterisk->verbose($ex->getMessage());
    exit(1);
}
