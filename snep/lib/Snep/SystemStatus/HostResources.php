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
 * Local host-resource collectors for System Status (TASK-0034I-R1).
 *
 * Replaces the historical HTTP self-call to the vendored linfo XML
 * endpoint on the container-internal default Apache listen port, which
 * broke under TASK-0035E2 host networking where Apache listens on
 * APACHE_HTTP_PORT (pilot: 8080) rather than the bridge-only default.
 *
 * All values are read from the local filesystem (/proc) — never via HTTP,
 * never from request Host / X-Forwarded-* headers, and never from a
 * configurable remote URL (SSRF surface removed by deleting the self-call).
 *
 * @category  Snep
 * @package   Snep
 */
class Snep_SystemStatus_HostResources {

    /** Operator-facing primary when a local metric cannot be read. */
    const UNAVAILABLE = 'Unavailable';

    /**
     * uptimePhrase - English uptime phrase derived from /proc/uptime.
     *
     * Returns null when /proc/uptime is unreadable or malformed so the
     * caller can degrade that field without failing the whole page.
     *
     * Shape matches the historical linfo fragment consumed by
     * SystemstatusController (day/days/hour/hours/minute/minutes tokens
     * that the controller translates for the locale).
     *
     * @param string|null $uptimeFile injectable path for tests
     * @return string|null
     */
    public static function uptimePhrase($uptimeFile = null) {
        $path = ($uptimeFile !== null && $uptimeFile !== '') ? $uptimeFile : '/proc/uptime';
        $raw = @file_get_contents($path);
        if ($raw === false || $raw === '') {
            return null;
        }
        $parts = preg_split('/\s+/', trim($raw), 2);
        if ($parts === false || !isset($parts[0]) || !is_numeric($parts[0])) {
            return null;
        }
        $seconds = (int) floor((float) $parts[0]);
        if ($seconds < 0) {
            return null;
        }
        return self::formatUptimeSeconds($seconds);
    }

    /**
     * formatUptimeSeconds - build the English uptime phrase.
     *
     * @param int $seconds
     * @return string
     */
    public static function formatUptimeSeconds($seconds) {
        $seconds = (int) $seconds;
        if ($seconds < 0) {
            $seconds = 0;
        }
        $days = (int) floor($seconds / 86400);
        $hours = (int) floor(($seconds % 86400) / 3600);
        $minutes = (int) floor(($seconds % 3600) / 60);

        $chunks = array();
        if ($days > 0) {
            $chunks[] = $days . ' ' . ($days === 1 ? 'day' : 'days');
        }
        if ($hours > 0 || $days > 0) {
            $chunks[] = $hours . ' ' . ($hours === 1 ? 'hour' : 'hours');
        }
        $chunks[] = $minutes . ' ' . ($minutes === 1 ? 'minute' : 'minutes');

        return implode(', ', $chunks);
    }

    /**
     * translateUptimePhrase - replace English duration tokens via a
     * callable translator (typically $view->translate).
     *
     * @param string   $phrase
     * @param callable $translate function(string):string
     * @return string
     */
    public static function translateUptimePhrase($phrase, $translate) {
        if (!is_callable($translate) || $phrase === '') {
            return $phrase;
        }
        $search = array('day', 'days', 'hour', 'hours', 'minute', 'minutes', 'second', 'seconds');
        $replace = array();
        foreach ($search as $token) {
            $replace[] = call_user_func($translate, $token);
        }
        return str_replace($search, $replace, $phrase);
    }
}
