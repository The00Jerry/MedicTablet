--[[
    Client-Kern: MDT oeffnen/schliessen mit sauberem NUI-Focus.
    Nach dem Schliessen werden Maus/Tastatur/Spielfigur vollstaendig freigegeben.
]]

PD = PD or {}
PD.isOpen = false

CreateThread(function()
    while GetResourceState(Config.ESXResource) ~= 'started' do Wait(200) end
    PD.ESX = exports[Config.ESXResource]:getSharedObject()
end)

function PD.openTablet()
    if PD.isOpen then return end
    if not Config.Features.tabletEnabled then return end
    PD.request('tablet.bootstrap', {}, function(ok, payload)
        if not ok then
            if PD.ESX and PD.ESX.ShowNotification then PD.ESX.ShowNotification((payload and payload.error) or 'Kein Zugriff auf das MDT.') end
            return
        end
        PD.isOpen = true
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false)
        SendNUIMessage({ type = 'open', payload = payload })
    end)
end

function PD.closeTablet()
    if not PD.isOpen then return end
    PD.isOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ type = 'close' })
end

CreateThread(function()
    while true do
        if PD.isOpen then
            if IsControlJustReleased(0, 322) then PD.closeTablet() end -- ESC
            Wait(0)
        else
            Wait(300)
        end
    end
end)

-- Oeffnungsmoeglichkeiten
if Config.Open.command.enabled then
    RegisterCommand(Config.Open.command.name, function() PD.openTablet() end, false)
end
if Config.Open.key.enabled then
    RegisterCommand(Config.Open.key.mapCommand, function() PD.openTablet() end, false)
    RegisterKeyMapping(Config.Open.key.mapCommand, 'LSPD MDT oeffnen', 'keyboard', Config.Open.key.default)
end
RegisterNetEvent('lspd:cl:open', function() PD.openTablet() end)

CreateThread(function()
    if not Config.Open.target.enabled then return end
    if GetResourceState('ox_target') ~= 'started' then return end
    for i, z in ipairs(Config.Open.target.zones) do
        exports.ox_target:addSphereZone({
            coords = z.coords, radius = z.radius or 1.5, debug = Config.Debug,
            options = { { name = 'lspd_mdt_open_' .. i, icon = 'fa-solid fa-tablet-screen-button', label = z.label or 'MDT oeffnen', onSelect = function() PD.openTablet() end } },
        })
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and PD.isOpen then SetNuiFocus(false, false) end
end)
