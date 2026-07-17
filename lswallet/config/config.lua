--[[
    City of Los Santos – Department of Licensing & Identification (Wallet)
    Hauptkonfiguration.

    * Sicherheitsrelevante Aktionen werden serverseitig geprueft.
    * Karten sind dauerhaft ueber den permanenten Charakter-Identifier verknuepft.
    * Stammdaten (Name, Geburtsdatum, Geschlecht) kommen aus der ESX users-Tabelle.
]]

Config = {}

Config.Locale = 'de'
Config.Debug = false
Config.ESXResource = 'es_extended'

-----------------------------------------------------------------------------
-- Wallet oeffnen
-----------------------------------------------------------------------------
Config.Open = {
    command = { enabled = true, name = 'wallet' },
    key     = { enabled = true, default = 'F2', mapCommand = 'wallet_key' },
    item    = { enabled = false, name = 'wallet' },
}

-----------------------------------------------------------------------------
-- Branding
-----------------------------------------------------------------------------
Config.Branding = {
    cityName  = 'City of Los Santos',
    deptName  = 'Department of Licensing & Identification',
    shortName = 'DOL',
    serverName= 'SunLife Roleplay',
    logo      = 'assets/logo.svg',
    theme     = 'dark',
    colorPrimary = '#2f6f4f',   -- dezentes Behoerden-Gruen
    colorAccent  = '#c9a94a',
    colorBg      = '#0c0f13',
}

-----------------------------------------------------------------------------
-- DMV-NPC (ox_target)
-----------------------------------------------------------------------------
Config.NPC = {
    enabled   = true,
    ped       = 'ig_lifeinvad_female',
    coords    = vector4(-544.85, -204.05, 38.22, 210.0), -- Rathaus/DMV
    scenario  = 'WORLD_HUMAN_SEAT_LEDGE',
    invincible= true,
    freeze    = true,
    blip = { enabled = true, sprite = 498, color = 2, scale = 0.8, label = 'Licensing & Identification' },
    target = { label = 'Schalter aufsuchen', icon = 'fa-solid fa-id-card', distance = 2.0 },
}

-----------------------------------------------------------------------------
-- Karten / Gebuehren
-----------------------------------------------------------------------------
Config.Cards = {
    -- Konto fuer Gebuehren
    account = 'bank',

    idFee            = 250,   -- Personalausweis
    driverFee        = 500,   -- Fuehrerschein (bei Ausstellung/Autorisierung)
    businessFee      = 150,   -- Visitenkarte
    ticketFee        = 0,     -- Ticket/Coupon drucken

    -- Gueltigkeit (Tage); 0 = unbegrenzt
    idExpiryDays     = 0,
    driverExpiryDays = 0,

    -- Fuehrerschein nur nach Antrag + Autorisierung durch DOL-Mitarbeiter?
    requireApplicationForDriver = true,
    -- Personalausweis direkt am Schalter ausstellbar?
    idSelfService    = true,
}

-----------------------------------------------------------------------------
-- Audit / Discord
-----------------------------------------------------------------------------
Config.Audit = {
    enabled = true,
    webhooks = { default = '', security = '' },
}

-----------------------------------------------------------------------------
-- Sicherheit
-----------------------------------------------------------------------------
Config.Security = {
    rateLimit = { windowMs = 10000, maxCalls = 60 },
}

Config.Identifier = { column = 'identifier' }
