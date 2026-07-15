--[[
    Account-Adapter (ESX Legacy) – EINZIGER Ort fuer Kontozugriffe.

    Standard: ESX Legacy speichert Konten als JSON in users.accounts
    ({ "bank": x, "money": y, "black_money": z }). Fuer ONLINE-Spieler wird die
    ESX-API (xPlayer) genutzt, fuer OFFLINE-Spieler direkt (parametrisiert) die DB.

    >>> Nutzt deine ESX-Version eine andere Struktur (z.B. separate Kontotabelle,
        esx_addonaccount, user_accounts), muss NUR diese Datei angepasst werden. <<<
]]

MT = MT or {}
MT.Account = {}

local ACCOUNTS_COLUMN = 'accounts' -- Spalte in der users-Tabelle (JSON)

-- Online-Spieler ueber permanenten Identifier finden
function MT.Account.getOnline(identifier)
    local ESX = MT.getESX()
    if not ESX then return nil end
    if ESX.GetPlayerFromIdentifier then
        return ESX.GetPlayerFromIdentifier(identifier)
    end
    -- Fallback: manuelle Suche
    for _, src in ipairs(GetPlayers()) do
        local xp = ESX.GetPlayerFromId(tonumber(src))
        if xp and xp.identifier == identifier then return xp end
    end
    return nil
end

-- Kontostand lesen (online bevorzugt, sonst DB)
function MT.Account.getBalance(identifier, account)
    local xp = MT.Account.getOnline(identifier)
    if xp then
        local acc = xp.getAccount(account)
        return acc and acc.money or 0, true
    end
    local raw = MT.DB.scalar(('SELECT `%s` FROM users WHERE identifier = ?'):format(ACCOUNTS_COLUMN), { identifier })
    if not raw then return 0, false end
    local ok, data = pcall(function() return json.decode(raw) end)
    if not ok or type(data) ~= 'table' then return 0, false end
    return tonumber(data[account]) or 0, false
end

--[[ Belastet ein Konto um amount (>0).
     Rueckgabe: ok(boolean), errKey(string|nil), online(boolean)
     Idempotenz/Doppelabbuchung wird eine Ebene hoeher (Premium week_key) verhindert. ]]
function MT.Account.charge(identifier, account, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'invalid_amount', false end

    -- ONLINE
    local xp = MT.Account.getOnline(identifier)
    if xp then
        local acc = xp.getAccount(account)
        local bal = acc and acc.money or 0
        if bal < amount then
            return false, 'ins_insufficient', true
        end
        xp.removeAccountMoney(account, amount)
        return true, nil, true
    end

    -- OFFLINE: JSON in users.accounts sicher aktualisieren
    local raw = MT.DB.scalar(('SELECT `%s` FROM users WHERE identifier = ?'):format(ACCOUNTS_COLUMN), { identifier })
    if raw == nil then
        return false, 'player_not_found', false
    end
    local ok, data = pcall(function() return json.decode(raw) end)
    if not ok or type(data) ~= 'table' then
        return false, 'db_error', false
    end
    local bal = tonumber(data[account]) or 0
    if bal < amount then
        return false, 'ins_insufficient', false
    end
    data[account] = bal - amount

    -- Bedingtes UPDATE: nur schreiben, wenn Guthaben unveraendert ausreicht (Race-Schutz)
    local affected = MT.DB.update(
        ('UPDATE users SET `%s` = ? WHERE identifier = ?'):format(ACCOUNTS_COLUMN),
        { json.encode(data), identifier }
    )
    if not affected or affected < 1 then
        return false, 'db_error', false
    end
    return true, nil, false
end

-- Gutschrift auf ein Society/Addonaccount, sofern vorhanden (fuer insurer_pays)
-- Prueft die tatsaechliche Verfuegbarkeit von esx_addonaccount, ehe gebucht wird.
function MT.Account.creditSociety(societyAccount, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'invalid_amount' end
    if GetResourceState('esx_addonaccount') ~= 'started' then
        return false, 'no_society_system'
    end
    local ok, err = pcall(function()
        local addon = exports['esx_addonaccount']:getSharedAccount(societyAccount)
        if not addon then error('society not found: ' .. tostring(societyAccount)) end
        addon.addMoney(amount)
    end)
    if not ok then
        MT.Util.warn('creditSociety fehlgeschlagen:', tostring(err))
        return false, 'db_error'
    end
    return true
end
