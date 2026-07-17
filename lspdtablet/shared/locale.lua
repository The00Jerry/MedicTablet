--[[ i18n. ]]

PD = PD or {}
PD.Locales = {}

PD.Locales['de'] = {
    ['no_permission']    = 'Fehlende Berechtigung.',
    ['tablet_disabled']  = 'Das MDT ist derzeit deaktiviert.',
    ['not_allowed_job']  = 'Dein Job ist für das MDT nicht freigeschaltet.',
    ['user_locked']      = 'Dein Zugriff auf das MDT wurde gesperrt.',
    ['rate_limited']     = 'Zu viele Anfragen. Bitte kurz warten.',
    ['invalid_input']    = 'Ungültige Eingabe.',
    ['db_error']         = 'Datenbankfehler. Bitte an die Leitung wenden.',
    ['not_on_duty']      = 'Du bist nicht im Dienst.',
    ['player_not_found'] = 'Spieler oder Charakter nicht gefunden.',
    ['saved']            = 'Gespeichert.',

    -- Fingerabdruck
    ['fp_no_target']     = 'Keine Person in Reichweite.',
    ['fp_too_far']       = 'Zielperson ist zu weit entfernt.',
    ['fp_ok']            = 'Person identifiziert.',
    ['fp_cancelled']     = 'Scan abgebrochen.',

    -- Bussgeld / Anzeige
    ['charge_ok']        = 'Anzeige erstellt.',
    ['charge_cancelled'] = 'Anzeige storniert.',
    ['charge_duplicate'] = 'Diese Anzeige wurde möglicherweise bereits erstellt.',
    ['patient_offline']  = 'Die Person ist nicht online.',
    ['billing_down']     = 'Das Rechnungssystem (CodeM Billing V2) ist nicht gestartet.',
    ['invoice_failed']   = 'Bussgeld konnte nicht gebucht werden.',
    ['invalid_amount']   = 'Ungültiger Betrag.',
    ['insufficient']     = 'Nicht genug Guthaben auf dem Konto.',

    -- Fahndung
    ['wanted_added']     = 'Zur Fahndung ausgeschrieben.',
    ['wanted_cleared']   = 'Fahndung aufgehoben.',

    -- Berichte
    ['report_saved']     = 'Bericht gespeichert.',
    ['report_closed']    = 'Bericht geschlossen.',
}

PD.L = function(key, ...)
    local loc = PD.Locales[(Config and Config.Locale) or 'de'] or PD.Locales['de']
    local s = loc[key] or key
    if select('#', ...) > 0 then return string.format(s, ...) end
    return s
end

return PD.Locales
