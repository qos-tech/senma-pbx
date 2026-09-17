<?php

/**
 *  This file is part of SNEP / SENMA.
 *
 *  SNEP is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Lesser General Public License as
 *  published by the Free Software Foundation, either version 3 of
 *  the License, or (at your option) any later version.
 */

/**
 * Defensive helpers for optional System Status runtime state (TASK-0034I-R2).
 *
 * Isolates CloudNotice registration auth extraction and Asterisk AMI
 * "core show version" parsing so missing/partial data cannot emit PHP
 * warnings or block the dashboard. Secrets are never fabricated and
 * never logged by these helpers.
 *
 * @category  Snep
 * @package   Snep
 */
class Snep_SystemStatus_OptionalRuntime {

    /**
     * Whether the once-per-session CloudNotice gate should still run.
     *
     * Uses empty()-safe session access (no undefined-key warning).
     * unset/false => run; true => skip.
     *
     * @param array $session typically $_SESSION
     * @return bool
     */
    public static function shouldRunCloudNotice(array $session) {
        return empty($session['cloud_noticed']);
    }

    /**
     * Build CloudNotice auth payload from Snep_Register_Manager::get().
     *
     * Legitimate shapes: associative array (possibly missing keys), false
     * (PDO fetch with no row), null. Never invents credentials — absent
     * values become empty strings so the outbound host-inspect body keeps
     * its historical shape without fabricating secrets.
     *
     * @param mixed $register
     * @return array{api_key:string,client_key:string}
     */
    public static function registerAuthPayload($register) {
        $apiKey = '';
        $clientKey = '';
        if (is_array($register)) {
            if (array_key_exists('api_key', $register) && $register['api_key'] !== null) {
                $apiKey = (string) $register['api_key'];
            }
            if (array_key_exists('client_key', $register) && $register['client_key'] !== null) {
                $clientKey = (string) $register['client_key'];
            }
        }
        return array(
            'api_key' => $apiKey,
            'client_key' => $clientKey,
        );
    }

    /**
     * Parse PBX_Asterisk_AMI::Command('core show version') into a version
     * string, or null when unavailable.
     *
     * Asterisk 22 AMI frames Command output as repeated "Output:" headers
     * accumulated into response['data'] (often a single version line).
     * Legacy "Response: Follows" payloads may include header lines before
     * the version. Never assume str_getcsv(...)[1].
     *
     * @param mixed $amiResponse
     * @return string|null
     */
    public static function asteriskVersionFromAmiCommand($amiResponse) {
        if ($amiResponse === false || $amiResponse === null) {
            return null;
        }
        if (!is_array($amiResponse)) {
            return null;
        }
        if (!isset($amiResponse['data']) || !is_string($amiResponse['data'])) {
            return null;
        }
        $data = trim($amiResponse['data']);
        if ($data === '') {
            return null;
        }
        // Prefer a real Asterisk version token anywhere in the payload.
        if (preg_match('/\bAsterisk\s+(\d+(?:\.\d+){0,3}\S*)\b/i', $data, $m)) {
            return $m[1];
        }
        // Fallback: first non-empty non-header line that looks useful.
        $lines = preg_split("/\r\n|\n|\r/", $data);
        if (!is_array($lines)) {
            return null;
        }
        foreach ($lines as $line) {
            $line = trim((string) $line);
            if ($line === '') {
                continue;
            }
            if (preg_match('/^(Response|Privilege|Message|ActionID|--END)\b/i', $line)) {
                continue;
            }
            if (preg_match('/\bAsterisk\b/i', $line)) {
                if (preg_match('/\bAsterisk\s+(\d+(?:\.\d+){0,3}\S*)\b/i', $line, $m2)) {
                    return $m2[1];
                }
                return $line;
            }
        }
        return null;
    }
}
