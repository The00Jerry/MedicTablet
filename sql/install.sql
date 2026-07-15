-- =====================================================================
--  SunLife Roleplay – Medic-Tablet
--  Vollstaendige Installationsdatei (MySQL / MariaDB, oxmysql)
--
--  Konventionen:
--    * Alle Tabellen: Prefix mt_ , InnoDB, utf8mb4.
--    * Patienten werden DAUERHAFT ueber den permanenten Charakter-Identifier
--      (VARCHAR 64, z.B. "license:xxxx" / "char1:license:xxxx") verknuepft.
--      Die FiveM-Server-ID wird NIE persistent gespeichert.
--    * Preise & Prozentsaetze werden bei Rechnungen als unveraenderliche
--      Momentaufnahme (Snapshot) gespeichert -> alte Rechnungen bleiben stabil.
--    * Idempotenz: Rechnungen (idempotency_key) und woechentliche Beitraege
--      (identifier + week_key) sind gegen Doppelausfuehrung geschuetzt.
--    * Loeschen wird durch Archivierung (archived_at / status) vermieden.
-- =====================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ---------------------------------------------------------------------
-- Preislisten-Kategorien
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mt_pricelist_categories` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `cat_key`    VARCHAR(64)  NOT NULL,
  `label`      VARCHAR(128) NOT NULL,
  `sort`       INT          NOT NULL DEFAULT 0,
  `active`     TINYINT(1)   NOT NULL DEFAULT 1,
  `archived_at` DATETIME    NULL DEFAULT NULL,
  `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_cat_key` (`cat_key`),
  KEY `idx_cat_active` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Preislisten-Eintraege
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mt_pricelist_items` (
  `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `code`         VARCHAR(32)  NOT NULL,
  `label`        VARCHAR(160) NOT NULL,
  `description`  VARCHAR(512) NOT NULL DEFAULT '',
  `category_id`  INT UNSIGNED NULL,
  `price`        INT UNSIGNED NOT NULL DEFAULT 0,
  `active`       TINYINT(1)   NOT NULL DEFAULT 1,
  `required_perm` VARCHAR(64) NOT NULL DEFAULT '',
  `created_by`   VARCHAR(64)  NOT NULL DEFAULT '',
  `updated_by`   VARCHAR(64)  NOT NULL DEFAULT '',
  `archived_at`  DATETIME     NULL DEFAULT NULL,
  `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_item_code` (`code`),
  KEY `idx_item_cat` (`category_id`),
  KEY `idx_item_active` (`active`),
  CONSTRAINT `fk_item_cat` FOREIGN KEY (`category_id`)
    REFERENCES `mt_pricelist_categories` (`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Digitale Patientenakte (verknuepft ueber permanenten Identifier)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mt_patient_records` (
  `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `identifier`   VARCHAR(64)  NOT NULL,               -- permanenter Charakter-Identifier
  `char_id`      INT UNSIGNED NULL,                   -- optionale numerische Charakter-ID
  `firstname`    VARCHAR(64)  NOT NULL DEFAULT '',
  `lastname`     VARCHAR(64)  NOT NULL DEFAULT '',
  `dateofbirth`  VARCHAR(32)  NOT NULL DEFAULT '',
  `sex`          VARCHAR(16)  NOT NULL DEFAULT '',
  `phone`        VARCHAR(32)  NOT NULL DEFAULT '',
  `blood_type`   VARCHAR(8)   NOT NULL DEFAULT '',
  `allergies`    TEXT         NULL,
  `preconditions` TEXT        NULL,
  `medications`  TEXT         NULL,
  `medical_notes` TEXT        NULL,                    -- allgemeine (nicht sensible) Hinweise
  `last_treatment_at` DATETIME NULL DEFAULT NULL,
  `archived_at`  DATETIME     NULL DEFAULT NULL,
  `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_patient_identifier` (`identifier`),
  KEY `idx_patient_name` (`lastname`, `firstname`),
  KEY `idx_patient_phone` (`phone`),
  KEY `idx_patient_charid` (`char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Behandlungen
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mt_treatments` (
  `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `treatment_no`  VARCHAR(32)  NOT NULL,               -- eindeutige Behandlungsnummer
  `patient_id`    INT UNSIGNED NOT NULL,
  `identifier`    VARCHAR(64)  NOT NULL,               -- redundant fuer schnelle Suche
  `staff_identifier` VARCHAR(64) NOT NULL,             -- behandelnder Mitarbeiter
  `staff_name`    VARCHAR(96)  NOT NULL DEFAULT '',
  `diagnosis`     VARCHAR(512) NOT NULL DEFAULT '',
  `measures`      TEXT         NULL,                    -- durchgefuehrte Massnahmen
  `medications`   TEXT         NULL,                    -- verabreichte Medikamente
  `report`        TEXT         NULL,                    -- ausfuehrlicher Bericht
  `internal_note` TEXT         NULL,                    -- sensible interne Notiz (Recht noetig)
  `amount_base`   INT          NOT NULL DEFAULT 0,      -- urspruenglicher Gesamtbetrag
  `amount_insurance` INT       NOT NULL DEFAULT 0,      -- Versicherungsanteil
  `amount_discount`  INT       NOT NULL DEFAULT 0,      -- zusaetzlicher Rabatt
  `amount_final`  INT          NOT NULL DEFAULT 0,      -- endgueltiger Rechnungsbetrag
  -- Status: draft | ongoing | completed | cancelled | archived
  `status`        VARCHAR(16)  NOT NULL DEFAULT 'draft',
  `archived_at`   DATETIME     NULL DEFAULT NULL,
  `created_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_treatment_no` (`treatment_no`),
  KEY `idx_treatment_patient` (`patient_id`),
  KEY `idx_treatment_identifier` (`identifier`),
  KEY `idx_treatment_status` (`status`),
  KEY `idx_treatment_created` (`created_at`),
  CONSTRAINT `fk_treatment_patient` FOREIGN KEY (`patient_id`)
    REFERENCES `mt_patient_records` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Behandlungspositionen (Snapshot der gewaehlten Leistungen)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mt_treatment_items` (
  `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `treatment_id` INT UNSIGNED NOT NULL,
  `item_code`    VARCHAR(32)  NOT NULL,                -- Snapshot des Codes
  `label`        VARCHAR(160) NOT NULL,                -- Snapshot der Bezeichnung
  `unit_price`   INT UNSIGNED NOT NULL DEFAULT 0,      -- Snapshot Einzelpreis
  `quantity`     INT UNSIGNED NOT NULL DEFAULT 1,
  `line_total`   INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `idx_titem_treatment` (`treatment_id`),
  CONSTRAINT `fk_titem_treatment` FOREIGN KEY (`treatment_id`)
    REFERENCES `mt_treatments` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Medizinische (sensible) Notizen – nur mit Recht notes.internal.view
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mt_medical_notes` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `patient_id`  INT UNSIGNED NOT NULL,
  `treatment_id` INT UNSIGNED NULL,
  `author_identifier` VARCHAR(64) NOT NULL,
  `author_name` VARCHAR(96)  NOT NULL DEFAULT '',
  `body`        TEXT         NOT NULL,
  `sensitive`   TINYINT(1)   NOT NULL DEFAULT 1,
  `archived_at` DATETIME     NULL DEFAULT NULL,
  `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_note_patient` (`patient_id`),
  CONSTRAINT `fk_note_patient` FOREIGN KEY (`patient_id`)
    REFERENCES `mt_patient_records` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Versicherungsstufen (genau 3, aber technisch offen)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mt_insurance_tiers` (
  `id`             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `tier_key`       VARCHAR(32)  NOT NULL,
  `label`          VARCHAR(96)  NOT NULL,
  `description`    VARCHAR(512) NOT NULL DEFAULT '',
  `color`          VARCHAR(16)  NOT NULL DEFAULT '#38bdf8',
  `icon`           VARCHAR(48)  NOT NULL DEFAULT 'shield',
  `weekly_premium` INT UNSIGNED NOT NULL DEFAULT 0,
  `coverage_pct`   INT UNSIGNED NOT NULL DEFAULT 0,     -- 0..100
  `max_per_invoice` INT UNSIGNED NOT NULL DEFAULT 0,    -- 0 = unbegrenzt
  `weekly_cap`     INT UNSIGNED NOT NULL DEFAULT 0,     -- 0 = unbegrenzt
  `active`         TINYINT(1)   NOT NULL DEFAULT 1,
  `min_term_days`  INT UNSIGNED NOT NULL DEFAULT 0,
  `cancel_notice_days` INT UNSIGNED NOT NULL DEFAULT 0,
  `waiting_days`   INT UNSIGNED NOT NULL DEFAULT 0,
  `created_at`     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_tier_key` (`tier_key`),
  KEY `idx_tier_active` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Versicherungsvertraege (pro Charakter, ueber Identifier)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mt_insurance_contracts` (
  `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `identifier`   VARCHAR(64)  NOT NULL,
  `tier_id`      INT UNSIGNED NOT NULL,
  `tier_key`     VARCHAR(32)  NOT NULL,               -- Snapshot fuer Historie
  -- Status: active | waiting | grace | paused | cancelled
  `status`       VARCHAR(16)  NOT NULL DEFAULT 'active',
  `started_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `waiting_until` DATETIME    NULL DEFAULT NULL,       -- Ende der Wartezeit
  `grace_until`  DATETIME     NULL DEFAULT NULL,       -- Ende der Kulanzzeit
  `min_term_until` DATETIME   NULL DEFAULT NULL,       -- Ende Mindestlaufzeit
  `cancel_effective_at` DATETIME NULL DEFAULT NULL,    -- Kuendigung wirksam ab (Frist)
  `next_charge_at` DATETIME   NULL DEFAULT NULL,       -- naechster geplanter Abbuchungstermin
  `last_charge_at` DATETIME   NULL DEFAULT NULL,       -- letzte erfolgreiche Abbuchung
  `last_week_key`  INT        NOT NULL DEFAULT 0,      -- letzte erfolgreich bezahlte Woche
  `failed_count` INT UNSIGNED NOT NULL DEFAULT 0,
  `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_contract_identifier` (`identifier`),   -- ein aktiver Vertrag je Charakter
  KEY `idx_contract_status` (`status`),
  KEY `idx_contract_next` (`next_charge_at`),
  CONSTRAINT `fk_contract_tier` FOREIGN KEY (`tier_id`)
    REFERENCES `mt_insurance_tiers` (`id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Versicherungs-Statuswechsel / Wechsel / Kuendigungen / Pausierungen
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mt_insurance_changes` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `identifier`  VARCHAR(64)  NOT NULL,
  -- change_type: subscribe | switch | cancel | pause | resume | expire
  `change_type` VARCHAR(16)  NOT NULL,
  `from_tier`   VARCHAR(32)  NULL,
  `to_tier`     VARCHAR(32)  NULL,
  `actor_identifier` VARCHAR(64) NOT NULL DEFAULT '',  -- Ausloeser (Spieler/Medic/System)
  `reason`      VARCHAR(255) NOT NULL DEFAULT '',
  `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_inschange_identifier` (`identifier`),
  KEY `idx_inschange_type` (`change_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Woechentliche Beitraege (idempotent je Woche) + Versuche
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mt_insurance_premiums` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `txn_id`      VARCHAR(48)  NOT NULL,                 -- eindeutige Transaktions-ID
  `identifier`  VARCHAR(64)  NOT NULL,
  `contract_id` INT UNSIGNED NULL,
  `tier_key`    VARCHAR(32)  NOT NULL,
  `amount`      INT UNSIGNED NOT NULL DEFAULT 0,
  `week_key`    INT          NOT NULL,                 -- year*100+isoweek (Idempotenz-Schluessel)
  `scheduled_at` DATETIME    NOT NULL,
  `charged_at`  DATETIME     NULL DEFAULT NULL,
  -- Status: pending | paid | failed | grace | cancelled
  `status`      VARCHAR(16)  NOT NULL DEFAULT 'pending',
  `attempts`    INT UNSIGNED NOT NULL DEFAULT 0,
  `last_error`  VARCHAR(255) NOT NULL DEFAULT '',
  `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_premium_txn` (`txn_id`),
  UNIQUE KEY `uq_premium_week` (`identifier`, `week_key`), -- verhindert Doppelabbuchung/Woche
  KEY `idx_premium_status` (`status`),
  KEY `idx_premium_ident` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mt_insurance_charge_attempts` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `premium_id`  INT UNSIGNED NOT NULL,
  `attempt_no`  INT UNSIGNED NOT NULL DEFAULT 1,
  `result`      VARCHAR(16)  NOT NULL DEFAULT '',       -- paid | insufficient | error
  `message`     VARCHAR(255) NOT NULL DEFAULT '',
  `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_attempt_premium` (`premium_id`),
  CONSTRAINT `fk_attempt_premium` FOREIGN KEY (`premium_id`)
    REFERENCES `mt_insurance_premiums` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Rechnungsreferenzen (Billing-Adapter) + Kalkulations-Snapshot
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mt_invoice_refs` (
  `id`              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `invoice_no`      VARCHAR(32)  NOT NULL,             -- interne Rechnungsnummer
  `idempotency_key` VARCHAR(64)  NOT NULL,             -- verhindert Doppelausstellung
  `treatment_id`    INT UNSIGNED NULL,
  `patient_id`      INT UNSIGNED NOT NULL,
  `identifier`      VARCHAR(64)  NOT NULL,             -- Patient (permanenter Identifier)
  `medic_identifier` VARCHAR(64) NOT NULL,             -- ausstellender Medic
  `medic_name`      VARCHAR(96)  NOT NULL DEFAULT '',
  `reason`          VARCHAR(255) NOT NULL DEFAULT '',
  -- Kalkulations-Snapshot (unveraenderlich):
  `amount_base`     INT          NOT NULL DEFAULT 0,   -- urspruenglicher Gesamtbetrag
  `insurance_tier_key` VARCHAR(32) NOT NULL DEFAULT '',
  `insurance_tier_label` VARCHAR(96) NOT NULL DEFAULT '',
  `insurance_pct`   INT          NOT NULL DEFAULT 0,
  `insurance_amount` INT         NOT NULL DEFAULT 0,   -- uebernommener Versicherungsbetrag
  `insurance_cap_applied` INT    NOT NULL DEFAULT 0,   -- angewendetes (rest-)Limit
  `insurance_status_at_time` VARCHAR(16) NOT NULL DEFAULT '',
  `discount_amount` INT          NOT NULL DEFAULT 0,   -- manueller Rabatt (separat!)
  `amount_final`    INT          NOT NULL DEFAULT 0,   -- endgueltiger Patientenbetrag
  `settlement_mode` VARCHAR(16)  NOT NULL DEFAULT 'patient_only',
  `provider`        VARCHAR(16)  NOT NULL DEFAULT '',  -- codem | esx
  `provider_invoice_id` VARCHAR(64) NULL,              -- CodeM-Billing-Rechnungs-ID
  -- Status: pending | issued | cancelled | failed
  `status`          VARCHAR(16)  NOT NULL DEFAULT 'pending',
  `error`           VARCHAR(255) NOT NULL DEFAULT '',
  `created_at`      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_invoice_no` (`invoice_no`),
  UNIQUE KEY `uq_invoice_idem` (`idempotency_key`),
  KEY `idx_invoice_patient` (`patient_id`),
  KEY `idx_invoice_ident` (`identifier`),
  KEY `idx_invoice_treatment` (`treatment_id`),
  KEY `idx_invoice_status` (`status`),
  CONSTRAINT `fk_invoice_patient` FOREIGN KEY (`patient_id`)
    REFERENCES `mt_patient_records` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Gespeicherte Rechnungspositionen (Snapshot)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mt_invoice_items` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `invoice_id`  INT UNSIGNED NOT NULL,
  `item_code`   VARCHAR(32)  NOT NULL,
  `label`       VARCHAR(160) NOT NULL,
  `unit_price`  INT UNSIGNED NOT NULL DEFAULT 0,
  `quantity`    INT UNSIGNED NOT NULL DEFAULT 1,
  `line_total`  INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `idx_iitem_invoice` (`invoice_id`),
  CONSTRAINT `fk_iitem_invoice` FOREIGN KEY (`invoice_id`)
    REFERENCES `mt_invoice_refs` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Versicherungserstattungen (fuer woechentliches Erstattungslimit)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mt_insurance_reimbursements` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `identifier`  VARCHAR(64)  NOT NULL,
  `invoice_id`  INT UNSIGNED NULL,
  `tier_key`    VARCHAR(32)  NOT NULL,
  `amount`      INT UNSIGNED NOT NULL DEFAULT 0,       -- tatsaechlich uebernommener Betrag
  `week_key`    INT          NOT NULL,
  `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_reimb_ident_week` (`identifier`, `week_key`),
  KEY `idx_reimb_invoice` (`invoice_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Berechtigungen (Job/Grade) – editierbare Spiegelung der Config
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mt_permissions` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `job`        VARCHAR(64)  NOT NULL,
  `grade`      INT          NOT NULL,
  `perm`       VARCHAR(64)  NOT NULL,
  `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_perm` (`job`, `grade`, `perm`),
  KEY `idx_perm_job` (`job`, `grade`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Ueberschreibende Einzelberechtigungen + Sperren je Benutzer/Charakter
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mt_permission_overrides` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `identifier` VARCHAR(64)  NOT NULL,
  `perm`       VARCHAR(64)  NOT NULL,
  `allow`      TINYINT(1)   NOT NULL DEFAULT 1,        -- 1 = gewaehren, 0 = entziehen
  `created_by` VARCHAR(64)  NOT NULL DEFAULT '',
  `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_override` (`identifier`, `perm`),
  KEY `idx_override_ident` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mt_user_locks` (
  `identifier` VARCHAR(64)  NOT NULL,
  `locked`     TINYINT(1)   NOT NULL DEFAULT 1,
  `reason`     VARCHAR(255) NOT NULL DEFAULT '',
  `created_by` VARCHAR(64)  NOT NULL DEFAULT '',
  `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Einstellungen (Team-Panel / Tablet) als Key-Value (JSON)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mt_settings` (
  `skey`       VARCHAR(96)  NOT NULL,
  `svalue`     LONGTEXT     NULL,                       -- JSON
  `updated_by` VARCHAR(64)  NOT NULL DEFAULT '',
  `updated_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`skey`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Synchronisierungsstatus (Team-Panel)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mt_sync_state` (
  `area`         VARCHAR(48)  NOT NULL,                 -- settings|pricelist|insurance
  `last_sync_at` DATETIME     NULL DEFAULT NULL,
  `last_ok`      TINYINT(1)   NOT NULL DEFAULT 1,
  `last_error`   VARCHAR(255) NOT NULL DEFAULT '',
  `payload_hash` VARCHAR(64)  NOT NULL DEFAULT '',
  PRIMARY KEY (`area`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- Audit-Log
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `mt_audit_log` (
  `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `actor_identifier` VARCHAR(64) NOT NULL DEFAULT '',
  `actor_name`  VARCHAR(96)  NOT NULL DEFAULT '',
  `discord_id`  VARCHAR(32)  NOT NULL DEFAULT '',
  `category`    VARCHAR(32)  NOT NULL DEFAULT 'default',
  `action`      VARCHAR(64)  NOT NULL,
  `target_type` VARCHAR(32)  NOT NULL DEFAULT '',       -- patient|treatment|invoice|...
  `target_id`   VARCHAR(64)  NOT NULL DEFAULT '',
  `old_value`   LONGTEXT     NULL,
  `new_value`   LONGTEXT     NULL,
  `reason`      VARCHAR(255) NOT NULL DEFAULT '',
  `result`      VARCHAR(16)  NOT NULL DEFAULT 'ok',      -- ok|denied|error
  `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_audit_actor` (`actor_identifier`),
  KEY `idx_audit_action` (`action`),
  KEY `idx_audit_target` (`target_type`, `target_id`),
  KEY `idx_audit_created` (`created_at`),
  KEY `idx_audit_category` (`category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;

-- =====================================================================
--  Ende Schema. Seed-Daten (Preisliste, Versicherungsstufen, Permissions)
--  werden beim ersten Ressourcenstart automatisch aus den Config-Dateien
--  eingespielt, sofern die jeweiligen Tabellen leer sind (siehe server/main.lua).
-- =====================================================================
