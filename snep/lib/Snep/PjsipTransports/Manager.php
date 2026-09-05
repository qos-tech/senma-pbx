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
 * Persistence/validation for PJSIP transports (TASK-0018).
 *
 * @category  Snep
 * @package   Snep
 */
class Snep_PjsipTransports_Manager {

    public static $protocols = array('udp', 'tcp', 'tls', 'wss', 'ws');

    // TASK-0029A: which protocols the cert_file/priv_key_file/
    // ca_list_file/verify_client/verify_server/method columns apply to
    // at all. `udp`/`tcp` carry no TLS concept -- these fields must be
    // empty for them (validatePost() rejects otherwise, matching this
    // project's "explicit failure over silent ignore" rule rather than
    // silently dropping user input).
    public static $tlsCapableProtocols = array('tls', 'wss', 'ws');

    // Modern, secure-by-default choices only -- deliberately narrower
    // than pjproject's full accepted `method` value set (sslv2, sslv3,
    // tlsv1, tlsv1_1 all excluded: this product does not support
    // configuring a known-insecure TLS version). '' means "let
    // Asterisk/pjproject pick" (pjsip show transport's own "unspecified"
    // default) -- see docs/tasks/0029a-tls-transport-certificate-management.md's
    // RUNTIME APPLY section for why 'tlsv1_2' is the recommended
    // explicit default rather than leaving this blank.
    public static $tlsMethods = array('', 'tlsv1_2', 'tlsv1_3');

    /**
     * getAll - every transport, with its usage count.
     */
    public static function getAll() {
        $db = Zend_Registry::get('db');
        $select = $db->select()->from('pjsip_transports')->order('id');
        $transports = $db->query($select)->fetchAll();

        foreach ($transports as &$transport) {
            $transport['usage_count'] = self::getUsageCount($transport['id']);
        }

        return $transports;
    }

    /**
     * get - one transport row, or false if it doesn't exist.
     */
    public static function get($id) {
        $db = Zend_Registry::get('db');
        $select = $db->select()->from('pjsip_transports')->where('id = ?', (int) $id);
        return $db->query($select)->fetch();
    }

    /**
     * getByName - one transport row by name, or false.
     */
    public static function getByName($name) {
        $db = Zend_Registry::get('db');
        $select = $db->select()->from('pjsip_transports')->where('name = ?', $name);
        return $db->query($select)->fetch();
    }

    /**
     * getNetworks - the local_net CIDR list for one transport, in
     * insertion order (matches the order they'll be emitted in the
     * generated config).
     */
    public static function getNetworks($transportId) {
        $db = Zend_Registry::get('db');
        $select = $db->select()->from('pjsip_transport_networks', array('network'))
            ->where('transport_id = ?', (int) $transportId)
            ->order('id');
        return $db->query($select)->fetchAll(Zend_Db::FETCH_COLUMN);
    }

    /**
     * getUsageCount - how many extensions/trunks currently reference this
     * transport. TASK-0018 item 9: usage detection must exist even
     * before templates do -- peers.transport_id/trunks.transport_id are
     * the only reference points today.
     */
    public static function getUsageCount($transportId) {
        $rows = self::getUsageDetails($transportId);
        return count($rows);
    }

    /**
     * getUsageDetails - which extensions/trunks reference this transport,
     * for a friendly delete-blocked message (mirrors
     * Snep_Trunks_Manager::getValidation()'s own "list what's using it"
     * pattern).
     *
     * @return array of array('type' => 'extension'|'trunk', 'id' => ..., 'label' => ...)
     */
    public static function getUsageDetails($transportId) {
        $db = Zend_Registry::get('db');
        $transportId = (int) $transportId;
        $rows = array();

        $select = $db->select()->from('peers', array('id', 'name'))
            ->where('transport_id = ?', $transportId);
        foreach ($db->query($select)->fetchAll() as $peer) {
            $rows[] = array('type' => 'extension', 'id' => $peer['id'], 'label' => $peer['name']);
        }

        $select = $db->select()->from('trunks', array('id', 'callerid'))
            ->where('transport_id = ?', $transportId);
        foreach ($db->query($select)->fetchAll() as $trunk) {
            $rows[] = array('type' => 'trunk', 'id' => $trunk['id'], 'label' => $trunk['callerid']);
        }

        return $rows;
    }

