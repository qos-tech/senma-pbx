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
 * Generates SENMA-managed native PJSIP configuration (TASK-0011).
 *
 * Deliberately a separate class from Snep_InterfaceConf, not a branch
 * added to it: a chan_sip peer is one flat stanza, a PJSIP extension is
 * three linked objects (endpoint/auth/aor) sharing one deterministic
 * identity. Forcing that shape through Snep_InterfaceConf's per-tech
 * flat-stanza loop would contaminate the PJSIP object model with
 * chan_sip's assumptions -- see docs/tasks/0010-pjsip-extension-provisioning-architecture.md §3.
 *
 * Only extensions (peer_type='R') are handled here. PJSIP trunk
 * provisioning is a separate, deferred task (TASK-0010 §15).
 *
 * @category  Snep
 * @package   Snep
 */
class Snep_PjsipConf {

    const AUTH_SUFFIX = '-auth';

    /**
     * dtmfmode DB values ('rfc2833'/'inband'/'info', chan_sip-era naming,
     * addedit.phtml's radio values) -> PJSIP's dtmf_mode values. Confirmed
     * against res_pjsip.c's ast_sip_str_to_dtmf(): "rfc2833" is NOT a
     * recognized PJSIP value (only "rfc4733" is) -- this is a real,
     * necessary rename, not stylistic. "inband"/"info" are identical in
     * both.
     */
    private static $dtmfModeMap = array(
        'rfc2833' => 'rfc4733',
        'inband'  => 'inband',
        'info'    => 'info',
    );

    /**
     * loadConfFromDb - regenerate the SENMA-managed PJSIP extension
     * config from the current peers table and reload res_pjsip.
     *
     * Full stateless rewrite, same property as Snep_InterfaceConf
     * (TASK-0010 §3/§6): every call reflects exactly the current DB
     * state, so create/rename/delete/disable all "just work" without any
     * incremental diff/cleanup logic -- a deleted or renamed row simply
     * doesn't appear in the next SELECT, so its old section(s) are never
     * re-emitted.
     *
     * @throws PBX_Exception_IO if the target file isn't writable, or if
     *         Asterisk reports the PJSIP reload did not succeed.
     */
    public static function loadConfFromDb() {
        $view = new Zend_View();
        $db = Snep_Db::getInstance();

        $config = Zend_Registry::get('config');
        $asteriskDirectory = $config->system->path->asterisk->conf;

        $extenFileConf = "$asteriskDirectory/snep/senma-pjsip.conf";

        if (!is_writable($extenFileConf)) {
            throw new PBX_Exception_IO($view->translate("Failed to open file %s with write permission.", $extenFileConf));
        }

        $todayDate = date("d/m/Y H:i:s");
        $header  = ";------------------------------------------------------------------------------------\n";
        $header .= "; File: senma-pjsip.conf - SENMA-generated PJSIP extension provisioning\n";
        $header .= ";\n";
        $header .= "; Generated: $todayDate\n";
        $header .= "; Copyright(c) 2008-" . date("Y") . " Opens Tecnologia\n";
        $header .= ";------------------------------------------------------------------------------------\n";
        $header .= "; GENERATED FILE -- do not edit manually. Rewritten in full on every extension\n";
        $header .= "; create/edit/delete/enable/disable (Snep_PjsipConf::loadConfFromDb()). Manual\n";
        $header .= "; edits are lost on the next write. See\n";
        $header .= "; docs/tasks/0011-pjsip-extension-provisioning.md.\n";
        $header .= ";------------------------------------------------------------------------------------\n";

        /* Only PJSIP extensions -- SIP/IAX2 rows are invisible to this
         * query (canal doesn't start with "PJSIP/"), exactly as PJSIP
         * rows are already invisible to Snep_InterfaceConf's own
         * "SIP%"/"IAX2%" filters. No coexistence flag needed (TASK-0010
         * §11). Trunks (peer_type='T') are explicitly excluded --
         * deferred, TASK-0010 §15. */
        $sql = "SELECT * FROM peers WHERE name != 'admin' AND disabled != true AND peer_type = 'R' AND canal LIKE 'PJSIP/%'";
        $peer_data = $db->query($sql)->fetchAll();

        $sections = "\n";

        foreach ($peer_data as $peer) {
            $sections .= self::renderExtension($peer);
        }

        $content = $header . $sections;
        file_put_contents($extenFileConf, $content);

        self::reload($view);
    }

