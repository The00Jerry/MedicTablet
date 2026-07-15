--[[
    Billing-Adapter: ESX Bank/Society (Fallback).

    Verhalten: Der endgueltige Patientenbetrag wird direkt vom Bankkonto des
    ONLINE-Patienten abgebucht und der Medic-Society gutgeschrieben.
    Ist der Patient offline, wird 'patient_offline' zurueckgegeben (ESX bietet
    ohne Zusatzressource keine Offline-Rechnungswarteschlange – hier wird
    bewusst NICHTS erfunden).

    Adapter-Vertrag (identisch fuer alle Billing-Adapter):
      isAvailable() -> boolean
      createInvoice(inv) -> ok(boolean), resultOrErrKey
        inv = {
          targetIdentifier, medicIdentifier, society, label, amount, reason
        }
        result = { providerInvoiceId = string }
]]

MT = MT or {}
MT.BillingAdapters = MT.BillingAdapters or {}

local ESXBilling = {}
ESXBilling.name = 'esx'

function ESXBilling.isAvailable()
    return GetResourceState(Config.ESXResource) == 'started'
end

function ESXBilling.createInvoice(inv)
    local amount = math.floor(tonumber(inv.amount) or 0)
    if amount <= 0 then
        return false, 'invalid_amount'
    end

    local xp = MT.Account.getOnline(inv.targetIdentifier)
    if not xp then
        return false, 'patient_offline'
    end

    -- Patient zahlt vom Bankkonto
    local ok, errKey = MT.Account.charge(inv.targetIdentifier, 'bank', amount)
    if not ok then
        -- ins_insufficient / db_error / player_not_found -> als invoice_failed nach oben
        return false, errKey or 'invoice_failed'
    end

    -- Society gutschreiben (best effort; ohne esx_addonaccount wird nur geloggt)
    local society = inv.society or Config.Billing.society
    local credited = MT.Account.creditSociety(('society_%s'):format(society), amount)
    if not credited then
        MT.Util.dbg('ESX-Billing: Society-Gutschrift uebersprungen (kein Addonaccount).')
    end

    local providerId = MT.Util.genId('ESXINV')
    return true, { providerInvoiceId = providerId }
end

MT.BillingAdapters['esx'] = ESXBilling
