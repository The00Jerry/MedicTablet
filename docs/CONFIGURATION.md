# Konfiguration

Alle wichtigen Funktionen sind konfigurierbar. Config-Dateien liefern **Seed-/Start-Werte**;
nach dem ersten Start ist die **Datenbank** die Source of Truth (pflegbar über Tablet-
Einstellungen bzw. Team-Panel). Preisliste, Versicherungsstufen, Branding und Module lassen
sich zur Laufzeit ändern.

---

## 1. Tablet öffnen (`config/config.lua` → `Config.Open`)

```lua
Config.Open = {
  command = { enabled = true,  name = 'medictablet' },
  key     = { enabled = true,  default = 'F6', mapCommand = 'medictablet_key' },
  item    = { enabled = false, name = 'medic_tablet' },
  target  = { enabled = true,  zones = { { coords = vector3(340.0,-1396.4,32.5), radius = 1.5, label = 'Medic-Tablet öffnen' } } },
}
```

- Jede Öffnungsart einzeln aktivierbar.
- Taste über `RegisterKeyMapping` – Spieler können sie in den FiveM-Einstellungen umbelegen.
- Item benötigt ein existierendes usable Item (ESX `RegisterUsableItem` wird serverseitig registriert).
- `requireOnDuty` (in `Config.Security`) erzwingt optional den Dienststatus.

Nach dem Schließen wird die Steuerung vollständig freigegeben.

---

## 2. Branding (`Config.Branding`) – auch im Tablet unter *Einstellungen* editierbar

```lua
Config.Branding = {
  serverName = 'SunLife Roleplay',
  clinicName = 'SunLife Medical Center',
  departments = { 'Notaufnahme', 'Chirurgie', 'Innere Medizin', 'Verwaltung' },
  logo = 'assets/logo.svg',
  theme = 'dark',            -- 'dark' | 'light'
  colorPrimary = '#e11d48',
  colorAccent  = '#f59e0b',
  colorBg      = '#0b0f19',
}
```

- Logo: eigene Datei nach `html/assets/` legen und Pfad (relativ zu `html/`) eintragen.
- Änderungen über *Einstellungen* werden in `mt_settings` gespeichert und sofort angewandt.

---

## 3. Preisliste anpassen

**Seed:** `config/pricelist.lua` (nur beim ersten Start, wenn Tabellen leer).
**Laufzeit:** Tablet → *Preisliste* (Recht `pricelist.edit`) oder Team-Panel.

Jeder Eintrag: eindeutige ID/Code, Bezeichnung, Beschreibung, Kategorie, Einzelpreis,
Status (aktiv/deaktiviert), benötigte Berechtigung, Ersteller/Änderer, Zeitstempel.

Möglich: neue Leistungen, bearbeiten, aktivieren/deaktivieren, archivieren, Kategorien
anlegen/bearbeiten, Preise ändern.

> **Preisänderungen wirken nie rückwirkend.** Bei Behandlung/Rechnung werden Bezeichnung
> und Einzelpreis als Snapshot separat gespeichert (`mt_treatment_items`, `mt_invoice_items`).

---

## 4. Krankenversicherung (`config/insurance.lua`)

### 4.1 Drei Stufen (`Config.Insurance.TiersSeed`)

Genau drei frei konfigurierbare Stufen. Pro Stufe einstellbar:

| Feld | Bedeutung |
|------|-----------|
| `tier_key` | stabiler Schlüssel (nicht ändern) |
| `label`, `description`, `color`, `icon` | Anzeige |
| `weekly_premium` | wöchentlicher Beitrag ($) |
| `coverage_pct` | prozentuale Kostenübernahme (0–100) |
| `max_per_invoice` | max. Übernahme pro Rechnung ($); `0` = unbegrenzt |
| `weekly_cap` | wöchentliches Erstattungslimit ($); `0` = unbegrenzt |
| `active` | aktiv/deaktiviert |
| `min_term_days` | Mindestlaufzeit (Tage) |
| `cancel_notice_days` | Kündigungsfrist (Tage) |
| `waiting_days` | Wartezeit bis Schutz aktiv (Tage) |

Beispiel-Übernahme: Basis 20 %, Komfort 50 %, Premium 80 %.
Laufzeit-Pflege: Tablet → *Versicherung* (Recht `insurance.manage`) oder Team-Panel.

