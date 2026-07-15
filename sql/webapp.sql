-- =====================================================================
--  Medic-Tablet – Web-App / Team-Panel Erweiterung
--  Zusatz-Migration (additiv zu sql/install.sql). Nach install.sql einspielen:
--     mysql -u USER -p DEINE_DB < sql/webapp.sql
--
--  Enthaelt die Rechnungs-Warteschlange: die externe Web-App legt Rechnungs-
--  wuensche hier ab; der FiveM-Server (server/webbridge.lua) holt sie ab und
--  erstellt sie ECHT ueber den CodeM-Billing-Adapter. Idempotent.
-- =====================================================================

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS `mt_invoice_queue` (
  `id`              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `idempotency_key` VARCHAR(64)  NOT NULL,               -- verhindert Doppelanlage
  `identifier`      VARCHAR(64)  NOT NULL,               -- Patient (permanenter Identifier)
  `treatment_id`    INT UNSIGNED NULL,                   -- optional: Rechnung aus Behandlung
  `items_json`      LONGTEXT     NULL,                   -- [{code, quantity}] falls ohne Behandlung
  `discount`        INT UNSIGNED NOT NULL DEFAULT 0,
  `reason`          VARCHAR(255) NOT NULL DEFAULT '',
  `actor_identifier` VARCHAR(64) NOT NULL DEFAULT '',    -- z.B. discord:123... (Web-User)
  `actor_name`      VARCHAR(96)  NOT NULL DEFAULT '',
  `actor_discord`   VARCHAR(32)  NOT NULL DEFAULT '',
  `actor_perms`     LONGTEXT     NULL,                   -- JSON: { "perm": true } (serverseitig gesetzt)
  -- Status: pending | processing | done | failed
  `status`          VARCHAR(16)  NOT NULL DEFAULT 'pending',
  `result_invoice_id` INT UNSIGNED NULL,
  `error`           VARCHAR(255) NOT NULL DEFAULT '',
  `attempts`        INT UNSIGNED NOT NULL DEFAULT 0,
  `created_at`      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `processed_at`    DATETIME     NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_queue_idem` (`idempotency_key`),
  KEY `idx_queue_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
