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
 * DB -> PJSIP runtime reconciliation orchestrator (TASK-0033B).
 *
 * Closes the production blocker TASK-0033 identified: today, generated
 * PJSIP config is only ever rebuilt as a side effect of a specific
 * extension/trunk/transport CRUD operation
 * (PjsipTransportsController::regenerateAll() and the equivalent calls in
 * ExtensionsController/TrunksController). If the generated files are
 * lost, stale, partially written, or drift from the database, there was
 * no supported operator command that could reconstruct the runtime from
 * the authoritative application state. This class IS that command's
 * engine (see docker/reconcile-pjsip.php for the CLI entrypoint and
 * `make reconcile`/`make reconcile-check`).
 *
 * Architecture: orchestration layer ON TOP of the existing generators,
 * never a second implementation of PJSIP rendering. Snep_PjsipConf,
 * Snep_PjsipTrunkConf, and Snep_PjsipTransportConf each expose a pure
 * renderContent() (extracted out of their own loadConfFromDb(), which
 * still exists unchanged for the CRUD call sites) -- this class calls
 * exactly those same methods to build the complete managed file set,
 * then owns everything CRUD's per-object write-and-reload never needed:
 * pre-publish validation, staging, atomic publish with rollback, a
 * single coordinated reload (not three redundant ones), and post-apply
 * runtime verification. See docs/tasks/
 * 0033b-pjsip-configuration-reconciliation.md for the full contract.
 *
 * Source-of-truth boundary (do not cross): the database is authoritative
 * for SENMA-managed extensions, native PJSIP trunks, PJSIP transports,
 * and their registration/identify/auth/AOR objects. It is explicitly NOT
 * authoritative for pjsip_external endpoint internals (owned by
 * whatever externally manages that endpoint), customer-owned Asterisk
 * files (custom/preagi.conf, custom/posagi.conf, custom/eof.conf),
 * externally-managed certificate/private-key bytes, or the `provider`
 * test-fixture service's own config. This class never reads, writes, or
 * judges any of those.
 *
 * @category  Snep
 * @package   Snep
 */
class Snep_Pjsip_Reconciler {

    // Phase 11 drift/check classification.
    const CHECK_IN_SYNC = 'IN_SYNC';
    const CHECK_DRIFTED = 'DRIFTED';
    const CHECK_INVALID_DB = 'INVALID_DB';
    const CHECK_RUNTIME_UNAVAILABLE = 'RUNTIME_UNAVAILABLE';

    // Phase 17 failure taxonomy, plus the successful terminal states.
    const RESULT_RECONCILED = 'RECONCILED';
    const RESULT_RUNTIME_RESTART_REQUIRED = 'RUNTIME_RESTART_REQUIRED';
    const RESULT_FILES_RECONCILED_RUNTIME_UNAVAILABLE = 'FILES_RECONCILED_RUNTIME_UNAVAILABLE';
    const RESULT_INVALID_DB_STATE = 'INVALID_DB_STATE';
    const RESULT_GENERATION_FAILED = 'GENERATION_FAILED';
    const RESULT_STAGING_VALIDATION_FAILED = 'STAGING_VALIDATION_FAILED';
    const RESULT_PUBLISH_FAILED = 'PUBLISH_FAILED';
    const RESULT_APPLY_FAILED = 'APPLY_FAILED';
    const RESULT_VERIFY_FAILED = 'VERIFY_FAILED';
    const RESULT_RUNTIME_UNAVAILABLE = 'RUNTIME_UNAVAILABLE';

    /**
     * The exact, exhaustive set of files this class owns. Nothing else
     * -- not the customer-owned custom/ dialplan includes, not the
     * certificate/key files under keys/, not the legacy chan_sip/IAX2
     * compatibility files Snep_InterfaceConf also knows how to generate
     * (Phase 2: "do not include historical SIP/IAX compatibility files
     * merely because the same legacy manager knows how to generate
     * them").
     */
    public static $managedFiles = array(
        'senma-pjsip-transports.conf',
        'senma-http-tls.conf',
        'senma-pjsip.conf',
        'senma-pjsip-trunks.conf',
    );

