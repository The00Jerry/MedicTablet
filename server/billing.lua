--[[
    Rechnungserstellung (CodeM Billing V2 via Adapter) + Kostenaufschluesselung.

    Der eigentliche Erstellungs-Kern liegt in MT.BillingSvc.create(opts) und wird von
    ZWEI Aufrufern genutzt:
      * dem In-Game-NUI-Handler 'billing.create' (Kontext = Medic im Spiel),
      * dem Web-Bridge-Poller (server/webbridge.lua), der Rechnungen aus der
        Warteschlange der externen Web-App abarbeitet.

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

-- Ermittelt Basisbetrag + Positionen (aus Items ODER Behandlung).
-- actor muss actor.can(perm) bereitstellen (fuer item.required_perm-Pruefung).
local function resolveLines(actor, data)
    if data.treatment_id then
        local t = MT.DB.single('SELECT * FROM mt_treatments WHERE id = ?', { tonumber(data.treatment_id) })
        if not t then return nil, 0, 'invalid_input', nil end
        local items = MT.DB.query('SELECT item_code, label, unit_price, quantity, line_total FROM mt_treatment_items WHERE treatment_id = ?', { t.id }) or {}
        local base = 0
        for _, l in ipairs(items) do base = base + (l.line_total or 0) end
        return items, base, nil, t
    else
        local lines, base, errKey = MT.Pricelist.buildLines(actor, data.items or {})
        if not lines then return nil, 0, errKey, nil end
        return lines, base, nil, nil
    end
end

-- Vollstaendige Kostenaufteilung berechnen (serverseitig, nicht manipulierbar).
local function computeBreakdown(actor, identifier, base, discountReq)
    local snap = MT.Insurance.calc(identifier, base)
    local discount = MT.Util.clampInt(discountReq or 0, 0, math.max(0, base - snap.covered))
    if discount > 0 and not actor.can('discount.grant') then
        return nil, 'no_permission'
    end
    local final = math.max(0, base - snap.covered - discount)
    return { base = base, insurance = snap, discount = discount, final = final }
end
MT.BillingSvc.computeBreakdown = computeBreakdown
MT.BillingSvc.resolveLines = resolveLines

--[[ KERN: erstellt idempotent eine Rechnung.
     opts = {
       identifier      = Patient (permanenter Identifier; bei treatment_id aus Behandlung),
       items|treatment_id, discount, reason, idempotency_key,
       actor = { identifier, name, can(perm) },  -- Ausfuehrender (Medic ODER Web-User)
       source = 'ingame'|'web',
     }
     return ok(boolean), resultTable | errKey ]]
function MT.BillingSvc.create(opts)
    local actor = opts.actor
    local identifier = tostring(opts.identifier or '')
    local idem = tostring(opts.idempotency_key or '')
    if #idem < 8 then return false, 'invalid_input' end

    if processing[idem] then return false, 'invoice_duplicate' end
    processing[idem] = true
    local function release() processing[idem] = nil end

    local existing = MT.DB.single('SELECT id, status FROM mt_invoice_refs WHERE idempotency_key = ?', { idem })
    if existing then
        release()
        if existing.status == 'issued' then
            return true, { duplicate = true, invoice_id = existing.id, message = MT.L('invoice_ok') }
        end
        return false, 'invoice_duplicate'
    end

    local lines, base, errKey, treatment = resolveLines(actor, opts)
    if not lines then release(); return false, errKey end
    if treatment and treatment.identifier then identifier = treatment.identifier end
    if identifier == '' then release(); return false, 'invalid_input' end
    if base <= 0 then release(); return false, 'invalid_amount' end

    local rec = MT.Patients.ensureRecord(identifier)
    if not rec then release(); return false, 'player_not_found' end

    local bd, perr = computeBreakdown(actor, identifier, base, opts.discount)
    if not bd then release(); return false, perr end
    if bd.final < 0 then release(); return false, 'invalid_amount' end

    local reason = tostring(opts.reason or ''):sub(1, 200)
    if reason == '' then reason = treatment and ('Behandlung ' .. treatment.treatment_no) or 'Medizinische Leistung' end

    local invNo = genInvoiceNo()
    local invId = MT.DB.insert([[INSERT INTO mt_invoice_refs
        (invoice_no, idempotency_key, treatment_id, patient_id, identifier, medic_identifier, medic_name, reason,
         amount_base, insurance_tier_key, insurance_tier_label, insurance_pct, insurance_amount, insurance_cap_applied,
         insurance_status_at_time, discount_amount, amount_final, settlement_mode, provider, status)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?, 'pending')]],
        { invNo, idem, treatment and treatment.id or nil, rec.id, identifier, actor.identifier, actor.name, reason,
          bd.base, bd.insurance.tier_key, bd.insurance.tier_label, bd.insurance.pct, bd.insurance.covered,
          bd.insurance.cap_applied, bd.insurance.status_at_time, bd.discount, bd.final,
          Config.Insurance.SettlementMode, Config.Billing.provider })

    if not invId then
        release()
        local dup = MT.DB.single('SELECT id FROM mt_invoice_refs WHERE idempotency_key = ?', { idem })
        if dup then return false, 'invoice_duplicate' end
        return false, 'db_error'
    end

    for _, l in ipairs(lines) do
        MT.DB.insert('INSERT INTO mt_invoice_items (invoice_id, item_code, label, unit_price, quantity, line_total) VALUES (?,?,?,?,?,?)',
            { invId, l.item_code, l.label, l.unit_price, l.quantity, l.line_total })
    end

    -- Billing-Adapter (nur der endgueltige Patientenbetrag!)
    local label = ('%s | %s'):format(Config.Branding.clinicName, reason)
    local ok, res = MT.Billing.createInvoice({
        targetIdentifier = identifier,
        medicIdentifier  = actor.identifier,
        society          = Config.Billing.society,
        label            = label,
        amount           = bd.final,
        reason           = reason,
    })

    local auditCtx = { identifier = actor.identifier, name = actor.name, discord = actor.discord }

    if not ok then
        MT.DB.update("UPDATE mt_invoice_refs SET status='failed', error=? WHERE id=?", { tostring(res), invId })
        MT.Audit.log(auditCtx, { category = 'billing', action = 'invoice.create', result = 'error',
            target_type = 'invoice', target_id = invId, reason = opts.source or 'ingame',
            new = { error = res, amount = bd.final } })
        release()
        return false, res or 'invoice_failed'
    end

    MT.DB.update("UPDATE mt_invoice_refs SET status='issued', provider=?, provider_invoice_id=? WHERE id=?",
        { res.provider, res.providerInvoiceId, invId })

    if bd.insurance.covered > 0 then
        MT.Insurance.recordReimbursement(identifier, invId, bd.insurance.tier_key, bd.insurance.covered)
    end

    if Config.Insurance.SettlementMode ~= 'patient_only' and bd.insurance.covered > 0 then
        local credited = MT.Account.creditSociety(('society_%s'):format(Config.Billing.society), bd.insurance.covered)
        if not credited then
            MT.Util.warn(('SettlementMode "%s": Versicherungsanteil nicht der Society gutgeschrieben (kein Kontosystem).'):format(Config.Insurance.SettlementMode))
        end
        MT.Audit.log(auditCtx, { category = 'billing', action = 'invoice.insurance_settlement',
            target_type = 'invoice', target_id = invId,
            new = { mode = Config.Insurance.SettlementMode, amount = bd.insurance.covered, credited = credited and true or false } })
    end

    if treatment then
        MT.DB.update([[UPDATE mt_treatments SET amount_base=?, amount_insurance=?, amount_discount=?, amount_final=?,
            status = CASE WHEN status IN ('draft','ongoing') THEN 'completed' ELSE status END WHERE id=?]],
            { bd.base, bd.insurance.covered, bd.discount, bd.final, treatment.id })
    end

    MT.Audit.log(auditCtx, { category = 'billing', action = 'invoice.create', result = 'ok',
        target_type = 'invoice', target_id = invId, reason = opts.source or 'ingame',
        new = { no = invNo, base = bd.base, insurance = bd.insurance.covered, discount = bd.discount,
                final = bd.final, provider = res.provider, provider_id = res.providerInvoiceId } })

    release()
    return true, {
        invoice_id = invId, invoice_no = invNo,
        provider = res.provider, provider_invoice_id = res.providerInvoiceId,
        breakdown = bd, message = MT.L('invoice_ok'),
    }
end

-----------------------------------------------------------------------------
-- NUI: Vorschau
-----------------------------------------------------------------------------
MT.register('billing.preview', { perm = 'invoice.create', feature = 'invoicing' }, function(ctx, data)
    local identifier = tostring(data.identifier or '')
    local lines, base, errKey, treatment = resolveLines(ctx, data)
    if not lines then return MT.fail(errKey) end
    if treatment and treatment.identifier then identifier = treatment.identifier end
    if identifier == '' then return MT.fail('invalid_input') end
    if base <= 0 then return MT.fail('invalid_amount') end

    local bd, perr = computeBreakdown(ctx, identifier, base, data.discount)
    if not bd then return MT.fail(perr) end

    return {
        lines = lines, breakdown = bd,
        display = {
            amount_base = bd.base, insurance_name = bd.insurance.tier_label, insurance_key = bd.insurance.tier_key,
            insurance_pct = bd.insurance.pct, insurance_covered = bd.insurance.covered,
            insurance_status = bd.insurance.status_at_time, coverable = bd.insurance.coverable,
            reason_key = bd.insurance.reason, weekly_cap = bd.insurance.weekly_cap,
            weekly_remaining = bd.insurance.weekly_remaining, discount = bd.discount, amount_final = bd.final,
        },
    }
end)

-----------------------------------------------------------------------------
-- NUI: Erstellen (delegiert an den Kern)
-----------------------------------------------------------------------------
MT.register('billing.create', { perm = 'invoice.create', feature = 'invoicing' }, function(ctx, data)
    local ok, res = MT.BillingSvc.create({
        identifier = tostring(data.identifier or ''),
        items = data.items, treatment_id = data.treatment_id,
        discount = data.discount, reason = data.reason,
        idempotency_key = tostring(data.idempotency_key or ''),
        actor = { identifier = ctx.identifier, name = ctx.name, discord = ctx.discord, can = ctx.can },
        source = 'ingame',
    })
    if not ok then return MT.fail(res) end
    res.ok = true
    return res
end)

-----------------------------------------------------------------------------
-- NUI: Stornieren
-----------------------------------------------------------------------------
MT.register('billing.cancel', { perm = 'invoice.cancel', feature = 'invoicing' }, function(ctx, data)
    local inv = MT.DB.single('SELECT * FROM mt_invoice_refs WHERE id = ?', { tonumber(data.id) })
    if not inv then return MT.fail('invalid_input') end
    if inv.status == 'cancelled' then return { ok = true } end

    MT.DB.update("UPDATE mt_invoice_refs SET status='cancelled', error=? WHERE id=?",
        { ('storniert: ' .. tostring(data.reason or '')):sub(1, 250), inv.id })

    if inv.insurance_amount and inv.insurance_amount > 0 then
        MT.DB.insert('INSERT INTO mt_insurance_reimbursements (identifier, invoice_id, tier_key, amount, week_key) VALUES (?,?,?,?,?)',
            { inv.identifier, inv.id, inv.insurance_tier_key, -inv.insurance_amount, MT.Util.weekKey() })
    end

    MT.Audit.log(ctx, { category = 'billing', action = 'invoice.cancel', target_type = 'invoice',
        target_id = inv.id, old = { status = inv.status }, new = { status = 'cancelled', reason = data.reason } })
    return { ok = true, message = MT.L('invoice_cancelled') }
end)
