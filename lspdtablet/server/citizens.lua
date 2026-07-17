--[[ Personensuche & Personenakte. Verknuepfung ueber permanenten Identifier. ]]

PD = PD or {}
PD.Citizens = {}

local USERCOL = { firstname = 'firstname', lastname = 'lastname', dob = 'dateofbirth', sex = 'sex', phone = 'phone_number' }

function PD.Citizens.ensure(identifier)
    local rec = PD.DB.single('SELECT * FROM pd_citizens WHERE identifier = ?', { identifier })
    if rec then return rec end
    local u = PD.DB.single(([[SELECT identifier, `%s` AS firstname, `%s` AS lastname, `%s` AS dob, `%s` AS sex, `%s` AS phone
        FROM users WHERE identifier = ?]]):format(USERCOL.firstname, USERCOL.lastname, USERCOL.dob, USERCOL.sex, USERCOL.phone), { identifier })
    if not u then return nil end
    local fp = PD.Util.fingerprint(identifier)
    local id = PD.DB.insert([[INSERT INTO pd_citizens (identifier, firstname, lastname, dateofbirth, sex, phone, fingerprint, licenses)
        VALUES (?,?,?,?,?,?,?,?)]],
        { identifier, u.firstname or '', u.lastname or '', u.dob or '', u.sex or '', u.phone or '', fp, json.encode({ driver = true, weapon = false }) })
    return PD.DB.single('SELECT * FROM pd_citizens WHERE id = ?', { id })
end

-- Aufbereitete Akte (fuer UI)
function PD.Citizens.fullRecord(ctx, identifier)
    local rec = PD.Citizens.ensure(identifier)
    if not rec then return nil end
    rec.licenses = rec.licenses and json.decode(rec.licenses) or {}
    local wanted = PD.DB.query("SELECT id, reason, level, officer_name, status, created_at FROM pd_wanted WHERE citizen_id = ? AND status='active' ORDER BY created_at DESC", { rec.id }) or {}
    local charges = PD.DB.query([[SELECT id, charge_no, reason, fine_total, jail_total, points_total, status, created_at
        FROM pd_charges WHERE citizen_id = ? ORDER BY created_at DESC LIMIT 100]], { rec.id }) or {}
    local reports = PD.DB.query([[SELECT r.id, r.report_no, r.title, r.type, r.status, ri.role, r.created_at
        FROM pd_report_involved ri JOIN pd_reports r ON r.id = ri.report_id
        WHERE ri.identifier = ? ORDER BY r.created_at DESC LIMIT 50]], { identifier }) or {}
    local notes = {}
    if ctx.can('notes.view') then
        notes = PD.DB.query('SELECT id, author_name, body, created_at FROM pd_notes WHERE citizen_id = ? AND archived_at IS NULL ORDER BY created_at DESC LIMIT 100', { rec.id }) or {}
    end
    -- priors summary
    local prior = PD.DB.single("SELECT COUNT(*) AS c, COALESCE(SUM(jail_total),0) AS jail FROM pd_charges WHERE citizen_id = ? AND status='issued'", { rec.id })
    return {
        record = rec, wanted = wanted, charges = charges, reports = reports, notes = notes,
        priors = { count = prior and prior.c or 0, jail = prior and prior.jail or 0 },
        canNotes = ctx.can('notes.view'), canEdit = ctx.can('citizen.edit'), canLicenses = ctx.can('licenses.manage'),
    }
end

