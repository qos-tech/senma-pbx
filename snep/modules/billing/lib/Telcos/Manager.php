<?php

/**
 * Class to manager Telcos
 *
 * @see Billing/Telcos
 *
 * @category  Snep
 * @package   Billing
 * @copyright Copyright (c) 2013 OpenS Tecnologia
 * @author    Douglas Conrad <conrad@opens.com.br>
 *
 */
class Telcos_Manager {

    /**
    * getAll - Get all Telcos
    * @return <array>
    */
    public function getAll(){
      $db = Zend_Registry::get('db');
      $select = $db->select()->from('telcos');
      $telcos = $db->query($select)->fetchAll();

      return $telcos;

    }

    /**
    * add <array> name,mobile_price, landline_price, start_time, fract
    * @return <$id>
    */
    public function add($telco){
      $db = Zend_Registry::get('db');

      $insert_data = array(
        "created" => date('Y-m-d H:i:s'),
        "name" => $telco['name'],
        "mobile_price" => $telco['mobile_price'],
        "landline_price" => $telco['landline_price'],
        "start_time" => $telco['start_time'],
        "fract" => $telco['fract']
      );

      try {
        $db->insert('telcos', $insert_data);

        return intval($db->lastInsertId());

      }catch(Exception $e){
        return $e;
      }

    }

    /**
     * Method to get a telco by id
     * @param int $id
     * @return Array
     */
    public function get($id) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
            ->from('telcos')
            ->where("id = ?", $id);

        $stmt = $db->query($select);
        $telco = $stmt->fetch();

        return $telco;

    }


    /**
     * Method to remove a telco
     * @param int $id
     */
    public function remove($id) {

        $db = Zend_Registry::get('db');

        $db->beginTransaction();
        $db->delete('telcos', "id = '$id'");

        try {
            $db->commit();
            return true;
        } catch (Exception $e) {
            $db->rollBack();
            return false;
        }
    }

    /**
     * Method to update a telco
     * @param <array>
     */
    public function update($telco) {

        $db = Zend_Registry::get('db');
        $update_data = array(
          "name" => $telco['name'],
          "mobile_price" => $telco['mobile_price'],
          "landline_price" => $telco['landline_price'],
          "start_time" => $telco['start_time'],
          "fract" => $telco['fract']
        );
        $db->beginTransaction();
        $db->update("telcos", $update_data, "id = '{$telco['id']}'");
        try {
            $db->commit();
            return true;
        } catch (Exception $e) {
            $db->rollBack();
            return false;
        }

    }

}
