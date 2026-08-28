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
/**
 * PHP 8 compatibility: every call site across the codebase invokes these
 * methods statically (Snep_Notifications::method(...)); the class is never
 * instantiated, and no method uses $this. Calling a non-static method
 * statically is a fatal Error since PHP 8.0. All methods below declared
 * static to match actual usage. Pulled forward from the P1 Manager-class
 * batch (TASK-0002) because getNoView() is called from the shared page
 * layout, blocking every page. See
 * docs/tasks/0002-php84-compatibility-baseline.md.
 */
class Snep_Notifications {

	/**
     * getNotification -
     * @return <string> HTML rendered with notifications
     */
		 public static function getNotifications($url) {

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
     * TASK-0024: getAll() is the shared-layout hot path (via
     * getNoView(), called from every layout-rendered page) -- it must
     * never require a live, successful vendor request. Now reads from
     * the local core_notifications cache first; only attempts a bounded
     * remote refresh once per CACHE_TTL_SECONDS (tracked via
     * Snep_Config's core_config row, not a new table), falling back to
     * the last-known-good cached data (or an empty array, identical to
     * the application's own pre-existing "no notifications" empty
     * state) on any failure. See
     * docs/tasks/0024-external-api-failure-isolation.md §2/§9/§11/§13.
     * @return <array> $notifications
     */
    public static function getAll() {

        if (!self::cacheIsStale()) {
            return self::getCachedNotifications();
        }

        // Record the attempt BEFORE calling out, so a failed vendor
        // stays "recently checked" for the rest of the TTL window --
        // this is what keeps make smoke deterministic during a vendor
        // outage (at most one attempt per TTL window, not one per page
        // load) and, as a side effect, is also what keeps the failure
        // log entry below from repeating on every page load (§7/§22).
        self::touchSyncTimestamp();

        $fresh = self::fetchFromVendor();
        if ($fresh !== null) {
            self::replaceCachedNotifications($fresh);
            return self::getCachedNotifications();
        }

        return self::getCachedNotifications();
    }

    const CACHE_TTL_SECONDS = 60;
    const SYNC_CONFIG_MODULE = 'default';
    const SYNC_CONFIG_NAME = 'notifications_synced_at';

    private static function cacheIsStale() {
        $configs = Snep_Config::getConfiguration(self::SYNC_CONFIG_MODULE, self::SYNC_CONFIG_NAME);
        if (!$configs || $configs['config_value'] === '') {
            return true;
        }
        return (time() - (int) $configs['config_value']) >= self::CACHE_TTL_SECONDS;
    }

    private static function touchSyncTimestamp() {
        Snep_Config::setConfiguration(self::SYNC_CONFIG_MODULE, self::SYNC_CONFIG_NAME, (string) time());
    }

    /**
     * fetchFromVendor - the actual outbound call, isolated from the
     * caching decision above. Returns a decoded array of notification
     * objects on success, or null on ANY failure (transport failure,
     * non-200, or a payload that doesn't decode to an array) -- null is
     * unambiguous here since a genuinely empty vendor list is still a
     * valid (empty) array, never null.
     */
    private static function fetchFromVendor() {
        $configs = Snep_Config::getConfiguration('default','host_notification');
        if (!$configs || empty($configs['config_value'])) {
            return null;
        }
        $url = $configs["config_value"] . '/' . $_SESSION["uuid"];
        // TASK-0024: 2s, not the previous 5s -- measured evidence in
        // the investigation doc §12; this call now only ever runs once
        // per CACHE_TTL_SECONDS, so the bound matters far less than it
        // used to, but stays short and consistent with Snep_Version's
        // own bounded refresh below.
        $ctx = Snep_Request::http_context(array("timeout"=> 2), "GET");
        $request = Snep_Request::send_request($url, $ctx);
        if ($request['response_code'] != 200 || $request['response'] === false) {
            self::logIntegrationFailure('notifications', $request['response_code']);
            return null;
        }
        $decoded = json_decode($request['response']);
        if (!is_array($decoded)) {
            self::logIntegrationFailure('notifications', $request['response_code'], 'malformed_payload');
            return null;
        }
        return $decoded;
    }

    /**
     * getCachedNotifications - reads core_notifications and shapes it
     * identically to what getAll() already returned from a live fetch
     * (a plain array of stdClass objects with id/title/message/
     * creation_date/status) -- getNoView()'s own `$value->status` and
     * the vendor payload's own json_decode() default (object, not
     * assoc-array) shape both already expect exactly this.
     */
    private static function getCachedNotifications() {
        $db = Zend_Registry::get('db');
        $select = $db->select()->from('core_notifications')->order('creation_date DESC');
        $rows = $db->query($select)->fetchAll();

        $result = array();
        foreach ($rows as $row) {
            $notification = new stdClass();
            $notification->id = $row['id_itc'];
            $notification->title = $row['title'];
            $notification->message = $row['message'];
            $notification->creation_date = $row['creation_date'];
            $notification->status = $row['read'] ? 'read' : 'unread';
            $result[] = $notification;
        }
        return $result;
    }

    /**
     * replaceCachedNotifications - idempotent by construction: a full
     * delete+insert of the small notification set on every successful
     * refresh, rather than a per-row upsert. core_notifications has
     * zero other readers/writers in live use today (getDateLastNotification()/
     * getNotificationWarning() below have no callers anywhere in the
     * codebase -- confirmed via grep during investigation), so there is
     * no conflicting behavior to preserve. title/message/creation_date
     * are core_notifications' own NOT NULL columns (confirmed via
     * DESCRIBE); `from`/`reading_date` are left to their own DB
     * defaults, unused by any current reader.
     */
    private static function replaceCachedNotifications($notifications) {
        $db = Zend_Registry::get('db');
        $db->delete('core_notifications');
        foreach ($notifications as $entry) {
            if (!is_object($entry) && !is_array($entry)) {
                continue;
            }
            $entry = (object) $entry;
            $db->insert('core_notifications', array(
                'id_itc' => $entry->id ?? null,
                'title' => (string) ($entry->title ?? ''),
                'message' => (string) ($entry->message ?? ''),
                'creation_date' => !empty($entry->creation_date) && strtotime($entry->creation_date) !== false
                    ? date('Y-m-d H:i:s', strtotime($entry->creation_date))
                    : date('Y-m-d H:i:s'),
                'read' => (isset($entry->status) && $entry->status === 'unread') ? 0 : 1,
            ));
        }
    }

    /**
     * logIntegrationFailure - TASK-0024 §7/§22. error_log() only (never
     * Zend_Registry::get('log'), still unregistered in the real
     * bootstrap per TASK-0019/0020's own finding). Called at most once
     * per CACHE_TTL_SECONDS window (see getAll()'s own comment above),
     * which is what keeps this from flooding logs during a prolonged
     * outage -- no separate dedup mechanism needed. Never logs
     * credentials, headers, full payloads, or session data.
     */
    private static function logIntegrationFailure($integration, $httpStatus, $category = null) {
        if ($category === null) {
            $category = $httpStatus > 0 ? 'http_status' : 'transport_failure';
        }
        error_log(sprintf(
            'External integration degraded -- integration=%s category=%s http_status=%s',
            $integration, $category, $httpStatus
        ));
    }

    /**
     * Method to get date last notification
     * @return <array> $notification
     */
    public static function getDateLastNotification() {

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
    public static function getNoView() {

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
    public static function getNotification($id) {

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
    public static function getNotificationWarning() {

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
    public static function setRead($id) {
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
    public static function addNotification($title,$message,$id_itc,$from) {


    }


		/**
     * Method to remove a Notification
     * @param <int> $id
     */
    public static function removeNotification($id) {

				$configs = Snep_Config::getConfiguration('default','host_notification');
				$url = $configs["config_value"] . '/' . $_SESSION["uuid"] . '/' . $id;
				$data = array();
				$ctx = Snep_Request::http_context($data, "DELETE");
				$request = Snep_Request::send_request($url, $ctx);
				return json_decode($request['response']);
    }


}
?>
