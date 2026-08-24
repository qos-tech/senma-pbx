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

require_once 'Zend/Form.php';

 /**
 * @see Snep_Form_Sectioned
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2011 OpenS Tecnologia 
 */
class Snep_Form_Sectioned extends Zend_Form {

    public function  __construct($options = null) {
        parent::__construct($options);
        
        $this->setElementDecorators(array(
            'ViewHelper',
            'Description',
            'Errors',
            array(array('elementTd' => 'HtmlTag'), array('tag' => 'td')),
            array('Label', array('tag' => 'th')),
            array(array('elementTr' => 'HtmlTag'), array('tag' => 'tr'))
        ));

        $this->setDecorators(array(
            'FormElements',
            array('HtmlTag', array('tag' => 'table')),
            array('Form', array('class' => 'snep_form sectioned_form'))
        ));

        $this->setButton();
    }
    
    /**
     * getEelementDecorators
     * @return <object>
     */
    public function getElementDecorators() {
        return $this->_elementDecorators;
    }


    protected function setButton() {
        $submit = new Zend_Form_Element_Submit("submit", array("label" => "Salvar"));
        $submit->removeDecorator('DtDdWrapper');
        $submit->addDecorator(array("opentd" => 'HtmlTag'), array('class' => 'form_control', "colspan" => 2, 'tag' => 'td', 'openOnly' => true, 'placement' => Zend_Form_Decorator_Abstract::PREPEND ));
        $submit->addDecorator(array("opentr" => 'HtmlTag'), array('tag' => 'tr', 'openOnly' => true, 'placement' => Zend_Form_Decorator_Abstract::PREPEND ));
        $submit->setOrder(100);

        $this->addElement($submit);

        $back = new Zend_Form_Element_Button("cancel", array("label" => "Cancelar" ));
        $back->setAttrib("onclick", "location.href='javascript:history.back();'");
        $back->removeDecorator('DtDdWrapper');
        $back->addDecorator(array("closetd" => 'HtmlTag'), array('tag' => 'td', 'closeOnly' => true, 'placement' => Zend_Form_Decorator_Abstract::APPEND));
        $back->addDecorator(array("closetr" => 'HtmlTag'), array('tag' => 'tr', 'closeOnly' => true, 'placement' => Zend_Form_Decorator_Abstract::APPEND));
        $back->setOrder(101);

        $this->addElement($back);
    }

}
