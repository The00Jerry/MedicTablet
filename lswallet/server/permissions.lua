--[[ Serverseitige Berechtigungspruefung fuer Verwaltungsaktionen. ]]
WL = WL or {}
WL.Perms = {}

local cache = {}
local TTL = 30000

function WL.Perms.invalidate(id) if id then cache[id] = nil else cache = {} end end

local function configPerms(job, grade)
    local set = {}
    local grades = Config.Perms.Grades[job]
    if not grades then return set end
    for g, list in pairs(grades) do if g <= grade then for _, p in ipairs(list) do set[p] = true end end end
    return set
end

local function dbPerms(job, grade)
    local rows = WL.DB.query('SELECT perm FROM lw_permissions WHERE job = ? AND grade <= ?', { job, grade })
    if not rows or #rows == 0 then return nil end
    local set = {}
    for _, r in ipairs(rows) do set[r.perm] = true end
    return set
end

function WL.Perms.effective(identifier, job, grade)
    local c = cache[identifier]
    if c and (GetGameTimer() - c.ts) < TTL then return c.perms end
    local set = dbPerms(job, grade) or configPerms(job, grade)
    local ov = WL.DB.query('SELECT perm, allow FROM lw_permission_overrides WHERE identifier = ?', { identifier })
    if ov then for _, r in ipairs(ov) do if tonumber(r.allow) == 1 then set[r.perm] = true else set[r.perm] = nil end end end
    cache[identifier] = { perms = set, ts = GetGameTimer() }
    return set
end

function WL.Perms.has(set, perm)
    if not perm or perm == '' then return true end
    if set['admin.full'] then return true end
    return set[perm] == true
end

function WL.Perms.list(set)
    local out = {}
    if set['admin.full'] then for _, p in ipairs(Config.Perms.All) do out[p] = true end return out end
    for p, v in pairs(set) do if v then out[p] = true end end
    return out
end
