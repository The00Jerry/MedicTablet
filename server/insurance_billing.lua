--[[
    Woechentliche Versicherungsbeitraege (Offline-faehig, idempotent).

    * Scheduler prueft periodisch faellige Vertraege.
    * Idempotenz: UNIQUE(identifier, week_key) in mt_insurance_premiums verhindert,
      dass fuer dieselbe Versicherungswoche doppelt abgebucht wird.
    * Offline-Abbuchung erfolgt ueber den Account-Adapter (DB), online ueber ESX.
    * Verhalten bei fehlendem Guthaben ist konfigurierbar (Kulanz -> Pause/Kuendigung).
]]

MT = MT or {}
MT.InsBilling = {}

local B = function() return Config.Insurance.Billing end

-- Benachrichtigung an Online-Spieler (optional)
function MT.notifyIdentifier(identifier, ntype, message)
    local xp = MT.Account.getOnline(identifier)
    if xp and xp.source then
        TriggerClientEvent('medictablet:cl:notify', xp.source, ntype, message)
    end
end

local function notifyCfg(key, identifier, message)
    if B().notify[key] then MT.notifyIdentifier(identifier, key, message) end
end

-- Get-or-create Premium-Zeile fuer eine Woche (idempotent)
local function ensurePremium(contract, wk, tier)
    MT.DB.insert([[INSERT IGNORE INTO mt_insurance_premiums
        (txn_id, identifier, contract_id, tier_key, amount, week_key, scheduled_at, status, attempts)
        VALUES (?,?,?,?,?,?,NOW(),'pending',0)]],
        { MT.Util.genId('PRM'), contract.identifier, contract.id, tier.tier_key, tier.weekly_premium, wk })
    return MT.DB.single('SELECT * FROM mt_insurance_premiums WHERE identifier = ? AND week_key = ?',
        { contract.identifier, wk })
end

local function recordAttempt(premiumId, attemptNo, result, message)
    MT.DB.insert('INSERT INTO mt_insurance_charge_attempts (premium_id, attempt_no, result, message) VALUES (?,?,?,?)',
        { premiumId, attemptNo, result, (message or ''):sub(1, 250) })
end

-- Fuehrt EINEN Abbuchungsversuch fuer einen Vertrag/Woche aus.
-- return status ('paid'|'grace'|'failed'|'skip')
function MT.InsBilling.attempt(contract, tier, premium)
    local attemptNo = (tonumber(premium.attempts) or 0) + 1
    local ok, errKey = MT.Account.charge(contract.identifier, B().account, tier.weekly_premium)

    if ok then
        MT.DB.update("UPDATE mt_insurance_premiums SET status='paid', charged_at=NOW(), attempts=?, last_error='' WHERE id=?",
            { attemptNo, premium.id })
        MT.DB.update([[UPDATE mt_insurance_contracts
            SET last_charge_at=NOW(), last_week_key=?, next_charge_at=?, failed_count=0,
                status = CASE WHEN status='grace' THEN 'active' ELSE status END, grace_until=NULL
            WHERE id=?]],
            { premium.week_key, MT.Insurance.nextChargeAt(), contract.id })
        recordAttempt(premium.id, attemptNo, 'paid', 'ok')
        notifyCfg('success', contract.identifier, MT.L('ins_charge_ok'))
        MT.Audit.log({ identifier = 'SYSTEM', name = 'System' },
            { category = 'insurance', action = 'insurance.charge.paid', target_type = 'insurance',
              target_id = contract.identifier, new = { amount = tier.weekly_premium, week = premium.week_key } })
        return 'paid'
    end

    -- Fehlgeschlagen (kein Guthaben oder Fehler)
    local reason = errKey or 'error'
    recordAttempt(premium.id, attemptNo, reason == 'ins_insufficient' and 'insufficient' or 'error', reason)

    if attemptNo >= B().maxAttempts then
        -- Endgueltig fehlgeschlagen -> onFail
        MT.DB.update("UPDATE mt_insurance_premiums SET status='failed', attempts=?, last_error=? WHERE id=?",
            { attemptNo, reason, premium.id })
        local newFailed = (tonumber(contract.failed_count) or 0) + 1
        if B().onFail == 'cancel' then
            MT.DB.update("UPDATE mt_insurance_contracts SET status='cancelled', next_charge_at=NULL, failed_count=? WHERE id=?",
                { newFailed, contract.id })
            MT.Insurance.logChange(contract.identifier, 'cancel', contract.tier_key, nil, 'SYSTEM', 'Zahlung endgueltig fehlgeschlagen')
            notifyCfg('cancelled', contract.identifier, MT.L('ins_cancelled'))
        else -- 'pause'
            MT.DB.update("UPDATE mt_insurance_contracts SET status='paused', next_charge_at=NULL, failed_count=? WHERE id=?",
                { newFailed, contract.id })
            MT.Insurance.logChange(contract.identifier, 'pause', contract.tier_key, nil, 'SYSTEM', 'Zahlung endgueltig fehlgeschlagen')
            notifyCfg('paused', contract.identifier, MT.L('ins_paused'))
        end
        MT.Audit.log({ identifier = 'SYSTEM', name = 'System' },
            { category = 'insurance', action = 'insurance.charge.failed_final', result = 'error',
              target_type = 'insurance', target_id = contract.identifier, new = { onFail = B().onFail } })
        return 'failed'
    else
        -- Kulanz + spaeterer Retry
        local graceUntil = os.date('%Y-%m-%d %H:%M:%S', os.time() + B().graceHours * 3600)
        local retryAt = os.date('%Y-%m-%d %H:%M:%S', os.time() + B().retryIntervalHours * 3600)
        MT.DB.update("UPDATE mt_insurance_premiums SET status='grace', attempts=?, last_error=? WHERE id=?",
            { attemptNo, reason, premium.id })
        MT.DB.update("UPDATE mt_insurance_contracts SET status='grace', grace_until=?, next_charge_at=?, failed_count=failed_count+1 WHERE id=?",
            { graceUntil, retryAt, contract.id })
        notifyCfg('grace', contract.identifier, MT.L('ins_charge_failed'))
        notifyCfg('failed', contract.identifier, MT.L('ins_charge_failed'))
        MT.Audit.log({ identifier = 'SYSTEM', name = 'System' },
            { category = 'insurance', action = 'insurance.charge.grace', result = 'error',
              target_type = 'insurance', target_id = contract.identifier, new = { attempt = attemptNo } })
        return 'grace'
    end
