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
 * To change this template, choose Tools | Templates and open the 
 * template in the editor
 * @see Snep_Rest_Exception_HTTP
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2010 OpenS Tecnologia
 */
class Snep_Rest_Exception_HTTP extends Exception {

    protected $errorMessage = "";

    public function __construct($message = "Server Error", $code = 503, $errorMessage = "Server Error") {
        parent::__construct($message, $code);
        $this->errorMessage = $errorMessage;
    }
    
    /**
     * getErrorMessage
     * @return type
     */
    public function getErrorMessage() {
        return $this->errorMessage;
    }

}
