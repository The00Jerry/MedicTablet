# City of Los Santos – Department of Licensing & Identification (Wallet)

Nachbau eines Wallet-/Ausweissystems (à la „mSeries/CodeM Wallet") als eigenständige
FiveM-Ressource (ESX Legacy): Personalausweise, Führerscheine, Visitenkarten, Job-Wallets
(Dienstmarken), Tickets & Coupons – mit **DMV-NPC (ox_target)**, einer dunklen Wallet-UI,
**Admin Control Center** und **Developer-Exports**.

> Eigenständig lauffähig, nutzt eigene `lw_`-Tabellen. Gleiche sichere Architektur wie die
> LSMD/LSPD-Tablets (serverseitige Rechte-/Eingabeprüfung, parametrisierte Queries, Audit-Log).

---

## Installation

1. Ordner nach `resources/[local]/lswallet`.
2. `mysql -u USER -p DEINE_DB < sql/install.sql`
3. In der `server.cfg`:
   ```cfg
   ensure oxmysql
   ensure es_extended
   ensure ox_target
   ensure lswallet
   ```
4. `config/config.lua`, `config/templates.lua`, `config/permissions.lua` anpassen.

Beim ersten Start werden Vorlagen und Berechtigungen aus den Config-Dateien geseedet (nur wenn leer).

---

## Bedienung

- **Wallet öffnen:** Command `/wallet`, Taste `F2` (umbelegbar) oder Item `wallet` (optional).
- **DMV-Schalter:** NPC „Department of Licensing & Identification" per `ox_target` ansprechen
  (`Config.NPC`). Dort: **Get ID Card**, **Get Business Card**, **Get License**,
  **Ticket & Coupon Printer**.
- **Wallet-Ansicht:** Kategorien **Cards / Licenses / Tickets & Coupons** → Karte anklicken →
  realistische Karten-Darstellung (Ausweis, Führerschein, Dienstmarke, Visitenkarte, Ticket).
- **Admin Control Center** (nur mit Recht): **Wallet Lookup**, **Applications** (Anträge
  genehmigen/ablehnen), **Templates**.

Nach dem Schließen wird die Steuerung vollständig freigegeben.

---

## Kartentypen & Job-Wallets

- `national_id` (Personalausweis, aus ESX-Stammdaten), `driver_license` (Führerschein mit
  Klasse), `business_card` (frei ausfüllbar), `ticket`/`coupon` (Drucker).
- **Job-Wallets** (Dienstmarken) werden **automatisch** aus dem ESX-Job erzeugt
  (`Config.Templates.JobWallets`, z. B. LSPD/BCSO/FIB/EMS) – nicht gespeichert, immer aktuell.
- Vorlagen sind in `config/templates.lua` gepflegt und im Admin-Center einsehbar/anpassbar.

## Echte ESX-Lizenzen (Führerschein, Waffenschein, …)

Die Lizenzkarten im Wallet sind **nicht nur kosmetisch** – beim Ausstellen/Entziehen wird die
**echte ESX-Lizenz** gesetzt bzw. entfernt, damit andere Systeme (Fahren, Waffenkauf,
Polizei-Check) sie erkennen. Bereits anderweitig vergebene Lizenzen werden automatisch im
Wallet angezeigt.

- **Backend** (`Config.Licenses.provider`):
  - `user_licenses` – ESX-Standardtabelle `user_licenses` (Resource `esx_license`) **[Standard]**
  - `users_json` – Spalte `users.licenses` als JSON-Map `{ drive=true, weapon=true }`
  - `none` – nur Wallet-Karte, keine echte Lizenz
- **Lizenztypen** in `config/templates.lua` → `Config.Templates.Licenses` (Führerschein mit
  Klasse, Waffenschein, Bootsführerschein, Pilotenlizenz, Angelschein …). Jede vergibt ihre
  echte `esxType`-Lizenz. Fee/Antragspflicht je Lizenz konfigurierbar.
- **Perso** kann optional zusätzlich eine ESX-Lizenz setzen (`Config.Licenses.idEsxType`).
- **Voraussetzung** für `user_licenses`: die Tabelle `user_licenses` muss existieren
  (kommt mit `esx_license`). Fehlt sie, wird die Lizenz nicht gesetzt (Wallet-Karte bleibt).

> `exports['lswallet']:HasLicense(identifier, 'drive')` liefert `true`, sobald der Führerschein
> ausgestellt wurde – nutzbar von Fahr-/Waffensystemen.

## Anträge & Autorisierung

Der Führerschein kann als **Antrag** laufen (`Config.Cards.requireApplicationForDriver`):
Spieler beantragt am Schalter → DOL-Mitarbeiter genehmigt/lehnt im Admin-Center ab →
bei Genehmigung wird die Karte ausgestellt. Alternativ direkte Ausstellung.

## Gebühren

`Config.Cards` – `idFee`, `driverFee`, `businessFee`, `ticketFee` sowie Gültigkeitsdauer
(`idExpiryDays`, `driverExpiryDays`). Abbuchung vom `Config.Cards.account` (Standard `bank`).

---

## Berechtigungen (nur Verwaltung)

Die Wallet selbst ist für **alle** Spieler nutzbar. Nur Verwaltungsaktionen erfordern ein Recht
(serverseitig, Job `dol` + Grade, DB-Overrides mit Vorrang):
`wallet.admin.view`, `wallet.admin.authorize`, `wallet.admin.issue`, `wallet.admin.revoke`,
`wallet.admin.template`, `admin.full`.

---

## Developer-Exports

```lua
exports['lswallet']:GetCards(identifier)                       -- alle Karten (Tabelle)
exports['lswallet']:HasCard(identifier, ctype)                 -- boolean
exports['lswallet']:GiveCard(identifier, ctype, templateKey, data, issuedBy) -- cardId
exports['lswallet']:SetCardProperty(cardId, propertyName, value)  -- boolean
exports['lswallet']:RevokeCard(cardId)                         -- boolean
exports['lswallet']:HasLicense(identifier, esxType)           -- boolean (echte ESX-Lizenz)
```

## Events / NUI-Callbacks

- Events: `lswallet:sv:request` (Client→Server), `lswallet:cl:response`, `lswallet:cl:notify`, `lswallet:cl:open`.
- NUI-Callbacks: `request` (generisch), `close`.

## Vorschau

`html/preview.html` im Browser öffnen (Mock, ohne Server): Wallet, DMV-Schalter, Karten-Viewer,
Admin-Center – ideal zum Ansehen des Designs.

## Hinweis zur „Karte in der Hand" (3D-Weltansicht)

Die in manchen Systemen gezeigte, in die Spielwelt gerenderte physische Karte ist ein sehr
aufwändiges Spezial-Feature (Prop-/Textur-Rendering). Diese Ressource stellt Karten in einer
sauberen Vollbild-Kartenansicht dar. Eine echte 3D-Weltansicht kann separat ergänzt werden.

## Sicherheit

Serverseitige Rechte-/Eingabeprüfung je Aktion, parametrisierte Queries, Rate-Limit,
Audit-Log (optional Discord), eindeutige Kartennummern, keine erfundenen Exports/Events.
