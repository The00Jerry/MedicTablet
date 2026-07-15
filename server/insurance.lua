--[[
    Krankenversicherung: Vertraege, serverseitige Kostenberechnung, NPC-Aktionen,
    Verwaltung. Die Berechnung erfolgt AUSSCHLIESSLICH serverseitig.
]]

MT = MT or {}
MT.Insurance = {}

-----------------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------------
function MT.Insurance.getTiers(activeOnly)
    local sql = 'SELECT * FROM mt_insurance_tiers'
    if activeOnly then sql = sql .. ' WHERE active = 1' end
    sql = sql .. ' ORDER BY weekly_premium ASC'
    return MT.DB.query(sql) or {}
end

function MT.Insurance.getTierByKey(key)
    return MT.DB.single('SELECT * FROM mt_insurance_tiers WHERE tier_key = ?', { key })
end

function MT.Insurance.getContract(identifier)
    return MT.DB.single('SELECT * FROM mt_insurance_contracts WHERE identifier = ?', { identifier })
end

-- Naechster Abbuchungszeitpunkt als DATETIME-String (Serverzeit)
function MT.Insurance.nextChargeAt(fromTs)
    local b = Config.Insurance.Billing
    fromTs = fromTs or os.time()
    local targetLuaWday = (b.weekday % 7) + 1 -- Config Mo=1..So=7 -> Lua So=1..Sa=7
    for dayOffset = 0, 7 do
        local ts = fromTs + dayOffset * 86400
        local t = os.date('*t', ts)
        if t.wday == targetLuaWday then
            t.hour, t.min, t.sec = b.hour, b.minute, 0
            local candidate = os.time(t)
            if candidate > fromTs then
                return os.date('%Y-%m-%d %H:%M:%S', candidate)
            end
        end
    end
    -- Fallback: in 7 Tagen
    return os.date('%Y-%m-%d %H:%M:%S', fromTs + 7 * 86400)
end

-- Ist die aktuelle Woche bereits bezahlt?
function MT.Insurance.currentWeekPaid(contract)
    if not contract then return false end
    local wk = MT.Util.weekKey()
    if (tonumber(contract.last_week_key) or 0) >= wk then return true end
    local p = MT.DB.single('SELECT status FROM mt_insurance_premiums WHERE identifier = ? AND week_key = ?',
        { contract.identifier, wk })
    return p ~= nil and p.status == 'paid'
end

-- Deckung aktiv? -> covered(bool), reasonKey
function MT.Insurance.isCovered(contract)
    if not contract then return false, 'ins_none' end
    if contract.status == 'cancelled' then return false, 'ins_none' end
    if contract.status == 'paused' then return false, 'ins_paused' end
    if contract.status == 'waiting' then
        return false, 'ins_waiting'
    end
    -- Wartezeit noch aktiv?
    if contract.waiting_until then
        local wu = MT.DB.scalar('SELECT (NOW() < ?)', { contract.waiting_until })
        if tonumber(wu) == 1 then return false, 'ins_waiting' end
    end
    if not MT.Insurance.currentWeekPaid(contract) then
        -- Beitrag der laufenden Woche nicht bezahlt -> keine Uebernahme
        -- (Grace/pending zaehlt nicht als bezahlt)
        return false, 'ins_charge_failed'
    end
    return true, nil
end

-- Woechentlich bereits erstattete Summe
function MT.Insurance.weeklyReimbursed(identifier)
    local wk = MT.Util.weekKey()
    local s = MT.DB.scalar('SELECT COALESCE(SUM(amount),0) FROM mt_insurance_reimbursements WHERE identifier = ? AND week_key = ?',
        { identifier, wk })
    return tonumber(s) or 0
end

--[[ Serverseitige Kostenberechnung fuer einen Basisbetrag.
     return snapshot = {
       base, tier_key, tier_label, pct, covered, cap_applied, status_at_time,
       coverable(bool), reason, weekly_cap, weekly_remaining, max_per_invoice
     } ]]
