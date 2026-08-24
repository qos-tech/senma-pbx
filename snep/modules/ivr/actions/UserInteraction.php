<?php
/**
 *  This file is part of SNEP, a SNEP Module.
 *
 *  IVR is a copyright from Opens Tecnologia.
 */

/**
 * Run a IVR
 *
 *
 * @see PBX_Rule
 * @see PBX_Rule_Action
 *
 * @category  Snep
 * @package   PBX_Rule_Action
 * @copyright Copyright (c) 2015 OpenS Tecnologia
 * @author    Douglas Conrad
 */
class UserInteraction extends PBX_Rule_Action {

    /**
     * @var Internacionalization
     */
    private $i18n;

    /**
     * Constructor
     * @param
     */
    public function __construct() {
        	$this->i18n = Zend_Registry::get("i18n");
    }

    /**
     * Define the actions configs
     * @param array $config
     */
    public function setConfig($config) {

        parent::setConfig($config);

        $this->file = $config['file'];
        $this->userentry = ( isset($config['userentry']) && $config['userentry'] == 'true') ? true:false;

    }

    /**
     * Return the Action Name
     * @return Action Name
     */
    public function getName() {
        return $this->i18n->translate("User Interaction");
    }

    /**
     * Retorna o numero da versão da classe.
     * @return Versão da classe
     */
    public function getVersion() {
        return SNEP_VERSION;
    }

    /**
     * Return the Action Description
     * @return
     */
    public function getDesc() {
        return $this->i18n->translate("Run an automation process defined by the administrator.");
    }

    /**
     * Return a XML with all configurations needed by the Action
     * @return String XML
     */
    public function getConfig() {
        $maxdigits = (isset($this->config['maxdigits']))?"<value>{$this->config['maxdigits']}</value>":"";
        $allow_exten_dial = (isset($this->config['allow_exten_dial']))?"<value>{$this->config['allow_exten_dial']}</value>":"";
        $finalflow = (isset($this->config['finalflow']))?"<value>{$this->config['finalflow']}</value>":"";
        $file = (isset($this->config['file']))?"<value>{$this->config['file']}</value>":"";
        $timeout = (isset($this->config['timeout']))?"<value>{$this->config['timeout']}</value>":"10";
        $digits = (isset($this->config['digits']))?"<value>{$this->config['digits']}</value>":"4";
        $forward_call = (isset($this->config['forward_call']))?"<value>{$this->config['forward_call']}</value>":"";
        $var_name = (isset($this->config['var_name']))?"<value>{$this->config['var_name']}</value>":"";

        $menu = array(
          "audio_file" => $this->i18n->translate('Menu Audio File'),
          "maxdigits" => $this->i18n->translate('How many digits are allowed to user input.'),
          "var_name" => $this->i18n->translate('Give a name for this user input.'),
          "allow_exten_dial" => $this->i18n->translate('Allow forward to an Extension'),
          "wait_time" => $this->i18n->translate('Wait for how long between each digit - in seconds'),
          "forward_call" => $this->i18n->translate('Forward call to the User Input destination'),
          "goto" => $this->i18n->translate('If informed Digits is not expected, go to action ID')
        );
        return <<<XML
<params>
    <audio>
        <label>{$menu['audio_file']}</label>
        <id>file</id>
        $file
    </audio>
    <int>
    	<id>maxdigits</id>
    	<default>10</default>
    	<label>{$menu['maxdigits']}</label>
	$maxdigits
    </int>
    <int>
        <label>{$menu['wait_time']}</label>
        <id>timeout</id>
        <default>2</default>
        $timeout
    </int>
    <string>
      <id>var_name</id>
      <default>userinput</default>
      <label>{$menu['var_name']}</label>
      $var_name
    </string>
    <boolean>
      <id>forward_call</id>
      <default>false</default>
      <label>{$menu['forward_call']}</label>
       $forward_call
    </boolean>
</params>
XML;
    }



    /**
     * Run the action. It is called inside the SNEP AGI.
     *
     * @param Asterisk_AGI $asterisk
     * @param Asterisk_AGI_Request $request
     */
    public function execute($asterisk, $request) {
        $log = Zend_Registry::get('log');
    		$this->log = $log;
    		$db = Zend_Registry::get("db");

        $log->info("Answering the call at UserInteraction action");
        $asterisk->answer();

        // $userinput = array();
        $already_input = $asterisk->get_variable("CUSTOM_NOTIFICATION");
        $tt = serialize($already_input);
        $log->info("Already userinput: {$tt}");
        if($already_input['data']){
          $userinput = "{$already_input['data']}&";
        }
        $maxdigits = $this->config['maxdigits'];
        $userinput_row = $asterisk->get_data($this->config['file'],$this->config['timeout']*1000, $maxdigits);
        $input_count = strlen($userinput_row['result']);
        if($input_count > 0){
          $userinput .= "{$this->config['var_name']}={$userinput_row['result']}";
          $asterisk->exec("Set","CUSTOM_NOTIFICATION=$userinput");
          $log->info("User inserted $input_count digits: [{$userinput_row['result']}]");
        }else{
          $log->info("User insert nothing");
        }

        $log->debug("Result code [{$userinput_row['code']}] and status [{$userinput_row['data']}] and forward_call [{$this->config['forward_call']}]");

        if($this->config['forward_call'] == "true"){

          $log->info("Forward Call: {$this->config['forward_call']} -> Going to extension: {$userinput_row['result']}");

          $asterisk->exec_goto('default',$userinput_row['result'],1);
          break;

        }else{
          $log->info("User inserted a set of digits. Going to the next action");
          // break;
        }


      }

}
