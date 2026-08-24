ALTER TABLE `peers` ADD COLUMN `useragent` VARCHAR(250) DEFAULT NULL;
ALTER TABLE `queues` ADD COLUMN `ringinuse` BOOL NOT NULL DEFAULT '1';

INSERT INTO `core_config` (`config_module`, `config_name`, `config_value`) VALUES ("default","userfield","TS_AAMMDD_HHii_SR_DS"),("default","userfield_ud","");

UPDATE `core_config` set `config_module`= 'default' WHERE `config_module`= 'CORE' ;
UPDATE `core_config` set `config_name`= 'host_notification' WHERE `config_name`= 'HOST_NOTIFICATION' AND `config_module`= 'default';
UPDATE `core_config` set `config_name`= 'last_id_notification' WHERE `config_name`= 'LAST_ID_NOTIFICATION' AND `config_module`= 'default' ;