function MT.Insurance.calc(identifier, base)
    base = MT.Util.clampInt(base, 0)
    local snap = {
        base = base, tier_key = '', tier_label = '', pct = 0, covered = 0,
        cap_applied = 0, status_at_time = 'none', coverable = false, reason = 'ins_none',
        weekly_cap = 0, weekly_remaining = 0, max_per_invoice = 0,
    }
    local contract = MT.Insurance.getContract(identifier)
    if not contract then return snap end

    local tier = MT.DB.single('SELECT * FROM mt_insurance_tiers WHERE id = ?', { contract.tier_id })
    if not tier then return snap end

    snap.tier_key = tier.tier_key
    snap.tier_label = tier.label
    snap.pct = tier.coverage_pct
    snap.status_at_time = contract.status
    snap.max_per_invoice = tier.max_per_invoice
    snap.weekly_cap = tier.weekly_cap

    local covered, reason = MT.Insurance.isCovered(contract)
    snap.coverable = covered
    snap.reason = reason or 'ok'

    -- verbleibendes Wochenlimit (Anzeige immer)
    local remaining = -1 -- unbegrenzt
    if tier.weekly_cap and tier.weekly_cap > 0 then
        remaining = math.max(0, tier.weekly_cap - MT.Insurance.weeklyReimbursed(identifier))
    end
    snap.weekly_remaining = remaining

    if not covered then
        return snap
    end

    local raw = math.floor(base * tier.coverage_pct / 100)
    if tier.max_per_invoice and tier.max_per_invoice > 0 then
        raw = math.min(raw, tier.max_per_invoice)
    end
    if remaining >= 0 then
        raw = math.min(raw, remaining)
    end
    raw = math.min(raw, base)
    snap.covered = math.max(0, raw)
    snap.cap_applied = (remaining >= 0) and remaining or 0
    return snap
end

-- Sicht fuer UI (Akte / NPC)
function MT.Insurance.getContractView(identifier)
    local contract = MT.Insurance.getContract(identifier)
    if not contract then
        return { hasContract = false }
    end
    local tier = MT.DB.single('SELECT * FROM mt_insurance_tiers WHERE id = ?', { contract.tier_id })
    local covered, reason = MT.Insurance.isCovered(contract)
    return {
        hasContract = true,
        tier = tier,
        status = contract.status,
        coverable = covered,
        reason = reason,
        started_at = contract.started_at,
        next_charge_at = contract.next_charge_at,
        last_charge_at = contract.last_charge_at,
        grace_until = contract.grace_until,
        waiting_until = contract.waiting_until,
        cancel_effective_at = contract.cancel_effective_at,
        failed_count = contract.failed_count,
        weekly_remaining = (tier and tier.weekly_cap > 0)
            and math.max(0, tier.weekly_cap - MT.Insurance.weeklyReimbursed(identifier)) or -1,
    }
end

-- Erstattung protokollieren (beim tatsaechlichen Rechnungsversand)
function MT.Insurance.recordReimbursement(identifier, invoiceId, tierKey, amount)
    if not amount or amount <= 0 then return end
    MT.DB.insert('INSERT INTO mt_insurance_reimbursements (identifier, invoice_id, tier_key, amount, week_key) VALUES (?,?,?,?,?)',
        { identifier, invoiceId, tierKey, amount, MT.Util.weekKey() })
end

local function logChange(identifier, ctype, fromTier, toTier, actor, reason)
    MT.DB.insert([[INSERT INTO mt_insurance_changes (identifier, change_type, from_tier, to_tier, actor_identifier, reason)
        VALUES (?,?,?,?,?,?)]], { identifier, ctype, fromTier, toTier, actor or '', reason or '' })
end
MT.Insurance.logChange = logChange

-----------------------------------------------------------------------------
-- NPC / Spieler-Aktionen (open = true: kein Medic-Job noetig)
-----------------------------------------------------------------------------
MT.register('insurance.npc.get', { feature = 'insurance', open = true }, function(ctx, data)
    return {
        tiers = MT.Insurance.getTiers(true),
        contract = MT.Insurance.getContractView(ctx.identifier),
        recentCharges = MT.DB.query([[SELECT tier_key, amount, status, scheduled_at, charged_at, attempts, last_error
            FROM mt_insurance_premiums WHERE identifier = ? ORDER BY scheduled_at DESC LIMIT 8]], { ctx.identifier }) or {},
    }
end)

