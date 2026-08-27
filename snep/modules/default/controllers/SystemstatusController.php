<?php
/**
 *  This file is part of SNEP.
 *
 *  SNEP is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  SNEP is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with SNEP.  If not, see <http://www.gnu.org/licenses/>.
 */

require_once 'lib/Zend/Controller/Action.php';
require_once "includes/AsteriskInfo.php";
require_once 'includes/functions.php';;

/**
 * SystemStatus controller.
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2013 OpenS Tecnologia
 */
class SystemstatusController extends Zend_Controller_Action {

    /**
     * TASK-0022: the resources.xml-registered permission that gates
     * destructive Asterisk operations. See
     * docs/tasks/0022-system-administration-authorization.md.
     */
    const ASTERISK_OPERATIONS_PERMISSION = 'default_asterisk-operations_write';

    private $systemInfo = array();
    private $sysInfo = array() ;

    /**
     * indexAction - List information of services
     */
    public function indexAction() {

        //Disables layout so jQuery .get() can call pure HTML at the index page.
        $this->_helper->layout()->disableLayout();

        $auth = Zend_Auth::getInstance();
        $username = $auth->getIdentity();
        $this->view->breadcrumb = $this->view->translate("Welcome to Snep, ") . $username ;

        $db = Zend_Registry::get('db');

        if(!$_SESSION['cloud_noticed']){
          $tdmboards = $this->CloudNotice();
          $_SESSION['cloud_noticed'] = true;
        }

    		// TASK-0006: this is a loopback request to the same Apache container,
    		// not to whatever host/port the browser used to reach us. The
    		// host-published MAG_HTTP_PORT (e.g. 8080) is a Docker port mapping
    		// that has no meaning inside the container -- Apache only ever
    		// listens on 80 here (docker/apache-mag.conf). $_SERVER['SERVER_PORT']
    		// must not be used either: under Apache's default UseCanonicalName
    		// Off, it reflects the client's Host header (confirmed: a request
    		// sent with Host: localhost:9999 made SERVER_PORT report 9999),
    		// not the server's actual listening port. See
    		// docs/tasks/0006-systemstatus-runtime.md.
    		$linfoData = new Zend_Http_Client('http://127.0.0.1:80' . str_replace("/index.php", "", $this->getFrontController()->getBaseUrl()) . '/lib/linfo/index.php?out=xml');

        try {
            $linfoData->request();
            $sysInfo = $linfoData->getLastResponse()->getBody();
            $this->sysInfo = simplexml_load_string($sysInfo);
        } catch (Zend_Http_Client_Exception $ex) {
            echo $ex;
        }

        // Server uptime

        $uptimeRaw = (array)$this->sysInfo->core->uptime;

        //$uptimeRaw = explode(",", $uptimeRaw[0]);
        $uptimeRaw = explode(";", $uptimeRaw[0]);
        $uptimeRaw = $uptimeRaw[0];
        $search =  array('day', 'days', 'hour', 'hours', 'minute', 'minutes', 'second', 'seconds');
        $replace = array();
        foreach ($search as $key => $value) {
            array_push($replace,$this->view->translate($value));
        }

        $uptimeRaw = str_replace($search,$replace,$uptimeRaw);

        $this->systemInfo['uptime'] = $uptimeRaw;


        // Mysql
        $this->systemInfo['mysql'] = trim(exec("mysql -V | awk -F, '{ print $1 }' | awk -F'mysql' '{ print $2 }'"));

        //Versao do S.O
        if (file_exists("/etc/slackware-version")) {
            exec("cat /etc/slackware-version", $linuxVer);
            $this->systemInfo['linux_ver'] = $linuxVer[0];
        }

        if (file_exists("/etc/redhat-release")) {
            exec("cat /etc/redhat-release", $linuxVer);
            $this->systemInfo['linux_ver'] = $linuxVer[0];
        } else {
            exec("cat /etc/issue", $linuxVer);
            $this->systemInfo['linux_ver'] = substr($linuxVer[0], 0, strpos($linuxVer[0], "\\"));
        }

        // Kernel
        $this->systemInfo['linux_kernel'] = exec("uname -sr");

        // Installed Modules
        $this->systemInfo['modules'] = array();
        $modules = Snep_Modules::getInstance()->getRegisteredModules();
        foreach ($modules as $module) {
            $this->systemInfo['modules'][] = array(
                "name" => $module->getName(),
                "version" => $module->getVersion(),
                "description" => $module->getDescription()
            );
        }
        $new_version = Snep_Version::getNewVersions();
        $this->view->new_version = $new_version;
        // Zend_Debug::Dump($new_version);exit;

        $this->statusbar_info();

        $this->view->indexData = $this->systemInfo ;

        // TASK-0021: restart controls live on this same page (no separate
        // navigation/layout, per the task's own "one central action, no
        // duplicate/parallel status system" requirement). See
        // docs/tasks/0021-asterisk-operational-restart.md.
        if (empty($_SESSION['snep_restart_csrf_token'])) {
            $_SESSION['snep_restart_csrf_token'] = bin2hex(random_bytes(32));
        }
        $this->view->restart_csrf_token = $_SESSION['snep_restart_csrf_token'];
        $this->view->active_call_count = Snep_Asterisk_Operations::getActiveCallCount();
        $this->view->restart_state = Snep_Asterisk_Operations::getRestartState();
        // TASK-0022: server-side only -- drives whether the destructive
        // restart buttons render at all. This is a UX nicety, NOT the
        // enforcement boundary: restartDispatchAction() re-checks this
        // exact same authorization independently, since a hidden button
        // is never a security control. See
        // docs/tasks/0022-system-administration-authorization.md §6/§13.
        $this->view->can_restart_asterisk = $this->userCanOperateAsterisk();
    }

