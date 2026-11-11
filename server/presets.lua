-- Where each inventory keeps its data.
--
-- format      "ox" = { slot, name, count, metadata }   "qb" = { slot, name, amount, info, type }
--             Reading always accepts both, so this only decides how items are written.
-- players     "framework" = the framework's player table (players.inventory / users.inventory)
--             "shared"    = rows of the `stashes` table whose type is listed in `playerTypes`
-- stashes / trunks / gloveboxes
--   type      "keyed"   = one row per inventory: a key column and a JSON data column
--             "ox"      = ox_inventory style table with owner + name + data
--             "columns" = trunk/glovebox columns on the framework's vehicle table (ox_inventory)
--   key/data  column names; a list means "use the first one that exists" (checked against your database)
--   prefixes  in a shared table, which key prefix marks a trunk or glovebox (the rest is the plate)
--   typeField JSON field holding the inventory type (ak47); `typeKinds` maps type -> trunk/glovebox
-- readOnly    can only be converted FROM

Frameworks = {
    qb   = { players = { table = 'players', key = 'citizenid', data = 'inventory' }, vehicles = { table = 'player_vehicles', key = 'plate' } },
    qbox = { players = { table = 'players', key = 'citizenid', data = 'inventory' }, vehicles = { table = 'player_vehicles', key = 'plate' } },
    esx  = { players = { table = 'users', key = 'identifier', data = 'inventory' }, vehicles = { table = 'owned_vehicles', key = 'plate' } },
}

Presets = {}

Presets.ox = {
    label = 'ox_inventory',
    format = 'ox',
    players = 'framework',
    stashes = { type = 'ox', table = 'ox_inventory', owner = 'owner', name = 'name', data = 'data' },
    trunks = { type = 'columns', column = 'trunk' },
    gloveboxes = { type = 'columns', column = 'glovebox' },
}

Presets.qb = {
    label = 'qb-inventory 2.x',
    format = 'qb',
    players = 'framework',
    stashes = {
        type = 'keyed', table = 'inventories', key = { 'identifier' }, data = { 'items' },
        prefixes = { trunk = 'trunk-', glovebox = 'glovebox-' },
    },
}

Presets.qb_old = {
    label = 'qb-inventory 1.x',
    format = 'qb',
    players = 'framework',
    stashes = { type = 'keyed', table = 'stashitems', key = { 'stash' }, data = { 'items' } },
    trunks = { type = 'keyed', table = 'trunkitems', key = { 'plate' }, data = { 'items' } },
    gloveboxes = { type = 'keyed', table = 'gloveboxitems', key = { 'plate' }, data = { 'items' } },
}

Presets.ps = setmetatable({ label = 'ps-inventory' }, { __index = Presets.qb_old })
Presets.lj = setmetatable({ label = 'lj-inventory' }, { __index = Presets.qb_old })

-- qs-inventory documents its table names but not its columns, so the columns are looked up in your database.
Presets.qs = {
    label = 'qs-inventory',
    format = 'qb',
    players = 'framework',
    stashes = { type = 'keyed', table = 'inventory_stash', key = { 'stash', 'identifier', 'name', 'id' }, data = { 'items', 'data', 'inventory' } },
    trunks = { type = 'keyed', table = 'inventory_trunk', key = { 'plate', 'identifier', 'id' }, data = { 'items', 'data', 'inventory' } },
    gloveboxes = { type = 'keyed', table = 'inventory_glovebox', key = { 'plate', 'identifier', 'id' }, data = { 'items', 'data', 'inventory' } },
}

-- ak47_inventory keeps every inventory in one table. Its data format isn't published, so it is read-only:
-- ak47_inventory itself imports from ox_inventory on first start.
Presets.ak47 = {
    label = 'ak47_inventory',
    format = 'qb',
    readOnly = true,
    players = 'shared',
    stashes = {
        type = 'keyed', table = 'ak47_inventory', key = { 'identifier' }, data = { 'data', 'items', 'inventory' },
        prefixes = { trunk = 'trunk:', glovebox = 'glovebox:' },
        typeField = 'type',
        typeKinds = { trunk = 'trunk', glovebox = 'glovebox' },
        playerTypes = { playerinventory = true, player = true },
    },
}

-- Fill this in for any inventory not listed above, then set Config.From / Config.To to "custom".
Presets.custom = {
    label = 'custom inventory',
    format = 'qb',
    players = 'framework',
    stashes = { type = 'keyed', table = 'my_stashes', key = { 'stash' }, data = { 'items' } },
    trunks = { type = 'keyed', table = 'my_trunks', key = { 'plate' }, data = { 'items' } },
    gloveboxes = { type = 'keyed', table = 'my_gloveboxes', key = { 'plate' }, data = { 'items' } },
}
