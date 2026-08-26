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

require_once "PBX/Asterisk/Interface.php";

/**
 * Interface PJSIP
 *
 * Representação de uma Interface PJSIP do asterisk dentro da estrutura do
 * snep (TASK-0009). Mirrors PBX_Asterisk_Interface_SIP exactly -- getCanal()
 * is the only method the internal-call path (PBX_Usuarios::get(),
 * PBX_Rule_Action_DiscarRamal, resolv_interface.php) actually calls on a
 * ramal's interface object. Kept deliberately minimal: this is a runtime
 * compatibility shim for TASK-0009's development call proof, not the
 * production PJSIP provisioning model (which will also need to generate
 * static/realtime pjsip.conf config, unlike this class).
 *
 * @category  Snep
 * @package   PBX_Asterisk
 */
class PBX_Asterisk_Interface_PJSIP extends PBX_Asterisk_Interface {

    /**
     * __construct - Construtor da classe
     * @param <array> $config Array de configurações da interface
     */
    public function __construct($config) {
        $this->tech = 'PJSIP';
        $this->config = $config;
    }

    /**
     * getCanal - Devolve o canal que identifica essa interface no asterisk.
     * ex: para o ramal 1000
     * PJSIP/1000
     * @return <string> Canal
     */
    public function getCanal() {
        return $this->getTech() . "/" . $this->config['username'];
    }

    /**
     * getUsername - Devolve o usuário ao qual a interface faz ou aceita login.
     * @return <string> username
     */
    public function getUsername() {
        return $this->config['username'];
    }

    /**
     * getDialStringForDestination - TASK-0015 override for trunk dialing.
     *
     * chan_pjsip's dial syntax places the destination FIRST
     * ("PJSIP/<destination>@<endpoint>"), the reverse of chan_sip's
     * "Peer/exten" order the base class's default implementation
     * reproduces for every other interface. Config's 'username' here is
     * the trunk's own endpoint name (e.g. "trunk-3", set by
     * PBX_Trunks::get()'s PJSIP branch) -- not the provider-assigned
     * auth username (a separate value, stored in the auth object
     * Snep_PjsipTrunkConf generates, never consulted here). $postfix is
     * accepted for signature compatibility with the base class but is
     * not appended: it has no defined meaning in PJSIP's URI-style dial
     * syntax and is not evidenced as needed for this milestone's model
     * (chan_sip/Khomp-only KGSM options -- see
     * docs/tasks/0014-pjsip-trunk-provisioning-architecture.md §7/§11).
     *
     * @param string $destination
     * @param string $postfix unused for PJSIP, see above
     * @return string
     */
    public function getDialStringForDestination($destination, $postfix = "") {
        return $this->getTech() . "/" . $destination . "@" . $this->config['username'];
    }
}
