# CodeM Billing V2 anbinden

Das Medic-Tablet erfindet **keine** Exports/Events. Die konkrete Schnittstelle von
CodeM Billing V2 wird über `Config.Billing.codem` (in `config/config.lua`) **gemappt**.
Solange nichts eingetragen ist, meldet der Adapter `isAvailable() = false` und – wenn
`Config.Billing.fallbackToESX = true` – übernimmt automatisch der ESX-Bank/Society-Adapter,
sodass nie eine Rechnung verloren geht.

## Schritt 1 – Aufrufart & Namen ermitteln

Öffne den Ordner deiner CodeM-Billing-V2-Ressource und suche in `server/*.lua` nach der
Funktion, die eine Rechnung erstellt. Typische Muster:

```lua
-- Variante A: Export
exports('CreateInvoice', function(data) ... end)

-- Variante B: Server-Event
RegisterNetEvent('codem-billing:server:sendInvoice')
AddEventHandler('codem-billing:server:sendInvoice', function(data) ... end)
```

Notiere: **Ressourcenname**, **Export- oder Eventname** und die **Payload-Felder**, die
CodeM erwartet (z. B. Ziel-Identifier, Absender, Society, Label, Betrag, Grund).

## Schritt 2 – Mapping eintragen

In `config/config.lua`:

```lua
Config.Billing = {
    provider      = 'codem',
    fallbackToESX = true,
    society       = 'ambulance',

    codem = {
        resource   = 'codem-billing',   -- echter Ressourcenname

        -- Variante A: Export
        useExport  = true,
        exportName = 'CreateInvoice',   -- echter Exportname

        -- Variante B: Event (statt Export)
        useEvent   = false,
        eventName  = '',

        -- Payload-Feldnamen, die CodeM erwartet (an echte Struktur anpassen)
        fields = {
            targetIdentifier = 'identifier',
            senderIdentifier = 'sender',
            society          = 'society',
            label            = 'label',
            amount           = 'amount',
            reason           = 'reason',
        },
    },
}
```

- Setze **entweder** `useExport = true` **oder** `useEvent = true` (nicht beides).
- Die `fields`-Namen sind die **Schlüssel** im Payload-Objekt, das an CodeM übergeben wird.
  Beispiel: `fields.amount = 'amount'` erzeugt `{ amount = 500 }`.

## Was das Tablet übergibt

Der Adapter (`server/adapters/billing_codem.lua`) baut aus den Feldnamen genau ein Objekt
und ruft:

```lua
-- Export-Variante:
exports[resource][exportName](payload)
-- Event-Variante:
TriggerEvent(eventName, payload)
```

**Wichtig:** An das Billing-System wird ausschließlich der **endgültige Patientenbetrag**
(`amount_final`) übergeben – der Versicherungsanteil wurde bereits serverseitig abgezogen.

### Rückgabewert (Export-Variante)

Gibt der CodeM-Export eine Rechnungs-ID zurück, wird sie als
`provider_invoice_id` gespeichert. Erkannt werden:

- ein String / eine Zahl → direkt als ID,
- eine Tabelle mit `id` oder `invoiceId`,
- `false` → wird als Fehlschlag gewertet (`invoice_failed`).

Fehlt eine ID (z. B. bei der Event-Variante), erzeugt der Adapter eine interne Referenz-ID.

## Schritt 3 – Prüfen

- CodeM-Ressource läuft? → `isAvailable()` wird `true`.
- Testrechnung im Tablet erstellen. Bei Fehler siehe Server-Log
  (`^1[medictablet]^7 CodeM …`) und Audit-Log (`invoice.create`, `result=error`).

## Fehlerbehandlung (immer verständlich)

| Situation | Rückmeldung |
|-----------|-------------|
| Patient nicht online (ESX-Fallback) | `patient_offline` |
| Spieler/Charakter nicht gefunden | `player_not_found` |
| CodeM nicht gestartet / kein Mapping | `billing_down` |
| Rechnung konnte nicht erstellt werden | `invoice_failed` |
| Ungültiger Betrag (≤ 0) | `invalid_amount` |
| Bereits erstellt (Doppelklick/Retry) | `invoice_duplicate` |
| DB-Fehler | `db_error` |
| Fehlende Berechtigung | `no_permission` |

## Anderes Rechnungssystem anbinden

Lege `server/adapters/billing_<name>.lua` an, das denselben Vertrag erfüllt:

```lua
local A = { name = 'meins' }
function A.isAvailable() return GetResourceState('meine-ressource') == 'started' end
function A.createInvoice(inv)
    -- inv = { targetIdentifier, medicIdentifier, society, label, amount, reason }
    -- return ok(boolean), { providerInvoiceId = '...' }  ODER  false, 'errKey'
end
MT.BillingAdapters['meins'] = A
```

In `fxmanifest.lua` einbinden und `Config.Billing.provider = 'meins'` setzen. Das restliche
Tablet bleibt unverändert.
