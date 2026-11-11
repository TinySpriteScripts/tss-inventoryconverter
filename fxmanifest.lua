fx_version "cerulean"
game "gta5"
lua54 'yes'

name "TSS-InventoryConverter"
author "TinySprite"
description "Move player, stash, trunk and glovebox items from one inventory to another"
version "2.0.0"
discord "https://discord.gg/ZMFfC54FdJ"
tebex "https://tinysprite.dev/"

dependency "tss_bridge"
dependency "oxmysql"

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config.lua',
    'server/presets.lua',
    'server/items.lua',
    'server/server.lua',
}
