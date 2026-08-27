fx_version 'cerulean'
game 'gta5'

name 'um_gigs'
description 'Snarf and Ryde Me: two parody gig-economy phone apps. Work that finds you, instead of a board you drive to.'
author 'Geckomacabre'
version '1.0.0'

shared_script 'config.lua'

client_scripts {
    '@ox_lib/init.lua',
    'client.lua',
}

server_scripts {
    '@ox_lib/init.lua',
    'server.lua',
}

-- Both apps are served from this resource and registered with lb-phone at
-- runtime, so every file the phone loads has to be declared here.
files {
    'ui/snarf.html',
    'ui/rydeme.html',
    'ui/app.js',
    'ui/app.css',
    'ui/snarf.svg',
    'ui/rydeme.svg',
    'ui/Optien.ttf',
    'ui/fonts/GTAArtDecoRegular.ttf',
    'ui/fonts/GTAArtDecoMedium.ttf',
    'ui/fonts/arista-pro.pro-trial-regular.ttf',
    -- Vendored from geocaching_phone, same as its own copy: the destination
    -- picker on the Ride tab is the same GTA-coordinate Leaflet map that app
    -- already uses, not a second map implementation.
    'ui/leaflet.js',
    'ui/leaflet.css',
}

dependencies {
    'ox_lib',
    'ox_target',
    'qbx_core',
    'lb-phone',
}

lua54 'yes'
