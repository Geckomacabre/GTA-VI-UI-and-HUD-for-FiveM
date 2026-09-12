fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'gk_pausemenu'
description 'Custom NUI pause menu: takes over the native ESC menu with a dashboard UI (sidebar profile/stats/OOC chat, navbar, Player Details/Report/Patch Notes cards, footer icons), reskinned after SY_PauseMenu and themed to match vice_hud (self-hosted GTAArtDeco/Pricedown fonts, its .plate glass surface, gender-based accent colour). Map, Settings and Keybinds all hand off to the real native frontend screens rather than any custom NUI -- see client/main.lua for why. No hard dependency on vice_hud, qbx_core, or MugShotBase64; defers to each cooperatively when running.'
version     '2.0.0'

dependencies {
    'ox_lib',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/fonts/*.otf',        -- Pricedown (dashboard money figures) -- same files vice_hud/html/fonts ships, copied rather than referenced cross-resource
    'html/fonts/*.ttf',        -- GTAArtDeco (dashboard headings/labels), ditto
}

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}
