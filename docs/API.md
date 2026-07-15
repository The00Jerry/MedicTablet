# API, Schnittstellen & Sicherheit

## Inhalt
1. Interner sicherer Kanal (Client ↔ Server)
2. Alle Request-Actions (NUI → Server)
3. FiveM-Events
4. NUI-Callbacks
5. Server-Exports (für andere Ressourcen)
6. Team-Panel-Schnittstelle (Vertrag)
7. Sicherheitsmaßnahmen
8. Fehlerbehandlung

---

## 1. Interner sicherer Kanal

NUI und Client rufen **nie** direkt DB/Billing. Es gibt genau einen Kanal:

```
NUI  --fetch('https://medictablet/request', {action, data})-->  client/nui.lua
client  --TriggerServerEvent('medictablet:sv:request', reqId, action, data)-->  server dispatcher
server  --TriggerClientEvent('medictablet:cl:response', src, reqId, ok, payload)-->  client
client  --resolve NUI callback-->  NUI
```

Der Dispatcher (`server/main.lua`) prüft **vor jedem Handler**: Master-Schalter,
Rate-Limit, Identität (permanenter Identifier), erlaubter Job, Sperre und die für die
Action nötige Berechtigung. Antwortformat an die NUI: `{ ok: boolean, data: {...} }`.
Bei Fehler: `{ ok: false, data: { error: 'lesbarer Text' } }`.

---

## 2. Request-Actions

Format: `action` — benötigtes Recht — Feature-Toggle — wichtigste Eingabe → Ausgabe.

### Bootstrap / Dashboard
| Action | Recht | Eingabe → Ausgabe |
|--------|-------|-------------------|
| `tablet.bootstrap` | `tablet.open` | – → `{identity, branding, features, perms, dashboard}` |
| `dashboard.data` | `tablet.open` | – → `{dashboard}` |
| `staff.overview` | `staff.view` | – → `{onDuty, activity}` |
| `audit.list` | `audit.view` | `{page, category}` → `{rows, total, page}` |

### Patienten & Behandlungen
| Action | Recht | Eingabe → Ausgabe |
|--------|-------|-------------------|
| `patients.search` | `patient.search` | `{q, field, page, pageSize}` → `{results, total}` |
| `patients.open` | `patient.view` | `{identifier}` → `{record, treatments, invoices, insurance}` |
| `patients.update` | `patient.edit` | `{identifier, blood_type, allergies, …}` → `{ok}` |
| `patients.notes` | `notes.internal.view` | `{identifier}` → `{notes}` |
| `patients.addNote` | `notes.internal.view` | `{identifier, body}` → `{ok}` |
| `treatment.get` | `patient.view` | `{id}` → `{treatment, items}` |
| `treatment.create` | `treatment.create` | `{identifier, diagnosis, items[], discount, status, …}` → `{id, treatment_no, insurance}` |
| `treatment.update` | `treatment.edit` | `{id, diagnosis?, status?, …}` → `{ok}` |
| `treatment.archive` | `treatment.archive` | `{id}` → `{ok}` |

### Rechnungen
| Action | Recht | Eingabe → Ausgabe |
|--------|-------|-------------------|
| `billing.preview` | `invoice.create` | `{identifier, items[]|treatment_id, discount}` → `{lines, breakdown, display}` |
| `billing.create` | `invoice.create` | `{identifier, items[]|treatment_id, discount, reason, idempotency_key}` → `{invoice_id, invoice_no, provider, provider_invoice_id}` |
| `billing.cancel` | `invoice.cancel` | `{id, reason}` → `{ok}` |

> `idempotency_key` wird pro Rechnungsformular **einmalig** erzeugt und schützt (zusammen mit
> `UNIQUE(idempotency_key)` in der DB und einem In-Memory-Lock) vor Doppelausstellung.

### Preisliste
| Action | Recht | Eingabe → Ausgabe |
|--------|-------|-------------------|
| `pricelist.list` | `pricelist.view` | `{all?}` → `{categories, items, canEdit}` |
| `pricelist.saveItem` | `pricelist.edit` | `{id?, label, code, price, category_id, required_perm, description}` → `{ok}` |
| `pricelist.toggle` | `pricelist.edit` | `{id}` → `{ok, active}` |
| `pricelist.archive` | `pricelist.edit` | `{id}` → `{ok}` |
| `pricelist.saveCategory` | `pricelist.edit` | `{id?, label, sort}` → `{ok}` |

