fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'medictablet'
author 'SunLife Roleplay'
description 'Medic-Tablet: Patientenakten, Rechnungen, Preisliste, Krankenversicherung & Team-Panel-Anbindung (ESX Legacy, oxmysql, ox_target, CodeM Billing V2)'
version '1.0.0'

-- Abhaengigkeiten. ESX ('es_extended'), oxmysql und ox_target muessen laufen.
-- CodeM Billing V2 ist optional: faellt der Adapter auf ESX-Bank/Society zurueck,
-- wenn CodeM nicht gestartet ist (siehe config/config.lua -> Config.Billing).
dependencies {
    'oxmysql',
    'es_extended',
    'ox_target',
}

shared_scripts {
    'config/config.lua',
    'config/permissions.lua',
    'config/pricelist.lua',
    'config/insurance.lua',
    'config/panel.lua',
    'shared/util.lua',
    'shared/locale.lua',
}

client_scripts {
    'client/main.lua',
    'client/nui.lua',
    'client/insurance_npc.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/db.lua',
    'server/ratelimit.lua',
    'server/audit.lua',
    'server/permissions.lua',
    'server/adapters/account.lua',
    'server/adapters/billing_esx.lua',
    'server/adapters/billing_codem.lua',
    'server/adapters/billing.lua',
    'server/main.lua',
    'server/dashboard.lua',
    'server/patients.lua',
    'server/treatments.lua',
    'server/pricelist.lua',
    'server/insurance.lua',
    'server/insurance_billing.lua',
    'server/billing.lua',
    'server/webbridge.lua',
    'server/panel.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/assets/logo.svg',
}
