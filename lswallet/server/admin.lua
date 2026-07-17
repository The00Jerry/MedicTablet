--[[ Admin Control Center: Lookup, Karten ausstellen/entziehen, Vorlagen, Rechte. ]]

WL = WL or {}

-- Wallet-Lookup: Person + Karten finden
WL.register('admin.lookup', { perm = 'wallet.admin.view' }, function(ctx, data)
    local q = WL.Util.trim(tostring(data.query or ''))
    if #q < 2 then return WL.fail('invalid_input') end
    local like = '%' .. q .. '%'
    -- Person suchen (users) ODER direkt per Kartennummer
    local user = WL.DB.single([[SELECT identifier, firstname, lastname, dateofbirth, sex, phone_number AS phone FROM users
        WHERE identifier = ? OR CONCAT(firstname,' ',lastname) LIKE ? OR firstname LIKE ? OR lastname LIKE ? LIMIT 1]],
        { q, like, like, like })
    if not user then
        local card = WL.DB.single('SELECT identifier FROM lw_cards WHERE serial = ?', { q })
        if card then user = WL.DB.single('SELECT identifier, firstname, lastname, dateofbirth, sex, phone_number AS phone FROM users WHERE identifier = ?', { card.identifier }) end
    end
    if not user then return { found = false } end
    local cards = WL.Wallet.getCards(user.identifier)
    WL.Audit.log(ctx, { action = 'admin.lookup', target_type = 'citizen', target_id = user.identifier, reason = q })
    return { found = true, identity = user, cards = cards, canRevoke = ctx.can('wallet.admin.revoke'), canIssue = ctx.can('wallet.admin.issue') }
end)

-- Karte manuell ausstellen
WL.register('admin.issue', { perm = 'wallet.admin.issue' }, function(ctx, data)
    local identifier = tostring(data.identifier or '')
    local ctype = tostring(data.ctype or '')
    if identifier == '' or not WL.Util.CardTypes[ctype] then return WL.fail('invalid_input') end
    if not WL.Wallet.getUser(identifier) then return WL.fail('player_not_found') end
    local cardData = data.data or {}
    local id = WL.Wallet.issue(identifier, ctype, tostring(data.template_key or ctype), cardData, ctx, { title = data.title or '' })
    if not id then return WL.fail('db_error') end
    -- Lizenzkarte -> echte ESX-Lizenz setzen
    if (ctype == 'license' or ctype == 'driver_license') and cardData.esxType then WL.License.grant(identifier, cardData.esxType) end
    WL.Audit.log(ctx, { action = 'admin.issue', target_type = 'card', target_id = id, new = { ctype = ctype, to = identifier } })
    return { ok = true, id = id, message = WL.L('card_issued') }
end)

-- Karte entziehen
WL.register('admin.revoke', { perm = 'wallet.admin.revoke' }, function(ctx, data)
    local card = WL.DB.single('SELECT * FROM lw_cards WHERE id = ?', { tonumber(data.id) })
    if not card then return WL.fail('invalid_input') end
    WL.DB.update('UPDATE lw_cards SET revoked = 1, revoked_by = ? WHERE id = ?', { ctx.identifier, card.id })
    -- Lizenzkarte -> echte ESX-Lizenz entziehen
    if card.ctype == 'license' or card.ctype == 'driver_license' then
        local d = card.data and json.decode(card.data) or {}
        if d.esxType then WL.License.revoke(card.identifier, d.esxType) end
    end
    WL.Audit.log(ctx, { action = 'admin.revoke', target_type = 'card', target_id = card.id, old = { serial = card.serial } })
    return { ok = true, message = WL.L('card_revoked') }
end)

-- Vorlagen
WL.register('admin.templates', { perm = 'wallet.admin.template' }, function(ctx, data)
    local rows = WL.DB.query('SELECT id, tkey, ctype, label, config FROM lw_templates ORDER BY ctype, label') or {}
    for _, t in ipairs(rows) do t.config = t.config and json.decode(t.config) or {} end
    return { templates = rows }
end)

WL.register('admin.saveTemplate', { perm = 'wallet.admin.template' }, function(ctx, data)
    local tkey = tostring(data.tkey or ''):gsub('%s', '')
    local ctype = tostring(data.ctype or '')
    local label = WL.Util.trim(tostring(data.label or ''))
    if tkey == '' or not WL.Util.CardTypes[ctype] or label == '' then return WL.fail('invalid_input') end
    local cfg = type(data.config) == 'table' and data.config or {}
    WL.DB.update([[INSERT INTO lw_templates (tkey, ctype, label, config, created_by) VALUES (?,?,?,?,?)
        ON DUPLICATE KEY UPDATE ctype=VALUES(ctype), label=VALUES(label), config=VALUES(config)]],
        { tkey, ctype, label, json.encode(cfg), ctx.identifier })
    WL.Audit.log(ctx, { category = 'settings', action = 'template.save', target_type = 'template', target_id = tkey })
    return { ok = true, message = WL.L('saved') }
end)

-- Rechte-Overrides
WL.register('admin.setOverride', { perm = 'admin.full' }, function(ctx, data)
    local identifier = tostring(data.identifier or ''); local perm = tostring(data.perm or '')
    if identifier == '' or perm == '' then return WL.fail('invalid_input') end
    local allow = (data.allow == true or data.allow == 1) and 1 or 0
    WL.DB.update('INSERT INTO lw_permission_overrides (identifier, perm, allow, created_by) VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE allow=VALUES(allow)', { identifier, perm, allow, ctx.identifier })
    WL.Perms.invalidate(identifier)
    WL.Audit.log(ctx, { category = 'settings', action = 'perm.override', target_type = 'user', target_id = identifier, new = { perm = perm, allow = allow } })
    return { ok = true }
end)
