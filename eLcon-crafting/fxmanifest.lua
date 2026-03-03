fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'eLcon-crafting'
author 'eLcon'
description 'Configurable crafting system with ox_target/ox_inventory support for QBCore (framework-agnostic style)'
version '1.0.0'

shared_scripts {
    'config.lua'
}

server_scripts {
    'server/main.lua'
}

client_scripts {
    'client/main.lua'
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/script.js'
}

dependencies {
    'ox_inventory'
}
