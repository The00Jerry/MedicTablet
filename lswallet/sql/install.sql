-- =====================================================================
--  City of Los Santos – Department of Licensing & Identification (Wallet)
--  Installationsdatei (MySQL/MariaDB, oxmysql). Prefix lw_ , InnoDB, utf8mb4.
--  Karten dauerhaft ueber permanenten Charakter-Identifier verknuepft.
-- =====================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- Karten (Ausweise, Fuehrerscheine, Visitenkarten, Tickets, Coupons)
CREATE TABLE IF NOT EXISTS `lw_cards` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `identifier`  VARCHAR(64)  NOT NULL,
  `ctype`       VARCHAR(24)  NOT NULL,              -- national_id|driver_license|business_card|ticket|coupon
  `template_key` VARCHAR(48) NOT NULL DEFAULT '',
  `title`       VARCHAR(120) NOT NULL DEFAULT '',
  `data`        LONGTEXT     NULL,                  -- JSON: Feldwerte (Snapshot)
  `photo_url`   VARCHAR(255) NOT NULL DEFAULT '',
  `serial`      VARCHAR(40)  NOT NULL,
  `issued_by`   VARCHAR(64)  NOT NULL DEFAULT '',
  `issued_by_name` VARCHAR(96) NOT NULL DEFAULT '',
  `issued_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expires_at`  DATETIME     NULL DEFAULT NULL,
  `revoked`     TINYINT(1)   NOT NULL DEFAULT 0,
  `revoked_by`  VARCHAR(64)  NOT NULL DEFAULT '',
  `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_card_serial` (`serial`),
  KEY `idx_card_ident` (`identifier`),
  KEY `idx_card_type` (`ctype`),
  KEY `idx_card_revoked` (`revoked`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Vorlagen
CREATE TABLE IF NOT EXISTS `lw_templates` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `tkey`       VARCHAR(48)  NOT NULL,
  `ctype`      VARCHAR(24)  NOT NULL,
  `label`      VARCHAR(120) NOT NULL,
  `config`     LONGTEXT     NULL,                   -- JSON
  `created_by` VARCHAR(64)  NOT NULL DEFAULT '',
  `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_tpl_key` (`tkey`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Antraege (z.B. Fuehrerschein) mit Autorisierung
CREATE TABLE IF NOT EXISTS `lw_applications` (
  `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `identifier`   VARCHAR(64)  NOT NULL,
  `applicant_name` VARCHAR(96) NOT NULL DEFAULT '',
  `atype`        VARCHAR(24)  NOT NULL,             -- template_key des Antrags
  `payload`      LONGTEXT     NULL,                 -- JSON (z.B. gewuenschte Klasse)
  `status`       VARCHAR(16)  NOT NULL DEFAULT 'pending', -- pending|approved|denied
  `reviewer_identifier` VARCHAR(64) NOT NULL DEFAULT '',
  `reviewer_name` VARCHAR(96) NOT NULL DEFAULT '',
  `note`         VARCHAR(255) NOT NULL DEFAULT '',
  `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `decided_at`   DATETIME     NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_app_ident` (`identifier`),
  KEY `idx_app_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Berechtigungen (Verwaltungsaktionen)
CREATE TABLE IF NOT EXISTS `lw_permissions` (
  `id`    INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `job`   VARCHAR(64)  NOT NULL,
  `grade` INT          NOT NULL,
  `perm`  VARCHAR(64)  NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_lwperm` (`job`, `grade`, `perm`),
  KEY `idx_lwperm_job` (`job`, `grade`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `lw_permission_overrides` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `identifier` VARCHAR(64)  NOT NULL,
  `perm`       VARCHAR(64)  NOT NULL,
  `allow`      TINYINT(1)   NOT NULL DEFAULT 1,
  `created_by` VARCHAR(64)  NOT NULL DEFAULT '',
  `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_lwoverride` (`identifier`, `perm`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Einstellungen
CREATE TABLE IF NOT EXISTS `lw_settings` (
  `skey`       VARCHAR(96)  NOT NULL,
  `svalue`     LONGTEXT     NULL,
  `updated_by` VARCHAR(64)  NOT NULL DEFAULT '',
  `updated_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`skey`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Audit-Log
CREATE TABLE IF NOT EXISTS `lw_audit_log` (
  `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `actor_identifier` VARCHAR(64) NOT NULL DEFAULT '',
  `actor_name`  VARCHAR(96)  NOT NULL DEFAULT '',
  `discord_id`  VARCHAR(32)  NOT NULL DEFAULT '',
  `category`    VARCHAR(32)  NOT NULL DEFAULT 'default',
  `action`      VARCHAR(64)  NOT NULL,
  `target_type` VARCHAR(32)  NOT NULL DEFAULT '',
  `target_id`   VARCHAR(64)  NOT NULL DEFAULT '',
  `old_value`   LONGTEXT     NULL,
  `new_value`   LONGTEXT     NULL,
  `reason`      VARCHAR(255) NOT NULL DEFAULT '',
  `result`      VARCHAR(16)  NOT NULL DEFAULT 'ok',
  `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_lwaudit_actor` (`actor_identifier`),
  KEY `idx_lwaudit_action` (`action`),
  KEY `idx_lwaudit_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;

-- Vorlagen & Berechtigungen werden beim ersten Ressourcenstart aus den Config-Dateien
-- geseedet, sofern die Tabellen leer sind.
