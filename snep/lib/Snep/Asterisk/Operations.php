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
 * Explicit, operator-initiated Asterisk restart control (TASK-0021).
 *
 * Every restart/probe exchange in this class opens its OWN short-lived AMI
 * TCP connection with explicit connect/read timeouts (via a raw socket, not
 * Asterisk_AMI::connect()/wait_response()), because TASK-0021's own live
 * testing proved those methods have no read timeout at all: a synchronous
 * `core restart gracefully` issued through the normal
 * PBX_Asterisk_AMI::getInstance() singleton blocked a PHP process for
 * PHP's full default_socket_timeout (60s) before returning an empty,
 * uninformative response. See docs/tasks/0021-asterisk-operational-restart.md
 * §4/§8. This class deliberately does not modify Asterisk_AMI.php or
 * PBX_Asterisk_AMI.php -- every other caller of the shared singleton is
 * completely unaffected.
 *
 * An empty/timed-out response to a restart command is the *expected*,
 * *normal* signal here, never a failure by itself -- actual completion is
 * only ever established by a later, independent readiness probe
 * (self::getRestartState()), never by the dispatch call's own return value.
 *
 * @category  Snep
 * @package   Snep
 */
class Snep_Asterisk_Operations {

    const SESSION_KEY = 'snep_asterisk_restart';

    // Short and deliberately bounded -- see class docblock. Evidence-based
    // per docs/tasks/0021-asterisk-operational-restart.md §4/§5/§13: a
    // healthy exchange completes in well under 100ms; these budgets exist
    // only to guarantee a fast, deterministic return when Asterisk is
    // mid-restart or still waiting on active calls, never to wait for a
    // slow-but-working reply.
    const DISPATCH_CONNECT_TIMEOUT = 3.0;
    const DISPATCH_READ_TIMEOUT = 3;
    const PROBE_CONNECT_TIMEOUT = 2.0;
    const PROBE_READ_TIMEOUT = 2;

    /**
     * getActiveCallCount - "N active calls" from `core show channels
     * count`, via the existing shared AMI singleton. Only ever called
     * before a restart is dispatched, when Asterisk is presumed healthy
     * (this is exactly the same assumption every other existing caller of
     * PBX_Asterisk_AMI::getInstance() already makes), so the singleton's
     * lack of a read timeout is not a risk here.
     *
     * @return int|null null if the count could not be determined.
     */
    public static function getActiveCallCount() {
        try {
            $ami = PBX_Asterisk_AMI::getInstance();
            $result = $ami->Command('core show channels count');
        } catch (Exception $e) {
            return null;
        }
        $data = $result['data'] ?? '';
        if (preg_match('/(\d+)\s+active call/i', $data, $m)) {
            return (int) $m[1];
        }
        return null;
    }

    /**
     * dispatchGraceful - send `core restart gracefully`. Returns as soon
     * as the command has been written and either answered or has timed
     * out waiting for an answer -- never waits for the restart itself to
     * finish. Records a dispatch marker in the session so
     * self::getRestartState() can later distinguish "we asked for this"
     * from "Asterisk is just down".
     */
    public static function dispatchGraceful($user) {
        return self::dispatch('gracefully', $user);
    }

    /**
     * dispatchNow - send `core restart now`. Same contract as
     * dispatchGraceful(), for the immediate/destructive variant.
     */
    public static function dispatchNow($user) {
        return self::dispatch('now', $user);
    }

