fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'gk_pausemenu'
description 'Custom NUI pause menu: takes over the native ESC menu with an entirely custom-drawn UI. Map is a self-drawn image (real GTA V map art, extracted via _tools/map_extract) with a themed Locations panel fed by a live scan of every real native blip server-wide (search, sprite-grouped colour accents, real blip icons where safe, per-location toggle/preview/waypoint) -- not a native-frontend takeover, see client/main.lua for why. Settings hands off to the real native Settings screen. No hard dependency on vice_hud; defers to it cooperatively (via its exports, or by not touching HUD/radar at all) when it is running, and matches its gender-based accent colour.'
version     '1.0.0'

dependencies {
    'ox_lib',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/images/*.jpg',
    'html/images/*.png',
    'html/images/blips/*.png', -- app.js's LOCAL_ICON_SPRITES -- the glob above isn't recursive, this subfolder needs its own line
    'html/data/*.json',        -- app.js's SPRITE_DATA/HUD_COLORS (sprite id -> icon, HUD colour id -> hex)
}

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

client_scripts {
    'client/blips.lua',         -- GK.ScanBlips() -- scans every active native blip server-wide, see its own header comment
    'client/native_pages.lua',  -- history/rationale behind the current Map + Settings design; see its header comment
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}
