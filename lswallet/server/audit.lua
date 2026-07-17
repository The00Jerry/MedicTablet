--[[ Audit-Log + optionale Discord-Webhooks. ]]
WL = WL or {}
WL.Audit = {}

local function webhookFor(cat) local w = Config.Audit.webhooks or {}; return w[cat] or w.default or '' end
local function ser(v) if v == nil then return nil end if type(v) == 'table' then local ok, s = pcall(function() return json.encode(v) end); return ok and s or tostring(v) end return tostring(v) end

function WL.Audit.log(ctx, e)
    if not Config.Audit.enabled then return end
    ctx = ctx or {}; e = e or {}
    WL.DB.insert([[INSERT INTO lw_audit_log (actor_identifier, actor_name, discord_id, category, action, target_type, target_id, old_value, new_value, reason, result)
        VALUES (?,?,?,?,?,?,?,?,?,?,?)]], {
        ctx.identifier or '', ctx.name or '', ctx.discord or '', e.category or 'default', e.action or 'unknown',
        e.target_type or '', tostring(e.target_id or ''), ser(e.old), ser(e.new), e.reason or '', e.result or 'ok' })
    local url = webhookFor(e.category or 'default')
    if url ~= '' then
        local payload = { username = 'DOL Wallet | ' .. (Config.Branding.serverName or 'SunLife'),
            embeds = { { title = 'Audit: ' .. (e.action or ''), color = e.result == 'denied' and 15158332 or 3066993,
              fields = { { name = 'Akteur', value = (ctx.name or '-') .. ' `' .. (ctx.identifier or '-') .. '`' }, { name = 'Ergebnis', value = tostring(e.result or 'ok'), inline = true } },
              footer = { text = os.date('%Y-%m-%d %H:%M:%S') } } } }
        PerformHttpRequest(url, function() end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
    end
end
