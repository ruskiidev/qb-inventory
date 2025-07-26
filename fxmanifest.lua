fx_version 'cerulean'
game 'gta5'
lua54 'yes'
description 'inventory'
version '0.0.0.1'

shared_scripts {
    '@qb-core/shared/locale.lua',
    'locales/*.lua',
    'config.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/functions.lua',
    'server/inventory.lua'
}

client_scripts {
    'client/inventory.lua',
}

ui_page {
    'html/ui.html'
}

files {
    'html/ui.html',
    'html/css/main.css',
    'html/js/app.js',
    'html/images/*.png',
    'html/images/*.jpg',
    'html/*.ttf'
}

--[[ files {
    'weaponsmeta.meta'
}
 ]]
--[[ data_file 'WEAPONINFO_FILE' 'weaponsmeta.meta' ]]

dependency 'qb-core'
