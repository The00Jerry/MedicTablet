--[[
    Fingerabdruck-Scan (Client-Teil).
    Findet die naechstgelegene Person, spielt eine kurze Scan-Animation und ruft
    danach serverseitig 'fingerprint.scan' (mit erneuter Distanzpruefung) auf.
    Ausgeloest aus der NUI (Button) oder per Command /fingerprint.
]]

PD = PD or {}

local function nearestPlayerServerId()
    local me = PlayerPedId()
    local myc = GetEntityCoords(me)
    local best, bestDist = nil, (Config.Fingerprint.maxDistance + 0.1)
    for _, p in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(p)
        if ped ~= me and DoesEntityExist(ped) then
            local d = #(myc - GetEntityCoords(ped))
            if d < bestDist then bestDist = d; best = p end
        end
    end
    if best then return GetPlayerServerId(best) end
    return nil
end

local function playScanAnim()
    local ped = PlayerPedId()
    local dict = 'anim@gangops@facility@servers@bodysearch@'
    RequestAnimDict(dict)
    local t = 0
    while not HasAnimDictLoaded(dict) and t < 50 do Wait(10); t = t + 1 end
    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(ped, dict, 'player_search', 3.0, -3.0, -1, 49, 0, false, false, false)
    end
end
local function stopScanAnim() ClearPedTasks(PlayerPedId()) end

-- Fuehrt einen Scan aus und ruft cb(ok, payload)
function PD.doFingerprintScan(cb)
    local sid = nearestPlayerServerId()
    if not sid then return cb(false, { error = PD.L and PD.L('fp_no_target') or 'Keine Person in Reichweite.' }) end
    playScanAnim()
    SetTimeout(Config.Fingerprint.scanDurationMs, function()
        stopScanAnim()
        -- Person koennte weggelaufen sein -> Server prueft Distanz erneut
        PD.request('fingerprint.scan', { targetServerId = sid }, function(ok, payload) cb(ok, payload) end)
    end)
end

-- NUI-Button
RegisterNUICallback('fingerprintScan', function(_, cb)
    PD.doFingerprintScan(function(ok, payload) cb({ ok = ok, data = payload }) end)
end)

-- Optionaler Command (auch ohne offenes Tablet nutzbar)
RegisterCommand('fingerprint', function()
    PD.doFingerprintScan(function(ok, payload)
        if ok and PD.isOpen then
            SendNUIMessage({ type = 'fingerprintResult', payload = payload })
        elseif PD.ESX and PD.ESX.ShowNotification then
            PD.ESX.ShowNotification(ok and ('Identifiziert: ' .. (payload.scan and payload.scan.record and (payload.scan.record.firstname .. ' ' .. payload.scan.record.lastname) or '')) or (payload.error or 'Scan fehlgeschlagen.'))
        end
    end)
end, false)
