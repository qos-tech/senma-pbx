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
 * TASK-0026H (F22): server-side, session-independent brute-force
 * throttle for AuthController::loginAction(). Backed by the existing
 * MariaDB database (the `login_attempts` table) -- no new runtime
 * dependency, matching this task's own explicit constraint.
 *
 * Two independent dimensions, both scoped by SOURCE IP, checked
 * independently so an attacker cannot bypass either merely by obtaining
 * a new session/cookie (nothing here reads $_SESSION):
 *
 *   - account+source: MAX_FAILURES_PER_ACCOUNT failures within
 *     WINDOW_MINUTES from the SAME (ip, username) pair. Deliberately
 *     scoped by ip, not username alone -- an attacker spraying failures
 *     against one victim account from many different sources is instead
 *     caught by the per-IP dimension below, so a victim can never be
 *     locked out indefinitely just because their username was tried
 *     (Phase 8's own explicit "avoid locking a victim account
 *     indefinitely through username-only abuse" requirement).
 *   - source alone: MAX_FAILURES_PER_IP failures within WINDOW_MINUTES
 *     from the same source, regardless of which username(s) it tried --
 *     catches broad credential-stuffing/scanning.
 *
 * Automatic expiration: both checks only ever count rows newer than the
 * window, so a block lifts on its own the moment the window elapses --
 * no separate unlock step, no permanent lockout. A successful login
 * clears (DELETEs) that (ip, username) pair's own failure rows
 * immediately (Phase 9's "success should clear/reduce relevant failure
 * state"); the broader per-IP counter is left to decay via the window
 * naturally, since an unrelated successful login should not reset a
 * scan/stuffing signal from the same source. Bounded storage growth: a
 * short opportunistic prune runs on every recorded failure.
 *
 * @category  Snep
 * @package   Snep
 */
class Snep_Security_LoginThrottle {

    /** Conservative pilot-use defaults; see the task doc for rationale. */
    const MAX_FAILURES_PER_ACCOUNT = 5;
    const MAX_FAILURES_PER_IP = 20;
    const WINDOW_MINUTES = 15;

    /**
     * isThrottled() - must be called BEFORE verifying credentials, so a
     * throttled request never even computes a password comparison
     * (Phase 8: "limiter must work before authentication").
     *
     * @param Zend_Db_Adapter_Abstract $db
     * @param string $username submitted, not yet validated as a real user
     * @param string $ip
     * @return bool
     */
    public static function isThrottled($db, $username, $ip) {
        $accountCount = (int) $db->fetchOne(
            $db->select()
                ->from('login_attempts', array('COUNT(*)'))
                ->where('username = ?', $username)
                ->where('ip_address = ?', $ip)
                ->where('attempted_at > ?', self::windowStart($db))
        );
        if ($accountCount >= self::MAX_FAILURES_PER_ACCOUNT) {
            return true;
        }

        $ipCount = (int) $db->fetchOne(
            $db->select()
                ->from('login_attempts', array('COUNT(*)'))
                ->where('ip_address = ?', $ip)
                ->where('attempted_at > ?', self::windowStart($db))
        );
        return $ipCount >= self::MAX_FAILURES_PER_IP;
    }

    /**
     * recordFailure() - call once per failed authentication attempt
     * (wrong password, unknown user -- never for a throttled request
     * that never reached credential verification at all, which would
     * otherwise inflate the very counter meant to expire on its own).
     *
     * @param Zend_Db_Adapter_Abstract $db
     * @param string $username
     * @param string $ip
     * @return void
     */
    public static function recordFailure($db, $username, $ip) {
        $db->insert('login_attempts', array(
            'username' => (string) $username,
            'ip_address' => (string) $ip,
            'attempted_at' => date('Y-m-d H:i:s'),
        ));

        // Opportunistic prune, bounds table growth without a separate
        // cron/scheduled job -- rows older than twice the window are
        // never read by isThrottled() again regardless.
        $db->delete(
            'login_attempts',
            $db->quoteInto('attempted_at < ?', date('Y-m-d H:i:s', strtotime('-' . (self::WINDOW_MINUTES * 2) . ' minutes')))
        );
    }

    /**
     * clearAccount() - call once on successful authentication.
     *
     * @param Zend_Db_Adapter_Abstract $db
     * @param string $username
     * @param string $ip
     * @return void
     */
    public static function clearAccount($db, $username, $ip) {
        $db->delete(
            'login_attempts',
            $db->quoteInto('username = ?', $username) . ' AND ' . $db->quoteInto('ip_address = ?', $ip)
        );
    }

    private static function windowStart($db) {
        return date('Y-m-d H:i:s', strtotime('-' . self::WINDOW_MINUTES . ' minutes'));
    }

}
