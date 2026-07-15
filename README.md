# SunLife Roleplay – Medic-Tablet

Produktionsfähiges FiveM-Script (ESX Legacy) für den Rettungsdienst/das Krankenhaus:
digitale Patientenakten, Behandlungen, Rechnungsstellung über CodeM Billing V2
(Adapter, austauschbar), bearbeitbare Preisliste, vollständiges Krankenversicherungssystem
mit NPC (ox_target) und automatischer wöchentlicher Beitragsabbuchung (offline-fähig),
serverseitiges Berechtigungssystem, Audit-Log und optionale Team-Panel-Anbindung.

> Kein Design-Mockup, keine Demo, keine Mock-Daten: echte oxmysql-Datenbankanbindung,
> serverseitige Rechte-/Berechnungsprüfung, idempotente Rechnungen & Abbuchungen.

---

## Technische Grundlage

| Komponente        | Anforderung                                        |
|-------------------|----------------------------------------------------|
| Server            | FiveM                                              |
| Framework         | ESX Legacy (`es_extended`)                         |
| Datenbank         | MySQL/MariaDB über `oxmysql`                        |
| Rechnungen        | CodeM Billing V2 (Adapter) – ESX-Fallback integriert |
| Target            | `ox_target`                                        |
| UI                | Eigene NUI (Vanilla JS, keine externen Abhängigkeiten) |

Abhängigkeiten: `oxmysql`, `es_extended`, `ox_target`. CodeM Billing V2 ist optional –
ohne funktionierendes Mapping fällt das System sauber auf ESX-Bank/Society zurück.

---

## Installation (Kurzfassung)

1. **Ressource kopieren:** Ordner nach `resources/[local]/medictablet` (Ordnername = Ressourcenname `medictablet`).
2. **Datenbank importieren:**
   ```bash
   mysql -u USER -p DEINE_DB < sql/install.sql
   ```
3. **In der `server.cfg` starten** – nach den Abhängigkeiten:
   ```cfg
   ensure oxmysql
   ensure es_extended
   ensure ox_target
   ensure medictablet
   ```
4. **Konfigurieren:** Werte in `config/config.lua`, `config/permissions.lua`,
   `config/insurance.lua` anpassen (siehe [docs/CONFIGURATION.md](docs/CONFIGURATION.md)).
5. **CodeM Billing V2 verbinden:** `Config.Billing.codem` gemäß
   [docs/CODEM_BILLING.md](docs/CODEM_BILLING.md) mit den ECHTEN Exports/Events deiner
   CodeM-Ressource ausfüllen. Bis dahin läuft der ESX-Fallback.

Beim ersten Start werden Preisliste, Versicherungsstufen und Berechtigungen aus den
Config-Dateien in die DB geseedet (nur wenn die jeweiligen Tabellen leer sind).
Danach ist die **Datenbank die Source of Truth** und wird über Tablet/Team-Panel gepflegt.

---

## Öffnen des Tablets

Konfigurierbar in `Config.Open`:

- **Command** (Standard: `/medictablet`)
- **Taste** (Standard: `F6`, über `RegisterKeyMapping` frei umbelegbar)
- **Item** (`Config.Open.item`, z. B. `medic_tablet` – muss als usable Item existieren)
- **ox_target-Zonen** (feste Orte, z. B. Empfangstresen)

Nach dem Schließen werden Maus/Tastatur/Spielfigur vollständig freigegeben
(kein `DisableControl`-Loop, sauberes `SetNuiFocus(false,false)`).

---

## Funktionsüberblick

- **Dashboard:** Medics im Dienst, heutige Behandlungen/Rechnungen, offene Behandlungen,
  zuletzt bearbeitete Akten, Schnellzugriffe, interner Hinweis – gefiltert nach Rechten.
- **Patientensuche:** Vorname/Nachname/Vollname/Geburtsdatum/Charakter-ID/Telefon,
  Teilsuche, Pagination. Verknüpfung **immer über permanenten Identifier**.
- **Patientenakte:** Stammdaten, Blutgruppe, Allergien, Vorerkrankungen, Medikamente,
  Hinweise, Behandlungen, Rechnungen, Versicherung, sensible interne Notizen (rechtebasiert).
