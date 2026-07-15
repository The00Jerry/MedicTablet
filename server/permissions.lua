--[[
    Serverseitige Berechtigungspruefung.

    Reihenfolge / Quellen:
      1. Basis: Job + Grade (kumulativ). Bevorzugt aus DB-Tabelle mt_permissions
         (per Panel/Tablet pflegbar). Ist dort nichts hinterlegt -> Config-Fallback.
      2. Einzel-Overrides je Charakter (mt_permission_overrides): allow=1 gewaehrt,
         allow=0 entzieht – hat Vorrang vor der Basis.
      3. admin.full impliziert ALLE Rechte.
      4. Sperre (mt_user_locks) blockiert jeglichen Zugriff.

    JEDE sensible Server-Aktion ruft MT.Perms.require(...) auf – Client-Checks
    sind nur UX, niemals Sicherheit.
]]

MT = MT or {}
MT.Perms = {}

local cache = {}          -- [identifier] = { perms = {set}, ts = timer }
local CACHE_TTL = 30000    -- 30s

function MT.Perms.invalidate(identifier)
    if identifier then cache[identifier] = nil else cache = {} end
end

local function jobAllowed(job)
    for _, j in ipairs(Config.Perms.AllowedJobs) do
        if j == job then return true end
    end
    return false
end

-- Kumulative Basis-Rechte aus Config
local function configPerms(job, grade)
    local set = {}
    local grades = Config.Perms.Grades[job]
    if not grades then return set end
    for g, list in pairs(grades) do
        if g <= grade then
            for _, p in ipairs(list) do set[p] = true end
        end
    end
    return set
end

-- Kumulative Basis-Rechte aus DB (falls vorhanden)
local function dbPerms(job, grade)
    local rows = MT.DB.query(
        'SELECT perm FROM mt_permissions WHERE job = ? AND grade <= ?',
        { job, grade }
    )
    if not rows or #rows == 0 then return nil end
    local set = {}
    for _, r in ipairs(rows) do set[r.perm] = true end
    return set
end

function MT.Perms.isLocked(identifier)
    local locked = MT.DB.scalar('SELECT locked FROM mt_user_locks WHERE identifier = ?', { identifier })
    return tonumber(locked) == 1
end

-- Liefert das effektive Rechte-Set (map perm->true)
function MT.Perms.effective(identifier, job, grade)
    local c = cache[identifier]
    if c and (GetGameTimer() - c.ts) < CACHE_TTL then
        return c.perms
    end

    local set = {}
    if jobAllowed(job) then
        set = dbPerms(job, grade) or configPerms(job, grade)
    end

    -- Overrides
    local ov = MT.DB.query('SELECT perm, allow FROM mt_permission_overrides WHERE identifier = ?', { identifier })
    if ov then
        for _, r in ipairs(ov) do
            if tonumber(r.allow) == 1 then set[r.perm] = true else set[r.perm] = nil end
        end
    end

    cache[identifier] = { perms = set, ts = GetGameTimer() }
    return set
end

-- Prueft ein einzelnes Recht (admin.full impliziert alles)
function MT.Perms.has(permsSet, perm)
    if not perm or perm == '' then return true end
    if permsSet['admin.full'] then return true end
    return permsSet[perm] == true
end

-- Baut die fuer den Client sichtbare Rechte-Liste (nur UX-Steuerung)
function MT.Perms.list(permsSet)
    local out = {}
    if permsSet['admin.full'] then
        for _, p in ipairs(Config.Perms.All) do out[p] = true end
        return out
    end
    for p, v in pairs(permsSet) do if v then out[p] = true end end
    return out
end
