--[[ NUI <-> Server Bruecke. ]]
WL = WL or {}
local pending = {}
local seq = 0
local function nextId() seq = seq + 1; return ('%d-%d'):format(GetGameTimer(), seq) end

function WL.request(action, data, cb)
    local reqId = nextId()
    pending[reqId] = cb
    TriggerServerEvent('lswallet:sv:request', reqId, action, data or {})
    SetTimeout(15000, function() local c = pending[reqId]; if c then pending[reqId] = nil; c(false, { error = 'Zeitueberschreitung.' }) end end)
end

RegisterNetEvent('lswallet:cl:response', function(reqId, ok, payload)
    local cb = pending[reqId]; if cb then pending[reqId] = nil; cb(ok, payload) end
end)

RegisterNUICallback('request', function(body, cb)
    if type(body) ~= 'table' or type(body.action) ~= 'string' then return cb({ ok = false, data = { error = 'invalid_input' } }) end
    WL.request(body.action, body.data, function(ok, payload) cb({ ok = ok, data = payload }) end)
end)

RegisterNUICallback('close', function(_, cb) WL.closeWallet(); cb({ ok = true }) end)

RegisterNetEvent('lswallet:cl:notify', function(ntype, message)
    if WL.isOpen then SendNUIMessage({ type = 'notify', level = ntype, message = message }) end
    if WL.ESX and WL.ESX.ShowNotification then WL.ESX.ShowNotification(message) end
end)
