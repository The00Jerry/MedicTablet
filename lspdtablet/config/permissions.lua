--[[
    Berechtigungssystem (Config-Seed).
    Serverseitig geprueft. Zuordnung ueber ESX-Job + Grade; DB-Overrides haben Vorrang.
]]

Config.Perms = {}

Config.Perms.All = {
    'tablet.open',
    'citizen.search',
    'citizen.view',
    'citizen.edit',
    'fingerprint.scan',
    'notes.view',
    'notes.add',
    'wanted.view',
    'wanted.manage',
    'penalcode.view',
    'penalcode.edit',
    'citation.create',
    'citation.cancel',
    'report.view',
    'report.create',
    'report.edit',
    'report.close',
    'vehicle.lookup',
    'licenses.manage',
    'staff.view',
    'audit.view',
    'settings.edit',
    'admin.full',
}

-- Zugelassene ESX-Jobs
Config.Perms.AllowedJobs = { 'police' }

--[[ job -> grade -> Rechte (kumulativ). Beispielhierarchie:
       0 Cadet        – Lesen, Personensuche, Fingerabdruck
       1 Officer      – Berichte, Bussgelder, Fahndung ansehen
       2 Sergeant     – Fahndung verwalten, Berichte schliessen, Akten bearbeiten
       3 Lieutenant   – Bussgeld stornieren, Statistiken, Audit
       4 Command      – Strafenkatalog, Rechte, Einstellungen (admin.full)
]]
Config.Perms.Grades = {
    police = {
        [0] = {
            'tablet.open', 'citizen.search', 'citizen.view', 'fingerprint.scan',
            'penalcode.view', 'vehicle.lookup', 'wanted.view', 'notes.view',
        },
        [1] = {
            'report.view', 'report.create', 'citation.create', 'notes.add',
        },
        [2] = {
            'wanted.manage', 'report.edit', 'report.close', 'citizen.edit', 'licenses.manage',
        },
        [3] = {
            'citation.cancel', 'staff.view', 'audit.view',
        },
        [4] = {
            'admin.full',
        },
    },
}

Config.Perms.AdminGrades = { police = { [4] = true } }
