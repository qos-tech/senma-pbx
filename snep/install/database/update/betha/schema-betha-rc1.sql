-- Update SNEP Alpha -> Betha e Asterisk 12 -> 13
ALTER TABLE  `peers` CHANGE  `ipaddr` `ipaddr` VARCHAR(45);
ALTER TABLE  `peers` CHANGE  `username` `defaultuser` VARCHAR(80);
ALTER TABLE  `peers` CHANGE  `regserver` `regserver` VARCHAR(20);
ALTER TABLE  `peers` CHANGE `nat` `nat` VARCHAR(100) NOT NULL;
ALTER TABLE  `voicemail_users` CHANGE  `password`  `password` VARCHAR(10);
ALTER TABLE  `queue_members` CHANGE  `paused`  `paused` INT(2);
ALTER TABLE  `peers` CHANGE  `nat`  `nat` VARCHAR(16);
ALTER TABLE  `contacts_group` CHANGE `name` `name` VARCHAR(50) NOT NULL;
ALTER TABLE  `sounds` DROP PRIMARY KEY, ADD PRIMARY KEY (`arquivo`,`tipo`,`secao`,`language`);


