--[[ i18n. Fehlermeldungen & UI-Texte zentral. ]]

MT = MT or {}
MT.Locales = {}

MT.Locales['de'] = {
    -- allgemein
    ['no_permission']       = 'Fehlende Berechtigung.',
    ['tablet_disabled']     = 'Das Medic-Tablet ist derzeit deaktiviert.',
    ['not_allowed_job']     = 'Dein Job ist für das Tablet nicht freigeschaltet.',
    ['user_locked']         = 'Dein Zugriff auf das Tablet wurde gesperrt.',
    ['rate_limited']        = 'Zu viele Anfragen. Bitte kurz warten.',
    ['invalid_input']       = 'Ungültige Eingabe.',
    ['db_error']            = 'Datenbankfehler. Bitte an die Leitung wenden.',
    ['not_on_duty']         = 'Du bist nicht im Dienst.',

    -- billing
    ['patient_offline']     = 'Der Patient ist nicht online.',
    ['player_not_found']    = 'Spieler oder Charakter nicht gefunden.',
    ['billing_down']        = 'Das Rechnungssystem (CodeM Billing V2) ist nicht gestartet.',
    ['invoice_failed']      = 'Rechnung konnte nicht erstellt werden.',
    ['invalid_amount']      = 'Ungültiger Rechnungsbetrag.',
    ['invoice_duplicate']   = 'Diese Rechnung wurde möglicherweise bereits erstellt.',
    ['invoice_ok']          = 'Rechnung erfolgreich erstellt.',
    ['invoice_cancelled']   = 'Rechnung storniert.',

    -- insurance
    ['ins_none']            = 'Keine aktive Versicherung.',
    ['ins_waiting']         = 'Versicherung befindet sich in der Wartezeit.',
    ['ins_paused']          = 'Versicherung ist pausiert.',
    ['ins_subscribed']      = 'Versicherung erfolgreich abgeschlossen.',
    ['ins_switched']        = 'Versicherung gewechselt.',
    ['ins_cancelled']       = 'Versicherung gekündigt.',
    ['ins_min_term']        = 'Mindestlaufzeit noch nicht erreicht.',
    ['ins_charge_ok']       = 'Versicherungsbeitrag abgebucht.',
    ['ins_charge_failed']   = 'Beitrag konnte nicht abgebucht werden (kein Guthaben).',
    ['ins_insufficient']    = 'Nicht genug Guthaben auf dem Konto.',

    -- treatments / patients
    ['patient_created']     = 'Patientenakte angelegt.',
    ['treatment_saved']     = 'Behandlung gespeichert.',
    ['treatment_archived']  = 'Behandlung archiviert.',
    ['saved']               = 'Gespeichert.',
}

MT.L = function(key, ...)
    local loc = MT.Locales[(Config and Config.Locale) or 'de'] or MT.Locales['de']
    local s = loc[key] or key
    if select('#', ...) > 0 then
        return string.format(s, ...)
    end
    return s
end

return MT.Locales
