CREATE TABLE IF NOT EXISTS `telcos` (
  `id` int(10) NOT NULL AUTO_INCREMENT,
  `created` datetime NOT NULL,
  `name` varchar(35) NOT NULL,
  `mobile_price` varchar(10) NOT NULL,
  `landline_price` varchar(10) NOT NULL,
  `start_time` varchar(2) NOT NULL,
  `fract` varchar(10) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `billing_types` (
  `id` int(10) NOT NULL AUTO_INCREMENT,
  `name` varchar(20) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO `billing_types` (`name`) VALUES ('Mobile');
INSERT INTO `billing_types` (`name`) VALUES ('Land Line');

CREATE TABLE IF NOT EXISTS `billing` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `created` datetime NOT NULL,
  `area` varchar(10),
  `type` INT(10) NOT NULL,
  `price` varchar(10) NOT NULL,
  `telco` int(10) NOT NULL,
  PRIMARY KEY (`id`),
  FOREIGN KEY (`telco`) REFERENCES telcos(`id`) ON DELETE CASCADE,
  FOREIGN KEY (`type`) REFERENCES billing_types(`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `rated_calls` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `date` datetime NOT NULL,
  `uniqueid` varchar(40) NOT NULL,
  `userfield` varchar(100),
  `price` varchar(10) NOT NULL DEFAULT '0,00',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
