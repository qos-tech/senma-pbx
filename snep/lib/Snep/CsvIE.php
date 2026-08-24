<?php

/**
 *  This file is part of SNEP.
 *  Para território Brasileiro leia LICENCA_BR.txt
 *  All other countries read the following disclaimer
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
 * Gerencia exportação e importação de CSV
 *
 * @see Snep_CsvIE
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2015 OpenS Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 *
 */
class Snep_CsvIE {

    /**
     * Contem o select a ser exportado
     */
    public $select;

    /**
     * Contem a tabela a ser exportada
     */
    public $table;

    /**
     * Contem o tipo de estrutura a ser exportada
     */
    public $type;

    /**
     * columns
     * @return <array> colunas da tabela
     */
    public function columns() {

        $db = Zend_Registry::get('db');
        if ($this->type == "cartesiano") {
            return array(array_keys($db->describeTable($this->table[0])), array_keys($db->describeTable($this->table[1])));
        } elseif ($this->type == "ignore") {
            return array_keys($db->describeTable($this->table[0]));
        } else {
            return array_keys($db->describeTable($this->table));
        }
    }

    /**
     * Define a tabela e o tipo de estrutura
     * @param <string> $table tabela.
     * @param <string> $type tipo de estrutura.
     */
    public function __construct($type = null) {

        $this->type = $type;
    }

    /**
     * getForm
     * @return <string> html do formulario de exportação
     */
    public function getForm() {
        if (isset($_FILES['csv']['tmp_name']))
            if (is_file($_FILES['csv']['tmp_name'])) {

                if ($this->type == "cartesiano") {
                    $result = $this->importCartesiano(fopen($_FILES['csv']['tmp_name'], 'r'));
                } else if ($this->type == "ignore") {
                    $result = $this->import(fopen($_FILES['csv']['tmp_name'], 'r'), $this->columns(), $this->table[0]);
                } else {
                    $result = $this->import(fopen($_FILES['csv']['tmp_name'], 'r'), $this->columns(), $this->table);
                }


                return '<div class="zend_form" id="form_ie">' .
                        '<span>' . $result[0] . '</span>' . $result[1] .
                        '<div class="menus">' .
                        '<input type="submit" name="submit" onclick="history.go(-1)" class="voltar" id="submit" title="Voltar" value="Voltar">' .
                        '</div>' .
                        '</div>';
            }
        return '<form enctype="multipart/form-data" action="" method="post">' .
                '<div class="zend_form" id="form_ie">' .
                '<span>Arquivo CSV</span>' .
                '<input type="file" name="csv" id="csv"/>' .
                '<div class="menus">' .
                '<input type="submit" name="submit" id="submit" title="Enviar" value="Enviar">' .
                '</div>' .
                '</div>' .
                '</div>' .
                '</form>';
    }

    /**
     * export - Gera e imprime a csv
     */
    public function export($select) {
        
        $db = Zend_Registry::get('db');

        $select = "SELECT ". $_SESSION['exportData']['coluns']. " FROM " .$_SESSION['exportData']['table'] . " ORDER BY " . $_SESSION['exportData']['order'];
        
        $stmt = $db->query($select);
        $values = $stmt->fetchAll();
        
        $reportData = array();
        $columns = explode(',', $_SESSION['exportData']['coluns']);
        
        foreach($columns as $key => $colun){
            $reportData['cols'][$colun] = $colun;
        }

        $reportData['data'] = $values;



        if ($reportData) {

            //$this->_helper->layout->disableLayout();
            $this->_helper->viewRenderer->setNoRender();
            
            $csv = new Snep_Csv();
            $csvData = $csv->generate($reportData['data'], true, $reportData['cols']);

            $dateNow = new Zend_Date();
            $fileName = $this->view->translate($table.'_csv_') . $dateNow->toString($this->view->translate(" dd-MM-yyyy_hh'h'mm'm' ")) . '.csv';

            header('Content-type: application/octet-stream');
            header('Content-Disposition: attachment; filename="' . $fileName . '"');
            echo $csvData;
        } else {
            $this->view->error = $this->view->translate("No records found.");
            $this->renderScript('error/sneperror.phtml');
        }
    }

    /**
     * exportResult
     * @return <string> html com o resultado da exportação
     */
    public function exportResult() {


        $db = Zend_Registry::get('db');

        $table = $_SESSION['exportData']['table'];
        $total = $db->fetchOne("SELECT COUNT(*) AS count FROM $table");

        $label = Snep_Locale::getInstance()->getZendTranslate()->translate("Export to CSV");
        $label2 = Snep_Locale::getInstance()->getZendTranslate()->translate("Total entries to be exported: ");
        $download = Snep_Locale::getInstance()->getZendTranslate()->translate("Download");
        $cancel = Snep_Locale::getInstance()->getZendTranslate()->translate("Cancel");

        return '<form enctype="" action="' . Zend_Controller_Front::getInstance()->getBaseUrl() . '/' . Zend_Controller_Front::getInstance()->getRequest()->getModuleName() . '/' . Zend_Controller_Front::getInstance()->getRequest()->getControllerName() . '/' . Zend_Controller_Front::getInstance()->getRequest()->getActionName() . '/download/true" method="post">' .
                '<div class="zend_form" id="form_ie">' .
                '   <h4><span>'.$label.'</span><br><br></h4>' .
                    $label2 . '<b> ' . $total . '</b>' .
                '   <div class="snep-body-footer-buttons">' .
                '      <input type="submit" class="btn btn-add btn-primary" style="width:100px;" name="submit" id="submit" title="Download" value="'.$download.'">' .
                '      &nbsp;&nbsp;&nbsp;<a class="btn btn-outline btn-add" href="javascript:window.history.go(-1)" role="button">'.$cancel.'</a>' .
                '   </div>' .
                '</div>' .
                '</form>';

    }

