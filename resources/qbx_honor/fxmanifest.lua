fx_version 'cerulean'
game 'gta5'

name 'qbx_honor'
description 'RDR2-style persistent honor stat for qbx_core, with a devil/angel toast on the vice_hud NUI.'
author 'em_toolkit'
version '1.0.0'

lua54 'yes'

shared_scripts {
    'config.lua',
}

server_scripts {
    'server/main.lua',
    'server/debug.lua',
}

client_scripts {
    'client/main.lua',
    'client/conduct.lua',
    'client/debug.lua',
}

dependencies {
    'qbx_core',
    'ox_target',
}
