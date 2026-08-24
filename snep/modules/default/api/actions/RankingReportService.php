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
* Ranking Report Service
*
* @category  Snep
* @package   Snep
* @copyright Copyright (c) 2015 OpenS Tecnologia
* @author    Opens Tecnologia <desenvolvimento@opens.com.br>
*/
class RankingReportService implements SnepService {

  /**
  * Executa as ações do serviço
  */
  public function execute() {

    $config = Zend_Registry::get('config');
    $db = Zend_registry::get('db');
    $format = new Formata;

    $start_date = $_GET['start_date'] . " " . $_GET['start_hour'];
    $end_date = $_GET['end_date'] . " " . $_GET['end_hour'];
    $showsource = $_GET['showsource'];
    $showdestiny = $_GET['showdestiny'];
    $rankType = $_GET['type'];

    // Binds
    if(isset($_GET['clausulepeer']) && isset($_GET['clausule'])){

      $clausulepeer = explode("_", $_GET['clausulepeer']);
      $where_binds = '';

      foreach( $clausulepeer as $key => $value){
        $where_binds .= $value.",";
      }
      $where_binds = substr($where_binds, 0,-1);

      // Not permission
      if($_GET['clausule'] == 'nobound'){

        $where_binds = " AND (src NOT IN (".$where_binds.") AND dst NOT IN (".$where_binds."))";

      }else{

        $where_binds = " AND (src IN (".$where_binds.") OR dst IN (".$where_binds."))";
      }
    }

    $prefix_inout = $config->ambiente->prefix_inout;

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

    $condDstExp = $where_exceptions = "";

    $where_exceptions .= " AND ( locate('ZOMBIE',channel) = 0 ) ";

    $select = "SELECT cdr.src, cdr.dst, cdr.disposition, cdr.duration, cdr.billsec, cdr.userfield, cdr.uniqueid ";
    $select .= " FROM cdr JOIN peers on cdr.src = peers.name WHERE";
    $select .= " ( calldate >= '$start_date' AND calldate <= '$end_date')";
    $select .= isset($where_binds) ? $where_binds : '';
    $select .= isset($where_prefix) ? $where_prefix : '';
    $select .= isset($where_exceptions) ? $where_exceptions : '';
    $select .= " ORDER BY calldate,userfield,cdr.amaflags";

    $userfield = "XXXXXXXXX" ;
    $flag_ini = True;
    $dados = array();

    foreach ($db->query($select) as $row) {

      /* userfield equals */
      if ($userfield != $row['userfield']) {
        if ($flag_ini) {
          $result[$row['uniqueid']] = $row;
          $userfield = $row['userfield'];
          $flag_ini = False;
          continue;
        }
      } else {
        $result[$row['uniqueid']] = $row;
        continue;
      }

      foreach ($result as $val) {

        $src = $val['src'];

        $dst = $val['dst'];

        if (!isset($dados[$src][$dst])) {
          $dados[$src][$dst]["QA"] = 0;
          $dados[$src][$dst]["QN"] = 0;
          $dados[$src][$dst]["QT"] = 0;
          $dados[$src][$dst]["TA"] = 0;
          $dados[$src][$dst]["TN"] = 0;
          $dados[$src][$dst]["TT"] = 0;
          $totais_q[$src] = 0;
          $totais_t[$src] = 0;
        }

        switch ($val['disposition']) {
          case "ANSWERED":
          $dados[$src][$dst]["QA"]++;
          $dados[$src][$dst]["TA"]+= $val['duration'];
          break;
          default:
          $dados[$src][$dst]["QN"]++;
          $dados[$src][$dst]["TN"] += $val['duration'];
          break;
        }

        (isset($dados[$src][$dst]["QT"])) ? $dados[$src][$dst]["QT"]++ : $dados[$src][$dst]["QT"] = 0;
        (isset($dados[$src][$dst]["TT"])) ? $dados[$src][$dst]["TT"] += $val['duration'] : $dados[$src][$dst]["TT"] = 0;
        $totais_q[$src]++;
        $totais_t[$src] += $val['duration'];
      }
      unset($result);
      $result[$row['uniqueid']] = $row;
      $userfield = $row['userfield'];
    }

    // no entries
    if(empty($dados)){
      return array("status" => "empty", "message" => "No entries found.");
    }else{

      /* possible last call */
      foreach ($result as $val) {
        $src = $val['src'];
        $dst = $val['dst'];
        if (!isset($dados[$src][$dst])) {
          $dados[$src][$dst]["QA"] = 0;
          $dados[$src][$dst]["QN"] = 0;
          $dados[$src][$dst]["QT"] = 0;
          $dados[$src][$dst]["TA"] = 0;
          $dados[$src][$dst]["TN"] = 0;
          $dados[$src][$dst]["TT"] = 0;
          $totais_q[$src] = 0;
          $totais_t[$src] = 0;
        }
        switch ($val['disposition']) {
          case "ANSWERED":

          $dados[$src][$dst]["QA"]++;
          $dados[$src][$dst]["TA"]+= $val['duration'];
          break;
          default:
          $dados[$src][$dst]["QN"]++;
          $dados[$src][$dst]["TN"] += $val['duration'];
          break;
        }

        (isset($dados[$src][$dst]["QT"])) ? $dados[$src][$dst]["QT"]++ : $dados[$src][$dst]["QT"] = 0;
        (isset($dados[$src][$dst]["TT"])) ? $dados[$src][$dst]["TT"] += $val['duration'] : $dados[$src][$dst]["TT"] = 0;
        $totais_q[$src]++;
        $totais_t[$src] += $val['duration'];
      }

      arsort($totais_q);
      arsort($totais_t);

      $array = array_chunk($totais_q, $showsource,true);
      $array_rank = $array[0];

      // ordered quantity by destination
      foreach($array_rank as $phone => $tot){
        foreach($dados as $key => $values){

          if($phone == $key){

            foreach($values as $destiny => $value){

              if ($rankType == "num") {
                $arr[$phone][$destiny] = $value['QT'];
                arsort($arr[$phone]);
              }else{
                $arr[$phone][$destiny] = $value['TT'];
                arsort($arr[$phone]);
              }
            }
          }
        }

        $arr = array_chunk($arr[$phone], $showdestiny,true);
        $value_array[$phone] = $arr[0];

      }

      // ordered array as quantity
      foreach($value_array as $phone => $value){

        // Totals
        if(!isset($totals[$phone])){
          $totals[$phone] = 0;
        }

        // Totals
        if(!isset($rank_totals[$phone])){
          $rank_totals[$phone] = 0;
        }

        foreach($dados as $key => $dado){
          if($phone == $key){
            foreach($value as $destiny => $x){
              foreach($dado as $dst => $val){
                if($destiny == $dst){
                  $rank_final[$phone][$destiny] = $val;

                  if ($rankType == "num") {
                    $totals[$phone] += $val['QT'];
                    $rank_totals[$phone] += $val['QT'];
                  }else{
                    $totals[$phone] += $val['TT'];
                    $rank_totals[$phone] += $val['TT'];
                  }

                }
              }
            }
          }
        }
      }

      // ordered array associative
      array_multisort($totals,$rank_final);


      //format hh:mm:ss
      foreach($rank_final as $key => $dado){
        foreach($dado as $x => $value){

          if(isset($value['TA'])){
            $rank_final[$key][$x]['TA'] = $format->fmt_segundos(array("a" => $value['TA'], "b" => 'hms'));
          }else{
            $rank_final[$key][$x]['TA'] = "00:00:00";
          }

          if(isset($param['TN'])){
            $rank_final[$key][$x]['TN'] = $format->fmt_segundos(array("a" => $value['TN'], "b" => 'hms'));
          }else{
            $rank_final[$key][$x]['TN'] = "00:00:00";
          }

          if(isset($value['TT'])){
            $rank_final[$key][$x]['TT'] = $format->fmt_segundos(array("a" => $value['TT'], "b" => 'hms'));
          }else{
            $rank_final[$key][$x]['TT'] = "00:00:00";
          }
        }
      }

      // ordered key and value
      arsort($rank_totals);
      $cont = 0;
      $rankfinal = array_reverse($rank_final);

      if($rankType != "num"){
        foreach($rank_totals as $key => $value){
          $rank_totals[$key] = $format->fmt_segundos(array("a" => $value, "b" => 'hms'));
        }
      }

      foreach($rank_totals as $x => $value){

        $rank[$x] = $rankfinal[$cont];
        $cont++;
      }

      $replace = false;
      if(isset($_GET['replace']))
      $replace = true;

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

        foreach($rank as $n => $numbers){

          if($contacts[$n]){

            $rank[$contacts[$n]. ' ->'.$n] = $rank[$n];
            unset($rank[$n]);
          }else{
            $val = $rank[$n];
            unset($rank[$n]);
            $rank[$n. ' ->'.$n] = $val;
          }
        }

        foreach($rank as $n => $numbers){
          foreach($numbers as $dst => $value){
            if($contacts[$dst]){
              $rank[$n][$contacts[$dst]] = $rank[$n][$dst];
              unset($rank[$n][$dst]);
            }else{
              $val = $rank[$n][$dst];
              unset($rank[$n][$dst]);
              $rank[$n][$dst] = $val;

            }
          }
        }
      }
      //Zend_Debug::Dump($rank);exit;
      //Zend_Debug::Dump($rank);exit;
      return array("status" => "ok", "quantity" => $rank, "type" => $rankType, "totals" => $rank_totals);

    }
  }
}