    private static function dispatch($mode, $user) {
        $activeCalls = self::getActiveCallCount();
        $exchange = self::amiExchange(
            array("core restart {$mode}"),
            self::DISPATCH_CONNECT_TIMEOUT,
            self::DISPATCH_READ_TIMEOUT
        );

        // A connect/login failure here is a real, immediate dispatch
        // failure -- Asterisk could not even be reached to accept the
        // command. A timeout on the restart command ITSELF (stage
        // 'command', $exchange['commands'][0]['timeout'] === true) is, by
        // contrast, the expected, evidence-backed shape of a successful
        // dispatch (docs/tasks/0021-asterisk-operational-restart.md §1/§4/
        // §5) -- Asterisk never sends a framed response to a restart
        // command before this class's own short read budget elapses,
        // whether or not the restart proceeds immediately.
        $dispatched = $exchange['ok'];

        $_SESSION[self::SESSION_KEY] = array(
            'mode' => $mode,
            'dispatched_at' => time(),
            'active_calls_at_dispatch' => $activeCalls,
        );

        $detail = $dispatched
            ? "comando aceito (sem confirmação de conclusão -- ver estado de prontidão)"
            : "falha ao contatar o Asterisk na etapa '{$exchange['stage']}': {$exchange['error']}";

        self::logRestart($mode, $user, $activeCalls, $dispatched, $detail);

        if (!$dispatched) {
            // Nothing to observe -- clear the marker so getRestartState()
            // does not report a phantom pending restart that was never
            // actually sent.
            unset($_SESSION[self::SESSION_KEY]);
        }

        return array(
            'dispatched' => $dispatched,
            'mode' => $mode,
            'active_calls_at_dispatch' => $activeCalls,
            'detail' => $detail,
        );
    }

    /**
     * getRestartState - the normalized state used by both the System
     * Status page's initial render and its polling endpoint. Every
     * state here is directly distinguishable from live evidence recorded
     * in docs/tasks/0021-asterisk-operational-restart.md -- see §7/§11/
     * §12 there for the mapping this method implements.
     *
     * @return array{state:string,detail:string,...}
     */
    public static function getRestartState() {
        $probe = self::probe();
        $dispatch = $_SESSION[self::SESSION_KEY] ?? null;
        $healthy = $probe['login_ok'] && $probe['version_ok'] && $probe['pjsip_ok'] && $probe['odbc_ok'];

        if ($dispatch === null) {
            if ($healthy) {
                return self::state('RUNNING', 'Asterisk operacional.');
            }
            return self::state('UNAVAILABLE', 'Não foi possível conectar ao Asterisk (nenhum reinício foi solicitado pelo SENMA).');
        }

        $elapsed = time() - $dispatch['dispatched_at'];

        if ($healthy) {
            unset($_SESSION[self::SESSION_KEY]);
            return self::state('RUNNING', 'Asterisk reiniciado e operacional novamente.', $dispatch, $elapsed);
        }

        if ($probe['login_ok'] && !$probe['version_ok']) {
            // A fresh AMI login succeeded -- this can only be a NEW
            // process (the old, still-running one would be stuck at the
            // 'login' stage instead, see below), so this is always the
            // "no such command"/module-still-loading transient from §5,
            // for both restart modes -- never "waiting for calls to end"
            // (a login succeeding proves the shutdown-pending lockout is
            // already over). Confirmed live during implementation: an
            // idle graceful restart briefly reported RESTART_PENDING here
            // before this fix, purely because version_ok lagged login_ok
            // by about a second while modules finished loading.
            return self::state('RECOVERING', 'Asterisk reiniciando -- ainda carregando módulos.', $dispatch, $elapsed);
        }

        if (!$probe['login_ok'] && $dispatch['mode'] === 'gracefully' && $probe['stage'] !== 'connect') {
            // Connected (or the banner arrived) but the login exchange
            // itself never completed -- exactly the CLI/AMI lockout
            // observed live while a graceful restart waits on an active
            // call (§4: "cannot be run during shutdown" answered every
            // command, including unrelated ones, for the entire time the
            // call lasted).
            return self::state('RESTART_PENDING', 'Aguardando o fim das chamadas ativas antes de reiniciar.', $dispatch, $elapsed);
        }

        if ($probe['login_ok'] && $probe['version_ok'] && !($probe['pjsip_ok'] && $probe['odbc_ok'])) {
            return self::state('ERROR', 'Asterisk respondeu, mas PJSIP e/ou ODBC ainda não estão prontos.', $dispatch, $elapsed);
        }

        // Not reachable at all (connection refused/failed outright) --
        // the exec() process-replacement gap observed in §5.
        return self::state('RECOVERING', 'Asterisk reiniciando.', $dispatch, $elapsed);
    }