    private static function snepDir() {
        $config = Zend_Registry::get('config');
        return $config->system->path->asterisk->conf . '/snep';
    }

    /**
     * check - Phase 11 non-mutating drift check. Never writes to disk,
     * never touches Asterisk. Generates the complete managed set in
     * memory and compares it against the currently active files.
     *
     * @return array('status' => self::CHECK_*, 'problems' => string[],
     *               'files' => array(filename => 'in_sync'|'drifted'|'missing'))
     */
    public static function check() {
        $db = Snep_Db::getInstance();
        try {
            // A cheap, real query -- proves the DB connection this whole
            // operation depends on is actually usable, not merely that
            // Zend_Db_Adapter's constructor didn't throw.
            $db->query('SELECT 1');
        } catch (Exception $ex) {
            return array('status' => self::CHECK_INVALID_DB, 'problems' => array('database unavailable: ' . $ex->getMessage()), 'files' => array());
        }

        $validation = self::validate();
        if (!$validation['valid']) {
            return array('status' => self::CHECK_INVALID_DB, 'problems' => $validation['problems'], 'files' => array());
        }

        $generated = self::generateAll();
        if ($generated['failure']) {
            return array('status' => self::CHECK_INVALID_DB, 'problems' => $generated['warnings'], 'files' => array());
        }

        $snepDir = self::snepDir();
        $fileStatus = array();
        $anyDrift = false;
        foreach (self::$managedFiles as $name) {
            $activePath = "$snepDir/$name";
            if (!file_exists($activePath)) {
                $fileStatus[$name] = 'missing';
                $anyDrift = true;
                continue;
            }
            // Content-only comparison -- the generators stamp a
            // "Generated: <timestamp>" line into every header, so a
            // byte-for-byte compare would report DRIFTED on every check
            // even when nothing meaningful changed. Strip that one line
            // from both sides before comparing (Phase 11: report
            // entity/file-level drift, not a raw diff -- this is the
            // simplest secret-safe drift signal: same-or-different, no
            // line ever printed anywhere).
            $active = @file_get_contents($activePath);
            $normalizedActive = preg_replace('/^; Generated: .*$/m', '', $active);
            $normalizedNew = preg_replace('/^; Generated: .*$/m', '', $generated['content'][$name]);
            if ($normalizedActive === $normalizedNew) {
                $fileStatus[$name] = 'in_sync';
            } else {
                $fileStatus[$name] = 'drifted';
                $anyDrift = true;
            }
        }

        return array(
            'status' => $anyDrift ? self::CHECK_DRIFTED : self::CHECK_IN_SYNC,
            'problems' => array(),
            'files' => $fileStatus,
        );
    }