    /**
     * getEnabled - transports valid for NEW explicit selection (TASK-0019
     * item 4/6: a disabled transport must never be newly pinned by an
     * extension/trunk, and every selector view pulls from this one
     * method rather than filtering getAll() itself).
     */
    public static function getEnabled() {
        $db = Zend_Registry::get('db');
        $select = $db->select()->from('pjsip_transports')->where('enabled = 1')->order('id');
        return $db->query($select)->fetchAll();
    }

    /**
     * getSelectableWithCurrent - the enabled list (for a <select>), plus
     * the object's own already-persisted transport if it is no longer
     * enabled. TASK-0019 item 3/4: an edit form must still be able to
     * show/pre-select a stale disabled reference (flagged via the added
     * 'stale_disabled' key) instead of a raw HTML <select> silently
     * falling back to its first <option> because the persisted value
     * isn't among the rendered ones -- that would make the form lie
     * about what's actually saved.
     *
     * @param int|null $currentTransportId the object's current transport_id, or null
     * @return array pjsip_transports rows, each with an added boolean 'stale_disabled'
     */
    public static function getSelectableWithCurrent($currentTransportId) {
        $transports = self::getEnabled();
        foreach ($transports as &$t) {
            $t['stale_disabled'] = false;
        }
        unset($t);

        if ($currentTransportId !== null && $currentTransportId !== '') {
            $found = false;
            foreach ($transports as $t) {
                if ((int) $t['id'] === (int) $currentTransportId) {
                    $found = true;
                    break;
                }
            }
            if (!$found) {
                $current = self::get($currentTransportId);
                if ($current) {
                    $current['stale_disabled'] = true;
                    $transports[] = $current;
                }
            }
        }

        return $transports;
    }

    /**
     * validateSelection - TASK-0019 item 4: may $transportId be
     * persisted as an explicit pin right now? It must exist, and --
     * unless it is simply being left unchanged from what this exact
     * object already had ("newly pinned" is the operative word in the
     * product requirement, not "currently pinned") -- it must be
     * enabled. Translation-agnostic on purpose, matching this class's
     * existing validators (validateName()/validateProtocol()/...) --
     * callers translate the returned reason themselves.
     *
     * @param int      $transportId
     * @param int|null $currentTransportId the object's own already-persisted value, or null
     * @return string|null 'not_found', 'disabled', or null if valid
     */
    public static function validateSelection($transportId, $currentTransportId = null) {
        $transport = self::get($transportId);
        if (!$transport) {
            return 'not_found';
        }
        $unchanged = ($currentTransportId !== null && $currentTransportId !== ''
            && (int) $currentTransportId === (int) $transportId);
        if (!$transport['enabled'] && !$unchanged) {
            return 'disabled';
        }
        return null;
    }

    /**
     * getDefault - the transport currently marked is_default.
     *
     * TASK-0018 correction: NO generator consumes this anymore.
     * NULL transport_id means AUTO (no transport= line at all, letting
     * Asterisk pick a compatible transport itself), not "resolve to the
     * default" -- see Snep_PjsipConf::resolveTransportName(). is_default
     * itself was traced and deliberately kept (not removed): it still
     * has real, current responsibilities --
     * PjsipTransportsController::removeAction() blocks deleting the
     * default transport while others exist, and the UI highlights it in
     * listings/pre-fills it as the suggested choice. This accessor is
     * kept for exactly those UI-facing uses (and for a future
     * transport-picker's initial selection), not for provisioning.
     */
    public static function getDefault() {
        $db = Zend_Registry::get('db');
        $select = $db->select()->from('pjsip_transports')->where('is_default = 1')->limit(1);
        return $db->query($select)->fetch();
    }

    /**
     * create - insert a new transport + its local_net rows in one
     * transaction. If $data['is_default'] is set, every other transport
     * is demoted first so exactly one default ever exists.
     *
     * @param array $data     pjsip_transports column values (id/created_at/updated_at excluded)
     * @param array $networks list of CIDR strings for pjsip_transport_networks
     * @return int the new transport's id
     */
    public static function create(array $data, array $networks = array()) {
        $db = Zend_Registry::get('db');
        $db->beginTransaction();
        try {
            if (!empty($data['is_default'])) {
                self::clearDefault($db);
            }
            $db->insert('pjsip_transports', $data);
            $id = $db->lastInsertId();
            self::replaceNetworks($db, $id, $networks);
            $db->commit();
            return $id;
        } catch (Exception $ex) {
            $db->rollBack();
            throw $ex;
        }
    }

