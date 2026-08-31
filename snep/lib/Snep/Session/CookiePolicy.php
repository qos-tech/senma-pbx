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
 * TASK-0026G (F19): session-cookie security attributes, centralized in the
 * one place safe to set them -- apply() must run before Zend_Session::start()
 * is called at the top of snep/Bootstrap.php, on every request. This calls
 * the native session_set_cookie_params(), the exact mechanism Zend_Session
 * itself builds on -- not a parallel/custom cookie layer. See
 * docs/tasks/0026g-session-cookie-csrf-hardening.md.
 *
 * @category  Snep
 * @package   Snep
 */
class Snep_Session_CookiePolicy {

    /**
     * TASK-0026G (F19): this project's current Docker topology
     * (compose.yaml) has no reverse proxy in front of the app container --
     * it serves plain HTTP directly. X-Forwarded-Proto is attacker-
     * controllable from any client unless a trusted proxy strips/overwrites
     * it, which nothing in this deployment currently guarantees. Trusting
     * it is therefore an explicit, documented opt-in for a deployment that
     * places a real trusted reverse proxy in front of the app -- never the
     * default.
     */
    const TRUST_PROXY_ENV = 'SENMA_TRUST_PROXY_HTTPS';

    /**
     * apply() - sets the session cookie's HttpOnly/SameSite/Secure policy.
     * Must be called before the session is started.
     *
     * HttpOnly and SameSite=Lax are unconditional -- no legitimate reason
     * was found for JavaScript to read this cookie, and Lax keeps ordinary
     * top-level navigation into the app (an external link, a bookmark)
     * working while still blocking the cross-site POST/AJAX shapes CSRF
     * relies on. Secure is deployment-aware: enabled whenever the current
     * request is actually HTTPS (direct, or via an explicitly trusted
     * proxy), left off otherwise so the documented local HTTP `make dev`
     * workflow keeps working unmodified.
     *
     * @return void
     */
    public static function apply() {
        session_set_cookie_params(array(
            'lifetime' => 0,
            'secure'   => self::isHttps(),
            'httponly' => true,
            'samesite' => 'Lax',
        ));
    }

    /**
     * isHttps() - direct-HTTPS detection always applies; trusting a
     * reverse proxy's X-Forwarded-Proto additionally requires
     * SENMA_TRUST_PROXY_HTTPS to be explicitly enabled (see TRUST_PROXY_ENV).
     *
     * @return bool
     */
    public static function isHttps() {
        if (!empty($_SERVER['HTTPS']) && strtolower((string) $_SERVER['HTTPS']) !== 'off') {
            return true;
        }
        if (isset($_SERVER['SERVER_PORT']) && (int) $_SERVER['SERVER_PORT'] === 443) {
            return true;
        }
        if (self::trustProxyHttps()
            && isset($_SERVER['HTTP_X_FORWARDED_PROTO'])
            && strtolower((string) $_SERVER['HTTP_X_FORWARDED_PROTO']) === 'https') {
            return true;
        }
        return false;
    }

    private static function trustProxyHttps() {
        $value = getenv(self::TRUST_PROXY_ENV);
        return $value === '1' || strtolower((string) $value) === 'true';
    }

}
