--[[ Serverseitige Berechtigungspruefung (Job/Grade + DB-Overrides + Sperre). ]]

PD = PD or {}
PD.Perms = {}

local cache = {}
local CACHE_TTL = 30000

function PD.Perms.invalidate(identifier)
    if identifier then cache[identifier] = nil else cache = {} end
end

local function jobAllowed(job)
    for _, j in ipairs(Config.Perms.AllowedJobs) do if j == job then return true end end
    return false
end

local function configPerms(job, grade)
    local set = {}
    local grades = Config.Perms.Grades[job]
    if not grades then return set end
    for g, list in pairs(grades) do
        if g <= grade then for _, p in ipairs(list) do set[p] = true end end
    end
    return set
end

local function dbPerms(job, grade)
    local rows = PD.DB.query('SELECT perm FROM pd_permissions WHERE job = ? AND grade <= ?', { job, grade })
    if not rows or #rows == 0 then return nil end
    local set = {}
    for _, r in ipairs(rows) do set[r.perm] = true end
    return set
end

function PD.Perms.isLocked(identifier)
    return tonumber(PD.DB.scalar('SELECT locked FROM pd_user_locks WHERE identifier = ?', { identifier })) == 1
end

function PD.Perms.effective(identifier, job, grade)
    local c = cache[identifier]
    if c and (GetGameTimer() - c.ts) < CACHE_TTL then return c.perms end
    local set = {}
    if jobAllowed(job) then set = dbPerms(job, grade) or configPerms(job, grade) end
    local ov = PD.DB.query('SELECT perm, allow FROM pd_permission_overrides WHERE identifier = ?', { identifier })
    if ov then for _, r in ipairs(ov) do if tonumber(r.allow) == 1 then set[r.perm] = true else set[r.perm] = nil end end end
    cache[identifier] = { perms = set, ts = GetGameTimer() }
    return set
end

function PD.Perms.has(permsSet, perm)
    if not perm or perm == '' then return true end
    if permsSet['admin.full'] then return true end
    return permsSet[perm] == true
end

function PD.Perms.list(permsSet)
    local out = {}
    if permsSet['admin.full'] then for _, p in ipairs(Config.Perms.All) do out[p] = true end return out end
    for p, v in pairs(permsSet) do if v then out[p] = true end end
    return out
end
