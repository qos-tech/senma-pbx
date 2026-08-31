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
 * TASK-0026H (F21): the one shared password-representation helper for the
 * whole application -- browser login (Snep_Auth_Adapter_Password), the
 * standalone API (snep/modules/default/api/index.php), and every
 * user-management password write (Snep_Users_Manager::add(),
 * UsersController::editAction(), Snep_Auth_Manager::getUpdatePass()) all
 * call this instead of independently deciding what "a password" looks
 * like. See docs/tasks/0026h-authentication-default-install-hardening.md.
 *
 * Legacy detection: a bare 32-hex-character string is treated as this
 * codebase's own pre-existing md5($plaintext) representation (the ONLY
 * format users.password ever held before this task -- confirmed via
 * AuthController.php, Snep_Users_Manager::add(), Snep_Auth_Manager::
 * getUpdatePass(), and the install seed, all previously exactly
 * `md5($plaintext)`, no salt, no prefix). Anything else is assumed to
 * already be a password_hash() string (starts with "$"), including the
 * one-time F27 bootstrap sentinel (see docker/bootstrap-admin.php), which
 * deliberately does not match either shape and therefore never verifies
 * against any submitted plaintext.
 *
 * @category  Snep
 * @package   Snep
 */
class Snep_Security_Password {

    const LEGACY_MD5_PATTERN = '/^[a-f0-9]{32}$/i';

    /**
     * TASK-0026H (F21, Phase 14): this application's minimum length for a
     * newly SET human password (account creation, password change,
     * reset/redefine) -- longer than the old MD5-era client-side "5",
     * favoring length over arbitrary complexity rules (uppercase/digit/
     * symbol requirements) per the task's own explicit guidance. Never
     * applied retroactively to verify() -- an existing password set
     * under an older, shorter policy must keep working.
     */
    const MIN_LENGTH = 8;

    /**
     * normalize() - bcrypt (PASSWORD_DEFAULT today) silently truncates its
     * input at 72 bytes; pre-hashing with a fixed-length digest removes
     * that ceiling entirely (a long passphrase must keep working, never
     * be silently cut short) regardless of which algorithm
     * PASSWORD_DEFAULT resolves to, now or in the future. Applied
     * identically by hash() and the modern branch of verify() -- never
     * applied to the legacy MD5 branch, which must keep comparing against
     * the exact pre-existing md5($plaintext) representation.
     *
     * @param string $plaintext
     * @return string
     */
    private static function normalize($plaintext) {
        return base64_encode(hash('sha256', $plaintext, true));
    }

    /**
     * isLegacyMd5() - true only for a bare 32-hex-character string. Does
     * NOT trust an arbitrary 32-character value blindly -- this is the
     * exact, only legacy format this schema/codebase ever produced (see
     * class docblock); anything else (including a value that merely
     * happens to be some other 32-character string) is never treated as
     * a credential match by verify() below regardless of this check, so
     * misclassifying a non-hash string here cannot itself grant access.
     *
     * @param string $stored
     * @return bool
     */
    public static function isLegacyMd5($stored) {
        return is_string($stored) && preg_match(self::LEGACY_MD5_PATTERN, $stored) === 1;
    }

    /**
     * meetsMinimumLength() - server-side enforcement point for every
     * password-SETTING flow (account creation, change, reset/redefine).
     * Byte length, not character count -- simple, and if anything
     * slightly stricter (not more lenient) for multi-byte input.
     *
     * @param string $plaintext
     * @return bool
     */
    public static function meetsMinimumLength($plaintext) {
        return is_string($plaintext) && strlen($plaintext) >= self::MIN_LENGTH;
    }

    /**
     * hash() - the ONLY way any code in this application should turn a
     * plaintext password into its stored representation going forward.
     *
     * @param string $plaintext
     * @return string
     */
    public static function hash($plaintext) {
        return password_hash(self::normalize($plaintext), PASSWORD_DEFAULT);
    }

    /**
     * verify() - constant-time comparison appropriate to the stored
     * representation's format. A stored password_hash() string or a
     * stored legacy MD5 hash used AS the submitted plaintext must both
     * fail here (pass-the-hash) -- password_verify() already treats its
     * two arguments asymmetrically (never true unless $plaintext hashes
     * to $stored), and the legacy branch below only ever compares
     * md5($plaintext), never $stored itself, against $stored.
     *
     * @param string $plaintext
     * @param string $stored
     * @return bool
     */
    public static function verify($plaintext, $stored) {
        if (!is_string($stored) || $stored === '') {
            return false;
        }
        if (self::isLegacyMd5($stored)) {
            return hash_equals(strtolower($stored), md5($plaintext));
        }
        return password_verify(self::normalize($plaintext), $stored);
    }

    /**
     * needsRehash() - a legacy MD5 representation always needs migrating;
     * a modern one is deferred to PHP's own cost/algorithm-aware check
     * (Phase 7 -- future PASSWORD_DEFAULT changes migrate transparently
     * on next login, without forcing every existing hash to be rewritten
     * now).
     *
     * @param string $stored
     * @return bool
     */
    public static function needsRehash($stored) {
        if (self::isLegacyMd5($stored)) {
            return true;
        }
        return password_needs_rehash($stored, PASSWORD_DEFAULT);
    }

}
