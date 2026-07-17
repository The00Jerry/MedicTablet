--[[
    Preisliste – SEED-Werte.
    Diese Eintraege werden nur beim ERSTEN Start (leere Tabelle mt_pricelist_items)
    in die Datenbank uebernommen. Danach ist die DB die Source of Truth und wird
    ueber Tablet/Team-Panel gepflegt. Aenderungen hier haben dann keine Wirkung mehr.

    WICHTIG: Preisaenderungen veraendern NIE bereits erstellte Rechnungen –
    Name & Preis werden bei der Rechnung als Momentaufnahme separat gespeichert.
]]

Config.PricelistSeed = {}

Config.PricelistSeed.Categories = {
    { key = 'diagnostics', label = 'Diagnostik',      sort = 10 },
    { key = 'treatment',   label = 'Behandlung',      sort = 20 },
    { key = 'surgery',     label = 'Chirurgie',       sort = 30 },
    { key = 'transport',   label = 'Transport',       sort = 40 },
    { key = 'stationary',  label = 'Stationaer',      sort = 50 },
}

-- required_perm: Recht, das zum Auswaehlen dieser Leistung noetig ist (leer = keins gesondert)
Config.PricelistSeed.Items = {
    { code = 'EXAM01',  label = 'Erstuntersuchung',     category = 'diagnostics', price = 250,   perm = '',                desc = 'Aufnahme und erste Diagnostik' },
    { code = 'TREAT01', label = 'Allgemeine Behandlung',category = 'treatment',   price = 400,   perm = '',                desc = 'Standardbehandlung' },
    { code = 'WOUND01', label = 'Wundversorgung',       category = 'treatment',   price = 350,   perm = '',                desc = 'Reinigung, Naht, Verband' },
    { code = 'MED01',   label = 'Medikamentengabe',     category = 'treatment',   price = 150,   perm = '',                desc = 'Verabreichung von Medikamenten' },
    { code = 'XRAY01',  label = 'Röntgenuntersuchung', category = 'diagnostics', price = 600,   perm = '',                desc = 'Bildgebende Diagnostik' },
    { code = 'SURG01',  label = 'Operation',            category = 'surgery',     price = 3500,  perm = 'treatment.edit',  desc = 'Operativer Eingriff' },
    { code = 'CPR01',   label = 'Wiederbelebung',       category = 'surgery',     price = 2500,  perm = '',                desc = 'Reanimation' },
    { code = 'TRANS01', label = 'Krankentransport',     category = 'transport',   price = 500,   perm = '',                desc = 'Transport zum Krankenhaus' },
    { code = 'STAT01',  label = 'Stationäre Aufnahme', category = 'stationary',  price = 1200,  perm = '',                desc = 'Aufnahme zur Beobachtung' },
}
