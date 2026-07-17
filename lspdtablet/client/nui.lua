--[[ NUI <-> Server Bruecke (generischer 'request'-Kanal). ]]

PD = PD or {}
local pending = {}
local seq = 0
local function nextId() seq = seq + 1; return ('%d-%d'):format(GetGameTimer(), seq) end

function PD.request(action, data, cb)
    local reqId = nextId()
    pending[reqId] = cb
    TriggerServerEvent('lspd:sv:request', reqId, action, data or {})
    SetTimeout(15000, function()
        local c = pending[reqId]
        if c then pending[reqId] = nil; c(false, { error = 'Zeitueberschreitung. Bitte erneut versuchen.' }) end
    end)
end

RegisterNetEvent('lspd:cl:response', function(reqId, ok, payload)
    local cb = pending[reqId]
    if cb then pending[reqId] = nil; cb(ok, payload) end
end)

RegisterNUICallback('request', function(body, cb)
    if type(body) ~= 'table' or type(body.action) ~= 'string' then return cb({ ok = false, data = { error = 'invalid_input' } }) end
    PD.request(body.action, body.data, function(ok, payload) cb({ ok = ok, data = payload }) end)
end)

RegisterNUICallback('close', function(_, cb) PD.closeTablet(); cb({ ok = true }) end)

RegisterNetEvent('lspd:cl:notify', function(ntype, message)
    if PD.isOpen then SendNUIMessage({ type = 'notify', level = ntype, message = message }) end
    if PD.ESX and PD.ESX.ShowNotification then PD.ESX.ShowNotification(message) end
end)
