--[[
    Fingerabdruck-Scanner.
    Der Beamte scannt eine Person in seiner Naehe zur zweifelsfreien Identifikation.
    Die Distanz wird SERVERSEITIG geprueft (kein Client-Spoofing der Zielperson).
]]

PD = PD or {}

-- Scan der nahegelegenen Zielperson (targetServerId vom Client).
PD.register('fingerprint.scan', { perm = 'fingerprint.scan', feature = 'fingerprint' }, function(ctx, data)
    local targetId = tonumber(data.targetServerId)
    if not targetId then return PD.fail('fp_no_target') end

    local officerPed = GetPlayerPed(ctx.src)
    local targetPed  = GetPlayerPed(targetId)
    if not targetPed or targetPed == 0 or GetPlayerName(targetId) == nil then return PD.fail('fp_no_target') end

    -- Serverseitige Distanzpruefung
    local oc = GetEntityCoords(officerPed)
    local tc = GetEntityCoords(targetPed)
    local dist = #(oc - tc)
    if dist > (Config.Fingerprint.maxDistance + 0.75) then -- kleine Toleranz
        return PD.fail('fp_too_far')
    end

    local ESX = PD.getESX()
    local xt = ESX and ESX.GetPlayerFromId(targetId)
    if not xt then return PD.fail('player_not_found') end

    local full = PD.Citizens.fullRecord(ctx, xt.identifier)
    if not full then return PD.fail('player_not_found') end

    PD.Audit.log(ctx, { category = 'default', action = 'fingerprint.scan', target_type = 'citizen',
        target_id = full.record.id, new = { fp = full.record.fingerprint, dist = math.floor(dist * 10) / 10 } })

    return { ok = true, message = PD.L('fp_ok'), scan = full }
end)

-- Nachschlagen eines (z.B. am Tatort gesicherten) Fingerabdruck-Codes.
PD.register('fingerprint.lookup', { perm = 'citizen.search', feature = 'fingerprint' }, function(ctx, data)
    local code = PD.Util.trim(tostring(data.code or '')):upper()
    if #code < 4 then return PD.fail('invalid_input') end
    local rec = PD.DB.single('SELECT identifier, firstname, lastname, fingerprint, is_wanted FROM pd_citizens WHERE fingerprint = ?', { code })
    if not rec then return { found = false } end
    PD.Audit.log(ctx, { action = 'fingerprint.lookup', target_type = 'citizen', target_id = rec.identifier, reason = code })
    return { found = true, match = rec }
end)