    /**
     * userCanOperateAsterisk - TASK-0022. Server-side authorization for
     * destructive Asterisk operations, checked directly via the existing
     * Snep_Permission_Manager data layer (profiles_permissions +
     * users_permissions, per-user override wins), exactly like
     * Snep_PermissionPlugin::preDispatch()'s own logic -- but invoked
     * directly here rather than through that plugin, since the
     * investigation proved the plugin structurally cannot protect this
     * action (SystemstatusController has no resources.xml entry of its
     * own, and the plugin's action-name whitelist does not include
     * "restart-dispatch" regardless). See
     * docs/tasks/0022-system-administration-authorization.md §2/§5/§7.
     *
     * Preserves the application's existing, pre-existing legacy
     * superuser convention ($_SESSION['id_user'] == "1" bypasses every
     * permission check in this codebase already -- Snep_PermissionPlugin,
     * Snep_Menu, Snep_Profiles_Manager's own user-exclusion queries all
     * do this same comparison). This is documented compatibility
     * behavior and remaining RBAC debt (§7/§17), not a new special case
     * introduced by this task.
     *
     * @return bool
     */
    private function userCanOperateAsterisk() {
        if (empty($_SESSION['id_user'])) {
            return false;
        }
        if ($_SESSION['id_user'] == "1") {
            return true;
        }

        $profileId = Snep_Profiles_Manager::getIdProfile($_SESSION['id_user']);
        $groupPermission = Snep_Permission_Manager::get($profileId, self::ASTERISK_OPERATIONS_PERMISSION);
        $userPermission = Snep_Permission_Manager::getUser($_SESSION['id_user'], self::ASTERISK_OPERATIONS_PERMISSION);

        // Per-user override wins over the profile/group default, exactly
        // matching Snep_PermissionPlugin::preDispatch()'s own precedence.
        $effective = ($userPermission !== false) ? $userPermission : $groupPermission;

        return $effective && $effective['allow'];
    }

    /**
     * logRestartAuthorizationDenied - TASK-0022. Uses the exact same
     * proven mechanism as Snep_Asterisk_Operations::logRestart()
     * (Snep_Audit_Manager + error_log(), never Zend_Registry::get('log')
     * -- TASK-0019/0020 already proved that is never registered in the
     * real bootstrap). Logs only user id/username/IP/attempted mode --
     * never the CSRF token, a password, or an AMI credential. See
     * docs/tasks/0022-system-administration-authorization.md §15.
     */
    private function logRestartAuthorizationDenied($mode) {
        $auth = Zend_Auth::getInstance();
        $username = $auth->hasIdentity() ? $auth->getIdentity() : 'unknown';
        $userId = $_SESSION['id_user'] ?? 'unknown';
        $ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
        $description = sprintf(
            'Restart dispatch denied -- user_id=%s user=%s ip=%s mode=%s missing_permission=%s',
            $userId,
            $username,
            $ip,
            $mode ?: 'unknown',
            self::ASTERISK_OPERATIONS_PERMISSION
        );
        try {
            Snep_Audit_Manager::SaveLog('RestartDenied', 'asterisk', $userId, $description);
        } catch (Exception $e) {
            error_log('SystemstatusController: failed to write audit log: ' . $e->getMessage());
        }
        error_log('SystemstatusController: ' . $description);
    }