MT.register('insurance.npc.subscribe', { feature = 'insurance', open = true }, function(ctx, data)
    local tier = MT.Insurance.getTierByKey(tostring(data.tier_key or ''))
    if not tier or tier.active ~= 1 then return MT.fail('invalid_input') end

    local existing = MT.Insurance.getContract(ctx.identifier)
    if existing and existing.status ~= 'cancelled' then
        return MT.fail('invalid_input') -- besitzt bereits Vertrag -> Wechsel nutzen
    end

    -- Erstbeitrag sofort abbuchen (Spieler ist online am NPC)
    local ok, errKey = MT.Account.charge(ctx.identifier, Config.Insurance.Billing.account, tier.weekly_premium)
    if not ok then
        return MT.fail(errKey == 'ins_insufficient' and 'ins_insufficient' or 'invoice_failed')
    end

    local now = os.time()
    local wk = MT.Util.weekKey(now)
    local waitingUntil = (tier.waiting_days > 0)
        and os.date('%Y-%m-%d %H:%M:%S', now + tier.waiting_days * 86400) or nil
    local minTermUntil = (tier.min_term_days > 0)
        and os.date('%Y-%m-%d %H:%M:%S', now + tier.min_term_days * 86400) or nil
    local status = (tier.waiting_days > 0) and 'waiting' or 'active'

    -- Vertrag anlegen/reaktivieren (UNIQUE auf identifier -> ggf. Update)
    if existing then
        MT.DB.update([[UPDATE mt_insurance_contracts SET tier_id=?, tier_key=?, status=?, started_at=NOW(),
            waiting_until=?, min_term_until=?, cancel_effective_at=NULL, grace_until=NULL,
            next_charge_at=?, last_charge_at=NOW(), last_week_key=?, failed_count=0 WHERE identifier=?]],
            { tier.id, tier.tier_key, status, waitingUntil, minTermUntil,
              MT.Insurance.nextChargeAt(now), wk, ctx.identifier })
    else
        MT.DB.insert([[INSERT INTO mt_insurance_contracts
            (identifier,tier_id,tier_key,status,waiting_until,min_term_until,next_charge_at,last_charge_at,last_week_key)
            VALUES (?,?,?,?,?,?,?,NOW(),?)]],
            { ctx.identifier, tier.id, tier.tier_key, status, waitingUntil, minTermUntil,
              MT.Insurance.nextChargeAt(now), wk })
    end

    -- Erstbeitrag als bezahlte Premium-Zeile (idempotent je Woche)
    MT.DB.insert([[INSERT IGNORE INTO mt_insurance_premiums
        (txn_id, identifier, tier_key, amount, week_key, scheduled_at, charged_at, status, attempts)
        VALUES (?,?,?,?,?,NOW(),NOW(),'paid',1)]],
        { MT.Util.genId('PRM'), ctx.identifier, tier.tier_key, tier.weekly_premium, wk })

    logChange(ctx.identifier, 'subscribe', nil, tier.tier_key, ctx.identifier, 'NPC')
    MT.Audit.log(ctx, { category = 'insurance', action = 'insurance.subscribe', target_type = 'insurance',
        target_id = ctx.identifier, new = { tier = tier.tier_key, premium = tier.weekly_premium } })

    return { ok = true, message = MT.L('ins_subscribed'), contract = MT.Insurance.getContractView(ctx.identifier) }
end)

MT.register('insurance.npc.switch', { feature = 'insurance', open = true }, function(ctx, data)
    local contract = MT.Insurance.getContract(ctx.identifier)
    if not contract or contract.status == 'cancelled' then return MT.fail('ins_none') end
    local newTier = MT.Insurance.getTierByKey(tostring(data.tier_key or ''))
    if not newTier or newTier.active ~= 1 then return MT.fail('invalid_input') end
    if newTier.tier_key == contract.tier_key then return MT.fail('invalid_input') end

    -- Mindestlaufzeit pruefen
    if contract.min_term_until then
        local active = MT.DB.scalar('SELECT (NOW() < ?)', { contract.min_term_until })
        if tonumber(active) == 1 then return MT.fail('ins_min_term') end
    end

    local from = contract.tier_key
    MT.DB.update([[UPDATE mt_insurance_contracts SET tier_id=?, tier_key=?, status='active',
        min_term_until=?, cancel_effective_at=NULL, grace_until=NULL, failed_count=0 WHERE identifier=?]],
        { newTier.id, newTier.tier_key,
          (newTier.min_term_days > 0) and os.date('%Y-%m-%d %H:%M:%S', os.time() + newTier.min_term_days * 86400) or nil,
          ctx.identifier })

    logChange(ctx.identifier, 'switch', from, newTier.tier_key, ctx.identifier, 'NPC')
    MT.Audit.log(ctx, { category = 'insurance', action = 'insurance.switch', target_type = 'insurance',
        target_id = ctx.identifier, old = { tier = from }, new = { tier = newTier.tier_key } })
    return { ok = true, message = MT.L('ins_switched'), contract = MT.Insurance.getContractView(ctx.identifier) }
end)

MT.register('insurance.npc.cancel', { feature = 'insurance', open = true }, function(ctx, data)
    local contract = MT.Insurance.getContract(ctx.identifier)
    if not contract or contract.status == 'cancelled' then return MT.fail('ins_none') end
    local tier = MT.DB.single('SELECT * FROM mt_insurance_tiers WHERE id = ?', { contract.tier_id })

    -- Mindestlaufzeit
    if contract.min_term_until then
        local active = MT.DB.scalar('SELECT (NOW() < ?)', { contract.min_term_until })
        if tonumber(active) == 1 then return MT.fail('ins_min_term') end
    end

    -- Kuendigungsfrist
    local effective = nil
    if tier and tier.cancel_notice_days > 0 then
        effective = os.date('%Y-%m-%d %H:%M:%S', os.time() + tier.cancel_notice_days * 86400)
        MT.DB.update('UPDATE mt_insurance_contracts SET cancel_effective_at=? WHERE identifier=?', { effective, ctx.identifier })
    else
        MT.DB.update("UPDATE mt_insurance_contracts SET status='cancelled', next_charge_at=NULL WHERE identifier=?", { ctx.identifier })
    end

    logChange(ctx.identifier, 'cancel', contract.tier_key, nil, ctx.identifier, effective and ('wirksam ' .. effective) or 'sofort')
    MT.Audit.log(ctx, { category = 'insurance', action = 'insurance.cancel', target_type = 'insurance',
        target_id = ctx.identifier, old = { tier = contract.tier_key }, new = { effective = effective or 'now' } })
    return { ok = true, message = MT.L('ins_cancelled'), contract = MT.Insurance.getContractView(ctx.identifier) }
end)

