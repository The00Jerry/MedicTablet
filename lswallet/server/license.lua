--[[
    ESX-Lizenz-Adapter.
    Setzt/entfernt die ECHTE ESX-Lizenz (Fuehrerschein etc.), damit andere Systeme sie
    erkennen. Backend konfigurierbar (Config.Licenses.provider):
      'user_licenses' -> Standardtabelle user_licenses (esx_license)
      'users_json'    -> users.<col> als JSON-Map { drive=true, ... }
      'none'          -> keine echte Lizenz (nur Wallet-Karte)

    Es werden KEINE fremden Exports/Events angenommen – die Integration erfolgt ueber die
    dokumentierte ESX-Datenbankstruktur. esx_license liest diese Tabelle bei Bedarf.
]]

WL = WL or {}
WL.License = {}

local function C() return Config.Licenses end

local function jsonGet(identifier)
    local raw = WL.DB.scalar(('SELECT `%s` FROM users WHERE identifier = ?'):format(C().usersJsonCol), { identifier })
    local t = {}
    if raw then local ok, d = pcall(function() return json.decode(raw) end); if ok and type(d) == 'table' then t = d end end
    return t
end
local function jsonSet(identifier, t)
    WL.DB.update(('UPDATE users SET `%s` = ? WHERE identifier = ?'):format(C().usersJsonCol), { json.encode(t), identifier })
end

function WL.License.grant(identifier, esxType)
    if not esxType or esxType == '' then return end
    local p = C().provider
    if p == 'user_licenses' then
        WL.DB.insert(('INSERT IGNORE INTO `%s` (`%s`, `%s`) VALUES (?, ?)'):format(C().table, C().typeCol, C().ownerCol), { esxType, identifier })
    elseif p == 'users_json' then
        local t = jsonGet(identifier); t[esxType] = true; jsonSet(identifier, t)
    end
end

function WL.License.revoke(identifier, esxType)
    if not esxType or esxType == '' then return end
    local p = C().provider
    if p == 'user_licenses' then
        WL.DB.update(('DELETE FROM `%s` WHERE `%s` = ? AND `%s` = ?'):format(C().table, C().typeCol, C().ownerCol), { esxType, identifier })
    elseif p == 'users_json' then
        local t = jsonGet(identifier); t[esxType] = nil; jsonSet(identifier, t)
    end
end

-- Liste der ESX-Lizenztypen, die der Charakter aktuell besitzt
function WL.License.list(identifier)
    local p = C().provider
    local out = {}
    if p == 'user_licenses' then
        local exists = WL.DB.scalar("SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?", { C().table })
        if not exists then return out end
        local rows = WL.DB.query(('SELECT `%s` AS t FROM `%s` WHERE `%s` = ?'):format(C().typeCol, C().table, C().ownerCol), { identifier }) or {}
        for _, r in ipairs(rows) do out[#out + 1] = r.t end
    elseif p == 'users_json' then
        for k, v in pairs(jsonGet(identifier)) do if v then out[#out + 1] = k end end
    end
    return out
end

function WL.License.has(identifier, esxType)
    for _, t in ipairs(WL.License.list(identifier)) do if t == esxType then return true end end
    return false
end

-- Lizenz-Definition per key bzw. per esxType
function WL.License.defByKey(key)
    for _, d in ipairs(Config.Templates.Licenses or {}) do if d.key == key then return d end end
    return nil
end
function WL.License.defByEsxType(esxType)
    for _, d in ipairs(Config.Templates.Licenses or {}) do if d.esxType == esxType then return d end end
    return nil
end

-- Stellt eine Lizenz-KARTE aus UND setzt die echte ESX-Lizenz. return cardId | nil
function WL.License.issueCard(identifier, def, class, actor)
    local u = WL.Wallet.getUser(identifier); if not u then return nil end
    local ctype = (def.key == 'driver') and 'driver_license' or 'license'
    local data = { firstname = u.firstname, lastname = u.lastname, dateofbirth = u.dateofbirth, esxType = def.esxType, label = def.label }
    if def.class then data.class = class end
    local expiresDays = (def.key == 'driver') and Config.Cards.driverExpiryDays or 0
    local cardId = WL.Wallet.issue(identifier, ctype, def.key, data, actor, { expiresDays = expiresDays, title = def.label })
    if cardId then WL.License.grant(identifier, def.esxType) end
    return cardId
end
