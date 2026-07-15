--[[
    Behandlungen: erstellen, bearbeiten, archivieren.
    * Leistungen werden serverseitig validiert & als Snapshot gespeichert.
    * Versicherungsanteil wird serverseitig (MT.Insurance.calc) berechnet – Vorschau.
      Die verbindliche Berechnung erfolgt erneut bei der Rechnungsstellung.
    * Jede Aenderung wird protokolliert (wer/wann/vorher/nachher).
]]

MT = MT or {}
MT.Treatments = {}

local function genTreatmentNo()
    return ('BH-%s-%03d'):format(os.date('%Y%m%d'), math.random(0, 999))
end

-- Einzelne Behandlung inkl. Positionen laden
MT.register('treatment.get', { perm = 'patient.view', feature = 'treatments' }, function(ctx, data)
    local t = MT.DB.single('SELECT * FROM mt_treatments WHERE id = ?', { tonumber(data.id) })
    if not t then return MT.fail('invalid_input') end
    if not ctx.can('notes.internal.view') then t.internal_note = nil end
    local items = MT.DB.query('SELECT item_code, label, unit_price, quantity, line_total FROM mt_treatment_items WHERE treatment_id = ?', { t.id }) or {}
    return { treatment = t, items = items }
end)

MT.register('treatment.create', { perm = 'treatment.create', feature = 'treatments' }, function(ctx, data)
    local rec = MT.Patients.ensureRecord(tostring(data.identifier or ''))
    if not rec then return MT.fail('player_not_found') end

    local lines, base, errKey = MT.Pricelist.buildLines(ctx, data.items or {})
    if not lines then return MT.fail(errKey) end

    local discount = MT.Util.clampInt(data.discount or 0, 0, base)
    if discount > 0 and not ctx.can('discount.grant') then return MT.fail('no_permission') end

    -- Versicherungsvorschau (serverseitig)
    local snap = MT.Insurance.calc(rec.identifier, base)
    local final = math.max(0, base - snap.covered - discount)

    local status = tostring(data.status or 'draft')
    if not MT.Util.TreatmentStatuses[status] then status = 'draft' end

    local internalNote = ctx.can('notes.internal.view') and tostring(data.internal_note or ''):sub(1, 2000) or ''

    local tno = genTreatmentNo()
    local tid = MT.DB.insert([[INSERT INTO mt_treatments
        (treatment_no, patient_id, identifier, staff_identifier, staff_name, diagnosis, measures,
         medications, report, internal_note, amount_base, amount_insurance, amount_discount, amount_final, status)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)]],
        { tno, rec.id, rec.identifier, ctx.identifier, ctx.name,
          tostring(data.diagnosis or ''):sub(1, 500), tostring(data.measures or ''):sub(1, 2000),
          tostring(data.medications or ''):sub(1, 2000), tostring(data.report or ''):sub(1, 4000),
          internalNote, base, snap.covered, discount, final, status })

    if not tid then return MT.fail('db_error') end

    for _, l in ipairs(lines) do
        MT.DB.insert('INSERT INTO mt_treatment_items (treatment_id, item_code, label, unit_price, quantity, line_total) VALUES (?,?,?,?,?,?)',
            { tid, l.item_code, l.label, l.unit_price, l.quantity, l.line_total })
    end

    MT.DB.update('UPDATE mt_patient_records SET last_treatment_at = NOW() WHERE id = ?', { rec.id })

    MT.Audit.log(ctx, { category = 'default', action = 'treatment.create', target_type = 'treatment',
        target_id = tid, new = { no = tno, base = base, final = final, status = status } })

    return { ok = true, id = tid, treatment_no = tno, message = MT.L('treatment_saved'),
             insurance = snap, amount_base = base, amount_final = final }
end)

MT.register('treatment.update', { perm = 'treatment.edit', feature = 'treatments' }, function(ctx, data)
    local t = MT.DB.single('SELECT * FROM mt_treatments WHERE id = ?', { tonumber(data.id) })
    if not t then return MT.fail('invalid_input') end

    local sets, params, oldv, newv = {}, {}, {}, {}
    local editable = { 'diagnosis', 'measures', 'medications', 'report', 'status' }
    for _, f in ipairs(editable) do
        if data[f] ~= nil then
            local v = tostring(data[f])
            if f == 'status' and not MT.Util.TreatmentStatuses[v] then v = t.status end
            sets[#sets + 1] = ('`%s` = ?'):format(f); params[#params + 1] = v:sub(1, 4000)
            oldv[f] = t[f]; newv[f] = v
        end
    end
    if data.internal_note ~= nil and ctx.can('notes.internal.view') then
        sets[#sets + 1] = 'internal_note = ?'; params[#params + 1] = tostring(data.internal_note):sub(1, 2000)
    end
    if #sets == 0 then return MT.fail('invalid_input') end
    params[#params + 1] = t.id
    MT.DB.update('UPDATE mt_treatments SET ' .. table.concat(sets, ', ') .. ' WHERE id = ?', params)

    MT.Audit.log(ctx, { category = 'default', action = 'treatment.update', target_type = 'treatment',
        target_id = t.id, old = oldv, new = newv })
    return { ok = true, message = MT.L('saved') }
end)

MT.register('treatment.archive', { perm = 'treatment.archive', feature = 'treatments' }, function(ctx, data)
    local t = MT.DB.single('SELECT * FROM mt_treatments WHERE id = ?', { tonumber(data.id) })
    if not t then return MT.fail('invalid_input') end
    MT.DB.update("UPDATE mt_treatments SET status='archived', archived_at=NOW() WHERE id=?", { t.id })
    MT.Audit.log(ctx, { category = 'default', action = 'treatment.archive', target_type = 'treatment', target_id = t.id })
    return { ok = true, message = MT.L('treatment_archived') }
end)
