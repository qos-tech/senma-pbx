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
 * AGI to provide channel resolution of the extension
 */

// Import AGI's configuration
require_once("agi_base.php");

if($argc != 3) {
    $asterisk->verbose("resolv_interface: the script wait 2 parameters: extension and variable");
    exit(1);
}

// Search peer in database
try {
    $ramal = PBX_Usuarios::get($argv[1]);
} catch (Exception $e) {
    $asterisk->verbose("[$requestid] Error in interface reoslution: " . $e->getMessage(), 1);
    exit(1);
}

$channel = $ramal->getInterface()->getCanal();
if(substr($channel, 0, 1)  == "k" || substr($channel, 0, 1)  == "K") {
    $channel = "Khomp/" . strtoupper(substr($channel, strpos($channel, '/') +1));
}
$asterisk->set_variable($argv[2], $channel);
