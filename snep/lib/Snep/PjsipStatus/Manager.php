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
 * PJSIP runtime status service (TASK-0029B).
 *
 * Answers, for every supported PJSIP entity, the question TASK-0028W's
 * completeness review found the product could not answer: not "is this
 * configured" (the DB already knows that) but "what does Asterisk's own
 * live runtime say right now" -- and normalizes the two into one small,
 * honest vocabulary:
 *
 *   ACTIVE    - confirmed working right now (registered+reachable,
 *               loaded and matching config, or "configured, no
 *               reachability check requested" -- see per-entity notes)
 *   DEGRADED  - loaded/registered, but a reachability check is
 *               currently failing
 *   PENDING   - a transitional runtime state (registration in progress,
 *               or a saved config Asterisk has not yet reloaded)
 *   INACTIVE  - no live counterpart at all (no contact registered),
 *               without implying anything is broken
 *   DISABLED  - the SENMA row itself is disabled
 *   ERROR     - an explicit failure (registration rejected, referenced
 *               external endpoint missing)
 *   UNKNOWN   - the runtime query itself failed or returned something
 *               this parser does not recognize; NEVER downgraded to any
 *               other state -- an observation failure must never be
 *               confused with an entity failure (TASK-0029B's own
 *               explicit Phase 6 requirement)
 *
 * One bulk AMI call per object family (`pjsip show endpoints`, `pjsip
 * show registrations outbound`) regardless of how many DB rows exist --
 * both proven live to already inline every endpoint's own AOR/Contact
 * lines, so there is no N-rows-times-N-AMI-calls cost here (TASK-0029B
 * Phase 17). Every raw CLI string is parsed HERE and only here; callers
 * (controllers/views) receive normalized state + a human detail string
 * only -- never a raw Asterisk fragment (Phase 10's explicit
 * requirement).
 *
 * @category  Snep
 * @package   Snep
 */
class Snep_PjsipStatus_Manager {

    const ACTIVE = 'ACTIVE';
    const DEGRADED = 'DEGRADED';
    const PENDING = 'PENDING';
    const INACTIVE = 'INACTIVE';
    const DISABLED = 'DISABLED';
    const ERROR = 'ERROR';
    const UNKNOWN = 'UNKNOWN';

    /**
     * status - build a normalized status array. Every return value in
     * this file goes through here so the shape is always identical.
     */
    private static function status($state, $detail) {
        return array('state' => $state, 'detail' => $detail);
    }

    /**
     * amiCommand - one AMI Command(), tolerant of any failure mode
     * (AMI down, PBX_Asterisk_AMI throwing, an unexpected response
     * shape). Returns null on any failure -- callers must treat null as
     * "could not observe", never as "empty/nothing found".
     */
    private static function amiCommand($cmd) {
        try {
            $ami = PBX_Asterisk_AMI::getInstance();
            $result = $ami->Command($cmd);
        } catch (Exception $e) {
            error_log("Snep_PjsipStatus_Manager: AMI command '$cmd' failed: " . $e->getMessage());
            return null;
        }
        if (!is_array($result) || !isset($result['data'])) {
            return null;
        }
        return $result['data'];
    }

    // =========================================================================
    // Extensions
    // =========================================================================

    /**
     * getExtensionStatuses - one status array per PJSIP-technology
     * extension.
     *
     * @return array peer id => status()
     */
    public static function getExtensionStatuses() {
        $db = Zend_Registry::get('db');
        $select = $db->select()
            ->from('peers', array('id', 'exten' => 'name', 'canal', 'qualify', 'disabled'))
            ->where('peer_type = ?', 'R')
            ->where("canal LIKE 'PJSIP/%'");
        $rows = $db->query($select)->fetchAll();

        $statuses = array();
        if (count($rows) === 0) {
            return $statuses;
        }

        $raw = self::amiCommand('pjsip show endpoints');
        $endpoints = $raw !== null ? self::parseEndpoints($raw) : null;

        foreach ($rows as $row) {
            if (!empty($row['disabled'])) {
                $statuses[$row['id']] = self::status(self::DISABLED, 'Extension disabled');
                continue;
            }
            if ($endpoints === null) {
                $statuses[$row['id']] = self::status(self::UNKNOWN, 'Could not query Asterisk runtime state');
                continue;
            }
            $qualifyEnabled = !empty($row['qualify']) && $row['qualify'] !== 'no';
            $statuses[$row['id']] = self::classifyContact(
                isset($endpoints[$row['exten']]) ? $endpoints[$row['exten']] : null,
                $qualifyEnabled
            );
        }
        return $statuses;
    }

    /**
     * classifyContact - the shared reachability logic extensions and
     * registrationless trunks both need: given the endpoint's parsed
     * runtime entry (or null if the endpoint was not found at all) and
     * whether SENMA's own config asked for qualify monitoring, produce
     * one normalized status. Combines DB config truth (is qualify even
     * turned on) with Asterisk runtime truth (what does the contact's
     * own qualify status say) -- exactly the "DB/config state + Asterisk
     * runtime state -> explicit SENMA status" contract this task exists
     * to build, not a guess from either source alone.
     */
    private static function classifyContact($endpoint, $qualifyEnabled) {
        if ($endpoint === null) {
            return self::status(self::UNKNOWN, 'Not found in Asterisk\'s runtime configuration -- it may not have been applied yet');
        }
        if (count($endpoint['contacts']) === 0) {
            return self::status(self::INACTIVE, 'No device registered');
        }

        // TASK-0029B: SENMA currently hardcodes max_contacts=1 for every
        // PJSIP endpoint it generates (Snep_PjsipConf/Snep_PjsipTrunkConf),
        // so this loop only ever really sees one contact today -- but the
        // aggregation rule below (ACTIVE if ANY contact is confirmed
        // reachable/unmonitored, DEGRADED only if ALL are failing) is
        // written to stay correct if that ever changes, rather than
        // silently assuming exactly one.
        $anyAvail = false;
        $anyNonQual = false;
        $anyPending = false;
        $rtts = array();
        foreach ($endpoint['contacts'] as $contact) {
            if ($contact['status'] === 'Avail') {
                $anyAvail = true;
                if ($contact['rtt'] !== 'nan') {
                    $rtts[] = $contact['rtt'];
                }
            } elseif ($contact['status'] === 'NonQual') {
                // Ambiguous by construction: Asterisk uses the identical
                // string both for "qualify is disabled for this AOR" and
                // for "qualify is enabled but the first check has not run
                // yet" -- SENMA's OWN qualify config (not Asterisk's
                // runtime) is what disambiguates the two below.
                $anyNonQual = true;
            }
        }
        $anyUnavail = !$anyAvail && !$anyNonQual;
        if (!$qualifyEnabled) {
            return self::status(self::ACTIVE, 'Registered -- reachability not monitored (qualify disabled)');
        }
        if ($anyAvail) {
            $detail = count($rtts) > 0
                ? 'Registered -- reachable (' . implode('ms, ', $rtts) . 'ms)'
                : 'Registered -- reachable';
            return self::status(self::ACTIVE, $detail);
        }
        if ($anyNonQual) {
            return self::status(self::PENDING, 'Registered -- reachability check pending');
        }
        return self::status(self::DEGRADED, 'Registered -- not responding to reachability checks');
    }

    // =========================================================================
    // Trunks
    // =========================================================================

    /**
     * getTrunkStatuses - one status array per trunk row (PJSIP and
     * PJSIP_EXTERNAL alike; legacy chan_sip/IAX trunks are out of this
     * service's scope entirely -- see IpStatusController for those).
     *
     * @return array trunk id => status()
     */
    public static function getTrunkStatuses() {
        $db = Zend_Registry::get('db');
        $select = $db->select()
            ->from(array('t' => 'trunks'), array('id', 'name', 'technology', 'reverse_auth', 'username', 'disabled'))
            ->joinLeft(array('p' => 'peers'), "p.name = t.name AND p.peer_type = 'T'", array('qualify'))
            ->where('t.technology IN (?)', array('PJSIP', 'PJSIP_EXTERNAL'));
        $rows = $db->query($select)->fetchAll();

        $statuses = array();
        if (count($rows) === 0) {
            return $statuses;
        }

        $endpointsRaw = self::amiCommand('pjsip show endpoints');
        $endpoints = $endpointsRaw !== null ? self::parseEndpoints($endpointsRaw) : null;
        $registrationsRaw = self::amiCommand('pjsip show registrations outbound');
        $registrations = $registrationsRaw !== null ? self::parseRegistrations($registrationsRaw) : null;

        foreach ($rows as $row) {
            if (!empty($row['disabled'])) {
                $statuses[$row['id']] = self::status(self::DISABLED, 'Trunk disabled');
                continue;
            }
            if ($row['technology'] === 'PJSIP_EXTERNAL') {
                $statuses[$row['id']] = self::classifyExternal($endpoints, $row['username']);
                continue;
            }
            // technology === 'PJSIP'
            $objectName = 'trunk-' . $row['id'];
            if (!empty($row['reverse_auth'])) {
                $statuses[$row['id']] = self::classifyRegistration($registrations, $objectName, $endpoints);
            } elseif ($endpoints === null) {
                $statuses[$row['id']] = self::status(self::UNKNOWN, 'Could not query Asterisk runtime state');
            } else {
                $qualifyEnabled = !empty($row['qualify']) && $row['qualify'] !== 'no';
                $statuses[$row['id']] = self::classifyContact(
                    isset($endpoints[$objectName]) ? $endpoints[$objectName] : null,
                    $qualifyEnabled
                );
            }
        }
        return $statuses;
    }

    /**
     * classifyRegistration - a registered (reverse_auth=1) trunk's
     * status is authoritatively its OUTBOUND REGISTRATION state, not
     * merely whether the endpoint object loaded -- a registration
     * object can be Rejected while the endpoint itself is perfectly
     * "loaded" (confirmed live, TASK-0029B investigation: bad
     * credentials against the real provider fixture produced
     * `Unregistered` transiently, then a stable `Rejected`, while the
     * endpoint object itself never stopped existing).
     */
    private static function classifyRegistration($registrations, $objectName, $endpoints) {
        if ($registrations === null) {
            return self::status(self::UNKNOWN, 'Could not query Asterisk runtime state');
        }
        if (!isset($registrations[$objectName])) {
            // The endpoint may still exist even with no registration
            // object found (e.g. reverse_auth was just enabled and the
            // config has not been regenerated/reloaded yet) -- say so
            // precisely rather than a bare "not found".
            if ($endpoints !== null && isset($endpoints[$objectName])) {
                return self::status(self::UNKNOWN, 'Endpoint loaded, but no outbound registration found -- configuration may not have been applied yet');
            }
            return self::status(self::UNKNOWN, 'Not found in Asterisk\'s runtime configuration -- it may not have been applied yet');
        }
        $reg = $registrations[$objectName];
        switch ($reg['state']) {
            case 'Registered':
                return self::status(self::ACTIVE, 'Registered' . ($reg['detail'] !== '' ? ' -- ' . $reg['detail'] : ''));
            case 'Rejected':
                return self::status(self::ERROR, 'Registration rejected by the provider' . ($reg['detail'] !== '' ? ' ' . $reg['detail'] : ''));
            case 'Unregistered':
            case 'Registering':
            case 'Request Sent':
            case 'Auth Sent':
                return self::status(self::PENDING, 'Registering' . ($reg['detail'] !== '' ? ' -- ' . $reg['detail'] : ''));
            case 'Stopped':
                return self::status(self::INACTIVE, 'Registration stopped');
            default:
                // A real state Asterisk reported that this parser does
                // not have a specific bucket for -- never fabricate a
                // more specific answer than the evidence supports.
                return self::status(self::UNKNOWN, 'Unrecognized registration state: ' . $reg['state']);
        }
    }

    /**
     * classifyExternal - TASK-0029B Phase 2D/14: SENMA does not own a
     * pjsip_external trunk's endpoint configuration at all (no `peers`
     * row is ever created for one -- TrunksController::preparePost()'s
     * own comment is explicit about this). Read-only, existence-only by
     * design -- this never implies SENMA provisioned or controls the
     * object, only that it observed whether Asterisk currently has one
     * by this name.
     */
    private static function classifyExternal($endpoints, $externalEndpointName) {
        if ($endpoints === null) {
            return self::status(self::UNKNOWN, 'Could not query Asterisk runtime state');
        }
        if (!isset($endpoints[$externalEndpointName])) {
            return self::status(self::ERROR, "External endpoint '$externalEndpointName' not found in Asterisk -- verify it is provisioned outside SENMA");
        }
        $contacts = $endpoints[$externalEndpointName]['contacts'];
        if (count($contacts) === 0) {
            return self::status(self::ACTIVE, 'External endpoint present (SENMA does not manage its configuration)');
        }
        $avail = false;
        foreach ($contacts as $c) {
            if ($c['status'] === 'Avail') {
                $avail = true;
            }
        }
        return self::status(
            self::ACTIVE,
            $avail
                ? 'External endpoint present and reachable (SENMA does not manage its configuration)'
                : 'External endpoint present, contact reachability unconfirmed (SENMA does not manage its configuration)'
        );
    }

    // =========================================================================
    // Raw CLI parsing -- isolated here, never leaked to a controller/view
    // =========================================================================

    /**
     * parseEndpoints - `pjsip show endpoints` (bulk, every endpoint) or
     * `pjsip show endpoint <name>` (one) share the identical per-object
     * block shape -- confirmed live against both. Each endpoint's own
     * Contact line(s), if any, are inlined directly under it; this is
     * also confirmed live to hold with multiple endpoints in the same
     * bulk response, which is exactly what makes one bulk call
     * sufficient instead of one call per row.
     *
     * @param string $raw
     * @return array endpoint-object-name => array('contacts' => array(array('status'=>.., 'rtt'=>..)))
     */
    private static function parseEndpoints($raw) {
        $endpoints = array();
        $current = null;
        foreach (explode("\n", $raw) as $line) {
            // The name is always followed by either "/<CID>" (extensions,
            // which have a numeric caller id) or directly by column
            // padding whitespace (trunk endpoints, confirmed live: a
            // trunk's own callerid is a name string, not a number, and
            // produces no "/..." suffix at all here) -- both must match.
            if (preg_match('/^\s*Endpoint:\s+([^\/\s]+)(?:\/\S*)?\s/', $line, $m)) {
                $current = $m[1];
                $endpoints[$current] = array('contacts' => array());
                continue;
            }
            if ($current !== null && preg_match('/^\s*Contact:\s+[^\/\s]+\/\S+\s+\S+\s+(\S+)\s+(\S+)\s*$/', $line, $m)) {
                $endpoints[$current]['contacts'][] = array('status' => $m[1], 'rtt' => $m[2]);
                continue;
            }
            if (trim($line) === '') {
                $current = null;
            }
        }
        return $endpoints;
    }

    /**
     * parseRegistrations - `pjsip show registrations outbound`. The
     * trailing detail (e.g. "(exp. 3587s)"/"(exp. 4s ago)") can itself
     * contain whitespace, so it is captured as one remainder group and
     * classified by prefix rather than positional token-splitting --
     * confirmed necessary live: naive last-token parsing breaks on
     * exactly this field.
     *
     * @param string $raw
     * @return array "trunk-<id>" => array('state' => .., 'detail' => ..)
     */
    private static function parseRegistrations($raw) {
        $registrations = array();
        foreach (explode("\n", $raw) as $line) {
            if (!preg_match('/^\s*(\S+?)-registration\/\S+\s+\S+\s+(.*)$/', $line, $m)) {
                continue;
            }
            $objectName = $m[1];
            $remainder = trim($m[2]);
            $state = 'Unknown';
            $detail = '';
            // Longest/most-specific candidates first so e.g. "Request
            // Sent" is not matched by a hypothetical shorter prefix.
            foreach (array('Registered', 'Unregistered', 'Rejected', 'Stopped', 'Request Sent', 'Auth Sent', 'Registering') as $candidate) {
                if (strpos($remainder, $candidate) === 0) {
                    $state = $candidate;
                    $detail = trim(substr($remainder, strlen($candidate)));
                    break;
                }
            }
            if ($state === 'Unknown') {
                $detail = $remainder;
            }
            $registrations[$objectName] = array('state' => $state, 'detail' => $detail);
        }
        return $registrations;
    }

}