    /**
     * reconcile - Phase 19 full operation: validate -> generate -> stage
     * -> publish atomically -> apply -> verify. Never partially applies:
     * a failure at any stage before publish leaves every active file
     * byte-for-byte untouched; a failure during publish itself is rolled
     * back to the prior complete known-good set (Phase 7/8/18).
     *
     * @return array structured result -- see docker/reconcile-pjsip.php
     *         for exactly which keys it prints.
     */
    public static function reconcile() {
        $result = array(
            'status' => null,
            'db_validation' => null,
            'generation' => null,
            'staging_validation' => null,
            'publish' => null,
            'apply' => null,
            'verification' => null,
            'external_dependencies' => array(),
        );

        // --- 1. Pre-generation validation (Phase 6) -------------------
        $validation = self::validate();
        $result['db_validation'] = $validation;
        if (!$validation['valid']) {
            $result['status'] = self::RESULT_INVALID_DB_STATE;
            return $result;
        }

        // --- 2. Generate the complete managed set into memory ---------
        $generated = self::generateAll();
        $result['generation'] = $generated;
        if ($generated['failure']) {
            // Per-row skip warnings from the generators themselves count
            // as invalid persisted state for a full reconciliation, even
            // though the same condition is tolerated (skip-and-log) by
            // an individual CRUD save -- see Snep_PjsipConf::
            // renderContent()'s own docblock for why that asymmetry is
            // deliberate.
            $result['status'] = self::RESULT_INVALID_DB_STATE;
            return $result;
        }

        // --- 3. Staged structural validation (Phase 10) ---------------
        $stagingValidation = self::validateStagedContent($generated['content']);
        $result['staging_validation'] = $stagingValidation;
        if (!$stagingValidation['valid']) {
            $result['status'] = self::RESULT_STAGING_VALIDATION_FAILED;
            return $result;
        }

        // --- 4. Snapshot pre-publish runtime transport state (needed to
        //        detect RUNTIME_RESTART_REQUIRED after reload below) ---
        $asteriskReachablePrePublish = self::asteriskReachable();

        // --- 5. Atomic publish with rollback (Phase 7/8/9) ------------
        $publish = self::publish($generated['content']);
        $result['publish'] = $publish;
        if (!$publish['published']) {
            $result['status'] = self::RESULT_PUBLISH_FAILED;
            return $result;
        }

        // --- 6. Apply (Phase 12/13) ------------------------------------
        if (!$asteriskReachablePrePublish) {
            // Files are durably published (step 5 already succeeded and
            // was not rolled back) -- Asterisk being unreachable is an
            // apply-time condition, not a reason to have refused
            // publication. Explicit, not a silent partial success
            // (Phase 30).
            $result['status'] = self::RESULT_FILES_RECONCILED_RUNTIME_UNAVAILABLE;
            return $result;
        }

        $apply = self::apply();
        $result['apply'] = $apply;
        if (!$apply['res_pjsip_reloaded'] || !$apply['http_reloaded']) {
            $result['status'] = self::RESULT_APPLY_FAILED;
            return $result;
        }

        // --- 7. Runtime verification (Phase 15/16) ---------------------
        $verification = self::verify();
        $result['verification'] = $verification;
        $result['external_dependencies'] = $verification['external_dependencies'];
        if (!$verification['ok']) {
            $result['status'] = self::RESULT_VERIFY_FAILED;
            return $result;
        }

        $result['status'] = $verification['restart_required']
            ? self::RESULT_RUNTIME_RESTART_REQUIRED
            : self::RESULT_RECONCILED;
        return $result;
    }

    // =====================================================================
    // Pre-generation validation (Phase 6)
    // =====================================================================

