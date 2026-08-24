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
 * Classe to manager a Contacts.
 *
 * @see Snep_Contacts_Manager
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2011 OpenS Tecnologia
 * @author    Rafael Pereira Bozzetti <rafael@opens.com.br>
 *
 */
class Snep_Contacts_Manager {

    public function __construct() {

    }

    /**
     * Method to get all contact
     */
    public function getAll() {

        $db = Zend_registry::get('db');

        $select = $db->select()
                ->from("contacts_names")
                ->from("contacts_group", "name as groupName")
                ->where('contacts_names.group = contacts_group.id');

        $stmt = $db->query($select);
        $allGroups = $stmt->fetchAll();

        return $allGroups;
    }

    /**
     * Method to get a contact by id
     * @param <int> $id
     * @return <array>
     */
    public function get($id) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('contacts_names')
                ->where("contacts_names.id = ?", $id);

        $stmt = $db->query($select);
        $contacts = $stmt->fetch();

        return $contacts;
    }

    /**
     * get id of members in group
     * @param <int> $id
     * @return <array>
     */
    public function getMember($id) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('contacts_names', array('id'))
                ->where("contacts_names.group = ?", $id);

        $stmt = $db->query($select);
        $member = $stmt->fetchall();

        return $member;
    }

    /**
     * Method to get phones a contact by id
     * @param <int> $id
     * @return <array>
     */
    public function getPhone($id) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('contacts_phone', array('phone'))
                ->where("contacts_phone.contact_id = ?", $id);

        $stmt = $db->query($select);
        $phone = $stmt->fetchall();

        return $phone;
    }

    /**
     * Method to get all state
     * @return <array>
     */
    public function getStates() {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('core_cnl_state');

        $stmt = $db->query($select);
        $states = $stmt->fetchall();

        return $states;
    }

    /**
     * getCity - Get City in Database
     * @param <string> $state
     * @return <array>
     */
    public function getCity($state) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('core_cnl_city',array('id','name'))
                ->where('core_cnl_city.state = ? ',$state)
                ->order('name');

        $stmt = $db->query($select);
        $states = $stmt->fetchAll();

        return $states;

    }

    /**
     * Method to add a contact.
     * @param array $contact
     * @return int
     */
    public function add($contact) {

        $db = Zend_Registry::get('db');

        $insert_data = array('id' => $contact['id'],
            'name' => $contact['name'],
            'address' => $contact['address'],
            'email' => $contact['email'],
            'id_city' => $contact['city'],
            'id_state' => $contact['state'],
            'cep' => $contact['zipcode'],
            'group' => $contact['group'],
            'created' => date('Y-m-d H:i:s'),
            'updated' => date('Y-m-d H:i:s'));

        $db->insert('contacts_names', $insert_data);

        $id = $db->lastInsertId();

        return $id;
    }

    /**
     * Method to add numbers a contact.
     * @param <array> $contact
     * @return int
     */
    public function addNumber($id, $phone) {

        $db = Zend_Registry::get('db');

        $insert_data = array('contact_id' => $id,
            'phone' => $phone);

        $db->insert('contacts_phone', $insert_data);
    }

    /**
     * Method to remove a contact
     * @param int $id
     */
    public function remove($id) {

        $db = Zend_Registry::get('db');

        $db->beginTransaction();
        $db->delete('contacts_names', "id = '$id'");

        try {
            $db->commit();
        } catch (Exception $e) {
            $db->rollBack();
        }
    }

    /**
     * Method to remove a contact group
     * @param <int> $id
     */
    public function removeGroup($id) {

        $db = Zend_Registry::get('db');

        $db->beginTransaction();
        $db->delete('contacts_names', "`group` = $id");

        try {
            $db->commit();
        } catch (Exception $e) {
            $db->rollBack();
        }
    }

    /**
     * Method to remove phone a contact
     * @param <int> $id
     */
    public function removePhone($id) {

        $db = Zend_Registry::get('db');

        $db->beginTransaction();
        $db->delete('contacts_phone', "contact_id = '$id'");

        try {
            $db->commit();
        } catch (Exception $e) {
            $db->rollBack();
        }
    }

    /**
     * Method to update a contact data
     * @param <array> $data
     */
    public function edit($contact) {

        $db = Zend_Registry::get('db');

        $update_data = array('name' => $contact['name'],
            'address' => $contact['address'],
            'email' => $contact['email'],
            'id_city' => $contact['city'],
            'id_state' => $contact['state'],
            'cep' => $contact['zipcode'],
            'group' => $contact['group'],
            'updated' => date('Y-m-d H:i:s'));

        $db->update("contacts_names", $update_data, "id = '{$contact['id']}'");
    }

    /**
     * Method to return a last inserted id.
     * The Contacts id cannot be a auto increment field
     */
    public function getLastId() {

        $db = Zend_registry::get('db');

        $select = $db->select()
                ->from("contacts_names", array(' max( floor( id ) ) as id'))
                //->order('id DESC')
                ->limit('1');

        $stmt = $db->query($select);
        $lastId = $stmt->fetch();
        $return = $lastId['id'] + 1;

        return $return;
    }

    /**
     * removeByGroupId
     * @param <int> $groupId
     */
    public function removeByGroupId($groupId) {

        $db = Zend_Registry::get('db');

        $db->beginTransaction();
        $db->delete('contacts_names', "contacts_names.group = '$groupId'");

        try {
            $db->commit();
        } catch (Exception $e) {
            $db->rollBack();
        }
    }

}
