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
 *  Class that  controls  the  persistence  in  database  of business rules
 * the Snep.
 *
 * Note about  persistence: The  persistence  control  is  done  in  the  SNEP
 * separate classes. Not in the constructor of the class model as is seen in other
 * Frameworks and architectures. The reason is that if a change in
 * how it is made ​​the persistence of these objects need not be the same
 * changed. This increases the compactness with legacy code and facilitates
 * migration of code between versions.
 * ~henrique
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2010 OpenS Tecnologia
 * @author Henrique Grolli Bassotto
 */
class Snep_ExtensionsGroups_Manager {

    private function __construct() { /* Protegendo métodos dinâmicos */
    }

    private function __destruct() { /* Protegendo métodos dinâmicos */
    }

    private function __clone() { /* Protegendo métodos dinâmicos */
    }

    /**
     * Return a group from the database based on their ID.
     *
     * @param int $id
     * @return array (id <int>, name (string))
     */
    public static function get($id) {

        $db = Zend_Registry::get('db');
        $select = $db->select()
                ->from('core_groups')
                ->where("id = $id");

        $stmt = $db->query($select);
        return $stmt->fetch();
    }

    /**
     * Return all the group's database.
     *
     * @return aray (id <int>, name <string>)
     */
    public static function getAll() {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('core_groups');

        $stmt = $db->query($select);
        return $stmt->fetchAll();
    }

    /**
     * Returns all extensions of the group based on their ID.
     *
     * @param int $id
     * @return array (peer_id <int>, group_id <int>, name <string> )
     */
    public function getExtensionsGroup($id) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
               ->from('core_peer_groups')
               ->from('peers',array('name'))
               ->where('core_peer_groups.group_id = ?', $id)
               ->where('peers.id = core_peer_groups.peer_id');

        $stmt = $db->query($select);
        return $stmt->fetchAll();
    }

    /**
     * Returns all extensions that are not group based on their ID.
     *
     * @param int $id
     * @return array (peer_id <int>, group_id <int>, name <string>, group_name <string> )
     */
    public function getExtensionsNoGroup($id) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
            ->from('core_peer_groups')
            ->joinInner('peers','peers.id = core_peer_groups.peer_id',array('name'))
            ->joinInner('core_groups','core_groups.id = core_peer_groups.group_id',array('group_name'=>'name'))
            ->where('core_peer_groups.group_id != ?', $id)
            ->order('peer_id');

        $stmt = $db->query($select);
        return $stmt->fetchAll();
    }
    /**
     * Returns all extensions in all grroups
     *
     * @return array (peer_id <int>, group_id <int>, name <string>, group_name <string> )
     */
    public function getExtensionsAll() {

        $db = Zend_Registry::get('db');

        $select = $db->select()
            ->from('core_peer_groups')
            ->joinInner('peers','peers.id = core_peer_groups.peer_id',array('name'))
            ->joinInner('core_groups','core_groups.id = core_peer_groups.group_id',array('group_name'=>'name'))
            ->order('peer_id');

        $stmt = $db->query($select);
        return $stmt->fetchAll();
    }

    /**
     * Returns all extensions that exist only in group ID
     *
     * @return <int> $group
     */
    public function getExtensionsOnlyGroup($group) {

        $exten_in  = self::getExtensionsGroup($group) ;
        $exten_out = self::getExtensionsNoGroup($group) ;
        $extensions = array() ;
        foreach ($exten_in as $key_in => $val_in) {
            $flag = true ;
            foreach($exten_out as $key_out => $val_out) {
                if ($val_out['peer_id'] === $val_in['peer_id']) {
                    $flag = false ;
                }
            }
            if ($flag) {
                array_push($extensions,$val_in['peer_id']) ;
            }
        }
        return $extensions ;      

    }

    /**
     * Method to get extension group by name
     *
     * @param <string> $id
     * @return Array
     */
    public function getName($name) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from("core_groups")
                ->where("core_groups.name = ?", $name);

        $stmt = $db->query($select);
        return $stmt->fetch();
    }

    

    /**
     * getValidation - checks if the group is used in the rule
     * @param <int> $id
     * @return <array>
     */
    public function getValidation($id) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('regras_negocio', array('id', 'desc'))
                ->where("regras_negocio.origem LIKE ?", 'G:' . $id)
                ->orwhere("regras_negocio.destino LIKE ?", 'G:' . $id);

        $stmt = $db->query($select);
        $regras = $stmt->fetchall();

        return $regras;
    }


    /**
     * Returns all groups and extensions of the database.
     */
    public function getExtensionsAllGroup() {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('peers', array('id', 'name', 'group'))
                ->from('groups', array('name', 'inherit'))
                ->where('peers.group = groups.name');

        $stmt = $db->query($select);
        $extensionsGroup = $stmt->fetchAll();

        return $extensionsGroup;
    }

    /**
     * Returns all groups of the extension based on their ID.
     * 
     * @param <int> $exten
     */

    public function getGroupsExtensions($exten) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('core_peer_groups')
                ->where('core_peer_groups.peer_id = ?', $exten);

        $stmt = $db->query($select);
        return $stmt->fetchAll();

    }