-----------------------------------------------------------------------------
-- Tablet: Versicherungsuebersicht (Medic)
-----------------------------------------------------------------------------
MT.register('insurance.tiers', { perm = 'insurance.patient.view', feature = 'insurance' }, function(ctx, data)
    return { tiers = MT.Insurance.getTiers(false), canManage = ctx.can('insurance.manage') }
end)

MT.register('insurance.patientView', { perm = 'insurance.patient.view', feature = 'insurance' }, function(ctx, data)
    local identifier = tostring(data.identifier or '')
    if identifier == '' then return MT.fail('invalid_input') end
    return { contract = MT.Insurance.getContractView(identifier) }
end)

-----------------------------------------------------------------------------
-- Verwaltung (insurance.manage): Stufen speichern, Vertrag pausieren/kuendigen
-----------------------------------------------------------------------------
MT.register('insurance.saveTier', { perm = 'insurance.manage', feature = 'insurance' }, function(ctx, data)
    local tier = MT.DB.single('SELECT * FROM mt_insurance_tiers WHERE id = ?', { tonumber(data.id) })
    if not tier then return MT.fail('invalid_input') end
    local fields = { 'label','description','color','icon','weekly_premium','coverage_pct',
        'max_per_invoice','weekly_cap','active','min_term_days','cancel_notice_days','waiting_days' }
    local sets, params, oldv, newv = {}, {}, {}, {}
    for _, f in ipairs(fields) do
        if data[f] ~= nil then
            local v = data[f]
            if f == 'coverage_pct' then v = MT.Util.clampInt(v, 0, 100)
            elseif f == 'active' then v = (v == true or v == 1) and 1 or 0
            elseif f ~= 'label' and f ~= 'description' and f ~= 'color' and f ~= 'icon' then v = MT.Util.clampInt(v, 0) end
            sets[#sets + 1] = ('`%s` = ?'):format(f); params[#params + 1] = v
            oldv[f] = tier[f]; newv[f] = v
        end
    end
    if #sets == 0 then return MT.fail('invalid_input') end
    params[#params + 1] = tier.id
    MT.DB.update('UPDATE mt_insurance_tiers SET ' .. table.concat(sets, ', ') .. ' WHERE id = ?', params)
    MT.Audit.log(ctx, { category = 'insurance', action = 'insurance.tier.save', target_type = 'insurance_tier',
        target_id = tier.id, old = oldv, new = newv })
    return { ok = true }
end)

MT.register('insurance.manageContract', { perm = 'insurance.manage', feature = 'insurance' }, function(ctx, data)
    local identifier = tostring(data.identifier or '')
    local action = tostring(data.action or '')
    local contract = MT.Insurance.getContract(identifier)
    if not contract then return MT.fail('ins_none') end

    if action == 'pause' then
        MT.DB.update("UPDATE mt_insurance_contracts SET status='paused', next_charge_at=NULL WHERE identifier=?", { identifier })
        logChange(identifier, 'pause', contract.tier_key, nil, ctx.identifier, 'manuell')
    elseif action == 'resume' then
        MT.DB.update("UPDATE mt_insurance_contracts SET status='active', grace_until=NULL, failed_count=0, next_charge_at=? WHERE identifier=?",
            { MT.Insurance.nextChargeAt(), identifier })
        logChange(identifier, 'resume', nil, contract.tier_key, ctx.identifier, 'manuell')
    elseif action == 'cancel' then
        MT.DB.update("UPDATE mt_insurance_contracts SET status='cancelled', next_charge_at=NULL WHERE identifier=?", { identifier })
        logChange(identifier, 'cancel', contract.tier_key, nil, ctx.identifier, 'manuell')
    else
        return MT.fail('invalid_input')
    end
    MT.Audit.log(ctx, { category = 'insurance', action = 'insurance.manage.' .. action, target_type = 'insurance', target_id = identifier })
    return { ok = true, contract = MT.Insurance.getContractView(identifier) }
end)
