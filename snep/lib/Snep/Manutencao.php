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
 * Classe que abstrai a Manutencao de arquivos
 *
 * @see Snep_Manutencao
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2010 OpenS Tecnologia
 * @author    Rafael Pereira Bozzetti <rafael@opens.com.br>
 *
 * Modified for SENMA PBX:
 * Copyright (C) 2026 QOS Tech
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * TASK-0034I-R6: static recording URLs must use the public web base
 * (path.web), not the front-controller base URL (which may include
 * /index.php). Recording directory resolution prefers the embedded
 * YYYYMMDD from CDR userfield when present, then calldate, then
 * calldate reinterpreted from UTC into system timezone (CDR vs AGI
 * recording-local date mismatch).
 */
class Snep_Manutencao {

    public function __construct() {

    }

    public function __destruct() {

    }

    public function __clone() {

    }

    public function __get($atributo) {
        return $this->{$atributo};
    }

    /**
     * Lista calldate, userfield das ligações do periodo.
     *
     * @param <string> $data_inicio aaaa-dd-mm hh:ii:ss
     * @param <string> $data_fim aaaa-dd-mm hh:ii:ss
     * @return <array> (calldate, userfield)
     */
    public function listaPeriodo($data_inicio, $data_fim) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('cdr', array('calldate', 'userfield'))
                ->where("calldate >= '$data_inicio'")
                ->where("calldate <= '$data_fim'")
                ->where("userfield != '' ")
                ->group('userfield');

        $stmt = $db->query($select);
        $registros = $stmt->fetchAll();

