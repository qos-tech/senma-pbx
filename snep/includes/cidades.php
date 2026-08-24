<?php
/*
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
 *  Provide <select> option list for cyties  
 */

$setup = parse_ini_file("setup.conf");
            
$idestado = $_GET['estado'];

mysql_connect($setup["db.host"],$setup["db.username"],$setup["db.password"]);
mysql_selectdb($setup["db.dbname"]);



if (is_numeric($idestado) ) {  // use core_cnl (connection with ITC)
    $result = mysql_query("SELECT id,name FROM core_city WHERE state_id = ".$idestado);
} else {
    $result = mysql_query("SELECT id,name FROM core_cnl_city WHERE state = '".$idestado."'");
}
 while($row = mysql_fetch_array($result) ){
        echo "<option value='".$row['id']."'>".$row['name']."</option>";
    } 
/*if (mysql_num_rows($result) == 0) {
    echo "<option value='5565'>"."Other"."</option>";
}else {
    while($row = mysql_fetch_array($result) ){
   	    echo "<option value='".$row['id']."'>".$row['name']."</option>";
    }   
}*/

?>