--[[
    Kennzeichenabfrage. Halterdaten kommen aus der ESX-Tabelle owned_vehicles
    (Spalten owner=identifier, plate). Weicht deine Struktur ab, hier anpassen.
]]

PD = PD or {}

local VEH_TABLE = 'owned_vehicles'
local VEH_OWNER = 'owner'
local VEH_PLATE = 'plate'

PD.register('vehicles.lookup', { perm = 'vehicle.lookup', feature = 'vehicles' }, function(ctx, data)
    local plate = PD.Util.trim(tostring(data.plate or '')):upper()
    if #plate < 2 then return PD.fail('invalid_input') end

    local owner = nil
    -- owned_vehicles kann fehlen -> geschuetzt abfragen
    local exists = PD.DB.scalar("SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?", { VEH_TABLE })
    if exists then
        local row = PD.DB.single(('SELECT `%s` AS owner FROM `%s` WHERE REPLACE(`%s`," ","") = ? LIMIT 1'):format(VEH_OWNER, VEH_TABLE, VEH_PLATE), { plate:gsub('%s', '') })
        if row and row.owner then
            local c = PD.DB.single('SELECT identifier, firstname, lastname, fingerprint, is_wanted FROM pd_citizens WHERE identifier = ?', { row.owner })
            if not c then
                -- Halter noch ohne Akte -> Basisdaten aus users
                local u = PD.DB.single('SELECT identifier, firstname, lastname FROM users WHERE identifier = ?', { row.owner })
                if u then owner = { identifier = u.identifier, firstname = u.firstname, lastname = u.lastname, is_wanted = 0 } end
            else
                owner = c
            end
        end
    end

    local flags = PD.DB.query("SELECT id, flag, reason, officer_identifier, created_at FROM pd_vehicle_flags WHERE REPLACE(plate,' ','') = ? AND status='active'", { plate:gsub('%s', '') }) or {}
    PD.Audit.log(ctx, { action = 'vehicle.lookup', target_type = 'plate', target_id = plate })
    return { plate = plate, owner = owner, flags = flags, canFlag = ctx.can('wanted.manage') }
end)

PD.register('vehicles.flag', { perm = 'wanted.manage', feature = 'vehicles' }, function(ctx, data)
    local plate = PD.Util.trim(tostring(data.plate or '')):upper():gsub('%s', '')
    local flag = tostring(data.flag or '')
    if plate == '' or flag == '' then return PD.fail('invalid_input') end
    local id = PD.DB.insert('INSERT INTO pd_vehicle_flags (plate, flag, reason, officer_identifier) VALUES (?,?,?,?)',
        { plate, flag:sub(1, 32), tostring(data.reason or ''):sub(1, 250), ctx.identifier })
    PD.Audit.log(ctx, { category = 'wanted', action = 'vehicle.flag', target_type = 'plate', target_id = plate, new = { flag = flag } })
    return { ok = true, id = id }
end)

PD.register('vehicles.clearFlag', { perm = 'wanted.manage', feature = 'vehicles' }, function(ctx, data)
    local f = PD.DB.single('SELECT * FROM pd_vehicle_flags WHERE id = ?', { tonumber(data.id) })
    if not f then return PD.fail('invalid_input') end
    PD.DB.update("UPDATE pd_vehicle_flags SET status='cleared' WHERE id=?", { f.id })
    PD.Audit.log(ctx, { category = 'wanted', action = 'vehicle.clearflag', target_type = 'plate', target_id = f.plate })
    return { ok = true }
end)
