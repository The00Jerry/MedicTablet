-- =====================================================================
--  SunLife Roleplay – LSPD Police-Tablet (MDT)
--  Vollstaendige Installationsdatei (MySQL/MariaDB, oxmysql)
--
--  Konventionen:
--    * Prefix pd_ , InnoDB, utf8mb4.
--    * Personen dauerhaft ueber permanenten Charakter-Identifier (VARCHAR 64).
--    * Anzeigen speichern Delikte/Betraege als Snapshot -> alte Faelle stabil.
--    * Idempotenz: Anzeigen ueber idempotency_key.
--    * Loeschen durch Archivierung vermeiden.
-- =====================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- Personenakte
CREATE TABLE IF NOT EXISTS `pd_citizens` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `identifier`  VARCHAR(64)  NOT NULL,
  `char_id`     INT UNSIGNED NULL,
  `firstname`   VARCHAR(64)  NOT NULL DEFAULT '',
  `lastname`    VARCHAR(64)  NOT NULL DEFAULT '',
  `dateofbirth` VARCHAR(32)  NOT NULL DEFAULT '',
  `sex`         VARCHAR(16)  NOT NULL DEFAULT '',
  `phone`       VARCHAR(32)  NOT NULL DEFAULT '',
  `fingerprint` VARCHAR(32)  NOT NULL DEFAULT '',          -- stabiler Fingerabdruck-Code
  `mugshot_url` VARCHAR(255) NOT NULL DEFAULT '',
  `licenses`    TEXT         NULL,                          -- JSON { driver:true, weapon:false, ... }
  `flags`       TEXT         NULL,                          -- JSON Freitext-Flags
  `notes`       TEXT         NULL,                          -- allg. (nicht sensible) Hinweise
  `is_wanted`   TINYINT(1)   NOT NULL DEFAULT 0,            -- Cache: aktive Fahndung?
  `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_citizen_identifier` (`identifier`),
  UNIQUE KEY `uq_citizen_fp` (`fingerprint`),
  KEY `idx_citizen_name` (`lastname`, `firstname`),
  KEY `idx_citizen_phone` (`phone`),
  KEY `idx_citizen_wanted` (`is_wanted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Fahndung / BOLO
CREATE TABLE IF NOT EXISTS `pd_wanted` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `citizen_id`  INT UNSIGNED NOT NULL,
  `identifier`  VARCHAR(64)  NOT NULL,
  `reason`      VARCHAR(512) NOT NULL DEFAULT '',
  `level`       VARCHAR(16)  NOT NULL DEFAULT 'medium',     -- low|medium|high
  `officer_identifier` VARCHAR(64) NOT NULL DEFAULT '',
  `officer_name` VARCHAR(96) NOT NULL DEFAULT '',
  `status`      VARCHAR(16)  NOT NULL DEFAULT 'active',      -- active|cleared
  `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `cleared_at`  DATETIME     NULL DEFAULT NULL,
  `cleared_by`  VARCHAR(64)  NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `idx_wanted_citizen` (`citizen_id`),
  KEY `idx_wanted_status` (`status`),
  CONSTRAINT `fk_wanted_citizen` FOREIGN KEY (`citizen_id`)
    REFERENCES `pd_citizens` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Strafenkatalog
CREATE TABLE IF NOT EXISTS `pd_penal_categories` (
  `id`       INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `cat_key`  VARCHAR(64)  NOT NULL,
  `label`    VARCHAR(128) NOT NULL,
  `sort`     INT          NOT NULL DEFAULT 0,
  `archived_at` DATETIME  NULL DEFAULT NULL,
  `created_at` DATETIME   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_pcat_key` (`cat_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pd_penal_offenses` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `code`        VARCHAR(16)  NOT NULL,
  `label`       VARCHAR(160) NOT NULL,
  `description` VARCHAR(512) NOT NULL DEFAULT '',
  `category_id` INT UNSIGNED NULL,
  `fine`        INT UNSIGNED NOT NULL DEFAULT 0,             -- Bussgeld ($)
  `jail`        INT UNSIGNED NOT NULL DEFAULT 0,             -- Haft (Monate)
  `points`      INT UNSIGNED NOT NULL DEFAULT 0,             -- Fuehrerscheinpunkte
  `active`      TINYINT(1)   NOT NULL DEFAULT 1,
  `required_perm` VARCHAR(64) NOT NULL DEFAULT '',
  `created_by`  VARCHAR(64)  NOT NULL DEFAULT '',
  `updated_by`  VARCHAR(64)  NOT NULL DEFAULT '',
  `archived_at` DATETIME     NULL DEFAULT NULL,
  `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_offense_code` (`code`),
  KEY `idx_offense_cat` (`category_id`),
  CONSTRAINT `fk_offense_cat` FOREIGN KEY (`category_id`)
    REFERENCES `pd_penal_categories` (`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Anzeigen / Bussgelder (Snapshot)
CREATE TABLE IF NOT EXISTS `pd_charges` (
  `id`              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `charge_no`       VARCHAR(32)  NOT NULL,
  `idempotency_key` VARCHAR(64)  NOT NULL,
  `citizen_id`      INT UNSIGNED NOT NULL,
  `identifier`      VARCHAR(64)  NOT NULL,
  `officer_identifier` VARCHAR(64) NOT NULL DEFAULT '',
  `officer_name`    VARCHAR(96)  NOT NULL DEFAULT '',
  `report_id`       INT UNSIGNED NULL,
  `fine_total`      INT          NOT NULL DEFAULT 0,
  `jail_total`      INT          NOT NULL DEFAULT 0,
  `points_total`    INT          NOT NULL DEFAULT 0,
  `reason`          VARCHAR(255) NOT NULL DEFAULT '',
  `provider`        VARCHAR(16)  NOT NULL DEFAULT '',
  `provider_invoice_id` VARCHAR(64) NULL,
  `status`          VARCHAR(16)  NOT NULL DEFAULT 'pending',  -- pending|issued|cancelled|failed
  `error`           VARCHAR(255) NOT NULL DEFAULT '',
  `created_at`      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_charge_no` (`charge_no`),
  UNIQUE KEY `uq_charge_idem` (`idempotency_key`),
  KEY `idx_charge_citizen` (`citizen_id`),
  KEY `idx_charge_status` (`status`),
  CONSTRAINT `fk_charge_citizen` FOREIGN KEY (`citizen_id`)
    REFERENCES `pd_citizens` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pd_charge_items` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `charge_id`  INT UNSIGNED NOT NULL,
  `code`       VARCHAR(16)  NOT NULL,
  `label`      VARCHAR(160) NOT NULL,
  `fine`       INT UNSIGNED NOT NULL DEFAULT 0,
  `jail`       INT UNSIGNED NOT NULL DEFAULT 0,
  `points`     INT UNSIGNED NOT NULL DEFAULT 0,
  `quantity`   INT UNSIGNED NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  KEY `idx_citem_charge` (`charge_id`),
  CONSTRAINT `fk_citem_charge` FOREIGN KEY (`charge_id`)
    REFERENCES `pd_charges` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Berichte / Faelle
CREATE TABLE IF NOT EXISTS `pd_reports` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `report_no`   VARCHAR(32)  NOT NULL,
  `title`       VARCHAR(200) NOT NULL DEFAULT '',
  `type`        VARCHAR(32)  NOT NULL DEFAULT 'incident',    -- incident|arrest|traffic|investigation
  `officer_identifier` VARCHAR(64) NOT NULL DEFAULT '',
  `officer_name` VARCHAR(96) NOT NULL DEFAULT '',
  `body`        TEXT         NULL,
  `status`      VARCHAR(16)  NOT NULL DEFAULT 'open',         -- open|closed|archived
  `archived_at` DATETIME     NULL DEFAULT NULL,
  `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_report_no` (`report_no`),
  KEY `idx_report_status` (`status`),
  KEY `idx_report_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pd_report_involved` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `report_id`  INT UNSIGNED NOT NULL,
  `identifier` VARCHAR(64)  NOT NULL,
  `name`       VARCHAR(96)  NOT NULL DEFAULT '',
  `role`       VARCHAR(16)  NOT NULL DEFAULT 'suspect',       -- suspect|victim|witness
  PRIMARY KEY (`id`),
  KEY `idx_involved_report` (`report_id`),
  CONSTRAINT `fk_involved_report` FOREIGN KEY (`report_id`)
    REFERENCES `pd_reports` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pd_report_evidence` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `report_id`   INT UNSIGNED NOT NULL,
  `label`       VARCHAR(160) NOT NULL,
  `description` VARCHAR(512) NOT NULL DEFAULT '',
  `created_by`  VARCHAR(64)  NOT NULL DEFAULT '',
  `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_evidence_report` (`report_id`),
  CONSTRAINT `fk_evidence_report` FOREIGN KEY (`report_id`)
    REFERENCES `pd_reports` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Personen-Notizen
CREATE TABLE IF NOT EXISTS `pd_notes` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `citizen_id`  INT UNSIGNED NOT NULL,
  `author_identifier` VARCHAR(64) NOT NULL,
  `author_name` VARCHAR(96)  NOT NULL DEFAULT '',
  `body`        TEXT         NOT NULL,
  `archived_at` DATETIME     NULL DEFAULT NULL,
  `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_note_citizen` (`citizen_id`),
  CONSTRAINT `fk_note_citizen` FOREIGN KEY (`citizen_id`)
    REFERENCES `pd_citizens` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Kennzeichen-Flags (optional; Halterdaten kommen aus ESX owned_vehicles)
CREATE TABLE IF NOT EXISTS `pd_vehicle_flags` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `plate`      VARCHAR(16)  NOT NULL,
  `flag`       VARCHAR(32)  NOT NULL,                          -- stolen|impound|bolo
  `reason`     VARCHAR(255) NOT NULL DEFAULT '',
  `officer_identifier` VARCHAR(64) NOT NULL DEFAULT '',
  `status`     VARCHAR(16)  NOT NULL DEFAULT 'active',
  `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_vflag_plate` (`plate`),
  KEY `idx_vflag_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Berechtigungen
CREATE TABLE IF NOT EXISTS `pd_permissions` (
  `id`    INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `job`   VARCHAR(64)  NOT NULL,
  `grade` INT          NOT NULL,
  `perm`  VARCHAR(64)  NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_pperm` (`job`, `grade`, `perm`),
  KEY `idx_pperm_job` (`job`, `grade`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pd_permission_overrides` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `identifier` VARCHAR(64)  NOT NULL,
  `perm`       VARCHAR(64)  NOT NULL,
  `allow`      TINYINT(1)   NOT NULL DEFAULT 1,
  `created_by` VARCHAR(64)  NOT NULL DEFAULT '',
  `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_poverride` (`identifier`, `perm`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `pd_user_locks` (
  `identifier` VARCHAR(64)  NOT NULL,
  `locked`     TINYINT(1)   NOT NULL DEFAULT 1,
  `reason`     VARCHAR(255) NOT NULL DEFAULT '',
  `created_by` VARCHAR(64)  NOT NULL DEFAULT '',
  `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Einstellungen
CREATE TABLE IF NOT EXISTS `pd_settings` (
  `skey`       VARCHAR(96)  NOT NULL,
  `svalue`     LONGTEXT     NULL,
  `updated_by` VARCHAR(64)  NOT NULL DEFAULT '',
  `updated_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`skey`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Audit-Log
CREATE TABLE IF NOT EXISTS `pd_audit_log` (
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
  KEY `idx_paudit_actor` (`actor_identifier`),
  KEY `idx_paudit_action` (`action`),
  KEY `idx_paudit_created` (`created_at`),
  KEY `idx_paudit_category` (`category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;

-- Seed (Strafenkatalog, Berechtigungen) erfolgt beim ersten Ressourcenstart
-- automatisch aus den Config-Dateien, sofern die Tabellen leer sind.
