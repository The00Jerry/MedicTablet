--[[
    Patientensuche & digitale Patientenakte.
    Verknuepfung IMMER ueber den permanenten Identifier.

    Hinweis zu ESX-Spalten: Standard ESX Legacy `users`:
      identifier, firstname, lastname, dateofbirth, sex, phone_number
    Weichen deine Spalten ab, hier (USERCOL) anpassen.
]]

MT = MT or {}
MT.Patients = {}

local USERCOL = {
    firstname = 'firstname',
    lastname  = 'lastname',
    dob       = 'dateofbirth',
    sex       = 'sex',
    phone     = 'phone_number',
}

-- Legt eine Akte an (aus users-Daten) bzw. gibt bestehende zurueck
function MT.Patients.ensureRecord(identifier)
    local rec = MT.DB.single('SELECT * FROM mt_patient_records WHERE identifier = ?', { identifier })
    if rec then return rec end

    local u = MT.DB.single(([[
        SELECT identifier, `%s` AS firstname, `%s` AS lastname, `%s` AS dob, `%s` AS sex, `%s` AS phone
        FROM users WHERE identifier = ?
    ]]):format(USERCOL.firstname, USERCOL.lastname, USERCOL.dob, USERCOL.sex, USERCOL.phone), { identifier })

    if not u then return nil end

    local id = MT.DB.insert([[
        INSERT INTO mt_patient_records (identifier, firstname, lastname, dateofbirth, sex, phone)
        VALUES (?,?,?,?,?,?)
    ]], { identifier, u.firstname or '', u.lastname or '', u.dob or '', u.sex or '', u.phone or '' })

    return MT.DB.single('SELECT * FROM mt_patient_records WHERE id = ?', { id })
end

-----------------------------------------------------------------------------
-- Suche
-----------------------------------------------------------------------------
-- data: { q = string, field = 'auto'|'firstname'|'lastname'|'fullname'|'dob'|'charid'|'phone', page, pageSize }
MT.register('patients.search', { perm = 'patient.search', feature = 'patientSearch' }, function(ctx, data)
    local q = MT.Util.trim(tostring(data.q or ''))
    if #q < 1 then return { results = {}, total = 0, page = 1 } end

    local page = MT.Util.clampInt(data.page or 1, 1)
    local pageSize = MT.Util.clampInt(data.pageSize or 15, 1, 50)
    local offset = (page - 1) * pageSize
    local like = '%' .. q .. '%'
    local field = data.field or 'auto'

    local where, params
    if field == 'firstname' then
        where = ('u.`%s` LIKE ?'):format(USERCOL.firstname); params = { like }
    elseif field == 'lastname' then
        where = ('u.`%s` LIKE ?'):format(USERCOL.lastname); params = { like }
    elseif field == 'dob' then
        where = ('u.`%s` LIKE ?'):format(USERCOL.dob); params = { like }
    elseif field == 'phone' then
        where = ('u.`%s` LIKE ?'):format(USERCOL.phone); params = { like }
    elseif field == 'charid' then
        where = 'u.identifier LIKE ? OR pr.char_id = ?'; params = { like, tonumber(q) or -1 }
    else -- auto / fullname
        where = ([[u.`%s` LIKE ? OR u.`%s` LIKE ? OR CONCAT(u.`%s`,' ',u.`%s`) LIKE ?
                   OR u.`%s` LIKE ? OR u.identifier LIKE ?]]):format(
            USERCOL.firstname, USERCOL.lastname, USERCOL.firstname, USERCOL.lastname, USERCOL.phone)
        params = { like, like, like, like, like }
    end

    local baseFrom = ([[
        FROM users u
        LEFT JOIN mt_patient_records pr ON pr.identifier = u.identifier
        WHERE (%s)
    ]]):format(where)

    local total = MT.DB.scalar('SELECT COUNT(*) ' .. baseFrom, params) or 0

    local rows = MT.DB.query(([[
        SELECT u.identifier,
               u.`%s` AS firstname, u.`%s` AS lastname, u.`%s` AS dob, u.`%s` AS phone,
               pr.id AS record_id, pr.last_treatment_at
        %s
        ORDER BY u.`%s`, u.`%s`
        LIMIT %d OFFSET %d
    ]]):format(USERCOL.firstname, USERCOL.lastname, USERCOL.dob, USERCOL.phone,
        baseFrom, USERCOL.lastname, USERCOL.firstname, pageSize, offset), params) or {}

    MT.Audit.log(ctx, { category = 'default', action = 'patient.search', reason = q })

    return { results = rows, total = total, page = page, pageSize = pageSize }
end)