end

-- Verarbeitet einen einzelnen Vertrag (Statuswechsel + faellige Abbuchung)
function MT.InsBilling.processContract(contract)
    -- Wirksame Kuendigung
    if contract.cancel_effective_at then
        local due = MT.DB.scalar('SELECT (NOW() >= ?)', { contract.cancel_effective_at })
        if tonumber(due) == 1 then
            MT.DB.update("UPDATE mt_insurance_contracts SET status='cancelled', next_charge_at=NULL WHERE id=?", { contract.id })
            MT.Insurance.logChange(contract.identifier, 'cancel', contract.tier_key, nil, 'SYSTEM', 'Kuendigungsfrist abgelaufen')
            return
        end
    end
    -- Wartezeit vorbei -> aktivieren
    if contract.status == 'waiting' and contract.waiting_until then
        local over = MT.DB.scalar('SELECT (NOW() >= ?)', { contract.waiting_until })
        if tonumber(over) == 1 then
            MT.DB.update("UPDATE mt_insurance_contracts SET status='active', waiting_until=NULL WHERE id=?", { contract.id })
            contract.status = 'active'
        end
    end

    if contract.status == 'paused' or contract.status == 'cancelled' then return end

    local wk = MT.Util.weekKey()
    if (tonumber(contract.last_week_key) or 0) >= wk then return end -- Woche bereits bezahlt

    -- Faellig?
    if contract.next_charge_at then
        local due = MT.DB.scalar('SELECT (NOW() >= ?)', { contract.next_charge_at })
        if tonumber(due) ~= 1 then return end
    end

    local tier = MT.DB.single('SELECT * FROM mt_insurance_tiers WHERE id = ?', { contract.tier_id })
    if not tier then return end

    local premium = ensurePremium(contract, wk, tier)
    if not premium or premium.status == 'paid' then return end
    if (tonumber(premium.attempts) or 0) >= B().maxAttempts and premium.status == 'failed' then return end

    MT.InsBilling.attempt(contract, tier, premium)
end

-- Scheduler
function MT.InsBilling.runCycle()
    local contracts = MT.DB.query([[SELECT * FROM mt_insurance_contracts
        WHERE status IN ('active','grace','waiting')]]) or {}
    for _, c in ipairs(contracts) do
        local ok, err = pcall(MT.InsBilling.processContract, c)
        if not ok then MT.Util.err('InsBilling.processContract Fehler:', tostring(err)) end
    end
end

CreateThread(function()
    if not Config.Features.weeklyBilling then return end
    -- kurze Startverzoegerung, damit Seeds/DB bereit sind
    Wait(15000)
    while true do
        local ok, err = pcall(MT.InsBilling.runCycle)
        if not ok then MT.Util.err('InsBilling.runCycle Fehler:', tostring(err)) end
        Wait(math.max(1, B().checkIntervalMinutes) * 60000)
    end
end)

-----------------------------------------------------------------------------
-- Verwaltung: fehlgeschlagene Beitraege ansehen / manuell erneut abbuchen
-----------------------------------------------------------------------------
MT.register('insurance.failedList', { perm = 'insurance.failed.view', feature = 'insurance' }, function(ctx, data)
    local page = MT.Util.clampInt(data.page or 1, 1)
    local pageSize = MT.Util.clampInt(data.pageSize or 20, 1, 50)
    local offset = (page - 1) * pageSize
    local total = MT.DB.scalar("SELECT COUNT(*) FROM mt_insurance_premiums WHERE status IN ('failed','grace')") or 0
    local rows = MT.DB.query([[SELECT id, identifier, tier_key, amount, week_key, status, attempts, last_error, scheduled_at
        FROM mt_insurance_premiums WHERE status IN ('failed','grace')
        ORDER BY scheduled_at DESC LIMIT ]] .. pageSize .. ' OFFSET ' .. offset) or {}
    return { rows = rows, total = total, page = page, pageSize = pageSize }
end)

MT.register('insurance.retry', { perm = 'insurance.retry', feature = 'insurance' }, function(ctx, data)
    local premium = MT.DB.single('SELECT * FROM mt_insurance_premiums WHERE id = ?', { tonumber(data.premium_id) })
    if not premium then return MT.fail('invalid_input') end
    if premium.status == 'paid' then return { ok = true, status = 'paid' } end
    local contract = MT.Insurance.getContract(premium.identifier)
    if not contract then return MT.fail('ins_none') end
    local tier = MT.DB.single('SELECT * FROM mt_insurance_tiers WHERE id = ?', { contract.tier_id })
    if not tier then return MT.fail('invalid_input') end

    local status = MT.InsBilling.attempt(contract, tier, premium)
    MT.Audit.log(ctx, { category = 'insurance', action = 'insurance.charge.manual_retry',
        target_type = 'insurance', target_id = premium.identifier, new = { result = status } })
    return { ok = true, status = status }
end)
