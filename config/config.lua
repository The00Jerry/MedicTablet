--[[
    SunLife Roleplay – Medic-Tablet
    Hauptkonfiguration.

    WICHTIG:
      * Alle sicherheitsrelevanten Werte werden serverseitig ausgewertet.
      * Die Datenbank ist die "Source of Truth" fuer Preisliste, Versicherungen,
        Berechtigungen und Einstellungen. Diese Config liefert die START-/SEED-Werte
        und wird beim ersten Start (bzw. bei leeren Tabellen) in die DB uebernommen.
      * Aenderungen ueber das Team-Panel / Tablet-Einstellungen ueberschreiben die
        DB-Werte zur Laufzeit. Config-Aenderungen greifen nur bei Neu-Seed.
]]

Config = {}

-- Sprache (siehe shared/locale.lua)
Config.Locale = 'de'

-- Debug-Ausgaben in der Server-/Client-Konsole
Config.Debug = false

-- Name der ESX-Ressource (ESX Legacy)
Config.ESXResource = 'es_extended'

-----------------------------------------------------------------------------
-- 1. TABLET: OEFFNUNGSMOEGLICHKEITEN
-----------------------------------------------------------------------------
Config.Open = {
    -- Command, z.B. /medictablet
    command = {
        enabled = true,
        name    = 'medictablet',
    },
    -- Tastendruck (RegisterKeyMapping). Standard: F6
    key = {
        enabled = true,
        default = 'F6',
        -- interner Name des Commands fuer die Tastenbelegung
        mapCommand = 'medictablet_key',
    },
    -- Nutzbares Item (ESX usable item). Item muss in der DB/Inventar existieren.
    item = {
        enabled = false,
        name    = 'medic_tablet',
    },
    -- ox_target an festen Orten (z.B. Empfangstresen im Krankenhaus)
    target = {
        enabled = true,
        model   = nil, -- optional: Ped-/Objektmodell; nil = Zonen unten
        zones = {
            -- vector3 Position, Radius (m), Label
            { coords = vector3(340.0, -1396.4, 32.5), radius = 1.5, label = 'Medic-Tablet oeffnen' },
        },
    },
}

-----------------------------------------------------------------------------
-- 2. BRANDING (zentral, wird ins NUI uebergeben)
-----------------------------------------------------------------------------
Config.Branding = {
    serverName   = 'SunLife Roleplay',
    clinicName   = 'SunLife Medical Center',
    departments  = { 'Notaufnahme', 'Chirurgie', 'Innere Medizin', 'Verwaltung' },
    logo         = 'assets/logo.svg', -- relativ zu html/
    theme        = 'dark',            -- 'dark' | 'light'
    colorPrimary = '#e11d48',         -- Hauptfarbe (SunLife rot)
    colorAccent  = '#f59e0b',         -- Akzentfarbe
    colorBg      = '#0b0f19',         -- Hintergrund (dark)
}

-----------------------------------------------------------------------------
-- 3. FEATURE-TOGGLES (Module aktivieren/deaktivieren)
-----------------------------------------------------------------------------
Config.Features = {
    tabletEnabled   = true,  -- Master-Schalter fuer das gesamte Tablet
    dashboard       = true,
    patientSearch   = true,
    treatments      = true,
    invoicing       = true,
    pricelist       = true,
    insurance       = true,
    insuranceNPC    = true,
    weeklyBilling   = true,
    staffOverview   = true,
    auditLog        = true,
    settings        = true,
}

