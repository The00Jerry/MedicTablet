--[[ Gemeinsame Hilfsfunktionen (Client + Server). ]]

PD = PD or {}
PD.Util = {}

function PD.Util.dbg(...) if Config and Config.Debug then print('^5[lspdtablet]^7', ...) end end
function PD.Util.log(...)  print('^2[lspdtablet]^7', ...) end
function PD.Util.warn(...) print('^3[lspdtablet]^7', ...) end
function PD.Util.err(...)  print('^1[lspdtablet]^7', ...) end

function PD.Util.trim(s)
    if type(s) ~= 'string' then return s end
    return (s:gsub('^%s*(.-)%s*$', '%1'))
end

function PD.Util.clampInt(v, minv, maxv)
    v = math.floor(tonumber(v) or 0)
    if minv and v < minv then v = minv end
    if maxv and v > maxv then v = maxv end
    return v
end

function PD.Util.genId(prefix)
    return string.format('%s%d%04d', prefix or '', os.time() % 100000000, math.random(0, 9999))
end

-- Stabiler Fingerabdruck-Code aus dem Identifier (deterministisch, kurz)
function PD.Util.fingerprint(identifier)
    local h = 2166136261
    for i = 1, #identifier do
        h = (h ~ identifier:byte(i)) & 0xFFFFFFFF
        h = (h * 16777619) & 0xFFFFFFFF
    end
    local prefix = (Config and Config.Fingerprint and Config.Fingerprint.codePrefix) or 'FP'
    return string.format('%s-%08X', prefix, h)
end

function PD.Util.money(v)
    v = math.floor(tonumber(v) or 0)
    local s = tostring(math.abs(v))
    local out = s:reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', '')
    if v < 0 then out = '-' .. out end
    return '$' .. out
end

PD.Util.WantedLevels = { low = true, medium = true, high = true }
PD.Util.ReportTypes  = { incident = true, arrest = true, traffic = true, investigation = true }
PD.Util.InvolvedRoles = { suspect = true, victim = true, witness = true }

return PD.Util
