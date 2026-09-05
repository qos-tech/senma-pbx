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
require_once "PBX/Asterisk/Interface/SIP.php";
require_once "PBX/Asterisk/Interface/SIP/NoAuth.php";
require_once "PBX/Asterisk/Interface/IAX2.php";
require_once "PBX/Asterisk/Interface/IAX2/NoAuth.php";
require_once "PBX/Asterisk/Interface/KHOMP.php";
require_once "PBX/Asterisk/Interface/VIRTUAL.php";
require_once "PBX/Asterisk/Interface/PJSIP.php";
require_once "Snep/Trunk.php";

/**
 * Classe que cuida da persistencia de troncos no banco de dados do snep.
 *
 * Nota sobre a persistencia: O controle de persistencia é feito no snep em
 * classes separadas. Não no construtor da classe modelo como se ve em outros
 * frameworks e arquiteturas. O motivo disso é que se ocorrer uma mudança na
 * forma como é feita a persistencia desses objetos os mesmos não precisam ser
 * alterados. Isso aumenta a compactibilidade com código legado.
 * ~henrique
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2010 OpenS Tecnologia
 * @author Henrique Grolli Bassotto
 */
class PBX_Trunks {

    private function __construct() { /* Protegendo métodos dinâmicos */
    }

    private function __destruct() { /* Protegendo métodos dinâmicos */
    }

    private function __clone() { /* Protegendo métodos dinâmicos */
    }

    /**
     * getAll - Método para obter todos os troncos registrados no sistema.
     * @return <array> Array com todos os usuarios do snep.
     */
    public static function getAll() {
        $db = Zend_Registry::get('db');

        $select = $db->select('id')
                ->from('trunks')
                ->order('id');

        $stmt = $db->query($select);
        $result = $stmt->fetchAll();

        $objetos = array();
        foreach ($result as $tronco) {
            $objetos[] = self::get($tronco['id']);
        }

        return $objetos;
    }

