--[[ Fuehrerschein-Antraege + Autorisierung durch DOL-Mitarbeiter. ]]

WL = WL or {}

local function chargeFee(ctx, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    local acc = ctx.xp and ctx.xp.getAccount(Config.Cards.account)
    if not acc or acc.money < amount then return false end
    ctx.xp.removeAccountMoney(Config.Cards.account, amount)
    return true
end

local function validClass(cls)
    for _, c in ipairs((Config.Templates.Cards[2] and Config.Templates.Cards[2].classes) or { 'B' }) do if c == cls then return true end end
    return false
end

local function issueDriver(identifier, class, actor)
    local u = WL.Wallet.getUser(identifier); if not u then return nil end
    return WL.Wallet.issue(identifier, 'driver_license', 'driver_license',
        { firstname = u.firstname, lastname = u.lastname, dateofbirth = u.dateofbirth, class = class },
        actor, { expiresDays = Config.Cards.driverExpiryDays })
end

-- Selbst-Service: Fuehrerschein beantragen (oder direkt ausstellen)
WL.register('dmv.applyDriver', {}, function(ctx, data)
    local class = tostring(data.class or 'B')
    if not validClass(class) then return WL.fail('invalid_input') end
    if WL.DB.single("SELECT id FROM lw_cards WHERE identifier = ? AND ctype='driver_license' AND revoked=0", { ctx.identifier }) then
        return WL.fail('id_exists')
    end
    if not chargeFee(ctx, Config.Cards.driverFee) then return WL.fail('no_money') end

    if not Config.Cards.requireApplicationForDriver then
        local id = issueDriver(ctx.identifier, class, ctx)
        if not id then return WL.fail('db_error') end
        WL.Audit.log(ctx, { action = 'card.issue', target_type = 'card', target_id = id, new = { ctype = 'driver_license', class = class } })
        return { ok = true, id = id, message = WL.L('card_issued') }
    end

    if WL.DB.single("SELECT id FROM lw_applications WHERE identifier = ? AND atype='driver_license' AND status='pending'", { ctx.identifier }) then
        return WL.fail('app_exists')
    end
    local aid = WL.DB.insert('INSERT INTO lw_applications (identifier, applicant_name, atype, payload) VALUES (?,?,?,?)',
        { ctx.identifier, ctx.name, 'driver_license', json.encode({ class = class }) })
    WL.Audit.log(ctx, { action = 'application.create', target_type = 'application', target_id = aid, new = { atype = 'driver_license', class = class } })
    return { ok = true, id = aid, message = WL.L('app_created') }
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
        local payload = app.payload and json.decode(app.payload) or {}
        local cardId = nil
        if app.atype == 'driver_license' then
            cardId = issueDriver(app.identifier, payload.class or 'B', ctx)
            if not cardId then return WL.fail('db_error') end
        end
        WL.DB.update("UPDATE lw_applications SET status='approved', reviewer_identifier=?, reviewer_name=?, note=?, decided_at=NOW() WHERE id=?",
            { ctx.identifier, ctx.name, note, app.id })
        WL.Audit.log(ctx, { category = 'default', action = 'application.approve', target_type = 'application', target_id = app.id, new = { card = cardId } })
        return { ok = true, message = WL.L('app_approved') }
    elseif decision == 'deny' then
        WL.DB.update("UPDATE lw_applications SET status='denied', reviewer_identifier=?, reviewer_name=?, note=?, decided_at=NOW() WHERE id=?",
            { ctx.identifier, ctx.name, note, app.id })
        WL.Audit.log(ctx, { action = 'application.deny', target_type = 'application', target_id = app.id, reason = note })
        return { ok = true, message = WL.L('app_denied') }
    end
    return WL.fail('invalid_input')
end)