### Versicherung (Medic/Verwaltung)
| Action | Recht | Eingabe → Ausgabe |
|--------|-------|-------------------|
| `insurance.tiers` | `insurance.patient.view` | – → `{tiers, canManage}` |
| `insurance.patientView` | `insurance.patient.view` | `{identifier}` → `{contract}` |
| `insurance.saveTier` | `insurance.manage` | `{id, label, weekly_premium, coverage_pct, …}` → `{ok}` |
| `insurance.manageContract` | `insurance.manage` | `{identifier, action: pause|resume|cancel}` → `{ok, contract}` |
| `insurance.failedList` | `insurance.failed.view` | `{page}` → `{rows, total}` |
| `insurance.retry` | `insurance.retry` | `{premium_id}` → `{ok, status}` |

### Versicherung (Spieler / NPC – ohne Medic-Job, `open=true`)
| Action | Eingabe → Ausgabe |
|--------|-------------------|
| `insurance.npc.get` | – → `{tiers, contract, recentCharges}` |
| `insurance.npc.subscribe` | `{tier_key}` → `{ok, contract}` (erster Beitrag sofort) |
| `insurance.npc.switch` | `{tier_key}` → `{ok, contract}` |
| `insurance.npc.cancel` | – → `{ok, contract}` |

### Einstellungen / Rechte (Admin)
| Action | Recht | Eingabe → Ausgabe |
|--------|-------|-------------------|
| `settings.get` | `settings.edit` | – → `{branding, features, notice, panel}` |
| `settings.save` | `settings.edit` | `{branding?, features?, notice?}` → `{ok}` |
| `perms.setOverride` | `settings.edit` | `{identifier, perm, allow}` → `{ok}` |
| `perms.lock` | `settings.edit` | `{identifier, locked, reason}` → `{ok}` |

---

## 3. FiveM-Events

| Event | Richtung | Zweck |
|-------|----------|-------|
| `medictablet:sv:request` | Client → Server | Einziger Eingangspunkt (Dispatcher) |
| `medictablet:cl:response` | Server → Client | Antwort per `reqId` |
| `medictablet:cl:notify` | Server → Client | Ingame-Benachrichtigung (z. B. Abbuchung) |
| `medictablet:cl:open` | Server → Client | Tablet öffnen (durch usable Item) |

Es werden **keine** fremden Events erfunden. CodeM/ESX werden nur über den jeweiligen
Adapter mit den in der Config hinterlegten (echten) Namen angesprochen.

---

## 4. NUI-Callbacks

| Callback | Zweck |
|----------|-------|
| `request` | generischer Kanal `{action, data}` → `{ok, data}` |
| `close` | Tablet schließen, NUI-Focus freigeben |

---

## 5. Server-Exports

Für andere Ressourcen (nur lesend/berechnend, keine Zustandsänderung):

```lua
exports['medictablet']:HasPermission(identifier, job, grade, perm) -- boolean
exports['medictablet']:CalcInsurance(identifier, baseAmount)       -- Snapshot-Tabelle
exports['medictablet']:GetInsuranceContract(identifier)            -- Vertrags-View
exports['medictablet']:IsInsuranceCovered(identifier)              -- boolean
```

---

## 6. Team-Panel-Schnittstelle (Vertrag)

Standardmäßig **deaktiviert** (`config/panel.lua` → `Config.Panel.enabled = false`).
Bei Aktivierung ist die FiveM-Seite der Client; **dein Panel implementiert die Gegenseite**
nach folgendem Vertrag. API-Key/Secret liegen ausschließlich serverseitig.

### 6.1 Outbound (FiveM → Panel)

Der Server pollt in `Config.Panel.syncIntervalMinutes` diese Endpunkte:

```
GET  {apiUrl}/settings    → { branding:{…}, features:{…}, notice:{text} }
GET  {apiUrl}/insurance   → { tiers:[ { tier_key,label,description,color,icon,
                                        weekly_premium,coverage_pct,max_per_invoice,
                                        weekly_cap,active,min_term_days,
                                        cancel_notice_days,waiting_days }, … ] }
GET  {apiUrl}/pricelist   → { items:[ { code,label,description,price,required_perm,active }, … ] }
```

