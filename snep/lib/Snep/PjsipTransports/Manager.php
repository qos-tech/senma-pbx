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

}
