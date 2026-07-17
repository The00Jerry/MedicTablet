--[[
    Server-Core: ESX-Init, sicherer Dispatcher, Handler-Registry, Seeding, Exports.
    Selbst-Aktionen (eigene Wallet) sind fuer jeden Spieler erlaubt; Verwaltungsaktionen
    erfordern ein Recht (opts.perm), das serverseitig geprueft wird.
]]

WL = WL or {}

local _esx
function WL.getESX()
    if _esx then return _esx end
    if GetResourceState(Config.ESXResource) ~= 'started' then return nil end
    local ok, obj = pcall(function() return exports[Config.ESXResource]:getSharedObject() end)
    if ok then _esx = obj end
    return _esx
end

function WL.discordOf(src)
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do if id:sub(1, 8) == 'discord:' then return id:sub(9) end end
    return ''
end

function WL.buildCtx(src)
    local ESX = WL.getESX(); if not ESX then return nil, 'db_error' end
    local xp = ESX.GetPlayerFromId(src); if not xp then return nil, 'player_not_found' end
    local ctx = { src = src, identifier = xp.identifier, name = xp.getName and xp.getName() or (xp.name or ('ID ' .. src)),
        job = xp.job and xp.job.name or '', grade = xp.job and xp.job.grade or 0, discord = WL.discordOf(src), xp = xp }
    ctx.perms = WL.Perms.effective(ctx.identifier, ctx.job, ctx.grade)
    ctx.can = function(perm) return WL.Perms.has(ctx.perms, perm) end
    return ctx
end

WL.Handlers = {}
function WL.register(action, opts, fn) WL.Handlers[action] = { opts = opts or {}, fn = fn } end

RegisterNetEvent('lswallet:sv:request', function(reqId, action, data)
    local src = source
    local function respond(ok, payload) TriggerClientEvent('lswallet:cl:response', src, reqId, ok, payload) end
    if not WL.RateLimit.check(src) then return respond(false, { error = WL.L('rate_limited') }) end
    local handler = WL.Handlers[action]
    if not handler then return respond(false, { error = WL.L('invalid_input') }) end
    local ctx, err = WL.buildCtx(src)
    if not ctx then return respond(false, { error = WL.L(err or 'player_not_found') }) end
    if handler.opts.perm and not ctx.can(handler.opts.perm) then
        WL.Audit.log(ctx, { category = 'security', action = 'perm.denied', result = 'denied', reason = action })
        return respond(false, { error = WL.L('no_permission') })
    end
    local ok, res = pcall(function() return handler.fn(ctx, data or {}) end)
    if not ok then WL.Util.err('Handler', action, ':', tostring(res)); return respond(false, { error = WL.L('db_error') }) end
    if type(res) == 'table' and res.__err then return respond(false, { error = WL.L(res.__err) }) end
    return respond(true, res or {})
end)

function WL.fail(key) return { __err = key } end

-- Item-basiertes Oeffnen
CreateThread(function()
    local tries = 0
    while not WL.getESX() and tries < 100 do Wait(200); tries = tries + 1 end
    if not WL.getESX() then WL.Util.err('ESX nicht gefunden – Wallet inaktiv.'); return end

    -- Seeds
    if WL.DB.isEmpty('lw_permissions') then
        for job, grades in pairs(Config.Perms.Grades) do
            for grade, list in pairs(grades) do
                for _, perm in ipairs(list) do WL.DB.insert('INSERT IGNORE INTO lw_permissions (job, grade, perm) VALUES (?,?,?)', { job, grade, perm }) end
            end
        end
        WL.Util.log('Berechtigungen geseedet.')
    end
    if WL.DB.isEmpty('lw_templates') then
        local function ins(t) WL.DB.insert('INSERT IGNORE INTO lw_templates (tkey, ctype, label, config, created_by) VALUES (?,?,?,?,?)', { t.key, t.type, t.label, json.encode(t), 'SEED' }) end
        for _, t in ipairs(Config.Templates.Cards) do ins(t) end
        for _, t in ipairs(Config.Templates.Tickets) do ins(t) end
        WL.Util.log('Vorlagen geseedet.')
    end

    if Config.Open.item.enabled then
        local ESX = WL.getESX()
        if ESX and ESX.RegisterUsableItem then
            ESX.RegisterUsableItem(Config.Open.item.name, function(s) TriggerClientEvent('lswallet:cl:open', s) end)
        end
    end
    WL.Util.log('DOL Wallet bereit.')
end)

-----------------------------------------------------------------------------
-- Oeffentliche Exports (fuer andere Ressourcen)
-----------------------------------------------------------------------------
exports('GetCards', function(identifier) return WL.Wallet and WL.Wallet.getCards(identifier) or {} end)
exports('HasCard', function(identifier, ctype)
    return tonumber(WL.DB.scalar('SELECT COUNT(*) FROM lw_cards WHERE identifier = ? AND ctype = ? AND revoked = 0', { identifier, ctype })) > 0
end)
exports('GiveCard', function(identifier, ctype, templateKey, data, issuedBy)
    return WL.Wallet and WL.Wallet.issue(identifier, ctype, templateKey, data or {}, { identifier = issuedBy or 'SYSTEM', name = issuedBy or 'System' })
end)
-- exports['lswallet']:SetCardProperty(cardId, propertyName, value)
exports('SetCardProperty', function(cardId, property, value)
    local card = WL.DB.single('SELECT data FROM lw_cards WHERE id = ?', { tonumber(cardId) })
    if not card then return false end
    local d = card.data and json.decode(card.data) or {}
    d[tostring(property)] = value
    return WL.DB.update('UPDATE lw_cards SET data = ? WHERE id = ?', { json.encode(d), tonumber(cardId) }) > 0
end)
exports('RevokeCard', function(cardId)
    return WL.DB.update('UPDATE lw_cards SET revoked = 1 WHERE id = ?', { tonumber(cardId) }) > 0
end)
-- exports['lswallet']:HasLicense(identifier, esxType)  -> boolean (echte ESX-Lizenz)
exports('HasLicense', function(identifier, esxType) return WL.License and WL.License.has(identifier, esxType) or false end)
