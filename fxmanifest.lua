fx_version 'cerulean'
game 'gta5'

name 'dps-transit'
author 'DaemonAlex'
description 'Multi-modal transit system - Regional Rail, Metro, Roxwood Line, and AI Shuttle Buses with 70/30 passenger/freight scheduling'
version '2.7.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config/*.lua',
    'bridge/init.lua',
    'shared/*.lua'
}

client_scripts {
    'client/*.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/*.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
    'locales/*.json',
    'bridge/qb.lua',
    'bridge/esx.lua'
}

dependencies {
    'ox_lib',
    'ox_target'
}
