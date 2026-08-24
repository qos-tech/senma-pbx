INSERT INTO `core_config` (`config_module`, `config_name`, `config_value`) VALUES ('default','update_server','http://api.opens.com.br/snep');
UPDATE `core_config` SET `config_value`='http://api.opens.com.br/v2/notifications' WHERE `config_name`='host_notification' AND `config_module`='default';
UPDATE `core_config` SET `config_value`='http://api.opens.com.br/inspect' WHERE `config_name`='host_inspect' AND `config_module`='default';
