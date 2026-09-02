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
 *
 *  TASK-0026R (Q-SQL-004): ported off the removed mysql_ extension
 *  (mysql_connect(), PHP 8-incompatible, and even before that,
 *  unparameterized) onto this application's existing Zend_Db abstraction
 *  (Snep_Db::getInstance(), the same connection/config path
 *  ip_status_trunks.php/ip_status_peers.php resolve via -- see
 *  docs/tasks/0026r-full-residual-sql-remediation.md). The query
 *  targets and the is_numeric()-branched table choice are preserved
 *  byte-for-byte -- only the connection method and the SQL-construction
 *  mechanism changed. Deliberately left unauthenticated, matching the
 *  established ip_status_*.php sibling pattern in this same directory --
 *  authentication-model changes are out of this task's scope.
 */

define('APPLICATION_PATH', realpath(dirname(__FILE__) . '/..'));
set_include_path(implode(PATH_SEPARATOR, array(APPLICATION_PATH . '/lib', get_include_path())));
require_once 'Snep/Config.php';
require_once 'Snep/Db.php';

Snep_Config::setConfigFile(dirname(__FILE__) . '/setup.conf');
$db = Snep_Db::getInstance();

$idestado = $_GET['estado'];

if (is_numeric($idestado)) {  // use core_cnl (connection with ITC)
    $select = $db->select()->from('core_city', array('id', 'name'))->where('state_id = ?', $idestado);
} else {
    $select = $db->select()->from('core_cnl_city', array('id', 'name'))->where('state = ?', $idestado);
}
$result = $db->query($select)->fetchAll();

foreach ($result as $row) {
    echo "<option value='".$row['id']."'>".$row['name']."</option>";
}

?>
