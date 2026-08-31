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

        // TASK-0026D (F4): this used to build an "awk '...' | grep
        // $others | grep \"VERBOSE[$verbose]\" $this->arquivo > $out"
        // shell command -- $dia_ini/$dia_fim/$hora_ini/$hora_fim/
        // $verbose/$others were all raw request values spliced straight
        // into shell syntax with zero quoting (F4's confirmed RCE).
        // $others in particular had no quotes at all, so it could also
        // inject arbitrary grep flags, not just shell metacharacters.
        //
        // Untrusted data must not become shell syntax, so this is now
        // plain PHP line-by-line filtering -- no exec()/shell involved
        // at all for this operation.
        //
        // This intentionally reproduces the OLD command's exact
        // observable behavior, confirmed by direct reproduction of the
        // original pipeline, rather than the "obviously more correct"
        // combined filter: because the log FILE argument was appended
        // at the very end of the whole piped command string, it always
        // bound to the *last* stage of the pipe, which then read the
        // file directly and ignored whatever the earlier stages had
        // piped into it. So: if $verbose is set, only the VERBOSE
        // marker filter ever applied (against the raw file, date range
        // and $others silently discarded); else if $others is set, only
        // that literal-substring filter applied (date range discarded);
        // the date/time range only ever took effect when both were
        // empty. Preserving this exactly, however accidental, per this
        // project's "preserve behavior before modernizing" rule -- see
        // docs/tasks/0026d-shell-execution-hardening.md.
        $hora_ini = ($hora_ini === null ? "00:00:00": $hora_ini);
        $hora_fim = ($hora_fim === null ? "23:59:59": $hora_fim);

        $start = "[" . $dia_ini . " " . $hora_ini;
        $end   = "[" . $dia_fim . " " . $hora_fim;
        $verboseMarker = "VERBOSE[" . $verbose . "]";

        $file_output = "/tmp/snep-log-file-".date("Y-m-d-H-i-s").".txt";

        $matched = array();
        $handle = is_readable($this->arquivo) ? fopen($this->arquivo, 'r') : false;
        if ($handle) {
            while (($line = fgets($handle)) !== false) {
                if ($verbose != '') {
                    if (strpos($line, $verboseMarker) !== false) {
                        $matched[] = $line;
                    }
                } elseif ($others != '') {
                    if (strpos($line, $others) !== false) {
                        $matched[] = $line;
                    }
                } else {
                    if ($line >= $start && $line <= $end) {
                        $matched[] = $line;
                    }
                }
            }
            fclose($handle);
        }

        file_put_contents($file_output, implode('', $matched));

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
