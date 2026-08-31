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
 * TASK-0026G (F20): the one shared CSRF token store for the whole
 * application, replacing the per-controller ad hoc pattern
 * SystemstatusController::indexAction()/restartDispatchAction() built for
 * TASK-0021/0022. A single, non-rotating, per-session token is generated
 * with random_bytes() (never predictable/derived data) and compared with
 * hash_equals() (constant-time). See
 * docs/tasks/0026g-session-cookie-csrf-hardening.md for the full lifecycle
 * design and why per-request rotation was deliberately NOT used (it would
 * break a legitimate second open browser tab using an older page load).
 *
 * @category  Snep
 * @package   Snep
 */
class Snep_Security_Csrf {

    const SESSION_KEY = 'snep_csrf_token';

    /**
     * FIELD - the POST body parameter name every form/AJAX call must send
     * the token under.
     */
    const FIELD = 'snep_csrf_token';

    /**
     * HEADER - documented alternative for AJAX callers that prefer a
     * request header over a body parameter.
     */
    const HEADER = 'X-Snep-Csrf-Token';

    /**
     * getToken() - returns the current session's CSRF token, minting one
     * on first use.
     *
     * @return string
     */
    public static function getToken() {
        if (empty($_SESSION[self::SESSION_KEY])) {
            $_SESSION[self::SESSION_KEY] = bin2hex(random_bytes(32));
        }
        return $_SESSION[self::SESSION_KEY];
    }

    /**
     * rotate() - forces a fresh token. Called once on successful login
     * (right after the session ID itself is regenerated, TASK-0026G F18)
     * so a newly-authenticated session never carries a token that could
     * have been seeded into it before authentication. Session destruction
     * (logout) already invalidates the token implicitly, since it lives
     * only in $_SESSION.
     *
     * @return string the newly minted token
     */
    public static function rotate() {
        $_SESSION[self::SESSION_KEY] = bin2hex(random_bytes(32));
        return $_SESSION[self::SESSION_KEY];
    }

    /**
     * isValid() - constant-time comparison against the current session's
     * token. False for a missing session token, a missing/empty submitted
     * token, or a mismatch.
     *
     * @param string|null $submitted
     * @return bool
     */
    public static function isValid($submitted) {
        if (empty($submitted) || empty($_SESSION[self::SESSION_KEY])) {
            return false;
        }
        return hash_equals($_SESSION[self::SESSION_KEY], (string) $submitted);
    }

}
