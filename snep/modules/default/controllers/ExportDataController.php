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
include ("includes/functions.php");

/**
 * Record Report Controller
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2015 Opens Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 */
class ExportDataController extends Zend_Controller_Action {

    /**
     * Initial settings of the class
     */
    public function init() {

        $this->view->baseUrl = Zend_Controller_Front::getInstance()->getBaseUrl();
        $this->view->key = Snep_Dashboard_Manager::getKey(
            Zend_Controller_Front::getInstance()->getRequest()->getModuleName(),
            Zend_Controller_Front::getInstance()->getRequest()->getControllerName(),
            Zend_Controller_Front::getInstance()->getRequest()->getActionName());
    }

    /**
     * indexAction
     */
    public function indexAction() {

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array($this->view->translate("Reports"),$this->view->translate("Export Data Table")));

        $tables = array('users' => $this->view->translate("Users"),
                        'peers' => $this->view->translate("Extensions"),
                        'ccustos' => $this->view->translate("Tags"),
                        'trunks' => $this->view->translate("Trunks"),
                        'queues' => $this->view->translate("Queues"));
       
        $this->view->tables = $tables;

        $this->view->users = array('id' => $this->view->translate("Code"), 'name' => $this->view->translate("Name"), 'email' => "Email", 'created' => $this->view->translate("Create Date"), 'updated' => $this->view->translate("Update Date"));
        $this->view->peers = array('name' => $this->view->translate("Extension"), 'callerid' => $this->view->translate("Name"), 'secret' => $this->view->translate("Password"), 'dtmfmode' => $this->view->translate("DTMF Mode"), 'allow' => "Codec", 'canal' => $this->view->translate("Channel"), 'nat' => "Codec", 'directmedia' => "Directmedia");
        $this->view->ccustos = array('codigo' => $this->view->translate("Code"), 'tipo' => $this->view->translate("Type"), 'nome' => $this->view->translate("Name"), 'descricao' => $this->view->translate("Description"));
        $this->view->queues = array('id' => $this->view->translate("Code"), 'name' => $this->view->translate("Name"), 'musiconhold' => $this->view->translate("Music on hold"));
        $this->view->trunks = array('id' => $this->view->translate("Code"), 'callerid' => $this->view->translate("Name"), 'dtmfmode' => $this->view->translate("DTMF Mode"), 'host' => $this->view->translate("Host"), 'username' => $this->view->translate("Username"), 'secret' => $this->view->translate("Password"), 'allow' => "Codec", 'type' => $this->view->translate("Type"), 'channel' => $this->view->translate("Channel"), 'domain' => $this->view->translate("Domain"));
   