    /**
     * validate - checks persisted state the three generators do not
     * already self-validate before rendering (Snep_PjsipTransportConf
     * emits pjsip_transports rows verbatim, with no per-row skip/warning
     * mechanism the way the other two generators have). Reuses
     * Snep_PjsipTransports_Manager's existing static validators
     * (identical ones PjsipTransportsController already runs at
     * save-time) rather than duplicating validation logic -- Phase 6's
     * explicit instruction.
     *
     * @return array('valid' => bool, 'problems' => string[])
     */
    public static function validate() {
        $db = Snep_Db::getInstance();
        $problems = array();

        $transports = $db->query('SELECT * FROM pjsip_transports WHERE enabled = 1')->fetchAll();
        foreach ($transports as $t) {
            $label = "transport '{$t['name']}' (id {$t['id']})";
            if (!Snep_PjsipTransports_Manager::validateProtocol($t['protocol'])) {
                $problems[] = "$label has an invalid protocol '{$t['protocol']}'";
            }
            if (!Snep_PjsipTransports_Manager::validateIpOrHostname($t['bind_address'])) {
                $problems[] = "$label has an invalid bind_address '{$t['bind_address']}'";
            }
            if (!Snep_PjsipTransports_Manager::validatePort($t['bind_port'])) {
                $problems[] = "$label has an invalid bind_port '{$t['bind_port']}'";
            }
            if ($t['protocol'] === 'tls') {
                if (!Snep_PjsipTransports_Manager::validateCertPath($t['cert_file'])) {
                    $problems[] = "$label has an invalid cert_file path";
                } elseif (!empty($t['cert_file'])) {
                    $cert = Snep_PjsipTransports_Manager::inspectCertificateFile($t['cert_file']);
                    if (!$cert['exists']) {
                        $problems[] = "$label references cert_file '{$t['cert_file']}', which does not exist on disk (externally-managed -- reconciliation cannot repair this, only report it)";
                    }
                }
                if (!Snep_PjsipTransports_Manager::validateCertPath($t['priv_key_file'])) {
                    $problems[] = "$label has an invalid priv_key_file path";
                } elseif (!empty($t['priv_key_file'])) {
                    $key = Snep_PjsipTransports_Manager::keyFileExists($t['priv_key_file']);
                    if (!$key['exists']) {
                        $problems[] = "$label references priv_key_file '{$t['priv_key_file']}', which does not exist on disk (externally-managed -- reconciliation cannot repair this, only report it)";
                    }
                }
                if (!empty($t['method']) && !Snep_PjsipTransports_Manager::validateMethod($t['method'])) {
                    $problems[] = "$label has an invalid TLS method '{$t['method']}'";
                }
            }

            $networks = $db->query('SELECT network FROM pjsip_transport_networks WHERE transport_id = ' . (int) $t['id'])->fetchAll(Zend_Db::FETCH_COLUMN);
            foreach ($networks as $network) {
                if (!Snep_PjsipTransports_Manager::validateCidr($network)) {
                    $problems[] = "$label has an invalid local_net entry '$network'";
                }
            }
        }

        return array('valid' => empty($problems), 'problems' => $problems);
    }

    // =====================================================================
    // Generation (Phase 5 -- orchestration only, no new rendering logic)
    // =====================================================================

    /**
     * generateAll - calls the three existing generators' renderContent()
     * in the same order PjsipTransportsController::regenerateAll()
     * already established (transports first -- extensions/trunks
     * reference transport names by value, so generating transports last
     * would not itself break anything here since this is in-memory-only,
     * but keeping the same order as the proven CRUD path avoids any
     * unnecessary behavioral divergence).
     *
     * @return array('content' => array(filename => string),
     *               'warnings' => string[], 'failure' => bool)
     */
    public static function generateAll() {
        $content = array();
        $warnings = array();

        try {
            $transports = Snep_PjsipTransportConf::renderContent();
            $content['senma-pjsip-transports.conf'] = $transports['content'];
            $warnings = array_merge($warnings, $transports['warnings']);
            $content['senma-http-tls.conf'] = Snep_PjsipTransportConf::renderHttpTlsContent();

            $extensions = Snep_PjsipConf::renderContent();
            $content['senma-pjsip.conf'] = $extensions['content'];
            $warnings = array_merge($warnings, $extensions['warnings']);

            $trunks = Snep_PjsipTrunkConf::renderContent();
            $content['senma-pjsip-trunks.conf'] = $trunks['content'];
            $warnings = array_merge($warnings, $trunks['warnings']);
        } catch (Exception $ex) {
            return array('content' => array(), 'warnings' => array('generation raised an uncaught exception: ' . $ex->getMessage()), 'failure' => true);
        }

        return array('content' => $content, 'warnings' => $warnings, 'failure' => !empty($warnings));
    }

    // =====================================================================
    // Staged structural validation (Phase 10) -- cheap, no Asterisk
    // config parser dependency introduced; structural sanity only.
    // =====================================================================

