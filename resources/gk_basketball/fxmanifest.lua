fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'gk_basketball'
description 'Playable basketball: hoops, shot mechanics, scoring detection and timed pickup matches.'
version     '1.0.0'

dependencies {
    'ox_lib',
    'ox_target',
    'ox_inventory',

    -- Routing buckets and state bags are both state-awareness features. Without
    -- OneSync they fail silently rather than loudly, so say so up front.
    '/onesync',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'data/hoops.json',
}

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
    'shared/util.lua',
}

client_scripts {
    'client/court.lua',      -- defines BB.notify/showHint used by the rest
    'client/hud.lua',
    'client/scoring.lua',
    'client/ball.lua',
    'client/ai.lua',
    'client/placement.lua',
}

server_scripts {
    'server/hoops.lua',      -- loads hoops before match/ball reference BB.courts
    'server/instance.lua',   -- routing buckets; match.lua moves players with these
    'server/ball.lua',
    'server/match.lua',
}