        if ($this->_request->getPost()) {
            $this->exportAction();            
        }

    }

    /**
     * getExportTables - canonical allowlist of table => valid column
     * names for the data-export feature.
     *
     * TASK-0026C (F11): the single source of truth exportAction()
     * validates $formData['group']/'coluns'/'orderby' against before any
     * of them reach SQL syntax. Table/column names are identifier
     * positions, not value positions, so ordinary parameter binding
     * (`where('col = ?', $v)`) does not apply -- a finite allowlist
     * mapped to trusted, hardcoded identifiers is the correct control
     * here (this task's own Phase 3 guidance). Mirrors indexAction()'s
     * existing per-table column keys exactly, so legitimate behavior is
     * unchanged; kept independent of indexAction()'s own arrays (which
     * also carry translated display labels, a display concern, not a
     * validation one) rather than derived from them, so a future label
     * text change can never silently alter the security allowlist.
     * @return array<string, array<string>>
     */
    private function getExportTables() {
        return array(
            'users' => array('id', 'name', 'email', 'created', 'updated'),
            'peers' => array('name', 'callerid', 'secret', 'dtmfmode', 'allow', 'canal', 'nat', 'directmedia'),
            'ccustos' => array('codigo', 'tipo', 'nome', 'descricao'),
            'trunks' => array('id', 'callerid', 'dtmfmode', 'host', 'username', 'secret', 'allow', 'type', 'channel', 'domain'),
            'queues' => array('id', 'name', 'musiconhold'),
        );
    }

    /**
     * exportAction - Export contacts for CSV file.
     */
    public function exportAction() {

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array($this->view->translate("Reports"),$this->view->translate("Export Data Table")));

        $formData = $this->_request->getPost();
        $exportTables = $this->getExportTables();

        if ($this->_request->getParam('download')) {

            $table = $_SESSION['exportData']['table'];
            $db = Zend_Registry::get('db');

            // TASK-0026C (F11): $table/coluns/order previously came
            // straight from $_SESSION['exportData'], itself populated
            // below with zero validation against indexAction()'s own
            // $tables allowlist -- an attacker could set an arbitrary
            // table, column list, and ORDER BY clause. Every identifier
            // used below is now required to be a member of the fixed
            // allowlist above; anything else is rejected before a query
            // is ever built.
            if (!isset($exportTables[$table])) {
                $this->view->error = $this->view->translate("No records found.");
                $this->renderScript('error/sneperror.phtml');
                return;
            }
            $validColumns = $exportTables[$table];
            // array_intersect() preserves $selectedColumns' own order
            // (the order the user's checkboxes were posted in), it just
            // drops anything not in $validColumns.
            $selectedColumns = array_values(array_intersect(explode(',', $_SESSION['exportData']['coluns']), $validColumns));
            if (empty($selectedColumns)) {
                $this->view->error = $this->view->translate("No records found.");
                $this->renderScript('error/sneperror.phtml');
                return;
            }
            $orderColumn = in_array($_SESSION['exportData']['order'], $validColumns, true)
                ? $_SESSION['exportData']['order']
                : $selectedColumns[0];

            $select = $db->select()
                ->from($table, $selectedColumns)
                ->order($orderColumn);
            $stmt = $db->query($select);
            $values = $stmt->fetchAll();

            // Varre array verificando se existe ; ou ,
            foreach($values as $key => $array){
                foreach($array as $colum => $value){
                    $res[$key][$colum] = str_replace(";", " ", $value);
                    $res[$key][$colum] = str_replace(",", " ", $value);
                }
            }

            $reportData['data'] = $res;
            $reportData['cols'] = $selectedColumns;

            if ($reportData) {
                $this->_helper->layout->disableLayout();
                $this->_helper->viewRenderer->setNoRender();

                $csv = new Snep_Csv();
                $csvData = $csv->generate($reportData['data'], $reportData['cols']);

                $dateNow = new Zend_Date();
                $fileName = $this->view->translate($table) . '_csv_' . $dateNow->toString("dd-MM-yyyy_hh'h'mm'm'") . '.csv';

                header('Content-type: application/octet-stream');
                header('Content-Disposition: attachment; filename="' . $fileName . '"');
                echo $csvData;

            } else {
                $this->view->error = $this->view->translate("No records found.");
                $this->renderScript('error/sneperror.phtml');
            }
        } else {

            // TASK-0026C (F11): reject an unknown/attacker-supplied
            // "group" (table) before anything derived from it is stored
            // in the session at all.
            if (!isset($formData['group']) || !isset($exportTables[$formData['group']])) {
                $this->view->error = $this->view->translate("No records found.");
                $this->renderScript('error/sneperror.phtml');
                return;
            }
            $validColumns = $exportTables[$formData['group']];

            // Selected columns -- only column KEYS present in this
            // table's own allowlist are kept (see getExportTables()).
            $fields = "" ;
            foreach((array) $formData['coluns'][$formData['group']] as $key => $value){
                if (in_array($key, $validColumns, true)) {
                    $fields .= $key.",";
                }
            }

            $ie = new Snep_CsvIE();
            $_SESSION['exportData']['table'] = $formData['group'];
            $_SESSION['exportData']['coluns'] = substr($fields, 0,-1);
            $_SESSION['exportData']['order'] = in_array($formData['orderby'][$formData['group']], $validColumns, true)
                ? $formData['orderby'][$formData['group']]
                : $validColumns[0];

            $this->view->form = $ie->exportResult();
            $this->view->title = "Export";
            $this->render('export');
        }

   }

}