    /**
     * update - same shape as create(), for an existing row.
     */
    public static function update($id, array $data, array $networks = array()) {
        $db = Zend_Registry::get('db');
        $id = (int) $id;
        $db->beginTransaction();
        try {
            if (!empty($data['is_default'])) {
                self::clearDefault($db);
            }
            $db->update('pjsip_transports', $data, "id = $id");
            self::replaceNetworks($db, $id, $networks);
            $db->commit();
        } catch (Exception $ex) {
            $db->rollBack();
            throw $ex;
        }
    }

    /**
     * remove - delete a transport. Callers MUST check getUsageCount()
     * first (item 9: "do not allow deleting a transport that is
     * currently referenced") -- the FK's ON DELETE RESTRICT
     * (schema.sql) is the hard backstop if that check is ever bypassed,
     * not the primary mechanism.
     */
    public static function remove($id) {
        $db = Zend_Registry::get('db');
        $db->delete('pjsip_transports', "id = " . (int) $id);
    }

    private static function clearDefault(Zend_Db_Adapter_Abstract $db) {
        $db->update('pjsip_transports', array('is_default' => 0), '1=1');
    }

    private static function replaceNetworks(Zend_Db_Adapter_Abstract $db, $transportId, array $networks) {
        $transportId = (int) $transportId;
        $db->delete('pjsip_transport_networks', "transport_id = $transportId");
        foreach ($networks as $network) {
            $network = trim($network);
            if ($network === '') {
                continue;
            }
            $db->insert('pjsip_transport_networks', array('transport_id' => $transportId, 'network' => $network));
        }
    }

    /**
     * socketFamily - TASK-0020 investigation §5: confirmed live,
     * repeatedly, that socket identity is (protocol-family, bind_address,
     * bind_port), where "protocol-family" groups by the underlying BSD
     * socket type, not the PJSIP protocol= string verbatim -- UDP and TCP
     * freely coexist on an identical port (independently proven both
     * directions), while two transports both requesting UDP (or both
     * TCP) on the same bind collide. Only udp/tcp were empirically
     * exercised; tls/ws/wss are grouped with tcp here on ordinary POSIX
     * socket semantics (all four ride a SOCK_STREAM socket) rather than
     * independent Asterisk-specific testing -- documented as such,
     * not asserted as evidence-backed to the same degree as the udp/tcp
     * finding (docs/tasks/0020-pjsip-transport-runtime-lifecycle.md §5).
     *
     * @return string 'datagram' or 'stream'
     */
    public static function socketFamily($protocol) {
        return ($protocol === 'udp') ? 'datagram' : 'stream';
    }

    /**
     * findCollision - TASK-0020 item 1: is $protocol/$bindAddress/$bindPort
     * already claimed by a DIFFERENT transport row? Checks every other
     * row regardless of enabled/disabled (TASK-0020 investigation §8/§9:
     * a disabled transport's socket was proven to stay silently bound at
     * the OS level, exactly like a deleted one -- so a disabled row can
     * still be the thing a new save would collide with). Exact
     * bind_address string match only (not a wildcard/overlap check) --
     * the investigation only empirically proved exact-address collisions;
     * inventing a broader 0.0.0.0-overlap rule was deliberately avoided
     * per the task's own "do not invent, use the audit result"
     * instruction. The post-save runtime verification
     * (Snep_PjsipTransportConf::isRuntimeActive()) is the deliberate
     * defense-in-depth backstop for any address-overlap case this
     * narrower, evidence-strict check does not catch.
     *
     * @param string   $protocol
     * @param string   $bindAddress
     * @param int      $bindPort
     * @param int|null $excludeId the row being saved, excluded from the
     *                  comparison so an unchanged self-edit never
     *                  "collides with itself"
     * @return array|false the colliding row, or false if none
     */
    public static function findCollision($protocol, $bindAddress, $bindPort, $excludeId = null) {
        $db = Zend_Registry::get('db');
        $family = self::socketFamily($protocol);
        $familyProtocols = ($family === 'datagram') ? array('udp') : array('tcp', 'tls', 'ws', 'wss');

        $select = $db->select()->from('pjsip_transports')
            ->where('protocol IN (?)', $familyProtocols)
            ->where('bind_address = ?', $bindAddress)
            ->where('bind_port = ?', (int) $bindPort);
        if ($excludeId !== null && $excludeId !== '') {
            $select->where('id != ?', (int) $excludeId);
        }
        return $db->query($select)->fetch();
    }

