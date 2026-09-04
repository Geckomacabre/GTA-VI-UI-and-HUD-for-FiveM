fx_version 'cerulean'
game 'gta5'

name 'qbx_relog'
description 'Singleplayer-style character switching: relog to the picker, or hold a key for the corner face panel and the switch cinematic'
version '2.1.0'

shared_script '@ox_lib/init.lua'
shared_script 'config.lua'

client_scripts {
    'client/headshots.lua',
    'client/wheel.lua',
    'client/switch.lua',
    'client/vice_theme.lua',
    'client/main.lua',
}

server_script 'server.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    -- The two GTA Art Deco cuts, served from this resource rather than fetched
    -- from vice_hud over nui://: a cross-resource URL would make this panel
    -- depend on another resource being started to render its own text, and a
    -- font 404 fails silently. Same call qb-menu makes.
    --
    -- Regenerate with:
    --   cp '[standalone]/vice_hud/html/fonts/GTAArtDeco*.ttf' '[qbx]/qbx_relog/html/fonts/'
    'html/fonts/GTAArtDecoRegular.ttf',
    'html/fonts/GTAArtDecoMedium.ttf',
}

dependencies {
    'ox_lib',
    'qbx_core',
}

lua54 'yes'
