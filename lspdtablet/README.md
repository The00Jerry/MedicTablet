# SunLife Roleplay – LSPD Police-Tablet (MDT)

Produktionsfähiges FiveM-Script (ESX Legacy) für das **Los Santos Police Department**:
Personenakten, **Fingerabdruck-Scanner** zur zweifelsfreien Identifikation, Fahndung/BOLO,
bearbeitbarer Strafenkatalog, Bußgelder/Anzeigen über CodeM Billing V2 (Adapter),
Berichte/Fälle mit Beweismitteln, Kennzeichenabfrage, serverseitiges Berechtigungssystem
und Audit-Log. Gleiche Architektur wie das LSMD Medic-Tablet.

> Eigenständige Ressource – unabhängig vom Medic-Tablet lauffähig. Nutzt eigene `pd_`-Tabellen.

---

## Technische Grundlage

| Komponente | Anforderung |
|-----------|-------------|
| Framework | ESX Legacy (`es_extended`) |
| Datenbank | MySQL über `oxmysql` |
| Interaktion | `ox_target` |
| Bußgelder | CodeM Billing V2 (Adapter) – ESX-Bank/Society-Fallback integriert |
| UI | eigene NUI (Vanilla JS, keine externen Abhängigkeiten) |

---

## Installation

1. Ordner nach `resources/[local]/lspdtablet` (Ordnername = `lspdtablet`).
2. Datenbank importieren: `mysql -u USER -p DEINE_DB < sql/install.sql`
3. In der `server.cfg` (nach den Abhängigkeiten):
   ```cfg
   ensure oxmysql
   ensure es_extended
   ensure ox_target
   ensure lspdtablet
   ```
4. `config/config.lua`, `config/permissions.lua`, `config/penalcode.lua` anpassen.
5. CodeM Billing V2 verbinden (`Config.Billing.codem`, siehe unten). Bis dahin läuft der ESX-Fallback.

Beim ersten Start werden Strafenkatalog und Berechtigungen aus den Config-Dateien in die DB
geseedet (nur wenn leer). Danach ist die **Datenbank** die Source of Truth (pflegbar im Tablet).

---

## Öffnen des MDT

Konfigurierbar in `Config.Open`:
- **Command** (Standard `/mdt`), **Taste** (Standard `F7`), **Item** (`police_tablet`), **ox_target** (Mission Row).

Nach dem Schließen wird die Steuerung vollständig freigegeben.

---

## Fingerabdruck-Scanner

Der Kern-„Cool-Feature": zweifelsfreie Identifikation einer Person vor Ort.

- Button **„☝ Fingerabdruck scannen"** (Dashboard/Personensuche) oder Command `/fingerprint`.
- Der Client sucht die **nächstgelegene Person**, spielt eine Scan-Animation und ruft
  serverseitig `fingerprint.scan` auf.
- Die **Distanz wird serverseitig erneut geprüft** (`Config.Fingerprint.maxDistance`) – kein
  Client-Spoofing möglich. Danach wird die Person identifiziert und ihre Akte geöffnet
  (Name, Fingerabdruck-Code, aktive Fahndung, Vorstrafen, Lizenzen).
- Jeder Charakter hat einen **stabilen Fingerabdruck-Code** (z. B. `FP-7A3C91DE`), abgeleitet
  aus dem permanenten Identifier. Über **Personensuche → Feld „Fingerabdruck"** oder
  `fingerprint.lookup` lässt sich ein am Tatort gesicherter Code einer Person zuordnen.

Einstellungen: `Config.Fingerprint` (maxDistance, scanDurationMs, targetMode, codePrefix).

---

## Funktionen

- **Dashboard:** Beamte im Dienst, aktive Fahndungen, offene Berichte, Anzeigen heute, Top-Fahndungen.
- **Personensuche/-akte:** Name/Geburtsdatum/Telefon/Charakter-ID/Fingerabdruck; Akte mit
  Identität, Fahndungsstatus, Lizenzen (Führer-/Waffenschein), Vorstrafen, Berichten, Notizen.
- **Fahndung/BOLO:** Ausschreiben (Stufe niedrig/mittel/hoch), Übersicht, Aufheben; Cache-Flag `is_wanted`.
- **Strafenkatalog:** Delikte (Bußgeld, Haft, Punkte) + Kategorien, bearbeiten/aktivieren/archivieren.
- **Anzeigen/Bußgelder:** Delikte auswählen → Summen (Bußgeld/Haft/Punkte) → ausstellen.
  Bußgeld wird über den Billing-Adapter gebucht, **Snapshot** je Anzeige (rückwirkungssicher), idempotent.
- **Berichte/Fälle:** Vorfall/Festnahme/Verkehr/Ermittlung, beteiligte Personen, Beweismittel, schließen.
- **Kennzeichenabfrage:** Halter (aus ESX `owned_vehicles`) + Markierungen (gestohlen/beschlagnahmt/BOLO).
- **Beamte/Protokolle:** Aktivitäten, paginiertes Audit-Log (optional Discord-Webhooks).
- **Einstellungen:** Branding, Module, Rechte-Overrides & Sperren.

---

## Berechtigungen

Serverseitig geprüft (Job `police` + Grade, DB-Overrides mit Vorrang, Sperren). Rechte-Schlüssel
u. a.: `tablet.open`, `citizen.search/view/edit`, `fingerprint.scan`, `wanted.view/manage`,
`penalcode.view/edit`, `citation.create/cancel`, `report.view/create/edit/close`,
`vehicle.lookup`, `licenses.manage`, `notes.view/add`, `staff.view`, `audit.view`,
`settings.edit`, `admin.full`. Standard-Ränge (0 Cadet … 4 Command) in `config/permissions.lua`
(frei anpassbar, per DB überschreibbar).

---

## CodeM Billing V2 (Bußgelder)

`Config.Billing.codem` mit den **echten** Werten deiner CodeM-Ressource ausfüllen
(Ressourcenname + Export- ODER Eventname + Payload-Feldnamen). Es werden keine Exports/Events
erfunden. Ohne Mapping (oder wenn CodeM aus ist) bucht der ESX-Adapter das Bußgeld vom Bankkonto
der Online-Person ab und schreibt der `police`-Society gut. Haft (Monate) und Führerscheinpunkte
werden gespeichert und können über einen eigenen Export an ein Jail-/Punktesystem übergeben werden.

---

## Vorschau (Browser)

`html/preview.html` im Browser öffnen: rendert die NUI mit Mock-Daten (inkl. Fingerabdruck-Scan)
ohne laufenden Server – ideal zum Ansehen des Designs.

---

## Events / Exports / NUI-Callbacks

- **Events:** `lspd:sv:request` (Client→Server, einziger Eingang), `lspd:cl:response`,
  `lspd:cl:notify`, `lspd:cl:open`.
- **NUI-Callbacks:** `request` (generisch), `fingerprintScan`, `close`.
- **Server-Exports:** `exports['lspdtablet']:HasPermission(identifier, job, grade, perm)`,
  `exports['lspdtablet']:IsWanted(identifier)`.

## Sicherheit

Serverseitige Rechte-/Distanzprüfung, parametrisierte Queries, Rate-Limit, idempotente Anzeigen
(`idempotency_key`), Audit-Log, keine fest eingebauten Zugangsdaten, keine erfundenen Exports/Events.
