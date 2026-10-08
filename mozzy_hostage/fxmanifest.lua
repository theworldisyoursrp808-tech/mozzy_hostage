fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'mozzy_hostage'
author 'Mozzy Dev'
description 'Mozzy NPC Hostage System - NPC hostages, negotiations, dispatch & robbery integration for Qbox'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/states.lua',
    'shared/lang.lua',
}

client_scripts {
    'bridge/client.lua',
    'client/utils.lua',
    'client/behavior.lua',
    'client/hold.lua',
    'client/main.lua',
    'client/interact.lua',
    'client/menu.lua',
    'client/negotiation.lua',
    'client/debug.lua',
}

server_scripts {
    'bridge/server.lua',
    'server/main.lua',
    'server/actions.lua',
    'server/monitor.lua',
    'server/negotiation.lua',
    'server/api.lua',
}

dependencies {
    '/onesync',
    'ox_lib',
    'qbx_core',
    'ox_target',
}
