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

require_once 'Zend/Auth/Adapter/Interface.php';

/**
 * TASK-0026H (F21): replaces Zend_Auth_Adapter_DbTable for both browser
 * login (AuthController) and the standalone API
 * (snep/modules/default/api/index.php) -- the ONE password-authentication
 * adapter shared by both.
 *
 * Zend_Auth_Adapter_DbTable cannot be reused here: it builds a SQL
 * "WHERE password = ?" equality expression and lets the DATABASE decide
 * the credential match. That only works for a deterministic hash
 * (md5($plaintext) always produces the same string) -- password_hash()
 * output is salted and non-deterministic, so verification MUST happen in
 * PHP (password_verify()) against a row fetched by identity alone. This
 * is a standard Zend_Auth_Adapter_Interface implementation (the
 * framework's own designed extension point for exactly this situation),
 * not a Zend_Auth redesign -- Zend_Auth::authenticate()/getStorage()/
 * hasIdentity()/clearIdentity() and Zend_Auth_Result's own semantics are
 * all unchanged and reused exactly as before.
 *
 * @category  Snep
 * @package   Snep
 */
class Snep_Auth_Adapter_Password implements Zend_Auth_Adapter_Interface {

    private $db;
    private $identity;
    private $credential;

    /**
     * @param Zend_Db_Adapter_Abstract $db
     * @param string $identity   submitted username
     * @param string $credential submitted plaintext password
     */
    public function __construct($db, $identity, $credential) {
        $this->db = $db;
        $this->identity = $identity;
        $this->credential = $credential;
    }

    /**
     * authenticate() - fetch by identity only (parameterized), verify in
     * PHP, migrate a legacy/stale representation on successful
     * verification only (never on failure, never for an unknown user,
     * never for a malformed stored value -- Phase 4's own invariant).
     *
     * @return Zend_Auth_Result
     */
    public function authenticate() {
        // BINARY: case-sensitive lookup, matching this codebase's own
        // pre-existing Snep_Acl::getCaseSensitive() convention (a plain
        // "=" would match case-insensitively under this schema's default
        // collation) -- absorbed here so AuthController no longer needs
        // a separate pre-check call before authenticating.
        $select = $this->db->select()
            ->from('users', array('id', 'name', 'password'))
            ->where('name = BINARY ?', $this->identity);
        $row = $this->db->fetchRow($select);

        if (!$row) {
            return new Zend_Auth_Result(
                Zend_Auth_Result::FAILURE_IDENTITY_NOT_FOUND,
                $this->identity,
                array('Identity not found.')
            );
        }

        if (!Snep_Security_Password::verify($this->credential, $row['password'])) {
            return new Zend_Auth_Result(
                Zend_Auth_Result::FAILURE_CREDENTIAL_INVALID,
                $this->identity,
                array('Supplied credential is invalid.')
            );
        }

        // TASK-0026H (F21, Phase 4): migrate only after successful
        // verification, and only this one row -- a parameterized UPDATE,
        // never string-interpolated.
        if (Snep_Security_Password::needsRehash($row['password'])) {
            $this->db->update(
                'users',
                array('password' => Snep_Security_Password::hash($this->credential)),
                $this->db->quoteInto('id = ?', $row['id'])
            );
        }

        return new Zend_Auth_Result(
            Zend_Auth_Result::SUCCESS,
            $this->identity,
            array('Authentication successful.')
        );
    }

}
