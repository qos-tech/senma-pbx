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
 * AGI - LOG in database services use like (Spy, Redial, WhoAmI, 
 *       Record and Record Play ) 
 */

// ImportAGI's configuration
require_once("agi_base.php");

if (isset($argv[1]) && isset($argv[2])) {
	$origem = PBX_Usuarios::get($request->callerid);
	$destino = $argv[2];
	$funcao = $argv[1];
    } else {
	    $asterisk->verbose("Faltam argumentos, deve-se utilizar AGI_PATH,FUNCAO,DESTINO.");
	    exit(1);
    }

try {
    if ($funcao == "SPY") {
        // LOG insert
        $sql = "INSERT INTO `services_log` VALUES(NOW(), '{$asterisk->request['agi_callerid']}', 'SPY', True, 'Ramal {$origem->getNumero()} espionou o ramal: $destino.')";
        $db->query($sql);
    } 
    
    if ($funcao == "WHOAMI") {
        // LOG insert
        $sql = "INSERT INTO `services_log` VALUES(NOW(), '{$asterisk->request['agi_callerid']}', 'WHOAMI', True, 'Ramal {$origem->getNumero()} perguntou qual e seu numero.')";
        $db->query($sql);
    }

    if ($funcao == "REDIAL") {
        // LOG insert
        $sql = "INSERT INTO `services_log` VALUES(NOW(), '{$asterisk->request['agi_callerid']}', 'REDIAL', True, 'Ramal {$origem->getNumero()} para o ramal $destino.')";
        $db->query($sql);
    }

    if ($funcao == "REC") {
        // LOG insert
        $sql = "INSERT INTO `services_log` VALUES(NOW(), '{$asterisk->request['agi_callerid']}', 'REC', True, 'Ramal {$origem->getNumero()} gravou um audio.')";
        $db->query($sql);
    }

    if ($funcao == "RECPLAY") {
        // LOG insert
        $sql = "INSERT INTO `services_log` VALUES(NOW(), '{$asterisk->request['agi_callerid']}', 'RECPLAY', True, 'Ramal {$origem->getNumero()} escutou a ultima gravacao.')";
        $db->query($sql);
    }

} catch (Exception $ex) {
    $asterisk->verbose($ex->getMessage());
    exit(1);
}