    /**
     * restartDispatchAction - TASK-0021. POST-only, CSRF-protected,
     * dispatches an explicit graceful/immediate Asterisk restart via
     * Snep_Asterisk_Operations and returns promptly (never waits for the
     * restart itself to finish -- see that class's docblock). Reuses this
     * controller's existing authentication boundary (Snep_AuthPlugin:
     * any authenticated SENMA session); see the implementation notes in
     * docs/tasks/0021-asterisk-operational-restart.md for why no more
     * granular per-profile permission currently applies to this
     * controller at all (a pre-existing condition, not introduced here).
     */
    public function restartDispatchAction() {
        $this->_helper->layout()->disableLayout();
        $this->_helper->viewRenderer->setNoRender();
        $this->getResponse()->setHeader('Content-Type', 'application/json');

        if (!$this->getRequest()->isPost()) {
            $this->getResponse()->setHttpResponseCode(405);
            echo json_encode(array('ok' => false, 'error' => 'POST required'));
            return;
        }

        // TASK-0022: authorization before CSRF, before mode validation,
        // before any Asterisk contact -- an unauthorized session is
        // rejected here, unconditionally, with no side effect and no
        // information about CSRF-token validity ever computed for it.
        // See docs/tasks/0022-system-administration-authorization.md §10.
        if (!$this->userCanOperateAsterisk()) {
            $this->logRestartAuthorizationDenied($this->getRequest()->getPost('mode'));
            $this->getResponse()->setHttpResponseCode(403);
            echo json_encode(array('ok' => false, 'error' => 'forbidden'));
            return;
        }

        $token = $this->getRequest()->getPost('csrf_token');
        if (empty($token) || empty($_SESSION['snep_restart_csrf_token']) || !hash_equals($_SESSION['snep_restart_csrf_token'], $token)) {
            $this->getResponse()->setHttpResponseCode(403);
            // TASK-0022: identical status/body to the authorization
            // rejection above -- an attacker probing with a stolen or
            // guessed CSRF token learns nothing about permission state
            // either way. See §10 of the investigation doc.
            echo json_encode(array('ok' => false, 'error' => 'forbidden'));
            return;
        }
        // One-shot: consume it, then immediately issue a fresh one so the
        // same page can still dispatch again (e.g. a failed attempt
        // followed by a retry) without a full reload.
        $_SESSION['snep_restart_csrf_token'] = bin2hex(random_bytes(32));

        $mode = $this->getRequest()->getPost('mode');
        $auth = Zend_Auth::getInstance();
        $user = $auth->hasIdentity() ? $auth->getIdentity() : 'unknown';

        if ($mode === 'graceful') {
            $result = Snep_Asterisk_Operations::dispatchGraceful($user);
        } elseif ($mode === 'now') {
            $result = Snep_Asterisk_Operations::dispatchNow($user);
        } else {
            $this->getResponse()->setHttpResponseCode(400);
            echo json_encode(array('ok' => false, 'error' => 'invalid mode'));
            return;
        }

        echo json_encode(array(
            'ok' => $result['dispatched'],
            'result' => $result,
            'csrf_token' => $_SESSION['snep_restart_csrf_token'],
        ));
    }

    /**
     * restartStatusAction - TASK-0021. GET, read-only, polled by the
     * System Status page's JS to observe recovery independently of the
     * dispatch request. Never triggers a restart itself.
     */
    public function restartStatusAction() {
        $this->_helper->layout()->disableLayout();
        $this->_helper->viewRenderer->setNoRender();
        $this->getResponse()->setHeader('Content-Type', 'application/json');
        echo json_encode(Snep_Asterisk_Operations::getRestartState());
    }

    /**
     * statusBarAction - List information of services
     */
    public function statusbarAction() {
        echo "xxxxxxx" ;
        $this->statusbar_info();
        $this->view->indexData = $this->systemInfo ;
    }

