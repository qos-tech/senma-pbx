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
class IVR extends PBX_Rule_Action {

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
        return $this->i18n->translate("IVR");
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
        $prefix = (isset($this->config['prefix']))?"<value>{$this->config['prefix']}</value>":"";
        $timeout = (isset($this->config['timeout']))?"<value>{$this->config['timeout']}</value>":"10";
        $digits = (isset($this->config['digits']))?"<value>{$this->config['digits']}</value>":"4";
        $wrongaction = (isset($this->config['wrongaction']))?"<value>{$this->config['wrongaction']}</value>":"0";
        $wloops = (isset($this->config['wloops']))?"<value>{$this->config['wloops']}</value>":"1";

        $menu = array(
          "audio_file" => $this->i18n->translate('Menu Audio File'),
          "maxdigits" => $this->i18n->translate('How many digits are allowed to user input.'),
          "allow_exten_dial" => $this->i18n->translate('Allow forward to an Extension'),
          "prefix" => $this->i18n->translate('IVR Prefix - used to identify the next steps on IVR process. You will need a Route with this destiny + the user input: PREFIX-USER_INPUT'),
          "wait_time" => $this->i18n->translate('Wait for how long between each digit - in seconds'),
          "wait_digits" => $this->i18n->translate('What menu digits options are allowed - split by ","'),
          "goto" => $this->i18n->translate('If informed Digits is not expected, go to action ID'),
          "loops" => $this->i18n->translate('How many loops')
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
    	<default>1</default>
    	<label>{$menu['maxdigits']}</label>
	$maxdigits
    </int>
    <string>
        <label>{$menu['prefix']}</label>
        <id>prefix</id>
        <default></default>
        $prefix
    </string>
    <boolean>
    	<id>allow_exten_dial</id>
    	<default>false</default>
    	<label>{$menu['allow_exten_dial']}</label>
	     $allow_exten_dial
    </boolean>
    <int>
        <label>{$menu['wait_time']}</label>
        <id>timeout</id>
        <default>2</default>
        $timeout
    </int>
    <string>
        <label>{$menu['wait_digits']}</label>
        <id>digits</id>
        <default>1,2,3</default>
        $digits
    </string>
    <int>
        <label>{$menu['goto']}</label>
        <id>wrongaction</id>
        <default>1</default>
        $wrongaction
    </int>
    <int>
        <label>{$menu['loops']}</label>
        <id>wloops</id>
        <default>3</default>
        $wloops
    </int>
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

    		$stop_flow = false;
        $valid = false;

    		$db = Zend_Registry::get("db");

        $log->info("Answering the at IVR");
        $asterisk->answer();

  			if($stop_flow == true){
  				$asterisk->hangup();
  			}

        $loop = $this->config['wloops'];
        $digits = explode(",",$this->config['digits']);
        if($this->config['prefix']){
          $prefix = $this->config['prefix'] . '-';
        }else{
          $prefix = "";
        }

        if($this->config['allow_exten_dial'] == "true"){
          $conf = Zend_Registry::get('config');
          $peer_digits = $conf->canais->peers_digits;
        }

        $maxdigits = $this->config['maxdigits'];

        $log->info("Waiting for $maxdigits digits in: {$this->config['digits']} and {$this->config['allow_exten_dial']}");

        while($loop > 0){
          $interaction++;
          $userinput_row = $asterisk->get_data($this->config['file'],$this->config['timeout']*1000, $maxdigits);
          $userinput = $userinput_row['result'];
          $asterisk->exec("Set","__USERINPUT=$userinput");
          $input_count = strlen($userinput);
          $log->info("User inserted $input_count digits: [{$userinput}] in the [$interaction] interaction.");
          $log->debug("Result code [{$userinput_row['code']}] and status [{$userinput_row['data']}]");
          if($input_count == 1 && in_array($userinput, $digits)){
            $log->info("User inserted a single digit in the menu option. Redirecting call to option $userinput");
            $asterisk->exec_goto('default',$prefix . $userinput,1);
            throw new PBX_Rule_Action_Exception_StopExecution("End of this IVR step");
            break;
          }elseif ($this->config['allow_exten_dial'] == "true" && $peer_digits == $input_count) {
            $log->info("User inserted a extension digit. Redirecting call to Extension $userinput");
            $asterisk->exec_goto('default', $userinput, 1);
            throw new PBX_Rule_Action_Exception_StopExecution("End of this IVR step");
            break;
          }elseif($this->config['maxdigits'] <= $input_count){
            $log->info("User inserted a set of digits. Going to the next action");
            $valid = true;
            break;
          }

          $loop--;
        }

        $log->debug("Testing wrongaction and valid input: [{$this->config['wrongaction']}] [$valid]");
        if(isset($this->config['wrongaction']) && !$valid){

          $log->info("Going to wrong option: {$this->config['wrongaction']}");

          throw new PBX_Rule_Action_Exception_GoTo($this->config['wrongaction'] - 1);

        }


      }

}
