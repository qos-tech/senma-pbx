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
 * Gerenciador de plugins das regras de negócio.
 *
 * @category  Snep
 * @package   Snep_Rule
 * @copyright Copyright (c) 2010 OpenS Tecnologia
 * @author Henrique Grolli Bassotto
 */
class PBX_Rule_Plugin_Broker extends PBX_Rule_Plugin {

    /**
     * Array com os plugins a serem executados.
     * @var <array>
     */
    protected $plugins = array();

    /**
     * Define a regra que tem controle sobre esse Broker
     * @param PBX_Rule $rule
     */
    public function setRule(PBX_Rule $rule) {
        parent::setRule($rule);
        foreach ($this->plugins as $plugin) {
            $plugin->setRule($rule);
        }
    }

    /**
     * Define a interface de comunicação com o asterisk em todos os plugins.
     * @param Asterisk_AGI $asterisk
     */
    public function setAsteriskInterface(Asterisk_AGI $asterisk) {
        parent::setAsteriskInterface($asterisk);
        foreach ($this->plugins as $plugin) {
            $plugin->setAsteriskInterface($asterisk);
        }
    }

    /**
     * registerPlugin - Register a plugin.
     * @param  PBX_Rule_Plugin $plugin
     * @param  <int> $stackIndex
     * @return PBX_Rule_Plugin_Broker
     */
    public function registerPlugin(PBX_Rule_Plugin $plugin, $stackIndex = null) {
        if (false !== array_search($plugin, $this->plugins, true)) {
            require_once 'Zend/Controller/Exception.php';
            throw new Zend_Controller_Exception('Plugin already registered');
        }

        $stackIndex = (int) $stackIndex;

        if ($stackIndex) {
            if (isset($this->plugins[$stackIndex])) {
                require_once 'Zend/Controller/Exception.php';
                throw new Zend_Controller_Exception('Plugin with stackIndex "' . $stackIndex . '" already registered');
            }
            $this->plugins[$stackIndex] = $plugin;
        } else {
            $stackIndex = count($this->plugins);
            while (isset($this->plugins[$stackIndex])) {
                ++$stackIndex;
            }
            $this->plugins[$stackIndex] = $plugin;
        }

        $rule = $this->getRule();
        if ($rule) {
            $this->plugins[$stackIndex]->setRule($rule);
        }

        $asterisk = $this->getAsteriskInterface();
        if ($asterisk) {
            $this->plugins[$stackIndex]->setAsteriskInterface($asterisk);
        }

        ksort($this->plugins);

        return $this;
    }

    /**
     * unregisterPlugin - Unregister a plugin.
     * @param string|PBX_Rule_Plugin $plugin Plugin object or class name
     * @return PBX_Rule_Plugin_Broker
     */
    public function unregisterPlugin($plugin) {
        if ($plugin instanceof Zend_Controller_Plugin) {
            // Given a plugin object, find it in the array
            $key = array_search($plugin, $this->plugins, true);
            if (false === $key) {
                require_once 'Zend/Controller/Exception.php';
                throw new Zend_Controller_Exception('Plugin never registered.');
            }
            unset($this->plugins[$key]);
        } elseif (is_string($plugin)) {
            // Given a plugin class, find all plugins of that class and unset them
            foreach ($this->plugins as $key => $_plugin) {
                $type = get_class($_plugin);
                if ($plugin == $type) {
                    unset($this->plugins[$key]);
                }
            }
        }
        return $this;
    }

    /**
     * hasPlugin - Is a plugin of a particular class registered?
     * @param  <string> $class
     * @return <boolean>
     */
    public function hasPlugin($class) {
        foreach ($this->plugins as $plugin) {
            $type = get_class($plugin);
            if ($class == $type) {
                return true;
            }
        }

        return false;
    }

    /**
     * getPlugin - Retrieve a plugin or plugins by class
     * @param  <string> $class Class name of plugin(s) desired
     * @return false|PBX_Rule_Plugin|array Returns false if none found, plugin
     * if only one found, and array of plugins if multiple plugins of same class
     * found
     */
    public function getPlugin($class) {
        $found = array();
        foreach ($this->plugins as $plugin) {
            $type = get_class($plugin);
            if ($class == $type) {
                $found[] = $plugin;
            }
        }

        switch (count($found)) {
            case 0:
                return false;
            case 1:
                return $found[0];
            default:
                return $found;
        }
    }

    /**
     * getPlguins - Retrieve all plugins
     * @return <array>
     */
    public function getPlugins() {
        return $this->plugins;
    }

    /**
     * startup - Invoca o metodo correspondente de todos os plugins registrados.
     */
    public function startup() {
        foreach ($this->plugins as $plugin) {
            try {
                $plugin->startup();
            } catch (PBX_Exception_AuthFail $ex) {
                throw $ex;
            } catch (PBX_Rule_Action_Exception_StopExecution $ex) {
                throw $ex;
            } catch (PBX_Rule_Action_Exception_GoTo $ex) {
                throw $ex;
            } catch (Exception $ex) {
                Zend_Registry::get("log")->err($ex);
            }
        }
    }