    /**
     * renderExtension - build the [name]/[name-auth]/[name] endpoint,
     * auth, and aor sections for one peers row.
     *
     * Field mapping is deliberately limited to what TASK-0010 classified
     * as safe/evidence-backed. See docs/tasks/0011-pjsip-extension-provisioning.md
     * for the full field-by-field rationale; ambiguous chan_sip-only
     * values (rewrite_contact, auto_force_rport/auto_comedia,
     * directmedia=outgoing) are deliberately NOT translated here -- they
     * fall back to a safe, documented default rather than an invented
     * mapping.
     *
     * @param array $peer one row from `peers`
     * @return string
     */
    private static function renderExtension(array $peer) {
        $name = $peer['name'];

        // Codecs: DB stores ";"-joined; PJSIP (like chan_sip) uses ",".
        // Identical transformation to Snep_InterfaceConf.php's own
        // chan_sip codec handling -- codec names/syntax are shared
        // between chan_sip and PJSIP, no new logic needed here.
        $codecList = array_filter(explode(";", (string) $peer['allow']));
        $allow = implode(",", $codecList);

        // NAT: only the two direct, evidence-backed tokens (TASK-0010 §9).
        // auto_force_rport/auto_comedia are deliberately NOT collapsed
        // into these -- TASK-0011 explicitly forbids inventing that
        // mapping. An extension using only "auto_*" NAT modes gets no
        // PJSIP NAT accommodation (both default "no"), which is the safe,
        // documented, explicit default, not silently equivalent to auto.
        $natTokens = array_filter(explode(",", (string) $peer['nat']));
        $forceRport = in_array('force_rport', $natTokens, true) ? 'yes' : 'no';
        $rtpSymmetric = in_array('comedia', $natTokens, true) ? 'yes' : 'no';
        // rewrite_contact: no source field in `peers` at all (TASK-0010
        // §9) -- deliberately left unset (Asterisk's own compiled
        // default, "no", applies by omission).

        // qualify: chan_sip boolean -> PJSIP interval. "no" -> 0
        // (disabled, a literal/direct translation). "yes" -> 60s, a
        // *chosen* default (not derived from any DB value) -- documented
        // as such, not asserted as evidence-backed.
        $qualifyFrequency = ($peer['qualify'] === 'yes') ? 60 : 0;

        // direct_media: only the evidence-backed chan_sip values
        // (TASK-0010 §9). "outgoing" has no PJSIP equivalent (PJSIP's
        // direct_media isn't direction-scoped) -- deliberately falls back
        // to the conservative default (direct_media=no) rather than an
        // invented approximation.
        $directMedia = 'no';
        $disableDirectMediaOnNat = false;
        $directMediaMethod = null;
        switch ($peer['directmedia']) {
            case 'yes':
                $directMedia = 'yes';
                break;
            case 'nonat':
                $directMedia = 'yes';
                $disableDirectMediaOnNat = true;
                break;
            case 'update':
                $directMedia = 'yes';
                $directMediaMethod = 'update';
                break;
            case 'no':
            case 'outgoing':
            default:
                $directMedia = 'no';
                break;
        }

        $dtmfMode = isset(self::$dtmfModeMap[$peer['dtmfmode']])
            ? self::$dtmfModeMap[$peer['dtmfmode']]
            : 'rfc4733';

        // 'br', not 'pt_BR' -- peers.language is CHAR(2) (schema.sql);
        // matches the column's own corrected default (see
        // ExtensionsController::execAdd()'s defFielsExten, TASK-0011).
        $language = $peer['language'] !== '' ? $peer['language'] : 'br';

        $auth = $name . self::AUTH_SUFFIX;
        $transportName = self::resolveTransportName(isset($peer['transport_id']) ? $peer['transport_id'] : null);

        $out = "[$name]\n";
        $out .= "type=endpoint\n";
        $out .= "context=" . $peer['context'] . "\n";
        // TASK-0018 correction: transport_id=NULL means AUTO -- no
        // transport= line at all, letting Asterisk's own documented
        // fallback apply ("Not specifying a transport will select the
        // first configured transport in pjsip.conf which is compatible
        // with the URI we are trying to contact" -- res_pjsip:endpoint:
        // transport's own built-in help text, Asterisk 22.10.1). This is
        // required, not merely permitted: explicitly forcing transport=udp
        // on every extension (the original TASK-0018 behavior) would
        // actively break a device that registered over TCP, since
        // "force" means exactly that -- see
        // docs/tasks/0018-pjsip-transports.md's corrected §9.
        if ($transportName !== null) {
            $out .= "transport=$transportName\n";
        }
        // Verbatim, exactly like Snep_InterfaceConf's own chan_sip
        // callerid= line -- the DB value is already the full
        // "Display Name <exten>" string (composed once in
        // ExtensionsController::addAction() before persistence, stripped
        // back apart only for display in editAction()), not a bare name
        // needing reassembly here.
        $out .= "callerid=" . $peer['callerid'] . "\n";
        $out .= "language=$language\n";
        $out .= "disallow=all\n";
        $out .= "allow=$allow\n";
        $out .= "dtmf_mode=$dtmfMode\n";
        $out .= "auth=$auth\n";
        $out .= "aors=$name\n";
        $out .= "force_rport=$forceRport\n";
        $out .= "rtp_symmetric=$rtpSymmetric\n";
        $out .= "direct_media=$directMedia\n";
        if ($disableDirectMediaOnNat) {
            $out .= "disable_direct_media_on_nat=yes\n";
        }
        if ($directMediaMethod) {
            $out .= "direct_media_method=$directMediaMethod\n";
        }
        $out .= "\n";

        $out .= "[$auth]\n";
        $out .= "type=auth\n";
        $out .= "auth_type=userpass\n";
        $out .= "username=$name\n";
        $out .= "password=" . $peer['secret'] . "\n";
        $out .= "\n";

        // AOR name MUST equal the endpoint name -- res_pjsip_registrar
        // matches the REGISTER URI's username directly against an AOR
        // object's own sorcery name, not merely anything listed in
        // aors=. Confirmed empirically in TASK-0009 (naming it
        // "<name>-aor" produced a real, reproduced 404/"AOR '' not
        // found"). See docs/tasks/0010-pjsip-extension-provisioning-architecture.md §6.
        $out .= "[$name]\n";
        $out .= "type=aor\n";
        $out .= "max_contacts=1\n";
        $out .= "remove_existing=yes\n";
        $out .= "qualify_frequency=$qualifyFrequency\n";
        $out .= "\n";

        return $out;
    }

