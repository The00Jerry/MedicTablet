--[[ Fahndung / BOLO. ]]

PD = PD or {}

local function refreshWantedFlag(citizenId, identifier)
    local active = PD.DB.scalar("SELECT COUNT(*) FROM pd_wanted WHERE citizen_id = ? AND status='active'", { citizenId })
    PD.DB.update('UPDATE pd_citizens SET is_wanted = ? WHERE id = ?', { (tonumber(active) or 0) > 0 and 1 or 0, citizenId })
end
PD.refreshWantedFlag = refreshWantedFlag

PD.register('wanted.list', { perm = 'wanted.view', feature = 'wanted' }, function(ctx, data)
    local rows = PD.DB.query([[SELECT w.id, w.reason, w.level, w.officer_name, w.created_at,
        c.identifier, c.firstname, c.lastname, c.fingerprint
        FROM pd_wanted w JOIN pd_citizens c ON c.id = w.citizen_id
        WHERE w.status='active' ORDER BY FIELD(w.level,'high','medium','low'), w.created_at DESC LIMIT 100]]) or {}
    return { wanted = rows }
end)

PD.register('wanted.add', { perm = 'wanted.manage', feature = 'wanted' }, function(ctx, data)
    local rec = PD.Citizens.ensure(tostring(data.identifier or ''))
    if not rec then return PD.fail('player_not_found') end
    local reason = PD.Util.trim(tostring(data.reason or ''))
    if #reason < 1 then return PD.fail('invalid_input') end
    local level = tostring(data.level or 'medium')
    if not PD.Util.WantedLevels[level] then level = 'medium' end
    local id = PD.DB.insert([[INSERT INTO pd_wanted (citizen_id, identifier, reason, level, officer_identifier, officer_name)
        VALUES (?,?,?,?,?,?)]], { rec.id, rec.identifier, reason:sub(1, 500), level, ctx.identifier, ctx.name })
    refreshWantedFlag(rec.id, rec.identifier)
    PD.Audit.log(ctx, { category = 'wanted', action = 'wanted.add', target_type = 'citizen', target_id = rec.id, new = { level = level, reason = reason } })
    return { ok = true, id = id, message = PD.L('wanted_added') }
end)

PD.register('wanted.clear', { perm = 'wanted.manage', feature = 'wanted' }, function(ctx, data)
    local w = PD.DB.single('SELECT * FROM pd_wanted WHERE id = ?', { tonumber(data.id) })
    if not w then return PD.fail('invalid_input') end
    PD.DB.update("UPDATE pd_wanted SET status='cleared', cleared_at=NOW(), cleared_by=? WHERE id=?", { ctx.identifier, w.id })
    refreshWantedFlag(w.citizen_id, w.identifier)
    PD.Audit.log(ctx, { category = 'wanted', action = 'wanted.clear', target_type = 'citizen', target_id = w.citizen_id })
    return { ok = true, message = PD.L('wanted_cleared') }
end)
