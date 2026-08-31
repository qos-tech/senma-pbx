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
 * Class to manager a Profiles.
 *
 * @see Snep_Profiles_Manager
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2014 OpenS Tecnologia
 * @author    Tiago Zimmermann <tiago.zimmermann@opens.com.br>
 *
 * PHP 8 compatibility: every call site invokes these methods statically
 * (Snep_Profiles_Manager::method(...)); the class is never instantiated,
 * and no method uses $this. Calling a non-static method statically is a
 * fatal Error since PHP 8.0. All methods below declared static to match
 * actual usage (TASK-0002 P1-A). See
 * docs/tasks/0002-php84-compatibility-baseline.md.
 */
class Snep_Profiles_Manager {

    public function __construct() {

    }

    /**
     * Method to get all profiles
     * @return <array>
     */
    public static function getAll() {

        $db = Zend_registry::get('db');

        $select = $db->select()
                ->from("profiles");

        $stmt = $db->query($select);
        $profiles = $stmt->fetchAll();

        return $profiles;
    }

    /**
     * Method to add a profile
     * @param <array> $profile
     */
    public static function add($profile) {

        $db = Zend_Registry::get('db');

        $insert_data = array('name' => $profile['name'],
            'created' => date('Y-m-d H:i:s'),
            'updated' => date('Y-m-d H:i:s'));

        $db->insert('profiles', $insert_data);
    }

    /**
     * Method to remove a profile
     * @param <int> $id
     */
    public static function remove($id) {

        $db = Zend_Registry::get('db');

        // TASK-0026C (F8 sibling boundary): was raw string interpolation
        // of $id into SQL syntax.
        $db->beginTransaction();
        $db->delete('profiles', $db->quoteInto('id = ?', $id));

        try {
            $db->commit();
        } catch (Exception $e) {
            $db->rollBack();
        }
    }

    /**
     * Method to remove permission a profile
     * @param <int> $id
     */
    public static function removePermission($id) {

        $db = Zend_Registry::get('db');

        // TASK-0026C (F8 sibling boundary): was raw string interpolation
        // of $id into SQL syntax.
        $db->beginTransaction();
        $db->delete('profiles_permissions', $db->quoteInto('profile_id = ?', $id));

        try {
            $db->commit();
        } catch (Exception $e) {
            $db->rollBack();
        }
    }

    /**
     * Method to get a profile by id
     * @param <int> $id
     * @return <Array>
     */
    public static function get($id) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('profiles')
                ->where("profiles.id = ?", $id);

        $stmt = $db->query($select);
        $profiles = $stmt->fetch();

        return $profiles;
    }

    /**
     * Method to update a profile data
     * @param <Array> $profile
     */
    public static function edit($profile) {

        $db = Zend_Registry::get('db');

        $update_data = array('name' => $profile['name'],
            'created' => $profile['created'],
            'updated' => date('Y-m-d H:i:s'));

        // TASK-0026C (F8 sibling boundary): was raw string interpolation
        // of $profile['id'] into SQL syntax.
        $db->update("profiles", $update_data, $db->quoteInto('id = ?', $profile['id']));
    }

    /**
     * Method to migration users for profile default while remove profile 
     * @param <Array> $member
     * @param <Array> $id
     */
    public static function migration($member) {

        $db = Zend_Registry::get('db');

        $update_data = array('profile_id' => 1,
            'updated' => date('Y-m-d H:i:s'));

        // TASK-0026C (F8 sibling boundary): was raw string interpolation
        // of $member['id'] into SQL syntax.
        $db->update("users", $update_data, $db->quoteInto('id = ?', $member['id']));
    }

    /**
     * Method to get members of profile
     * @param <int> $id
     * @return <array>
     */
    public static function getUsersProfiles($id) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('users', array('id', 'name'))
                ->where("users.profile_id = ?", $id)
                ->where("users.id != ?", 1);

        $stmt = $db->query($select);
        $users = $stmt->fetchall();

        return $users;
    }

    /**
     * Method to get not members of profile
     * @param <int> $id
     * @return <array>
     */
    public static function getUsersnotProfile($id) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from(array("n" => "users"), array("id", "name as nome"))
                ->join(array("g" => "profiles"), 'n.profile_id = g.id', "name")
                ->where("n.profile_id != ?", $id)
                ->where("n.id != ?", 1);

        $stmt = $db->query($select);
        $users = $stmt->fetchall();

        return $users;
    }

    /**
     * Method to get a last id of profile 
     * @return <int> 
     */
    public static function lastId() {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('profiles', array(' max( floor( id ) ) as id'))
                ->limit('1');

        $stmt = $db->query($select);
        $lastId = $stmt->fetch();
        $return = $lastId['id'];

        return $return;
    }

    /**
     * Get id of profile in users
     * @param <int> $id
     * @return <array>
     */
    public static function getIdProfile($id) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('users', array('profile_id'))
                ->where('users.id = ?', $id);

        $stmt = $db->query($select);
        $profile = $stmt->fetch();
        return $profile['profile_id'];
    }

    /**
     * Method to get Profile by name
     * @param <string> $id
     * @return Array
     */
    public static function getName($name) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from("profiles", array("id", "name"))
                ->where("profiles.name = ?", $name);

        $stmt = $db->query($select);
        $profile = $stmt->fetch();

        return $profile;
    }

}

?>
