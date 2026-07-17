--[[
    Billing-Adapter: ESX Bank/Society (Fallback fuer Bussgelder).
    Bucht den Bussgeldbetrag vom Bankkonto der ONLINE-Person ab und schreibt der
    Police-Society gut. Offline -> 'patient_offline'.

    Adapter-Vertrag:
      isAvailable() -> boolean
      createInvoice(inv) -> ok(boolean), resultOrErrKey
        inv = { targetIdentifier, officerIdentifier, society, label, amount, reason }
]]

PD = PD or {}
PD.BillingAdapters = PD.BillingAdapters or {}

local ESXAdp = { name = 'esx' }

local function onlineByIdentifier(identifier)
    local ESX = PD.getESX(); if not ESX then return nil end
    if ESX.GetPlayerFromIdentifier then return ESX.GetPlayerFromIdentifier(identifier) end
    for _, src in ipairs(GetPlayers()) do
        local xp = ESX.GetPlayerFromId(tonumber(src))
        if xp and xp.identifier == identifier then return xp end
    end
    return nil
end

function ESXAdp.isAvailable()
    return GetResourceState(Config.ESXResource) == 'started'
end

function ESXAdp.createInvoice(inv)
    local amount = math.floor(tonumber(inv.amount) or 0)
    if amount <= 0 then return false, 'invalid_amount' end
    local xp = onlineByIdentifier(inv.targetIdentifier)
    if not xp then return false, 'patient_offline' end

    local acc = xp.getAccount('bank')
    if not acc or acc.money < amount then return false, 'insufficient' end
    xp.removeAccountMoney('bank', amount)

    -- Society best-effort
    if GetResourceState('esx_addonaccount') == 'started' then
        pcall(function()
            local society = exports['esx_addonaccount']:getSharedAccount(('society_%s'):format(inv.society or Config.Billing.society))
            if society then society.addMoney(amount) end
        end)
    end
    return true, { providerInvoiceId = PD.Util.genId('ESXFINE') }
end

PD.BillingAdapters['esx'] = ESXAdp
