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
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2015 OpenS Tecnologia
 * @author    Flavio H. Somensi <flavio@opens.com.br>
 * 
 */
class Snep_Cnl {

    public function __construct() {}
    public function __destruct() {}
    public function __clone() {}

    /**
     * get country list
     * @return <Array> country list
     */
    public static function getCountries() {

        $db = Zend_Registry::get('db');

        $select = $db->select()
        ->from('core_cnl_country');

        $stmt = $db->query($select);
        $registros = $stmt->fetchAll();

        return $registros;
    }

    /**
     * get state
     * @param <String> $state - State code
     * @param <Integer> $country - Country code
     * @return <Array> Data found
     */
    public static function getState($state,$country) {
        
        $db = Zend_Registry::get('db');
        $select = $db->select()
        ->from('core_cnl_state')
        ->where("id = '$state'")
        ->where("country = '$country'");

        $stmt = $db->query($select);
        $registros = $stmt->fetchAll();

        return $registros;
    }
     /**
     * add state
     * @param <String> $state - State code
     * @param <Integer> $country - Country code
     * @param <String> $name - State name
     * @return <String> Error or NULL
     */
    public static function addState($state, $country, $name = 'Unknown') {
        
        $db = Zend_Registry::get('db');
        $db->beginTransaction();

        try {
            $db->insert('core_cnl_state', array(
                'id' => $state,
                'country' => $country,
                'name' => $name));
            $db->commit();
            return "" ;

        } catch (Exception $ex) {
            $db->rollBack();
            return $ex;
        }
    }

    /**
     * get city
     * @param <String> $state - State code
     * @param <String> $name - City Name
     * @return <Array> Data found
     */
    public static function getCityCode($state,$name) {
        
        $db = Zend_Registry::get('db');
        $select = $db->select()
        ->from('core_cnl_city')
        ->where("name = '$name'")
        ->where("state = '$state'");

        $stmt = $db->query($select);
        $registros = $stmt->fetchAll();

        return ( count($registros) > 0 ? $registros[0] : NULL );
        
    }

    /**
     * get city
     * @param <String> Telephon number
     * @return <String> City / State
     */
    public static function getCity($number) {
        
        $i18n = Zend_Registry::get("i18n");

        //Extract prefix number - valid from Brazil phone numbers
        // ------>>>>>>>>> TO DO - Get country code <<<<<<<------//
        switch (strlen($number)) {

            case 8 :
            case 9:
                $prefix = $i18n->translate("Local") ;
                break ;
          
            case 10 :
                $prefix = substr($number,0,6) ;
                break ;

            case 11 :
                if (substr($number,0,1) === "0") {
                    $prefix = substr($number,1,6) ;
                } elseif (substr($number,0,1) != "0" && substr($number,2,1) === "9") {
                    $prefix = substr($number,0,7)  ;
                } else {
                    $prefix = $i18n->translate("Unknown") ;
                }
                break ;

            case 12 :
                if (substr($number,0,1) === "0" && substr($number,3,1) === "9") {
                    $prefix = substr($number,1,7) ;
                } else {
                    $prefix = substr($number,2,6)  ;
                }
                break ;

            case 13 :
                if (substr($number,0,1) === "0" ) {
                    $prefix = substr($number,3,6) ;
                } elseif (substr($number,0,1) != "0" && substr($number,4,1) === "9") {
                    $prefix = substr($number,3,7) ;
                } else {
                    $prefix = $i18n->translate("Unknown");
                } 
                break ;

            case 14 :
                if (substr($number,0,1) === "0" && substr($number,5,1) === "9") {
                    $prefix = substr($number,3,7) ;
                } else {
                    $prefix = $i18n->translate("Unknown") ;
                }
                break;
            default:
                $prefix = $i18n->translate("Unknown") ;
                break;
        }

        // ------>>>>>>>>> TO DO - Get country code <<<<<<<------//
        if ($prefix != "Unknown" && $prefix != "Local") {
            $db = Zend_Registry::get('db');
            $select = $db->select()
            ->from(array('p' => 'core_cnl_prefix'), array('c.name', 'c.state'))
            ->joinleft(array('c' => 'core_cnl_city'), 'p.city = c.id')
            ->where("p.id = '$prefix'");

            $stmt = $db->query($select);
            $registros = $stmt->fetchAll();

            if (count($registros) > 0 ) {
                if ($registros[0]['name'] === NULL) {
                    $result = $i18n->translate("Cell");
                } else {
                    $result = $registros[0]['name'] . "/" . $registros[0]['state'] ;
                }
            } else {
                $result = $i18n->translate("Unknown");
            }

        } else {
            $result = $prefix;
        }
        return $result;
        
    }

