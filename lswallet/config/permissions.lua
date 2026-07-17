--[[
    Berechtigungen fuer Verwaltungs-Aktionen (Admin Control Center).
    Die Wallet selbst ist fuer ALLE Spieler nutzbar (eigene Karten ansehen).
    Nur Verwaltungsaktionen (Antrag autorisieren, Lookup, Templates, Karte entziehen)
    erfordern ein Recht – serverseitig geprueft. Zuordnung ueber ESX-Job + Grade,
    DB-Overrides haben Vorrang.
]]

Config.Perms = {}

Config.Perms.All = {
    'wallet.admin.view',       -- Wallet-Lookup / Applications ansehen
    'wallet.admin.authorize',  -- Antraege genehmigen/ablehnen
    'wallet.admin.issue',      -- Karten manuell ausstellen
    'wallet.admin.revoke',     -- Karten entziehen
    'wallet.admin.template',   -- Vorlagen verwalten
    'admin.full',
}

-- Job(s), deren Grades Verwaltungsrechte tragen koennen (z.B. 'dol' = DMV-Mitarbeiter).
-- Spieler ohne diese Rechte koennen weiterhin ihre eigene Wallet nutzen.
Config.Perms.AdminJobs = { 'dol' }

Config.Perms.Grades = {
    dol = {
        [0] = { 'wallet.admin.view' },
        [1] = { 'wallet.admin.authorize', 'wallet.admin.issue' },
        [2] = { 'wallet.admin.revoke' },
        [3] = { 'wallet.admin.template' },
        [4] = { 'admin.full' },
    },
}
