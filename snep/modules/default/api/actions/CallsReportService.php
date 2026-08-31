<?php

/*
*  This file is part of SNEP.
*
*  SNEP is free software: you can redistribute it and/or modify
*  it under the terms of the GNU Lesser General Public License as
*  published by the Free Software Foundation, either version 3 of
*  the License, or (at your option) any later version.
*
*  SNEP is distributed in the hope that it will be useful,
*  but WITHOUT ANY WARRANTY; without even the implied warranty of
*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*  GNU Lesser General Public License for more details.
*
*  You should have received a copy of the GNU Lesser General Public License
*  along with SNEP.  If not, see <http://www.gnu.org/licenses/lgpl.txt>.
*/

require_once '../../../includes/functions.php';

/**
* Calls Report Service
*
* @category  Snep
* @package   Snep
* @copyright Copyright (c) 2015 OpenS Tecnologia
* @author    Opens Tecnologia <desenvolvimento@opens.com.br>
*/
class CallsReportService implements SnepService {

  /**
  * Executa as ações do serviço
  */
  public function execute() {

    $config = Zend_Registry::get('config');
    $db = Zend_registry::get('db');

    $prefix_inout = $config->ambiente->prefix_inout;

    $start_date = $_GET['start_date'] . " " . $_GET['start_hour'];
    $end_date = $_GET['end_date'] . " " . $_GET['end_hour'];
    $report_type = $_GET['report_type'];

    if(isset($_GET['limit']))
    // TASK-0026F1: LIMIT is a numeric-literal SQL position, not a
    // bindable value or an identifier -- an int cast is the correct
    // control here (quoting would break the query), and collapses any
    // SQL-shaped input harmlessly to an integer.
    $limit = (int) $_GET['limit'];

    if(isset($_GET['replace']))
    $replace = true;

    // exceptions
    if(isset($_GET['exceptions'])){
      $exceptions = explode("_", $_GET['exceptions']);

      // TASK-0026F1: $db->quote() both escapes and wraps the value in
      // quotes (replacing manual "'".$value."'" concatenation), so each
      // list member becomes a safe SQL literal before it ever reaches the
      // IN (...) fragments built below.
      foreach($exceptions as $key => $value){
        (isset($exceptionsAll)) ? $exceptionsAll .= $db->quote($value)."," : $exceptionsAll = $db->quote($value).",";
      }
      $exceptions = substr($exceptionsAll, 0,-1);
    }

    // Binds
    if(isset($_GET['clausulepeer']) && isset($_GET['clausule'])){

      $clausulepeer = explode("_", $_GET['clausulepeer']);
      $where_binds = '';

      // TASK-0026F1: same $db->quote() treatment as $exceptions above --
      // peer names were previously concatenated completely unquoted.
      foreach( $clausulepeer as $key => $value){
        $where_binds .= $db->quote($value).",";
      }
      $where_binds = substr($where_binds, 0,-1);

      // Not permission
      if($_GET['clausule'] == 'nobound'){

        if(isset($exceptions)){
          $where_binds = " AND (src IN (".$exceptions.") OR dst IN (".$exceptions."))"." AND (src NOT IN (".$where_binds.") OR dst NOT IN (".$where_binds."))";
        }else{
          $where_binds = " AND (src NOT IN (".$where_binds.") OR dst NOT IN (".$where_binds."))";
        }

      }else{

        if(isset($exceptions)){
          $where_binds = " AND (src IN (".$where_binds.",".$exceptions.") OR dst IN (".$where_binds.",".$exceptions."))";
        }else{
          $where_binds = " AND (src IN (".$where_binds.") OR dst IN (".$where_binds."))";
        }
      }

    }

    // when no exits bind and exsts only exception special
    if(!isset($where_binds) && isset($exceptions)){
      $where_binds = " AND (src IN (".$exceptions.") OR dst IN (".$exceptions."))";
    }

    // Status call
    $where_options[0] = " disposition != 'ANSWERED'";
    $where_options[1] = " disposition != 'NO ANSWER'";
    $where_options[2] = " disposition != 'BUSY'";
    $where_options[3] = " disposition != 'FAILED'";

    if(isset($_GET['status_answered']))
    unset($where_options[0]);

    if(isset($_GET['status_noanswer']))
    unset($where_options[1]);

    if(isset($_GET['status_busy']))
    unset($where_options[2]);

    if(isset($_GET['status_failed']))
    unset($where_options[3]);

    // TASK-0026F1: contactGroupSrcId/contactSrcId/contactGroupDstId/
    // contactDstId are foreign-key ids -- (int) cast plus quoteInto()
    // ensures a SQL-shaped value can never alter these subqueries'
    // syntax, regardless of what non-numeric text is supplied.
    if (isset($_GET['contactGroupSrcId'])) {
      $contactGroupSrcId = (int) $_GET['contactGroupSrcId'];
      $where_contactGroupSrc = " AND src IN (";
      $where_contactGroupSrc .= " SELECT phone FROM contacts_names cn ";
      $where_contactGroupSrc .= " INNER JOIN contacts_phone cp ON cp.contact_id = cn.id ";
      $where_contactGroupSrc .= " INNER JOIN contacts_group cg on cg.id = cn.group ";
      $where_contactGroupSrc .= $db->quoteInto(" WHERE cn.group = ? ", $contactGroupSrcId);
      $where_contactGroupSrc .= ") ";
    }

    if (isset($_GET['contactSrcId'])) {
      $contactSrcId = (int) $_GET['contactSrcId'];
      $where_contactSrc = " AND src IN ( ";
      $where_contactSrc .= " SELECT phone FROM contacts_names cn ";
      $where_contactSrc .= " INNER JOIN contacts_phone cp ON cp.contact_id = cn.id ";
      $where_contactSrc .= $db->quoteInto(" WHERE cn.id = ? ", $contactSrcId);
      $where_contactSrc .= ") ";
    }

    if (isset($_GET['contactGroupDstId'])) {
      $contactGroupDstId = (int) $_GET['contactGroupDstId'];
      $where_contactGroupDst = " AND dst IN (";
      $where_contactGroupDst .= " SELECT phone FROM contacts_names cn ";
      $where_contactGroupDst .= " INNER JOIN contacts_phone cp ON cp.contact_id = cn.id ";
      $where_contactGroupDst .= " INNER JOIN contacts_group cg on cg.id = cn.group ";
      $where_contactGroupDst .= $db->quoteInto(" WHERE cn.group = ? ", $contactGroupDstId);
      $where_contactGroupDst .= ") ";
    }

    if (isset($_GET['contactDstId'])) {
      $contactDstId = (int) $_GET['contactDstId'];
      $where_contactDst = " AND dst IN ( ";
      $where_contactDst .= " SELECT phone FROM contacts_names cn ";
      $where_contactDst .= " INNER JOIN contacts_phone cp ON cp.contact_id = cn.id ";
      $where_contactDst .= $db->quoteInto(" WHERE cn.id = ? ", $contactDstId);
      $where_contactDst .= ") ";
    }

    /* Busca os ramais pertencentes ao grupo de ramal de origem selecionado */
    $ramaissrc = $ramaisdst = "";
    if (isset($_GET['groupsrc'])) {

      $groupsrc = $_GET['groupsrc'];
      $origens = Snep_ExtensionsGroups_Manager::getExtensionsGroup($groupsrc);

      if (count($origens) == 0) {
        return array("status" => "fail", "message" => "errorgroup");
      } else {
        $ramalsrc = "";

        foreach ($origens as $key => $ramal) {
          $num = $ramal['name'];
          if (is_numeric($num)) {
            $ramalsrc .= $num . ',';
          }
        }
        $ramaissrc = " AND src in (" . trim($ramalsrc, ',') . ") ";
      }
    }

    if (isset($_GET['groupdst'])) {

      $groupdst = $_GET['groupdst'];
      $destino = Snep_ExtensionsGroups_Manager::getExtensionsGroup($groupdst);

      if (count($destino) == 0) {
        return array("status" => "fail", "message" => "There are no extensions in the selected group");
      } else {
        $ramaldst = "";

        foreach ($destino as $key => $ramal) {
          $num = $ramal['name'];
          if (is_numeric($num)) {
            $ramaldst .= $num . ',';
          }
        }
        $ramaisdst = " AND dst in (" . trim($ramaldst, ',') . ") ";
      }
    }

    // Src or dst value
    // TASK-0026F1: every src/dst comparison below now crosses into SQL
    // via $db->quoteInto() instead of raw interpolation; the OR-chain /
    // substr(...,3) accumulation shape (each fragment still starts with
    // " OR (") and the equal-vs-LIKE branching are otherwise unchanged.
    if (isset($_GET['src'])) {
      $src = $_GET['src'];
      $srcEqual = isset($_GET['order_src']) && $_GET['order_src'] == 'equal';
      if (strpos($src, ",")) {
        $where_src = '';
        $arrSrc = explode(",", $src);

        foreach ($arrSrc as $srcs) {
          $where_src .= $srcEqual
            ? $db->quoteInto(" OR (src = ?)", $srcs)
            : $db->quoteInto(" OR (src LIKE ?)", '%' . $srcs . '%');
        }

        $where_src = " AND (" . substr($where_src, 3) . ")";

      } else {
        $where_src = $srcEqual
          ? $db->quoteInto("AND (src = ?)", $src)
          : $db->quoteInto("AND (src LIKE ?)", '%' . $src . '%');
      }
    }

    if (isset($_GET['dst'])) {
      $dst = $_GET['dst'];
      $dstEqual = isset($_GET['order_dst']) && $_GET['order_dst'] == 'equal';
      if (strpos($dst, ",")) {
        $where_dst = '';
        $arrdst = explode(",", $dst);

        foreach ($arrdst as $dsts) {
          $where_dst .= $dstEqual
            ? $db->quoteInto(" OR (dst = ?)", $dsts)
            : $db->quoteInto(" OR (dst LIKE ?)", '%' . $dsts . '%');
        }

        $where_dst = " AND (" . substr($where_dst, 3) . ")";

      } else {
        $where_dst = $dstEqual
          ? $db->quoteInto("AND (dst = ?)", $dst)
          : $db->quoteInto("AND (dst LIKE ?)", '%' . $dst . '%');
      }
    }

    // Time call option -- duration is a numeric column position, same
    // treatment as `limit` above.
    (isset($_GET['time_call_init'])) ? $where_options[] = $db->quoteInto(' duration >= ? ', (int) $_GET['time_call_init']) : null ;
    (isset($_GET['time_call_end'])) ? $where_options[] = $db->quoteInto(' duration <= ? ', (int) $_GET['time_call_end']) : null ;


    // Cost center
    if(isset($_GET['cost_center'])){
      $where_cost_center = "";
      $cost_centers = explode("_", $_GET['cost_center']);

      if (count($cost_centers) > 0) {
        $tmp_cc = "";
        foreach ($cost_centers as $valor) {
          $tmp_cc .= $db->quoteInto(" cdr.accountcode like ? ", $valor . '%');
          $tmp_cc .= " OR ";
        }
        $cost_centers = implode(",", $cost_centers);
        if($tmp_cc != "")
        $where_cost_center.= " AND ( " . substr($tmp_cc, 0, strlen($tmp_cc) - 3) . " ) ";
      }else{
        $where_cost_center = " cdr.accountcode like ".$cost_centers."%";
      }
    }

    /* Where Prefix Login/Logout */
    $where_prefix = "";
    if (strlen($prefix_inout) > 3) {
      $cond_pio = "";
      $array_prefixo = explode(";", $prefix_inout);
      foreach ($array_prefixo as $valor) {
        $par = explode("/", $valor);
        $pio_in = $par[0];
        if (!empty($par[1])) {
          $pio_out = $par[1];
        }
        $t_pio_in = strlen($pio_in);
        $t_pio_out = strlen($pio_out);
        $cond_pio .= " substr(dst,1,$t_pio_in) != '$pio_in' ";
        if (!$pio_out == '') {
          $cond_pio .= " AND substr(dst,1,$t_pio_out) != '$pio_out' ";
        }
        $cond_pio .= " AND ";
      }
      if ($cond_pio != "")
      $where_prefix .= " AND ( " . substr($cond_pio, 0, strlen($cond_pio) - 4) . " ) ";
    }
    $where_prefix .= " AND ( locate('ZOMBIE',channel) = 0 ) ";

    // Locale call
    $locale_call = null;
    (isset($_GET['locale_call'])) ? $locale_call = true : null ;

    if($where_options){
      $where = "";
      foreach($where_options as $key => $option){
        $where .= ' AND ('.$option.') ';
      }
    }

    // SQL
    $select = "SELECT date_format(cdr.calldate,'%d/%m/%Y') AS key_dia, date_format(cdr.calldate,'%d/%m/%Y %H:%i:%s') AS dia, ";
    $select .= "cdr.src, cdr.dst, cdr.disposition, cdr.duration, cdr.billsec, cdr.accountcode,";
    $select .= "cdr.userfield, cdr.dcontext, cdr.amaflags, cdr.uniqueid, cdr.calldate, cdr.dstchannel";
    $select .= ",ccustos.codigo,ccustos.tipo,ccustos.nome";
    if($_GET['rate']){
      $select .= ", bc.price FROM cdr ";
      $select .= " LEFT JOIN rated_calls bc ON bc.userfield = cdr.userfield ";
    }else{
      $select .= " FROM cdr ";
    }
    $select .= " LEFT JOIN ccustos ON accountcode = ccustos.codigo ";
    $select .= " WHERE ( " . $db->quoteInto('calldate >= ?', $start_date) . " AND " . $db->quoteInto('calldate <= ?', $end_date) . ") ";
    $select .= (isset($where_cost_center)) ? $where_cost_center : '';
    $select .= (isset($where)) ? $where : '';
    $select .= (isset($where_contactGroupSrc)) ? $where_contactGroupSrc : '';
    $select .= (isset($where_contactSrc)) ? $where_contactSrc : '';
    $select .= (isset($where_contactGroupDst)) ? $where_contactGroupDst : '';
    $select .= (isset($where_contactDst)) ? $where_contactDst : '';
    $select .= (isset($where_src)) ? $where_src : '';
    $select .= (isset($where_dst)) ? $where_dst : '';
    $select .= (isset($ramaissrc)) ? $ramaissrc : '';
    $select .= (isset($ramaisdst)) ? $ramaisdst : '';
    $select .= (isset($where_binds)) ? $where_binds : '';
    $select .= $where_prefix;
    //$select .= " GROUP BY userfield ORDER BY calldate, userfield ";
    $select .= " ORDER BY calldate, cdr.userfield ";

    if($report_type != 'synthetic'){
      $select .= (isset($limit)) ? " LIMIT ".$limit : '';

      $selectcont = "SELECT count(*) as cont,disposition,accountcode,date_format(calldate,'%d/%m/%Y') AS key_dia ";
      $selectcont .= (isset($where_cost_center)) ? ", ccustos.tipo  FROM cdr, ccustos " : " FROM cdr";
      $selectcont .= " WHERE ( " . $db->quoteInto('calldate >= ?', $start_date) . " AND " . $db->quoteInto('calldate <= ?', $end_date) . ") ";
      $selectcont .= (isset($where_cost_center)) ? $where_cost_center : '';
      $selectcont .= (isset($where)) ? $where : '';
      $selectcont .= (isset($where_contactGroupSrc)) ? $where_contactGroupSrc : '';
      $selectcont .= (isset($where_contactSrc)) ? $where_contactSrc : '';
      $selectcont .= (isset($where_contactGroupDst)) ? $where_contactGroupDst : '';
      $selectcont .= (isset($where_contactDst)) ? $where_contactDst : '';
      $selectcont .= (isset($where_src)) ? $where_src : '';
      $selectcont .= (isset($where_dst)) ? $where_dst : '';
      $selectcont .= (isset($ramaissrc)) ? $ramaissrc : '';
      $selectcont .= (isset($ramaisdst)) ? $ramaisdst : '';
      $selectcont .= (isset($where_binds)) ? $where_binds : '';
      $selectcont .= $where_prefix;
      $selectcont .= " GROUP BY userfield ORDER BY calldate, userfield";

      $result = $db->query($selectcont)->fetchAll();
      $cont = count($result);
    }

    $stmt = $db->query($select);

    $row = array();
    while ($dado = $stmt->fetch()) {
      $row[] = $dado;
    }
    // TASK-0009: was count($stmt) -- PHP 8 made count() on a non-Countable
    // object (Zend_Db_Statement_Pdo) a fatal TypeError instead of PHP 7's
    // silent 1. $row is exactly the rows this query returned, fetched
    // immediately below anyway, so counting it after the fetch loop
    // preserves the original "row count" intent without re-querying.
    $cont = count($row);

    if($replace){
      $select_contacts = "SELECT `c`.id,`c`.name, `p`.`phone` FROM `contacts_names` AS `c` INNER JOIN `contacts_phone` AS `p` ON c.id = p.contact_id";
      $stmt = $db->query($select_contacts);
      $allContacts = $stmt->fetchAll();
      $select_peers = "SELECT name,callerid FROM `peers` WHERE peer_type = 'R'";
      $stmt = $db->query($select_peers);
      $allPeers = $stmt->fetchAll();

      foreach ($allContacts as $key => $value) {
        $contacts[$value['phone']] = $value['name'];
      }
      foreach ($allPeers as $key => $value) {
        $contacts[$value['name']] = $value['callerid'];
      }
    }

    foreach ($row as $key => $value) {

      if(!$result_data[$value['uniqueid']]['disposition']){
        $result_data[$value['uniqueid']]["disposition"] = $value["disposition"];
      }

      if($result_data[$value['uniqueid']]['dia'] == null){
        $result_data[$value['uniqueid']]['dia'] = $value["dia"];
      }

      if($result_data[$value['uniqueid']]['billsec'] === null){
        $result_data[$value['uniqueid']]['billsec'] = 0;
      }

      if($value['disposition'] == 'ANSWERED'){
        $result_data[$value['uniqueid']]['billsec'] = $result_data[$value['uniqueid']]['billsec'] + $value['billsec'];
        $result_data[$value['uniqueid']]["disposition"] = $value["disposition"];
      }

      $result_data[$value['uniqueid']]["codigo"] = $value['codigo'];
      $result_data[$value['uniqueid']]["tipo"] = $value["tipo"];
      $result_data[$value['uniqueid']]["nome"] = $value["nome"];
      $result_data[$value['uniqueid']]["key_dia"] = $value["key_dia"];
      $result_data[$value['uniqueid']]["src"] = $value["src"];
      $result_data[$value['uniqueid']]["dst"] = $value["dst"];

      $result_data[$value['uniqueid']]["src_name"] = $value["src"];
      $result_data[$value['uniqueid']]["dst_name"] = $value["dst"];

      if($value['price'] !== ""){
        //$bill = money_format('%.2n', $value["price"]);
        $result_data[$value['uniqueid']]["price"] = $value["price"];
      }

      if($replace){
        if($contacts[$value["src"]]){
          $result_data[$value['uniqueid']]["src_name"] = $contacts[$value["src"]];
        }

        if($contacts[$value["dst"]]){
          $result_data[$value['uniqueid']]["dst_name"] = $contacts[$value["dst"]];
        }
      }

      $result_data[$value['uniqueid']]["duration"] += $value["duration"];
      $result_data[$value['uniqueid']]["accountcode"] = $value["accountcode"];
      $result_data[$value['uniqueid']]["userfield"] = $value["userfield"];
      $result_data[$value['uniqueid']]["dcontext"] = $value["dcontext"];
      $result_data[$value['uniqueid']]["amaflags"] = $value["amaflags"];
      $result_data[$value['uniqueid']]["uniqueid"] = $value["uniqueid"];
      $result_data[$value['uniqueid']]["calldate"] = $value["calldate"];
      $result_data[$value['uniqueid']]["dstchannel"] = $value["dstchannel"];
    }

    //if($report_type == 'synthetic'){
    unset($row);
    $row = array();
    foreach($result_data as $r => $res){
      array_push($row,$res);
    }
    //}

    //$cont = count($row);
    //Totals
    $totals = array("ANSWERED" => 0, "NOANSWER" => 0, "BUSY" => 0, "FAILED" => 0, "TOTALS" => 0);
    $type = array("S" => 0, "E" => 0, "O" => 0);
    $values = array();
    $ccustos = array();
    $calldate = array();

    foreach($row as $key => $value){

      // Calls number
      if($value['disposition'] == 'ANSWERED'){
        $totals['TOTALS']++;
        $totals['ANSWERED']++;

      }elseif($value['disposition'] == 'NO ANSWER'){
        $totals['TOTALS']++;
        $totals['NOANSWER']++;

      }elseif($value['disposition'] == 'BUSY'){
        $totals['TOTALS']++;
        $totals['BUSY']++;


      }elseif($value['disposition'] == 'FAILED'){
        $totals['TOTALS']++;
        $totals['FAILED']++;
      }

      if($report_type == 'synthetic'){

        (isset($ccustos[$value['accountcode']])) ? $ccustos[$value['accountcode']]++ : $ccustos[$value['accountcode']] = 1;

        if(!isset($calldate[$value['key_dia']])){
          $calldate[$value['key_dia']]['TOTALS'] = 0;
          $calldate[$value['key_dia']]['ANSWERED'] = 0;
          $calldate[$value['key_dia']]['NOANSWER'] = 0;
          $calldate[$value['key_dia']]['BUSY'] = 0;
          $calldate[$value['key_dia']]['FAILED'] = 0;
        }

        if($value['disposition'] == 'ANSWERED'){
          $calldate[$value['key_dia']]['ANSWERED']++;
        }

        if($value['disposition'] == 'NO ANSWER'){
          $calldate[$value['key_dia']]['NOANSWER']++;
        }

        if($value['disposition'] == 'BUSY'){
          $calldate[$value['key_dia']]['BUSY']++;
        }

        if($value['disposition'] == 'FAILED'){
          $calldate[$value['key_dia']]['FAILED']++;
        }

        $calldate[$value['key_dia']]['TOTALS']++;

        if($value['tipo'] == 'S'){
          $type['S']++;
        }elseif($value['tipo'] == 'E'){
          $type['E']++;
        }else{
          $type['O']++;
        }
      }
    }

    if($report_type == 'synthetic'){
      return array("status" => "ok", "quantity" => $cont, "totals" => $totals, "ccustos" => $ccustos, "type" => $type, "calldate" => $calldate);
    }else{
      // TASK-0026I (F26): the generated SQL text was previously echoed
      // back in the response ("select"/"selectcont") -- an internal
      // implementation-detail disclosure (deferred by TASK-0026F1 §5).
      // The functional payload (data/quantity/totals) is unchanged.
      return array("status" => "ok", "data" => $row, "quantity" => $cont, "totals" => $totals);
    }
  }

}
