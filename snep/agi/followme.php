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
* AGI to provide Follow-me function
*/

// ImportAGI's configuration
require_once("agi_base.php");

$source = $asterisk->request['agi_callerid'];
$sql = "SELECT cancallforward FROM peers WHERE name='$source'";
$result = $db->query($sql)->fetch();

// Disable follow-me to the extension itself
if($source == $argv[1]){
  $hab = false;
  $asterisk->verbose("Ramal não pode habilitar o siga-me para o proprio ramal");
  $asterisk->stream_file("pm-invalid-option");
  exit(1);
}

if ($result['cancallforward'] == 'yes') {
  $hab = true;
} else {
  $hab = false;

  $asterisk->verbose("Ramal não pode habilitar o siga-me");
  //Sugestao: trocar audio por algo que indique que nao tem permissao.
  $asterisk->stream_file("pm-invalid-option");

  try {
    $sql = "INSERT INTO `services_log` VALUES(NOW(), '{$asterisk->request['agi_callerid']}', 'SIGAME', False, 'Ramal sem Permissao para Ativar o Sigame')";
    $db->query($sql);
    exit(0);
  } catch (Exception $ex) {
    $asterisk->verbose($ex->getMessage());
    exit(1);
  }

}

if (isset($argv[1]) && is_numeric($argv[1]) && $hab == true) {
  $funcao = "enable";
  $ramal = $argv[1];
} else {
  $funcao = "disable";
}

try {
  if ($funcao == "enable") {
    // Enable service
    $sql = "UPDATE `peers` SET sigame='$ramal' WHERE name='{$asterisk->request['agi_callerid']}'";
    $db->query($sql);

    // LOG insert
    $sql = "INSERT INTO `services_log` VALUES(NOW(), '{$asterisk->request['agi_callerid']}', 'SIGAME', True, 'Sigame ativado, desviando para: $ramal')";
    $db->query($sql);

    $asterisk->stream_file("activated");
  } else {
    // Disable service
    $sql = "UPDATE `peers` SET sigame=NULL WHERE name='{$asterisk->request['agi_callerid']}'";
    $db->query($sql);

    // LOG insert
    $sql = "INSERT INTO `services_log` VALUES(NOW(), '{$asterisk->request['agi_callerid']}', 'SIGAME', False, 'Sigame desativado')";
    $db->query($sql);
  }
} catch (Exception $ex) {
  $asterisk->verbose($ex->getMessage());
  exit(1);
}
