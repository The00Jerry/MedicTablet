--[[
    Rechnungserstellung (CodeM Billing V2 via Adapter) + Kostenaufschluesselung.

    Ablauf:
      1. billing.preview  -> serverseitige Kostenaufteilung (Section 11) fuer die UI.
      2. billing.create   -> validiert erneut serverseitig, erstellt idempotent eine
                             Rechnungsreferenz, ruft den Billing-Adapter, speichert
                             die unveraenderliche Momentaufnahme (Section 12).

    Doppelausstellung wird verhindert durch:
      * UNIQUE(idempotency_key) in der DB,
      * einen In-Memory-Lock je idempotency_key waehrend der Verarbeitung.
]]

MT = MT or {}
MT.BillingSvc = {}

local processing = {} -- [idempotency_key] = true (In-Flight-Lock)

local function genInvoiceNo()
    return ('RG-%s-%04d'):format(os.date('%Y%m%d'), math.random(0, 9999))
end

-- Ermittelt Basisbetrag + Positionen (aus Items ODER Behandlung)
local function resolveLines(ctx, data)
    if data.treatment_id then
        local t = MT.DB.single('SELECT * FROM mt_treatments WHERE id = ?', { tonumber(data.treatment_id) })
        if not t then return nil, 0, 'invalid_input', nil end
        local items = MT.DB.query('SELECT item_code, label, unit_price, quantity, line_total FROM mt_treatment_items WHERE treatment_id = ?', { t.id }) or {}
        local base = 0
        for _, l in ipairs(items) do base = base + (l.line_total or 0) end
        return items, base, nil, t
    else
        local lines, base, errKey = MT.Pricelist.buildLines(ctx, data.items or {})
        if not lines then return nil, 0, errKey, nil end
        return lines, base, nil, nil
    end
end

-- Vollstaendige Kostenaufteilung berechnen
local function computeBreakdown(ctx, identifier, base, discountReq)
    local snap = MT.Insurance.calc(identifier, base)
    local discount = MT.Util.clampInt(discountReq or 0, 0, math.max(0, base - snap.covered))
    if discount > 0 and not ctx.can('discount.grant') then
        return nil, 'no_permission'
    end
    local final = math.max(0, base - snap.covered - discount)
    return {
        base = base,
        insurance = snap,
        discount = discount,
        final = final,
    }
end

-----------------------------------------------------------------------------
-- Vorschau
-----------------------------------------------------------------------------
MT.register('billing.preview', { perm = 'invoice.create', feature = 'invoicing' }, function(ctx, data)
    local identifier = tostring(data.identifier or '')

    local lines, base, errKey, treatment = resolveLines(ctx, data)
    if not lines then return MT.fail(errKey) end
    -- Bei Rechnung aus Behandlung ist der Patient autoritativ die Behandlung
    if treatment and treatment.identifier then identifier = treatment.identifier end
    if identifier == '' then return MT.fail('invalid_input') end
    if base <= 0 then return MT.fail('invalid_amount') end

    local bd, perr = computeBreakdown(ctx, identifier, base, data.discount)
    if not bd then return MT.fail(perr) end

    return {
        lines = lines,
        breakdown = bd,
        -- Aufbereitete Anzeige-Werte (Section 11)
        display = {
            amount_base       = bd.base,
            insurance_name    = bd.insurance.tier_label,
            insurance_key     = bd.insurance.tier_key,
            insurance_pct     = bd.insurance.pct,
            insurance_covered = bd.insurance.covered,
            insurance_status  = bd.insurance.status_at_time,
            coverable         = bd.insurance.coverable,
            reason_key        = bd.insurance.reason,
            weekly_cap        = bd.insurance.weekly_cap,
            weekly_remaining  = bd.insurance.weekly_remaining,
            discount          = bd.discount,
            amount_final      = bd.final,
        },
    }
end)