    /**
     * importCartesiano - importa csv com estrutura de produto cartesiano
     * @param <string> $file arquivo a ser importado
     */
    public function importCartesiano($f) {
        $tmp1 = tmpfile();
        $tmp2 = tmpfile();
        $columns = $this->columns();

        $line = fgetcsv($f);
        foreach ($line as $key => $value) {
            if ($key < count($columns[0])) {
                if ($value != $columns[0][$key])
                    return array("Erro", "Estrutura do CSV não pode ser importada0");
            }else {
                if ($value != $columns[1][$key - count($columns[0])])
                    return array("Erro", "Estrutura do CSV não pode ser importada1");
            }
        }

        fputcsv($tmp1, $columns[0]);
        fputcsv($tmp2, $columns[1]);

        $ant = array();

        while ($line = fgetcsv($f)) {
            $data = array();
            foreach ($line AS $key => $value) {
                if ($key < count($columns[0])) {
                    $data[0][] = $value;
                } else {
                    $data[1][] = $value;
                }
            }
            if ($ant !== $data[0])
                fputcsv($tmp1, $data[0]);
            $ant = $data[0];
            fputcsv($tmp2, $data[1]);
        }
        rewind($tmp1);
        rewind($tmp2);

        $result = $this->import($tmp2, $columns[1], $this->table[1]);
        if ($result[0] != "Erro")
            $result = $this->import($tmp1, $columns[0], $this->table[0]);
        return $result;
    }

    /**
     * import
     * @param <string> $f
     * @param <array> $columns
     * @param <string> $table
     * @return type
     */
    public function import($f, $columns, $table) {
        $db = Zend_Registry::get('db');
        $line = fgetcsv($f);
        if ($columns !== $line)
            return array("Erro", "Estrutura do CSV não pode ser importada");
        $i = 0;
        $buffer = array();
        $pedido = 0;
        $inserido = 0;
        do {
            $line = fgetcsv($f);
            if ($buffer && (!$line || !($i % 10))) {
                $query = "INSERT IGNORE INTO $table(`" . implode("`, `", $columns) . "`) VALUES " . implode(",", $buffer);
                $inserido += $db->Query($query)->rowCount();
                $i = 0;
                $buffer = array();
            }
            if ($line) {
                $data = array();
                foreach ($columns as $key => $column) {
                    $data[$column] = $line[$key];
                }
                foreach ($data as $key => $value)
                    $data[$key] = str_replace('\\"', '"', $value);
                $buffer[] = "('" . implode("','", $data) . "')";
                $pedido++;
            }
            $i++;
        } while ($line);

        return array("Importação realizada com sucesso", "$inserido cadastros inseridos <br/> " . ($pedido - $inserido) . " ignorados por repetição de identificação");
    }


    /**
     * exportResult
     * @return <string> html com o resultado da exportação
     */
    public function exportResultReport($selectcont) {


        $db = Zend_Registry::get('db');

        $result = $db->query($selectcont)->fetchAll();
        
        if(isset($result[0]['tot'])){
            $total = $result[0]['tot'];    
        }else{
            $total = count($result);
        }
        
        
        $label = Snep_Locale::getInstance()->getZendTranslate()->translate("Export to CSV");
        $label2 = Snep_Locale::getInstance()->getZendTranslate()->translate("Total entries to be exported: ");
        $download = Snep_Locale::getInstance()->getZendTranslate()->translate("Download");
        $cancel = Snep_Locale::getInstance()->getZendTranslate()->translate("Cancel");

        return '<form enctype="" action="' . Zend_Controller_Front::getInstance()->getBaseUrl() . '/' . Zend_Controller_Front::getInstance()->getRequest()->getModuleName() . '/' . Zend_Controller_Front::getInstance()->getRequest()->getControllerName() . '/' . Zend_Controller_Front::getInstance()->getRequest()->getActionName() . '/download/true" method="post">' .
                '<div class="zend_form" id="form_ie">' .
                '   <h4><span>'.$label.'</span><br><br></h4>' .
                    $label2 . '<b> ' . $total . '</b>' .
                '   <div class="snep-body-footer-buttons">' .
                '      <input type="submit" class="btn btn-add btn-primary" style="width:100px;" name="submit" id="submit" title="Download" value="'.$download.'">' .
                '      &nbsp;&nbsp;&nbsp;<a class="btn btn-outline btn-add" href="javascript:window.history.go(-1)" role="button">'.$cancel.'</a>' .
                '   </div>' .
                '</div>' .
                '</form>';

    }

}