    /**
     * add city
     * @param <String> $state - State Code (Ex: SP)
     * @param <String> $name - City name
     * @return <String> Error or 
     * @return <Integer> City Code
     */
    public static function addCity($state, $name ) {
        
        $db = Zend_Registry::get('db');
        $db->beginTransaction();

        $name = self::parseName($name) ;

        try {
            $insert_data = array('id' => NULL, 'state' => $state,'name' => $name);

            $db->insert('core_cnl_city', $insert_data);

            $id = $db->lastInsertId();

            $db->commit();

            return $id;

        } catch (Exception $ex) {
            $db->rollBack();
            return $ex;
        }
    }

    /**
     * get prefix
     * @param <Integer> $prefix - Prefix (For Brazil: DDD+Prefix)
     * @param <Integer> $country - Country Code
     * @return <Array> Data found
     */
    public static function getPrefix($prefix, $country) {
        
        $db = Zend_Registry::get('db');
        $select = $db->select()
        ->from('core_cnl_prefix')
        ->where("id = '$prefix'")
        ->where("country = '$country'");

        $stmt = $db->query($select);
        $registros = $stmt->fetchAll();

        return $registros;
    }

    /**
     * add prefix
     * @param <Integer> $prefix - Prefix (For Brazil: DDD+Prefix)
     * @param <Integer> $country - Country Code
     * @param <Integer> $city - City code
     * @param <String> $latitud
     * @param <String> $longitud
     * @param <String> $hemisphere
     * @return <String> Error or NULL 
     */
    public static function addPrefix($prefix, $country, $city, $latitud, $longitud, $hemisphere) {
        
        $db = Zend_Registry::get('db');
        $db->beginTransaction();

        try {
            $db->insert('core_cnl_prefix', array(
                'id' => $prefix,
                'country' => $country,
                'city' => $city,
                'latitud' => $latitud,
                'longitud' => $longitud,
                'hemisphere' => $hemisphere));

            $db->commit();
            return "" ;

        } catch (Exception $ex) {
            $db->rollBack();
            return $ex;
        }
    }

    /**
     * Parsing name file
     * @param <string> $name
     * @return <string> $name
     */
    public function parseName($name) {
    
        $invalid = array('â', 'ã', 'á', 'à', 'ẽ', 'é', 'è', 'ê', 'í', 'ì', 'ó', 'õ', 'ò', 'ô', 'ú', 'ù', 'ç', 'Â', 'Ã', 'Á', 'À', 'È', 'É', 'È', 'Ê', 'Í', 'Ì', 'Ó', 'Õ', 'Ò', 'Ô', 'Ú', 'Ù', 'Ç', '\'', '´');
        $valid   = array('a', 'a', 'a', 'a', 'e', 'e', 'e', 'e', 'i', 'i', 'o', 'o', 'o', 'o', 'u', 'u', 'c', 'A', 'A', 'A', 'A', 'E', 'E', 'E', 'E', 'I', 'I', 'O', 'O', 'O', 'O', 'U', 'U', 'C', ' ' , ' ');

        return str_replace($invalid, $valid, $name);
    }

    
}
