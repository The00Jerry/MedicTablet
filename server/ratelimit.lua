--[[ Einfacher serverseitiger Rate-Limiter je Spielerquelle. ]]

MT = MT or {}
MT.RateLimit = {}

local buckets = {} -- [src] = { count, windowStart }

function MT.RateLimit.check(src)
    local cfg = Config.Security.rateLimit
    local now = GetGameTimer()
    local b = buckets[src]
    if not b or (now - b.windowStart) > cfg.windowMs then
        buckets[src] = { count = 1, windowStart = now }
        return true
    end
    b.count = b.count + 1
    if b.count > cfg.maxCalls then
        return false
    end
    return true
end

AddEventHandler('playerDropped', function()
    local src = source
    buckets[src] = nil
end)
