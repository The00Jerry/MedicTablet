--[[
    Versicherungs-NPC via ox_target.
    Frei konfigurierbar: Koordinaten (vector4), Ped, Szenario/Animation, Blip.
    NPC ist unverwundbar & unbeweglich. Interaktion oeffnet die Versicherungs-UI.
]]

local spawnedPed = nil

local function loadModel(model)
    local hash = type(model) == 'string' and joaat(model) or model
    RequestModel(hash)
    local tries = 0
    while not HasModelLoaded(hash) and tries < 100 do Wait(20); tries = tries + 1 end
    return hash
end

CreateThread(function()
    local cfg = Config.Insurance.NPC
    if not cfg.enabled or not Config.Features.insuranceNPC then return end
    while GetResourceState('ox_target') ~= 'started' do Wait(250) end

    local hash = loadModel(cfg.ped)
    local c = cfg.coords
    spawnedPed = CreatePed(4, hash, c.x, c.y, c.z - 1.0, c.w, false, true)
    SetModelAsNoLongerNeeded(hash)

    if cfg.invincible then SetEntityInvincible(spawnedPed, true) end
    if cfg.freeze then FreezeEntityPosition(spawnedPed, true) end
    SetBlockingOfNonTemporaryEvents(spawnedPed, true)
    SetPedDiesWhenInjured(spawnedPed, false)
    SetPedCanRagdoll(spawnedPed, false)

    if cfg.scenario then
        TaskStartScenarioInPlace(spawnedPed, cfg.scenario, 0, true)
    elseif cfg.anim and cfg.anim.dict then
        RequestAnimDict(cfg.anim.dict)
        local t = 0
        while not HasAnimDictLoaded(cfg.anim.dict) and t < 100 do Wait(20); t = t + 1 end
        TaskPlayAnim(spawnedPed, cfg.anim.dict, cfg.anim.name, 8.0, -8.0, -1, 1, 0, false, false, false)
    end

    -- Blip
    if cfg.blip and cfg.blip.enabled then
        local blip = AddBlipForCoord(c.x, c.y, c.z)
        SetBlipSprite(blip, cfg.blip.sprite)
        SetBlipColour(blip, cfg.blip.color)
        SetBlipScale(blip, cfg.blip.scale)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(cfg.blip.label)
        EndTextCommandSetBlipName(blip)
    end

    -- ox_target
    exports.ox_target:addLocalEntity(spawnedPed, {
        {
            name = 'medictablet_insurance',
            icon = cfg.target.icon,
            label = cfg.target.label,
            distance = cfg.target.distance,
            onSelect = function()
                MT.openInsurance()
            end,
        },
    })
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and spawnedPed and DoesEntityExist(spawnedPed) then
        DeleteEntity(spawnedPed)
    end
end)
