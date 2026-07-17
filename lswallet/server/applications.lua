--[[ Lizenz-Antraege + Autorisierung. Ausstellung setzt die echte ESX-Lizenz. ]]

WL = WL or {}

local function chargeFee(ctx, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    local acc = ctx.xp and ctx.xp.getAccount(Config.Cards.account)
    if not acc or acc.money < amount then return false end
    ctx.xp.removeAccountMoney(Config.Cards.account, amount)
    return true
end

local function validClass(def, cls)
    if not def.class then return true end
    for _, c in ipairs(def.classes or { 'B' }) do if c == cls then return true end end
    return false
end

-- Generischer Lizenzantrag / Direktausstellung (Fuehrerschein & weitere Scheine)
WL.register('dmv.applyLicense', {}, function(ctx, data)
    local def = WL.License.defByKey(tostring(data.key or ''))
    if not def then return WL.fail('invalid_input') end
    local class = tostring(data.class or (def.classes and def.classes[1] or ''))
    if not validClass(def, class) then return WL.fail('invalid_input') end

    -- Besitzt bereits diese Lizenz-Karte?
    if WL.DB.single("SELECT id FROM lw_cards WHERE identifier = ? AND template_key = ? AND revoked = 0", { ctx.identifier, def.key }) then
        return WL.fail('id_exists')
    end
    if not chargeFee(ctx, def.fee) then return WL.fail('no_money') end

    if not def.requireApplication then
        local id = WL.License.issueCard(ctx.identifier, def, class, ctx)
        if not id then return WL.fail('db_error') end
        WL.Audit.log(ctx, { action = 'license.issue', target_type = 'card', target_id = id, new = { key = def.key, esxType = def.esxType, class = class } })
        return { ok = true, id = id, message = WL.L('card_issued') }
    end

    if WL.DB.single("SELECT id FROM lw_applications WHERE identifier = ? AND atype = ? AND status='pending'", { ctx.identifier, def.key }) then
        return WL.fail('app_exists')
    end
    local aid = WL.DB.insert('INSERT INTO lw_applications (identifier, applicant_name, atype, payload) VALUES (?,?,?,?)',
        { ctx.identifier, ctx.name, def.key, json.encode({ class = class }) })
    WL.Audit.log(ctx, { action = 'application.create', target_type = 'application', target_id = aid, new = { key = def.key, class = class } })
    return { ok = true, id = aid, message = WL.L('app_created') }
end)

-- Kompatibilitaet: Fuehrerschein direkt
WL.register('dmv.applyDriver', {}, function(ctx, data)
    return WL.Handlers['dmv.applyLicense'].fn(ctx, { key = 'driver', class = data.class })
end)

-----------------------------------------------------------------------------
-- Admin: Antraege ansehen & entscheiden
-----------------------------------------------------------------------------
WL.register('admin.applications', { perm = 'wallet.admin.view' }, function(ctx, data)
    local rows = WL.DB.query("SELECT id, identifier, applicant_name, atype, payload, status, created_at FROM lw_applications WHERE status='pending' ORDER BY created_at ASC LIMIT 100") or {}
    for _, a in ipairs(rows) do a.payload = a.payload and json.decode(a.payload) or {} end
    return { applications = rows }
end)

WL.register('admin.decideApplication', { perm = 'wallet.admin.authorize' }, function(ctx, data)
    local app = WL.DB.single('SELECT * FROM lw_applications WHERE id = ?', { tonumber(data.id) })
    if not app or app.status ~= 'pending' then return WL.fail('invalid_input') end
    local decision = tostring(data.decision or '')
    local note = tostring(data.note or ''):sub(1, 200)

    if decision == 'approve' then
        local def = WL.License.defByKey(app.atype)
        if not def then return WL.fail('invalid_input') end
        local payload = app.payload and json.decode(app.payload) or {}
        local cardId = WL.License.issueCard(app.identifier, def, payload.class, ctx)
        if not cardId then return WL.fail('db_error') end
        WL.DB.update("UPDATE lw_applications SET status='approved', reviewer_identifier=?, reviewer_name=?, note=?, decided_at=NOW() WHERE id=?",
            { ctx.identifier, ctx.name, note, app.id })
        WL.Audit.log(ctx, { action = 'application.approve', target_type = 'application', target_id = app.id, new = { card = cardId, esxType = def.esxType } })
        return { ok = true, message = WL.L('app_approved') }
    elseif decision == 'deny' then
        WL.DB.update("UPDATE lw_applications SET status='denied', reviewer_identifier=?, reviewer_name=?, note=?, decided_at=NOW() WHERE id=?",
            { ctx.identifier, ctx.name, note, app.id })
        WL.Audit.log(ctx, { action = 'application.deny', target_type = 'application', target_id = app.id, reason = note })
        return { ok = true, message = WL.L('app_denied') }
    end
    return WL.fail('invalid_input')
end)
