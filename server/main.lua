--[[
    Server-Core: ESX-Init, sicherer Request-Dispatcher, Handler-Registry, Seeding.

    Sicherheitsprinzip:
      * NUI/Client rufen NIE direkt DB oder Billing auf. Sie senden EIN Event
        (medictablet:sv:request) mit action + data. Der Dispatcher prueft
        Rate-Limit, Identitaet, Job, Sperre und Berechtigung SERVERSEITIG,
        bevor irgendein Handler laeuft. Die Antwort geht per requestId zurueck.
]]

MT = MT or {}

-- ESX lazy accessor (memoisiert). Adapter/Handler rufen dies zur Laufzeit.
local _esx
function MT.getESX()
    if _esx then return _esx end
    if GetResourceState(Config.ESXResource) ~= 'started' then return nil end
    local ok, obj = pcall(function()
        return exports[Config.ESXResource]:getSharedObject()
    end)
    if ok then _esx = obj end
    return _esx
end

-----------------------------------------------------------------------------
-- Identitaet
-----------------------------------------------------------------------------
function MT.discordOf(src)
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:sub(1, 8) == 'discord:' then return id:sub(9) end
    end
    return ''
end

-- Baut den Kontext eines anfragenden Spielers (server-authoritativ)
function MT.buildCtx(src)
    local ESX = MT.getESX()
    if not ESX then return nil, 'db_error' end
    local xp = ESX.GetPlayerFromId(src)
    if not xp then return nil, 'player_not_found' end

    local ctx = {
        src        = src,
        identifier = xp.identifier,
        name       = xp.getName and xp.getName() or (xp.name or ('ID ' .. src)),
        job        = xp.job and xp.job.name or '',
        grade      = xp.job and xp.job.grade or 0,
        onDuty     = xp.job and (xp.job.onDuty ~= false) or true,
        discord    = MT.discordOf(src),
    }
    ctx.perms = MT.Perms.effective(ctx.identifier, ctx.job, ctx.grade)
    ctx.can = function(perm) return MT.Perms.has(ctx.perms, perm) end
    return ctx
end

-----------------------------------------------------------------------------
-- Handler-Registry
-----------------------------------------------------------------------------
MT.Handlers = {}

--[[ action  : string
     opts    : { perm = 'xxx' (optional), feature = 'invoicing' (optional),
                 open = true (falls kein tablet.open noetig, z.B. Versicherungs-NPC) }
     fn(ctx, data) -> ok(boolean), payloadOrErrKey ]]
function MT.register(action, opts, fn)
    MT.Handlers[action] = { opts = opts or {}, fn = fn }
end

local function featureEnabled(feature)
    if not feature then return true end
    return Config.Features[feature] ~= false
end

RegisterNetEvent('medictablet:sv:request', function(reqId, action, data)
    local src = source
    local function respond(ok, payload)
        TriggerClientEvent('medictablet:cl:response', src, reqId, ok, payload)
    end

    -- Master-Schalter
    if not Config.Features.tabletEnabled then
        return respond(false, { error = MT.L('tablet_disabled') })
    end

    -- Rate-Limit
    if not MT.RateLimit.check(src) then
        return respond(false, { error = MT.L('rate_limited') })
    end

    local handler = MT.Handlers[action]
    if not handler then
        MT.Util.warn('Unbekannte Action von src', src, ':', tostring(action))
        return respond(false, { error = MT.L('invalid_input') })
    end

    -- Identitaet
    local ctx, err = MT.buildCtx(src)
    if not ctx then
        return respond(false, { error = MT.L(err or 'player_not_found') })
    end

    -- Feature aktiv?
    if not featureEnabled(handler.opts.feature) then
        return respond(false, { error = MT.L('tablet_disabled') })
    end

    -- Sperre
    if MT.Perms.isLocked(ctx.identifier) then
        MT.Audit.log(ctx, { category = 'security', action = 'access.locked', result = 'denied', reason = action })
        return respond(false, { error = MT.L('user_locked') })
    end

    -- Basis: erlaubter Job (ausser explizit 'open=true' fuer NPC-Aktionen)
    if not handler.opts.open then
        local allowed = false
        for _, j in ipairs(Config.Perms.AllowedJobs) do if j == ctx.job then allowed = true break end end
        if not allowed then
            MT.Audit.log(ctx, { category = 'security', action = 'access.job', result = 'denied', reason = action })
            return respond(false, { error = MT.L('not_allowed_job') })
        end
        if Config.Security.requireOnDuty and not ctx.onDuty then
            return respond(false, { error = MT.L('not_on_duty') })
        end
    end

    -- Berechtigung
    if handler.opts.perm and not ctx.can(handler.opts.perm) then
        MT.Audit.log(ctx, { category = 'security', action = 'perm.denied', result = 'denied', reason = action .. ' (' .. handler.opts.perm .. ')' })
        return respond(false, { error = MT.L('no_permission') })
    end

    -- Handler ausfuehren (geschuetzt)
    local ok, res = pcall(function() return handler.fn(ctx, data or {}) end)
    if not ok then
        MT.Util.err('Handler-Fehler bei', action, ':', tostring(res))
        return respond(false, { error = MT.L('db_error') })
    end

    -- res-Konvention: erstes Rueckgabeelement = handlerOk; hier ist ok=true (pcall),
    -- daher pruefen wir die eigentliche Handler-Antwort:
    local handlerOk, payload = res, nil
    if type(res) == 'table' and res.__err then
        return respond(false, { error = MT.L(res.__err) })
    end
    return respond(true, res or {})
end)