    /**
     * resolveTransportName - TASK-0018 correction (post-commit semantic
     * fix, see docs/tasks/0018-pjsip-transports.md's "final invariant"
     * section). $transportId is peers.transport_id/trunks.transport_id.
     *
     * NULL/'' means AUTO -- "no explicit transport pinning", NOT
     * "resolve to the default transport". Returns null in that case;
     * callers must omit the transport= line entirely rather than
     * substitute any name. This is a deliberate reversal of this
     * method's original TASK-0018 behavior (which always resolved NULL
     * to whichever transport was marked is_default and always emitted a
     * transport= line) -- that behavior was a real functional bug, not
     * just an architectural preference: `transport=` on an endpoint
     * *forces* that transport ("This will *force* the endpoint to use
     * the specified transport configuration to send SIP messages" --
     * res_pjsip:endpoint:transport's own built-in help text, Asterisk
     * 22.10.1), so pinning every extension to transport=udp would
     * actively break a device that registered over TCP. Confirmed both
     * from Asterisk's own documented fallback ("Not specifying a
     * transport will select the first configured transport in
     * pjsip.conf which is compatible with the URI we are trying to
     * contact") and live: a trunk endpoint+registration pair with no
     * transport= line at all registered and completed a real outbound
     * call identically to one with transport= explicitly set.
     *
     * A non-null $transportId is an explicit pin: resolved to that
     * transport's current name (never a stale one -- re-resolved fresh
     * on every generation, so a rename needs no data migration).
     *
     * @param int|null $transportId
     * @return string|null the resolved transport's name, or null for AUTO
     * @throws PBX_Exception_NotFound if $transportId is set but no such
     *         transport exists -- a real data-integrity problem (the
     *         FK's ON DELETE RESTRICT should make this unreachable
     *         through the application), surfaced loudly rather than
     *         silently downgraded to AUTO.
     *
     * Public: Snep_PjsipTrunkConf reuses this exact method rather than
     * duplicating the resolution logic -- confirmed live (§ this task's
     * own investigation) that endpoint and registration objects behave
     * identically for this specific AUTO-vs-pinned question, so one
     * shared implementation is correct, not an assumption.
     */
    public static function resolveTransportName($transportId) {
        if ($transportId === null || $transportId === '') {
            return null;
        }
        $transport = Snep_PjsipTransports_Manager::get($transportId);
        if (!$transport) {
            throw new PBX_Exception_NotFound("PJSIP transport id $transportId not found (referenced but missing).");
        }
        return $transport['name'];
    }

    /**
     * reload - reload res_pjsip only (not a full Asterisk reload), and
     * surface failure instead of silently assuming success.
     *
     * Snep_InterfaceConf's own three reload calls never check their
     * return value at all (a real, pre-existing gap, TASK-0010 §10) --
     * this deliberately does better, not worse: it inspects Asterisk's
     * own response text for the known success marker and throws (logging
     * first) if it isn't present, so a broken PJSIP reload is visible
     * rather than silently swallowed.
     *
     * @throws PBX_Exception_IO if the reload did not report success.
     */
    private static function reload(Zend_View $view) {
        $asteriskAmi = PBX_Asterisk_AMI::getInstance();
        $result = $asteriskAmi->Command("module reload res_pjsip.so");

        $data = isset($result['data']) ? $result['data'] : '';

        if (stripos($data, 'reloaded successfully') === false) {
            $log = Zend_Registry::get('log');
            $log->err("Snep_PjsipConf: 'module reload res_pjsip.so' did not report success: " . $data);
            throw new PBX_Exception_IO($view->translate("Failed to reload Asterisk PJSIP configuration: %s", $data));
        }
    }

}
