--[[
    Billing-Adapter-Selector.
    Waehlt den konfigurierten Provider und faellt bei Bedarf auf ESX zurueck,
    damit eine Rechnung nie "verloren" geht. Gibt den effektiv genutzten
    Provider-Namen zurueck (wird an der Rechnung gespeichert).
]]

MT = MT or {}
MT.Billing = {}

function MT.Billing.getAdapter()
    local wanted = Config.Billing.provider
    local a = MT.BillingAdapters[wanted]
    if a and a.isAvailable() then
        return a
    end
    if Config.Billing.fallbackToESX then
        local esx = MT.BillingAdapters['esx']
        if esx and esx.isAvailable() then
            if wanted ~= 'esx' then
                MT.Util.warn(('Billing-Provider "%s" nicht verfuegbar -> Fallback auf ESX.'):format(tostring(wanted)))
            end
            return esx
        end
    end
    return nil
end

--[[ Erstellt eine Rechnung. Rueckgabe:
       ok(boolean), resultOrErrKey
       result = { providerInvoiceId, provider }
]]
function MT.Billing.createInvoice(inv)
    local a = MT.Billing.getAdapter()
    if not a then
        return false, 'billing_down'
    end
    local ok, res = a.createInvoice(inv)
    if not ok then
        return false, res -- errKey
    end
    res.provider = a.name
    return true, res
end
