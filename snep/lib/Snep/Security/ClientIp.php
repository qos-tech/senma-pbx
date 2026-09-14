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
 * TASK-0035E1: authoritative client-IP resolution for rate limiting /
 * auditing when SENMA sits behind an explicitly trusted reverse proxy.
 *
 * Default (empty TRUSTED_PROXY_CIDRS): always return REMOTE_ADDR.
 * Forwarding headers are never consulted unless REMOTE_ADDR itself is
 * inside an explicitly configured trusted CIDR. There is no trust-all
 * mode (0.0.0.0/0 and ::/0 are rejected).
 *
 * X-Forwarded-For semantics (when REMOTE_ADDR is trusted): walk the
 * comma-separated chain from right to left, skip hops that are also in
 * TRUSTED_PROXY_CIDRS, return the first remaining valid IP. That matches
 * a proxy that appends the connecting client. For the current one-proxy
 * pilot topology (client -> trusted NPM -> SENMA) where NPM sets a
 * single client address, that address is returned.
 *
 * Do NOT use Zend_Controller_Request_Http::getClientIp() -- it trusts
 * forwarding headers unconditionally.
 *
 * @category  Snep
 * @package   Snep
 */
class Snep_Security_ClientIp {

    /** Explicit opt-in list of reverse-proxy CIDRs (comma-separated). */
    const TRUSTED_PROXY_ENV = 'TRUSTED_PROXY_CIDRS';

    /** Preserves AuthController's historical missing-REMOTE_ADDR behavior. */
    const FALLBACK = 'unknown';

    /**
     * resolveFromServer() - resolve the throttle/audit client IP.
     *
     * @param array|null $server request server bag; defaults to $_SERVER
     * @return string validated IPv4/IPv6 address, or FALLBACK
     */
    public static function resolveFromServer($server = null) {
        if ($server === null) {
            $server = $_SERVER;
        }
        if (!is_array($server)) {
            return self::FALLBACK;
        }

        $remote = isset($server['REMOTE_ADDR']) ? trim((string) $server['REMOTE_ADDR']) : '';
        if ($remote === '' || !self::isValidIp($remote)) {
            return self::FALLBACK;
        }

        $trustedCidrs = self::trustedProxyCidrs();
        if ($trustedCidrs === array() || !self::ipInAnyCidr($remote, $trustedCidrs)) {
            return $remote;
        }

        $fromXff = self::clientFromForwardedFor(
            isset($server['HTTP_X_FORWARDED_FOR']) ? $server['HTTP_X_FORWARDED_FOR'] : null,
            $trustedCidrs
        );
        if ($fromXff !== null) {
            return $fromXff;
        }

        $realIp = isset($server['HTTP_X_REAL_IP']) ? trim((string) $server['HTTP_X_REAL_IP']) : '';
        if ($realIp !== '' && self::isValidIp($realIp)) {
            return $realIp;
        }

        return $remote;
    }

    /**
     * trustedProxyCidrs() - parse TRUSTED_PROXY_CIDRS. Empty/absent => [].
     * Invalid or wildcard entries are ignored (fail-safe: no trust).
     *
     * @return string[] normalized CIDR strings
     */
    public static function trustedProxyCidrs() {
        $raw = getenv(self::TRUSTED_PROXY_ENV);
        if ($raw === false || trim((string) $raw) === '') {
            return array();
        }

        $out = array();
        foreach (preg_split('/\s*,\s*/', trim((string) $raw)) as $entry) {
            if ($entry === '') {
                continue;
            }
            $normalized = self::normalizeCidr($entry);
            if ($normalized === null) {
                // Diagnostics only -- never dump the full environment.
                error_log('Snep_Security_ClientIp: ignoring invalid or unsafe TRUSTED_PROXY_CIDRS entry');
                continue;
            }
            $out[] = $normalized;
        }
        return $out;
    }

