--[[ DMV-NPC (Department of Licensing & Identification) via ox_target. ]]

local ped = nil

local function loadModel(model)
    local hash = type(model) == 'string' and joaat(model) or model
    RequestModel(hash)
    local t = 0
    while not HasModelLoaded(hash) and t < 100 do Wait(20); t = t + 1 end
    return hash
end

CreateThread(function()
    local cfg = Config.NPC
    if not cfg.enabled then return end
    while GetResourceState('ox_target') ~= 'started' do Wait(250) end
    local hash = loadModel(cfg.ped)
    local c = cfg.coords
    ped = CreatePed(4, hash, c.x, c.y, c.z - 1.0, c.w, false, true)
    SetModelAsNoLongerNeeded(hash)
    if cfg.invincible then SetEntityInvincible(ped, true) end
    if cfg.freeze then FreezeEntityPosition(ped, true) end
    SetBlockingOfNonTemporaryEvents(ped, true)
    if cfg.scenario then TaskStartScenarioInPlace(ped, cfg.scenario, 0, true) end

    if cfg.blip and cfg.blip.enabled then
        local blip = AddBlipForCoord(c.x, c.y, c.z)
        SetBlipSprite(blip, cfg.blip.sprite); SetBlipColour(blip, cfg.blip.color); SetBlipScale(blip, cfg.blip.scale)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(cfg.blip.label); EndTextCommandSetBlipName(blip)
    end

    exports.ox_target:addLocalEntity(ped, {
        { name = 'lswallet_dmv', icon = cfg.target.icon, label = cfg.target.label, distance = cfg.target.distance,
          onSelect = function() WL.openWallet('dmv') end },
    })
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and ped and DoesEntityExist(ped) then DeleteEntity(ped) end
end)
