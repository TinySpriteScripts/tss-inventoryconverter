-- ┌──────────────────────────────┐
-- │    TSS-InventoryConverter     │
-- └──────────────────────────────┘
-- `convertinventory`          preview: reads everything and reports what would change, writes nothing
-- `convertinventory confirm`  backs up the target tables, then writes

local okBridge, TSS = pcall(function() return exports.tss_bridge:GetModules({ 'Inventory' }) end)
if not okBridge then TSS = nil end

local TAG = '^3[Convert Inventory]^7'
local KINDS = { 'player', 'stash', 'trunk', 'glovebox' }
local CONVERT_KEY = { player = 'players', stash = 'stashes', trunk = 'trunks', glovebox = 'gloveboxes' }
local running = false

-- Log file of the current run: `summary` mirrors the console, `details` lists every inventory.
local report = nil

local function log(message, ...)
    local text = select('#', ...) > 0 and message:format(...) or message
    print(('%s %s'):format(TAG, text))
    if report then report.summary[#report.summary + 1] = (text:gsub('%^%d', '')) end
end
local function warn(message, ...) log('^1' .. message .. '^7', ...) end

local function detail(line)
    if report then report.details[#report.details + 1] = line end
end

local function itemList(items, format)
    local parts = {}
    for _, item in ipairs(items) do
        local name = Items.TargetName(item.name, format)
        parts[#parts + 1] = name ~= item.name and ('%s x%d (was %s)'):format(name, item.count, item.name) or ('%s x%d'):format(name, item.count)
    end
    return #parts > 0 and table.concat(parts, ', ') or 'no items'
end

local function saveReport(mode)
    local name = ('logs/%s_%s.log'):format(mode, os.date('%Y-%m-%d_%H-%M-%S'))
    local lines = {
        'TSS-InventoryConverter log',
        ('Date:      %s'):format(os.date('%Y-%m-%d %H:%M:%S')),
        ('Mode:      %s'):format(mode == 'convert' and 'CONVERT (data written)' or 'PREVIEW (nothing written)'),
        ('From / To: %s -> %s (%s framework)'):format(tostring(Config.From), tostring(Config.To), tostring(Config.Framework)),
        ('Overwrite: %s   Backup: %s   DropUnknownItems: %s'):format(tostring(Config.Overwrite), tostring(Config.Backup), tostring(Config.DropUnknownItems)),
        '',
        '==================== SUMMARY ====================',
    }
    for _, line in ipairs(report.summary) do lines[#lines + 1] = line end
    lines[#lines + 1] = ''
    lines[#lines + 1] = '==================== DETAILS ===================='
    lines[#lines + 1] = 'WRITE = converted (or would be in a preview), SKIP = left untouched, ERROR = could not be read (left untouched)'
    for _, line in ipairs(report.details) do lines[#lines + 1] = line end

    local saved = SaveResourceFile(GetCurrentResourceName(), name, table.concat(lines, '\n') .. '\n', -1)
    if saved then
        print(('%s Log saved to ^5%s/%s^7'):format(TAG, GetResourcePath(GetCurrentResourceName()), name))
    else
        print(('%s ^1Could not save the log file %s^7'):format(TAG, name))
    end
end

local function quote(identifier)
    if type(identifier) ~= 'string' or not identifier:match('^[%w_]+$') then
        error(('Invalid SQL name in config: %s'):format(tostring(identifier)), 0)
    end
    return ('`%s`'):format(identifier)
end

local function trim(value)
    return type(value) == 'string' and value:match('^%s*(.-)%s*$') or value
end

local function startsWith(value, prefix)
    return type(value) == 'string' and value:sub(1, #prefix) == prefix
end

-- ┌────────────────┐
-- │    DATABASE    │
-- └────────────────┘

local columnCache = {}

--- Returns a set of the table's columns, or nil when the table doesn't exist.
local function columnsOf(tableName)
    if columnCache[tableName] == nil then
        local rows = MySQL.query.await(
            'SELECT COLUMN_NAME AS name FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?',
            { tableName }) or {}
        local set = false
        for _, row in ipairs(rows) do
            set = set or {}
            set[row.name:lower()] = row.name
        end
        columnCache[tableName] = set
    end
    return columnCache[tableName] or nil
end

--- Picks the first existing column from a name or list of names.
local function pickColumn(tableName, candidates)
    local columns = columnsOf(tableName)
    if not columns then return nil, ('table `%s` not found'):format(tableName) end
    if type(candidates) == 'string' then candidates = { candidates } end
    for _, name in ipairs(candidates) do
        if columns[name:lower()] then return columns[name:lower()] end
    end
    return nil, ('table `%s` has none of the columns: %s'):format(tableName, table.concat(candidates, ', '))
end

-- ┌────────────────┐
-- │    READING     │
-- └────────────────┘

-- A container is one inventory: { kind, id, owner?, items, from = "table.column" }
local function addContainer(result, stats, kind, id, owner, raw, from)
    local decoded, items, err = Items.Decode(raw)
    stats.read = stats.read + 1
    if err then
        stats.unreadable = stats.unreadable + 1
        if stats.unreadable <= 5 then warn('Could not read %s `%s` (%s)', kind, tostring(id), err) end
        detail(('[ERROR] %-10s %s (%s): could not read - %s'):format(kind, tostring(id), from, err))
        return decoded
    end
    result[#result + 1] = { kind = kind, id = tostring(id), owner = owner, items = items, from = from }
    return decoded
end

local function classify(def, id, decoded, defaultKind)
    local kind = defaultKind
    if def.typeField and type(decoded) == 'table' then
        local invType = decoded[def.typeField]
        if def.playerTypes and def.playerTypes[invType] then return 'player', id end
        if def.typeKinds and def.typeKinds[invType] then kind = def.typeKinds[invType] end
    end
    for prefixKind, prefix in pairs(def.prefixes or {}) do
        if startsWith(id, prefix) then return prefixKind, id:sub(#prefix + 1) end
    end
    return kind, id
end

local function readKeyed(def, defaultKind, result, stats)
    local key, err = pickColumn(def.table, def.key)
    if not key then return err end
    local data; data, err = pickColumn(def.table, def.data)
    if not data then return err end

    local rows = MySQL.query.await(('SELECT %s AS id, %s AS data FROM %s'):format(quote(key), quote(data), quote(def.table))) or {}
    for _, row in ipairs(rows) do
        local decoded, items, decodeErr = Items.Decode(row.data)
        stats.read = stats.read + 1
        if decodeErr then
            stats.unreadable = stats.unreadable + 1
            if stats.unreadable <= 5 then warn('Could not read `%s` from %s (%s)', tostring(row.id), def.table, decodeErr) end
            detail(('[ERROR] %-10s %s (%s.%s): could not read - %s'):format('?', tostring(row.id), def.table, data, decodeErr))
        else
            local kind, id = classify(def, tostring(row.id), decoded, defaultKind)
            result[#result + 1] = { kind = kind, id = id, items = items, from = def.table .. '.' .. data }
        end
    end
end

local function readOx(def, result, stats)
    for _, column in ipairs({ def.owner, def.name, def.data }) do
        local ok, err = pickColumn(def.table, column)
        if not ok then return err end
    end
    local rows = MySQL.query.await(('SELECT %s AS owner, %s AS name, %s AS data FROM %s'):format(
        quote(def.owner), quote(def.name), quote(def.data), quote(def.table))) or {}
    for _, row in ipairs(rows) do
        local kind, id = 'stash', row.name
        -- Very old ox_inventory versions kept vehicles in this table.
        if startsWith(id, 'trunk-') then kind, id = 'trunk', id:sub(7)
        elseif startsWith(id, 'glovebox-') then kind, id = 'glovebox', id:sub(10) end
        local owner = row.owner ~= '' and row.owner or nil
        addContainer(result, stats, kind, id, owner, row.data, def.table .. '.' .. def.data)
    end
end

local function readColumns(def, kind, fw, result, stats)
    local column, err = pickColumn(fw.vehicles.table, def.column)
    if not column then return err end
    local rows = MySQL.query.await(('SELECT %s AS id, %s AS data FROM %s WHERE %s IS NOT NULL AND %s <> \'\''):format(
        quote(fw.vehicles.key), quote(column), quote(fw.vehicles.table), quote(column), quote(column))) or {}
    for _, row in ipairs(rows) do
        addContainer(result, stats, kind, trim(row.id), nil, row.data, fw.vehicles.table .. '.' .. column)
    end
end

local function readPlayers(fw, result, stats)
    local p = fw.players
    local column, err = pickColumn(p.table, p.data)
    if not column then return err end
    local rows = MySQL.query.await(('SELECT %s AS id, %s AS data FROM %s'):format(quote(p.key), quote(column), quote(p.table))) or {}
    for _, row in ipairs(rows) do
        addContainer(result, stats, 'player', row.id, nil, row.data, p.table .. '.' .. column)
    end
end

local function readStorage(def, kind, fw, result, stats)
    if not def then return end
    if def.type == 'keyed' then return readKeyed(def, kind, result, stats)
    elseif def.type == 'ox' then return readOx(def, result, stats)
    elseif def.type == 'columns' then return readColumns(def, kind, fw, result, stats) end
    return ('unknown storage type "%s"'):format(tostring(def.type))
end

local function readSource(preset, fw)
    local result, stats, errors = {}, { read = 0, unreadable = 0 }, {}
    local function check(err) if err then errors[#errors + 1] = err end end

    if preset.players == 'framework' then check(readPlayers(fw, result, stats)) end
    check(readStorage(preset.stashes, 'stash', fw, result, stats))
    check(readStorage(preset.trunks, 'trunk', fw, result, stats))
    check(readStorage(preset.gloveboxes, 'glovebox', fw, result, stats))
    return result, stats, errors
end

-- ┌────────────────┐
-- │    WRITING     │
-- └────────────────┘

local function oxOwner(name)
    for _, rule in ipairs(Config.OxStashOwners or {}) do
        local captures = { tostring(name):match(rule.pattern) }
        if captures[1] then
            return type(rule.owner) == 'number' and captures[rule.owner] or tostring(rule.owner)
        end
    end
    return ''
end

local function hasItems(raw)
    local _, items = Items.Decode(raw)
    return items ~= nil and #items > 0
end

--- A store knows one target location, what it already holds, and how to write one container to it.
local function makeStore(def, kind, fw)
    if kind == 'player' then
        local p = fw.players
        local column, err = pickColumn(p.table, p.data)
        if not column then return nil, err end
        local existing = {}
        for _, row in ipairs(MySQL.query.await(('SELECT %s AS id, %s AS data FROM %s'):format(quote(p.key), quote(column), quote(p.table))) or {}) do
            existing[tostring(row.id)] = { data = row.data }
        end
        return {
            table = p.table, label = p.table .. '.' .. column,
            locate = function(c)
                local row = existing[c.id]
                if not row then return nil, 'no character with that id' end
                return { key = c.id, existing = row.data, describe = ('%s.%s (%s = %s)'):format(p.table, column, p.key, c.id),
                    query = ('UPDATE %s SET %s = ? WHERE %s = ?'):format(quote(p.table), quote(column), quote(p.key)),
                    values = function(json) return { json, c.id } end }
            end,
        }
    end

    if not def then return nil, 'the target inventory has no storage for ' .. kind end

    if def.type == 'columns' then
        local v = fw.vehicles
        local column, err = pickColumn(v.table, def.column)
        if not column then return nil, err end
        local existing = {}
        for _, row in ipairs(MySQL.query.await(('SELECT %s AS id, %s AS data FROM %s'):format(quote(v.key), quote(column), quote(v.table))) or {}) do
            existing[trim(row.id)] = { plate = row.id, data = row.data }
        end
        return {
            table = v.table, label = v.table .. '.' .. column,
            locate = function(c)
                local row = existing[trim(c.id)]
                if not row then return nil, 'no owned vehicle with that plate' end
                return { key = row.plate, existing = row.data, describe = ('%s.%s (plate %s)'):format(v.table, column, row.plate),
                    query = ('UPDATE %s SET %s = ? WHERE %s = ?'):format(quote(v.table), quote(column), quote(v.key)),
                    values = function(json) return { json, row.plate } end }
            end,
        }
    end

    if def.type == 'ox' then
        for _, column in ipairs({ def.owner, def.name, def.data }) do
            local ok, err = pickColumn(def.table, column)
            if not ok then return nil, err end
        end
        local existing = {}
        for _, row in ipairs(MySQL.query.await(('SELECT %s AS owner, %s AS name, %s AS data FROM %s'):format(
            quote(def.owner), quote(def.name), quote(def.data), quote(def.table))) or {}) do
            existing[(row.owner or '') .. '\0' .. row.name] = { data = row.data }
        end
        return {
            table = def.table, label = def.table .. '.' .. def.data,
            locate = function(c)
                local owner = c.owner or oxOwner(c.id)
                local key = owner .. '\0' .. c.id
                local row = existing[key]
                local describe = ('%s (name %s, owner %s)'):format(def.table, c.id, owner == '' and 'shared' or owner)
                if row then
                    return { key = key, existing = row.data, describe = describe,
                        query = ('UPDATE %s SET %s = ? WHERE %s = ? AND COALESCE(%s, \'\') = ?'):format(
                            quote(def.table), quote(def.data), quote(def.name), quote(def.owner)),
                        values = function(json) return { json, c.id, owner } end }
                end
                return { key = key, describe = describe,
                    query = ('INSERT INTO %s (%s, %s, %s) VALUES (?, ?, ?)'):format(
                        quote(def.table), quote(def.owner), quote(def.name), quote(def.data)),
                    values = function(json) return { owner, c.id, json } end }
            end,
        }
    end

    -- keyed
    local key, err = pickColumn(def.table, def.key)
    if not key then return nil, err end
    local data; data, err = pickColumn(def.table, def.data)
    if not data then return nil, err end
    local existing = {}
    for _, row in ipairs(MySQL.query.await(('SELECT %s AS id, %s AS data FROM %s'):format(quote(key), quote(data), quote(def.table))) or {}) do
        existing[tostring(row.id)] = { data = row.data }
    end
    return {
        table = def.table, label = def.table .. '.' .. data,
        locate = function(c)
            local id = c.id
            if kind ~= 'stash' and def.prefixes and def.prefixes[kind] then id = def.prefixes[kind] .. trim(id) end
            if kind == 'stash' and c.owner then id = Config.OwnedStashName:format(c.id, c.owner) end
            local row = existing[id]
            local describe = ('%s (%s = %s)'):format(def.table, key, id)
            if row then
                return { key = id, existing = row.data, describe = describe,
                    query = ('UPDATE %s SET %s = ? WHERE %s = ?'):format(quote(def.table), quote(data), quote(key)),
                    values = function(json) return { json, id } end }
            end
            return { key = id, describe = describe,
                query = ('INSERT INTO %s (%s, %s) VALUES (?, ?)'):format(quote(def.table), quote(key), quote(data)),
                values = function(json) return { id, json } end }
        end,
    }
end

local function targetDef(preset, kind)
    if kind == 'stash' then return preset.stashes end
    if kind == 'trunk' then return preset.trunks or (preset.stashes and preset.stashes.prefixes and preset.stashes.prefixes.trunk and preset.stashes) end
    if kind == 'glovebox' then return preset.gloveboxes or (preset.stashes and preset.stashes.prefixes and preset.stashes.prefixes.glovebox and preset.stashes) end
end

-- ┌──────────────────┐
-- │    ITEM CHECK    │
-- └──────────────────┘

local SYSTEM_MATCH = { ox = 'ox', qb = 'qb', qb_old = 'qb', ps = 'ps', lj = 'lj', qs = 'qs' }

--- Returns the running inventory's item list when it is the target inventory.
local function knownItems()
    if not TSS then return nil, 'tss_bridge not available' end
    local okSystem, system = pcall(TSS.Inventory.System)
    local wanted = SYSTEM_MATCH[Config.To]
    if not okSystem or not system or not wanted or not tostring(system):lower():find(wanted, 1, true) then
        return nil, ('the running inventory (%s) is not the target, item names were not checked'):format(tostring(system))
    end
    local okItems, items = pcall(TSS.Inventory.Items)
    if not okItems or type(items) ~= 'table' or next(items) == nil then return nil, 'could not read the item list' end
    return items
end

-- ┌────────────────┐
-- │    COMMAND     │
-- └────────────────┘

local function convert(confirm)
    local from, to = Presets[Config.From], Presets[Config.To]
    local fw = Frameworks[Config.Framework]
    if not from then return warn('Unknown Config.From "%s"', tostring(Config.From)) end
    if not to then return warn('Unknown Config.To "%s"', tostring(Config.To)) end
    if not fw then return warn('Unknown Config.Framework "%s"', tostring(Config.Framework)) end
    if to.readOnly then
        return warn('%s can only be converted FROM. It imports from ox_inventory itself on first start.', to.label)
    end
    if Config.From == Config.To then return warn('Config.From and Config.To are the same') end

    log('%s: ^5%s^7 -> ^5%s^7 (%s framework)', confirm and '^1CONVERTING^7' or '^2PREVIEW^7', from.label, to.label, Config.Framework)

    local containers, readStats, readErrors = readSource(from, fw)
    for _, err in ipairs(readErrors) do warn('Source: %s', err) end
    log('Read ^5%d^7 inventories from %s (%d unreadable)', readStats.read, from.label, readStats.unreadable)

    -- Players stored in the same column and format need no conversion.
    local samePlayers = from.players == 'framework' and to.players == 'framework' and from.format == to.format

    local items, itemNote = knownItems()
    if not items then log('^3Note^7: %s', itemNote) end
    local unknown = {}
    local function keep(name)
        if not items or items[name] or items[name:lower()] then return true end
        unknown[name] = (unknown[name] or 0) + 1
        return not Config.DropUnknownItems
    end

    local stores, plan, tables, seen = {}, {}, {}, {}
    local stats = {}
    for _, kind in ipairs(KINDS) do stats[kind] = { found = 0, write = 0, skipped = {}, examples = {} } end
    local current
    local function skip(s, reason)
        s.skipped[reason] = (s.skipped[reason] or 0) + 1
        detail(('[SKIP]  %-10s %s (%s): %s'):format(current.kind, current.id, current.from, reason))
    end

    for _, c in ipairs(containers) do
        current = c
        local s = stats[c.kind]
        s.found = s.found + 1
        if not Config.Convert[CONVERT_KEY[c.kind]] then skip(s, 'turned off in Config.Convert')
        elseif c.kind == 'player' and samePlayers then skip(s, 'already in the right format')
        elseif #c.items == 0 then skip(s, 'empty')
        else
            if stores[c.kind] == nil then
                local store, err = makeStore(targetDef(to, c.kind), c.kind, fw)
                if not store then warn('Target %s: %s', c.kind, err) end
                stores[c.kind] = store or false
            end
            local store = stores[c.kind]
            if not store then skip(s, 'no target storage')
            else
                local target, reason = store.locate(c)
                if not target then skip(s, reason)
                elseif seen[store.label .. '\0' .. target.key] then skip(s, 'another inventory already maps to the same target')
                -- Converting in place (same column, e.g. qb -> ox players) always rewrites the row.
                elseif c.from ~= store.label and target.existing and hasItems(target.existing) and not Config.Overwrite then
                    skip(s, 'target already has items')
                else
                    seen[store.label .. '\0' .. target.key] = true
                    local json = Items.Encode(c.items, to.format, keep)
                    plan[#plan + 1] = { query = target.query, values = target.values(json) }
                    tables[store.table] = true
                    s.write = s.write + 1
                    detail(('[WRITE] %-10s %s (%s) -> %s%s\n        %s'):format(c.kind, c.id, c.from, target.describe,
                        target.existing and hasItems(target.existing) and ' [replaced existing items]' or '', itemList(c.items, to.format)))
                    if #s.examples < 3 then s.examples[#s.examples + 1] = ('%s `%s` -> %s'):format(c.from, c.id, target.describe) end
                end
            end
        end
    end

    for _, kind in ipairs(KINDS) do
        local s = stats[kind]
        if s.found > 0 then
            local skipped = {}
            for reason, count in pairs(s.skipped) do skipped[#skipped + 1] = ('%d %s'):format(count, reason) end
            log('^5%s^7: %d found, ^2%d to write^7%s', CONVERT_KEY[kind], s.found, s.write,
                #skipped > 0 and (', skipped: ' .. table.concat(skipped, ', ')) or '')
            for _, example in ipairs(s.examples) do log('    e.g. %s', example) end
        end
    end

    if next(unknown) then
        local list = {}
        for name, count in pairs(unknown) do list[#list + 1] = ('%s (%d)'):format(name, count) end
        table.sort(list)
        warn('Items not in your %s item list%s: %s', to.label,
            Config.DropUnknownItems and ' (left out)' or ' (kept - add them or use Config.ItemRenames)', table.concat(list, ', '))
    end

    if #plan == 0 then return log('Nothing to write.') end
    if not confirm then
        return log('Preview only, nothing was written. Run ^5%s confirm^7 to write %d inventories.', Config.Command, #plan)
    end

    if Config.Backup then
        local stamp = os.date('%Y%m%d_%H%M%S')
        for tableName in pairs(tables) do
            local backup = ('%s_bak_%s'):format(tableName, stamp)
            local ok, err = pcall(MySQL.query.await, ('CREATE TABLE %s AS SELECT * FROM %s'):format(quote(backup), quote(tableName)))
            local exists = ok and MySQL.scalar.await(
                'SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', { backup })
            if not exists then return warn('Backup of %s failed (%s), nothing was written', tableName, tostring(err or 'see oxmysql error')) end
            log('Backed up ^5%s^7 to ^5%s^7', tableName, backup)
        end
    end

    local done, chunkSize = 0, 250
    for i = 1, #plan, chunkSize do
        local chunk = {}
        for j = i, math.min(i + chunkSize - 1, #plan) do chunk[#chunk + 1] = plan[j] end
        if not MySQL.transaction.await(chunk) then
            return warn('Writing failed after %d of %d inventories. Restore from the backup tables if needed.', done, #plan)
        end
        done = done + #chunk
    end
    log('^2Done^7: wrote %d inventories. Restart the server with %s running.', done, to.label)
end

RegisterCommand(Config.Command or 'convertinventory', function(source, args)
    if source ~= 0 then return end -- console only
    if running then return warn('A conversion is already running') end
    running = true
    local confirm = args[1] == 'confirm'
    report = { summary = {}, details = {} }
    local ok, err = pcall(convert, confirm)
    if not ok then warn('Stopped: %s', tostring(err)) end
    saveReport(confirm and 'convert' or 'preview')
    report = nil
    running = false
    columnCache = {}
end, true)
