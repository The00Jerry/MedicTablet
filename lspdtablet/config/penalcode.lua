--[[
    Strafenkatalog – SEED.
    Nur beim ersten Start in die DB uebernommen (leere Tabellen). Danach ist die DB
    Source of Truth (pflegbar im Tablet unter "Strafenkatalog").

    Betraege/Haft/Punkte werden bei einer Anzeige als Momentaufnahme separat gespeichert,
    damit spaetere Aenderungen alte Anzeigen nicht veraendern.
    jail = Haft in Monaten (Spiel-Einheit), points = Fuehrerschein-Punkte.
]]

Config.PenalSeed = {}

Config.PenalSeed.Categories = {
    { key = 'traffic',  label = 'Verkehr',           sort = 10 },
    { key = 'property', label = 'Eigentumsdelikte',  sort = 20 },
    { key = 'violence', label = 'Gewaltdelikte',     sort = 30 },
    { key = 'drugs',    label = 'Betaeubungsmittel',  sort = 40 },
    { key = 'other',    label = 'Sonstiges',         sort = 50 },
}

-- required_perm: leer = kein gesondertes Recht noetig
Config.PenalSeed.Offenses = {
    { code = 'V01', label = 'Geschwindigkeitsuebertretung', category = 'traffic',  fine = 250,   jail = 0,  points = 1, desc = 'Zu schnelles Fahren' },
    { code = 'V02', label = 'Rotlichtverstoss',             category = 'traffic',  fine = 300,   jail = 0,  points = 1, desc = 'Missachtung roter Ampel' },
    { code = 'V03', label = 'Fahren ohne Fuehrerschein',    category = 'traffic',  fine = 750,   jail = 1,  points = 3, desc = '' },
    { code = 'E01', label = 'Diebstahl',                    category = 'property', fine = 1000,  jail = 3,  points = 0, desc = '' },
    { code = 'E02', label = 'Einbruch',                     category = 'property', fine = 2500,  jail = 8,  points = 0, desc = '' },
    { code = 'E03', label = 'Fahrzeugdiebstahl (GTA)',      category = 'property', fine = 3000,  jail = 10, points = 0, desc = '' },
    { code = 'G01', label = 'Koerperverletzung',            category = 'violence', fine = 2000,  jail = 6,  points = 0, desc = '' },
    { code = 'G02', label = 'Schwere Koerperverletzung',    category = 'violence', fine = 5000,  jail = 15, points = 0, desc = '' },
    { code = 'G03', label = 'Bewaffneter Raub',             category = 'violence', fine = 8000,  jail = 25, points = 0, desc = '' },
    { code = 'G04', label = 'Angriff auf Beamte',           category = 'violence', fine = 6000,  jail = 20, points = 0, desc = '' },
    { code = 'B01', label = 'Drogenbesitz',                 category = 'drugs',    fine = 1500,  jail = 4,  points = 0, desc = '' },
    { code = 'B02', label = 'Drogenhandel',                 category = 'drugs',    fine = 7500,  jail = 22, points = 0, desc = '', perm = 'penalcode.view' },
    { code = 'S01', label = 'Illegaler Waffenbesitz',       category = 'other',    fine = 4000,  jail = 12, points = 0, desc = '' },
    { code = 'S02', label = 'Widerstand/Flucht',            category = 'other',    fine = 2500,  jail = 7,  points = 0, desc = '' },
}
