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
 */
/**
 * Classe Formata - Data Format
 *
 * @see Classes.php
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2014 OpenS Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 */
class Formata {

/**
 * fmt_segundos - Formats seconds on a standard outlet
 * @param <array> $params
 * @return <string> $marty
 */
function fmt_segundos($params,$smarty = null){

  $seconds = $params['a'] ;
  $type_ret = (isset($params['b']) && $params['b'] != "") ? $params['b'] : 'hms' ;

  switch($type_ret){
    case "m":
      $ret = $seconds/60;
    break;
    case "H":
      $ret = $seconds/3600;
    break;
    case "h":
      $ret = round($seconds/3600);
    break;
    case "D":
      $ret = $seconds/86400;
    break;
    case "d":
      $ret = round($seconds/86400);
    break;
    case "hms":
      $min_t = intval($seconds/60) ;
      $tsec = sprintf("%02s",intval($seconds%60)) ;
      $thor = sprintf("%02s",intval($min_t/60)) ;
      $tmin = sprintf("%02s",intval($min_t%60)) ;
      $ret = $thor.":".$tmin.":".$tsec;
    break ;
    case "ms":
      $min_t = intval($seconds/60) ;
      $tsec = sprintf("%02s",intval($seconds%60)) ;
      $tmin = sprintf("%02s",intval($min_t%60)) ;
      $ret = $tmin.":".$tsec;
    break ;
  }
  return $ret ;
}

/**
* fmt_telefone - Format Phone Number
* @param <array> $params
* @return <string> $number
*/
function fmt_telefone($params) {

  $number = trim($params['a']);

  if(!is_numeric($number)){
    return $number;
  }elseif(substr($number, 0, 4) == "0800" || substr($number, 0, 4) == "0300") {
    $number = substr($number, 0, 4) . "-" . substr($number, 4);
  }else{
    switch (strlen($number)) {
      case '8': //fixed
        $number = substr($number,0,4)."-".substr($number,4);
      break;
      case '9': //celphone
        $number = substr($number,0,5)."-".substr($number,5);
      break;
      case '10': //fixed with ddd
        $number = "(".substr($number,0,2).")".substr($number,2,4)."-".substr($number,6);
      break;
      case '11':
        if(substr($number,2,1) == 9){//celphone with ddd
          $number = "(".substr($number,0,2).")".substr($number,2,5)."-".substr($number,7);
        }else{//fixed with ddd and 0
          $number = substr($number,0,1)."(".substr($number,1,2).")".substr($number,3,4)."-".substr($number,7);
        }
      break;
      case '12':
        if(substr($number,3,1) == 9){//celphone with ddd and 0
          $number = substr($number,0,1)."(".substr($number,1,2).")".substr($number,3,5)."-".substr($number,8);
        }else{// fixed with ddd and 55
          $number = substr($number,0,2)."(".substr($number,2,2).")".substr($number,4,4)."-".substr($number,8);
        }
      break;
      case '13':
        if(substr($number,4,1) == 9){ //celphone with ddd and 55
          $number = substr($number,0,2)."(".substr($number,2,2).")".substr($number,4,5)."-".substr($number,9);
        }else{ // fixed with 0 + 55 + ddd
          $number = substr($number,0,3)."(".substr($number,3,2).")".substr($number,5,4)."-".substr($number,9);
        }
      break;
      case '14': //celphone with 0 + 55 + ddd
        $number = substr($number,0,3)."(".substr($number,3,2).")".substr($number,5,5)."-".substr($number,10);
      break;
      default:
        return $number;
      break;
    }
  }
  return $number;
}

/**
* fmt_cep - Format CEP
* @param <string> $number
* @return <string> $formated cep number
*/
function fmt_cep($number){

  // Get country code
  $country = Zend_Registry::get('config')->system->country_code;

  switch ($country) {
    case 76 : // Brazil
      $cep = substr($number,0,2).".".substr($number, 2,3)."-".substr($number, 5,3);
    break ;
  }
  return $cep ;

}
}

/**
 * Verifica alguns status do asterisk utilizando a classe phpagi-asmanager
 * @param <String> $comand - comando do asterisk ou Action
 *                          -> Se for Action, incluir a palavra "Action"
 * @param <String> $break - linha que retorna o resultado
 * @param <boolean>  $all - True/False - Se devolve todo Resultado ou nao
 * @return <String>
 */
function ast_status($comand, $break, $all = False) {
  require_once "AsteriskInfo.php";
  try {
    $astinfo = new AsteriskInfo();
    return $astinfo->status_asterisk($comand, $break, $all);
  } catch (Exception $e) {
    return $this->view->translate("Error! Failed to connect to server Asterisk.");
  }
}

/**
 *
 * Le arquivos do servidor
 * @param <String> $strFileName - Caminho/Nome do Arquivo a ser lido
 * @param <String> $intLines - Numero de linhas a serem retornadas
 * @param <String> $intBytes - Tamanho Maximo em bytes a ser lido por linha
 * @return <array>
 */
function rfts($strFileName, $intLines = 0, $intBytes = 4096) {
  $strFile = "";
  $intCurLine = 1;
  if (file_exists($strFileName)) {
    if ($fd = fopen($strFileName, 'r')) {
      while (!feof($fd)) {
        $strFile .= fgets($fd, $intBytes);
        if ($intLines <= $intCurLine && $intLines != 0) {
          break;
        } else {
          $intCurLine++;
        }
      }
      fclose($fd);
    } else {
      return "ERROR";
    }
  } else {
    return "ERROR";
  }
  return $strFile;
}
