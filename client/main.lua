--[[
    Client-Kern: Tablet oeffnen/schliessen mit sauberem NUI-Focus-Management.
    Nach dem Schliessen werden Maus, Tastatur und Spielfigur vollstaendig
    freigegeben – das Tablet blockiert keine Steuerung.
]]

MT = MT or {}
MT.isOpen = false

CreateThread(function()
    while GetResourceState(Config.ESXResource) ~= 'started' do Wait(200) end
    MT.ESX = exports[Config.ESXResource]:getSharedObject()
end)

-- Oeffnen
function MT.openTablet(mode)
    if MT.isOpen then return end
    if not Config.Features.tabletEnabled then return end

    MT.request('tablet.bootstrap', {}, function(ok, payload)
        if not ok then
            if MT.ESX and MT.ESX.ShowNotification then
                MT.ESX.ShowNotification((payload and payload.error) or 'Kein Zugriff auf das Tablet.')
            end
            return
        end
        MT.isOpen = true
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false)
        SendNUIMessage({
            type = 'open',
            mode = mode or 'tablet', -- 'tablet' | 'insurance'
            payload = payload,
        })
    end)
end

-- Insurance-NPC-Oberflaeche (schlanker Modus, gleiche NUI)
function MT.openInsurance()
    if MT.isOpen then return end
    MT.request('insurance.npc.get', {}, function(ok, payload)
        if not ok then
            if MT.ESX and MT.ESX.ShowNotification then
                MT.ESX.ShowNotification((payload and payload.error) or 'Versicherung nicht verfuegbar.')
            end
            return
        end
        MT.isOpen = true
        SetNuiFocus(true, true)
        SendNUIMessage({ type = 'open', mode = 'insurance', payload = { insurance = payload } })
    end)
end

-- Schliessen: ALLES freigeben
function MT.closeTablet()
    if not MT.isOpen then return end
    MT.isOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ type = 'close' })
    -- Sicherheitshalber Steuerung nicht blockieren (kein disableControl-Loop aktiv)
end

-- ESC schliesst (falls NUI-Callback mal nicht greift)
CreateThread(function()
    while true do
        if MT.isOpen then
            if IsControlJustReleased(0, 322) then -- ESC
                MT.closeTablet()
            end
            Wait(0)
        else
            Wait(300)
        end
    end
end)

-----------------------------------------------------------------------------
-- Oeffnungsmoeglichkeiten
-----------------------------------------------------------------------------
-- Command
if Config.Open.command.enabled then
    RegisterCommand(Config.Open.command.name, function()
        MT.openTablet('tablet')
    end, false)
end

-- Taste
if Config.Open.key.enabled then
    RegisterCommand(Config.Open.key.mapCommand, function()
        MT.openTablet('tablet')
    end, false)
    RegisterKeyMapping(Config.Open.key.mapCommand, 'Medic-Tablet oeffnen', 'keyboard', Config.Open.key.default)
end

-- Item (vom Server getriggert)
RegisterNetEvent('medictablet:cl:open', function()
    MT.openTablet('tablet')
end)

-- ox_target Zonen
CreateThread(function()
    if not Config.Open.target.enabled then return end
    if GetResourceState('ox_target') ~= 'started' then return end
    for i, z in ipairs(Config.Open.target.zones) do
        exports.ox_target:addSphereZone({
            coords = z.coords,
            radius = z.radius or 1.5,
            debug = Config.Debug,
            options = {
                {
                    name = 'medictablet_open_' .. i,
                    icon = 'fa-solid fa-tablet-screen-button',
                    label = z.label or 'Medic-Tablet oeffnen',
                    onSelect = function() MT.openTablet('tablet') end,
                    groups = nil, -- Job-Pruefung erfolgt serverseitig beim bootstrap
                },
            },
        })
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and MT.isOpen then
        SetNuiFocus(false, false)
    end
end)