    private static function state($state, $detail, $dispatch = null, $elapsed = null) {
        $out = array('state' => $state, 'detail' => $detail);
        if ($dispatch !== null) {
            $out['mode'] = $dispatch['mode'];
            $out['active_calls_at_dispatch'] = $dispatch['active_calls_at_dispatch'];
            $out['elapsed_seconds'] = $elapsed;
        }
        return $out;
    }

    /**
     * probe - one bounded AMI exchange used by getRestartState(). Never
     * blocks longer than roughly
     * (PROBE_CONNECT_TIMEOUT + PROBE_READ_TIMEOUT * 4), even when
     * Asterisk is completely down or mid-restart -- see the class
     * docblock and docs/tasks/0021-asterisk-operational-restart.md §12.
     */
    private static function probe() {
        $exchange = self::amiExchange(
            array('core show version', 'pjsip show transports', 'odbc show all'),
            self::PROBE_CONNECT_TIMEOUT,
            self::PROBE_READ_TIMEOUT
        );

        $result = array(
            'login_ok' => $exchange['ok'],
            'version_ok' => false,
            'pjsip_ok' => false,
            'odbc_ok' => false,
            'stage' => $exchange['stage'],
        );

        if (!$exchange['ok']) {
            return $result;
        }

        $cmds = $exchange['commands'];
        $result['version_ok'] = isset($cmds[0]) && !$cmds[0]['timeout'] && stripos($cmds[0]['data'], 'Asterisk') !== false;
        $result['pjsip_ok'] = isset($cmds[1]) && !$cmds[1]['timeout'] && stripos($cmds[1]['data'], 'Objects found') !== false;
        $result['odbc_ok'] = isset($cmds[2]) && !$cmds[2]['timeout'] && stripos($cmds[2]['data'], 'Number of active connections') !== false;

        return $result;
    }

    /**
     * amiExchange - minimal, purpose-built AMI client used only by this
     * class: raw socket, explicit connect timeout (fsockopen's own 5th
     * argument) and explicit read timeout (stream_set_timeout()) applied
     * before any blocking read, including the login handshake itself.
     * Deliberately does not reuse Asterisk_AMI::connect()/wait_response()
     * -- see the class docblock for why.
     *
     * @return array{ok:bool,stage:string,error:?string,commands:array}
     *   stage is 'connect'|'banner'|'login'|'ready' (start of command
     *   loop) describing where a failure occurred, or where the exchange
     *   currently stands on success. Each entry in 'commands' is
     *   ['timeout'=>bool,'data'=>string].
     */
    private static function amiExchange(array $commands, $connectTimeout, $readTimeout) {
        $config = Zend_Registry::get('config');
        $server = $config->ambiente->ip_sock;
        $username = $config->ambiente->user_sock;
        $secret = $config->ambiente->pass_sock;
        $port = 5038;
        if (strpos($server, ':') !== false) {
            list($server, $port) = explode(':', $server, 2);
        }

        $errno = $errstr = null;
        $socket = @fsockopen($server, (int) $port, $errno, $errstr, $connectTimeout);
        if ($socket === false) {
            return array('ok' => false, 'stage' => 'connect', 'error' => "{$errno}: {$errstr}", 'commands' => array());
        }
        stream_set_timeout($socket, (int) $readTimeout);

        $banner = fgets($socket, 4096);
        $meta = stream_get_meta_data($socket);
        if ($banner === false || $meta['timed_out']) {
            fclose($socket);
            return array('ok' => false, 'stage' => 'banner', 'error' => 'no banner received', 'commands' => array());
        }

        fwrite($socket, "Action: Login\r\nUsername: {$username}\r\nSecret: {$secret}\r\n\r\n");
        $loginBlock = self::readBlock($socket);
        if ($loginBlock['timeout'] || stripos($loginBlock['data'], 'Response: Success') === false) {
            fclose($socket);
            return array('ok' => false, 'stage' => 'login', 'error' => 'login not confirmed', 'commands' => array());
        }

        $results = array();
        foreach ($commands as $command) {
            fwrite($socket, "Action: Command\r\nCommand: {$command}\r\n\r\n");
            $results[] = self::readBlock($socket);
            if (end($results)['timeout']) {
                // The connection is behaving exactly like the documented
                // shutdown-pending lockout (§4) -- stop issuing further
                // commands on it rather than waiting out the same timeout
                // repeatedly.
                break;
            }
        }

        fclose($socket);
        return array('ok' => true, 'stage' => 'ready', 'error' => null, 'commands' => $results);
    }

