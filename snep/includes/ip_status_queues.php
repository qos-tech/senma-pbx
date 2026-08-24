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
 */

require_once "AMI.php";


$ami = new AMI() ;
$queues = $ami->get_queues() ;

$ret = array() ;

foreach ($queues as $key => $value) {
    $ret[$key]['id'] = $key;
    $ret[$key]['calls'] = $value['calls'];
    $ret[$key]['completed'] = $value['completed'];
    $ret[$key]['abandoned'] = $value['abandoned'];
    $ret[$key]['strategy'] = $value['strategy'];
    $members = 0 ;
    foreach($value['members'] as $val) {
        $members ++ ;
    }     
    $ret[$key]['members'] = $members;
  
}

$out = array_values($ret);
$ret = json_encode($out);
echo $ret ;