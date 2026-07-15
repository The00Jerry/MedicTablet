--[[
    Web-App Rechnungs-Bruecke (Poller).

    Die externe Web-App kann selbst KEINE CodeM-Rechnung erstellen (das kann nur der
    laufende FiveM-Server). Sie legt daher Rechnungswuensche in mt_invoice_queue ab.
    Dieser Poller:
      1. beansprucht offene Eintraege atomar (status pending -> processing),
      2. baut aus den serverseitig gespeicherten actor_perms einen can()-Kontext,
      3. ruft den gemeinsamen Kern MT.BillingSvc.create (idempotent, CodeM-Adapter),
      4. schreibt das Ergebnis zurueck (done/failed + result_invoice_id/error).

    Sicherheit: Rechte wurden bereits im Web-Backend geprueft UND werden hier erneut
    aus actor_perms angewandt (item.required_perm, discount.grant). Idempotenz ueber
    idempotency_key (Queue UNIQUE + mt_invoice_refs UNIQUE).
]]

MT = MT or {}
MT.WebBridge = {}

local function permsFromJson(raw)
    local set = {}
    if raw and raw ~= '' then
        local ok, t = pcall(function() return json.decode(raw) end)
        if ok and type(t) == 'table' then set = t end
    end
    return set
end

local function makeActor(row)
    local set = permsFromJson(row.actor_perms)
    return {
        identifier = row.actor_identifier ~= '' and row.actor_identifier or 'WEB',
        name       = row.actor_name ~= '' and row.actor_name or 'Web-App',
        discord    = row.actor_discord or '',
        can = function(perm)
            if not perm or perm == '' then return true end
            if set['admin.full'] then return true end
            return set[perm] == true
        end,
    }
end

function MT.WebBridge.processRow(row)
    -- atomar beanspruchen
    local claimed = MT.DB.update(
        "UPDATE mt_invoice_queue SET status='processing', attempts=attempts+1 WHERE id=? AND status='pending'",
        { row.id })
    if not claimed or claimed < 1 then return end -- schon von jemand anderem beansprucht

    local items = nil
    if row.items_json and row.items_json ~= '' then
        local ok, t = pcall(function() return json.decode(row.items_json) end)
        if ok then items = t end
    end

    local ok, res = MT.BillingSvc.create({
        identifier      = row.identifier,
        items           = items,
        treatment_id    = row.treatment_id,
        discount        = row.discount,
        reason          = row.reason,
        idempotency_key = row.idempotency_key,
        actor           = makeActor(row),
        source          = 'web',
    })

    if ok then
        MT.DB.update("UPDATE mt_invoice_queue SET status='done', result_invoice_id=?, error='', processed_at=NOW() WHERE id=?",
            { res.invoice_id, row.id })
    else
        local errKey = tostring(res)
        -- transiente Fehler ggf. erneut versuchen, sonst endgueltig fehlschlagen
        local transient = (errKey == 'db_error' or errKey == 'billing_down' or errKey == 'patient_offline')
        if transient and (tonumber(row.attempts) or 0) + 1 < Config.WebBridge.maxAttempts then
            MT.DB.update("UPDATE mt_invoice_queue SET status='pending', error=? WHERE id=?", { errKey, row.id })
        else
            MT.DB.update("UPDATE mt_invoice_queue SET status='failed', error=?, processed_at=NOW() WHERE id=?", { errKey, row.id })
        end
    end
end

function MT.WebBridge.runCycle()
    local rows = MT.DB.query(
        "SELECT * FROM mt_invoice_queue WHERE status='pending' ORDER BY id ASC LIMIT " .. tonumber(Config.WebBridge.batch or 10))
    if not rows then return end
    for _, row in ipairs(rows) do
        local ok, err = pcall(MT.WebBridge.processRow, row)
        if not ok then MT.Util.err('WebBridge.processRow Fehler:', tostring(err)) end
    end
end

CreateThread(function()
    if not Config.WebBridge.enabled then
        MT.Util.dbg('Web-Bridge deaktiviert.')
        return
    end
    -- Existiert die Queue-Tabelle? (sql/webapp.sql eingespielt?)
    Wait(16000)
    local exists = MT.DB.scalar("SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'mt_invoice_queue'")
    if not exists then
        MT.Util.warn('Web-Bridge aktiviert, aber Tabelle mt_invoice_queue fehlt. Bitte sql/webapp.sql einspielen.')
        return
    end
    MT.Util.log('Web-Bridge aktiv (Rechnungs-Warteschlange).')
    while true do
        local ok, err = pcall(MT.WebBridge.runCycle)
        if not ok then MT.Util.err('WebBridge.runCycle Fehler:', tostring(err)) end
        Wait(math.max(1, Config.WebBridge.pollIntervalSeconds) * 1000)
    end
end)
