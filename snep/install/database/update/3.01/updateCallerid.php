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
 *  This routine update callerid for used module billing and should 
 *  be performed when migrating from versions prior to 3.0 stable release.
 * 
 *  @author : Opens Developers Team
 *  @package : snep
 *  @version : 3.0 - 2016, march
 * 
 */

$conecta = mysql_connect("localhost", "snep", "sneppass") or print (mysql_error()); 
mysql_select_db("snep", $conecta) or print(mysql_error()); 

$sql = "SELECT callerid,name FROM peers"; 

$result = mysql_query($sql, $conecta); 
/* Escreve resultados até que não haja mais linhas na tabela */  
while($consulta = mysql_fetch_array($result)) { 
	
	$nameValue = explode("<", $consulta['callerid']);
	if(count($nameValue) <= 1){
        $new_callerid = $consulta['callerid']. " <".$consulta['name'].">"; 
    }else{
    	$new_callerid = $consulta['callerid'];
    };
	
	$name = $consulta['name'];
	$sql = "UPDATE peers SET callerid = '$new_callerid' WHERE name='$name'";
	       
	mysql_query($sql) or die(mysql_error());
	
}; 

mysql_free_result($result); 
mysql_close($conecta); 
?>