    /**
     * get - Retorna um tronco do banco de dados do snep.
     * @param <int> $id Numero do tronco a ser obtido
     */
    public static function get($id) {
        $db = Zend_Registry::get('db');

        $select = $db->select()->from('trunks')->where('id = ?', $id);
        $stmt = $db->query($select);
        $rawTrunk = $stmt->fetchObject();
        if (!$rawTrunk) {
            throw new PBX_Exception_NotFound("Trunk $id not found");
        }

        $tech = $rawTrunk->type;

        if (($tech == "SIP" || $tech == "IAX2") && $rawTrunk->dialmethod == "NOAUTH") {
            $config = array('host' => $rawTrunk->host);
            if ($tech == "SIP")
                $interface = new PBX_Asterisk_Interface_SIP_NoAuth($config);
            else
                $interface = new PBX_Asterisk_Interface_IAX2_NoAuth($config);
        }
        else if ($tech == "SIP") {
            $config = array(
                "username" => $rawTrunk->username,
                "secret" => $rawTrunk->secret,
                "host" => $rawTrunk->host
            );
            $interface = new PBX_Asterisk_Interface_SIP($config);
        } else if ($tech == "IAX2") {
            $config = array(
                "username" => $rawTrunk->username,
                "secret" => $rawTrunk->secret,
                "host" => $rawTrunk->host
            );
            $interface = new PBX_Asterisk_Interface_IAX2($config);
        } else if ($tech == "PJSIP") {
            // TASK-0015: 'username' here is SENMA's own PJSIP endpoint
            // name (trunk-<id>, TASK-0014 §10's object-naming scheme) --
            // NOT the provider-assigned auth username (a separate value,
            // stored only in the auth object Snep_PjsipTrunkConf
            // generates). getDialStringForDestination() is what actually
            // reads this; getCanal()/getHost() aren't used on the trunk
            // dial path. Outbound-only milestone: dialmethod=NOAUTH for
            // a PJSIP trunk is not specially handled here, matching
            // Snep_PjsipTrunkConf's own scope (no identify object) --
            // see docs/tasks/0014-pjsip-trunk-provisioning-architecture.md §7/§20.
            $config = array(
                "username" => "trunk-" . $rawTrunk->id,
                "secret" => $rawTrunk->secret,
                "host" => $rawTrunk->host
            );
            $interface = new PBX_Asterisk_Interface_PJSIP($config);
        } else if ($tech == "PJSIP_EXTERNAL") {
            // TASK-0028X: pjsip_external (TASK-0028B) never falls into the
            // "PJSIP" branch above -- trunks.type is persisted as the
            // literal string "PJSIP_EXTERNAL"
            // (TrunksController::preparePost()'s pjsip_external branch),
            // which is a different string than "PJSIP" and previously fell
            // through, unhandled, to the generic `else` (VIRTUAL) branch
            // below. VIRTUAL's getDialStringForDestination() is the base
            // class's default -- chan_sip's "Peer/exten" concatenation
            // ("PJSIP/<endpoint>/<destination>"), structurally wrong for
            // chan_pjsip, which requires "exten@endpoint". Reusing
            // PBX_Asterisk_Interface_PJSIP here (the same class the native
            // PJSIP branch above already uses) gets the correct
            // "PJSIP/<destination>@<endpoint>" form for free from its
            // existing getDialStringForDestination() override -- no new
            // dial-string formatting logic needed. Unlike a native PJSIP
            // trunk (whose 'username' is a SENMA-generated "trunk-<id>"
            // object name), a pjsip_external row's 'username' column
            // already holds the externally-managed endpoint's own name
            // exactly as validated by
            // TrunksController::externalPjsipEndpointExists() at creation
            // time -- see TrunksController.php's pjsip_external branch
            // ('username' => $endpoint) and
            // docs/tasks/0028b-pjsip-external-endpoint-trunks.md. Inbound
            // matching (PBX_Interfaces::getChannelOwner()) is unaffected:
            // it regexes trunks.id_regex directly from the DB row and only
            // calls PBX_Trunks::get() afterward, once a match is already
            // found -- this branch only changes which interface object is
            // built, not id_regex or the match itself. See
            // docs/tasks/0028-pjsip-only-architecture-audit.md ("Discagem
            // de tronco" finding) and
            // docs/tasks/0028x-pjsip-external-dialstring-fix.md.
            $config = array(
                "username" => $rawTrunk->username,
                "secret" => $rawTrunk->secret,
                "host" => $rawTrunk->host
            );
            $interface = new PBX_Asterisk_Interface_PJSIP($config);
        } else if ($tech == "KHOMP") {
            $khomp_id = substr($rawTrunk->channel, strpos($rawTrunk->channel, '/') + 1);
            $config = array(
                "board" => substr($khomp_id, 1, 1)
            );
            if (substr($khomp_id, 2, 1) == 'c') {
                $config['channel'] = substr($khomp_id, strpos($khomp_id, 'c') + 1);
            } else if (substr($khomp_id, 2, 1) == 'l') {
                $config['link'] = substr($khomp_id, strpos($khomp_id, 'l') + 1);
            }
            $interface = new PBX_Asterisk_Interface_KHOMP($config);
        } else {
            $interface = new PBX_Asterisk_Interface_VIRTUAL(array("channel" => $rawTrunk->channel, "channel_regex" => $rawTrunk->channel));
        }

        $trunk = new Snep_Trunk($rawTrunk->callerid, $interface);

        if ($rawTrunk->map_extensions) {
            $trunk->setExtensionMapping(true);
        }

        $trunk->setId($id);

        $trunk->setDtmfDialMode($rawTrunk->dtmf_dial ? true : false);
        $trunk->setDtmfDialNumber($rawTrunk->dtmf_dial_number);

        return $trunk;
    }

}
