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

/**
 * Conference Controller
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2014 OpenS Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 */
class ConferenceRoomsController extends Zend_Controller_Action {

 
    /**
     * indexAction - List Conference Rooms
     * @return <boolean>
     * @throws ErrorException
     */
    public function indexAction() {

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Conference Rooms")));

        $config = Zend_Registry::get('config');
        $conf_app = $config->ambiente->conference_app;
        $language = $config->system->language ;

        for ($i = 901; $i <= 915; $i++) {

            $salas[$i]["id"] = $i;
            $salas[$i]["authenticate"] = "";
            $salas[$i]["status"] = 0;
            $salas[$i]["rec"] = False;
            $salas[$i]["ccustos"] = "5.01";
        }

        exec('cat /etc/asterisk/snep/snep-authconferences.conf | grep "^[9][0-1][0-9]"', $senhas, $err);

        foreach ($senhas as $value) {
            $line = explode(":", $value);
            $salas[$line[0]]["authenticate"] = $line[1];
        }

        //verifica se salas possuem gravacao
        exec("cat /etc/asterisk/snep/snep-conferences.conf | grep 'exten => [9][0-1][0-9],n,Set(gravacao' | cut -d '>' -f2", $gravacoes, $err);

        foreach ($gravacoes as $gravacao_ => $gravacao) {
            $item = explode(",", $gravacao);
            $item_ = trim($item[0]);
            $salas[$item_]["rec"] = true;
        }

        exec("cat /etc/asterisk/snep/snep-conferences.conf | grep 'exten => [9][0-1][0-9]' | cut -d '>' -f2", $out, $err);

        foreach ($out as $key => $value) {
            $room = explode(",", $value);

            if (isset($room[0])) {
                $sala = trim($room[0]);
                $salas[$sala]["status"] = 1;

                (isset($salas[$sala]["ccustos"]) ? null : $salas[$sala]["ccustos"] = "");
            }

            if (strpos($room[2], "accountcode") > 0) {
                $ccustos = trim(substr($room[2], strpos($room[2], "=") + 1, -1));
                $salas[$sala]["ccustos"] = $ccustos;
            }
        }

        $this->view->baseUrl = Zend_Controller_Front::getInstance()->getBaseUrl();
        $this->view->key = Snep_Dashboard_Manager::getKey(
            Zend_Controller_Front::getInstance()->getRequest()->getModuleName(),
            Zend_Controller_Front::getInstance()->getRequest()->getControllerName(),
            Zend_Controller_Front::getInstance()->getRequest()->getActionName());

        $this->view->conferenceRooms = $salas;
        $this->view->costCenter = Snep_CostCenter_Manager::getAll();

        // After post
        if ($this->getRequest()->getPost()) {
            $file_conf = "/etc/asterisk/snep/snep-conferences.conf";
            $file_auth = "/etc/asterisk/snep/snep-authconferences.conf";

            if (!is_writable($file_conf) || !is_writable($file_auth)) {
                $this->view->error_message = $this->view->translate("File does not have editing permission");
                $this->renderScript('error/sneperror.phtml');
                return False;
            }

            $linhas_conf = file($file_conf);
            $linhas_auth = file($file_auth);

            for ($i = 901; $i <= 915; $i++) {
                $rec = $salas[$i]["rec"];
            }

            $costCenter = $_POST['costCenter'];
            $activate = $_POST['activate'];
            $password = $_POST['password'];
            $rec = $_POST["rec"];

            $updateDate = "; Atualizado em:" . date('d/m/Y H:i:s') . "\n";

            $contentAuth = ";-------------------------------------------------------------------------------\n";
            $contentAuth .= "; Arquivo: snep-authenticate.conf - Cadastro de Senhas de Cadeado\n";
            $contentAuth .= "; Sintaxe: codigo,senha(hash MD5)\n";
            $contentAuth .= "; Include: em /etc/asterisk/extensions.conf\n";
            $contentAuth .= ";      Ex: exten => _[7-9]XXXXXXX,n,Authenticate(/etc/asterisk/snep/snep-authenticate,am)\n";
            $contentAuth .= "; Atualizado em: $updateDate \n";
            $contentAuth .= "; Copyright(c) 2015 Opens Tecnologia\n";
            $contentAuth .= ";-------------------------------------------------------------------------------\n";
            $contentAuth .= "; Os registros a Seguir sao gerados pelo Software SNEP. \n";
            $contentAuth .= "; Este Arquivo NAO DEVE ser editado Manualmente sob riscos de \n";
            $contentAuth .= "; causar mau funcionamento do Asterisk\n";
            $contentAuth .= ";-------------------------------------------------------------------------------\n";

            $contentConfe = ";----------------------------------------------------------------\n";
            $contentConfe .= "; Arquivo: snep-conferences.conf - Salasa de COnferencia\n";
            $contentConfe .= "; Sintaxe: exten => sala,1,Set(CHANNEL(language)=br)\n";
            $contentConfe .= ";          exten => sala,n,Set(CHANNEL(accountcode)=Conferencia)\n";
            $contentConfe .= ";  (*)     exten => sala,n,Authenticate(senha em hash md5,a)\n";
            $contentConfe .= ";          exten => sala,n,Conference(\${EXTEN}/S)\n";
            $contentConfe .= ";          exten => sala,n,Hangup\n";
            $contentConfe .= "; (*) = Linha Opcional - so aparece se usar senha\n";
            $contentConfe .= "; Include: em /etc/asterisk/extensions.conf\n";
            $contentConfe .= ";          include /etc/asterisk/snep/snep-conferences.conf\n";
            $contentConfe .= "; Atualizado em: $updateDate\n";
            $contentConfe .= "; Copyright(c) 2015 Opens Tecnologia\n";
            $contentConfe .= ";----------------------------------------------------------------\n";
            $contentConfe .= "; Os registros a Seguir sao gerados pelo Software SNEP.\n";
            $contentConfe .= "; Este Arquivo NAO DEVE ser editado Manualmente sob riscos de\n";
            $contentConfe .= "; causar mau funcionamento do Asterisk\n";
            $contentConfe .= ";----------------------------------------------------------------\n";
            $contentConfe .= "[conferences]\n";
            $contentConfe .= "\n";
            $contentConfe .= "; Next Lines = Default of System - don't change, please\n";
            $contentConfe .= "exten => i,1,Set(CHANNEL(language)=$language)\n";
            $contentConfe .= "exten => i,n,Playback(invalid)\n";
            $contentConfe .= "exten => i,n,Hangup\n";
            $contentConfe .= "\n";
            $contentConfe .= "exten => t,1,Hangup\n";
            $contentConfe .= "exten => h,1,Hangup\n";
            $contentConfe .= "exten => H,1,Hangup\n";
            $contentConfe .= "\n";


            foreach ($activate as $idActivate => $val) {
                


                $contentConfe .= ";SNEP(" . $idActivate . "): Room added by system\n";
                $contentConfe .= "exten => " . $idActivate . ",1,Set(CHANNEL(language)=$language)\n";
                
                // Passwords
                if ($salas[$idActivate]['authenticate'] <>  "" && $password[$idActivate] === "") {
                    $password[$idActivate] = $salas[$idActivate]['authenticate'] ;
                }
                if ($password[$idActivate] <> "" ) {
                    $valuePassword = $password[$idActivate] ;
                    if (strlen($valuePassword) != 32) {
                        $valuePassword = md5($valuePassword);
                    }
                    $newPassword = $idActivate . ":" . $valuePassword . "\n";
                    $contentAuth .= $newPassword;
                    $contentConfe .= "exten => " . $idActivate . ",n,Authenticate(/etc/asterisk/snep/snep-authconferences.conf,m)\n";
                }

                // Tag
                $valueCostCenter = $costCenter[$idActivate]; 
                $contentConfe .= "exten => " . $idActivate . ",n,Set(CHANNEL(accountcode)=" . $valueCostCenter . ")\n";
                $contentConfe .= "exten => " . $idActivate . ",n,Answer()\n";
                $contentConfe .= "exten => " . $idActivate . ",n,Set(CONFBRIDGE_JOIN_SOUND=beep)\n";
                $contentConfe .= "exten => " . $idActivate . ",n,Set(CONFBRIDGE_MOH=default)\n";

                $date = date("Y-m-d");
                $hour = date("H");
                $path_voz = $config->ambiente->path_voz;

                foreach ($rec as $_rec_ => $_rec) {

                    if ($_rec == "") {
                        if ($idActivate == $_rec_) {

                            $contentConfe .= "exten => " . $_rec_ . ",n,Set(gravacao=/$path_voz/$_rec_/$";
                            $contentConfe .= "{UNIQUEID:0:10}_$";
                            $contentConfe .= "{STRFTIME($";
                            $contentConfe .= "{EPOCH},,%Y%m%d_%H%M)}_$";
                            $contentConfe .= "{EXTEN:}_$";
                            $contentConfe .= "{CALLERID(num)})\n";

                            $contentConfe .= "exten => " . $_rec_ . ",n,Set(CDR(userfield)=$";
                            $contentConfe .= '{UNIQUEID:0:10}_$';
                            $contentConfe .= '{STRFTIME($';
                            $contentConfe .= '{EPOCH},,%Y%m%d_%H%M)}_$';
                            $contentConfe .= '{EXTEN:}_$';
                            $contentConfe .= "{CALLERID(num)}" . ")\n";
                            $contentConfe .= "exten => " . $_rec_ . ",n,MixMonitor($";
                            $contentConfe .= "{gravacao}.wav)\n";
                        }
                    }
                }
                $contentConfe .= "exten => " . $idActivate . ",n,ConfBridge(\${EXTEN})\n";
                $contentConfe .= "exten => " . $idActivate . ",n,Hangup\n";
                $contentConfe .= "\n";
            }

            file_put_contents($file_conf, $contentConfe);
            file_put_contents($file_auth, $contentAuth);

            $asterisk = PBX_Asterisk_AMI::getInstance();
            $asterisk->Command("module reload");
            $this->_redirect($this->getRequest()->getControllerName());
        }
    }

}