    /**
     * statusbar
     *
     * @return array
     */
    public function statusbar_info () {
        // Asterisk Status & Version
        try {
            $astinfo = new AsteriskInfo();
            $astVersionRaw = explode('@', $astinfo->status_asterisk("core show version", "", True));
            preg_match('/Asterisk (.*) built/', $astVersionRaw[0], $astVersion);
        } catch (Exception $e) {

        }
        if (isset($astVersion[1])) {
            $this->systemInfo['asterisk'] = "Asterisk - " . $astVersion[1];
        } else {
            $this->systemInfo['asterisk'] = "Asterisk - ";
        }

		// Snep version
        $config = Zend_Registry::get('config');
		    $this->systemInfo['snep'] = exec('cat '.$config->system->path->base.'/configs/snep_version');

        //CPU Info
        $hard1 = exec("cat /proc/cpuinfo | grep name |  awk -F: '{print $2}'");
        $hard2 = exec("cat /proc/cpuinfo | grep MHz |  awk -F: '{print $2}'");
        $this->systemInfo['hardware'] = trim($hard1 . " , " . $hard2 . " Mhz");

        // $cpuNumber = count(explode('<br />', $this->sysInfo->core->CPU));

        // $cpuUsageRaw = explode(' ', $this->sysInfo->core->load);
        // $sum_cpu = ($cpuUsageRaw[0] + $cpuUsageRaw[1] + $cpuUsageRaw[2]) ;
        // if ($sum_cpu === 0 ) {
        //     $loadAvarege = 0 ;
        // } else {
        //     $loadAvarege = $sum_cpu / 3;
        // }

        // $this->systemInfo['usage'] = round(($loadAvarege * 100) / ($cpuNumber));


        $prevVal = shell_exec("cat /proc/stat");
        $prevArr = explode(' ',trim($prevVal));
        $prevTotal = $prevArr[2] + $prevArr[3] + $prevArr[4] + $prevArr[5];
        $prevIdle = $prevArr[5];
        usleep(0.15 * 1000000);
        $val = shell_exec("cat /proc/stat");
        $arr = explode(' ', trim($val));
        $total = $arr[2] + $arr[3] + $arr[4] + $arr[5];
        $idle = $arr[5];
        $intervalTotal = intval($total - $prevTotal);
        $stat =  intval(100 * (($intervalTotal - ($idle - $prevIdle)) / $intervalTotal));

        $this->systemInfo['usage'] = $stat;


        // RAM Memory
        $this->systemInfo['memory'] = self::sys_meminfo();

        $this->systemInfo['memory']['swap'] = array(
            'total' => $this->byte_convert(floatval($this->sysInfo->memory->swap->core->free)),
            'free' => $this->byte_convert(floatval($this->sysInfo->memory->swap->core->total)),
            'used' => $this->byte_convert(floatval($this->sysInfo->memory->swap->core->used)),
            'percent' => floatval($this->sysInfo->memory->swap->core->total) > 0 ? round(floatval($this->sysInfo->memory->swap->core->used) / floatval($this->sysInfo->memory->swap->core->total) * 100) : 0
        );

        // Hard Disk
        $repeat = array();
        $cont = 0;
        foreach($this->sys_fsinfo() as $key => $partition){

            // verifica valores duplicados de disco
            isset($repeat[$partition['mount_point']]) ? $repeat[$partition['mount_point']] += 1 : $repeat[$partition['mount_point']] = 1;

            foreach($repeat as $x => $value){
                if($partition['mount_point'] == $x && $value == 1){
                    $this->systemInfo['space'][$cont] = $partition;
                    $cont++;
                }
            }
        }
    }

    /**
     * byte_convert
     * @param <int> $size
     * @param <int> $precision
     * @return string
     */
    private function byte_convert($size, $precision = 2) {


        // Sanity check
        if (!is_numeric($size))
            return '?';

        // Get the notation
        $notation = 1024;

        $types = array('B', 'KB', 'MB', 'GB', 'TB');
        $types_i = array('B', 'KiB', 'MiB', 'GiB', 'TiB');
        for ($i = 0; $size >= $notation && $i < (count($types) - 1 ); $size /= $notation, $i++)
            ;
        return(round($size, $precision) . ' ' . ($notation == 1000 ? $types[$i] : $types_i[$i]));
    }

