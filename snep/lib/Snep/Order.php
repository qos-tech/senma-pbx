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
 * Classe que abstrai os Vínculos
 *
 * @see Snep_Order
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2012 OpenS Tecnologia
 * @author    Iago Uilian Berndt <iagouilian@gmail.com.com.br>
 *
 */
class Snep_Order {

    /**
     * setSelect
     * @param <object> $select
     * @param <string> $opcoes
     * @param <string> $request
     * @return <array>
     */
    public static function setSelect($select, $opcoes, $request) {

        $order = Snep_Order::get($opcoes, $request);
        $select->order($order[0] . ($order[1] ? " " . $order[1] : ""));
        return array($order[0], $order[1]);
    }

    /**
     * get
     * @param <array> $opcoes
     * @param <object> $request
     * @return <array>
     */
    public static function get($opcoes, $request) {
        if ($request->getParam('order'))
            $order = $request->getParam('order');
        else
            $order = $opcoes[0];
        if (!in_array($order, $opcoes))
            $order = $opcoes[0];

        if ($request->getParam('desc'))
            $desc = "DESC";
        else
            $desc = "";

        if ($order == "prio")
            $desc = "DESC";

        return array($order, $desc);
    }

    /**
     * getLink
     * @param <object> $view
     * @param <string> $title
     * @param <string> $name
     * @return <string>
     */
    public static function getLink($view, $title, $name) {

        $class = "";
        $link = "";
        if ($name == $view->order[0] && !$view->order[1]) {
            $link = "limit/" . $view->limit . "/order/$name/desc/true";
            $class = "asc";
        } else {
            $link = "limit/" . $view->limit . "/order/" . $name;
            if ($name == $view->order[0])
                $class = "desc";
        }
        $link .= ($view->filter_value ? "/filter/" . $view->filter_value : "");
        return"<a class='order $class' href='" . $view->PAGE_URL . $link . "'>" . $view->translate($title) . "</a>";
    }

}