        return $registros;
    }

    /**
     * Lista Unidade montadas como Storage
     *
     * @param <string> $arquivos
     * @return <array>
     *
     * PHP 8 compatibility (TASK-0002 P1-B): uses no $this, only called
     * internally via self:: from arquivoExiste() (no external call
     * sites) -- declared static alongside arquivoExiste() since a static
     * arquivoExiste() would otherwise have no $this to fall back on when
     * forwarding this call. See
     * docs/tasks/0002-php84-compatibility-baseline.md.
     */
    public static function listaStorage($arquivos) {

        $root = scandir($arquivos);
        $return = array();

        foreach ($root as $files) {
            if (preg_match('/^storage/', $files)) {
                $return[] = $files;
            }
        }

        return $return;
    }

    /**
     * Public (static-asset) web base URL for recordings under /arquivos.
     *
     * Distinct from Zend_Controller_Front::getBaseUrl(), which is the
     * front-controller base and may include "/index.php" when the
     * request is served through the front controller. Static files live
     * under DocumentRoot and must not be prefixed with the script name.
     *
     * Uses setup.conf path.web (TASK-0012): "" for root deployment,
     * "/subdir" for subdirectory deployment. Never hardcodes a host.
     *
     * @return string
     */
    public static function publicAssetBaseUrl() {
        $config = Zend_Registry::get('config');
        $web = '';
        if (isset($config->system->path->web)) {
            $web = (string) $config->system->path->web;
        }
        return rtrim($web, '/');
    }

    /**
     * Candidate YYYY-MM-DD directory names for a recording lookup.
     *
     * Order (first match that exists on disk wins in arquivoExiste):
     * 1. Embedded YYYYMMDD tokens from userfield (AGI recording-local
     *    date from date() under system timezone — canonical when the
     *    configured userfield pattern includes AA/MM/DD).
     * 2. calldate calendar day (historical behavior).
     * 3. calldate reinterpreted as UTC into system timezone (covers the
     *    known CDR=UTC vs recording-local midnight boundary without
     *    requiring a userfield date token).
     *
     * @param string $calldate
     * @param string $userfield
     * @return string[]
     */
    public static function recordingDateCandidates($calldate, $userfield) {
        $candidates = array();

        if (is_string($userfield) && $userfield !== '') {
            if (preg_match_all('/(?<!\d)(\d{4})(\d{2})(\d{2})(?!\d)/', $userfield, $matches, PREG_SET_ORDER)) {
                foreach ($matches as $match) {
                    $y = (int) $match[1];
                    $m = (int) $match[2];
                    $d = (int) $match[3];
                    if (checkdate($m, $d, $y)) {
                        $candidates[] = sprintf('%04d-%02d-%02d', $y, $m, $d);
                    }
                }
            }
        }

        if (is_string($calldate) && strlen($calldate) >= 10) {
            $fromCalldate = substr($calldate, 0, 10);
            if (preg_match('/^\d{4}-\d{2}-\d{2}$/', $fromCalldate)) {
                $candidates[] = $fromCalldate;
            }
        }

        if (is_string($calldate) && strlen($calldate) >= 19) {
            try {
                $config = Zend_Registry::get('config');
                $tzName = isset($config->system->timezone)
                    ? (string) $config->system->timezone
                    : 'America/Sao_Paulo';
                $utc = new DateTime(substr($calldate, 0, 19), new DateTimeZone('UTC'));
                $utc->setTimezone(new DateTimeZone($tzName));
                $candidates[] = $utc->format('Y-m-d');
            } catch (Exception $e) {
                // Keep prior candidates; filesystem probe remains authoritative.
            }
        }

        return array_values(array_unique($candidates));
    }

    /**
     * Build the browser URL for a recording relative path under /arquivos.
     *
     * @param string $relative e.g. "2026-09-18/file.wav" or "storage_x/..."
     * @return string
     */
    public static function recordingPublicUrl($relative) {
        $base = self::publicAssetBaseUrl();
        $relative = ltrim(str_replace('\\', '/', (string) $relative), '/');
        return $base . '/arquivos/' . $relative;
    }

    /**
     * Busca arquivo de gravacao, retorna caminho do mesmo ou não
     * @param <string> $calldate
     * @param <string> $userfield
     * @param <string> $arquivos
     * @return <string> Caminho para o arquivo.
     */
    /**
     * PHP 8 compatibility (TASK-0002 P1-B): Snep_Manutencao is never
     * instantiated anywhere in the tree; this method uses no $this and
     * its only external call site (CallsReportController.php:471)
     * already uses ::. Declared static to match. See
     * docs/tasks/0002-php84-compatibility-baseline.md.
     *
     * TASK-0034I-R6: returns a static public URL (/arquivos/...), never
     * /index.php/arquivos/..., and resolves the dated directory using
     * recordingDateCandidates().
     */
    public static function arquivoExiste($calldate, $userfield) {

        $config = Zend_Registry::get('config');
        $file_dir = $config->ambiente->path_voz;
        $arquivos = substr($file_dir, 0, strlen($file_dir) - 1);

        $conference = explode("_", (string) $userfield);
        $conf = false;
        if (isset($conference[3]) && is_numeric($conference[3])) {
            $room = (int) $conference[3];
            if ($room >= 901 && $room <= 915) {
                $conf = true;
            }
        }

        if (!file_exists($arquivos)) {
            return false;
        }

        $dateCandidates = self::recordingDateCandidates($calldate, $userfield);

        foreach ($dateCandidates as $data) {
            $found = self::findRecordingUnderDate($arquivos, $data, $userfield, $conf, $conference);
            if ($found !== false) {
                return $found;
            }
        }

        // Conference rooms historically live under /arquivos/<room>/ without
        // a date directory — try once regardless of date candidates.
        if ($conf === true && isset($conference[3])) {
            $room = $conference[3];
            if (file_exists($arquivos . "/" . $room . "/" . $userfield . ".wav")) {
                return self::recordingPublicUrl($room . "/" . $userfield . ".wav");
            }
            $storages = self::listaStorage($arquivos);
            foreach ($storages as $storage) {
                if (file_exists($arquivos . "/" . $storage . "/" . $room . "/" . $userfield . ".wav")) {
                    return self::recordingPublicUrl($storage . "/" . $room . "/" . $userfield . ".wav");
                }
            }
        }

        return false;
    }

    /**
     * Probe dated + storage paths for one YYYY-MM-DD candidate.
     *
     * @param string $arquivos
     * @param string $data
     * @param string $userfield
     * @param bool $conf
     * @param array $conference
     * @return string|false
     */
    private static function findRecordingUnderDate($arquivos, $data, $userfield, $conf, $conference) {
        $exts = array('.wav', '.mp3', '.WAV');
        foreach ($exts as $ext) {
            if (file_exists($arquivos . "/" . $data . "/" . $userfield . $ext)) {
                return self::recordingPublicUrl($data . "/" . $userfield . $ext);
            }
        }

        if ($conf === true && isset($conference[3])) {
            $room = $conference[3];
            if (file_exists($arquivos . "/" . $room . "/" . $userfield . ".wav")) {
                return self::recordingPublicUrl($room . "/" . $userfield . ".wav");
            }
        }

        $storages = self::listaStorage($arquivos);
        foreach ($storages as $storage) {
            foreach ($exts as $ext) {
                if (file_exists($arquivos . "/" . $storage . "/" . $data . "/" . $userfield . $ext)) {
                    return self::recordingPublicUrl($storage . "/" . $data . "/" . $userfield . $ext);
                }
            }
            if ($conf === true && isset($conference[3])) {
                $room = $conference[3];
                if (file_exists($arquivos . "/" . $storage . "/" . $room . "/" . $userfield . ".wav")) {
                    return self::recordingPublicUrl($storage . "/" . $room . "/" . $userfield . ".wav");
                }
            }
        }

        return false;
    }

    /**
     * Remove arquivo de gravação.
     * @param <string> $arquivo
     * @return <bool>
     */
    public function removeBackup($arquivo) {

        if (file_exists($arquivo)) {
            return (unlink($arquivo));
        }
    }

    /**
     * Compacta lista de arquivos
     * @param <string> $arquivo
     * @return <string> $file_path
     */
    public function compactaArquivos($arquivos) {

        $config = Zend_Registry::get('config');

        $save_dir = $config->ambiente->path_voz_bkp;

        $file_dir = $config->ambiente->path_voz;

        $strArquivos = substr($arquivos, 0, strlen($arquivos) - 1);
        $strListaArquivos = str_replace(",", " ", $strArquivos);
        $strNomeArquivo = date("d-m-Y-h-i") . ".zip";

        $strArquivo = $save_dir . "/" . $strNomeArquivo;

        $zip = new ZipArchive();

        if ($zip->open($strArquivo, ZipArchive::CREATE) !== TRUE) {
            return 2;
        }

        $arquivosLista = explode(",", trim($strArquivos));

        foreach ($arquivosLista as $arquivo) {
            $arq = $file_dir . $arquivo;

            if (file_exists($arq)) {
                $zip->addFile($arq);
            }
        }

        $zip->close();

        // TASK-0012 / TASK-0034I-R6: static asset URL, not front-controller.
        return self::recordingPublicUrl($strNomeArquivo);
    }

}

?>
