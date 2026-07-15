--[[
    Berechtigungssystem (Config-Seed).

    * Rechte werden NIE ausschliesslich im Client geprueft. Jede sensible Aktion
      prueft server/permissions.lua zusaetzlich serverseitig.
    * Zuordnung erfolgt ueber ESX-Job + Job-Grade. Zusaetzliche/ueberschreibende
      Einzelberechtigungen kommen aus der DB-Tabelle `mt_permission_overrides`
      (per Team-Panel / Tablet-Einstellungen pflegbar) und haben Vorrang.
    * Raenge stehen NICHT fest im Code – hier nur die Standard-Zuordnung, die per
      DB/Panel ueberschrieben werden kann.
]]

Config.Perms = {}

-- Alle bekannten Berechtigungs-Schluessel (siehe Doku PERMISSIONS.md)
Config.Perms.All = {
    'tablet.open',
    'patient.search',
    'patient.view',
    'patient.edit',
    'treatment.create',
    'treatment.edit',
    'treatment.archive',
    'notes.internal.view',
    'invoice.create',
    'invoice.cancel',
    'discount.grant',
    'pricelist.view',
    'pricelist.edit',
    'insurance.patient.view',
    'insurance.manage',
    'insurance.failed.view',
    'insurance.retry',
    'staff.view',
    'audit.view',
    'settings.edit',
    'admin.full',        -- impliziert alle Rechte
}

-- Zugelassene ESX-Jobs (nur diese Jobs koennen das Tablet ueberhaupt nutzen)
Config.Perms.AllowedJobs = { 'ambulance' }

--[[ Rang-Zuordnung: job -> grade(Zahl) -> Liste von Rechten.
     grade ist der MINDEST-Grade: ein Spieler erhaelt alle Rechte seines Grades
     PLUS aller niedrigeren Grades (kumulativ).
     Beispielhierarchie (frei anpassbar):
       0 Praktikant      – eingeschraenkter Lesezugriff
       1 Rettungssani    – Patientenakten & Behandlungen
       2 Arzt            – volle medizinische Bearbeitung
       3 Oberarzt        – zusaetzliche Verwaltung
       4 Klinikleitung   – Preisliste, Rechte, Einstellungen (admin.full)
]]
Config.Perms.Grades = {
    ambulance = {
        [0] = {
            'tablet.open', 'patient.search', 'patient.view', 'pricelist.view',
            'insurance.patient.view',
        },
        [1] = {
            'treatment.create', 'patient.edit',
        },
        [2] = {
            'treatment.edit', 'treatment.archive', 'invoice.create',
            'discount.grant', 'notes.internal.view',
        },
        [3] = {
            'invoice.cancel', 'staff.view', 'audit.view',
            'insurance.failed.view', 'insurance.retry',
        },
        [4] = {
            'admin.full', -- Klinikleitung: alles
        },
    },
}

-- Grades, die als Voll-Admin gelten (Kurzform; 'admin.full' oben tut dasselbe)
Config.Perms.AdminGrades = {
    ambulance = { [4] = true },
}