- **Behandlungen:** Status Entwurf/läuft/abgeschlossen/storniert/archiviert, Leistungen als
  Snapshot, Änderungsprotokollierung, Archivierung statt Löschen.
- **Rechnungen (CodeM Billing V2):** serverseitige Versicherungsberechnung, sichtbare
  Kostenaufteilung **vor** dem Ausstellen, explizite Bestätigung, idempotent (kein
  Doppel-Ausstellen), unveränderlicher Kalkulations-Snapshot.
- **Preisliste:** Kategorien & Leistungen, aktiv/deaktiviert/archiviert, benötigte Rechte,
  Ersteller/Änderer/Zeitstempel. Preisänderungen wirken **nie** rückwirkend.
- **Krankenversicherung:** genau 3 frei konfigurierbare Stufen, NPC via ox_target,
  Abschluss/Wechsel/Kündigung mit Bestätigung, wöchentliche Abbuchung (offline-fähig,
  idempotent), Kulanz/Pause/Kündigung bei fehlendem Guthaben.
- **Berechtigungen:** Job + Grade (DB/Config) + Einzel-Overrides + Sperren, alles serverseitig.
- **Audit-Log:** jede sensible Aktion, optional Discord-Webhooks.
- **Team-Panel:** optionale, HMAC-signierte Sync-Schnittstelle (standardmäßig deaktiviert).

---

## Dokumentation

| Datei | Inhalt |
|-------|--------|
| [docs/CONFIGURATION.md](docs/CONFIGURATION.md) | Öffnen, Branding, Preisliste, Versicherung, Abbuchung, Panel |
| [docs/PERMISSIONS.md](docs/PERMISSIONS.md) | Alle Rechte, Rollenbeispiele, Overrides, Sperren |
| [docs/CODEM_BILLING.md](docs/CODEM_BILLING.md) | CodeM Billing V2 anbinden (Adapter-Mapping) |
| [docs/API.md](docs/API.md) | Team-Panel-Vertrag, Sicherheit, Events/Exports/NUI-Callbacks, Fehlerbehandlung |

---

## Projektstruktur

```
medictablet/
├── fxmanifest.lua
├── config/            # config.lua, permissions.lua, pricelist.lua, insurance.lua, panel.lua
├── shared/            # util.lua, locale.lua
├── sql/install.sql    # vollständiges Schema (Tabellen, Indizes, FKs, Idempotenz)
├── server/
│   ├── main.lua       # ESX-Init, sicherer Request-Dispatcher, Seeding
│   ├── db.lua ratelimit.lua audit.lua permissions.lua
│   ├── dashboard.lua patients.lua treatments.lua pricelist.lua
│   ├── insurance.lua insurance_billing.lua billing.lua panel.lua
│   └── adapters/      # account.lua, billing.lua, billing_codem.lua, billing_esx.lua
├── client/            # main.lua (open/close), nui.lua (Bridge), insurance_npc.lua
└── html/              # index.html, style.css, app.js, assets/logo.svg
```

### Architektur in Kürze

- **Ein sicherer Kanal:** NUI/Client senden nur `{action, data}` an
  `medictablet:sv:request`. Der **Dispatcher** (`server/main.lua`) prüft Master-Schalter,
  Rate-Limit, Identität (permanenter Identifier), Job, Sperre und Berechtigung
  **serverseitig**, bevor irgendein Handler läuft. Antwort per `requestId`.
- **Adapter-Muster:** Billing (`codem`/`esx`) und Kontozugriff (`account.lua`) sind gekapselt –
  ein anderes Rechnungssystem oder eine andere ESX-Kontostruktur erfordert nur den Tausch
  einer Datei, nicht des ganzen Tablets.
- **Snapshots:** Behandlungen und Rechnungen speichern Preise/Prozentsätze als Momentaufnahme.
  Spätere Änderungen an Preisliste/Versicherung verändern alte Datensätze nie.
- **Idempotenz:** Rechnungen über `idempotency_key`, wöchentliche Beiträge über
  `UNIQUE(identifier, week_key)`.
