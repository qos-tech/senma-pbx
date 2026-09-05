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
 * Generates SENMA-managed native PJSIP transport configuration (TASK-0018).
 *
 * A third sibling of Snep_PjsipConf/Snep_PjsipTrunkConf, not a branch
 * added to either -- transports are a genuinely separate concern
 * (referenced by, never merged into, endpoint/aor/auth/registration
 * objects). See docs/tasks/0017-pjsip-transports-and-templates-architecture.md
 * §4 and docs/tasks/0018-pjsip-transports.md.
 *
 * Replaces the single static [transport-udp] stanza that used to live
 * directly in docker/asterisk-config/pjsip.conf -- every PJSIP
 * extension/trunk that existed before this task implicitly depended on
 * that one static transport; the seeded `udp` row this class reads is
 * byte-identical to it, so migration requires no data backfill (see
 * loadConfFromDb()'s own note below and TASK-0017 §3/§17).
 *
 * @category  Snep
 * @package   Snep
 */
class Snep_PjsipTransportConf {

    /**
     * loadConfFromDb - regenerate the SENMA-managed PJSIP transport
     * config from the current pjsip_transports table and reload
     * res_pjsip.
     *
     * Full stateless rewrite, same property as Snep_PjsipConf/
     * Snep_PjsipTrunkConf: every call reflects exactly the current DB
     * state, so create/edit/delete "just work" without any incremental
     * diff/cleanup logic.
     *
     * Disabled transports (pjsip_transports.enabled = 0) are skipped
     * entirely -- a transport row may exist (e.g. the seeded `wss` row)
     * without ever being emitted into Asterisk's live config, which is
     * how an unconfigured-TLS WSS placeholder stays inert instead of
     * producing a broken/unbindable transport section.
     *
     * @throws PBX_Exception_IO if the target file isn't writable, or if
     *         Asterisk reports the PJSIP reload did not succeed.
     */
    public static function loadConfFromDb() {
        $view = new Zend_View();
        $db = Snep_Db::getInstance();

        $config = Zend_Registry::get('config');
        $asteriskDirectory = $config->system->path->asterisk->conf;

        $transportFileConf = "$asteriskDirectory/snep/senma-pjsip-transports.conf";

        if (!is_writable($transportFileConf)) {
            throw new PBX_Exception_IO($view->translate("Failed to open file %s with write permission.", $transportFileConf));
        }

        $todayDate = date("d/m/Y H:i:s");
        $header  = ";------------------------------------------------------------------------------------\n";
        $header .= "; File: senma-pjsip-transports.conf - SENMA-generated PJSIP transport provisioning\n";
        $header .= ";\n";
        $header .= "; Generated: $todayDate\n";
        $header .= "; Copyright(c) 2008-" . date("Y") . " Opens Tecnologia\n";
        $header .= ";------------------------------------------------------------------------------------\n";
        $header .= "; GENERATED FILE -- do not edit manually. Rewritten in full on every transport\n";
        $header .= "; create/edit/delete (Snep_PjsipTransportConf::loadConfFromDb()). Manual\n";
        $header .= "; edits are lost on the next write. See\n";
        $header .= "; docs/tasks/0018-pjsip-transports.md.\n";
        $header .= ";------------------------------------------------------------------------------------\n";

        $sql = "SELECT * FROM pjsip_transports WHERE enabled = 1 ORDER BY id";
        $transports = $db->query($sql)->fetchAll();

        $sections = "\n";

        foreach ($transports as $transport) {
            $networksSql = "SELECT network FROM pjsip_transport_networks WHERE transport_id = " . (int) $transport['id'] . " ORDER BY id";
            $networks = $db->query($networksSql)->fetchAll(Zend_Db::FETCH_COLUMN);
            $sections .= self::renderTransport($transport, $networks);
        }

        $content = $header . $sections;
        file_put_contents($transportFileConf, $content);

        self::reload($view);

        // TASK-0029A: the wss/ws certificate lives at the Asterisk
        // http.conf level, not on the PJSIP transport object itself
        // (confirmed live: cert_file/priv_key_file set directly on a
        // protocol=wss transport are silently ignored by
        // res_pjsip_transport_websocket -- see
        // docs/tasks/0029a-tls-transport-certificate-management.md
        // FINDINGS). This has to regenerate and reload unconditionally,
        // same "full stateless rewrite" property as everything above --
        // any transport create/edit/delete could have changed which row
        // (if any) is now the active wss cert source.
        self::writeHttpTlsConf($view);
        self::reloadHttp($view);
    }

    /**
     * writeHttpTlsConf - TASK-0029A. Regenerates the #include'd snippet
     * docker/asterisk-config/http.conf's [general] section pulls TLS
     * settings from, sourced from whichever single enabled ws/wss row
     * currently carries certificate material (Manager::
     * getActiveWssCertTransport() -- PjsipTransportsController's own
     * save-time validation, findActiveWssCertConflict(), is what
     * guarantees there is at most one). No row qualifying is a normal,
     * explicit state (a fresh install before any cert is configured, or
     * every wss/ws row disabled) -- tlsenable=no is emitted rather than
     * leaving stale previous settings in place, matching "explicit
     * failure over silently broken behavior".
     */
    private static function writeHttpTlsConf(Zend_View $view) {
        $config = Zend_Registry::get('config');
        $asteriskDirectory = $config->system->path->asterisk->conf;
        $httpTlsFileConf = "$asteriskDirectory/snep/senma-http-tls.conf";

        if (!is_writable($httpTlsFileConf)) {
            throw new PBX_Exception_IO($view->translate("Failed to open file %s with write permission.", $httpTlsFileConf));
        }

        $todayDate = date("d/m/Y H:i:s");
        $header  = ";------------------------------------------------------------------------------------\n";
        $header .= "; File: senma-http-tls.conf - SENMA-generated Asterisk HTTP/WSS TLS settings\n";
        $header .= ";\n";
        $header .= "; Generated: $todayDate\n";
        $header .= "; Copyright(c) 2008-" . date("Y") . " Opens Tecnologia\n";
        $header .= ";------------------------------------------------------------------------------------\n";
        $header .= "; GENERATED FILE -- do not edit manually. Rewritten in full on every transport\n";
        $header .= "; create/edit/delete (Snep_PjsipTransportConf::loadConfFromDb()). Manual\n";
        $header .= "; edits are lost on the next write. Included from docker/asterisk-config/\n";
        $header .= "; http.conf's [general] section. See\n";
        $header .= "; docs/tasks/0029a-tls-transport-certificate-management.md.\n";
        $header .= ";------------------------------------------------------------------------------------\n\n";

        $active = Snep_PjsipTransports_Manager::getActiveWssCertTransport();

        if (!$active) {
            $content = $header . "tlsenable=no\n";
        } else {
            $content = $header;
            $content .= "tlsenable=yes\n";
            $content .= "tlsbindaddr=" . $active['bind_address'] . ":" . $active['bind_port'] . "\n";
            $content .= "tlscertfile=" . $active['cert_file'] . "\n";
            $content .= "tlsprivatekey=" . $active['priv_key_file'] . "\n";
            // http.conf's own TLS option set is narrower than a native
            // PJSIP tls transport's -- confirmed against the options
            // Asterisk's own binary actually recognizes (no http.conf
            // equivalent of verify_server/method exists; those stay
            // meaningful only for protocol=tls, emitted by
            // renderTransport() below). tlscafile+tlsverifyclient is the
            // one pair that IS real here.
            if (!empty($active['verify_client']) && !empty($active['ca_list_file'])) {
                $content .= "tlscafile=" . $active['ca_list_file'] . "\n";
                $content .= "tlsverifyclient=yes\n";
            }
        }

        file_put_contents($httpTlsFileConf, $content);
    }

    /**
     * reloadHttp - TASK-0029A. `module reload http` (not
     * `module reload res_pjsip.so`) is what actually re-reads http.conf
     * -- confirmed live: changing tlscertfile/tlsprivatekey and running
     * `module reload http` immediately presents the new certificate to a
     * fresh TLS connection, no Asterisk/container restart needed (see
     * docs/tasks/0029a-tls-transport-certificate-management.md RUNTIME
     * APPLY / ROTATION). Same explicit-failure contract as reload()
     * above -- never silently assume success.
     *
     * @throws PBX_Exception_IO if the reload did not report success.
     */
    private static function reloadHttp(Zend_View $view) {
        $asteriskAmi = PBX_Asterisk_AMI::getInstance();
        $result = $asteriskAmi->Command("module reload http");

        $data = isset($result['data']) ? $result['data'] : '';

        if (stripos($data, 'reloaded successfully') === false) {
            error_log("Snep_PjsipTransportConf: 'module reload http' did not report success: " . $data);
            throw new PBX_Exception_IO($view->translate("Failed to reload Asterisk HTTP/WSS TLS configuration: %s", $data));
        }
    }

    /**
     * renderTransport - build the [name] transport section for one
     * pjsip_transports row.
     *
     * Every field maps 1:1 to a real PJSIP transport option, verbatim --
     * transports have no chan_sip-era legacy field to translate/interpret
     * (unlike endpoint/aor NAT-flag mapping in the other two generators),
     * so there is no ambiguous-mapping decision to make here at all.
     *
     * @param array $transport one row from `pjsip_transports`
     * @param array $networks  local_net values for this transport (may be empty)
     * @return string
     */
    private static function renderTransport(array $transport, array $networks) {
        $name = $transport['name'];

        $out = "[$name]\n";
        $out .= "type=transport\n";
        $out .= "protocol=" . $transport['protocol'] . "\n";
        $out .= "bind=" . $transport['bind_address'] . ":" . $transport['bind_port'] . "\n";

        if ($transport['domain'] !== '' && $transport['domain'] !== null) {
            $out .= "domain=" . $transport['domain'] . "\n";
        }
        if ($transport['external_signaling_address'] !== '' && $transport['external_signaling_address'] !== null) {
            $out .= "external_signaling_address=" . $transport['external_signaling_address'] . "\n";
        }
        if ($transport['external_signaling_port'] !== '' && $transport['external_signaling_port'] !== null) {
            $out .= "external_signaling_port=" . $transport['external_signaling_port'] . "\n";
        }
        if ($transport['external_media_address'] !== '' && $transport['external_media_address'] !== null) {
            $out .= "external_media_address=" . $transport['external_media_address'] . "\n";
        }
        // local_net: a real, repeatable directive -- one line per
        // pjsip_transport_networks row, not a delimited/joined string
        // (TASK-0017 §2/§18's explicit normalized-representation
        // requirement, carried through all the way to generation).
        foreach ($networks as $network) {
            $out .= "local_net=$network\n";
        }
        $out .= "symmetric_transport=" . ($transport['symmetric_transport'] ? 'yes' : 'no') . "\n";
        $out .= "allow_reload=" . ($transport['allow_reload'] ? 'yes' : 'no') . "\n";

        // TASK-0029A: cert_file/priv_key_file/ca_list_file/verify_client/
        // verify_server/method are REQUIRED-if-set for protocol=tls
        // (Asterisk's native PJSIP TLS transport genuinely reads and
        // uses these -- confirmed live, a real TLS handshake presenting
        // exactly this cert_file's own certificate). They are
        // deliberately NEVER emitted for udp/tcp/ws/wss: udp/tcp have no
        // TLS concept, and confirmed live that Asterisk's
        // res_pjsip_transport_websocket silently IGNORES these same
        // fields for ws/wss -- real TLS control for that protocol lives
        // only in http.conf (see writeHttpTlsConf() above). Emitting
        // them here for ws/wss would misleadingly suggest they do
        // something when they provably do not.
        if ($transport['protocol'] === 'tls') {
            if (!empty($transport['cert_file'])) {
                $out .= "cert_file=" . $transport['cert_file'] . "\n";
            }
            if (!empty($transport['priv_key_file'])) {
                $out .= "priv_key_file=" . $transport['priv_key_file'] . "\n";
            }
            if (!empty($transport['ca_list_file'])) {
                $out .= "ca_list_file=" . $transport['ca_list_file'] . "\n";
            }
            $out .= "verify_client=" . (!empty($transport['verify_client']) ? 'yes' : 'no') . "\n";
            $out .= "verify_server=" . (!empty($transport['verify_server']) ? 'yes' : 'no') . "\n";
            if (!empty($transport['method'])) {
                $out .= "method=" . $transport['method'] . "\n";
            }
        }
        $out .= "\n";

        return $out;
    }

    /**
     * reload - reload res_pjsip only, surfacing failure instead of
     * silently assuming success. Identical mechanism to
     * Snep_PjsipConf::reload()/Snep_PjsipTrunkConf::reload().
     *
     * TASK-0020 item 9 / investigation §11: this used to log via
     * Zend_Registry::get('log'), which is NOT registered in this
     * application's real HTTP request bootstrap -- confirmed live
     * (TASK-0019) that hitting this exact line throws an unrelated
     * "No entry is registered for key 'log'" Zend_Exception, masking
     * whatever the real reload failure was. error_log() has no such
     * dependency and still reaches the same container log every other
     * PHP warning in this app already does (same fix TASK-0019 already
     * applied to the disabled-transport skip paths in
     * Snep_PjsipConf/Snep_PjsipTrunkConf).
     *
     * @throws PBX_Exception_IO if the reload did not report success.
     */
    private static function reload(Zend_View $view) {
        $asteriskAmi = PBX_Asterisk_AMI::getInstance();
        $result = $asteriskAmi->Command("module reload res_pjsip.so");

        $data = isset($result['data']) ? $result['data'] : '';

        if (stripos($data, 'reloaded successfully') === false) {
            error_log("Snep_PjsipTransportConf: 'module reload res_pjsip.so' did not report success: " . $data);
            throw new PBX_Exception_IO($view->translate("Failed to reload Asterisk PJSIP configuration: %s", $data));
        }
    }

    /**
     * isRuntimeActive - TASK-0020 item 4: post-save runtime verification.
     * Never trust "reloaded successfully" alone as proof a transport is
     * live -- the investigation proved that response reflects
     * module-level command acceptance, not per-object success (§11): a
     * genuinely colliding transport, or one referencing an invalid
     * protocol, or even a transport section following a syntactically
     * broken one in the same file, all still produce "reloaded
     * successfully" while the specific object silently never loads.
     * This asks Asterisk directly, by name, using the exact `pjsip show
     * transport <name>` CLI command already proven reliable throughout
     * the investigation's own live testing.
     *
     * @param string $name
     * @param string $bindAddress
     * @param int    $bindPort
     * @return bool true only if Asterisk's own runtime reports this
     *         exact name bound at this exact address:port right now
     */
    public static function isRuntimeActive($name, $bindAddress, $bindPort) {
        $asteriskAmi = PBX_Asterisk_AMI::getInstance();
        $result = $asteriskAmi->Command("pjsip show transport " . $name);
        $data = isset($result['data']) ? $result['data'] : '';

        if (stripos($data, 'Unable to find object') !== false) {
            return false;
        }
        return stripos($data, "$bindAddress:$bindPort") !== false;
    }

    /**
     * getRuntimeTransportNames - TASK-0020 item 6/§15: the transport
     * list page's runtime-mismatch check needs to know exactly which
     * transport names Asterisk currently has loaded. No structured AMI
     * action exists for transports (confirmed, investigation §15 --
     * `manager show commands` lists PJSIPShowEndpoints/Aors/Auths/
     * Contacts/RegistrationsOutbound, but no PJSIPShowTransports) --
     * `pjsip show transports`'s own CLI text is the only source,
     * parsed the same deliberate way every other AMI Command response
     * in this codebase already is. Matches only real data rows (name
     * followed immediately by a known protocol token), which
     * structurally excludes the header row, the "====" separator, and
     * the trailing "Objects found: N" line without needing to special-
     * case any of them.
     *
     * @return array transport names currently loaded in Asterisk's
     *         live PJSIP runtime
     */
    public static function getRuntimeTransportNames() {
        $asteriskAmi = PBX_Asterisk_AMI::getInstance();
        $result = $asteriskAmi->Command("pjsip show transports");
        $data = isset($result['data']) ? $result['data'] : '';

        $names = array();
        foreach (explode("\n", $data) as $line) {
            if (preg_match('/^Transport:\s+(\S+)\s+(udp|tcp|tls|ws|wss)\s/i', rtrim($line), $m)) {
                $names[] = $m[1];
            }
        }
        return $names;
    }

}
