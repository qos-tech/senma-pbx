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
 * Gerador de títulos com opções
 *
 * @see Snep_Titles
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2012 OpenS Tecnologia
 * @author    Iago Uilian Berndt <iagouilian@gmail.com.com.br>
 *
 */
class Snep_Title {

    public $title;
    public $options;

    /**
     * Constroi o título
     * @param <string> $title Titulo
     */
    public function __construct($title) {
        $this->title = $title;

        $nameBaseURL = Zend_Controller_Front::getInstance()->getBaseUrl();

        //$this->addOption('exit', $nameBaseURL . '/default/auth/logout');
        $nameModule = Zend_Controller_Front::getInstance()->getRequest()->getModuleName();
        $nameController = Zend_Controller_Front::getInstance()->getRequest()->getControllerName();
        $nameAction = Zend_Controller_Front::getInstance()->getRequest()->getActionName();
        $dashboard = Snep_Dashboard_Manager::getModelosNotUsed();

        foreach ($dashboard as $key => $value) {

            if (!isset($value['module'])) {

                $value['module'] = "";
            }

            if (
                    (
                    $value['module'] && $value['module'] == $nameModule || !$value['module'] && "default" == $nameModule
                    ) && (
                    FALSE !== strpos($value['link'], $nameController . "/" . $nameAction) || $nameController != "index" && $nameAction == "index" && $value['link'] == $nameController
                    )
            ) {
                echo "e";exit;
                $this->addOption('dashboard', $nameBaseURL . "/default/index/index/add/$key");
                break;
            }
        }
    }

    public function __destruct() {
        
    }

    public function __clone() {
        
    }

    /**
     * addOption - Adiciona opção
     * @param <int> $model
     * @param <string> $link
     */
    public function addOption($model, $link) {
        $this->options[] = Array('model' => $model, 'link' => $link);
    }

    /**
     * getHtml
     * @return <string> $html - html do titulo
     */
    public function getHtml() {
        $i18n = Zend_Registry::get("i18n");

        Zend_Controller_Front::getInstance()->getParam('bootstrap')
                ->getResource('layout')->getView()->headTitle()->
                append($i18n->translate(strval($this->title)));

        $baseUrl = Zend_Controller_Front::getInstance()->getBaseUrl();

        $html = "<div class='titleTop'>" . $i18n->translate(strval($this->title));
        $xml = simplexml_load_file('configs/titleOptions.xml');
        $modelos = Array();
        foreach ($xml->children() as $child) {
            foreach ($child->children() as $child2) {
                $modelos[$child->getName()][$child2->getName()] = $child2;
            }
        }
//        foreach ($this->options as $option) {
//            $html .= "<a class='option_$option[model]' href='$option[link]' class='option'><img alt='" .
//                    $i18n->translate(strval($modelos[$option['model']]['alt'])) .
//                    "' src='" .
//                    str_replace("/index.php", "", $baseUrl) .
//                    "/modules/default/img/" .
//                    $modelos[$option['model']]['icon'] .
//                    "'/><span>" .
//                    $i18n->translate(strval($modelos[$option['model']]['name'])) .
//                    "</span></a>";
//        }
        return $html . "</div>";
    }

}

?>