/**
     * Adds the group to the database based on the value reported.
     *
     * @param <string> $group
     */
    public static function addGroup($group) {

        $db = Zend_Registry::get('db');
        $db->beginTransaction();

        try {
            $db->insert('core_groups', $group);
            $id=$db->lastInsertId();
            $db->commit();
            return $id;
        } catch (Exception $e) {
            $db->rollBack();
            return $e;
        }

    }

    /**
     * Add peer and your group.
     *
     * @param <array> $extensionsGroup
     */
    public function addExtensionsGroup($extensionsGroup) {
        $db = Zend_Registry::get('db');
        $db->beginTransaction();

        try {
            $db->insert('core_peer_groups', $extensionsGroup);
            $db->commit();
            return true;
        } catch (Exception $e) {
            $db->rollBack();
            return $e;
        }
    }

    /**
     * Change the group in the database based on the value reported.
     * 
     * @param <array> $group
     */
    public static function editGroup($group) {

        $db = Zend_Registry::get('db');
        $db->beginTransaction();

        try {

            $value = array('name' => $group['name']);

            $db->update("core_groups", $value, "id = " . $group['id'] );
            $db->commit();

            return true;
        } catch (Exception $e) {

            $db->rollBack();
            return $e;
        }
    }

    /**
     * Update all extensions of a group based on your ID.
     *
     * @param <int> $group - Group id
     * @param <array> $old_members
     * @param <array> $new_members
     * 
     */
    public function updateExtensionsGroup($group, $old_members, $new_members) {

        // Delete all group extensions  based in old_members
        // Insert into Default group if necessary, because any extension must belong one group
        foreach ($old_members as $key => $val) {
            self::deleteGroupExtensions($val) ;
            $result = self::getGroupsExtensions($val['peer_id']) ;
            if ( count($result) === 0  && ! array_key_exists($val['peer_id'], $new_members)) {
                self::addExtensionsGroup(array('peer_id' => $val['peer_id'], 'group_id' => 1));
            }
        }

        // Add new group members based in new_members
        foreach ($new_members as $key => $val) {
            self::addExtensionsGroup(array('peer_id' => $key, 'group_id' => $group));
        }

    }

    /**
     * Update all groups of a extension based in your ID
     *
     * @param <int> $extension - Extension ID
     * @param <array> $old_members
     * @param <array> $new_members
     * 
     */
    public function updateGroupsExtension($extension, $old_members, $new_members) {

        if (count($old_members) > 0) {
            foreach ($old_members as $key => $val) {
               self::deleteGroupExtensions($val) ;
            }
        }
        foreach ($new_members as $key => $value) {
            self::addExtensionsGroup(array('peer_id' => $extension,'group_id' => $value));
        }
    }

    /**
     * Remove a group from the database based on his  ID.
     *
     * @param int $id
     * 
     */
    public static function delete($id) {

        $db = Zend_Registry::get('db');

        $db->beginTransaction();

        try {

            $db->delete("core_groups", "id= ".$id);
            $db->commit();

            return true;
        } catch (Exception $e) {

            $db->rollBack();
            return $e;
        }
    }

    /**
     * Remove group members from the database .
     *
     * @param <array> $member
     */
    public static function deleteGroupExtensions($member) {

        $db = Zend_Registry::get('db');

        $db->beginTransaction();

        try {

            $db->delete("core_peer_groups", 
                array('peer_id = '.$member['peer_id'],
                      'group_id = '.$member['group_id']));
            $db->commit();
            return true;
        } catch (Exception $e) {

            $db->rollBack();
            return $e;
        }
    }

    /**
     * Remove group from DB based in extension ID
     *
     * @param <int> $extension
     */
    public static function deleteExtensionGroups($extension) {

        $db = Zend_Registry::get('db');

        $db->beginTransaction();

        try {

            $db->delete("core_peer_groups", 
                array('peer_id = '.$extension));
            $db->commit();
            return true;
        } catch (Exception $e) {

            $db->rollBack();
            return $e;
        }
    }


}

?>
