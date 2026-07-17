--[[
    Billing-Adapter: CodeM Billing V2 (konfigurierbar gemappt).
    KEINE Exports/Events fest angenommen – Werte kommen aus Config.Billing.codem.
    Siehe README (Abschnitt CodeM Billing V2). Ohne Mapting -> isAvailable() = false.
]]

PD = PD or {}
PD.BillingAdapters = PD.BillingAdapters or {}

local CodeM = { name = 'codem' }
local function cfg() return Config.Billing.codem end

function CodeM.isAvailable()
    local c = cfg()
    if not c or not c.resource or c.resource == '' then return false end
    if GetResourceState(c.resource) ~= 'started' then return false end
    if c.useExport and c.exportName and c.exportName ~= '' then return true end
    if c.useEvent and c.eventName and c.eventName ~= '' then return true end
    return false
end

local function buildPayload(inv)
    local f = cfg().fields
    local p = {}
    p[f.targetIdentifier] = inv.targetIdentifier
    p[f.senderIdentifier] = inv.officerIdentifier
    p[f.society]          = inv.society or Config.Billing.society
    p[f.label]            = inv.label
    p[f.amount]           = math.floor(tonumber(inv.amount) or 0)
    p[f.reason]           = inv.reason or ''
    return p
end

function CodeM.createInvoice(inv)
    local amount = math.floor(tonumber(inv.amount) or 0)
    if amount <= 0 then return false, 'invalid_amount' end
    if not CodeM.isAvailable() then return false, 'billing_down' end
    local c = cfg()
    local payload = buildPayload(inv)

    if c.useExport and c.exportName ~= '' then
        local ok, ret = pcall(function() return exports[c.resource][c.exportName](payload) end)
        if not ok then PD.Util.err('CodeM Export:', tostring(ret)); return false, 'invoice_failed' end
        if ret == false then return false, 'invoice_failed' end
        local id = (type(ret) == 'table' and (ret.id or ret.invoiceId)) or (type(ret) == 'string' and ret)
            or (type(ret) == 'number' and tostring(ret)) or PD.Util.genId('CODEM')
        return true, { providerInvoiceId = tostring(id) }
    end
    if c.useEvent and c.eventName ~= '' then
        local ok, err = pcall(function() TriggerEvent(c.eventName, payload) end)
        if not ok then PD.Util.err('CodeM Event:', tostring(err)); return false, 'invoice_failed' end
        return true, { providerInvoiceId = PD.Util.genId('CODEM') }
    end
    return false, 'billing_down'
end

PD.BillingAdapters['codem'] = CodeM
