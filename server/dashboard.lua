--[[ Dashboard + Bootstrap (Daten beim Oeffnen des Tablets). ]]

MT = MT or {}
MT.Settings = {}

-- Einstellung lesen (DB -> Fallback default). DB ist Panel-/Tablet-editierbar.
function MT.Settings.get(key, default)
    local raw = MT.DB.scalar('SELECT svalue FROM mt_settings WHERE skey = ?', { key })
    if raw == nil then return default end
    local ok, val = pcall(function() return json.decode(raw) end)
    if not ok then return default end
    return val
end

function MT.Settings.set(key, tbl, by)
    MT.DB.update('INSERT INTO mt_settings (skey, svalue, updated_by) VALUES (?,?,?) ON DUPLICATE KEY UPDATE svalue=VALUES(svalue), updated_by=VALUES(updated_by)',
        { key, json.encode(tbl), by or '' })
end

-- Liste der aktuell im Dienst befindlichen Medic-Mitarbeiter
function MT.Settings.onDutyMedics()
    local ESX = MT.getESX()
    local out = {}
    if not ESX then return out end
    local allowed = {}
    for _, j in ipairs(Config.Perms.AllowedJobs) do allowed[j] = true end
    for _, src in ipairs(GetPlayers()) do
        local xp = ESX.GetPlayerFromId(tonumber(src))
        if xp and xp.job and allowed[xp.job.name] then
            if not Config.Security.requireOnDuty or xp.job.onDuty ~= false then
                out[#out + 1] = {
                    name = xp.getName and xp.getName() or xp.name,
                    grade_label = xp.job.grade_label or tostring(xp.job.grade),
                    grade = xp.job.grade,
                }
            end
        end
    end
    return out
end

local function dashboardData(ctx)
    local todayTreatments = MT.DB.scalar("SELECT COUNT(*) FROM mt_treatments WHERE DATE(created_at)=CURDATE()") or 0
    local todayInvoices = MT.DB.scalar("SELECT COUNT(*) FROM mt_invoice_refs WHERE status='issued' AND DATE(created_at)=CURDATE()") or 0
    local openTreatments = MT.DB.query([[SELECT id, treatment_no, staff_name, diagnosis, status, created_at
        FROM mt_treatments WHERE status IN ('draft','ongoing') ORDER BY created_at DESC LIMIT 10]]) or {}
    local recentPatients = MT.DB.query([[SELECT pr.identifier, pr.firstname, pr.lastname, pr.last_treatment_at, pr.updated_at
        FROM mt_patient_records pr ORDER BY pr.updated_at DESC LIMIT 8]]) or {}

    local data = {
        onDuty = MT.Settings.onDutyMedics(),
        todayTreatments = todayTreatments,
        todayInvoices = todayInvoices,
        openTreatments = openTreatments,
        recentPatients = recentPatients,
        notice = MT.Settings.get('notice', { text = '' }),
    }
    return data
end

-- Bootstrap: alles was das UI beim Oeffnen braucht
MT.register('tablet.bootstrap', { perm = 'tablet.open' }, function(ctx, data)
    return {
        identity = { name = ctx.name, job = ctx.job, grade = ctx.grade, identifier = ctx.identifier },
        branding = MT.Settings.get('branding', Config.Branding),
        features = MT.Settings.get('features', Config.Features),
        perms = MT.Perms.list(ctx.perms),
        dashboard = Config.Features.dashboard and dashboardData(ctx) or nil,
    }
end)

MT.register('dashboard.data', { perm = 'tablet.open', feature = 'dashboard' }, function(ctx, data)
    return { dashboard = dashboardData(ctx) }
end)

-- Staff-Uebersicht + Aktivitaeten
MT.register('staff.overview', { perm = 'staff.view', feature = 'staffOverview' }, function(ctx, data)
    local activity = MT.DB.query([[SELECT actor_name, action, target_type, target_id, result, created_at
        FROM mt_audit_log ORDER BY created_at DESC LIMIT 30]]) or {}
    return { onDuty = MT.Settings.onDutyMedics(), activity = activity }
end)

-- Audit-Log Ansicht (paginiert, filterbar)
MT.register('audit.list', { perm = 'audit.view', feature = 'auditLog' }, function(ctx, data)
    local page = MT.Util.clampInt(data.page or 1, 1)
    local pageSize = MT.Util.clampInt(data.pageSize or 25, 1, 100)
    local offset = (page - 1) * pageSize
    local cat = tostring(data.category or '')
    local where, params = '1=1', {}
    if cat ~= '' and cat ~= 'all' then where = 'category = ?'; params = { cat } end
    local total = MT.DB.scalar('SELECT COUNT(*) FROM mt_audit_log WHERE ' .. where, params) or 0
    local rows = MT.DB.query(('SELECT id, actor_name, actor_identifier, category, action, target_type, target_id, result, reason, created_at FROM mt_audit_log WHERE %s ORDER BY id DESC LIMIT %d OFFSET %d'):format(where, pageSize, offset), params) or {}
    return { rows = rows, total = total, page = page, pageSize = pageSize }
end)
