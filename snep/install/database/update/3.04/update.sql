--
-- Table structure for table `users_queues_permissions`
--
CREATE TABLE IF NOT EXISTS `users_queues_permissions` (
  `id` integer NOT NULL auto_increment,
  `user_id` int(11) NOT NULL,
  `queue_id` int(11) NOT NULL,
  PRIMARY KEY  (`id`),
  CONSTRAINT `fk_id_user_p` FOREIGN KEY (`user_id` ) REFERENCES `users` (`id`),
  CONSTRAINT `fk_id_queue_p` FOREIGN KEY (`queue_id` ) REFERENCES `queues` (`id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8;

--
-- Table structure for table `core_binds_exceptions`
--
CREATE TABLE IF NOT EXISTS `core_binds_exceptions` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `exception` text NOT NULL,
  `created` datetime NOT NULL,
  `updated` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `user_id` (`user_id`),
  CONSTRAINT `binds_peer_refs_user_id_exception` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;