    /**
     * sys_fsinfo
     * @return type
     */
    private function sys_fsinfo() {
        $df = $this->execute_program('df', '-kPh');
        $mounts = explode("\n", $df);
        $fstype = array();
        if ($fd = fopen('/proc/mounts', 'r')) {
            while ($buf = fgets($fd, 4096)) {
                list($dev, $mpoint, $type) = preg_split('/\s+/', trim($buf), 4);
                $fstype[$mpoint] = $type;
                $fsdev[$dev] = $type;
            }
            fclose($fd);
        }

        for ($i = 1; $i < sizeof($mounts); $i++) {
            $ar_buf = preg_split('/\s+/', $mounts[$i], 6);
            if ($fstype[$ar_buf[5]] == "tmpfs")
                continue;
            $results[$i - 1] = array();

            $results[$i - 1]['disk'] = $ar_buf[0];
            $results[$i - 1]['size'] = $ar_buf[1];
            $results[$i - 1]['used'] = $ar_buf[2];
            $results[$i - 1]['free'] = $ar_buf[3];
            $results[$i - 1]['percent'] = $ar_buf[4];
            //$results[$i - 1]['percent'] = round(($results[$i - 1]['used'] * 100) / $results[$i - 1]['size']) . '%';
            $results[$i - 1]['mount_point'] = $ar_buf[5];
            ($fstype[$ar_buf[5]]) ? $results[$i - 1]['fstype'] = $fstype[$ar_buf[5]] : $results[$i - 1]['fstype'] = $fsdev[$ar_buf[0]];
        }

        return $results;
    }

    /**
     * execute_program
     * @param <string> $program
     * @param <string> $params
     * @return type
     */
    private function execute_program($program, $params) {
        $path = array('/bin/', '/sbin/', '/usr/bin', '/usr/sbin', '/usr/local/bin', '/usr/local/sbin');
        $buffer = '';
        while ($cur_path = current($path)) {
            if (is_executable("$cur_path/$program")) {
                if ($fp = popen("$cur_path/$program $params", 'r')) {
                    while (!feof($fp)) {
                        $buffer .= fgets($fp, 4096);
                    }
                    return trim($buffer);
                }
            }
            next($path);
        }
    }

    /**
     * sys_meminfo - information of system
     * @return type
     */
    function sys_meminfo() {
        $results['ram'] = array('total' => 0, 'free' => 0, 'used' => 0, 'percent' => 0);
        $results['swap'] = array('total' => 0, 'free' => 0, 'used' => 0, 'percent' => 0);
        $results['devswap'] = array();

        $bufr = rfts('/proc/meminfo');

        if ($bufr != "ERROR") {
            $bufe = explode("\n", $bufr);
            foreach ($bufe as $buf) {
                if (preg_match('/^MemTotal:\s+(.*)\s*kB/i', $buf, $ar_buf)) {
                    $results['ram']['total'] = $ar_buf[1];
                } else if (preg_match('/^MemFree:\s+(.*)\s*kB/i', $buf, $ar_buf)) {
                    $results['ram']['free'] = $ar_buf[1];
                } else if (preg_match('/^Cached:\s+(.*)\s*kB/i', $buf, $ar_buf)) {
                    $results['ram']['cached'] = $ar_buf[1];
                } else if (preg_match('/^Buffers:\s+(.*)\s*kB/i', $buf, $ar_buf)) {
                    $results['ram']['buffers'] = $ar_buf[1];
                }
            }
            $results['ram']['used'] = $results['ram']['total'] - $results['ram']['free'];
            $results['ram']['percent'] = round(($results['ram']['used'] * 100) / $results['ram']['total']);
            // values for splitting memory usage
            if (isset($results['ram']['cached']) && isset($results['ram']['buffers'])) {
                $results['ram']['app'] = $results['ram']['used'] - $results['ram']['cached'] - $results['ram']['buffers'];
                $results['ram']['app_percent'] = round(($results['ram']['app'] * 100) / $results['ram']['total']);
                $results['ram']['buffers_percent'] = round(($results['ram']['buffers'] * 100) / $results['ram']['total']);
                $results['ram']['cached_percent'] = round(($results['ram']['cached'] * 100) / $results['ram']['total']);
            }

            $bufr = rfts('/proc/swaps');
            if ($bufr != "ERROR") {
                $swaps = explode("\n", $bufr);
                for ($i = 1; $i < (sizeof($swaps)); $i++) {
                    if (trim($swaps[$i]) != "") {
                        $ar_buf = preg_split('/\s+/', $swaps[$i], 6);
                        $results['devswap'][$i - 1] = array();
                        $results['devswap'][$i - 1]['dev'] = $ar_buf[0];
                        $results['devswap'][$i - 1]['total'] = $ar_buf[2];
                        $results['devswap'][$i - 1]['used'] = $ar_buf[3];
                        $results['devswap'][$i - 1]['free'] = ($results['devswap'][$i - 1]['total'] - $results['devswap'][$i - 1]['used']);
                        $results['devswap'][$i - 1]['percent'] = round(($ar_buf[3] * 100) / $ar_buf[2]);
                        $results['swap']['total'] += $ar_buf[2];
                        $results['swap']['used'] += $ar_buf[3];
                        $results['swap']['free'] = $results['swap']['total'] - $results['swap']['used'];
                        $results['swap']['percent'] = round(($results['swap']['used'] * 100) / $results['swap']['total']);
                    }
                }
            }
        }
        return $results;
    }