    /**
     * @param array $content filename => generated string
     * @return array('valid' => bool, 'problems' => string[])
     */
    public static function validateStagedContent(array $content) {
        $problems = array();

        foreach (self::$managedFiles as $name) {
            if (!array_key_exists($name, $content)) {
                $problems[] = "$name was not generated at all";
                continue;
            }
            $text = $content[$name];
            if (trim($text) === '') {
                $problems[] = "$name generated as empty content";
                continue;
            }

            // Every generator legitimately repeats the SAME [name] more
            // than once on purpose -- an extension/trunk's endpoint and
            // its aor share one identity by sorcery convention (res_pjsip_
            // registrar matches a REGISTER URI's AOR by name directly;
            // see Snep_PjsipConf::renderExtension()'s own comment on
            // this). A raw "have we seen this bracket name before" check
            // would flag that correct, load-bearing pattern as a false
            // "duplicate section" on every single extension/trunk --
            // confirmed live during this task's own validation. The real
            // invariant is: the same (name, type) PAIR must never repeat
            // (that WOULD mean two competing stanzas of the same kind).
            $seenPairs = array();
            $pendingName = null;
            $pendingLine = null;
            $lineNo = 0;
            foreach (explode("\n", $text) as $line) {
                $lineNo++;
                $trimmed = rtrim($line, "\r");
                if ($trimmed === '' || $trimmed[0] === ';') {
                    continue; // blank/comment
                }
                if (preg_match('/^\[([^\]]+)\]\s*$/', $trimmed, $m)) {
                    $pendingName = $m[1];
                    $pendingLine = $lineNo;
                    continue;
                }
                if ($pendingName !== null && preg_match('/^type\s*=\s*(\S+)/', $trimmed, $tm)) {
                    $pairKey = $pendingName . '|' . $tm[1];
                    if (isset($seenPairs[$pairKey])) {
                        $problems[] = "$name: duplicate [{$pendingName}] type={$tm[1]} section (line $pendingLine and line {$seenPairs[$pairKey]})";
                    }
                    $seenPairs[$pairKey] = $pendingLine;
                    $pendingName = null;
                }
                if (preg_match('/^[A-Za-z0-9_]+\s*=/', $trimmed)) {
                    // TASK-0033B invariant: PJSIP-only. A generator bug
                    // that somehow emitted a chan_sip/IAX2-style
                    // directive (e.g. accidentally reusing
                    // Snep_InterfaceConf's own template) must never
                    // silently publish -- this is cheap insurance, not
                    // expected to ever actually fire.
                    if (preg_match('/^(type)\s*=\s*(peer|friend|user)\s*$/', $trimmed)) {
                        $problems[] = "$name line $lineNo looks like a chan_sip/IAX2-style directive ('$trimmed'), not PJSIP -- refusing to publish";
                    }
                    continue;
                }
                $problems[] = "$name line $lineNo is neither a comment, a [section] header, nor a key=value directive: '$trimmed'";
            }
        }

        return array('valid' => empty($problems), 'problems' => $problems);
    }

    // =====================================================================
    // Atomic publication with rollback (Phase 7/8/9)
    // =====================================================================

