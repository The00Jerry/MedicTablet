--[[ Dashboard, Bootstrap, Staff, Audit, Einstellungen, Rechte-Verwaltung. ]]

PD = PD or {}
PD.Settings = {}

function PD.Settings.get(key, default)
    local raw = PD.DB.scalar('SELECT svalue FROM pd_settings WHERE skey = ?', { key })
    if raw == nil then return default end
    local ok, v = pcall(function() return json.decode(raw) end)
    if not ok then return default end
    return v
end
function PD.Settings.set(key, tbl, by)
    PD.DB.update('INSERT INTO pd_settings (skey, svalue, updated_by) VALUES (?,?,?) ON DUPLICATE KEY UPDATE svalue=VALUES(svalue), updated_by=VALUES(updated_by)', { key, json.encode(tbl), by or '' })
end

function PD.Settings.onDutyOfficers()
    local ESX = PD.getESX()
    local out = {}
    if not ESX then return out end
    local allowed = {}
    for _, j in ipairs(Config.Perms.AllowedJobs) do allowed[j] = true end
    for _, src in ipairs(GetPlayers()) do
        local xp = ESX.GetPlayerFromId(tonumber(src))
        if xp and xp.job and allowed[xp.job.name] then
            if not Config.Security.requireOnDuty or xp.job.onDuty ~= false then
                out[#out + 1] = { name = xp.getName and xp.getName() or xp.name, grade_label = xp.job.grade_label or tostring(xp.job.grade), grade = xp.job.grade }
            end
        end
    end
    return out
end

local function dashboardData()
    return {
        onDuty = PD.Settings.onDutyOfficers(),
        activeWanted = PD.DB.scalar("SELECT COUNT(*) FROM pd_wanted WHERE status='active'") or 0,
        openReports = PD.DB.scalar("SELECT COUNT(*) FROM pd_reports WHERE status='open'") or 0,
        todayCharges = PD.DB.scalar("SELECT COUNT(*) FROM pd_charges WHERE status='issued' AND DATE(created_at)=CURDATE()") or 0,
        topWanted = PD.DB.query([[SELECT w.reason, w.level, c.firstname, c.lastname, c.identifier
            FROM pd_wanted w JOIN pd_citizens c ON c.id=w.citizen_id WHERE w.status='active'
            ORDER BY FIELD(w.level,'high','medium','low'), w.created_at DESC LIMIT 6]]) or {},
        recentCitizens = PD.DB.query('SELECT identifier, firstname, lastname, is_wanted, updated_at FROM pd_citizens ORDER BY updated_at DESC LIMIT 8') or {},
        notice = PD.Settings.get('notice', { text = '' }),
    }
end

PD.register('tablet.bootstrap', { perm = 'tablet.open' }, function(ctx, data)
    return {
        identity = { name = ctx.name, job = ctx.job, grade = ctx.grade, identifier = ctx.identifier },
        branding = PD.Settings.get('branding', Config.Branding),
        features = PD.Settings.get('features', Config.Features),
        perms = PD.Perms.list(ctx.perms),
        dashboard = Config.Features.dashboard and dashboardData() or nil,
    }
end)

PD.register('dashboard.data', { perm = 'tablet.open', feature = 'dashboard' }, function(ctx, data)
    return { dashboard = dashboardData() }
end)

PD.register('staff.overview', { perm = 'staff.view', feature = 'staffOverview' }, function(ctx, data)
    local activity = PD.DB.query('SELECT actor_name, action, target_type, target_id, result, created_at FROM pd_audit_log ORDER BY id DESC LIMIT 30') or {}
    return { onDuty = PD.Settings.onDutyOfficers(), activity = activity }
end)

PD.register('audit.list', { perm = 'audit.view', feature = 'auditLog' }, function(ctx, data)
    local page = PD.Util.clampInt(data.page or 1, 1)
    local pageSize = PD.Util.clampInt(data.pageSize or 25, 1, 100)
    local offset = (page - 1) * pageSize
    local cat = tostring(data.category or '')
    local where, params = '1=1', {}
    if cat ~= '' and cat ~= 'all' then where = 'category = ?'; params = { cat } end
    local total = PD.DB.scalar('SELECT COUNT(*) FROM pd_audit_log WHERE ' .. where, params) or 0
    local rows = PD.DB.query(('SELECT id, actor_name, actor_identifier, category, action, target_type, target_id, result, reason, created_at FROM pd_audit_log WHERE %s ORDER BY id DESC LIMIT %d OFFSET %d'):format(where, pageSize, offset), params) or {}
    return { rows = rows, total = total, page = page, pageSize = pageSize }
end)

-- Einstellungen
PD.register('settings.get', { perm = 'settings.edit', feature = 'settings' }, function(ctx, data)
    return { branding = PD.Settings.get('branding', Config.Branding), features = PD.Settings.get('features', Config.Features), notice = PD.Settings.get('notice', { text = '' }) }
end)
PD.register('settings.save', { perm = 'settings.edit', feature = 'settings' }, function(ctx, data)
    local saved = {}
    if type(data.branding) == 'table' then PD.Settings.set('branding', data.branding, ctx.identifier); saved.branding = true end
    if type(data.features) == 'table' then PD.Settings.set('features', data.features, ctx.identifier); saved.features = true end
    if type(data.notice) == 'table' then PD.Settings.set('notice', data.notice, ctx.identifier); saved.notice = true end
    PD.Audit.log(ctx, { category = 'settings', action = 'settings.save', new = saved })
    return { ok = true, message = PD.L('saved') }
end)

-- Rechte-Overrides / Sperre
PD.register('perms.setOverride', { perm = 'settings.edit', feature = 'settings' }, function(ctx, data)
    local identifier = tostring(data.identifier or ''); local perm = tostring(data.perm or '')
    if identifier == '' or perm == '' then return PD.fail('invalid_input') end
    local allow = (data.allow == true or data.allow == 1) and 1 or 0
    PD.DB.update('INSERT INTO pd_permission_overrides (identifier, perm, allow, created_by) VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE allow=VALUES(allow), created_by=VALUES(created_by)', { identifier, perm, allow, ctx.identifier })
    PD.Perms.invalidate(identifier)
    PD.Audit.log(ctx, { category = 'settings', action = 'perm.override', target_type = 'user', target_id = identifier, new = { perm = perm, allow = allow } })
    return { ok = true }
end)
PD.register('perms.lock', { perm = 'settings.edit', feature = 'settings' }, function(ctx, data)
    local identifier = tostring(data.identifier or '')
    if identifier == '' then return PD.fail('invalid_input') end
    local locked = (data.locked == true or data.locked == 1) and 1 or 0
    PD.DB.update('INSERT INTO pd_user_locks (identifier, locked, reason, created_by) VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE locked=VALUES(locked), reason=VALUES(reason)', { identifier, locked, tostring(data.reason or ''):sub(1, 200), ctx.identifier })
    PD.Perms.invalidate(identifier)
    PD.Audit.log(ctx, { category = 'security', action = 'user.lock', target_type = 'user', target_id = identifier, new = { locked = locked } })
    return { ok = true }
end)