    /**
     * readBlock - wait for the next AMI *response* block, transparently
     * skipping over any unsolicited Event blocks first -- Asterisk sends
     * an Event: FullyBooted immediately after a successful login on every
     * connection, and can send others at any time, exactly like
     * Asterisk_AMI::wait_response()'s own `while($type != 'response' &&
     * !$timeout)` loop already accounts for. Confirmed live during
     * implementation: without this, the leftover FullyBooted event was
     * being read back as if it were the response to the very next
     * command sent on the same connection. Still bounded by whatever
     * stream_set_timeout() the caller applied -- each skipped event costs
     * one more bounded read, never an unbounded wait.
     */
    private static function readBlock($socket) {
        while (true) {
            $block = self::readRawBlock($socket);
            if ($block['timeout'] || stripos($block['data'], 'Event:') !== 0) {
                return $block;
            }
        }
    }

    /**
     * readRawBlock - read exactly one AMI block (up to the blank line
     * that terminates it), accumulating "Output:" lines the same way
     * Asterisk_AMI::wait_response() already does for Command replies
     * (TASK-0006B framing). Does not distinguish Event from Response --
     * see readBlock() for that.
     */
    private static function readRawBlock($socket) {
        $data = '';
        $sawAnyLine = false;
        while (true) {
            $line = fgets($socket, 4096);
            $meta = stream_get_meta_data($socket);
            if ($meta['timed_out']) {
                return array('timeout' => true, 'data' => $data);
            }
            if ($line === false) {
                // EOF -- the remote end closed the connection outright
                // (the abrupt-disconnect shape observed for `core restart
                // now`, §5). Treat like a timeout for callers: no framed
                // response was received.
                return array('timeout' => !$sawAnyLine, 'data' => $data);
            }
            $line = rtrim($line, "\r\n");
            if ($line === '') {
                if ($sawAnyLine) {
                    break;
                }
                continue;
            }
            $sawAnyLine = true;
            if (stripos($line, 'Output:') === 0) {
                $data .= substr($line, strlen('Output:')) . "\n";
            } else {
                $data .= $line . "\n";
            }
        }
        return array('timeout' => false, 'data' => $data);
    }

    /**
     * logRestart - audit trail via the existing, already-DB-backed
     * Snep_Audit_Manager (no new logging subsystem, per TASK-0021 item
     * 16), plus error_log() for the application log -- NOT
     * Zend_Registry::get('log'), which TASK-0019/TASK-0020 already
     * proved is never registered in the real bootstrap. Never logs AMI
     * credentials.
     */
    private static function logRestart($mode, $user, $activeCalls, $dispatched, $detail) {
        $description = sprintf(
            'Reinício do Asterisk (%s) solicitado por %s -- chamadas ativas no momento: %s -- %s',
            $mode,
            $user,
            $activeCalls === null ? 'desconhecido' : $activeCalls,
            $detail
        );
        try {
            Snep_Audit_Manager::SaveLog($dispatched ? 'Restart' : 'RestartFailed', 'asterisk', $mode, $description);
        } catch (Exception $e) {
            error_log('Snep_Asterisk_Operations: failed to write audit log: ' . $e->getMessage());
        }
        error_log('Snep_Asterisk_Operations: ' . $description);
    }
}