    /**
     * publish - writes the complete managed set into a staging area on
     * the SAME filesystem as the active files (required for rename() to
     * be atomic -- /etc/asterisk/snep/.reconcile-staging, not a system
     * /tmp, which could be a different volume), backs up whatever is
     * currently active, then renames every staged file into place. If
     * any rename fails partway, every already-renamed file is restored
     * from its backup copy before returning -- the active set is either
     * entirely the new generation or entirely the prior one, never a mix
     * (Phase 7's explicit "never new transports + old trunks" concern).
     *
     * Ownership: docker/asterisk-entrypoint.sh establishes
     * owner=asterisk, group=senma-config, mode=0664 for every file under
     * /etc/asterisk/snep on first boot (senma-config is the shared group
     * both the asterisk and www-data users belong to -- see that
     * script's own comments). This re-applies that exact scheme to every
     * staged file before it is renamed into place, rather than trusting
     * whatever mode the staging write happened to produce (Phase 9).
     *
     * @return array('published' => bool, 'files' => string[] (published,
     *               in order), 'problems' => string[])
     */
    public static function publish(array $content) {
        $snepDir = self::snepDir();
        $stagingDir = "$snepDir/.reconcile-staging";

        if (!is_dir($stagingDir) && !@mkdir($stagingDir, 0770, true)) {
            return array('published' => false, 'files' => array(), 'problems' => array("could not create staging directory $stagingDir"));
        }
        @chgrp($stagingDir, 'senma-config');
        @chmod($stagingDir, 0770);

        $backups = array();
        $staged = array();

        foreach (self::$managedFiles as $name) {
            $activePath = "$snepDir/$name";
            $stagePath = "$stagingDir/$name.new";
            if (@file_put_contents($stagePath, $content[$name]) === false) {
                self::cleanupStaging($stagingDir, $staged, $backups);
                return array('published' => false, 'files' => array(), 'problems' => array("could not write staged content for $name"));
            }
            @chown($stagePath, 'asterisk');
            @chgrp($stagePath, 'senma-config');
            @chmod($stagePath, 0664);
            $staged[$name] = $stagePath;

            if (file_exists($activePath)) {
                $backupPath = "$stagingDir/$name.rollback";
                if (!@copy($activePath, $backupPath)) {
                    self::cleanupStaging($stagingDir, $staged, $backups);
                    return array('published' => false, 'files' => array(), 'problems' => array("could not back up active $name before publishing"));
                }
                $backups[$name] = $backupPath;
            }
        }

        $published = array();
        foreach (self::$managedFiles as $name) {
            $activePath = "$snepDir/$name";
            if (!@rename($staged[$name], $activePath)) {
                // Roll back every file already published in this pass.
                foreach ($published as $doneName) {
                    if (isset($backups[$doneName])) {
                        @rename($backups[$doneName], "$snepDir/$doneName");
                    }
                }
                self::cleanupStaging($stagingDir, $staged, $backups);
                return array('published' => false, 'files' => $published, 'problems' => array("renaming $name into place failed -- rolled back " . count($published) . " already-published file(s) to their prior state"));
            }
            $published[] = $name;
        }

        self::cleanupStaging($stagingDir, array(), $backups);
        return array('published' => true, 'files' => $published, 'problems' => array());
    }

    private static function cleanupStaging($stagingDir, array $staged, array $backups) {
        foreach ($staged as $path) {
            if (file_exists($path)) {
                @unlink($path);
            }
        }
        foreach ($backups as $path) {
            if (file_exists($path)) {
                @unlink($path);
            }
        }
    }

    // =====================================================================
    // Apply (Phase 12/13) -- one coordinated reload, not three redundant
    // ones (unlike calling all three generators' own loadConfFromDb()).
    // =====================================================================

    public static function asteriskReachable() {
        try {
            $asteriskAmi = PBX_Asterisk_AMI::getInstance();
            $result = $asteriskAmi->Command('core show version');
            $data = isset($result['data']) ? $result['data'] : '';
            return $data !== '';
        } catch (Exception $ex) {
            return false;
        }
    }

    /**
     * @return array('res_pjsip_reloaded' => bool, 'http_reloaded' => bool,
     *               'problems' => string[])
     */
    public static function apply() {
        $problems = array();
        $asteriskAmi = PBX_Asterisk_AMI::getInstance();

        $pjsipResult = $asteriskAmi->Command('module reload res_pjsip.so');
        $pjsipData = isset($pjsipResult['data']) ? $pjsipResult['data'] : '';
        $pjsipReloaded = stripos($pjsipData, 'reloaded successfully') !== false;
        if (!$pjsipReloaded) {
            $problems[] = 'module reload res_pjsip.so did not report success: ' . $pjsipData;
        }

        // TASK-0029A precedent: http.conf (the WSS/TLS listener) needs
        // its own separate reload command -- confirmed by
        // Snep_PjsipTransportConf::reloadHttp()'s own docblock.
        $httpResult = $asteriskAmi->Command('module reload http');
        $httpData = isset($httpResult['data']) ? $httpResult['data'] : '';
        $httpReloaded = stripos($httpData, 'reloaded successfully') !== false;
        if (!$httpReloaded) {
            $problems[] = 'module reload http did not report success: ' . $httpData;
        }

        return array('res_pjsip_reloaded' => $pjsipReloaded, 'http_reloaded' => $httpReloaded, 'problems' => $problems);
    }