    /**
     * validateName - non-empty, safe-for-a-sorcery-object-name (alnum,
     * dash, underscore only -- this string becomes a literal
     * "[name]" section header in generated Asterisk config, so it must
     * never contain characters that could break out of that context).
     */
    public static function validateName($name) {
        return is_string($name) && preg_match('/^[A-Za-z0-9_-]{1,80}$/', $name) === 1;
    }

    public static function validateProtocol($protocol) {
        return in_array($protocol, self::$protocols, true);
    }

    /**
     * validateIpOrHostname - accepts a real IPv4/IPv6 literal or a
     * syntactically valid hostname (Asterisk itself resolves hostnames
     * for bind/external addresses at load time -- TASK-0017 §2 already
     * established this is consistent with how peers.host already
     * behaves for trunks).
     */
    public static function validateIpOrHostname($value) {
        if ($value === '' || $value === null) {
            return true; // optional field
        }
        if (filter_var($value, FILTER_VALIDATE_IP)) {
            return true;
        }
        return preg_match('/^(?=.{1,253}$)[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$/', $value) === 1;
    }

    public static function validatePort($port) {
        if ($port === '' || $port === null) {
            return true; // optional field
        }
        return filter_var($port, FILTER_VALIDATE_INT, array('options' => array('min_range' => 1, 'max_range' => 65535))) !== false;
    }

    /**
     * validateCidr - a real IPv4/IPv6 address or CIDR block for
     * local_net -- rejects free text (TASK-0017/0018's own security
     * requirement, "validation of identify CIDRs" generalized to every
     * network-typed field this task introduces).
     */
    public static function validateCidr($value) {
        if (strpos($value, '/') === false) {
            return filter_var($value, FILTER_VALIDATE_IP) !== false;
        }
        list($address, $prefix) = explode('/', $value, 2);
        if (filter_var($address, FILTER_VALIDATE_IP) === false) {
            return false;
        }
        if (!ctype_digit($prefix)) {
            return false;
        }
        $prefix = (int) $prefix;
        $max = filter_var($address, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) ? 32 : 128;
        return $prefix >= 0 && $prefix <= $max;
    }

    /**
     * validateCertPath - TASK-0029A. This is a Model B (externally-
     * managed certificate paths) field: an absolute, in-CONTAINER
     * filesystem path an admin has already placed real certificate/key
     * material at (see docs/tasks/0029a-tls-transport-certificate-management.md
     * CONFIG OWNERSHIP) -- never PEM content pasted into the form. Only
     * validates syntax (absolute, no NUL bytes, reasonable length); real
     * filesystem existence/readability is checked separately by
     * inspectCertificateFile()/keyFileExists() since that needs a
     * filesystem call, not a pure string check.
     */
    public static function validateCertPath($path) {
        if ($path === '' || $path === null) {
            return true; // optional field
        }
        if (!is_string($path) || strlen($path) > 255 || strpos($path, "\0") !== false) {
            return false;
        }
        return $path[0] === '/';
    }

    public static function validateMethod($method) {
        return in_array((string) $method, self::$tlsMethods, true);
    }

    /**
     * inspectCertificateFile - TASK-0029A Phase 8 validation: does this
     * path exist, is it readable, does it parse as a real X.509 PEM
     * certificate? Certificate files are deliberately world-readable
     * (0644, see docker/asterisk-entrypoint.sh) -- a public certificate
     * is meant to be handed to every TLS client anyway -- so the app
     * container (a different UID than the asterisk container's own
     * asterisk user) can always read and parse it here. This is the
     * ONLY half of the cert/key pair SENMA validates directly; see
     * keyFileExists()'s own docblock for why the private key half
     * cannot be (and must not be) parsed the same way.
     *
     * @param string $path absolute in-container path
     * @return array('exists' => bool, 'readable' => bool, 'valid' => bool,
     *               'subject' => string|null, 'not_after' => string|null,
     *               'error' => string|null)
     */
    public static function inspectCertificateFile($path) {
        $result = array('exists' => false, 'readable' => false, 'valid' => false,
            'subject' => null, 'not_after' => null, 'error' => null);
        if ($path === '' || $path === null) {
            $result['error'] = 'empty path';
            return $result;
        }
        if (!file_exists($path)) {
            $result['error'] = 'file does not exist';
            return $result;
        }
        $result['exists'] = true;
        if (!is_readable($path)) {
            $result['error'] = 'file exists but is not readable by the web application process';
            return $result;
        }
        $result['readable'] = true;
        $pem = file_get_contents($path);
        $cert = $pem !== false ? @openssl_x509_read($pem) : false;
        if ($cert === false) {
            $result['error'] = 'file is not a valid PEM X.509 certificate';
            return $result;
        }
        $parsed = openssl_x509_parse($cert);
        if ($parsed === false) {
            $result['error'] = 'certificate could not be parsed';
            return $result;
        }
        $result['valid'] = true;
        $result['subject'] = isset($parsed['name']) ? $parsed['name'] : null;
        $result['not_after'] = isset($parsed['validTo_time_t']) ? date('Y-m-d H:i:s', $parsed['validTo_time_t']) : null;
        return $result;
    }

