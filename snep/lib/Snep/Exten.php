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
require_once "Snep/Usuario.php";

/**
 * Classe que abstrai ramais do snep.
 *
 * @see Snep_Usuario
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2010 OpenS Tecnologia
 * @author    Henrique Grolli Bassotto
 */
class Snep_Exten extends Snep_Usuario {

    /**
     * Do Not Disturb
     *
     * @var boolean dnd
     */
    private $dnd;
    /**
     * Email para o qual as mensagens do voicemail serão enviadas.
     *
     * @var string email
     */
    private $email;
    /**
     * Ramal para siga-me
     *
     * @var Snep_Exten Siga-me
     */
    private $folowme;
    /**
     * Interface de comunicação fisica com o ramal.
     *
     * @var Interface objeto que herda a classe Interface
     */
    private $interface;
    /**
     * Trava do ramal.
     *
     * @var boolean locked
     */
    private $locked;
    /**
     * Caixa de mensagem do ramal (se houver).
     *
     * @var integer mailbox
     */
    private $mailbox;
    /**
     * Grupo de captura
     *
     * @var string
     */
    protected $pickupgroup;
    /**
     * Controle de minutos
     *
     * @var bool
     */
    protected $minuteControl;
    /**
     * Controle de minutos - Tempo total dosponível
     *
     * @var int
     */
    protected $timeTotal;
    /**
     * Controle de minutos - Periodisisação do controle
     *
     * @var int
     */
    protected $ctrlType;
         /**
     * Info de Canal 
     *
     * @var string
     */
    protected $channel;

    public function __construct($numero, $senha, $callerid, $interface) {
        parent::__construct($numero, $callerid, $numero, $senha);

        if (!$interface instanceof PBX_Asterisk_Interface) {
            throw new Exception("Error:  'Snep_Exten::__construct()' wait for a instancee of the abstract class: PBX_Asterisk_Interface");
        }

        $this->setInterface($interface);
        $this->unlock();
        $this->setFollowMe(null);
    }

    /**
     * __toString - Formato imprimivel do ramal
     * @return <string>
     */
    public function __toString() {
        return (string) $this->numero;
    }

    /**
     * DNDDisable - Desativa DND
     */
    public function DNDDisable() {
        $this->dnd = false;
    }

    /**
     * DNDEnable - Ativa DND
     */
    public function DNDEnable() {
        $this->dnd = true;
    }
    
    /**
     * getChannel
     * @return type
     */
    public function getChannel() {
        return $this->channel;
    }
    
    /**
     * setChannel
     * @param <string> $channel
     */
    public function setChannel($channel) {
        $this->channel = $channel;
    }


    /**
     * getEmail - Email do ramal para voicemail.
     * @return string email
     */
    public function getEmail() {
        return $this->email;
    }

    /**
     * getFollowMe - Retorna o ramal para siga-me, se habilitado.
     * @return <string> followme
     */
    public function getFollowMe() {
        return $this->followme;
    }
    
    /**
     * getTimeTotal
     * @return type
     */
    public function getTimeTotal() {
        return $this->timeTotal;
    }
    
    /**
     * getCtrlType
     * @return type
     */
    public function getCtrlType() {
        return $this->ctrlType;
    }

	public function getCancallforward() {
        return $this->cancallforward;
    }

    /**
     * getInterface - Retorna a interface física do ramal
     * @return PBX_Asterisk_Interface interface
     */
    public function getInterface() {
        $this->interface->setOwner($this);
        return $this->interface;
    }

    /**
     * getMailBox - Retorna a caixa de mensagem do ramal
     * @return <int> mailbox
     */
    public function getMailBox() {
        return $this->mailbox;
    }

    /**
     * getPickupGroup - Retorna a que grupo de captura pertence esse ramal
     * @return <string> pickupgroup
     */
    public function getPickupGroup() {
        return $this->pickupgroup;
    }

    /**
     * hasVoiceMail - Informa se o ramal tem ou não VoiceMail configurado
     * @return <boolean> hasVoicemail
     */
    public function hasVoiceMail() {
        return ($this->mailbox === null) ? false : true;
    }

    /**
     * isDNDActive - Verifica se DND está ou não ativado
     * @return <boolean> dnd
     */
    public function isDNDActive() {
        return $this->dnd;
    }

    /**
     * isLocked - Verifica se o ramal está ou não bloqueado.
     * @return <boolean> locked
     */
    public function isLocked() {
        return $this->locked;
    }

    /**
     * lock - Coloca o ramal em estado de trava. O sistema pode usar esse estado para
     * pedir senha antes de efetuar qualquer ação com esse ramal. (autenticação)
     */
    public function lock() {
        $this->locked = true;
    }

    /**
     * setEmail - Define um email para o ramal usar com voicemail.
     * @param <string> $email
     */
    public function setEmail($email) {
        $this->email = $email;
    }

    /**
     * setFollowMe - Define siga-me para ramal
     * @param <string> $ramal siga-me
     */
    public function setFollowMe($ramal) {
        $this->followme = $ramal;
    }

    /**
     * setInterface - Define a interface física do ramal
     * @param PBX_Asterisk_Interface $interface
     */
    public function setInterface($interface) {
        $this->interface = $interface;
    }

    /**
     * setMailBox - Define uma caixa de mensagens para o ramal.
     * @param <int> $mailbox
     */
    public function setMailBox($mailbox) {
        $this->mailbox = $mailbox;
    }

    /**
     * setPIckupGroup - Define a qual grupo de captura pertence esse usuário.
     * @param <string> $group name
     */
    public function setPickupGroup($group) {
        $this->pickupgroup = $group;
    }
    
    /**
     * setTimeTotal
     * @param <string> $timeTotal
     */
    public function setTimeTotal($timeTotal) {
        $this->timeTotal = $timeTotal;
    }
    
    /**
     * setCtrlType
     * @param <string> $ctrl
     */
    public function setCtrlType($ctrl) {
        $this->ctrlType = $ctrl;
    }

	public function setCancallforward($cancallforward) {
        $this->cancallforward = $cancallforward;
    }

    /**
     * unlock - Destrava o ramal
     */
    public function unlock() {
        $this->locked = false;
    }

}
