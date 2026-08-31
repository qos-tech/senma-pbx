<?php

// silenciando strict até arrumar zend_locale
// date_default_timezone_set("America/Sao_Paulo");

$config_file = "../../../includes/setup.conf";

//encontrado diretórios do sistema
if (!file_exists($config_file)) {
    die("FATAL ERROR: arquivo $config_file nao encontrado");
};
$config = parse_ini_file($config_file, true);

error_reporting(E_ERROR | E_WARNING | E_PARSE);

// Adicionando caminho de libs ao include path para autoloader trabalhar:
set_include_path($config['system']['path.base'] . "/lib" . PATH_SEPARATOR . get_include_path());
$logdir = $config['system']['path.log'];
unset($config);
// iniciando auto loader
require_once "Zend/Loader/Autoloader.php";
$autoloader = Zend_Loader_Autoloader::getInstance();


// Registrando namespaces para as outras bibliotecas
$autoloader->registerNamespace('Snep_');
$autoloader->registerNamespace('PBX_');
$autoloader->registerNamespace('Asterisk_');

// Carregando arquivo de configuração do snep e alocando as informações
// no registro do Zend.
$config = new Zend_Config_Ini($config_file);
$debug = (boolean) $config->system->debug;
Zend_Registry::set('configFile', $config_file);
Zend_Registry::set('config', $config);



// Iniciando sistema de logs
$log = new Zend_Log();
Zend_Registry::set('log', $log);

// Definindo aonde serão escritos os logs
$writer = new Zend_Log_Writer_Stream($logdir . '/ui.log');
// Filtramos a 'sujeira' dos logs se não estamos em debug mode.
if (!$debug) {
    $filter = new Zend_Log_Filter_Priority(Zend_Log::WARN);
    $writer->addFilter($filter);
} else {
    ini_set('display_errors', 1);
    ini_set('display_startup_errors', 1);
}
$log->addWriter($writer);

// Iniciando banco de dados
$db = Zend_Db::factory('Pdo_Mysql', $config->ambiente->db->toArray());
Zend_Db_Table::setDefaultAdapter($db);
Zend_Registry::set('db', $db);
//unset($db);

// require_once(dirname(__FILE__) . "/actions/SnepService.php");

/**
 * Função para  os erros
 * @param Causa do erro, "mensagem que será impressa"
 * @param tipo do erro, fatal usa die, normal usa echo
 */
function error($cause) {
    die('{"status":"error","cause":"' . $cause . '"}');
}

/**
 * TASK-0026F (F17-A): single Basic-auth parsing path. Both server-variable
 * shapes a deployment may populate (HTTP_AUTHORIZATION vs PHP_AUTH_USER/
 * PHP_AUTH_PW) are normalized here into one (username, plaintext-password)
 * pair *before* any hashing, so there is exactly one place downstream that
 * turns a password into its stored representation. Returns array(null, null)
 * when no usable credentials were supplied.
 */
function resolveApiCredentials() {
    if (isset($_SERVER['HTTP_AUTHORIZATION'])) {
        if (stripos($_SERVER['HTTP_AUTHORIZATION'], 'basic') === 0) {
            $decoded = base64_decode(substr($_SERVER['HTTP_AUTHORIZATION'], 6), true);
            if ($decoded !== false && strpos($decoded, ':') !== false) {
                list($httpAuthUser, $httpAuthPasswd) = explode(':', $decoded, 2);
                return array($httpAuthUser, $httpAuthPasswd);
            }
        }
        return array(null, null);
    }

    if (isset($_SERVER['PHP_AUTH_USER'])) {
        return array($_SERVER['PHP_AUTH_USER'], (string) $_SERVER['PHP_AUTH_PW']);
    }

    return array(null, null);
}

list($apiUser, $apiPlainPasswd) = resolveApiCredentials();

if ($apiUser && $apiPlainPasswd) {
    // TASK-0026F: current compatibility -- plaintext credential -> md5 ->
    // compare against the stored MD5 hash in users.password, applied here
    // exactly once. This mirrors AuthController::loginAction()'s existing
    // convention and is deliberately NOT modernized to password_hash()/
    // password_verify() in this task; see docs/tasks/0026f-... for the
    // deferred password-hashing modernization boundary.
    $authAdapter = new Zend_Auth_Adapter_DbTable($db);
    $authAdapter->setTableName('users');
    $authAdapter->setIdentityColumn('name');
    $authAdapter->setCredentialColumn('password');
    $authAdapter->setIdentity($apiUser);
    $authAdapter->setCredential(md5($apiPlainPasswd));

    // Autentication
    $auth = Zend_Auth::getInstance();
    $result = $auth->authenticate($authAdapter);
    if ($result->getCode() !== Zend_Auth_Result::SUCCESS) {
        error("User or password invalid");
    }

    require_once(dirname(__FILE__) . "/actions/SnepService.php");

    // TASK-0026F (F17-B): finite, trusted registry of service name ->
    // filename. $_GET['service'] only ever selects a key into this array --
    // it is never concatenated into a filesystem path, so no request value
    // can reach require_once() with an unexpected path, even after
    // validation. Unknown services fail closed.
    $serviceRegistry = array(
        'CallsReport'    => 'CallsReportService.php',
        'Contacts'       => 'ContactsService.php',
        'CSV_ExportData' => 'CSV_ExportDataService.php',
        'CSV_GetParams'  => 'CSV_GetParamsService.php',
        'RankingReport'  => 'RankingReportService.php',
        'ServicesReport' => 'ServicesReportService.php',
    );

    $requestedService = isset($_GET['service']) ? $_GET['service'] : 'CallsReport';

    if (!is_string($requestedService) || !array_key_exists($requestedService, $serviceRegistry)) {
        error("Servico nao encontrado");
    }

    $service_name = $requestedService . "Service";
    require_once(dirname(__FILE__) . "/actions/" . $serviceRegistry[$requestedService]);

    // Carrega o serviç
    $service = new $service_name;
    // Executa o serviço
    $resultado = $service->execute();

    // Seta o HTTP header de conteudo de resposta para application/json
    header('Content-Type: application/json');

    // // Imprime resultado
    if (isset($_GET['service']) && $_GET['service'] == "CallsReport") {
        echo str_replace('\\/', '/', json_encode($resultado));
    } else {
        echo json_encode($resultado);
    }
} else {
    header('WWW-Authenticate: Basic realm="SNEP Services"');
    header('HTTP/1.0 401 Unauthorized');
    error("Unauthorized!");
}