    /**
     * keyFileExists - TASK-0029A. Deliberately existence-only, NOT
     * content validation. The private key file is 0600, owned by the
     * asterisk container's own `asterisk` user (docker/asterisk-entrypoint.sh)
     * -- the app container's www-data user (a DIFFERENT uid, even though
     * both share the senma-config GROUP for unrelated, non-secret files)
     * cannot and must not read its bytes. `file_exists()` only needs
     * directory-traversal (execute) permission on parent directories,
     * which it always has, so this can still catch the single most
     * common real mistake (typo'd/wrong path) without ever touching key
     * material. Whether the key is valid/matches its certificate is
     * proven by Asterisk's own runtime apply instead -- see
     * docs/tasks/0029a-tls-transport-certificate-management.md's
     * VALIDATION and RUNTIME APPLY sections for why this split is the
     * deliberate, secure design, not a shortcut.
     *
     * @return array('exists' => bool, 'mode_warning' => string|null)
     */
    public static function keyFileExists($path) {
        $result = array('exists' => false, 'mode_warning' => null);
        if ($path === '' || $path === null || !file_exists($path)) {
            return $result;
        }
        $result['exists'] = true;
        $perms = @fileperms($path);
        if ($perms !== false && ($perms & 0077) !== 0) {
            // Readable/writable by group and/or other -- stat() alone
            // (no read access needed) is enough to see this. Advisory
            // only: never block a save over it, an admin fixing urgent
            // TLS connectivity should not be locked out by a permission
            // warning, but they must be told.
            $result['mode_warning'] = sprintf('private key file mode is %o (expected 0600 -- readable by more than its owner)', $perms & 0777);
        }
        return $result;
    }

    /**
     * findActiveWssCertConflict - TASK-0029A. Asterisk's built-in HTTP
     * server has exactly ONE TLS listener (http.conf's global
     * tlscertfile/tlsprivatekey) -- there is no per-PJSIP-transport TLS
     * context for ws/wss (confirmed live: setting cert_file/priv_key_file
     * directly on a protocol=wss transport object is silently ignored by
     * Asterisk's res_pjsip_transport_websocket, see
     * docs/tasks/0029a-tls-transport-certificate-management.md FINDINGS).
     * So at most ONE enabled ws/wss row may carry certificate material at
     * any time -- a second, different one would silently overwrite the
     * first's certificate in the generated http.conf-level config with
     * no indication anything is wrong. Checked BEFORE save, same
     * "explicit failure over silently broken" principle
     * findCollision() already applies to bind-address collisions.
     *
     * @param string   $certFile   the value being saved (already
     *                 validated non-empty by the caller)
     * @param int|null $excludeId  the row being saved, excluded from
     *                 the comparison
     * @return array|false the conflicting row, or false if none
     */
    public static function findActiveWssCertConflict($certFile, $excludeId = null) {
        $db = Zend_Registry::get('db');
        $select = $db->select()->from('pjsip_transports')
            ->where('protocol IN (?)', array('wss', 'ws'))
            ->where('enabled = 1')
            ->where("cert_file IS NOT NULL AND cert_file != ''")
            ->where('cert_file != ?', $certFile);
        if ($excludeId !== null && $excludeId !== '') {
            $select->where('id != ?', (int) $excludeId);
        }
        return $db->query($select)->fetch();
    }

