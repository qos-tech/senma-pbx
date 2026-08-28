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

require_once "Zend/Config/Ini.php";

/**
 * Classe estática para facilitar a obtenção das configurações do Snep.
 *
 * @author Henrique Grolli Bassotto
 */
abstract class Snep_Config {

    /**
     * Objeto que armazena as configurações do snep.
     *
     * @var Zend_Config
     */
    protected static $config;

    /**
     * Retorna o objeto que armazena as configurações do snep.
     *
     * @return Zend_Config $config
     */
    public static function getConfig() {
        if(self::$config === null) {
            self::setConfigFile("/etc/snep.conf");
        }

        return self::$config;
    }

    /**
     * Instancia um novo objeto de configurações para o snep a partir de um
     * caminho para um  arquivo .ini
     */
    public static function setConfigFile($file) {
        if (file_exists($file)) {
            $config = new Zend_Config_Ini($file);
            self::$config = $config;
        } else {
            throw new Exception("Fatal Error: configuration file not found: $file");
        }
    }

    /**
     * Get configuration on Snep and modules
     * @param <string> $module
     * @return <array> $configuration
     *
     * PHP 8 compatibility: Snep_Config is abstract (can never be
     * instantiated) and every call site in the codebase uses ::; the body
     * never uses $this. Pulled forward from the P1 Manager-class batch
     * (TASK-0002) because it's called from the shared page layout
     * (modules/default/views/layouts/layout.phtml), blocking every page,
     * not one specific flow. See
     * docs/tasks/0002-php84-compatibility-baseline.md.
     */
    public static function getAllConfiguration($module) {

        $db = Zend_registry::get('db');

        $select = $db->select()
                ->from("core_config")
                ->where("core_config.config_module = ?",$module);

        $stmt = $db->query($select);
        $configs = $stmt->fetchAll();

        return $configs;
    }

    /**
     * Get configuration on Snep and modules
     * @param <string> $module
     * @param <string> $key
     * @return <array> $configuration
     */
    public static function getConfiguration($module, $key) {

        $db = Zend_registry::get('db');

        $select = $db->select()
                ->from("core_config")
                ->where("core_config.config_module = ?",$module)
                ->where("core_config.config_name = ?",$key);

        $stmt = $db->query($select);
        $configs = $stmt->fetch();

        return $configs;
    }

    /**
     * TASK-0024: the write-side counterpart to getConfiguration() --
     * previously nonexistent, needed so Snep_Notifications/Snep_Version
     * can persist a small last-synced-at marker in the existing
     * core_config table (no schema change, no new table -- see
     * docs/tasks/0024-external-api-failure-isolation.md §2/§3/§5/§13).
     * core_config has no unique constraint on (config_module,
     * config_name) -- confirmed via SHOW CREATE TABLE -- so this must
     * select-then-insert-or-update, the same idempotent pattern already
     * established elsewhere in this codebase for tables lacking a real
     * unique key (e.g. scripts/smoke-test.sh's own handling of `users`).
     * @param <string> $module
     * @param <string> $key
     * @param <string> $value
     */
    public static function setConfiguration($module, $key, $value) {

        $db = Zend_Registry::get('db');
        $existing = self::getConfiguration($module, $key);

        if ($existing) {
            $db->update("core_config", array("config_value" => $value), array(
                $db->quoteInto("config_module = ?", $module),
                $db->quoteInto("config_name = ?", $key),
            ));
        } else {
            $db->insert("core_config", array(
                "config_module" => $module,
                "config_name" => $key,
                "config_value" => $value,
            ));
        }
    }

}
