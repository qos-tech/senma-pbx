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
 *  AGI to provide phone number in schedule 
 */

require_once('agi_base.php');

$action = substr($asterisk->request['agi_extension'],0,3);
$entryid = substr($asterisk->request['agi_extension'],3);
$log = Zend_Registry::get('log');
$log->info("Calling from " . $asterisk->request['agi_callerid'] . " for schedule code " . $entryid . ".");

try {
    $sql = "SELECT phone FROM contacts_phone WHERE contact_id='$entryid' limit 1";
    $result = $db->query($sql)->fetchAll();
    if(count($result) == 1 && ($action == "*12" && $result[0]['phone'] != "") ) {
        
            $asterisk->set_extension($result[0]['phone']);        
        
    }
    else {
        $asterisk->verbose("Schedule: Invalid phone for code: [$requestid]!", 1);
    }
}
catch (Exception $ex) {
    $asterisk->verbose("[$requestid] Schedule error: " . $ex->getMessage(), 1);
}
