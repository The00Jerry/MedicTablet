--[[ Gemeinsame Hilfsfunktionen (Client + Server). ]]

MT = MT or {}
MT.Util = {}

-- Debug-Print (nur bei Config.Debug)
function MT.Util.dbg(...)
    if Config and Config.Debug then
        print('^5[medictablet]^7', ...)
    end
end

function MT.Util.log(...)
    print('^2[medictablet]^7', ...)
end

function MT.Util.warn(...)
    print('^3[medictablet]^7', ...)
end

function MT.Util.err(...)
    print('^1[medictablet]^7', ...)
end

-- String trim
function MT.Util.trim(s)
    if type(s) ~= 'string' then return s end
    return (s:gsub('^%s*(.-)%s*$', '%1'))
end

-- Auf Ganzzahl >= 0 begrenzen
function MT.Util.clampInt(v, minv, maxv)
    v = tonumber(v) or 0
    v = math.floor(v)
    if minv and v < minv then v = minv end
    if maxv and v > maxv then v = maxv end
    return v
end

-- Sichere Kopie einer Tabelle (flach)
function MT.Util.shallow(t)
    local r = {}
    if type(t) == 'table' then for k, v in pairs(t) do r[k] = v end end
    return r
end

-- ISO-Wochen-Schluessel: year*100 + isoweek (fuer Idempotenz der Beitraege)
-- os.date('%G') = ISO-Jahr, '%V' = ISO-Woche
function MT.Util.weekKey(ts)
    ts = ts or os.time()
    local y = tonumber(os.date('%G', ts))
    local w = tonumber(os.date('%V', ts))
    return y * 100 + w
end

-- Simple deterministische ID (Prefix + Zeit + Zufall)
function MT.Util.genId(prefix)
    return string.format('%s%d%04d', prefix or '', os.time() % 100000000, math.random(0, 9999))
end

-- Waehrungsformat (Anzeige)
function MT.Util.money(v)
    v = math.floor(tonumber(v) or 0)
    local s = tostring(math.abs(v))
    local out = s:reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', '')
    if v < 0 then out = '-' .. out end
    return '$' .. out
end

-- Whitelist-Pruefung fuer Behandlungsstatus
MT.Util.TreatmentStatuses = {
    draft = true, ongoing = true, completed = true, cancelled = true, archived = true,
}

return MT.Util
