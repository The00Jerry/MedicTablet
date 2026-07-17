--[[ Rate-Limiter je Spielerquelle. ]]
WL = WL or {}
WL.RateLimit = {}
local buckets = {}
function WL.RateLimit.check(src)
    local cfg = Config.Security.rateLimit
    local now = GetGameTimer()
    local b = buckets[src]
    if not b or (now - b.windowStart) > cfg.windowMs then buckets[src] = { count = 1, windowStart = now }; return true end
    b.count = b.count + 1
    return b.count <= cfg.maxCalls
end
AddEventHandler('playerDropped', function() buckets[source] = nil end)
