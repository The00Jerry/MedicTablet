--[[ Audit-Log + optionale Discord-Webhooks. ]]

PD = PD or {}
PD.Audit = {}

local function webhookFor(category)
    local w = Config.Audit.webhooks or {}
    return w[category] or w.default or ''
end
local function ser(v)
    if v == nil then return nil end
    if type(v) == 'table' then local ok, s = pcall(function() return json.encode(v) end); return ok and s or tostring(v) end
    return tostring(v)
end

function PD.Audit.log(ctx, e)
    if not Config.Audit.enabled then return end
    ctx = ctx or {}; e = e or {}
    local category = e.category or 'default'
    local ok = PD.DB.insert([[INSERT INTO pd_audit_log
        (actor_identifier, actor_name, discord_id, category, action, target_type, target_id, old_value, new_value, reason, result)
        VALUES (?,?,?,?,?,?,?,?,?,?,?)]], {
        ctx.identifier or '', ctx.name or '', ctx.discord or '', category, e.action or 'unknown',
        e.target_type or '', tostring(e.target_id or ''), ser(e.old), ser(e.new), e.reason or '', e.result or 'ok' })
    if ok == nil then PD.Util.err('Audit-Log fehlgeschlagen:', e.action) end
    local url = webhookFor(category)
    if url ~= '' then PD.Audit.discord(url, ctx, e) end
end

function PD.Audit.discord(url, ctx, e)
    local color = e.result == 'denied' and 15158332 or (e.result == 'error' and 15105570 or 3447003)
    local fields = {
        { name = 'Aktion', value = tostring(e.action or ''), inline = true },
        { name = 'Ergebnis', value = tostring(e.result or 'ok'), inline = true },
        { name = 'Beamter', value = ('%s\n`%s`'):format(ctx.name or '-', ctx.identifier or '-'), inline = false },
    }
    if e.target_type and e.target_type ~= '' then
        fields[#fields + 1] = { name = 'Ziel', value = ('%s #%s'):format(e.target_type, tostring(e.target_id or '')), inline = true }
    end
    if e.reason and e.reason ~= '' then fields[#fields + 1] = { name = 'Grund', value = e.reason, inline = false } end
    local payload = { username = 'LSPD MDT | ' .. (Config.Branding.serverName or 'SunLife'),
        embeds = { { title = 'Audit: ' .. (e.action or ''), color = color, fields = fields, footer = { text = os.date('%Y-%m-%d %H:%M:%S') } } } }
    PerformHttpRequest(url, function(status)
        if status ~= 200 and status ~= 204 then PD.Util.warn('Discord-Webhook HTTP', tostring(status)) end
    end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end
