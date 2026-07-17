--[[ i18n. ]]

WL = WL or {}
WL.Locales = {}

WL.Locales['de'] = {
    ['no_permission']   = 'Fehlende Berechtigung.',
    ['disabled']        = 'Die Wallet ist derzeit deaktiviert.',
    ['rate_limited']    = 'Zu viele Anfragen. Bitte kurz warten.',
    ['invalid_input']   = 'Ungültige Eingabe.',
    ['db_error']        = 'Datenbankfehler.',
    ['player_not_found']= 'Spieler oder Charakter nicht gefunden.',
    ['saved']           = 'Gespeichert.',
    ['no_money']        = 'Nicht genug Guthaben.',

    ['id_issued']       = 'Personalausweis ausgestellt.',
    ['id_exists']       = 'Du besitzt bereits einen gültigen Personalausweis.',
    ['card_issued']     = 'Karte ausgestellt.',
    ['card_revoked']    = 'Karte entzogen.',
    ['app_created']     = 'Antrag eingereicht. Ein Mitarbeiter prüft ihn.',
    ['app_exists']      = 'Es liegt bereits ein offener Antrag vor.',
    ['app_approved']    = 'Antrag genehmigt – Karte ausgestellt.',
    ['app_denied']      = 'Antrag abgelehnt.',
    ['ticket_printed']  = 'Ticket/Coupon gedruckt.',
}

WL.L = function(key, ...)
    local loc = WL.Locales[(Config and Config.Locale) or 'de'] or WL.Locales['de']
    local s = loc[key] or key
    if select('#', ...) > 0 then return string.format(s, ...) end
    return s
end

return WL.Locales