    /**
     * verifyTlsHandshake - TASK-0029A Phase 9/12: `pjsip show transport
     * <name>` reporting a bind address is proof the OBJECT loaded, not
     * proof its TLS context actually works -- confirmed live: a
     * transport with a broken/mismatched cert_file/priv_key_file still
     * showed up fully "loaded" via that CLI command while a real TLS
     * client got a protocol-level handshake failure (see
     * docs/tasks/0029a-tls-transport-certificate-management.md
     * FINDINGS). This performs one real TLS connection (from the app
     * container, over the shared Docker network) and compares the
     * certificate Asterisk actually PRESENTS against the one this
     * transport is configured to use -- the same "ask the runtime
     * directly, never trust a config-accepted response" principle
     * isRuntimeActive() already applies, one layer deeper.
     *
     * A bind_address of 127.0.0.1 is intentionally unreachable from the
     * app container's own network namespace by design (this project's
     * plain HTTP/WS listener -- docs/tasks/0028z-wss-asterisk-http-enablement.md
     * SECURITY BOUNDARY); that specific, expected case is reported as
     * 'skipped', not 'failed'.
     *
     * @param string $bindAddress the transport's configured bind_address
     * @param int    $bindPort
     * @param string $expectedCertFile absolute in-container path to the
     *               certificate this transport is configured to present
     * @return array('status' => 'match'|'mismatch'|'unreachable'|'skipped',
     *               'detail' => string)
     */
    public static function verifyTlsHandshake($bindAddress, $bindPort, $expectedCertFile) {
        if ($bindAddress === '127.0.0.1') {
            return array('status' => 'skipped', 'detail' => 'bind address is loopback-only by design, not reachable from the application container');
        }
        $expected = @file_get_contents($expectedCertFile);
        if ($expected === false) {
            return array('status' => 'unreachable', 'detail' => 'expected certificate file could not be read for comparison');
        }
        $expectedParsed = openssl_x509_parse($expected);
        if ($expectedParsed === false) {
            return array('status' => 'unreachable', 'detail' => 'expected certificate file did not parse');
        }

        // Connect via the Docker Compose service DNS name, never a raw
        // container IP (project convention, see docker-platform-engineer
        // skill guidance) -- correct for any bind_address that includes
        // the docker-network-facing interface (0.0.0.0 or that interface's
        // own address), which is the only realistic production case.
        $context = stream_context_create(array('ssl' => array(
            'verify_peer' => false,
            'verify_peer_name' => false,
            'capture_peer_cert' => true,
        )));
        $client = @stream_socket_client(
            "ssl://asterisk:" . (int) $bindPort, $errno, $errstr, 5,
            STREAM_CLIENT_CONNECT, $context
        );
        if (!$client) {
            return array('status' => 'unreachable', 'detail' => "TLS connection to asterisk:$bindPort failed: $errstr");
        }
        $params = stream_context_get_params($client);
        fclose($client);
        if (!isset($params['options']['ssl']['peer_certificate'])) {
            return array('status' => 'unreachable', 'detail' => 'connected, but no certificate was presented');
        }
        $presentedParsed = openssl_x509_parse($params['options']['ssl']['peer_certificate']);

        if ($presentedParsed !== false
            && isset($presentedParsed['serialNumber'], $expectedParsed['serialNumber'])
            && $presentedParsed['serialNumber'] === $expectedParsed['serialNumber']
            && $presentedParsed['name'] === $expectedParsed['name']) {
            return array('status' => 'match', 'detail' => "presented certificate matches (subject: {$presentedParsed['name']})");
        }
        $presentedName = $presentedParsed !== false ? $presentedParsed['name'] : 'unparseable';
        return array('status' => 'mismatch', 'detail' => "expected {$expectedParsed['name']}, Asterisk presented $presentedName");
    }

    /**
     * getActiveWssCertTransport - TASK-0029A. The one enabled ws/wss
     * transport (if any) whose certificate should currently drive
     * http.conf's global TLS block. Guaranteed unique by
     * findActiveWssCertConflict() being enforced at save time; `id ASC
     * LIMIT 1` is just a deterministic tie-breaker, never expected to
     * matter in practice.
     *
     * @return array|false
     */
    public static function getActiveWssCertTransport() {
        $db = Zend_Registry::get('db');
        $select = $db->select()->from('pjsip_transports')
            ->where('protocol IN (?)', array('wss', 'ws'))
            ->where('enabled = 1')
            ->where("cert_file IS NOT NULL AND cert_file != ''")
            ->where("priv_key_file IS NOT NULL AND priv_key_file != ''")
            ->order('id ASC')
            ->limit(1);
        return $db->query($select)->fetch();
    }

}