-----------------------------------------------------------------------------
-- 4. BILLING-ADAPTER (Rechnungssystem)
-----------------------------------------------------------------------------
-- provider:
--   'codem' -> CodeM Billing V2 (server/adapters/billing_codem.lua)
--   'esx'   -> ESX Bank/Society Fallback (server/adapters/billing_esx.lua)
-- fallbackToESX: Ist 'codem' nicht gestartet oder schlaegt der Aufruf fehl,
--                wird automatisch der ESX-Adapter benutzt (statt Rechnung zu verlieren).
Config.Billing = {
    provider      = 'codem',
    fallbackToESX = true,

    -- Society/Job-Konto, dem eingehende Zahlungen gutgeschrieben werden (ESX-Adapter)
    society       = 'ambulance',

    --[[ CodeM Billing V2 – Schnittstellen-Mapping.
         >>> HIER die ECHTEN Werte aus deiner CodeM-Ressource eintragen. <<<
         Es werden bewusst KEINE Exports/Events fest im Code angenommen.
         Trage genau EINE Aufrufart ein (export ODER event) – siehe Adapter-Doc.
         Sind resource/exportName leer, meldet der Adapter das sauber
         und (falls fallbackToESX = true) wird ESX benutzt.
    ]]
    codem = {
        resource   = 'codem-billing', -- Ressourcenname von CodeM Billing V2 (pruefen!)

        -- Variante A: Export-Aufruf. exportName = Name des Exports in CodeM.
        -- Beispielhafte, NICHT bestaetigte Signatur -> im Adapter dokumentiert.
        useExport  = false,
        exportName = '', -- z.B. 'CreateInvoice' – NUR eintragen wenn real vorhanden

        -- Variante B: Server-Event. eventName = Servertrigger in CodeM.
        useEvent   = false,
        eventName  = '', -- z.B. 'codem-billing:server:sendInvoice'

        -- Feldnamen des Payloads, die CodeM erwartet. Anpassen an echte Struktur.
        fields = {
            targetIdentifier = 'identifier', -- Ziel-Spieler (permanenter Identifier)
            senderIdentifier = 'sender',
            society          = 'society',
            label            = 'label',
            amount           = 'amount',
            reason           = 'reason',
        },
    },
}

-----------------------------------------------------------------------------
-- 5. AUDIT / LOGGING
-----------------------------------------------------------------------------
Config.Audit = {
    enabled = true,
    -- Discord-Webhooks je Kategorie (leer lassen = aus). Niemals im Client verwenden.
    webhooks = {
        default   = '',
        billing   = '',
        insurance = '',
        security  = '',
        settings  = '',
    },
    -- Wieviele Log-Zeilen behaelt die "letzten Aktivitaeten"-Ansicht per Query (Pagination greift zusaetzlich)
    recentLimit = 50,
}

-----------------------------------------------------------------------------
-- 6. SICHERHEIT / RATE-LIMITS
-----------------------------------------------------------------------------
Config.Security = {
    -- Max. NUI-/Server-Callbacks pro Spieler und Zeitfenster
    rateLimit = {
        windowMs = 10000, -- 10s Fenster
        maxCalls = 60,    -- max. 60 sensible Aktionen / Fenster
    },
    -- Distanz-Check: Spieler muss "an einem Tablet-Ort/Fahrzeug" sein? Aus = ueberall.
    requireOnDuty = false, -- true = nur im Dienst (ESX job onDuty) nutzbar
}

-----------------------------------------------------------------------------
-- 6b. WEB-APP RECHNUNGS-BRUECKE
-----------------------------------------------------------------------------
-- Die externe Web-App legt Rechnungswuensche in der Tabelle mt_invoice_queue ab.
-- Dieser Poller holt sie ab und erstellt sie ECHT ueber den Billing-Adapter.
-- Benoetigt sql/webapp.sql. Deaktivieren, wenn keine Web-App genutzt wird.
Config.WebBridge = {
    enabled            = true,
    pollIntervalSeconds= 5,
    batch              = 10,  -- max. Rechnungen pro Durchlauf
    maxAttempts        = 3,   -- Wiederholungen bei transienten Fehlern
}

-----------------------------------------------------------------------------
-- 7. IDENTIFIER
-----------------------------------------------------------------------------
-- Permanenter Charakter-Identifier. ESX Legacy: 'identifier' (license:...) in users-Tabelle.
-- charId = numerische Charakter-ID falls vorhanden (Multichar). Wir speichern beide,
-- verknuepfen Akten aber IMMER ueber den permanenten Identifier.
Config.Identifier = {
    -- Spalte in der users-Tabelle mit dem permanenten Identifier
    column = 'identifier',
}
