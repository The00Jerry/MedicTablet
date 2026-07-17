--[[ DB-Helper (oxmysql). Ausschliesslich parametrisierte Queries. ]]

PD = PD or {}
PD.DB = {}

function PD.DB.query(sql, params)
    local ok, res = pcall(function() return MySQL.query.await(sql, params or {}) end)
    if not ok then PD.Util.err('DB.query:', tostring(res), '| SQL:', sql); return nil, res end
    return res or {}
end
function PD.DB.single(sql, params)
    local ok, res = pcall(function() return MySQL.single.await(sql, params or {}) end)
    if not ok then PD.Util.err('DB.single:', tostring(res), '| SQL:', sql); return nil, res end
    return res
end
function PD.DB.scalar(sql, params)
    local ok, res = pcall(function() return MySQL.scalar.await(sql, params or {}) end)
    if not ok then PD.Util.err('DB.scalar:', tostring(res), '| SQL:', sql); return nil, res end
    return res
end
function PD.DB.insert(sql, params)
    local ok, res = pcall(function() return MySQL.insert.await(sql, params or {}) end)
    if not ok then PD.Util.err('DB.insert:', tostring(res), '| SQL:', sql); return nil, res end
    return res
end
function PD.DB.update(sql, params)
    local ok, res = pcall(function() return MySQL.update.await(sql, params or {}) end)
    if not ok then PD.Util.err('DB.update:', tostring(res), '| SQL:', sql); return nil, res end
    return res or 0
end
function PD.DB.isEmpty(tbl)
    local c = PD.DB.scalar(('SELECT COUNT(*) FROM `%s`'):format(tbl))
    return (tonumber(c) or 0) == 0
end