    /**
     * preExecute - Invoca o metodo correspondente de todos os plugins registrados.
     * @param <int> $index Índice da ação que está sendo executada essa chamada
     */
    public function preExecute($index) {
        foreach ($this->plugins as $plugin) {
            try {
                $plugin->preExecute($index);
            } catch (PBX_Exception_AuthFail $ex) {
                throw $ex;
            } catch (PBX_Rule_Action_Exception_StopExecution $ex) {
                throw $ex;
            } catch (PBX_Rule_Action_Exception_GoTo $ex) {
                throw $ex;
            } catch (Exception $ex) {
                Zend_Registry::get("log")->err($ex);
            }
        }
    }

    /**
     * postExecute - Invoca o metodo correspondente de todos os plugins registrados.
     * @param <int> $index Índice da ação que está sendo executada essa chamada
     */
    public function postExecute($index) {

      $action = $this->rule->getAction($index);
      if ($action instanceof DiscarTronco) {
        $log = Zend_Registry::get('log');

        $asterisk = $this->asterisk;
        // Tempo que será contabilizado
        $answered_time = $asterisk->get_variable("ANSWEREDTIME");
        $answered_time = (int) $answered_time['data'];

        if ($answered_time > 0) {

          //Update
          $db = Zend_Registry::get("db");
          $config = $action->getConfigArray();
          $trunkId = $config['tronco'];
          $tronco = PBX_Trunks::get($config['tronco']);

          $sql = "SELECT time_total, time_chargeby, time_initial_date FROM trunks WHERE id='$trunkId' AND time_total IS NOT NULL";
          $owner_info = $db->query($sql)->fetchAll();

          $year = date("Y");

          if (count($owner_info) == 1) {
            $controlling = true;
            $ownertype = 'T';
            // Ver se temos dados, se nao (e for necessario) adicionamos
            $sql = "SELECT * FROM time_history WHERE owner='$trunkId' && owner_type='$ownertype' ";
            switch ($owner_info[0]['time_chargeby']) {
              case 'Y':
                $sql .= "&& year=YEAR(NOW()) && month IS NULL && day IS NULL";
                break;
              case 'M':
                $day = date('d');
                if($day < $owner_info[0]['time_initial_date']){
                  $month = date('m');
                }else{
                  $month = date("m", strtotime("+1 month"));
                  if($month == '01'){
                    $year = date("Y", strtotime("+1 year"));
                  }
                }

                $sql .= "&& year='$year' && month='$month' && day IS NULL";
                break;
              case 'D':
                $sql .= "&& year=YEAR(NOW()) && month=MONTH(NOW()) && day=DAY(NOW())";
                break;
            }


            $query_result = $db->query($sql)->fetchAll();

            if (count($query_result) > 0 ){
              $asterisk->verbose("Contabilizando {$answered_time} segundos para tronco {$trunkId} - {$tronco}");
              $queryId = $query_result[0]['id'];
              try {
                $sql = "SELECT used FROM time_history WHERE id='$queryId'";
                $history = $db->query($sql)->fetchAll();

                $used = $query_result[0]['used'] + $answered_time;

                $sql = "UPDATE time_history SET used='$used', changed=NOW() WHERE id='$queryId'";
                $db->query($sql);
              } catch (Exception $e) {
                throw new Exception("Fatal Error while updating the time: " . $e->getMessage());
              }

            }else{
              $asterisk->verbose("Inserindo {$answered_time} segundos para tronco {$trunkId} - {$tronco}");
              $sql = "INSERT INTO time_history VALUES ";
              switch ($owner_info[0]['time_chargeby']) {
                case 'Y':
                  $sql .= "('', '$trunkId', YEAR(NOW()), NULL, NULL, '$answered_time',NOW(), '$ownertype')";
                  break;
                case 'M':
                  $sql .= "('', '$trunkId', '$year', '$month', NULL, '$answered_time', NOW(), '$ownertype')";
                  break;
                case 'D':
                  $sql .= "('', '$trunkId', YEAR(NOW()), MONTH(NOW()), DAY(NOW()), '$answered_time', NOW(), '$ownertype')";
                  break;
              }
              // adicionando
              $db->query($sql);
            }
          }
        }
      }

      foreach ($this->plugins as $plugin) {
        try {
          $plugin->postExecute($index);
        } catch (PBX_Exception_AuthFail $ex) {
          throw $ex;
        } catch (PBX_Rule_Action_Exception_StopExecution $ex) {
          throw $ex;
        } catch (PBX_Rule_Action_Exception_GoTo $ex) {
          throw $ex;
        } catch (Exception $ex) {
          Zend_Registry::get("log")->err($ex);
        }
      }
    }

    /**
     * shutdown - Invoca o metodo correspondente de todos os plugins registrados.
     */
    public function shutdown() {
        foreach ($this->plugins as $plugin) {
            try {
                $plugin->shutdown();
            } catch (PBX_Exception_AuthFail $ex) {
                throw $ex;
            } catch (PBX_Rule_Action_Exception_StopExecution $ex) {
                throw $ex;
            } catch (PBX_Rule_Action_Exception_GoTo $ex) {
                throw $ex;
            } catch (Exception $ex) {
                Zend_Registry::get("log")->err($ex);
            }
        }
    }

}
