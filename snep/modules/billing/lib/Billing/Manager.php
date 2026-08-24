<?php

/**
 * Class to manager Bills
 *
 * @see Billing/Billing
 *
 * @category  Snep
 * @package   Billing
 * @copyright Copyright (c) 2013 OpenS Tecnologia
 * @author    Douglas Conrad <conrad@opens.com.br>
 *
 */
class Billing_Manager {

    public function __construct() {
      $this->log = Zend_Registry::get('log');
    }
    /**
    * getAll - Get all bills
    * @return <array>
    */
    public function getAll(){
      $db = Zend_Registry::get('db');
      $select = $db->select()
          ->from('billing',array('area', 'price', 'id'))
          ->from('billing_types',array('billtype' => 'name'))
          ->from('telcos',array('telco' => 'name','telcoid' => 'id'))
          ->join('telcos', 'telcos.id = billing.telco',array())
          ->join('billing_types', 'billing.type = billing_types.id',array('billtypeid' => 'id'))
          ->group('billing.id');
      $bills = $db->query($select)->fetchAll();

      return $bills;

    }
    /**
    * getBillTypes - Get all billing types
    * @return <array>
    */
    public function getBillTypes(){
      $db = Zend_Registry::get('db');
      $select = $db->select()->from('billing_types');

      $bills = $db->query($select)->fetchAll();


      return $bills;

    }
    /**
    * add <array> area, price, telco
    * @return <$id>
    */
    public function add($bill){
      $db = Zend_Registry::get('db');

      $insert_data = array(
        "created" => date("Y-m-d H:i:s"),
        "area" => $bill['area'],
        "type" => $bill['billtype'],
        "price" => $bill['price'],
        "telco" => $bill['telco']
      );

      //Zend_Debug::Dump($insert_data);exit;
      try {
        $db->insert('billing', $insert_data);

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
            ->from('billing',array('area', 'price', 'id'))
            ->from('billing_types',array('billtype' => 'name'))
            ->from('telcos',array('telco' => 'name','telcoid' => 'id'))
            ->join('telcos', 'telcos.id = billing.telco',array())
            ->join('billing_types', 'billing.type = billing_types.id',array('billtypeid' => 'billing_types.id'))
            ->where("billing.id = ?", $id);

        $stmt = $db->query($select);
        $telco = $stmt->fetch();

        return $telco;

    }

    /**
     * Method to get a rate by Area Code
     * @param int $id
     * @return Array
     */
    public function getByArea($area) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
            ->from('billing',array('area', 'price', 'id'))
            ->from('billing_types',array('billtype' => 'name'))
            ->from('telcos',array('telco' => 'name','telcoid' => 'id'))
            ->join('telcos', 'telcos.id = billing.telco',array())
            ->join('billing_types', 'billing.type = billing_types.id',array('billtypeid' => 'billing_types.id'))
            ->where("billing.area = ?", $area);

        $stmt = $db->query($select);
        $telco = $stmt->fetch();

        if(count($telco) > 0){
          return $telco;
        }else{
          return null;
        }


    }

