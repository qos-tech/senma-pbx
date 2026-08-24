 
CREATE TABLE `core_groups` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `name` varchar(50) NOT NULL,
     PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO `core_groups` (`name`) VALUES ('Default'); 

CREATE TABLE `core_peer_groups` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `peer_id` int(11) NOT NULL,
    `group_id` int(11) NOT NULL,
    PRIMARY KEY (`id`),
    KEY `group_id` (`group_id`),
    KEY `peer_id` (`peer_id`),
    CONSTRAINT `core_peer_groups_ibfk_1` FOREIGN KEY (`group_id`) REFERENCES `core_groups` (`id`) ON DELETE CASCADE,
    CONSTRAINT `core_peer_groups_ibfk_2` FOREIGN KEY (`peer_id`) REFERENCES `peers` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8  ;

