--[[
    DB-Helper (Wrapper um oxmysql).
    * Ausschliesslich parametrisierte Queries -> Schutz vor SQL-Injection.
    * pcall-gekapselt -> saubere Fehlerbehandlung (kein Ressourcencrash).
    * .await-Varianten (synchron im Thread) fuer klaren Kontrollfluss.
]]

MT = MT or {}
MT.DB = {}

-- SELECT mehrere Zeilen
function MT.DB.query(sql, params)
    local ok, res = pcall(function()
        return MySQL.query.await(sql, params or {})
    end)
    if not ok then
        MT.Util.err('DB.query Fehler:', tostring(res), '| SQL:', sql)
        return nil, res
    end
    return res or {}
end

-- SELECT eine Zeile
function MT.DB.single(sql, params)
    local ok, res = pcall(function()
        return MySQL.single.await(sql, params or {})
    end)
    if not ok then
        MT.Util.err('DB.single Fehler:', tostring(res), '| SQL:', sql)
        return nil, res
    end
    return res
end

-- Einzelwert
function MT.DB.scalar(sql, params)
    local ok, res = pcall(function()
        return MySQL.scalar.await(sql, params or {})
    end)
    if not ok then
        MT.Util.err('DB.scalar Fehler:', tostring(res), '| SQL:', sql)
        return nil, res
    end
    return res
end

-- INSERT -> insertId
function MT.DB.insert(sql, params)
    local ok, res = pcall(function()
        return MySQL.insert.await(sql, params or {})
    end)
    if not ok then
        MT.Util.err('DB.insert Fehler:', tostring(res), '| SQL:', sql)
        return nil, res
    end
    return res
end

-- UPDATE/DELETE -> affectedRows
function MT.DB.update(sql, params)
    local ok, res = pcall(function()
        return MySQL.update.await(sql, params or {})
    end)
    if not ok then
        MT.Util.err('DB.update Fehler:', tostring(res), '| SQL:', sql)
        return nil, res
    end
    return res or 0
end

-- Prueft, ob eine Tabelle leer ist (fuer Seeding)
function MT.DB.isEmpty(table)
    local c = MT.DB.scalar(('SELECT COUNT(*) FROM `%s`'):format(table))
    return (tonumber(c) or 0) == 0
end
