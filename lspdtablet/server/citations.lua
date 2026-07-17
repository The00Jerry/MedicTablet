--[[
    Anzeigen / Bussgelder.
    Der Bussgeldbetrag wird ueber den Billing-Adapter (CodeM Billing V2 / ESX) gebucht.
    Haft (Monate) und Punkte werden protokolliert (Uebergabe an ein Jail-/Punktesystem
    kann per Export angebunden werden – siehe README). Idempotent gegen Doppelausstellung.
]]

PD = PD or {}
local processing = {}

local function genChargeNo() return ('AZ-%s-%04d'):format(os.date('%Y%m%d'), math.random(0, 9999)) end

PD.register('citations.preview', { perm = 'citation.create', feature = 'citations' }, function(ctx, data)
    local lines, totals, err = PD.Penal.buildLines(ctx, data.items or {})
    if not lines then return PD.fail(err) end
    return { lines = lines, totals = totals }
end)

PD.register('citations.create', { perm = 'citation.create', feature = 'citations' }, function(ctx, data)
    local identifier = tostring(data.identifier or '')
    local idem = tostring(data.idempotency_key or '')
    if identifier == '' or #idem < 8 then return PD.fail('invalid_input') end

    if processing[idem] then return PD.fail('charge_duplicate') end
    processing[idem] = true
    local function release() processing[idem] = nil end

    local existing = PD.DB.single('SELECT id, status FROM pd_charges WHERE idempotency_key = ?', { idem })
    if existing then
        release()
        if existing.status == 'issued' then return { ok = true, duplicate = true, charge_id = existing.id, message = PD.L('charge_ok') } end
        return PD.fail('charge_duplicate')
    end

    local rec = PD.Citizens.ensure(identifier)
    if not rec then release(); return PD.fail('player_not_found') end

    local lines, totals, err = PD.Penal.buildLines(ctx, data.items or {})
    if not lines then release(); return PD.fail(err) end
    if totals.fine <= 0 and totals.jail <= 0 then release(); return PD.fail('invalid_amount') end

    local reason = tostring(data.reason or ''):sub(1, 200)
    if reason == '' then reason = 'Anzeige LSPD' end

    local no = genChargeNo()
    local chargeId = PD.DB.insert([[INSERT INTO pd_charges
        (charge_no, idempotency_key, citizen_id, identifier, officer_identifier, officer_name, report_id,
         fine_total, jail_total, points_total, reason, provider, status)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?, 'pending')]],
        { no, idem, rec.id, identifier, ctx.identifier, ctx.name, tonumber(data.report_id),
          totals.fine, totals.jail, totals.points, reason, Config.Billing.provider })
    if not chargeId then
        release()
        local dup = PD.DB.single('SELECT id FROM pd_charges WHERE idempotency_key = ?', { idem })
        if dup then return PD.fail('charge_duplicate') end
        return PD.fail('db_error')
    end

    for _, l in ipairs(lines) do
        PD.DB.insert('INSERT INTO pd_charge_items (charge_id, code, label, fine, jail, points, quantity) VALUES (?,?,?,?,?,?,?)',
            { chargeId, l.code, l.label, l.fine, l.jail, l.points, l.quantity })
    end

    -- Bussgeld buchen (nur wenn > 0). Haft/Punkte werden gespeichert.
    local provider, providerId = 'none', nil
    if totals.fine > 0 then
        local label = ('%s | %s'):format(Config.Branding.shortName, reason)
        local ok, res = PD.Billing.createInvoice({
            targetIdentifier = identifier, officerIdentifier = ctx.identifier,
            society = Config.Billing.society, label = label, amount = totals.fine, reason = reason,
        })
        if not ok then
            PD.DB.update("UPDATE pd_charges SET status='failed', error=? WHERE id=?", { tostring(res), chargeId })
            PD.Audit.log(ctx, { category = 'citations', action = 'citation.create', result = 'error', target_type = 'charge', target_id = chargeId, new = { error = res, fine = totals.fine } })
            release()
            return PD.fail(res or 'invoice_failed')
        end
        provider, providerId = res.provider, res.providerInvoiceId
    end

    PD.DB.update("UPDATE pd_charges SET status='issued', provider=?, provider_invoice_id=? WHERE id=?", { provider, providerId, chargeId })
    PD.Audit.log(ctx, { category = 'citations', action = 'citation.create', result = 'ok', target_type = 'charge', target_id = chargeId,
        new = { no = no, fine = totals.fine, jail = totals.jail, points = totals.points, provider = provider } })

    release()
    return { ok = true, charge_id = chargeId, charge_no = no, totals = totals, provider = provider, message = PD.L('charge_ok') }
end)

PD.register('citations.cancel', { perm = 'citation.cancel', feature = 'citations' }, function(ctx, data)
    local c = PD.DB.single('SELECT * FROM pd_charges WHERE id = ?', { tonumber(data.id) })
    if not c then return PD.fail('invalid_input') end
    if c.status == 'cancelled' then return { ok = true } end
    PD.DB.update("UPDATE pd_charges SET status='cancelled', error=? WHERE id=?", { ('storniert: ' .. tostring(data.reason or '')):sub(1, 250), c.id })
    PD.Audit.log(ctx, { category = 'citations', action = 'citation.cancel', target_type = 'charge', target_id = c.id, new = { reason = data.reason } })
    return { ok = true, message = PD.L('charge_cancelled') }
end)
