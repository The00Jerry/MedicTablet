--[[ Berichte / Faelle inkl. beteiligte Personen & Beweismittel. ]]

PD = PD or {}

local function genReportNo() return ('CR-%s-%04d'):format(os.date('%Y%m%d'), math.random(0, 9999)) end

PD.register('reports.list', { perm = 'report.view', feature = 'reports' }, function(ctx, data)
    local page = PD.Util.clampInt(data.page or 1, 1)
    local pageSize = PD.Util.clampInt(data.pageSize or 20, 1, 50)
    local offset = (page - 1) * pageSize
    local status = tostring(data.status or '')
    local where, params = '1=1', {}
    if status == 'open' or status == 'closed' then where = 'status = ?'; params = { status } end
    local total = PD.DB.scalar('SELECT COUNT(*) FROM pd_reports WHERE ' .. where, params) or 0
    local rows = PD.DB.query(('SELECT id, report_no, title, type, officer_name, status, created_at FROM pd_reports WHERE %s ORDER BY id DESC LIMIT %d OFFSET %d'):format(where, pageSize, offset), params) or {}
    return { rows = rows, total = total, page = page, pageSize = pageSize }
end)

PD.register('reports.get', { perm = 'report.view', feature = 'reports' }, function(ctx, data)
    local r = PD.DB.single('SELECT * FROM pd_reports WHERE id = ?', { tonumber(data.id) })
    if not r then return PD.fail('invalid_input') end
    local involved = PD.DB.query('SELECT id, identifier, name, role FROM pd_report_involved WHERE report_id = ?', { r.id }) or {}
    local evidence = PD.DB.query('SELECT id, label, description, created_by, created_at FROM pd_report_evidence WHERE report_id = ?', { r.id }) or {}
    return { report = r, involved = involved, evidence = evidence, canEdit = ctx.can('report.edit'), canClose = ctx.can('report.close') }
end)

PD.register('reports.create', { perm = 'report.create', feature = 'reports' }, function(ctx, data)
    local title = PD.Util.trim(tostring(data.title or ''))
    if title == '' then return PD.fail('invalid_input') end
    local rtype = tostring(data.type or 'incident')
    if not PD.Util.ReportTypes[rtype] then rtype = 'incident' end
    local no = genReportNo()
    local id = PD.DB.insert([[INSERT INTO pd_reports (report_no, title, type, officer_identifier, officer_name, body)
        VALUES (?,?,?,?,?,?)]], { no, title:sub(1, 200), rtype, ctx.identifier, ctx.name, tostring(data.body or ''):sub(1, 8000) })
    if not id then return PD.fail('db_error') end

    if type(data.involved) == 'table' then
        for _, p in ipairs(data.involved) do
            local role = tostring(p.role or 'suspect')
            if not PD.Util.InvolvedRoles[role] then role = 'suspect' end
            PD.DB.insert('INSERT INTO pd_report_involved (report_id, identifier, name, role) VALUES (?,?,?,?)',
                { id, tostring(p.identifier or ''), tostring(p.name or ''):sub(1, 96), role })
        end
    end
    if type(data.evidence) == 'table' then
        for _, e in ipairs(data.evidence) do
            local lbl = PD.Util.trim(tostring(e.label or ''))
            if lbl ~= '' then PD.DB.insert('INSERT INTO pd_report_evidence (report_id, label, description, created_by) VALUES (?,?,?,?)',
                { id, lbl:sub(1, 160), tostring(e.description or ''):sub(1, 500), ctx.identifier }) end
        end
    end

    PD.Audit.log(ctx, { action = 'report.create', target_type = 'report', target_id = id, new = { no = no, type = rtype } })
    return { ok = true, id = id, report_no = no, message = PD.L('report_saved') }
end)

PD.register('reports.update', { perm = 'report.edit', feature = 'reports' }, function(ctx, data)
    local r = PD.DB.single('SELECT * FROM pd_reports WHERE id = ?', { tonumber(data.id) })
    if not r then return PD.fail('invalid_input') end
    local sets, params = {}, {}
    for _, f in ipairs({ 'title', 'body', 'type' }) do
        if data[f] ~= nil then
            local v = tostring(data[f])
            if f == 'type' and not PD.Util.ReportTypes[v] then v = r.type end
            sets[#sets + 1] = ('`%s` = ?'):format(f); params[#params + 1] = v:sub(1, 8000)
        end
    end
    if #sets > 0 then params[#params + 1] = r.id; PD.DB.update('UPDATE pd_reports SET ' .. table.concat(sets, ', ') .. ' WHERE id = ?', params) end
    if data.addInvolved and type(data.addInvolved) == 'table' then
        local role = tostring(data.addInvolved.role or 'suspect')
        if not PD.Util.InvolvedRoles[role] then role = 'suspect' end
        PD.DB.insert('INSERT INTO pd_report_involved (report_id, identifier, name, role) VALUES (?,?,?,?)',
            { r.id, tostring(data.addInvolved.identifier or ''), tostring(data.addInvolved.name or ''):sub(1, 96), role })
    end
    if data.addEvidence and type(data.addEvidence) == 'table' then
        local lbl = PD.Util.trim(tostring(data.addEvidence.label or ''))
        if lbl ~= '' then PD.DB.insert('INSERT INTO pd_report_evidence (report_id, label, description, created_by) VALUES (?,?,?,?)',
            { r.id, lbl:sub(1, 160), tostring(data.addEvidence.description or ''):sub(1, 500), ctx.identifier }) end
    end
    PD.Audit.log(ctx, { action = 'report.update', target_type = 'report', target_id = r.id })
    return { ok = true, message = PD.L('saved') }
end)

PD.register('reports.close', { perm = 'report.close', feature = 'reports' }, function(ctx, data)
    local r = PD.DB.single('SELECT id FROM pd_reports WHERE id = ?', { tonumber(data.id) })
    if not r then return PD.fail('invalid_input') end
    PD.DB.update("UPDATE pd_reports SET status='closed' WHERE id=?", { r.id })
    PD.Audit.log(ctx, { action = 'report.close', target_type = 'report', target_id = r.id })
    return { ok = true, message = PD.L('report_closed') }
end)
