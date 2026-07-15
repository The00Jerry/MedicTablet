--[[
    Krankenversicherung – SEED & Systemkonfiguration.

    * Genau DREI frei konfigurierbare Versicherungsstufen.
    * Namen, Preise, Prozentsaetze etc. stehen NICHT fest im Code -> hier als Seed,
      danach DB (Tabelle mt_insurance_tiers) = Source of Truth, pflegbar per Panel/Tablet.
    * Alte Rechnungen bleiben unveraendert (Snapshot in mt_invoice_refs).
]]

Config.Insurance = {}

-----------------------------------------------------------------------------
-- 3 Versicherungsstufen (SEED)
-----------------------------------------------------------------------------
-- tier_key ist stabil (nicht aendern), label/desc/... frei anpassbar.
Config.Insurance.TiersSeed = {
    {
        tier_key       = 'basic',
        label          = 'Basisversicherung',
        description    = 'Grundschutz fuer die wichtigsten Behandlungen.',
        color          = '#38bdf8',
        icon           = 'shield',
        weekly_premium = 500,   -- woechentlicher Beitrag ($)
        coverage_pct   = 20,    -- prozentuale Kostenuebernahme
        max_per_invoice= 2000,  -- max. Uebernahme pro Rechnung ($); 0 = unbegrenzt
        weekly_cap     = 5000,  -- woechentliches Erstattungslimit ($); 0 = unbegrenzt
        active         = true,
        min_term_days  = 0,     -- Mindestlaufzeit (Tage); 0 = keine
        cancel_notice_days = 0, -- Kuendigungsfrist (Tage); 0 = sofort
        waiting_days   = 0,     -- Wartezeit bis Schutz aktiv (Tage)
    },
    {
        tier_key       = 'comfort',
        label          = 'Komfortversicherung',
        description    = 'Erweiterter Schutz mit hoeherer Kostenuebernahme.',
        color          = '#34d399',
        icon           = 'shield-check',
        weekly_premium = 1200,
        coverage_pct   = 50,
        max_per_invoice= 5000,
        weekly_cap     = 12000,
        active         = true,
        min_term_days  = 7,
        cancel_notice_days = 0,
        waiting_days   = 0,
    },
    {
        tier_key       = 'premium',
        label          = 'Premiumversicherung',
        description    = 'Rundum-Schutz mit maximaler Kostenuebernahme.',
        color          = '#f59e0b',
        icon           = 'crown',
        weekly_premium = 2500,
        coverage_pct   = 80,
        max_per_invoice= 15000,
        weekly_cap     = 30000,
        active         = true,
        min_term_days  = 14,
        cancel_notice_days = 7,
        waiting_days   = 1,
    },
}

-----------------------------------------------------------------------------
-- Versicherungs-NPC (ox_target)
-----------------------------------------------------------------------------
Config.Insurance.NPC = {
    enabled  = true,
    ped      = 's_m_m_doctor_01',           -- Ped-Modell
    coords   = vector4(295.9, -600.1, 43.28, 20.0), -- x,y,z,heading
    scenario = 'WORLD_HUMAN_CLIPBOARD',      -- optionales Szenario (nil = keins)
    anim     = nil,                          -- alternativ { dict=, name= }
    invincible = true,
    freeze     = true,
    blip = {
        enabled = true,
        sprite  = 274,
        color   = 25,
        scale   = 0.8,
        label   = 'Krankenversicherung',
    },
    target = {
        label = 'Krankenversicherung verwalten',
        icon  = 'fa-solid fa-heart-pulse',
        distance = 2.0,
    },
}

-----------------------------------------------------------------------------
-- Woechentliche Beitrags-Abbuchung
-----------------------------------------------------------------------------
Config.Insurance.Billing = {
    -- ESX-Konto, von dem abgebucht wird
    account      = 'bank',

    -- Abbuchungszeitpunkt (Serverzeit). weekday: 1=Mo ... 7=So
    weekday      = 1,
    hour         = 4,
    minute       = 0,

    -- Wie oft der Scheduler prueft, ob eine faellige Woche offen ist (Minuten)
    checkIntervalMinutes = 15,

    -- Wiederholungen bei fehlendem Guthaben
    maxAttempts        = 3,
    retryIntervalHours = 12,

    -- Kulanzzeit (Stunden) bevor Pausierung/Kuendigung greift
    graceHours   = 48,

    -- Verhalten bei endgueltig fehlgeschlagener Zahlung nach maxAttempts:
    --   'pause'  -> Versicherung pausieren (kein Schutz, spaeter reaktivierbar)
    --   'cancel' -> Versicherung kuendigen
    onFail       = 'pause',

    -- Ingame-Benachrichtigungen an Online-Spieler
    notify = {
        success   = true,
        failed    = true,
        grace     = true,
        paused    = true,
        cancelled = true,
        upcoming  = false, -- Hinweis auf naechste Abbuchung
    },
}

-----------------------------------------------------------------------------
-- Verrechnung des Versicherungsanteils (Sektion 10)
-----------------------------------------------------------------------------
-- 'patient_only'  -> nur der reduzierte Patientenbetrag geht an Billing (Standard)
-- 'insurer_pays'  -> zusaetzlich zahlt ein Versicherungskonto an die Medic-Society
-- 'full_then_net' -> Gesamtbetrag buchen, Anteil separat gegenverrechnen
Config.Insurance.SettlementMode = 'patient_only'

-- Nur relevant fuer 'insurer_pays'/'full_then_net':
-- ESX-Addonaccount des Versicherers (muss real existieren, sonst wird geloggt & uebersprungen)
Config.Insurance.InsurerAccount = 'society_insurance'
