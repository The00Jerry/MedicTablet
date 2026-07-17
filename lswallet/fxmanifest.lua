fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lswallet'
author 'SunLife Roleplay'
description 'City of Los Santos – Department of Licensing & Identification: Wallet mit Ausweisen, Fuehrerscheinen, Visitenkarten, Job-Wallets, Tickets/Coupons, DMV-NPC & Admin-Center (ESX, oxmysql, ox_target)'
version '1.0.0'

dependencies {
    'oxmysql',
    'es_extended',
    'ox_target',
}

shared_scripts {
    'config/config.lua',
    'config/permissions.lua',
    'config/templates.lua',
    'shared/util.lua',
    'shared/locale.lua',
}

client_scripts {
    'client/main.lua',
    'client/nui.lua',
    'client/dmv.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/db.lua',
    'server/ratelimit.lua',
    'server/audit.lua',
    'server/permissions.lua',
    'server/license.lua',
    'server/main.lua',
    'server/wallet.lua',
    'server/applications.lua',
    'server/tickets.lua',
    'server/admin.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/preview.html',
    'html/assets/logo.svg',
}
