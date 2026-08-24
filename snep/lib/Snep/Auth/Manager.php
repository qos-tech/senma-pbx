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
 * Classe to manager a Profiles.
 *
 * @see Snep_Auth_Manager
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2014 OpenS Tecnologia
 * @author    Tiago Zimmermann <tiago.zimmermann@opens.com.br>
 * 
 */
class Snep_Auth_Manager {

    public function __construct() {
        
    }

    /**
     * getUser - Method to get data users by name
     * @return <array>
     */
    public function getUser($name) {

        $db = Zend_registry::get('db');

        $select = $db->select()
                ->from("users")
                ->where("users.name =?", $name);

        $stmt = $db->query($select);
        $user = $stmt->fetch();

        return $user;
    }

    /**
     * getPassword - Method to get data password_recovery by id of user
     * @return <array>
     */
    public function getPassword($name) {

        $db = Zend_registry::get('db');

        $select = $db->select()
                ->from(array("p" => "password_recovery"), array("user_id", "code", "expiration"))
                ->join(array("u" => "users"), 'p.user_id = u.id', "name")
                ->where("u.name = ?", $name)
                ->order("p.created DESC");

        $stmt = $db->query($select);
        $recuperation = $stmt->fetch();

        return $recuperation;
    }

    /**
     * sendEmail - Send mail with code for user
     * @param <array> $user 
     */
    public function sendEmail($user, $msg, $subject) {

        $config = Zend_Registry::get('config');

        $email = $user['email'];
        $mail = new Zend_Mail('UTF-8');
        $mail->setHeaderEncoding(Zend_Mime::ENCODING_BASE64);
        $mail->setBodyHtml($msg);
        $mail->setFrom($config->system->mail);
        $mail->addTo($email);
        $mail->setSubject($subject);
        $mail->send();
    }

    /**
     * addCode - Add data on table password-recovery
     * @param <array> $user
     */
    public function addCode($user) {

        $db = Zend_Registry::get('db');

        $insert_data = array('user_id' => $user['id'],
            'code' => $user['code'],
            'created' => date('Y-m-d H:i:s'),
            'expiration' => $user['expiration']);

        $db->insert('password_recovery', $insert_data);
    }

    /**
     * getUpdatePass - Update password of user
     * @param <array> $data
     */
    public function getUpdatePass($data) {

        $db = Zend_Registry::get('db');

        $update_data = array('password' => md5($data['password']),
            'updated' => date('Y-m-d H:i:s'));

        $db->update("users", $update_data, "name = '{$data['user']}'");
    }

    /**
     * adduuid - Add uuid
     * @param <array> $uuid
     */
    public function adduuid($uuid) {

        $db = Zend_Registry::get('db');

        $insert_data = array('uuid' => $uuid,
            'created' => date('Y-m-d H:i:s'));

        $db->insert('itc_register', $insert_data);
    }

}

?>