    // =====================================================================
    // Runtime verification (Phase 15/16)
    // =====================================================================

    /**
     * verify - builds the expected live-object identity set from the
     * SAME DB queries the generators use, then checks Asterisk's actual
     * runtime against it. Responsible for CONFIGURED_CORRECTLY/
     * RUNTIME_OBJECT_LOADED only (Phase 16) -- never treats a trunk
     * registration's live status (Registered/Rejected/Unregistered) or
     * an extension's contact/registration state as a reconciliation
     * failure; only whether the *object itself* loaded.
     *
     * @return array('ok' => bool, 'restart_required' => bool,
     *               'problems' => string[], 'external_dependencies' => array)
     */
    public static function verify() {
        $db = Snep_Db::getInstance();
        $problems = array();
        $asteriskAmi = PBX_Asterisk_AMI::getInstance();

        // --- Expected identity sets, straight from DB (same source of
        //     truth the generators themselves query) -------------------
        $extensions = $db->query("SELECT name FROM peers WHERE name != 'admin' AND disabled != true AND peer_type = 'R' AND canal LIKE 'PJSIP/%'")->fetchAll(Zend_Db::FETCH_COLUMN);
        $trunkRows = $db->query("SELECT t.id, t.reverse_auth FROM peers p JOIN trunks t ON t.name = p.name WHERE p.peer_type = 'T' AND p.disabled != true AND p.canal LIKE 'PJSIP/%'")->fetchAll();
        $enabledTransports = $db->query('SELECT name, bind_address, bind_port FROM pjsip_transports WHERE enabled = 1')->fetchAll();
        $externalEndpointNames = $db->query("SELECT DISTINCT username FROM trunks WHERE type = 'PJSIP_EXTERNAL' AND username != ''")->fetchAll(Zend_Db::FETCH_COLUMN);

        $expectedEndpoints = array();
        foreach ($extensions as $ext) {
            $expectedEndpoints[] = $ext;
        }
        $trunkNames = array();
        foreach ($trunkRows as $t) {
            $trunkNames[] = 'trunk-' . $t['id'];
        }
        $expectedEndpoints = array_merge($expectedEndpoints, $trunkNames);

        // --- Bulk live listings (one AMI round-trip per object class,
        //     not one per object) -----------------------------------
        // Extension endpoints display as "<name>/<calleridnum>"
        // (e.g. "1098/1098"); trunk endpoints display as a bare
        // "<name>" with no slash at all (confirmed live against a real
        // native PJSIP trunk during this task's own validation -- an
        // earlier version of this pattern required a trailing "/...",
        // which silently made every trunk invisible to this check and
        // produced a false "expected endpoint not loaded" failure for
        // every one). Capture up to the first "/" or whitespace, never
        // require either.
        $liveEndpoints = self::parseBulkNames($asteriskAmi->Command('pjsip show endpoints'), '/^\s*Endpoint:\s+([^\s\/]+)/');

        // --- Expected present, none missing --------------------------
        foreach ($expectedEndpoints as $name) {
            if (!in_array($name, $liveEndpoints, true)) {
                $problems[] = "expected endpoint '$name' is not loaded in the live PJSIP runtime";
            }
        }

        // --- No stale/leftover SENMA-managed endpoint survives --------
        // (Phase 27/28: a disabled/deleted/stale object must disappear
        // from the runtime after a real reload of a full rewrite -- if
        // one is still here, either the reload silently no-op'd or this
        // reconciliation itself has a gap.) pjsip_external's own
        // endpoint is explicitly excluded -- it is not SENMA's to judge
        // (Phase 4).
        foreach ($liveEndpoints as $name) {
            if (in_array($name, $expectedEndpoints, true)) {
                continue;
            }
            if (in_array($name, $externalEndpointNames, true)) {
                continue; // externally-managed, not this class's concern
            }
            $problems[] = "unexpected endpoint '$name' is still loaded in the live PJSIP runtime (should have been removed)";
        }

        // --- pjsip_external: existence-only check, reported separately,
        //     never repaired, never a reconciliation failure (Phase 4/16) --
        $externalDependencies = array();
        foreach ($externalEndpointNames as $name) {
            $externalDependencies[$name] = in_array($name, $liveEndpoints, true) ? 'present' : 'missing (external dependency -- not managed by SENMA, not repaired by reconcile)';
        }

        // --- Identify objects for trunks with reverse_auth (registered
        //     trunks) get one too, unconditionally, per
        //     Snep_PjsipTrunkConf's own class doc -- check every trunk's,
        //     not just the registered ones. -----------------------------
        foreach ($trunkRows as $t) {
            $identifyName = 'trunk-' . $t['id'] . Snep_PjsipTrunkConf::IDENTIFY_SUFFIX;
            $result = $asteriskAmi->Command('pjsip show identify ' . $identifyName);
            $data = isset($result['data']) ? $result['data'] : '';
            if (stripos($data, 'Unable to find') !== false || $data === '') {
                $problems[] = "expected identify object '$identifyName' is not loaded in the live PJSIP runtime";
            }
        }

        // --- Transports: reuse the existing runtime-verification
        //     primitives Snep_PjsipTransportConf already exposes
        //     (TASK-0020) rather than re-implementing them -----------
        $restartRequired = false;
        foreach ($enabledTransports as $t) {
            if (!Snep_PjsipTransportConf::isRuntimeActive($t['name'], $t['bind_address'], $t['bind_port'])) {
                // A transport present in the freshly-published config
                // but not bound at its expected address:port after a
                // successful reload is the documented TASK-0028V/0029A
                // case: some transport changes (a bind address/port
                // change on a transport Asterisk already has open)
                // cannot hot-converge and need a full Asterisk restart
                // to rebind the socket. This is NOT a verification
                // failure -- Phase 14 requires it be reported as its own
                // explicit, non-error terminal state.
                $restartRequired = true;
            }
        }

        return array(
            'ok' => empty($problems),
            'restart_required' => $restartRequired,
            'problems' => $problems,
            'external_dependencies' => $externalDependencies,
        );
    }