-----------------------------------------------------------------------------
-- Erstellen (idempotent)
-----------------------------------------------------------------------------
MT.register('billing.create', { perm = 'invoice.create', feature = 'invoicing' }, function(ctx, data)
    local identifier = tostring(data.identifier or '')
    local idem = tostring(data.idempotency_key or '')
    if identifier == '' or #idem < 8 then return MT.fail('invalid_input') end

    -- In-Flight-Lock
    if processing[idem] then return MT.fail('invoice_duplicate') end
    processing[idem] = true
    local function release() processing[idem] = nil end

    -- Bereits erstellt?
    local existing = MT.DB.single('SELECT id, status, provider_invoice_id FROM mt_invoice_refs WHERE idempotency_key = ?', { idem })
    if existing then
        release()
        if existing.status == 'issued' then
            return { ok = true, duplicate = true, invoice_id = existing.id, message = MT.L('invoice_ok') }
        end
        return MT.fail('invoice_duplicate')
    end

    local lines, base, errKey, treatment = resolveLines(ctx, data)
    if not lines then release(); return MT.fail(errKey) end
    -- Bei Rechnung aus Behandlung ist der Patient autoritativ die Behandlung
    if treatment and treatment.identifier then identifier = treatment.identifier end
    if base <= 0 then release(); return MT.fail('invalid_amount') end

    local rec = MT.Patients.ensureRecord(identifier)
    if not rec then release(); return MT.fail('player_not_found') end

    local bd, perr = computeBreakdown(ctx, identifier, base, data.discount)
    if not bd then release(); return MT.fail(perr) end
    if bd.final < 0 then release(); return MT.fail('invalid_amount') end

    local reason = tostring(data.reason or ''):sub(1, 200)
    if reason == '' then reason = treatment and ('Behandlung ' .. treatment.treatment_no) or 'Medizinische Leistung' end

    -- Rechnungsreferenz (pending) anlegen – UNIQUE(idempotency_key) schuetzt zusaetzlich
    local invNo = genInvoiceNo()
    local invId = MT.DB.insert([[INSERT INTO mt_invoice_refs
        (invoice_no, idempotency_key, treatment_id, patient_id, identifier, medic_identifier, medic_name, reason,
         amount_base, insurance_tier_key, insurance_tier_label, insurance_pct, insurance_amount, insurance_cap_applied,
         insurance_status_at_time, discount_amount, amount_final, settlement_mode, provider, status)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?, 'pending')]],
        { invNo, idem, treatment and treatment.id or nil, rec.id, identifier, ctx.identifier, ctx.name, reason,
          bd.base, bd.insurance.tier_key, bd.insurance.tier_label, bd.insurance.pct, bd.insurance.covered,
          bd.insurance.cap_applied, bd.insurance.status_at_time, bd.discount, bd.final,
          Config.Insurance.SettlementMode, Config.Billing.provider })

    if not invId then
        release()
        -- Sehr wahrscheinlich Duplicate-Key durch parallelen Klick
        local dup = MT.DB.single('SELECT id FROM mt_invoice_refs WHERE idempotency_key = ?', { idem })
        if dup then return MT.fail('invoice_duplicate') end
        return MT.fail('db_error')
    end

    -- Positionen-Snapshot speichern
    for _, l in ipairs(lines) do
        MT.DB.insert('INSERT INTO mt_invoice_items (invoice_id, item_code, label, unit_price, quantity, line_total) VALUES (?,?,?,?,?,?)',
            { invId, l.item_code, l.label, l.unit_price, l.quantity, l.line_total })
    end

    -- Billing-Adapter aufrufen (nur der endgueltige Patientenbetrag!)
    local label = ('%s | %s'):format(Config.Branding.clinicName, reason)
    local ok, res = MT.Billing.createInvoice({
        targetIdentifier = identifier,
        medicIdentifier  = ctx.identifier,
        society          = Config.Billing.society,
        label            = label,
        amount           = bd.final,
        reason           = reason,
    })

    if not ok then
        MT.DB.update("UPDATE mt_invoice_refs SET status='failed', error=? WHERE id=?", { tostring(res), invId })
        MT.Audit.log(ctx, { category = 'billing', action = 'invoice.create', result = 'error',
            target_type = 'invoice', target_id = invId, new = { error = res, amount = bd.final } })
        release()
        return MT.fail(res or 'invoice_failed')
    end

    -- Erfolg persistieren
    MT.DB.update("UPDATE mt_invoice_refs SET status='issued', provider=?, provider_invoice_id=? WHERE id=?",
        { res.provider, res.providerInvoiceId, invId })

    -- Versicherungserstattung fuer Wochenlimit protokollieren
    if bd.insurance.covered > 0 then
        MT.Insurance.recordReimbursement(identifier, invId, bd.insurance.tier_key, bd.insurance.covered)
    end

    -- Optionale Verrechnung des Versicherungsanteils (Config.Insurance.SettlementMode).
    -- Standard 'patient_only': keine Zusatzbuchung (an Billing ging bereits nur der Patientenbetrag).
    if Config.Insurance.SettlementMode ~= 'patient_only' and bd.insurance.covered > 0 then
        local credited = MT.Account.creditSociety(('society_%s'):format(Config.Billing.society), bd.insurance.covered)
        if not credited then
            MT.Util.warn(('SettlementMode "%s": Versicherungsanteil konnte nicht der Society gutgeschrieben werden (kein passendes Kontosystem).'):format(Config.Insurance.SettlementMode))
        end
        MT.Audit.log(ctx, { category = 'billing', action = 'invoice.insurance_settlement',
            target_type = 'invoice', target_id = invId,
            new = { mode = Config.Insurance.SettlementMode, amount = bd.insurance.covered, credited = credited and true or false } })
    end

    -- Behandlung verknuepfen/abschliessen
    if treatment then
        MT.DB.update([[UPDATE mt_treatments SET amount_base=?, amount_insurance=?, amount_discount=?, amount_final=?,
            status = CASE WHEN status IN ('draft','ongoing') THEN 'completed' ELSE status END WHERE id=?]],
            { bd.base, bd.insurance.covered, bd.discount, bd.final, treatment.id })
    end

    MT.Audit.log(ctx, { category = 'billing', action = 'invoice.create', result = 'ok',
        target_type = 'invoice', target_id = invId,
        new = { no = invNo, base = bd.base, insurance = bd.insurance.covered, discount = bd.discount,
                final = bd.final, provider = res.provider, provider_id = res.providerInvoiceId } })

    release()
    return {
        ok = true, invoice_id = invId, invoice_no = invNo,
        provider = res.provider, provider_invoice_id = res.providerInvoiceId,
        breakdown = bd, message = MT.L('invoice_ok'),
    }