Empfangene Werte werden per UPSERT in die DB übernommen (Panel gewinnt). Schlägt ein Aufruf
fehl, bleibt der zuletzt gespeicherte DB-Stand aktiv (`onOutage='last_known'`), und
`mt_sync_state` protokolliert `last_ok=0` + Fehler.

**Header jeder ausgehenden Anfrage:**

```
Authorization: Bearer <apiKey>
X-Timestamp: <unix-seconds>
X-Nonce: <zufällig>
X-Signature: HMAC_SHA256(hmacSecret, timestamp + nonce + METHOD + path + body)   (hex)
Content-Type: application/json
```

### 6.2 Inbound (Panel → FiveM)

Optional (`Config.Panel.inbound.enabled`). FiveM stellt über `SetHttpHandler` bereit:

```
POST /trigger-sync    → sofortiger Pull aller Bereiche; Antwort { ok:true }
```

Eingehende Anfragen **müssen** dieselbe Signatur mitsenden. Prüfung:
- `X-Timestamp` innerhalb `maxSkewSeconds` (Replay-Schutz),
- `X-Signature` == erwartete HMAC. Sonst `401` + Audit-Eintrag (`panel.inbound.denied`).

URL des Handlers: `http://<server-ip>:<port>/medictablet/trigger-sync`
(FiveM-Ressourcen-HTTP-Endpunkt).

### 6.3 Konfigurierbare Werte

`apiUrl`, `apiKey`, `hmacSecret`, `syncIntervalMinutes`, `timeoutMs`, `maxRetries`,
`retryBackoffMs`, `onOutage`, feingranular `sync.{settings,pricelist,insurance,auditPush}`.

---

## 7. Sicherheitsmaßnahmen

- **Serverseitige Autorität:** jede sensible Aktion prüft Rechte serverseitig; Client-Checks
  sind nur UX. Versicherungsberechnung ausschließlich serverseitig (nicht manipulierbar).
- **Permanenter Identifier:** Akten hängen an `identifier`, nie an der Server-ID. Die Server-ID
  dient nur zur Erkennung eines aktuell verbundenen Spielers.
- **SQL-Injection:** ausschließlich parametrisierte Queries (`server/db.lua`).
- **Manipulierte NUI-Callbacks / Events:** ein einziger Eingangspunkt, Rate-Limit, Identitäts-
  und Rechteprüfung; unbekannte Actions werden geloggt und abgewiesen.
- **Doppel-Absenden:** Rechnungen über `idempotency_key` + In-Memory-Lock; Beiträge über
  `UNIQUE(identifier, week_key)`.
- **Rate-Limits:** `Config.Security.rateLimit` (Fenster/Anzahl je Spieler).
- **Panel:** HMAC-SHA256-signierte, zeitlich begrenzte Anfragen; Secrets nur serverseitig;
  Kommunikation nur serverseitig; Ausfall-Resilienz + Auto-Resync.
- **Keine fest eingebauten Zugangsdaten**, keine erfundenen Exports/Events.
- **Audit-Log** für alle wichtigen Änderungen, optional Discord-Webhooks (serverseitig).

---

## 8. Fehlerbehandlung (Locale-Schlüssel → Anzeige)

| Schlüssel | Bedeutung |
|-----------|-----------|
| `no_permission` | Fehlende Berechtigung |
| `not_allowed_job` | Job nicht freigeschaltet |
| `user_locked` | Zugriff gesperrt |
| `rate_limited` | Zu viele Anfragen |
| `invalid_input` | Ungültige Eingabe |
| `db_error` | Datenbankfehler |
| `patient_offline` | Patient nicht online |
| `player_not_found` | Spieler/Charakter nicht gefunden |
| `billing_down` | CodeM Billing V2 nicht gestartet / kein Mapping |
| `invoice_failed` | Rechnung konnte nicht erstellt werden |
| `invalid_amount` | Ungültiger Rechnungsbetrag |
| `invoice_duplicate` | Rechnung evtl. bereits erstellt |
| `ins_insufficient` | Nicht genug Guthaben |
| `ins_waiting` / `ins_paused` / `ins_none` | Kein aktiver Versicherungsschutz |

Server-Logs sind farbcodiert (`[medictablet]`): grün = Info, gelb = Warnung, rot = Fehler.
Handler-Ausnahmen werden abgefangen (pcall) und führen nie zum Ressourcencrash.
