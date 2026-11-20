fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'whip_roulette'
description 'Casino roulette on whip: the casino\'s own tables and wheel, a dealer, every bet on a clickable board, money through whip.'
version '0.1.0'
author 'Flek'

shared_script '@whip_core/lib/satellite.lua'
shared_script 'config.lua'
shared_script 'shared/wheel.lua'
client_scripts {
    'client/table.lua',
    'client/play.lua',
    'client/editor.lua',
}
server_scripts {
    'server/main.lua',
}

ui_page 'html/index.html'
files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

dependency 'whip_core'
whip_requires '1.0'
