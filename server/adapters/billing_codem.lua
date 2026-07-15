--[[
    Billing-Adapter: CodeM Billing V2 (konfigurierbar gemappt).

    >>> WICHTIG <<<
    Es werden KEINE Exports/Events fest angenommen. Aufrufart, Namen und
    Payload-Felder kommen aus Config.Billing.codem. Trage dort die ECHTEN Werte
    deiner CodeM-Billing-V2-Ressource ein (Export- ODER Event-Variante).

    So findest du die richtigen Werte:
      1. Oeffne den Ordner deiner CodeM-Billing-V2-Ressource.
      2. Suche in server/*.lua nach 'exports(' bzw. 'RegisterNetEvent(' /
         'AddEventHandler(' fuer das Erstellen einer Rechnung.
      3. Trage Ressourcenname + Export-/Eventname + die erwarteten Payload-Felder
         in Config.Billing.codem ein.
      4. Schicke mir bei Unsicherheit fxmanifest.lua + die betroffene server-Datei,
         dann fuelle ich das Mapping exakt aus.

    Solange nichts eingetragen ist, meldet isAvailable() = false und (bei
    Config.Billing.fallbackToESX = true) uebernimmt der ESX-Adapter.
]]

MT = MT or {}
MT.BillingAdapters = MT.BillingAdapters or {}

local CodeM = {}
CodeM.name = 'codem'

local function cfg() return Config.Billing.codem end

function CodeM.isAvailable()
    local c = cfg()
    if not c or not c.resource or c.resource == '' then return false end
    if GetResourceState(c.resource) ~= 'started' then return false end
    if c.useExport and c.exportName and c.exportName ~= '' then return true end
    if c.useEvent and c.eventName and c.eventName ~= '' then return true end
    return false
end

-- Baut das Payload mit den in der Config hinterlegten Feldnamen
local function buildPayload(inv)
    local f = cfg().fields
    local p = {}
    p[f.targetIdentifier] = inv.targetIdentifier
    p[f.senderIdentifier] = inv.medicIdentifier
    p[f.society]          = inv.society or Config.Billing.society
    p[f.label]            = inv.label
    p[f.amount]           = math.floor(tonumber(inv.amount) or 0)
    p[f.reason]           = inv.reason or ''
    return p
end

function CodeM.createInvoice(inv)
    local amount = math.floor(tonumber(inv.amount) or 0)
    if amount <= 0 then
        return false, 'invalid_amount'
    end
    if not CodeM.isAvailable() then
        return false, 'billing_down'
    end

    local c = cfg()
    local payload = buildPayload(inv)

    -- Variante A: Export
    if c.useExport and c.exportName ~= '' then
        local ok, ret = pcall(function()
            return exports[c.resource][c.exportName](payload)
        end)
        if not ok then
            MT.Util.err('CodeM Export-Aufruf fehlgeschlagen:', tostring(ret))
            return false, 'invoice_failed'
        end
        -- CodeM koennte eine Rechnungs-ID zurueckgeben; sonst interne ID erzeugen
        local providerId = (type(ret) == 'table' and (ret.id or ret.invoiceId))
            or (type(ret) == 'string' and ret)
            or (type(ret) == 'number' and tostring(ret))
            or MT.Util.genId('CODEM')
        if ret == false then
            return false, 'invoice_failed'
        end
        return true, { providerInvoiceId = tostring(providerId) }
    end

    -- Variante B: Server-Event (fire-and-forget). Interne ID als Referenz.
    if c.useEvent and c.eventName ~= '' then
        local ok, err = pcall(function()
            TriggerEvent(c.eventName, payload)
        end)
        if not ok then
            MT.Util.err('CodeM Event-Aufruf fehlgeschlagen:', tostring(err))
            return false, 'invoice_failed'
        end
        return true, { providerInvoiceId = MT.Util.genId('CODEM') }
    end

    return false, 'billing_down'
end

MT.BillingAdapters['codem'] = CodeM
