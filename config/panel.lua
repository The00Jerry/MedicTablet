--[[
    Team-Panel-Anbindung.

    Standardmaessig DEAKTIVIERT ausgeliefert (Config.Panel.enabled = false).
    Quelle der Wahrheit ist dann Config + DB. Wird die Anbindung aktiviert,
    synchronisiert server/panel.lua Einstellungen/Preisliste/Versicherungen
    bidirektional und faellt bei Ausfall auf die zuletzt gespeicherten
    DB-Werte zurueck (siehe Tabelle mt_sync_state).

    SICHERHEIT:
      * API-Schluessel liegt AUSSCHLIESSLICH serverseitig (nie im Client/NUI).
      * Kommunikation nur serverseitig (PerformHttpRequest).
      * Eingehende Panel-Requests werden HMAC-signiert & zeitlich begrenzt geprueft
        (siehe API-Doku docs/API.md). Ohne gueltige Signatur -> abgelehnt & geloggt.
]]

Config.Panel = {
    enabled = false, -- <<< erst aktivieren, wenn das Panel bereit ist

    -- Ausgehende Verbindung (FiveM -> Panel)
    apiUrl  = 'https://panel.example.com/api/medictablet',
    apiKey  = '',    -- Bearer/API-Key; NUR serverseitig. Leer lassen bis vorhanden.
    hmacSecret = '', -- gemeinsames Secret fuer Request-Signatur (HMAC-SHA256)

    -- Eingehende Verbindung (Panel -> FiveM). FiveM oeffnet dafuer HTTP-Endpunkte
    -- ueber den ressourcen-eigenen HTTP-Handler (SetHttpHandler).
    inbound = {
        enabled = false,        -- eingehende Endpunkte aktivieren
        requireSignature = true,-- HMAC-Signatur zwingend
        maxSkewSeconds = 300,   -- max. Zeitversatz signierter Requests (Replay-Schutz)
    },

    -- Synchronisation
    syncIntervalMinutes = 5,   -- Poll-/Push-Intervall
    timeoutMs           = 8000,
    maxRetries          = 4,   -- Verbindungsversuche
    retryBackoffMs      = 2000,-- Basis fuer exponentielles Backoff

    -- Verhalten bei Ausfall:
    --   'last_known' -> mit zuletzt gespeicherten DB-Settings weiterarbeiten (empfohlen)
    onOutage = 'last_known',

    -- Welche Bereiche synchronisiert werden
    sync = {
        settings   = true,
        pricelist  = true,
        insurance  = true,
        auditPush  = true, -- Audit-Logs ans Panel pushen
    },
}
