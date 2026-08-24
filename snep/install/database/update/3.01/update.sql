--
-- Table structure for table `core_config`
--
CREATE TABLE IF NOT EXISTS `core_config` (
	`id` INTEGER PRIMARY KEY AUTO_INCREMENT,
    `config_module` VARCHAR (255) NOT NULL,
    `config_name` VARCHAR (255) NOT NULL,
    `config_value` VARCHAR(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

ALTER TABLE `regras_negocio` ADD COLUMN `type` ENUM('incoming','outgoing','others') NOT NULL DEFAULT 'others' ;

ALTER TABLE `core_notifications` ADD COLUMN `id_itc` INT(11) DEFAULT 1;
ALTER TABLE `core_notifications` ADD COLUMN `from` VARCHAR(128) DEFAULT "Opens";
INSERT INTO `core_config` (`config_module`, `config_name`, `config_value`) VALUES ('default', 'host_notification', 'http://api.opens.com.br:3003/notifications');
