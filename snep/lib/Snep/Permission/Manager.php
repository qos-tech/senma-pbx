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
 * Classe to manager a Permission.
 *
 * @see Snep_Permission_Manager
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2014 OpenS Tecnologia
 * @author    Tiago Zimmermann <tiago.zimmermann@opens.com.br>
 *
 */
class Snep_Permission_Manager {

    public function __construct() {

    }

    /**
     * Method to get permissions
     * @param <string> $profile
     * @return <array>
     */
    public static function getAllPermissions($profile) {

        $db = Zend_registry::get('db');

        $select = $db->select()
                ->from("profiles_permissions", array("permission_id"))
                ->where('profile_id = ?', $profile)
                ->where('allow = ?', 1);

        $stmt = $db->query($select);
        $fetch = $stmt->fetchAll();

        $result = array();
        foreach ($fetch as $value)
            $result[$value['permission_id']] = $value['permission_id'];
        return $result;
    }

    /**
     * Method to get permissions of user
     * @param <string> $profile
     * @return <array>
     */
    public static function getAllPermissionsUser($id) {

        $db = Zend_registry::get('db');

        $select = $db->select()
                ->from("users_permissions", array("permission_id", "allow"))
                ->where('user_id = ?', $id);

        $stmt = $db->query($select);
        $fetch = $stmt->fetchAll();

        $result = array();
        foreach ($fetch as $value) {

            $result[$value['permission_id']] = $value['permission_id'] . $value['allow'];
        }
        return $result;
    }

    /**
     * Method to remove permissions of user
     * @param <int> $id
     * @param <array> $modules
     */
    public static function removePermissionUser($id, $modules) {

        $db = Zend_Registry::get('db');
        $where[] = "user_id = '$id'";
        $where[] = "allow =" . 0;

        $db->delete("users_permissions", $where);

        foreach ($modules as $key => $value) {

            $db->insert('users_permissions', array(
                "permission_id" => $value,
                "user_id" => $id,
                "created" => date('Y-m-d H:i:s'),
                "updated" => date('Y-m-d H:i:s'),
                "allow" => 0
                    )
            );
        };
    }

    /**
     * Method to add permissions of user
     * @param <int> $id
     * @param <array> $modules
     */
    public static function addPermissionUser($id, $modules) {

        $db = Zend_Registry::get('db');
        $where[] = "user_id = '$id'";
        $where[] = "allow =" . 1;

        $db->delete("users_permissions", $where);

        foreach ($modules as $key => $value) {
            $db->insert('users_permissions', array(
                "permission_id" => $value,
                "user_id" => $id,
                "created" => date('Y-m-d H:i:s'),
                "updated" => date('Y-m-d H:i:s'),
                "allow" => 1
                    )
            );
        };
    }

    /**
     * Method to check for individual permission
     * @param <int> $id
     * @return <boolean>
     */
    public static function existPermission($id) {

        $db = Zend_registry::get('db');

        $select = $db->select()
                ->from("users_permissions")
                ->where('user_id = ?', $id);


        $stmt = $db->query($select);
        $result = $stmt->fetch();

        return $result;
    }

    /**
     * Method to return all resouces of modules
     * @return <array>
     */
    public static function getAll() {

        return Snep_Modules::$resources;
    }

    /**
     * update - Method to add permission
     * @param <array> $resource
     * @param <string> $id
     */
    public static function addPermissionOld($resource, $id) {

        $db = Zend_Registry::get('db');

        $db->insert('profiles_permissions', array(
            "permission_id" => $resource,
            "profile_id" => $id,
            "created" => date('Y-m-d H:i:s'),
            "updated" => date('Y-m-d H:i:s'),
            "allow" => true)
        );
    }

    /**
     * Method to remove permission of profile
     * @param <array> $resource
     * @param <string> $id
     */
    public static function removePermissionProfile($id) {

        $db = Zend_Registry::get('db');

        $where[] = "profile_id = $id";

        $update_data = array('allow' => false,
            'updated' => date('Y-m-d H:i:s'));

        $db->update("profiles_permissions", $update_data, $where);
    }


    /**
     * Method list permissions
     * @param type $id
     * @return type
     */
    public static function getPermissions($id) {

        $db = Zend_registry::get('db');

        $select = $db->select()
                ->from("profiles_permissions", array("permission_id"))
                ->where('profile_id = ?', $id)
                ->where('allow = ?', true);

        $stmt = $db->query($select);
        $fetch = $stmt->fetchAll();

        $result = array();
        foreach ($fetch as $value)
            $result[] = $value['permission_id'];

        return $result;
    }

    /**
     * getIdprofile - Get id of profile
     * @param <int> $id
     * @return <array>
     */
    public static function getIdProfile($id) {

        $db = Zend_registry::get('db');

        $select = $db->select()
                ->from("users", array("profile_id"))
                ->where('id = ?', $id);

        $stmt = $db->query($select);
        return $stmt->fetch();
    }

    /**
     * checkExistenceCurrentResource - Verifica se o resource atual existe.
     * @return <booleano>
     */
    public static function checkExistenceCurrentResource() {

        $resources = Snep_Modules::$resources;

        $request = Zend_Controller_Front::getInstance()->getRequest();

        if($request->getControllerName() == 'route'){
          return true;
        }
        if (!isset($resources[$request->getModuleName()]))
            return false;
        if (!isset($resources[$request->getModuleName()][$request->getControllerName()]))
            return false;
        // if (!isset($resources[$request->getModuleName()][$request->getControllerName()][$request->getActionName()]))
        //     return false;
        return true;
    }

    /**
     * get - Method to get permission
     * @param <string> $group
     * @param <string> $resource
     * @return <array>
     */
    public static function get($group, $resource) {

        $db = Zend_registry::get('db');

        $select = $db->select()
                ->from("profiles_permissions", array("permission_id", "allow"))
                ->where('profile_id = ?', $group)
                ->where('permission_id = ?', $resource)
                ->order("id DESC");

        $stmt = $db->query($select);
        $result = $stmt->fetch();

        return $result;
    }

    /**
     * Method to get permission of user
     * @param <string> $user
     * @param <string> $resource
     * @return <array>
     */
    public static function getUser($user, $resource) {

        $db = Zend_registry::get('db');

        $select = $db->select()
                ->from("users_permissions", array("permission_id", "allow"))
                ->where('user_id = ?', $user)
                ->where('permission_id = ?', $resource)
                ->order("id DESC");

        $stmt = $db->query($select);
        $result = $stmt->fetch();
        return $result;
    }

}
