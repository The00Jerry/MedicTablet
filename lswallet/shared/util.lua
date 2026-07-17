--[[ Gemeinsame Hilfsfunktionen (Client + Server). ]]

WL = WL or {}
WL.Util = {}

function WL.Util.dbg(...) if Config and Config.Debug then print('^5[lswallet]^7', ...) end end
function WL.Util.log(...)  print('^2[lswallet]^7', ...) end
function WL.Util.warn(...) print('^3[lswallet]^7', ...) end
function WL.Util.err(...)  print('^1[lswallet]^7', ...) end

function WL.Util.trim(s) if type(s) ~= 'string' then return s end return (s:gsub('^%s*(.-)%s*$', '%1')) end
function WL.Util.clampInt(v, minv, maxv)
    v = math.floor(tonumber(v) or 0)
    if minv and v < minv then v = minv end
    if maxv and v > maxv then v = maxv end
    return v
end
function WL.Util.genId(prefix) return string.format('%s%d%04d', prefix or '', os.time() % 100000000, math.random(0, 9999)) end
function WL.Util.serial(prefix)
    return string.format('%s%d%03d', prefix or 'LS', os.time() % 10000000, math.random(0, 999))
end
function WL.Util.money(v)
    v = math.floor(tonumber(v) or 0)
    local s = tostring(math.abs(v))
    local out = s:reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', '')
    return '$' .. (v < 0 and '-' or '') .. out
end

WL.Util.CardTypes = { national_id = true, driver_license = true, license = true, business_card = true, job_wallet = true, ticket = true, coupon = true }

return WL.Util
