--[[
    SunLife Roleplay – LSPD Police-Tablet (MDT)
    Hauptkonfiguration.

    * Sicherheitsrelevante Aktionen werden serverseitig geprueft.
    * Datenbank ist Source of Truth fuer Strafenkatalog, Berechtigungen, Einstellungen.
    * Personen werden dauerhaft ueber den permanenten Charakter-Identifier verknuepft.
]]

Config = {}

Config.Locale = 'de'
Config.Debug = false
Config.ESXResource = 'es_extended'

-----------------------------------------------------------------------------
-- Oeffnungsmoeglichkeiten
-----------------------------------------------------------------------------
Config.Open = {
    command = { enabled = true, name = 'mdt' },
    key     = { enabled = true, default = 'F7', mapCommand = 'lspd_mdt_key' },
    item    = { enabled = false, name = 'police_tablet' },
    target  = {
        enabled = true,
        zones = {
            { coords = vector3(441.0, -981.0, 30.7), radius = 1.6, label = 'MDT oeffnen' }, -- Mission Row
        },
    },
}

-----------------------------------------------------------------------------
-- Branding (LSPD-Look)
-----------------------------------------------------------------------------
Config.Branding = {
    serverName   = 'SunLife Roleplay',
    deptName     = 'Los Santos Police Department',
    shortName    = 'LSPD',
    divisions    = { 'Patrol', 'Traffic', 'Detective Bureau', 'Command' },
    logo         = 'assets/logo.svg',
    theme        = 'dark',
    colorPrimary = '#2b4c8c',  -- LSPD-Navy
    colorAccent  = '#c8a24a',  -- Gold (Badge)
    colorBg      = '#0d131c',
}

-----------------------------------------------------------------------------
-- Feature-Toggles
-----------------------------------------------------------------------------
Config.Features = {
    tabletEnabled = true,
    dashboard     = true,
    citizenSearch = true,
    fingerprint   = true,
    wanted        = true,
    penalcode     = true,
    citations     = true,
    reports       = true,
    vehicles      = true,
    staffOverview = true,
    auditLog      = true,
    settings      = true,
}

-----------------------------------------------------------------------------
-- Fingerabdruck-Scanner
-----------------------------------------------------------------------------
Config.Fingerprint = {
    -- Max. Distanz (Meter) zwischen Beamtem und Zielperson beim Scan.
    -- Wird SERVERSEITIG geprueft (kein Client-Spoofing).
    maxDistance   = 3.0,
    -- Dauer der Scan-Animation (ms) am Client
    scanDurationMs = 4000,
    -- Ziel muss sein: 'any' (jeder in Reichweite) | 'cuffed' (nur gefesselte) | 'nearby'
    targetMode    = 'nearby',
    -- Fingerabdruck-Code-Prefix (Anzeige in der Akte)
    codePrefix    = 'FP',
}

-----------------------------------------------------------------------------
-- Bussgeld/Strafen-Abwicklung (Billing-Adapter)
-----------------------------------------------------------------------------
-- provider: 'codem' (CodeM Billing V2) | 'esx' (Bank-Abbuchung/Society-Fallback)
Config.Billing = {
    provider      = 'codem',
    fallbackToESX = true,
    society       = 'police',

    -- CodeM Billing V2 Mapping – ECHTE Werte deiner Ressource eintragen (siehe README).
    codem = {
        resource   = 'codem-billing',
        useExport  = false,
        exportName = '',
        useEvent   = false,
        eventName  = '',
        fields = {
            targetIdentifier = 'identifier',
            senderIdentifier = 'sender',
            society          = 'society',
            label            = 'label',
            amount           = 'amount',
            reason           = 'reason',
        },
    },
}

-----------------------------------------------------------------------------
-- Audit / Discord
-----------------------------------------------------------------------------
Config.Audit = {
    enabled = true,
    webhooks = { default = '', citations = '', wanted = '', security = '', settings = '' },
    recentLimit = 50,
}

-----------------------------------------------------------------------------
-- Sicherheit
-----------------------------------------------------------------------------
Config.Security = {
    rateLimit = { windowMs = 10000, maxCalls = 60 },
    requireOnDuty = false,
}

Config.Identifier = { column = 'identifier' }