    /**
     * Method to get a rate by rate type
     * @param int $id
     * @return Array
     */
    public function getByType($type) {

        $db = Zend_Registry::get('db');

        $select = $db->select()
            ->from('billing',array('area', 'price', 'id'))
            ->from('billing_types',array('billtype' => 'name'))
            ->from('telcos',array('telco' => 'name','telcoid' => 'id'))
            ->join('telcos', 'telcos.id = billing.telco',array())
            ->join('billing_types', 'billing.type = billing_types.id',array('billtypeid' => 'billing_types.id'))
            ->where("billing_types.id = ?", $type);

        $stmt = $db->query($select);
        $telco = $stmt->fetch();

        if(count($telco) > 0){
          return $telco;
        }else{
          return null;
        }

    }
    /**
     * Method to remove a telco
     * @param int $id
     */
    public function remove($id) {

        $db = Zend_Registry::get('db');

        $db->beginTransaction();
        $db->delete('billing', "id = '$id'");

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
    public function update($bill) {

        $db = Zend_Registry::get('db');
        $update_data = array(
          "area" => $bill['area'],
          "price" => $bill['price'],
          "telco" => $bill['telco'],
          "type" => $bill['billtype']
        );
        $db->beginTransaction();
        $db->update("billing", $update_data, "id = '{$bill['id']}'");
        try {
            $db->commit();
            return true;
        } catch (Exception $e) {
            $db->rollBack();
            return false;
        }

    }

    /**
    * Method to rate a Calls
    * @param <array> uniqueid, userfield, billsec, duration
    */
    public function rate($bill){
      $db = Zend_Registry::get('db');

      if($bill['phone']){

        $this->log->debug("Checking to rate number: {$bill['phone']} on Channel: {$bill['channel']} and Dst Channel: {$bill['dstchannel']}");

        $telco_channel = preg_split("/-/",$bill['dstchannel'])[0];

        $telco_interface = PBX_Interfaces::getChannelOwner($telco_channel);

        if ($telco_interface instanceof Snep_Trunk){

          $telco_id = $telco_interface->getId();

          $telco = $db->query("SELECT telco FROM trunks WHERE id='{$telco_id}'")->fetch();

          $this->log->debug("The Dst Channel is an Telco: {$telco['telco']}");

          $phone = self::checkPhoneNumber($bill['phone']);

          if (isset($phone['area']) && (count($telco) > 0)) {
            if(preg_match("/^[2-5]/",$phone['phone'])){
              $type = 2;
            }else{
              $type = 1;
            }
            $rate = self::getRate($phone['area'], $type, $telco['telco']);
            if(!$rate) {
              $this->log->debug("No rate found");
            }else{
              $this->log->debug("Rate found: [{$rate['price']}] initial increment [{$rate['start_time']}] increment [{$rate['fract']}]");
            }
          }else{
            $res = implode("|", $phone);
            $this->log->info("No rate found for this number: {$phone}");
          }
        }
      }

      if(isset($rate) && isset($bill['billsec'])){

        $price = self::calculatePrice($bill['billsec'],$rate);

        $insert_data = array(
          "date" => date('Y-m-d H:i:s'),
          "uniqueid" => $bill['uniqueid'],
          "userfield" => $bill['userfield'],
          "price" => $price
        );

        $rr = implode("|", $insert_data);
        $this->log->debug("Final rate: $rr");
        //return $insert_data;
        //Zend_Debug::Dump($insert_data);exit;
        try {
          $db->insert('rated_calls', $insert_data);

          return intval($db->lastInsertId());

        }catch(Exception $e){
          return $e;
        }
      }else{
        return;
      }
    }

    /**
    * Method to calculate the price based on billsec time and rate information
    * @param String billsec time in seconds
    * @param <array> price, initial increment time, increment time
    * @return string price
    */
    public function calculatePrice($billsec, $rate){

      $rr = implode("|", $rate);
      $rate['price'] = str_replace(',','.',$rate['price']);
      $this->log->debug("Calculating rate for billsec $billsec: $rr");
      $total_price = 0;
      if($billsec <= 0){
        return 0;
      }

      if($billsec <= $rate['start_time']){
        $result = abs($rate['price'] / 60 * $rate['start_time']);
        $result = sprintf("%3.3f",$result);
        return str_replace('.',',',$result);
      }

      $result = abs($rate['price'] / 60 * $billsec);
      $result = sprintf("%3.3f",$result);
      return str_replace('.',',',$result);

    }

    /**
    * Method to get Rate based on area code, phone type and/or telco
    * @param <array> area, phone_type, telco_id
    * @return string price
    */
    public function getRate($area, $type, $telco){
      $db = Zend_Registry::get('db');
      $select = $db->select()
          ->from('billing',array('area', 'price', 'id'))
          ->join('telcos', 'telcos.id = billing.telco',array('telco' => 'name','telcoid' => 'id','start_time','fract'))
          ->join('billing_types', 'billing.type = billing_types.id',array('billtypeid' => 'billing_types.id'))
          ->where("billing.type = ?", $type)
          ->where("billing.telco = ?", $telco)
          ->where("billing.area = ?", $area);


      $this->log->debug("Searching telco [$telco] type [$type] area [$area]");

      $stmt = $db->query($select)->fetch();
      if(isset($stmt) && isset($stmt['price'])){
        $rr = implode("|", $stmt);
        $this->log->debug("Rate by area found: {$rr}");
        return $stmt;
      }

      // getting default rating by telco
      $select = $db->select()
        ->from('telcos')
        ->where('id = ?', $telco);

      $stmt = $db->query($select)->fetch();

      if($type === 1){
        $stmt['price'] = $stmt['mobile_price'];
      }else{
        $stmt['price'] = $stmt['landline_price'];
      }
      $this->log->debug("Using Rate default found: {$stmt['price']}");
      return $stmt;

    }

    public function checkPhoneNumber($number){
      $size = strlen($number);
      $fn = substr($number,0,1);
      if(($size > 10) && ($size <= 13) && ($fn == 0)){
        $area = substr($number,3,2);
        $phone = substr($number,3);
        $result = array("area" => $area, "phone" => $phone);
      }elseif (($size > 10) && ($size < 13)) {
        $area = substr($number,0,2);
        $phone = substr($number,2);
        $result = array("area" => $area, "phone" => $phone);
      }elseif (($size > 7) && ($size < 11)) {
        $area = 'local';
        $phone = $number;
        $result = array("area" => $area, "phone" => $phone);
      }

      $this->log->debug("Checking number: [$number] phone [{$result['phone']}] area [{$result['area']}]");
      return $result;
    }

}
