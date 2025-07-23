CREATE TABLE IF NOT EXISTS `player_chests` (
  `chest_uuid` varchar(50) NOT NULL,
  `owner` varchar(50) NOT NULL,
  `coords` text NOT NULL,
  `heading` float NOT NULL DEFAULT 0,
  `model` varchar(50) NOT NULL DEFAULT 'p_chest01x',
  `custom_name` varchar(100) DEFAULT NULL,
  `items` text DEFAULT NULL,
  `tier` tinyint(4) DEFAULT NULL,
  `max_weight` float DEFAULT NULL,
  `max_slots` int(11) DEFAULT NULL,
  `shared_with` text DEFAULT NULL,
  `logs` text DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`chest_uuid`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;


CREATE TABLE IF NOT EXISTS `player_chests_logs` (
  `log_id` int(11) NOT NULL AUTO_INCREMENT,
  `chest_uuid` varchar(50) NOT NULL,
  `actor_citizenid` varchar(60) NOT NULL,
  `action_type` varchar(50) NOT NULL,
  `target_citizenid` varchar(60) DEFAULT NULL,
  `details` text DEFAULT NULL,
  `timestamp` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`log_id`)
) ENGINE=InnoDB AUTO_INCREMENT=75 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
