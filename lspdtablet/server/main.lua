--[[
    Server-Core: ESX-Init, sicherer Request-Dispatcher, Handler-Registry, Seeding.
    Client/NUI senden nur { action, data } an lspd:sv:request; der Dispatcher prueft
    Rate-Limit, Identitaet (permanenter Identifier), Job, Sperre und Berechtigung
    SERVERSEITIG, bevor ein Handler laeuft. Antwort per requestId.
]]

PD = PD or {}

local _esx
function PD.getESX()
    if _esx then return _esx end
    if GetResourceState(Config.ESXResource) ~= 'started' then return nil end
    local ok, obj = pcall(function() return exports[Config.ESXResource]:getSharedObject() end)
    if ok then _esx = obj end
    return _esx
end

function PD.discordOf(src)
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:sub(1, 8) == 'discord:' then return id:sub(9) end
    end
    return ''
end

function PD.buildCtx(src)
    local ESX = PD.getESX()
    if not ESX then return nil, 'db_error' end
    local xp = ESX.GetPlayerFromId(src)
    if not xp then return nil, 'player_not_found' end
    local ctx = {
        src = src, identifier = xp.identifier,
        name = xp.getName and xp.getName() or (xp.name or ('ID ' .. src)),
        job = xp.job and xp.job.name or '', grade = xp.job and xp.job.grade or 0,
        onDuty = xp.job and (xp.job.onDuty ~= false) or true,
        discord = PD.discordOf(src),
    }
    ctx.perms = PD.Perms.effective(ctx.identifier, ctx.job, ctx.grade)
    ctx.can = function(perm) return PD.Perms.has(ctx.perms, perm) end
    return ctx
end

PD.Handlers = {}
function PD.register(action, opts, fn) PD.Handlers[action] = { opts = opts or {}, fn = fn } end
local function featureEnabled(feature) if not feature then return true end return Config.Features[feature] ~= false end

RegisterNetEvent('lspd:sv:request', function(reqId, action, data)
    local src = source
    local function respond(ok, payload) TriggerClientEvent('lspd:cl:response', src, reqId, ok, payload) end

    if not Config.Features.tabletEnabled then return respond(false, { error = PD.L('tablet_disabled') }) end
    if not PD.RateLimit.check(src) then return respond(false, { error = PD.L('rate_limited') }) end

    local handler = PD.Handlers[action]
    if not handler then PD.Util.warn('Unbekannte Action von', src, ':', tostring(action)); return respond(false, { error = PD.L('invalid_input') }) end

    local ctx, err = PD.buildCtx(src)
    if not ctx then return respond(false, { error = PD.L(err or 'player_not_found') }) end
    if not featureEnabled(handler.opts.feature) then return respond(false, { error = PD.L('tablet_disabled') }) end
    if PD.Perms.isLocked(ctx.identifier) then
        PD.Audit.log(ctx, { category = 'security', action = 'access.locked', result = 'denied', reason = action })
        return respond(false, { error = PD.L('user_locked') })
    end

    local allowed = false
    for _, j in ipairs(Config.Perms.AllowedJobs) do if j == ctx.job then allowed = true break end end
    if not allowed then
        PD.Audit.log(ctx, { category = 'security', action = 'access.job', result = 'denied', reason = action })
        return respond(false, { error = PD.L('not_allowed_job') })
    end
    if Config.Security.requireOnDuty and not ctx.onDuty then return respond(false, { error = PD.L('not_on_duty') }) end

    if handler.opts.perm and not ctx.can(handler.opts.perm) then
        PD.Audit.log(ctx, { category = 'security', action = 'perm.denied', result = 'denied', reason = action .. ' (' .. handler.opts.perm .. ')' })
        return respond(false, { error = PD.L('no_permission') })
    end

    local ok, res = pcall(function() return handler.fn(ctx, data or {}) end)
    if not ok then PD.Util.err('Handler-Fehler', action, ':', tostring(res)); return respond(false, { error = PD.L('db_error') }) end
    if type(res) == 'table' and res.__err then return respond(false, { error = PD.L(res.__err) }) end
    return respond(true, res or {})
end)

function PD.fail(key) return { __err = key } end

-- Oeffentliche Exports (lesend)
exports('HasPermission', function(identifier, job, grade, perm)
    return PD.Perms.has(PD.Perms.effective(identifier, job or '', tonumber(grade) or 0), perm)
end)
exports('IsWanted', function(identifier)
    return tonumber(PD.DB.scalar('SELECT is_wanted FROM pd_citizens WHERE identifier = ?', { identifier })) == 1
end)

-----------------------------------------------------------------------------
-- Seeding
-----------------------------------------------------------------------------
local function seedPermissions()
    if not PD.DB.isEmpty('pd_permissions') then return end
    for job, grades in pairs(Config.Perms.Grades) do
        for grade, list in pairs(grades) do
            for _, perm in ipairs(list) do
                PD.DB.insert('INSERT IGNORE INTO pd_permissions (job, grade, perm) VALUES (?,?,?)', { job, grade, perm })
            end
        end
    end
    PD.Util.log('Berechtigungen geseedet.')
end

local function seedPenal()
    if not PD.DB.isEmpty('pd_penal_categories') then return end
    local catId = {}
    for _, c in ipairs(Config.PenalSeed.Categories) do
        catId[c.key] = PD.DB.insert('INSERT INTO pd_penal_categories (cat_key,label,sort) VALUES (?,?,?)', { c.key, c.label, c.sort })
    end
    for _, o in ipairs(Config.PenalSeed.Offenses) do
        PD.DB.insert([[INSERT INTO pd_penal_offenses (code,label,description,category_id,fine,jail,points,required_perm,created_by,updated_by)
            VALUES (?,?,?,?,?,?,?,?,?,?)]],
            { o.code, o.label, o.desc or '', catId[o.category], o.fine, o.jail, o.points, o.perm or '', 'SEED', 'SEED' })
    end
    PD.Util.log('Strafenkatalog geseedet.')
end

local function seedSettings()
    local function ensure(key, tbl)
        if not PD.DB.scalar('SELECT 1 FROM pd_settings WHERE skey = ?', { key }) then
            PD.DB.insert('INSERT INTO pd_settings (skey, svalue, updated_by) VALUES (?,?,?)', { key, json.encode(tbl), 'SEED' })
        end
    end
    ensure('branding', Config.Branding)
    ensure('features', Config.Features)
end

CreateThread(function()
    local tries = 0
    while not PD.getESX() and tries < 100 do Wait(200); tries = tries + 1 end
    if not PD.getESX() then PD.Util.err('ESX nicht gefunden – MDT inaktiv.'); return end
    seedPermissions(); seedPenal(); seedSettings()

    if Config.Open.item.enabled then
        local ESX = PD.getESX()
        if ESX and ESX.RegisterUsableItem then
            ESX.RegisterUsableItem(Config.Open.item.name, function(src) TriggerClientEvent('lspd:cl:open', src) end)
            PD.Util.log('Nutzbares Item registriert:', Config.Open.item.name)
        end
    end
    PD.Util.log('LSPD MDT bereit. Provider:', Config.Billing.provider)
end)
