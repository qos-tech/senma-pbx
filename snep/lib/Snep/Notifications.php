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
 * Snep Notifications
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2015 Opens Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 */
class Snep_Notifications {

	/**
     * getNotification -
     * @return <string> HTML rendered with notifications
     */
		 public function getNotifications($url) {

         $i18n = Zend_Registry::get("i18n");
         $html = "";
         $notifications = self::getAll();

         if($notifications){

 	        foreach ($notifications as $key => $notification) {

                 // number of notifications in the top menu
                 if($key < 3){
     	            $html .= "<li><a href=".$url."/index.php/default/notifications?id=".$notification['id'].">";
     	            $html .= "<div><strong>".$notification['title']."</strong>";
     	            $html .= "<span class='pull-right text-muted'><em>".date("d/m/Y G:i:s", strtotime($notification['creation_date']))."</em>";
     	            $html .= "</spam></div>";
     	            $html .= "<div>".substr($notification['message'], 0,30).'...</div></a></li>';

     	            if($key < 2){
     	            	$html .= "<li class='divider'></li>";
     	            }
                 }
 	        }

 	        $html .= "<li class='divider'></li><li><a class='text-center' ";
 	        $html .= "href='".$url."/index.php/default/notifications?id=all'>";
 	        $html .= "<strong>".$i18n->translate('Read All Messages')."</strong>";
 	        $html .= "</a></li>";


 	    }else{

 	    	$html .= "<li><a class='text-center'>";
        $html .= "<strong>".$i18n->translate('You have no notifications')."</strong>";
        $html .= "</a></li>";

 	    }

      return $html;
   }

		/**
     * Method to get all profiles
     * @return <array> $notifications
     */
    public function getAll() {

				$configs = Snep_Config::getConfiguration('default','host_notification');
				$url = $configs["config_value"] . '/' . $_SESSION["uuid"];
				// get notification in itc
				$ctx = Snep_Request::http_context(array("timeout"=> 5), "GET");
				$request = Snep_Request::send_request($url, $ctx);
				return json_decode($request['response']);
    }

    /**
     * Method to get date last notification
     * @return <array> $notification
     */
    public function getDateLastNotification() {

        $db = Zend_registry::get('db');

        $select = $db->select()
                ->from("core_notifications", array("id_itc"))
                ->order("id_itc DESC");

        $stmt = $db->query($select);
        $notification = $stmt->fetch();
        $last_notification = $notification["id_itc"];

        return $last_notification;
    }


		/**
     * Get notification where not read
     * @return <array> $notification
     */
    public function getNoView() {

			$notifications = self::getAll();
			$notification = array();
			if($notifications){
				foreach ($notifications as $key => $value) {
					if($value->status == 'unread'){
						array_push($notification, $value);
					}
				}

			}

      return $notification;
    }

		/**
     * Method to get all profiles
     * @return <array> $notifications
     */
    public function getNotification($id) {

				$configs = Snep_Config::getConfiguration('default','host_notification');
				$url = $configs["config_value"] . '/' . $_SESSION["uuid"] . "/$id";
				// get notification in itc
				$ctx = Snep_Request::http_context(array("timeout"=> 1), "GET");
				$request = Snep_Request::send_request($url, $ctx);
				$httpcode = $request['response_code'];
				$response = json_decode($request['response']);

				return $response;
    }

    /**
     * Get notification warning where not read
     * @return <boolean>
     */
    public function getNotificationWarning() {

        $db = Zend_registry::get('db');

        $select = $db->select()
                ->from("core_notifications")
                ->where("core_notifications.read = ?",false)
                ->where("core_notifications.title = ?","Warning")
                ->order("creation_date DESC");

        $stmt = $db->query($select);
        $notification = $stmt->fetch();


        if(is_array($notification)){
            $notification = true;
        }

        return $notification;
    }


		/**
     * setRead - Update core_notifications while user notification read
     * @param <int> $id
     */
    public function setRead($id) {
				$configs = Snep_Config::getConfiguration('default','host_notification');
				$url = $configs["config_value"] . '/' . $_SESSION["uuid"] . '/' . $id;
				// get notification in itc
				$data = array(
					"status" => "read"
				);
				$ctx = Snep_Request::http_context($data, "PUT");
				$request = Snep_Request::send_request($url, $ctx);
				return json_decode($request['response']);
    }

    /**
     * addNotification - Method to add notification a snep
     * @param <string> $title
     * @param <string> $notification
     */
    public function addNotification($title,$message,$id_itc,$from) {


    }


		/**
     * Method to remove a Notification
     * @param <int> $id
     */
    public function removeNotification($id) {

				$configs = Snep_Config::getConfiguration('default','host_notification');
				$url = $configs["config_value"] . '/' . $_SESSION["uuid"] . '/' . $id;
				$data = array();
				$ctx = Snep_Request::http_context($data, "DELETE");
				$request = Snep_Request::send_request($url, $ctx);
				return json_decode($request['response']);
    }


}
?>
