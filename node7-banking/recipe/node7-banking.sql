CREATE TABLE IF NOT EXISTS `node7_bank_transactions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `citizenid` varchar(50) NOT NULL,
  `account_number` varchar(64) NOT NULL DEFAULT '',
  `transaction_type` varchar(32) NOT NULL,
  `amount` decimal(18,2) NOT NULL DEFAULT 0.00,
  `balance_after` decimal(18,2) NOT NULL DEFAULT 0.00,
  `description` varchar(255) NOT NULL DEFAULT '',
  `counterparty` varchar(128) NOT NULL DEFAULT '',
  `reference` varchar(64) NOT NULL DEFAULT '',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_node7_bank_tx_citizenid` (`citizenid`),
  KEY `idx_node7_bank_tx_account` (`account_number`),
  KEY `idx_node7_bank_tx_reference` (`reference`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `node7_bank_accounts` (
  `account_name` varchar(64) NOT NULL,
  `account_number` varchar(32) NOT NULL DEFAULT '',
  `label` varchar(128) NOT NULL,
  `account_type` varchar(32) NOT NULL DEFAULT 'society',
  `owner_citizenid` varchar(50) NOT NULL DEFAULT '',
  `balance` decimal(18,2) NOT NULL DEFAULT 0.00,
  `frozen` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`account_name`),
  UNIQUE KEY `idx_node7_shared_number` (`account_number`),
  KEY `idx_node7_shared_owner` (`owner_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `node7_bank_account_members` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `account_name` varchar(64) NOT NULL,
  `citizenid` varchar(50) NOT NULL,
  `member_name` varchar(128) NOT NULL DEFAULT '',
  `role` varchar(24) NOT NULL DEFAULT 'member',
  `can_deposit` tinyint(1) NOT NULL DEFAULT 1,
  `can_withdraw` tinyint(1) NOT NULL DEFAULT 0,
  `can_transfer` tinyint(1) NOT NULL DEFAULT 0,
  `can_manage` tinyint(1) NOT NULL DEFAULT 0,
  `created_by` varchar(50) NOT NULL DEFAULT '',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_node7_bank_member` (`account_name`,`citizenid`),
  KEY `idx_node7_bank_member_citizen` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `node7_bank_account_transactions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `account_name` varchar(64) NOT NULL,
  `transaction_type` varchar(32) NOT NULL,
  `amount` decimal(18,2) NOT NULL DEFAULT 0.00,
  `balance_after` decimal(18,2) NOT NULL DEFAULT 0.00,
  `description` varchar(255) NOT NULL DEFAULT '',
  `actor_citizenid` varchar(50) NOT NULL DEFAULT '',
  `actor_name` varchar(128) NOT NULL DEFAULT '',
  `counterparty` varchar(128) NOT NULL DEFAULT '',
  `reference` varchar(64) NOT NULL DEFAULT '',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_node7_shared_tx_account` (`account_name`),
  KEY `idx_node7_shared_tx_reference` (`reference`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Existing installations are migrated automatically by server/main.lua.

-- Upgrade path for older NODE7 banking account tables.
ALTER TABLE `node7_bank_accounts` ADD COLUMN IF NOT EXISTS `account_name` varchar(64) NOT NULL DEFAULT '';
ALTER TABLE `node7_bank_accounts` ADD COLUMN IF NOT EXISTS `account_number` varchar(32) NOT NULL DEFAULT '';
ALTER TABLE `node7_bank_accounts` ADD COLUMN IF NOT EXISTS `label` varchar(128) NOT NULL DEFAULT '';
ALTER TABLE `node7_bank_accounts` ADD COLUMN IF NOT EXISTS `account_type` varchar(32) NOT NULL DEFAULT 'society';
ALTER TABLE `node7_bank_accounts` ADD COLUMN IF NOT EXISTS `owner_citizenid` varchar(50) NOT NULL DEFAULT '';
ALTER TABLE `node7_bank_accounts` ADD COLUMN IF NOT EXISTS `balance` decimal(18,2) NOT NULL DEFAULT 0.00;
ALTER TABLE `node7_bank_accounts` ADD COLUMN IF NOT EXISTS `frozen` tinyint(1) NOT NULL DEFAULT 0;
ALTER TABLE `node7_bank_accounts` ADD COLUMN IF NOT EXISTS `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE `node7_bank_accounts` ADD COLUMN IF NOT EXISTS `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP;

UPDATE `node7_bank_accounts`
SET `label` = `account_name`
WHERE `label` IS NULL OR `label` = '';

ALTER TABLE `node7_bank_account_transactions` ADD COLUMN IF NOT EXISTS `account_name` varchar(64) NOT NULL DEFAULT '';
ALTER TABLE `node7_bank_account_transactions` ADD COLUMN IF NOT EXISTS `transaction_type` varchar(32) NOT NULL DEFAULT 'unknown';
ALTER TABLE `node7_bank_account_transactions` ADD COLUMN IF NOT EXISTS `amount` decimal(18,2) NOT NULL DEFAULT 0.00;
ALTER TABLE `node7_bank_account_transactions` ADD COLUMN IF NOT EXISTS `balance_after` decimal(18,2) NOT NULL DEFAULT 0.00;
ALTER TABLE `node7_bank_account_transactions` ADD COLUMN IF NOT EXISTS `description` varchar(255) NOT NULL DEFAULT '';
ALTER TABLE `node7_bank_account_transactions` ADD COLUMN IF NOT EXISTS `actor_citizenid` varchar(50) NOT NULL DEFAULT '';
ALTER TABLE `node7_bank_account_transactions` ADD COLUMN IF NOT EXISTS `actor_name` varchar(128) NOT NULL DEFAULT '';
ALTER TABLE `node7_bank_account_transactions` ADD COLUMN IF NOT EXISTS `counterparty` varchar(128) NOT NULL DEFAULT '';
ALTER TABLE `node7_bank_account_transactions` ADD COLUMN IF NOT EXISTS `reference` varchar(64) NOT NULL DEFAULT '';
ALTER TABLE `node7_bank_account_transactions` ADD COLUMN IF NOT EXISTS `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP;