end)

-----------------------------------------------------------------------------
-- Stornieren
-----------------------------------------------------------------------------
MT.register('billing.cancel', { perm = 'invoice.cancel', feature = 'invoicing' }, function(ctx, data)
    local inv = MT.DB.single('SELECT * FROM mt_invoice_refs WHERE id = ?', { tonumber(data.id) })
    if not inv then return MT.fail('invalid_input') end
    if inv.status == 'cancelled' then return { ok = true } end

    MT.DB.update("UPDATE mt_invoice_refs SET status='cancelled', error=? WHERE id=?",
        { ('storniert: ' .. tostring(data.reason or '')):sub(1, 250), inv.id })

    -- Erstattung fuer Wochenlimit zuruecknehmen (Gegenbuchung)
    if inv.insurance_amount and inv.insurance_amount > 0 then
        MT.DB.insert('INSERT INTO mt_insurance_reimbursements (identifier, invoice_id, tier_key, amount, week_key) VALUES (?,?,?,?,?)',
            { inv.identifier, inv.id, inv.insurance_tier_key, -inv.insurance_amount, MT.Util.weekKey() })
    end

    MT.Audit.log(ctx, { category = 'billing', action = 'invoice.cancel', target_type = 'invoice',
        target_id = inv.id, old = { status = inv.status }, new = { status = 'cancelled', reason = data.reason } })
    return { ok = true, message = MT.L('invoice_cancelled') }
end)