-- Bequeme Fehlerrueckgabe fuer Handler: return MT.fail('key')
function MT.fail(key) return { __err = key } end

-----------------------------------------------------------------------------
-- Oeffentliche Server-Exports (fuer andere Ressourcen; nur lesend/berechnend)
-----------------------------------------------------------------------------
-- exports['medictablet']:HasPermission(identifier, job, grade, perm) -> boolean
exports('HasPermission', function(identifier, job, grade, perm)
    local set = MT.Perms.effective(identifier, job or '', tonumber(grade) or 0)
    return MT.Perms.has(set, perm)
end)

-- exports['medictablet']:CalcInsurance(identifier, baseAmount) -> snapshot table
exports('CalcInsurance', function(identifier, base)
    return MT.Insurance and MT.Insurance.calc(identifier, base) or nil
end)

-- exports['medictablet']:GetInsuranceContract(identifier) -> view table
exports('GetInsuranceContract', function(identifier)
    return MT.Insurance and MT.Insurance.getContractView(identifier) or nil
end)

-- exports['medictablet']:IsInsuranceCovered(identifier) -> boolean
exports('IsInsuranceCovered', function(identifier)
    if not MT.Insurance then return false end
    local c = MT.Insurance.getContract(identifier)
    local ok = MT.Insurance.isCovered(c)
    return ok
end)

-----------------------------------------------------------------------------
-- Seeding beim ersten Start
-----------------------------------------------------------------------------
local function seedPermissions()
    if not MT.DB.isEmpty('mt_permissions') then return end
    for job, grades in pairs(Config.Perms.Grades) do
        for grade, list in pairs(grades) do
            for _, perm in ipairs(list) do
                MT.DB.insert('INSERT IGNORE INTO mt_permissions (job, grade, perm) VALUES (?,?,?)', { job, grade, perm })
            end
        end
    end
    MT.Util.log('Berechtigungen aus Config geseedet.')
end

local function seedPricelist()
    if not MT.DB.isEmpty('mt_pricelist_categories') then return end
    local catId = {}
    for _, c in ipairs(Config.PricelistSeed.Categories) do
        local id = MT.DB.insert('INSERT INTO mt_pricelist_categories (cat_key,label,sort) VALUES (?,?,?)', { c.key, c.label, c.sort })
        catId[c.key] = id
    end
    for _, it in ipairs(Config.PricelistSeed.Items) do
        MT.DB.insert([[INSERT INTO mt_pricelist_items
            (code,label,description,category_id,price,required_perm,created_by,updated_by)
            VALUES (?,?,?,?,?,?,?,?)]],
            { it.code, it.label, it.desc or '', catId[it.category], it.price, it.perm or '', 'SEED', 'SEED' })
    end
    MT.Util.log('Preisliste aus Config geseedet.')
end

local function seedInsurance()
    if not MT.DB.isEmpty('mt_insurance_tiers') then return end
    for _, t in ipairs(Config.Insurance.TiersSeed) do
        MT.DB.insert([[INSERT INTO mt_insurance_tiers
            (tier_key,label,description,color,icon,weekly_premium,coverage_pct,max_per_invoice,weekly_cap,active,min_term_days,cancel_notice_days,waiting_days)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)]],
            { t.tier_key, t.label, t.description, t.color, t.icon, t.weekly_premium, t.coverage_pct,
              t.max_per_invoice, t.weekly_cap, t.active and 1 or 0, t.min_term_days, t.cancel_notice_days, t.waiting_days })
    end
    MT.Util.log('Versicherungsstufen aus Config geseedet.')
end

local function seedSettings()
    -- Branding/Features als DB-Settings ablegen (Panel/Tablet-editierbar), falls fehlen
    local function ensure(key, tbl)
        local exists = MT.DB.scalar('SELECT 1 FROM mt_settings WHERE skey = ?', { key })
        if not exists then
            MT.DB.insert('INSERT INTO mt_settings (skey, svalue, updated_by) VALUES (?,?,?)', { key, json.encode(tbl), 'SEED' })
        end
    end
    ensure('branding', Config.Branding)
    ensure('features', Config.Features)
end

CreateThread(function()
    -- Auf ESX warten
    local tries = 0
    while not MT.getESX() and tries < 100 do Wait(200); tries = tries + 1 end
    if not MT.getESX() then
        MT.Util.err('ESX (' .. Config.ESXResource .. ') nicht gefunden – Tablet inaktiv.')
        return
    end
    seedPermissions()
    seedPricelist()
    seedInsurance()
    seedSettings()

    -- Nutzbares Item registrieren (oeffnet das Tablet clientseitig)
    if Config.Open.item.enabled then
        local ESX = MT.getESX()
        if ESX and ESX.RegisterUsableItem then
            ESX.RegisterUsableItem(Config.Open.item.name, function(src)
                TriggerClientEvent('medictablet:cl:open', src)
            end)
            MT.Util.log('Nutzbares Item registriert:', Config.Open.item.name)
        else
            MT.Util.warn('RegisterUsableItem nicht verfuegbar – Item-Oeffnung inaktiv.')
        end
    end

    MT.Util.log('Medic-Tablet bereit. Provider:', Config.Billing.provider,
        '| Panel:', Config.Panel.enabled and 'an' or 'aus')
end)