-----------------------------------------------------------------------------
-- Akte oeffnen (mit Behandlungen, Rechnungen, Versicherung)
-----------------------------------------------------------------------------
MT.register('patients.open', { perm = 'patient.view', feature = 'patientSearch' }, function(ctx, data)
    local identifier = tostring(data.identifier or '')
    if identifier == '' then return MT.fail('invalid_input') end

    local rec = MT.Patients.ensureRecord(identifier)
    if not rec then return MT.fail('player_not_found') end

    -- Behandlungen (ohne interne Notiz, falls kein Recht)
    local canInternal = ctx.can('notes.internal.view')
    local treatments = MT.DB.query([[
        SELECT id, treatment_no, staff_name, diagnosis, status,
               amount_base, amount_insurance, amount_discount, amount_final, created_at
        FROM mt_treatments
        WHERE patient_id = ? AND (archived_at IS NULL OR status = 'archived')
        ORDER BY created_at DESC LIMIT 100
    ]], { rec.id }) or {}

    local invoices = MT.DB.query([[
        SELECT id, invoice_no, reason, amount_base, insurance_amount, discount_amount,
               amount_final, status, provider, provider_invoice_id, created_at
        FROM mt_invoice_refs WHERE patient_id = ? ORDER BY created_at DESC LIMIT 100
    ]], { rec.id }) or {}

    local insurance = MT.Insurance.getContractView(identifier)

    MT.Audit.log(ctx, { category = 'default', action = 'patient.open', target_type = 'patient', target_id = rec.id })

    rec.canInternal = canInternal
    return {
        record = rec,
        treatments = treatments,
        invoices = invoices,
        insurance = insurance,
    }
end)

-----------------------------------------------------------------------------
-- Akte bearbeiten (medizinische Stammdaten)
-----------------------------------------------------------------------------
MT.register('patients.update', { perm = 'patient.edit', feature = 'patientSearch' }, function(ctx, data)
    local rec = MT.DB.single('SELECT * FROM mt_patient_records WHERE identifier = ?', { tostring(data.identifier or '') })
    if not rec then return MT.fail('player_not_found') end

    local fields = { 'blood_type', 'allergies', 'preconditions', 'medications', 'medical_notes', 'phone' }
    local sets, params, oldv, newv = {}, {}, {}, {}
    for _, f in ipairs(fields) do
        if data[f] ~= nil then
            sets[#sets + 1] = ('`%s` = ?'):format(f)
            params[#params + 1] = tostring(data[f]):sub(1, 2000)
            oldv[f] = rec[f]; newv[f] = data[f]
        end
    end
    if #sets == 0 then return MT.fail('invalid_input') end
    params[#params + 1] = rec.id

    local ok = MT.DB.update('UPDATE mt_patient_records SET ' .. table.concat(sets, ', ') .. ' WHERE id = ?', params)
    if ok == nil then return MT.fail('db_error') end

    MT.Audit.log(ctx, { category = 'default', action = 'patient.update', target_type = 'patient',
        target_id = rec.id, old = oldv, new = newv })

    return { ok = true, message = MT.L('saved') }
end)

-----------------------------------------------------------------------------
-- Sensible interne Notizen (nur mit Recht)
-----------------------------------------------------------------------------
MT.register('patients.notes', { perm = 'notes.internal.view', feature = 'patientSearch' }, function(ctx, data)
    local rec = MT.DB.single('SELECT id FROM mt_patient_records WHERE identifier = ?', { tostring(data.identifier or '') })
    if not rec then return MT.fail('player_not_found') end
    local notes = MT.DB.query([[
        SELECT id, author_name, body, created_at FROM mt_medical_notes
        WHERE patient_id = ? AND archived_at IS NULL ORDER BY created_at DESC LIMIT 100
    ]], { rec.id }) or {}
    return { notes = notes }
end)

MT.register('patients.addNote', { perm = 'notes.internal.view', feature = 'patientSearch' }, function(ctx, data)
    local rec = MT.DB.single('SELECT id FROM mt_patient_records WHERE identifier = ?', { tostring(data.identifier or '') })
    if not rec then return MT.fail('player_not_found') end
    local body = MT.Util.trim(tostring(data.body or ''))
    if #body < 1 then return MT.fail('invalid_input') end
    local id = MT.DB.insert([[INSERT INTO mt_medical_notes (patient_id, author_identifier, author_name, body, sensitive)
        VALUES (?,?,?,?,1)]], { rec.id, ctx.identifier, ctx.name, body:sub(1, 2000) })
    MT.Audit.log(ctx, { category = 'default', action = 'note.add', target_type = 'patient', target_id = rec.id })
    return { ok = true, id = id }
end)
