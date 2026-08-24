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
 * Classe to manager a Queues.
 *
 * @see Snep_Queues_Manager
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2011 OpenS Tecnologia
 * @author    Rafael Pereira Bozzetti <rafael@opens.com.br>
 *
 * PHP 8 compatibility: every call site invokes these methods statically
 * (Snep_Queues_Manager::method(...)); the class is never instantiated,
 * and no method uses $this. Calling a non-static method statically is a
 * fatal Error since PHP 8.0. All methods below declared static to match
 * actual usage (TASK-0002 P1-A). See
 * docs/tasks/0002-php84-compatibility-baseline.md.
 */
class Snep_Queues_Manager {

    public function __construct() {

    }

    /**
     * Get a queue by id
     * @param int $id
     * @return Array
     */
    public static function get($name) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('queues')
                ->where("queues.name = ?", $name);

        $stmt = $db->query($select);
        $queue = $stmt->fetch();

        return $queue;
    }

    /**
     * Method to get all queues
     * @return <array>
     */
    public static function getQueueAll() {

        $db = Zend_registry::get('db');

        $select = $db->select()
                ->from("queues")
                ->order("name");

        $stmt = $db->query($select);
        $queues = $stmt->fetchAll();

        return $queues;
    }

    /**
     * Add a Queue.
     * @param array $queue
     * @return int
     */
    public static function add($queue) {

        $db = Zend_Registry::get('db');

        $insert_data = array('name' => $queue['name'],
            'musiconhold' => $queue['musiconhold'],
            'announce' => $queue['announce'],
            'context' => $queue['context'],
            'timeout' => $queue['timeout'],
            'queue_youarenext' => $queue['queue_youarenext'],
            'queue_thereare' => $queue['queue_thereare'],
            'queue_callswaiting' => $queue['queue_callswaiting'],
            'queue_thankyou' => $queue['queue_thankyou'],
            'announce_frequency' => $queue['announce_frequency'],
            'retry' => $queue['retry'],
            'wrapuptime' => $queue['wrapuptime'],
            'maxlen' => $queue['maxlen'],
            'servicelevel' => $queue['servicelevel'],
            'strategy' => $queue['strategy'],
            'joinempty' => $queue['joinempty'],
            'leavewhenempty' => $queue['leavewhenempty'],
            'reportholdtime' => $queue['reportholdtime'],
            'memberdelay' => $queue['memberdelay'],
            'weight' => $queue['weight'],
            'ringinuse' => $queue['ringinuse']
        );

        $db->insert('queues', $insert_data);
        return $db->lastInsertId();
    }

    /**
     * Edit a Queue
     * @param array $queue
     */
    public static function edit($queue) {

        $db = Zend_Registry::get('db');

        $update_data = array('musiconhold' => $queue['musiconhold'],
            'announce' => $queue['announce'],
            'context' => $queue['context'],
            'timeout' => $queue['timeout'],
            'queue_youarenext' => $queue['queue_youarenext'],
            'queue_thereare' => $queue['queue_thereare'],
            'queue_callswaiting' => $queue['queue_callswaiting'],
            'queue_thankyou' => $queue['queue_thankyou'],
            'announce_frequency' => $queue['announce_frequency'],
            'retry' => $queue['retry'],
            'wrapuptime' => $queue['wrapuptime'],
            'maxlen' => $queue['maxlen'],
            'servicelevel' => $queue['servicelevel'],
            'strategy' => $queue['strategy'],
            'joinempty' => $queue['joinempty'],
            'leavewhenempty' => $queue['leavewhenempty'],
            'reportholdtime' => $queue['reportholdtime'],
            'memberdelay' => $queue['memberdelay'],
            'weight' => $queue['weight'],
            'ringinuse' => $queue['ringinuse']
        );

        $db->update('queues', $update_data, "name = '{$queue['name']}'");
    }

    /**
     * Remove a Queue
     * @param int $name
     */
    public static function remove($name) {

        $db = Zend_Registry::get('db');

        $db->beginTransaction();
        $db->delete('queues', "name = '$name'");

        try {
            $db->commit();
        } catch (Exception $e) {
            $db->rollBack();
        }
    }

    /**
     * removeQueues - Remove a queues_agent
     * @param <string> $name
     */
    public static function removeQueues($name) {

        $db = Zend_Registry::get('db');

        $db->beginTransaction();
        $db->delete('queues_agent', "queue = '$name'");

        try {
            $db->commit();
        } catch (Exception $e) {
            $db->rollBack();
        }
    }

    /**
     * removeUserPermission
     * @param <string> $queue
     */
    public static function removeUserPermission($id) {

        $db = Zend_Registry::get('db');

        $db->beginTransaction();
        $db->delete('users_queues_permissions', "users_queues_permissions.queue_id = $id");

        try {
            $db->commit();
        } catch (Exception $e) {
            $db->rollBack();
        }
    }

    /**
     * removeQueuePeers
     * @param <string> $queue
     */
    public static function removeQueuePeers($queue) {

        $db = Zend_Registry::get('db');

        $db->beginTransaction();
        $db->delete('queue_peers', "queue_peers.fila = '$queue'");

        try {
            $db->commit();
        } catch (Exception $e) {
            $db->rollBack();
        }
    }

    /**
     * Get queue members
     * @param string $queue
     * @return array
     */
    public static function getMembers($queue) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('queue_members')
                ->where("queue_members.queue_name = ?", $queue);

        $stmt = $db->query($select);
        $queuemember = $stmt->fetchAll();

        return $queuemember;
    }

    /**
     * Get all members
     * @return array
     */
    public static function getAllMembers() {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('peers', array('name', 'canal', 'callerid'))
                ->where("peers.peer_type = 'R'")
                ->where("peers.canal != ''");

        $stmt = $db->query($select);
        $allMembers = $stmt->fetchAll();

        return $allMembers;
    }

    /**
     * Remove queue members
     * @param string $queue
     */
    public static function removeAllMembers($queue) {

        $db = Zend_Registry::get('db');

        $db->beginTransaction();
        $db->delete('queue_members', "queue_name = '$queue'");

        try {
            $db->commit();
        } catch (Exception $e) {
            $db->rollBack();
        }
    }

    /**
     * Remove queue member
     * @param string $member
     */
    public static function removeMember($member) {

        $db = Zend_Registry::get('db');

        $db->beginTransaction();
        $db->delete('queue_members', "membername = '$member'");

        try {
            $db->commit();
        } catch (Exception $e) {
            $db->rollBack();
        }
    }

    /**
     * Insert member on queue
     * @param string $queue
     * @param string $member
     */
    public static function insertMember($queue, $member) {

        $db = Zend_Registry::get('db');

        $insert_data = array('membername' => $member,
            'queue_name' => $queue,
            'interface' => $member);

        $db->insert('queue_members', $insert_data);
    }

    /**
     * getValidationpeers - checks if the queue have member
     * @param <int> $id
     * @return <array>
     */
    public static function getValidationPeers($id) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('queue_members', array('membername'))
                ->where("queue_members.queue_name = ?", $id);

        $stmt = $db->query($select);
        $member = $stmt->fetchall();

        return $member;
    }

    /**
     * getValidation - checks if the queue have member
     * @param <int> $id
     * @return <array>
     */
    public static function getValidationAgent($id) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('queues_agent', array('agent_id'))
                ->where("queues_agent.queue = ?", $id);

        $stmt = $db->query($select);
        $agent = $stmt->fetchall();

        return $agent;
    }

    /**
     * getValidation - checks if the queue is used in the rule
     * @param <int> $id
     * @return <array>
     */
    public static function getValidation($id) {

        $db = Zend_Registry::get('db');

        $rules_query = "SELECT rule.id, rule.desc FROM regras_negocio as rule, regras_negocio_actions_config as rconf WHERE (rconf.regra_id = rule.id AND rconf.value = '$id' AND (rconf.key = 'queue'))";
        $regras = $db->query($rules_query)->fetchAll();

        return $regras;
    }

    /**
     * insertLogFila - insere na tabela logs_users os dados das filas
     * @param <string> $acao
     * @param <array> $add
     */
    public static function insertLogQueue($acao, $add) {

        $db = Zend_Registry::get("db");

        $ip = $_SERVER['REMOTE_ADDR'];
        $auth = Zend_Auth::getInstance();
        $username = $auth->getIdentity();

        $insert_data = array('hora' => date('Y-m-d H:i:s'),
            'ip' => $ip,
            'idusuario' => $username,
            'cod' => $add["name"],
            'param1' => $add["musiconhold"],
            'param2' => $add["context"],
            'value' => "Fila",
            'tipo' => $acao);

        $db->insert('logs_users', $insert_data);
    }

    /**
     * Get all queue for csv file
     * @return <array>
     */
    public static function getCsv() {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('queues', array('name', 'musiconhold', 'context', 'servicelevel'));

        $stmt = $db->query($select);
        $queues = $stmt->fetchall();

        return $queues;
    }

    /**
     * Method to get queue by name
     * @param <string> $id
     * @return Array
     */
    public static function getName($name) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from("queues", array("id","name"))
                ->where("queues.name = ?", $name);

        $stmt = $db->query($select);
        $queue = $stmt->fetch();

        return $queue;
    }

}
