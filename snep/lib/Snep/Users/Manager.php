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
 * Class to manager a Users.
 *
 * @see Snep_Users_Manager
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2014 OpenS Tecnologia
 * @author    Tiago Zimmermann <tiago.zimmermann@opens.com.br>
 *
 * PHP 8 compatibility: every call site invokes these methods statically
 * (Snep_Users_Manager::method(...)); the class is never instantiated, and
 * no method uses $this. Calling a non-static method statically is a fatal
 * Error since PHP 8.0. All methods below declared static to match actual
 * usage (TASK-0002 P1-A). See
 * docs/tasks/0002-php84-compatibility-baseline.md.
 */
class Snep_Users_Manager {

    public function __construct() {

    }

    /**
     * Method to add a user.
     * @param <array> $user
     */
    public static function add($user) {

        $db = Zend_Registry::get('db');

        $insert_data = array('name' => $user['name'],
            'password' => md5($user['password']),
            'email' => $user['email'],
            // TASK-0023: users.dashboard is TEXT NOT NULL with no
            // default -- omitting it fails under strict MariaDB. ''
            // matches the seeded admin row's own historical value, and
            // is exactly what Snep_Dashboard_Manager::get()'s existing
            // is_array(unserialize(...)) fallback already expects. See
            // docs/tasks/0023-users-crud-php84-strict-sql.md §4.
            'dashboard' => '',
            'profile_id' => $user['profile_id'],
            'created' => date('Y-m-d H:i:s'),
            'updated' => date('Y-m-d H:i:s'));

        $db->insert('users', $insert_data);
        $last_id = $db->lastInsertId();

        return $last_id;
    }

    /**
     * Method to remove a user
     * @param <int> $id
     */
    public static function remove($id) {

        $db = Zend_Registry::get('db');

        // TASK-0026C (F8): was raw string interpolation of $id into SQL
        // syntax.
        $db->beginTransaction();
        $db->delete('users', $db->quoteInto('id = ?', $id));

        try {
            $db->commit();
        } catch (Exception $e) {
            $db->rollBack();
        }
    }

    /**
     * Method to remove data of user in table password_recovery
     * @param <int> $id
     */
    public static function removeRecovery($id) {

        $db = Zend_Registry::get('db');

        // TASK-0026C (F8): was raw string interpolation of $id into SQL
        // syntax.
        $db->beginTransaction();
        $db->delete('password_recovery', $db->quoteInto('user_id = ?', $id));

        try {
            $db->commit();
        } catch (Exception $e) {
            $db->rollBack();
        }
    }

    /**
     * removePermission - Method to remove permission a user
     * @param <int> $id
     */
    public static function removePermission($id) {

        $db = Zend_Registry::get('db');

        // TASK-0026C (F8): was raw string interpolation of $id into SQL
        // syntax.
        $db->beginTransaction();
        $db->delete('users_permissions', $db->quoteInto('user_id = ?', $id));

        try {
            $db->commit();
        } catch (Exception $e) {
            $db->rollBack();
        }
    }

    /**
     * addProfile - Adds the id of the profile to the User
     * @param <array> $data
     * @return \Exception|boolean
     */
    public static function addProfile($data) {

        $db = Zend_Registry::get('db');

        $update_data = array('profile_id' => $data['profile'],
            'updated' => date('Y-m-d H:i:s'));

        // TASK-0026C (F8): was raw string interpolation of $data['user']
        // into SQL syntax.
        $db->update("users", $update_data, $db->quoteInto('id = ?', $data['user']));
    }

    /**
     * Method to getAll users
     * @return <Array> $users
     */
    public static function getAll() {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('users');

        $stmt = $db->query($select);
        $users = $stmt->fetchAll();

        return $users;
    }

    /**
     * Method to get a user by id
     * @param <int> $id
     * @return <Array> $users
     */
    public static function get($id) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('users')
                ->where("users.id = ?", $id);

        $stmt = $db->query($select);
        $users = $stmt->fetch();

        return $users;
    }

    /**
     * Method to update a user data
     * @param <Array> $user
     */
    public static function edit($user) {

        $db = Zend_Registry::get('db');

        $update_data = array('name' => $user['name'],
            'password' => $user['password'],
            'email' => $user['email'],
            'profile_id' => $user['profile_id'],
            'created' => $user['created'],
            'updated' => date('Y-m-d H:i:s'));

        // TASK-0026C (F8): was raw string interpolation of $user['id']
        // (the request's own route/POST id param) into SQL syntax.
        $db->update("users", $update_data, $db->quoteInto('id = ?', $user['id']));
    }

    /**
     * addProfileByName - Update profile
     * @param <array> $data
     * @return \Exception|boolean
     */
    public static function addProfileByName($data) {

        $db = Zend_Registry::get('db');
        $db->beginTransaction();
        // TASK-0026C (F8): was raw string interpolation of $data['box']
        // (posted as duallistbox_profile[]) into SQL syntax -- the exact
        // mass-privilege-escalation sink the audit named: an
        // always-true condition here reassigned EVERY user's profile_id
        // in one request.
        $where = $db->quoteInto('`users`.`name` = ?', $data['box']);

        try {

            $value = array("users.profile_id" => (int) $data['id']);

            $db->update("users", $value, $where);
            $db->commit();

            return true;
        } catch (Exception $e) {

            $db->rollBack();
            return $e;
        }
    }

    /**
     * removeProfileByName - Update user for profile default
     * @param <string> $name
     * @param <int> $id
     */
    public static function removeProfileByName($name) {

        $db = Zend_Registry::get('db');

        $update_data = array('profile_id' => 1,
            'updated' => date('Y-m-d H:i:s'));

        // TASK-0026C (F8): was raw string interpolation of $name into
        // SQL syntax.
        $db->update("users", $update_data, $db->quoteInto('name = ?', $name));
    }

    /**
     * Method to get users by name
     * @param <string> $id
     * @return Array
     */
    public static function getName($name) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from("users", array("id", "name"))
                ->where("users.name = ?", $name);

        $stmt = $db->query($select);
        $user = $stmt->fetch();

        return $user;
    }

    /**
     * Method to add a permission user if the queue .
     * @param <int> $queue
     */
    public static function addQueuesPermission($id,$queue_id) {

        $db = Zend_Registry::get('db');

        $insert_data = array('user_id' => $id,
            'queue_id' => $queue_id);

        $db->insert('users_queues_permissions', $insert_data);
    }

    /**
     * Method to get a user by id
     * @param <int> $id
     * @return <Array> $users
     */
    public static function getQueuesPermission($id) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('users_queues_permissions')
                ->where("users_queues_permissions.user_id = ?", $id);

        $stmt = $db->query($select);
        $queues = $stmt->fetchAll();

        return $queues;
    }

    /**
     * removeQueuesPermission - Method to remove permission queues a user
     * @param <int> $id
     */
    public static function removeQueuesPermission($id) {

        $db = Zend_Registry::get('db');

        // TASK-0026C (F8): was raw string interpolation of $id into SQL
        // syntax.
        $db->beginTransaction();
        $db->delete('users_queues_permissions', $db->quoteInto('user_id = ?', $id));

        try {
            $db->commit();
        } catch (Exception $e) {
            $db->rollBack();
        }
    }

}

?>