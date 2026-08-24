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
 * AGI to provide group resolution
 */

require_once('agi_base.php');

if(!isset($argv[1]) || !is_numeric($argv[1])) {
   $log->crit("resolv_group: Argument invalid for first parameter , $argv[1]. Wait a extension");
}

if(!isset($argv[2]) || !is_numeric($argv[2])) {
   $log->crit("resolv_group:: Argument invalid for second parameter , $argv[2]. Wait a extension");
}

if(isset($argv[3])) {
    $variable = $argv[3];
}
else {
    $variable = "GROUP";
}


try {
    $ramal1 = PBX_Usuarios::get($argv[1]);
}
catch(PBX_Exception_NotFound $ex) {
    $log->info("Extension {$argv[1]} not fount.");
    $asterisk->set_variable($variable, '-1');
}

try {
    $ramal2 = PBX_Usuarios::get($argv[2]);
}
catch(PBX_Exception_NotFound $ex) {
    $log->info("Extension {$argv[2]} not found.");
    $asterisk->set_variable($variable, '-1');
}

$group1 = $ramal1->getGroup();
$group2 = $ramal2->getGroup();

if($group1 == $group2) {
    $log->crit("The extensions $ramal1 and $ramal2 they are in the same group!");
    $asterisk->set_variable($variable, 'true');
} else {
    $log->crit("The extensions $ramal1 and $ramal2 they are not in  the same group!");
    $asterisk->set_variable($variable, 'false');
    $asterisk->stream_file("beeperr");
    $asterisk->stream_file("beeperr");
}

