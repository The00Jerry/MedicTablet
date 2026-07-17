--[[ Serverseitiger Rate-Limiter je Spielerquelle. ]]

PD = PD or {}
PD.RateLimit = {}
local buckets = {}

function PD.RateLimit.check(src)
    local cfg = Config.Security.rateLimit
    local now = GetGameTimer()
    local b = buckets[src]
    if not b or (now - b.windowStart) > cfg.windowMs then
        buckets[src] = { count = 1, windowStart = now }; return true
    end
    b.count = b.count + 1
    return b.count <= cfg.maxCalls
end

AddEventHandler('playerDropped', function() buckets[source] = nil end)
