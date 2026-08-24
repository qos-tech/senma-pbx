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
 * Classe to register a dashboard
 *
 * @see Snep_Register_Manager
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2015 OpenS Tecnologia
 */
class Snep_Register_Manager {

    public function __construct() {

    }

    /**
     * getCountry - Get Country in Database
     * @return <array>
     */
    public function getCountry() {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('core_country',array('id','name'))
                ->order('name');

        $stmt = $db->query($select);
        $countrys = $stmt->fetchAll();

        return $countrys;

    }


    /**
     * getState - Get State in Database
     * @return <array>
     */
    public function getState() {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('core_state',array('id','name'))
                ->order('name');

        $stmt = $db->query($select);
        $states = $stmt->fetchAll();

        return $states;

    }

    /**
     * getCity - Get City in Database
     * @param int $state
     * @return <array>
     */
    public function getCity($id_state) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('core_city',array('id','name'))
                ->where('core_city.state_id = ? ',$id_state)
                ->order('name');

        $stmt = $db->query($select);
        $states = $stmt->fetchAll();

        return $states;

    }

    /**
     * registerITC - Register Snep in ITC
     */
    public function registerITC($api_key,$client_key) {

        $db = Zend_Registry::get('db');
        $db->update("itc_register", array('registered_itc' => true,
                    'api_key' => $api_key,
                    'client_key' => $client_key));
    }

    /**
     * noregister - No Register Snep in ITC
     */
    public function noregister() {

        $db = Zend_Registry::get('db');
        $db->update("itc_register", array('noregister' => true));

    }

    /**
     * get - Get register data in the database
     */
    public function get() {

        $db = Zend_Registry::get('db');

        $select = $db->select()
                ->from('itc_register');

        $stmt = $db->query($select);
        $data = $stmt->fetch();

        return $data;

    }

    /**
     * addDistributions - Add distributions in database
     */
    public function addDistributions($distributions){

        $db = Zend_Registry::get('db');

        $insert_data = array('id_distro' => 1,
        'id_service' => 1,
        'name_service' => 'intercomunexao');

        $db->insert('itc_consumers', $insert_data);
        if(count($distributions) > 0){
          foreach($distributions as $key => $distribution){

              $insert_data = array('id_distro' => $distribution->id,
              'id_service' => $distribution->service->id,
              'name_service' => $distribution->service->name);

              $db->insert('itc_consumers', $insert_data);

          }
  
        }

    }

    /**
     * deleteDistributions - Remove consumers in database
     */
    public static function removeDistributions() {

        $db = Zend_Registry::get('db');

        $db->beginTransaction();

        try {

            $db->delete("itc_consumers");
            $db->commit();

            return true;
        } catch (Exception $e) {

            $db->rollBack();
            return $e;
        }
    }

}
