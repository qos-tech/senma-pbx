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
}
