--[[ Billing-Adapter-Selector (mit ESX-Fallback). ]]

PD = PD or {}
PD.Billing = {}

function PD.Billing.getAdapter()
    local wanted = Config.Billing.provider
    local a = PD.BillingAdapters[wanted]
    if a and a.isAvailable() then return a end
    if Config.Billing.fallbackToESX then
        local esx = PD.BillingAdapters['esx']
        if esx and esx.isAvailable() then
            if wanted ~= 'esx' then PD.Util.warn(('Billing-Provider "%s" nicht verfuegbar -> ESX-Fallback.'):format(tostring(wanted))) end
            return esx
        end
    end
    return nil
end

function PD.Billing.createInvoice(inv)
    local a = PD.Billing.getAdapter()
    if not a then return false, 'billing_down' end
    local ok, res = a.createInvoice(inv)
    if not ok then return false, res end
    res.provider = a.name
    return true, res
end
