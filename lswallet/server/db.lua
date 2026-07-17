--[[ DB-Helper (oxmysql). Parametrisierte Queries. ]]

WL = WL or {}
WL.DB = {}

function WL.DB.query(sql, params) local ok, r = pcall(function() return MySQL.query.await(sql, params or {}) end); if not ok then WL.Util.err('DB.query:', tostring(r)); return nil end return r or {} end
function WL.DB.single(sql, params) local ok, r = pcall(function() return MySQL.single.await(sql, params or {}) end); if not ok then WL.Util.err('DB.single:', tostring(r)); return nil end return r end
function WL.DB.scalar(sql, params) local ok, r = pcall(function() return MySQL.scalar.await(sql, params or {}) end); if not ok then WL.Util.err('DB.scalar:', tostring(r)); return nil end return r end
function WL.DB.insert(sql, params) local ok, r = pcall(function() return MySQL.insert.await(sql, params or {}) end); if not ok then WL.Util.err('DB.insert:', tostring(r)); return nil end return r end
function WL.DB.update(sql, params) local ok, r = pcall(function() return MySQL.update.await(sql, params or {}) end); if not ok then WL.Util.err('DB.update:', tostring(r)); return nil end return r or 0 end
function WL.DB.isEmpty(tbl) return (tonumber(WL.DB.scalar(('SELECT COUNT(*) FROM `%s`'):format(tbl))) or 0) == 0 end
