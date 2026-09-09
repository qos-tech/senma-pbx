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
 * Classe agi faz teste de permissão e existência nos arquivos referentes ao
 * asterisk
 *
 * @see Snep_Inspector_Test
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2010 OpenS Tecnologia
 * @author    Rafael Pereira Bozzetti <rafael@opens.com.br>
 *
 */
class AGI extends Snep_Inspector_Test {

    /**
     * Array de arquivos e permissões exigidas.
     *
     * TASK-0034I: this used to also require
     * '/var/lib/asterisk/agi-bin/snep' and '/var/lib/asterisk/moh' --
     * both Asterisk-container paths this check has no way to see: the
     * Inspector runs as PHP inside the `app` container, which (before
     * this task) had no visibility into /var/lib/asterisk at all
     * (confirmed live: file_exists() on either path always returned
     * false, independent of whether Asterisk's own copy existed). The
     * real, app-visible AGI requirement -- the bind-mounted
     * $config->system->path->base . '/agi' source tree PHP/Apache
     * actually serve AGI scripts from -- is added dynamically in
     * getTests() below instead, since it depends on the runtime config
     * path. The MOH directory has its own dedicated check
     * (inspectors/Sounds.php, "Music on Hold class") and does not
     * belong under an "AGI environment" label.
     *
     * Also removed: snep-iax2.conf, snep-iax2-trunks.conf, snep-sip.conf,
     * snep-sip-trunks.conf. TASK-0028C (docs/tasks/
     * 0028c-pjsip-legacy-runtime-closure.md) already classified these
     * exact 4 files DEAD_NOT_INCLUDED/GENERATED_EMPTY_LEGACY -- chan_sip
     * and chan_iax2 are absent from this Asterisk 22/PJSIP-only build,
     * nothing #includes them, and that task deliberately left
     * Snep_InterfaceConf still generating them (a documented, standalone
     * decision, not reversed here). Gating System Status on their
     * presence asserted they were REQUIRED_RUNTIME, which contradicts
     * that established classification -- see docs/tasks/
     * 0034i-system-status-dependency-runtime-resource-closure.md.
     * @var Array
     */
    public $paths = array('/etc/asterisk/snep/snep-authconferences.conf' => array('exists' => 1, 'writable' => 1, 'readable' => 1),
                          '/etc/asterisk/snep/snep-conferences.conf' => array('exists' => 1, 'writable' => 1, 'readable' => 1),
                          '/etc/asterisk/snep/snep-features.conf' => array('exists' => 1, 'writable' => 1, 'readable' => 1)
    );

    /**
     * Executa teste na criação do objeto.
     */
    public function __contruct() {
        self::getTests();
    }

    /**
     * Realiza testes de dono do arquivo e permissões de leitura e escrita
     * @return Array
     */
    public function getTests() {

        $result['agi']['error'] = 0;
        $result['agi']['message'] = '';

        // TASK-0034I: the real, app-visible AGI script source -- computed
        // here (not in the static $paths property above) since it
        // depends on the runtime config path.base value. astagidir
        // resolves AGI calls via a symlink Asterisk's own container
        // maintains (asterisk-entrypoint.sh); this side only needs to
        // confirm the source tree it serves that symlink's target from
        // is actually present/readable/writable.
        $config = Zend_Registry::get('config');
        $paths = $this->paths;
        $paths[$config->system->path->base . '/agi'] = array('exists' => 1, 'writable' => 1, 'readable' => 1);

        // Percorre array de arquivos
        foreach ($paths as $path => $agi) {

            // Verifica existencia do mesmo
            if ($agi['exists']) {
                if (!file_exists($path)) {
                    // Não existindo o arquivo registra concatena mensagem de erro.
                    $result['agi']['message'] .= Zend_Registry::get("Zend_Translate")->translate(" $path not exist.") ."\n";
                    // Seta erro com verdadeiro.
                    $result['agi']['error'] = 1;

                    // Existindo o arquivo, realiza testes.
                } else {

                    // Verifica se existe exigencia de gravação.
                    if ($agi['writable']) {
                        if (!is_writable($path)) {
                            // Não existindo permissão de gravação concatena mensagem de erro.
                            $result['agi']['message'] .=  Zend_Registry::get("Zend_Translate")->translate(" $path does not have permition to be modified.") ."\n";
                            // Seta erro como verdadeiro.
                            $result['agi']['error'] = 1;
                        }
                    }

                    // Verifica se existe exigênca de leitura.
                    if ($agi['readable']) {
                        if (!is_readable($path)) {
                            // Não existindo permissão de gravação concatena mensagem de erro.
                            $result['agi']['message'] .= Zend_Registry::get("Zend_Translate")->translate(" $path does not have permition to be viewed.") ."\n";
                            // Seta erro como verdadeiro.
                            $result['agi']['error'] = 1;
                        }
                    }
                }
            }
        }
        // Transforma newline em br
        $result['agi']['message'] = $result['agi']['message'];

        // Retorna array.
        return $result['agi'];
    }

    public function getTestName() {
        return Zend_Registry::get("Zend_Translate")->translate("Environment for AGI SNEP");
    }

}
