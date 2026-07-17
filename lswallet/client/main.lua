--[[ Client-Kern: Wallet oeffnen/schliessen mit sauberem NUI-Focus. ]]

WL = WL or {}
WL.isOpen = false

CreateThread(function()
    while GetResourceState(Config.ESXResource) ~= 'started' do Wait(200) end
    WL.ESX = exports[Config.ESXResource]:getSharedObject()
end)

function WL.openWallet(mode)
    if WL.isOpen then return end
    WL.request('wallet.get', {}, function(ok, payload)
        if not ok then if WL.ESX and WL.ESX.ShowNotification then WL.ESX.ShowNotification((payload and payload.error) or 'Wallet nicht verfuegbar.') end return end
        WL.isOpen = true
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false)
        SendNUIMessage({ type = 'open', mode = mode or 'wallet', payload = payload })
    end)
end

function WL.closeWallet()
    if not WL.isOpen then return end
    WL.isOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ type = 'close' })
end

CreateThread(function()
    while true do
        if WL.isOpen then
            if IsControlJustReleased(0, 322) then WL.closeWallet() end -- ESC
            Wait(0)
        else Wait(300) end
    end
end)

if Config.Open.command.enabled then RegisterCommand(Config.Open.command.name, function() WL.openWallet('wallet') end, false) end
if Config.Open.key.enabled then
    RegisterCommand(Config.Open.key.mapCommand, function() WL.openWallet('wallet') end, false)
    RegisterKeyMapping(Config.Open.key.mapCommand, 'Wallet oeffnen', 'keyboard', Config.Open.key.default)
end
RegisterNetEvent('lswallet:cl:open', function() WL.openWallet('wallet') end)

AddEventHandler('onResourceStop', function(res) if res == GetCurrentResourceName() and WL.isOpen then SetNuiFocus(false, false) end end)