    /**
     * parseBulkNames - shared bulk-listing parser for `pjsip show
     * endpoints`-shaped AMI Command output. Same parsing convention
     * Snep_PjsipTransportConf::getRuntimeTransportNames() already
     * established for `pjsip show transports` (TASK-0020) -- matches
     * only real data rows, which structurally excludes the header,
     * the "====" separator, and the trailing "Objects found: N" line.
     *
     * @param array  $amiResult raw PBX_Asterisk_AMI::Command() result
     * @param string $pattern   regex with exactly one capturing group
     * @return string[]
     */
    private static function parseBulkNames($amiResult, $pattern) {
        $data = isset($amiResult['data']) ? $amiResult['data'] : '';
        $names = array();
        foreach (explode("\n", $data) as $line) {
            if (preg_match($pattern, rtrim($line), $m)) {
                // The CLI's own column-header row (e.g.
                // "Endpoint:  <Endpoint/CID.....>  <State.....>  ...")
                // matches the same "Endpoint:  <name>" shape a real data
                // row does -- confirmed live, an earlier version of this
                // method returned the literal string "<Endpoint" as a
                // "live endpoint name", which then made every real
                // endpoint look "unexpected" by comparison. A real
                // Snep_PjsipTransports_Manager::validateName() name is
                // restricted to [A-Za-z0-9_-]; Asterisk's own header/
                // placeholder tokens always start with "<" or contain
                // ".", neither of which a real object name can.
                if ($m[1] === '' || $m[1][0] === '<' || strpos($m[1], '.') !== false) {
                    continue;
                }
                $names[] = $m[1];
            }
        }
        return $names;
    }

}
