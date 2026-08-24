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
 * @see Snep_Form_Element_Submit
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2011 OpenS Tecnologia 
 */
class Snep_Form_Element_Submit extends Zend_Form_Element {

    public function __construct($spec, $options = null) {
        parent::__construct($spec, $options);
    }

    /**
     * loadDefaultDecorators - Default decorators
     * Uses only 'Submit' and 'TrTdWrapper' decorators by default.
     * @return void
     */
    public function loadDefaultDecorators() {
        if ($this->loadDefaultDecoratorsIsDisabled()) {
            return;
        }

        $decorators = $this->getDecorators();
        if (empty($decorators)) {
            $this->setDecorators(array(
                array(array('elementTd' => 'HtmlTag'), array('tag' => 'td')),
                array(array('emptyTd' => 'HtmlTag'), array('tag' => 'td', 'placement' => Zend_Form_Decorator_Abstract::PREPEND)),
                array(array('elementTr' => 'HtmlTag'), array('tag' => 'tr', 'class' => 'snep_form_submit'))
            ));
        }
    }

    /**
     * render - Render form element
     * @param  Zend_View_Interface $view
     * @return string
     */
    public function render(Zend_View_Interface $view = null) {
        if ($this->_isPartialRendering) {
            return '';
        }

        if (null !== $view) {
            $this->setView($view);
        }

        $i18n = Zend_Registry::get('i18n');

        $disabled = $this->getAttrib("disabled") === NULL ? "" : sprintf('disabled="%s"', $this->getAttrib("disabled"));

        $content = sprintf('<div class="form-group"><div class="col-lg-12" align="center"><input type="submit" class="btn btn-add" value="%s" %s />', $this->_label, $disabled);
        if(Zend_Registry::isRegistered("cancel_url")) {
            $url = Zend_Registry::get("cancel_url");
        } else {
            $url = "javascript:history.back();";
        }
        $content .= sprintf('&nbsp;&nbsp; <a class="btn btn-outline btn-add" href="%s">%s</a></div></div><br>', $url, $i18n->translate("Cancel"));
        foreach ($this->getDecorators() as $decorator) {
            $decorator->setElement($this);
            $content = $decorator->render($content);
        }
        return $content;
    }

}