### 4.2 Versicherungs-NPC (`Config.Insurance.NPC`)

```lua
Config.Insurance.NPC = {
  enabled  = true,
  ped      = 's_m_m_doctor_01',
  coords   = vector4(295.9, -600.1, 43.28, 20.0), -- x,y,z,heading
  scenario = 'WORLD_HUMAN_CLIPBOARD',             -- oder anim = { dict=, name= }
  invincible = true, freeze = true,
  blip = { enabled = true, sprite = 274, color = 25, scale = 0.8, label = 'Krankenversicherung' },
  target = { label = 'Krankenversicherung verwalten', icon = 'fa-solid fa-heart-pulse', distance = 2.0 },
}
```

NPC ist unverwundbar, unbeweglich, über ox_target ansprechbar und öffnet die
Versicherungs-Oberfläche (vergleichen, abschließen, wechseln, kündigen, Status/letzte
Abbuchung/nächster Termin/fehlgeschlagene Abbuchungen). Vor jeder Aktion: Bestätigungsdialog.

### 4.3 Wöchentliche Abbuchung (`Config.Insurance.Billing`)

```lua
Config.Insurance.Billing = {
  account = 'bank',
  weekday = 1, hour = 4, minute = 0,      -- 1=Mo … 7=So
  checkIntervalMinutes = 15,
  maxAttempts = 3, retryIntervalHours = 12,
  graceHours = 48,
  onFail = 'pause',                        -- 'pause' | 'cancel'
  notify = { success=true, failed=true, grace=true, paused=true, cancelled=true, upcoming=false },
}
```

- **Offline-fähig:** die Abbuchung liest/schreibt bei Offline-Spielern serverseitig direkt
  die ESX-Konten (Account-Adapter). Online läuft es über die ESX-API.
- **Idempotent:** `UNIQUE(identifier, week_key)` verhindert Doppelabbuchung pro Woche.
- **Kein Guthaben:** Kulanzzeit → Retry → nach `maxAttempts` je nach `onFail` Pause/Kündigung.
- Während **Pause/Kündigung/Wartezeit** erfolgt **keine** Kostenübernahme.

Jede Abbuchung erzeugt Transaktions-ID, Charakter-ID, Stufe, Betrag, geplantes/tatsächliches
Datum, Status, Versuche und ggf. Fehlermeldung (`mt_insurance_premiums` + `..._charge_attempts`).

### 4.4 Verrechnung des Versicherungsanteils (`Config.Insurance.SettlementMode`)

- `patient_only` **(Standard)** – an Billing geht nur der reduzierte Patientenbetrag.
- `insurer_pays` – zusätzlich wird der Versicherungsanteil einem Society-/Versicherungskonto
  gutgeschrieben (nur bei vorhandenem `esx_addonaccount`, sonst wird es geloggt & übersprungen).
- `full_then_net` – analog, Gegenverrechnung des Anteils.

> Es werden keine nicht vorhandenen Kontosysteme erfunden. Ohne passendes System bleibt es
> beim Patientenbetrag, das Verhalten wird protokolliert.

---

## 5. Account-Struktur (`server/adapters/account.lua`)

Standard: ESX Legacy `users.accounts` (JSON: `bank`/`money`/`black_money`). Weicht deine
ESX-Version ab (separate Kontotabelle o. Ä.), muss **nur** diese eine Datei angepasst werden
(`ACCOUNTS_COLUMN` bzw. die `charge`/`getBalance`-Logik).

---

## 6. Team-Panel (`config/panel.lua`)

Standardmäßig **deaktiviert** (`Config.Panel.enabled = false`) – siehe [API.md](API.md).
Aktivierung: `apiUrl`, `apiKey`, `hmacSecret`, Intervalle setzen und `enabled = true`.
Bei Ausfall arbeitet das Tablet mit den zuletzt gespeicherten DB-Settings weiter
(`onOutage = 'last_known'`) und synchronisiert nach Reconnect automatisch.

---

## 7. Audit & Discord (`Config.Audit`)

`Config.Audit.enabled` sowie kategoriebezogene Webhooks (`default`, `billing`, `insurance`,
`security`, `settings`). Webhooks werden **nur serverseitig** aufgerufen.