    private function CloudNotice(){
        // TDM Board inspect
        $db = Zend_Registry::get('db');
        $asterisk = PBX_Asterisk_AMI::getInstance();
        $tdm = array();
        $tdm['tdm'] = array();

        $register = Snep_Register_Manager::get();

        $tdm['auth'] = array(
          'api_key' => $register['api_key'],
          'client_key' => $register['client_key']
        );
        // Khomp Boards
        $khomp = $asterisk->Command('khomp summary concise');
        $tdmkhomp = str_replace("<K> ","",str_getcsv($khomp['data'],"\n"));
        $tdm['tdm']['khomp'] = array("boards"=>array(), "conf"=>array());
        if(count($tdmkhomp) > 2){
                foreach($tdmkhomp as $row => $item){
                   if($row > 2){
                      $line = str_getcsv($item,";");
                      $board = array(
                         "board"    => $line[0],
                         "desc"     => $line[1],
                         "serial"   => $line[2],
                         "channels" => $line[3],
                         "mac"      => $line[4],
                         "ip"       => $line[5],
                         "status"   => $line[6]
                      );
                      array_push($tdm['tdm']['khomp']['boards'],$board);
                   }else if($row > 0){
                      array_push($tdm['tdm']['khomp']['conf'],$item);
                   }
                }
        }
        // End Khomp Boards

        // Dahdi Boards
        $dahdi = $asterisk->Command('dahdi show status');
        $tdmdahdi = str_getcsv($dahdi['data'],"\n");
        $tdm['tdm']['dahdi'] = array("boards"=>array());
        if(count($tdmdahdi) > 0){
                foreach($tdmdahdi as $row => $item){
                   if($row > 1){
                      preg_match("/([a-zA-Z0-9_-]+)\s+.+(Card\s[0-9]).+(Span\s[0-9])\s+([A-Za-z]+)/", $item, $line);
                      if($line[2] != null){
                        $board = array(
                           "board"    => $line[2],
                           "desc"     => $line[1],
                           "span"     => $line[3],
                           "status"   => $line[4]
                        );
                        array_push($tdm['tdm']['dahdi']['boards'],$board);
                      }

                   }
                }
        }
        // End Dahdi Boards



        //$tdm['session'] = $_SESSION;
        $disk = self::sys_fsinfo();
        $tdm['os'] = array(
          "memory" => self::sys_meminfo()['ram']['total'],
          "disk" => $disk
        );

        $ast_v = $asterisk->Command('core show version');
        $asterisk_version = str_getcsv($ast_v['data'],"\n")[1];

        $slt = $db->select()->from('peers')->where('peer_type = ?', 'R');
        $peers = $db->query($slt)->fetchAll();

        $slt = $db->select()->from('peers')->where('peer_type = ?', 'T');
        $trunks = $db->query($slt)->fetchAll();

        $slt = $db->select()->from('queues');
        $queues = $db->query($slt)->fetchAll();

        $tdm['asterisk'] = array(
          "version" => $asterisk_version,
          "peers" => count($peers),
          "trunks" => count($trunks),
          "queues" => count($queues)
        );

        $configs = Snep_Config::getConfiguration('default','host_inspect');

        if($configs['config_value']){
          $tdm['timeout'] = 3;
          $ctx = Snep_Request::http_context($tdm);
          $request = Snep_Request::send_request("{$configs['config_value']}/snep/host/info/{$_SESSION['uuid']}",$ctx);
          if($request['response_code'] == 401){
            $ctx = Snep_Request::http_context($tdm,"PUT");
            $put_request = Snep_Request::send_request("{$configs['config_value']}/snep/host/info/{$_SESSION['uuid']}",$ctx);
          }
        }
        // TDM Board inspection end

    }


}
