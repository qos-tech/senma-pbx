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
 * Classe de validação dos caracteres na alias de expressão 
 * 
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2012 OpenS Tecnologia
 * @author    Tiago Zimmermann <tiago@thesource.com.br>
 *
 * PHP 8 compatibility: the only external call site
 * (ExpressionAliasController.php:88,151) invokes execute() statically with
 * no object context, so its internal self::IdentificarChave()/
 * self::IdentificarValidade() calls have no $this to fall back on either.
 * The class is never instantiated and no method uses $this. Calling a
 * non-static method statically is a fatal Error since PHP 8.0. All
 * methods below declared static to match actual usage (TASK-0002 P1-A).
 * See docs/tasks/0002-php84-compatibility-baseline.md.
 */
class Snep_ValidateExpression {

    /**
     * execute - validação da expressão
     * @param <string> $String
     * @return <array>
     */
    public static function execute($String) {
        if (trim($String) === "") {
            return false ;
        }
        if (!self::IdentificarChave($String)) {
            return false;
        }
        if (!self::IdentificarValidade($String)) {
            return false;
        }

        return true;
    }

    /**
     * IdentificarValidade - Identifica se string possui caracteres invalidos
     * @param <string> $string
     * @return <boolean>
     */
    static function IdentificarValidade($string) {

        // Caracteres válidos
        $char_valido = array("%", "|", "#", ",", "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "a", "s", "d", "f", "g", "h", "j", "k", "l", "z", "x", "c", "v", "b", "n", "m", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "A", "S", "D", "F", "G", "H", "J", "K", "L", "Z", "X", "C", "V", "B", "N", "M", ".", "[", "]", "-", "_", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9");
        $array_char = str_split($string);
        $quant_error = implode(Array_diff($array_char, $char_valido));

        if (strlen($quant_error) != '0') {
            return false;
        } else {
            return true;
        }
    }

    /**
     * IdentificarChave - Identifica se possui valor nulo entre as chaves
     * @param <string> $string
     * @return <boolean>
     */
    static function IdentificarChave($string) {

        $total = strlen($string);
        $temp = false;
        $chaves1 = "[";
        $chaves2 = "]";
        // Flag - se encontrou chaves
        $status = false;
        for ($i = 0; $i < $total; $i++) {
            if ($string[$i] == $chaves1 && $string[$i + 1] == $chaves2) {
                $status = true;
            }
        }

        if ($status == true) {
            return false;
        } else {
            return true;
        }
    }

}

?>
