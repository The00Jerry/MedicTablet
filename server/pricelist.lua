--[[
    Preisliste (DB = Source of Truth).
    * Preisaenderungen wirken NIE rueckwirkend: bei Behandlung/Rechnung werden
      Bezeichnung & Einzelpreis als Snapshot separat gespeichert.
    * buildLines() validiert Auswahl serverseitig (Existenz, aktiv, Recht, Menge).
]]

MT = MT or {}
MT.Pricelist = {}

-- Baut validierte Positions-Snapshots aus einer Client-Auswahl.
-- itemsInput: { { code=, quantity= }, ... }
-- return lines, base, errKey
function MT.Pricelist.buildLines(ctx, itemsInput)
    if type(itemsInput) ~= 'table' or #itemsInput == 0 then
        return nil, 0, 'invalid_input'
    end
    local lines, base = {}, 0
    for _, sel in ipairs(itemsInput) do
        local code = tostring(sel.code or '')
        local qty = MT.Util.clampInt(sel.quantity or 1, 1, 999)
        local item = MT.DB.single([[SELECT * FROM mt_pricelist_items
            WHERE code = ? AND active = 1 AND archived_at IS NULL]], { code })
        if not item then
            return nil, 0, 'invalid_input'
        end
        if item.required_perm and item.required_perm ~= '' and not ctx.can(item.required_perm) then
            return nil, 0, 'no_permission'
        end
        local lineTotal = item.price * qty
        lines[#lines + 1] = {
            item_code = item.code, label = item.label,
            unit_price = item.price, quantity = qty, line_total = lineTotal,
        }
        base = base + lineTotal
    end
    return lines, base, nil
end

-----------------------------------------------------------------------------
-- Anzeige
-----------------------------------------------------------------------------
MT.register('pricelist.list', { perm = 'pricelist.view', feature = 'pricelist' }, function(ctx, data)
    local includeInactive = data.all == true and ctx.can('pricelist.edit')
    local cats = MT.DB.query('SELECT * FROM mt_pricelist_categories WHERE archived_at IS NULL ORDER BY sort, label') or {}
    local itemSql = 'SELECT * FROM mt_pricelist_items WHERE archived_at IS NULL'
    if not includeInactive then itemSql = itemSql .. ' AND active = 1' end
    itemSql = itemSql .. ' ORDER BY label'
    local items = MT.DB.query(itemSql) or {}
    return { categories = cats, items = items, canEdit = ctx.can('pricelist.edit') }
end)

-----------------------------------------------------------------------------
-- Bearbeiten (neu/aendern)
-----------------------------------------------------------------------------
MT.register('pricelist.saveItem', { perm = 'pricelist.edit', feature = 'pricelist' }, function(ctx, data)
    local label = MT.Util.trim(tostring(data.label or ''))
    local price = MT.Util.clampInt(data.price or 0, 0)
    if label == '' then return MT.fail('invalid_input') end
    local catId = tonumber(data.category_id)
    local perm = tostring(data.required_perm or '')
    local desc = tostring(data.description or ''):sub(1, 500)

    if data.id then -- Update
        local old = MT.DB.single('SELECT * FROM mt_pricelist_items WHERE id = ?', { tonumber(data.id) })
        if not old then return MT.fail('invalid_input') end
        MT.DB.update([[UPDATE mt_pricelist_items
            SET label=?, description=?, category_id=?, price=?, required_perm=?, updated_by=?
            WHERE id=?]], { label, desc, catId, price, perm, ctx.identifier, old.id })
        MT.Audit.log(ctx, { category = 'settings', action = 'pricelist.update', target_type = 'pricelist_item',
            target_id = old.id, old = { price = old.price, label = old.label }, new = { price = price, label = label } })
        return { ok = true }
    else -- Neu
        local code = tostring(data.code or ''):gsub('%s', ''):upper()
        if code == '' then code = 'ITEM' .. os.time() % 100000 end
        local id = MT.DB.insert([[INSERT INTO mt_pricelist_items
            (code,label,description,category_id,price,required_perm,created_by,updated_by)
            VALUES (?,?,?,?,?,?,?,?)]], { code, label, desc, catId, price, perm, ctx.identifier, ctx.identifier })
        if not id then return MT.fail('db_error') end
        MT.Audit.log(ctx, { category = 'settings', action = 'pricelist.create', target_type = 'pricelist_item',
            target_id = id, new = { code = code, price = price, label = label } })
        return { ok = true, id = id }
    end
end)

MT.register('pricelist.toggle', { perm = 'pricelist.edit', feature = 'pricelist' }, function(ctx, data)
    local it = MT.DB.single('SELECT * FROM mt_pricelist_items WHERE id = ?', { tonumber(data.id) })
    if not it then return MT.fail('invalid_input') end
    local newActive = it.active == 1 and 0 or 1
    MT.DB.update('UPDATE mt_pricelist_items SET active=?, updated_by=? WHERE id=?', { newActive, ctx.identifier, it.id })
    MT.Audit.log(ctx, { category = 'settings', action = 'pricelist.toggle', target_type = 'pricelist_item',
        target_id = it.id, old = { active = it.active }, new = { active = newActive } })
    return { ok = true, active = newActive }
end)

MT.register('pricelist.archive', { perm = 'pricelist.edit', feature = 'pricelist' }, function(ctx, data)
    local it = MT.DB.single('SELECT * FROM mt_pricelist_items WHERE id = ?', { tonumber(data.id) })
    if not it then return MT.fail('invalid_input') end
    MT.DB.update('UPDATE mt_pricelist_items SET archived_at=NOW(), active=0, updated_by=? WHERE id=?', { ctx.identifier, it.id })
    MT.Audit.log(ctx, { category = 'settings', action = 'pricelist.archive', target_type = 'pricelist_item', target_id = it.id })
    return { ok = true }
end)

MT.register('pricelist.saveCategory', { perm = 'pricelist.edit', feature = 'pricelist' }, function(ctx, data)
    local label = MT.Util.trim(tostring(data.label or ''))
    if label == '' then return MT.fail('invalid_input') end
    local sort = MT.Util.clampInt(data.sort or 0, 0)
    if data.id then
        MT.DB.update('UPDATE mt_pricelist_categories SET label=?, sort=? WHERE id=?', { label, sort, tonumber(data.id) })
    else
        local key = tostring(data.cat_key or label:lower():gsub('%s', '_'))
        MT.DB.insert('INSERT INTO mt_pricelist_categories (cat_key,label,sort) VALUES (?,?,?)', { key, label, sort })
    end
    MT.Audit.log(ctx, { category = 'settings', action = 'pricelist.category.save' })
    return { ok = true }
end)