-----------------------------------------------------------------------------
-- Suche
-----------------------------------------------------------------------------
PD.register('citizens.search', { perm = 'citizen.search', feature = 'citizenSearch' }, function(ctx, data)
    local q = PD.Util.trim(tostring(data.q or ''))
    if #q < 1 then return { results = {}, total = 0, page = 1 } end
    local page = PD.Util.clampInt(data.page or 1, 1)
    local pageSize = PD.Util.clampInt(data.pageSize or 15, 1, 50)
    local offset = (page - 1) * pageSize
    local like = '%' .. q .. '%'
    local field = data.field or 'auto'

    local where, params
    if field == 'firstname' then where = ('u.`%s` LIKE ?'):format(USERCOL.firstname); params = { like }
    elseif field == 'lastname' then where = ('u.`%s` LIKE ?'):format(USERCOL.lastname); params = { like }
    elseif field == 'dob' then where = ('u.`%s` LIKE ?'):format(USERCOL.dob); params = { like }
    elseif field == 'phone' then where = ('u.`%s` LIKE ?'):format(USERCOL.phone); params = { like }
    elseif field == 'fingerprint' then where = 'pc.fingerprint LIKE ?'; params = { like }
    elseif field == 'charid' then where = 'u.identifier LIKE ? OR pc.char_id = ?'; params = { like, tonumber(q) or -1 }
    else
        where = ([[u.`%s` LIKE ? OR u.`%s` LIKE ? OR CONCAT(u.`%s`,' ',u.`%s`) LIKE ? OR u.`%s` LIKE ? OR u.identifier LIKE ? OR pc.fingerprint LIKE ?]]):format(
            USERCOL.firstname, USERCOL.lastname, USERCOL.firstname, USERCOL.lastname, USERCOL.phone)
        params = { like, like, like, like, like, like }
    end

    local from = ([[FROM users u LEFT JOIN pd_citizens pc ON pc.identifier = u.identifier WHERE (%s)]]):format(where)
    local total = PD.DB.scalar('SELECT COUNT(*) ' .. from, params) or 0
    local rows = PD.DB.query(([[SELECT u.identifier, u.`%s` AS firstname, u.`%s` AS lastname, u.`%s` AS dob, u.`%s` AS phone,
        pc.id AS record_id, pc.is_wanted, pc.fingerprint %s ORDER BY u.`%s`, u.`%s` LIMIT %d OFFSET %d]]):format(
        USERCOL.firstname, USERCOL.lastname, USERCOL.dob, USERCOL.phone, from, USERCOL.lastname, USERCOL.firstname, pageSize, offset), params) or {}
    PD.Audit.log(ctx, { action = 'citizen.search', reason = q })
    return { results = rows, total = total, page = page, pageSize = pageSize }
end)

PD.register('citizens.open', { perm = 'citizen.view', feature = 'citizenSearch' }, function(ctx, data)
    local identifier = tostring(data.identifier or '')
    if identifier == '' then return PD.fail('invalid_input') end
    local full = PD.Citizens.fullRecord(ctx, identifier)
    if not full then return PD.fail('player_not_found') end
    PD.Audit.log(ctx, { action = 'citizen.open', target_type = 'citizen', target_id = full.record.id })
    return full
end)

PD.register('citizens.update', { perm = 'citizen.edit', feature = 'citizenSearch' }, function(ctx, data)
    local rec = PD.DB.single('SELECT * FROM pd_citizens WHERE identifier = ?', { tostring(data.identifier or '') })
    if not rec then return PD.fail('player_not_found') end
    local sets, params, oldv, newv = {}, {}, {}, {}
    for _, f in ipairs({ 'phone', 'notes', 'mugshot_url' }) do
        if data[f] ~= nil then sets[#sets + 1] = ('`%s` = ?'):format(f); params[#params + 1] = tostring(data[f]):sub(1, 2000); oldv[f] = rec[f]; newv[f] = data[f] end
    end
    if #sets == 0 then return PD.fail('invalid_input') end
    params[#params + 1] = rec.id
    PD.DB.update('UPDATE pd_citizens SET ' .. table.concat(sets, ', ') .. ' WHERE id = ?', params)
    PD.Audit.log(ctx, { action = 'citizen.update', target_type = 'citizen', target_id = rec.id, old = oldv, new = newv })
    return { ok = true, message = PD.L('saved') }
end)

-- Fuehrerschein/Waffenschein setzen
PD.register('citizens.setLicense', { perm = 'licenses.manage', feature = 'citizenSearch' }, function(ctx, data)
    local rec = PD.DB.single('SELECT * FROM pd_citizens WHERE identifier = ?', { tostring(data.identifier or '') })
    if not rec then return PD.fail('player_not_found') end
    local lic = rec.licenses and json.decode(rec.licenses) or {}
    local key = tostring(data.key or '')
    if key == '' then return PD.fail('invalid_input') end
    lic[key] = (data.value == true or data.value == 1)
    PD.DB.update('UPDATE pd_citizens SET licenses = ? WHERE id = ?', { json.encode(lic), rec.id })
    PD.Audit.log(ctx, { action = 'citizen.license', target_type = 'citizen', target_id = rec.id, new = { [key] = lic[key] } })
    return { ok = true, licenses = lic }
end)

-- Notizen
PD.register('citizens.addNote', { perm = 'notes.add', feature = 'citizenSearch' }, function(ctx, data)
    local rec = PD.DB.single('SELECT id FROM pd_citizens WHERE identifier = ?', { tostring(data.identifier or '') })
    if not rec then return PD.fail('player_not_found') end
    local body = PD.Util.trim(tostring(data.body or ''))
    if #body < 1 then return PD.fail('invalid_input') end
    local id = PD.DB.insert('INSERT INTO pd_notes (citizen_id, author_identifier, author_name, body) VALUES (?,?,?,?)',
        { rec.id, ctx.identifier, ctx.name, body:sub(1, 2000) })
    PD.Audit.log(ctx, { action = 'note.add', target_type = 'citizen', target_id = rec.id })
    return { ok = true, id = id }
end)
