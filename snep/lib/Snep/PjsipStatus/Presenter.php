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
 * Operator-facing status detail presentation (TASK-0035E6).
 *
 * Snep_PjsipStatus_Manager owns the normalized runtime vocabulary and
 * emits {state, detail}. This presenter is the single place that turns
 * that pair into what the UI may show underneath / as a tooltip:
 *
 *   primary status  → what is the state?
 *   detail          → what does the operator need to know? (optional)
 *
 * Rules:
 *   - ACTIVE (healthy) → empty detail (primary alone is enough)
 *   - never repeat the primary label in the detail
 *   - never pass through raw exception / stack / AMI dumps
 *   - keep one short line when a detail is shown
 *
 * Controllers and views must not invent their own detail wording when
 * rendering runtime badges; call operatorDetail() (StatusBadge does).
 *
 * @category  Snep
 * @package   Snep
 */
class Snep_PjsipStatus_Presenter {

    /** Soft cap for a single operator-facing detail line. */
    const MAX_DETAIL_CHARS = 120;

    /**
     * operatorDetail - final UI detail for a normalized status pair.
     *
     * @param string|null $state  Snep_PjsipStatus_Manager constant or null
     * @param string|null $detail raw detail from the status producer
     * @return string empty string when the primary status is enough
     */
    public static function operatorDetail($state, $detail) {
        if ($state === null || $state === '') {
            return '';
        }

        $detail = is_string($detail) ? trim($detail) : '';
        if ($detail === '') {
            return '';
        }

        // Healthy/normal: primary badge alone. Do not decorate Active with
        // success prose ("Registered -- reachable", RTT, etc.).
        if ($state === Snep_PjsipStatus_Manager::ACTIVE) {
            return '';
        }

        if (self::looksLikeDiagnosticLeak($detail)) {
            error_log('Snep_PjsipStatus_Presenter: suppressed diagnostic leak in status detail for state=' . $state);
            return self::safeFallback($state);
        }

        // Drop details that only echo the primary label ("Offline",
        // "Inactive", "Error", …) — including "Endpoint is offline".
        if (self::isRedundantWithState($state, $detail)) {
            return '';
        }

        if (function_exists('mb_strlen') && function_exists('mb_substr')) {
            if (mb_strlen($detail) > self::MAX_DETAIL_CHARS) {
                $detail = rtrim(mb_substr($detail, 0, self::MAX_DETAIL_CHARS - 1)) . '…';
            }
        } elseif (strlen($detail) > self::MAX_DETAIL_CHARS) {
            $detail = rtrim(substr($detail, 0, self::MAX_DETAIL_CHARS - 1)) . '...';
        }

        return $detail;
    }

    /**
     * shouldShowDetail - whether a visible help-block / separator is useful.
     */
    public static function shouldShowDetail($state, $detail) {
        return self::operatorDetail($state, $detail) !== '';
    }

    /**
     * looksLikeDiagnosticLeak - raw exception / dump / nullish markers.
     */
    private static function looksLikeDiagnosticLeak($detail) {
        if (preg_match('/\b(exception|stack trace|traceback|fatal error|PDOException|mysqli_|SQLSTATE|Zend_)\b/i', $detail)) {
            return true;
        }
        if (preg_match('/^\s*(null|undefined|n\/a|array\s*\(|object\s*\()/i', $detail)) {
            return true;
        }
        if (preg_match('/\bHTTP\s*[45]\d\d\b/', $detail)) {
            return true;
        }
        // PHP-style "in /path/file.php on line N"
        if (preg_match('/\bon line\s+\d+\b/i', $detail) && preg_match('/\.php\b/i', $detail)) {
            return true;
        }
        return false;
    }

    private static function isRedundantWithState($state, $detail) {
        $normalized = strtolower(preg_replace('/[^a-z]+/i', ' ', $detail));
        $normalized = trim(preg_replace('/\s+/', ' ', $normalized));
        $aliases = array(
            Snep_PjsipStatus_Manager::ACTIVE   => array('active', 'online', 'registered'),
            Snep_PjsipStatus_Manager::INACTIVE => array('inactive', 'offline', 'unregistered'),
            Snep_PjsipStatus_Manager::PENDING  => array('pending'),
            Snep_PjsipStatus_Manager::DEGRADED => array('degraded'),
            Snep_PjsipStatus_Manager::DISABLED => array('disabled'),
            Snep_PjsipStatus_Manager::ERROR    => array('error', 'failed', 'failure'),
            Snep_PjsipStatus_Manager::UNKNOWN  => array('unknown'),
        );
        if (!isset($aliases[$state])) {
            return false;
        }
        foreach ($aliases[$state] as $word) {
            // Exact echo: "Offline" / "Endpoint is offline"
            if ($normalized === $word || $normalized === 'endpoint is ' . $word
                || $normalized === 'status is ' . $word
                || $normalized === 'runtime is ' . $word) {
                return true;
            }
        }
        return false;
    }

    private static function safeFallback($state) {
        switch ($state) {
            case Snep_PjsipStatus_Manager::UNKNOWN:
                return 'Runtime status unavailable';
            case Snep_PjsipStatus_Manager::ERROR:
                return 'Runtime reported an error';
            default:
                return 'See system logs for diagnostic detail';
        }
    }

}
