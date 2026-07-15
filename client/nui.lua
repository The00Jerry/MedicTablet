--[[
    NUI <-> Server Bruecke.
    Ein einziger, generischer Kanal: die NUI ruft 'request' mit { action, data }.
    Der Client leitet an den serverseitigen Dispatcher weiter (der ALLE Rechte
    prueft) und gibt die Antwort per requestId zurueck. Keine Logik/Secrets im NUI.
]]

MT = MT or {}
MT.Bridge = {}

local pending = {}
local seq = 0

local function nextId()
    seq = seq + 1
    return ('%d-%d'):format(GetGameTimer(), seq)
end

-- action, data, cb(ok, payload)
function MT.request(action, data, cb)
    local reqId = nextId()
    pending[reqId] = cb
    TriggerServerEvent('medictablet:sv:request', reqId, action, data or {})
    SetTimeout(15000, function()
        local c = pending[reqId]
        if c then
            pending[reqId] = nil
            c(false, { error = 'Zeitueberschreitung. Bitte erneut versuchen.' })
        end
    end)
end

RegisterNetEvent('medictablet:cl:response', function(reqId, ok, payload)
    local cb = pending[reqId]
    if cb then
        pending[reqId] = nil
        cb(ok, payload)
    end
end)

-- Generischer NUI-Callback
RegisterNUICallback('request', function(body, cb)
    if type(body) ~= 'table' or type(body.action) ~= 'string' then
        return cb({ ok = false, data = { error = 'invalid_input' } })
    end
    MT.request(body.action, body.data, function(ok, payload)
        cb({ ok = ok, data = payload })
    end)
end)

RegisterNUICallback('close', function(_, cb)
    MT.closeTablet()
    cb({ ok = true })
end)

-- Server-Benachrichtigungen (z.B. Versicherungsabbuchung)
RegisterNetEvent('medictablet:cl:notify', function(ntype, message)
    if MT.isOpen then
        SendNUIMessage({ type = 'notify', level = ntype, message = message })
    end
    -- zusaetzlich ESX-Notify falls verfuegbar
    if MT.ESX and MT.ESX.ShowNotification then
        MT.ESX.ShowNotification(message)
    end
end)
