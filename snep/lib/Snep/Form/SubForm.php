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
 * @see Snep_Form_SubForm
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2011 OpenS Tecnologia 
 */
class Snep_Form_SubForm extends Zend_Form {
    /**
     * Whether or not form elements are members of an array
     * @var bool
     */
    protected $_isArray = true;

    public function __construct($legend = null, $options = null, $name = null) {
        $this->addPrefixPath('Snep_Form', 'Snep/Form');
        parent::__construct($options);

        if($legend !== null) {
            $legend = new Snep_Form_Element_SectionTitle("title", array("label"=>$legend));
            $legend->setOrder(0);
            $this->addElement($legend);
        }

        $this->setElementDecorators(array(
            'ViewHelper',
            'Description',
            'Errors',
            array(array('elementTd' => 'HtmlTag'), array('tag' => 'td')),
            array('Label', array('tag' => 'th')),
            array(array('elementTr' => 'HtmlTag'), array('tag' => 'tr', 'class'=>"snep_form_element" . " $name"))
        ));

        $this->setDecorators(array(
            'FormElements'
        ));
    }
}
