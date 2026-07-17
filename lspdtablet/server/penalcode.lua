--[[ Strafenkatalog (DB = Source of Truth). Snapshots verhindern rueckwirkende Aenderung. ]]

PD = PD or {}
PD.Penal = {}

-- Validierte Snapshot-Zeilen aus einer Auswahl. return lines, totals, errKey
function PD.Penal.buildLines(ctx, itemsInput)
    if type(itemsInput) ~= 'table' or #itemsInput == 0 then return nil, nil, 'invalid_input' end
    local lines = {}
    local totals = { fine = 0, jail = 0, points = 0 }
    for _, sel in ipairs(itemsInput) do
        local code = tostring(sel.code or '')
        local qty = PD.Util.clampInt(sel.quantity or 1, 1, 50)
        local o = PD.DB.single('SELECT * FROM pd_penal_offenses WHERE code = ? AND active = 1 AND archived_at IS NULL', { code })
        if not o then return nil, nil, 'invalid_input' end
        if o.required_perm and o.required_perm ~= '' and not ctx.can(o.required_perm) then return nil, nil, 'no_permission' end
        lines[#lines + 1] = { code = o.code, label = o.label, fine = o.fine, jail = o.jail, points = o.points, quantity = qty }
        totals.fine = totals.fine + o.fine * qty
        totals.jail = totals.jail + o.jail * qty
        totals.points = totals.points + o.points * qty
    end
    return lines, totals, nil
end

PD.register('penalcode.list', { perm = 'penalcode.view', feature = 'penalcode' }, function(ctx, data)
    local includeInactive = data.all == true and ctx.can('penalcode.edit')
    local cats = PD.DB.query('SELECT * FROM pd_penal_categories WHERE archived_at IS NULL ORDER BY sort, label') or {}
    local sql = 'SELECT * FROM pd_penal_offenses WHERE archived_at IS NULL' .. (includeInactive and '' or ' AND active = 1') .. ' ORDER BY label'
    local offenses = PD.DB.query(sql) or {}
    return { categories = cats, offenses = offenses, canEdit = ctx.can('penalcode.edit') }
end)

PD.register('penalcode.saveOffense', { perm = 'penalcode.edit', feature = 'penalcode' }, function(ctx, data)
    local label = PD.Util.trim(tostring(data.label or ''))
    if label == '' then return PD.fail('invalid_input') end
    local fine = PD.Util.clampInt(data.fine or 0, 0)
    local jail = PD.Util.clampInt(data.jail or 0, 0)
    local points = PD.Util.clampInt(data.points or 0, 0)
    local catId = tonumber(data.category_id)
    local desc = tostring(data.description or ''):sub(1, 500)
    local perm = tostring(data.required_perm or '')
    if data.id then
        local old = PD.DB.single('SELECT * FROM pd_penal_offenses WHERE id = ?', { tonumber(data.id) })
        if not old then return PD.fail('invalid_input') end
        PD.DB.update([[UPDATE pd_penal_offenses SET label=?, description=?, category_id=?, fine=?, jail=?, points=?, required_perm=?, updated_by=? WHERE id=?]],
            { label, desc, catId, fine, jail, points, perm, ctx.identifier, old.id })
        PD.Audit.log(ctx, { category = 'settings', action = 'penalcode.update', target_type = 'offense', target_id = old.id, old = { fine = old.fine }, new = { fine = fine } })
        return { ok = true }
    else
        local code = tostring(data.code or ''):gsub('%s', ''):upper()
        if code == '' then code = 'X' .. os.time() % 100000 end
        local id = PD.DB.insert([[INSERT INTO pd_penal_offenses (code,label,description,category_id,fine,jail,points,required_perm,created_by,updated_by)
            VALUES (?,?,?,?,?,?,?,?,?,?)]], { code, label, desc, catId, fine, jail, points, perm, ctx.identifier, ctx.identifier })
        if not id then return PD.fail('db_error') end
        PD.Audit.log(ctx, { category = 'settings', action = 'penalcode.create', target_type = 'offense', target_id = id, new = { code = code, fine = fine } })
        return { ok = true, id = id }
    end
end)

PD.register('penalcode.toggle', { perm = 'penalcode.edit', feature = 'penalcode' }, function(ctx, data)
    local o = PD.DB.single('SELECT * FROM pd_penal_offenses WHERE id = ?', { tonumber(data.id) })
    if not o then return PD.fail('invalid_input') end
    local na = o.active == 1 and 0 or 1
    PD.DB.update('UPDATE pd_penal_offenses SET active=?, updated_by=? WHERE id=?', { na, ctx.identifier, o.id })
    PD.Audit.log(ctx, { category = 'settings', action = 'penalcode.toggle', target_type = 'offense', target_id = o.id, new = { active = na } })
    return { ok = true, active = na }
end)

PD.register('penalcode.archive', { perm = 'penalcode.edit', feature = 'penalcode' }, function(ctx, data)
    local o = PD.DB.single('SELECT id FROM pd_penal_offenses WHERE id = ?', { tonumber(data.id) })
    if not o then return PD.fail('invalid_input') end
    PD.DB.update('UPDATE pd_penal_offenses SET archived_at=NOW(), active=0, updated_by=? WHERE id=?', { ctx.identifier, o.id })
    PD.Audit.log(ctx, { category = 'settings', action = 'penalcode.archive', target_type = 'offense', target_id = o.id })
    return { ok = true }
end)

PD.register('penalcode.saveCategory', { perm = 'penalcode.edit', feature = 'penalcode' }, function(ctx, data)
    local label = PD.Util.trim(tostring(data.label or ''))
    if label == '' then return PD.fail('invalid_input') end
    local sort = PD.Util.clampInt(data.sort or 0, 0)
    if data.id then PD.DB.update('UPDATE pd_penal_categories SET label=?, sort=? WHERE id=?', { label, sort, tonumber(data.id) })
    else PD.DB.insert('INSERT INTO pd_penal_categories (cat_key,label,sort) VALUES (?,?,?)', { tostring(data.cat_key or label:lower():gsub('%s', '_')), label, sort }) end
    PD.Audit.log(ctx, { category = 'settings', action = 'penalcode.category.save' })
    return { ok = true }
end)
