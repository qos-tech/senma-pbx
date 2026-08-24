<?php
/**
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

/**
 * Classe que manipular os arquivos de log full.log
 *
 * @see Snep_Log
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2010 OpenS Tecnologia
 * @author    Rafael Pereira Bozzetti <rafael@opens.com.br>
 * 
 */
class Snep_Log {

    private $log;
    private $tail;
    private $dia_ini;
    private $dia_fim;
    private $hora_ini;
    private $hora_fim;


    // Contrutor da classe - Faz a leitura do arquivo de log.
    public function __construct($log, $arq) {

        $this->arquivo = $log . '/'. $arq;

        if(file_exists($this->arquivo)) {
            return 'ok';
        }else{
              return 'error';
        }
    }

    /**
     * Function para filtar o Log por dia e hora
     * 
     * @param <string> dia_ini (MMM dd)
     * @param <string> dia_fim (MMM dd)
     * @param <string> hora_ini (hh:mm:ss)
     * @param <string> hora_fim (hh:mm:ss)
     * @return <array> 
     *
     */
    public function grepLog($dia_ini, $dia_fim, $hora_ini, $hora_fim, $verbose, $others) {


        // Gera arquivo temporario baseado nos parametros, dia, hora e verbose
        $hora_ini = ($hora_ini === null ? "00:00:00": $hora_ini);
        $hora_fim = ($hora_fim === null ? "23:59:59": $hora_fim);
            
        $cmd = "awk  '$0 >= \"[".$dia_ini." ".$hora_ini."\" && $0 <= \"[".$dia_fim." ".$hora_fim."\"'"  ;

        if ($others != '') {
            $cmd .= " | grep ".$others ;
        }

        if ($verbose != '') {
            $cmd .= " | grep \"VERBOSE\[".$verbose."\]\"" ;
        }

        $file_output = "/tmp/snep-log-file-".date("Y-m-d-H-i-s").".txt";

        $cmd .= " " . $this->arquivo . " > ".$file_output ;

        exec($cmd) ;

        if (file_exists($file_output) && is_readable($file_output) && filesize($file_output) > 0 ) {
            return $file_output ;
        } else { 
            return 'error' ;
        }
        
    }


    /**
     * Função para extrair um array conforme parametros passados.
     *
     * @param <string> dia_ini (MMM dd)
     * @param <string> dia_fim (MMM dd)
     * @return <array>
     */
    public function getLog($src, $dst) {

        $this->status = $st;
        $this->src = $src;
        $this->dst = $dst;

        $this->log = explode("\n", $this->log);

        
        exit;


        
        return $filtro;
        
    }
    
}
