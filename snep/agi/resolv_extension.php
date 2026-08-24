#!/usr/bin/php -q
<?php
/**
 *  This file is part of SNEP.
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
 * AGI to provide extension resolution based in interface
 */


// Import AGI's configuration
require_once("agi_base.php");

if($argc != 3) {
    $asterisk->verbose("Resolv_Extension: This script need 2 arguments");
    exit(1);
}

// Search in database for peer channel
try {
    $peer = PBX_Interfaces::getChannelOwner($argv[1]);
                              
} catch (Exception $e) {
    $asterisk->verbose("[$requestid] Error in get channel owner: " . $e->getMessage(), 1);
    exit(1);
}

if ($peer instanceof Agents_Agent ) {
	$asterisk->set_variable($argv[2], $peer->getCode());
}else{	
	$asterisk->set_variable($argv[2], $peer->getNumero());
}