    /**
     * isValidIp() - IPv4 or IPv6, no ports, no hostnames.
     *
     * @param string $ip
     * @return bool
     */
    public static function isValidIp($ip) {
        if (!is_string($ip) || $ip === '') {
            return false;
        }
        return filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4 | FILTER_FLAG_IPV6) !== false;
    }

    /**
     * ipInCidr() - membership test for one CIDR.
     *
     * @param string $ip
     * @param string $cidr normalized "addr/prefix"
     * @return bool
     */
    public static function ipInCidr($ip, $cidr) {
        if (!self::isValidIp($ip)) {
            return false;
        }
        $parts = explode('/', (string) $cidr, 2);
        if (count($parts) !== 2) {
            return false;
        }
        list($network, $prefixStr) = $parts;
        if (!self::isValidIp($network) || !preg_match('/^\d+$/', $prefixStr)) {
            return false;
        }
        $prefix = (int) $prefixStr;
        // Explicitly never treat /0 as a matching trusted hop here either.
        if ($prefix === 0) {
            return false;
        }

        $ipBin = inet_pton($ip);
        $netBin = inet_pton($network);
        if ($ipBin === false || $netBin === false || strlen($ipBin) !== strlen($netBin)) {
            return false;
        }

        $maxPrefix = strlen($ipBin) * 8;
        if ($prefix < 0 || $prefix > $maxPrefix) {
            return false;
        }

        $fullBytes = (int) floor($prefix / 8);
        $remainBits = $prefix % 8;
        if ($fullBytes > 0 && substr($ipBin, 0, $fullBytes) !== substr($netBin, 0, $fullBytes)) {
            return false;
        }
        if ($remainBits === 0) {
            return true;
        }
        $mask = (~((1 << (8 - $remainBits)) - 1)) & 0xFF;
        return (ord($ipBin[$fullBytes]) & $mask) === (ord($netBin[$fullBytes]) & $mask);
    }

    /**
     * @param string $ip
     * @param string[] $cidrs
     * @return bool
     */
    public static function ipInAnyCidr($ip, array $cidrs) {
        foreach ($cidrs as $cidr) {
            if (self::ipInCidr($ip, $cidr)) {
                return true;
            }
        }
        return false;
    }

    /**
     * @param string|null $header
     * @param string[] $trustedCidrs
     * @return string|null
     */
    private static function clientFromForwardedFor($header, array $trustedCidrs) {
        if ($header === null) {
            return null;
        }
        $header = trim((string) $header);
        if ($header === '') {
            return null;
        }

        $ips = array();
        foreach (explode(',', $header) as $part) {
            $candidate = trim($part);
            if ($candidate === '') {
                continue;
            }
            if (!self::isValidIp($candidate)) {
                continue;
            }
            $ips[] = $candidate;
        }
        if ($ips === array()) {
            return null;
        }

        for ($i = count($ips) - 1; $i >= 0; $i--) {
            if (!self::ipInAnyCidr($ips[$i], $trustedCidrs)) {
                return $ips[$i];
            }
        }
        return null;
    }

    /**
     * normalizeCidr() - accept "addr/prefix" or bare addr (/32 or /128).
     * Rejects wildcards and malformed values.
     *
     * @param string $entry
     * @return string|null
     */
    private static function normalizeCidr($entry) {
        $entry = trim((string) $entry);
        if ($entry === '') {
            return null;
        }

        if (strpos($entry, '/') === false) {
            if (!self::isValidIp($entry)) {
                return null;
            }
            $bin = inet_pton($entry);
            if ($bin === false) {
                return null;
            }
            $prefix = (strlen($bin) === 4) ? 32 : 128;
            return $entry . '/' . $prefix;
        }

        $parts = explode('/', $entry, 2);
        if (count($parts) !== 2) {
            return null;
        }
        list($network, $prefixStr) = $parts;
        $network = trim($network);
        $prefixStr = trim($prefixStr);
        if (!self::isValidIp($network) || !preg_match('/^\d+$/', $prefixStr)) {
            return null;
        }
        $prefix = (int) $prefixStr;
        $bin = inet_pton($network);
        if ($bin === false) {
            return null;
        }
        $maxPrefix = strlen($bin) * 8;
        if ($prefix < 0 || $prefix > $maxPrefix) {
            return null;
        }
        // Never accept trust-all.
        if ($prefix === 0) {
            return null;
        }
        if ($network === '0.0.0.0' || $network === '::') {
            return null;
        }
        return $network . '/' . $prefix;
    }

}
