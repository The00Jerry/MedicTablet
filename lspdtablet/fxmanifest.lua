fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lspdtablet'
author 'SunLife Roleplay'
description 'LSPD Police-Tablet/MDT: Personenakten, Fingerabdruck-Scanner, Fahndung/BOLO, Strafenkatalog, Bussgelder (CodeM Billing V2), Berichte, Kennzeichenabfrage (ESX, oxmysql, ox_target)'
version '1.0.0'

dependencies {
    'oxmysql',
    'es_extended',
    'ox_target',
}

shared_scripts {
    'config/config.lua',
    'config/permissions.lua',
    'config/penalcode.lua',
    'shared/util.lua',
    'shared/locale.lua',
}

client_scripts {
    'client/main.lua',
    'client/nui.lua',
    'client/fingerprint.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/db.lua',
    'server/ratelimit.lua',
    'server/audit.lua',
    'server/permissions.lua',
    'server/adapters/billing_esx.lua',
    'server/adapters/billing_codem.lua',
    'server/adapters/billing.lua',
    'server/main.lua',
    'server/dashboard.lua',
    'server/citizens.lua',
    'server/fingerprint.lua',
    'server/wanted.lua',
    'server/penalcode.lua',
    'server/citations.lua',
    'server/reports.lua',
    'server/vehicles.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/preview.html',
    'html/assets/logo.svg',
}
