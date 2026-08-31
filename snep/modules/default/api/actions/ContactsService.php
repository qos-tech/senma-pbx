<?php

/*
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

require_once '../../../includes/functions.php';


/**
 * Services Contact
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2017 OpenS Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 */
class ContactsService implements SnepService {

    /**
     * Execute action
     * URL: http://127.0.0.1/snep/modules/default/api/?service=Contact&phone=4899999999&name=Xxxxx
     */
    public function execute() {

    	$config = Zend_Registry::get('config');
      $db = Zend_registry::get('db');

      // get by phone
      if(isset($_GET["phone"])){
        $phone = $_GET["phone"];
      }

      if(isset($_GET["callerid"])){
        $phone = $_GET["callerid"];
      }

      if($phone){
        $select = "select contacts_phone.phone as phone,
        contacts_names.name as name, contacts_group.name as group_name
        from contacts_phone inner join contacts_names
        on contacts_names.id = contacts_phone.contact_id
        inner join contacts_group on contacts_names.group = contacts_group.id
        where " . $db->quoteInto('contacts_phone.phone like ?', '%' . $phone);
      }

      // get by name
      if(isset($_GET["name"])){
        // TASK-0026F1: minimal guard -- the unqualified `name` column is
        // ambiguous once joined against contacts_group (which also has a
        // `name` column), a pre-existing bug independent of SQL-shaping
        // (confirmed live: an ordinary name=John request already fataled
        // identically before this task -- SQLSTATE[23000] "Column 'name'
        // in WHERE is ambiguous"). Qualifying it as contacts_names.name,
        // exactly like the SELECT list already does two lines above, is
        // required to validate the parameterized fix on this line at all;
        // isolated to this one token, not a broader fix of unrelated debt.
        $select = "select contacts_phone.phone as phone,
        contacts_names.name as name, contacts_group.name as group_name
        from contacts_phone inner join contacts_names
        on contacts_names.id = contacts_phone.contact_id
        inner join contacts_group on contacts_names.group = contacts_group.id
        where " . $db->quoteInto('contacts_names.name like ?', '%' . $_GET['name']);
      }

      // TASK-0026F1: minimal guard -- if neither a phone/callerid nor a
      // name was supplied, $select is undefined (pre-existing PHP 8.4
      // crash on $db->query(null), see docs/tasks/0026f1-...). Required
      // here because the parameterized rewrite above still leaves $select
      // unset in exactly that case; returning the same "no match" shape
      // the empty-result branch below already uses is the minimal safe
      // guard, not a broader fix of that debt.
      if (!isset($select)) {
        return array("status" => "empty", "message" => "No entries found.");
      }

      $stmt = $db->query($select);
      $contact = $stmt->fetch();

      if(!empty($contact)){
        $result = array(
          "status" => "ok",
          "contact" => $contact,
          "desc" => $contact['name'] . ' - ' . $contact['group_name']
        );
        if($_GET['redirect']){
          $result["return"] = $contact['group_name'];
        }

      	return $result;

    	}else{
    		return array("status" => "empty", "message" => "No entries found.");
    	}

    }

}
