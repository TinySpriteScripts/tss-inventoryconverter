-- Reads items stored by any inventory and writes them in ox or qb format.
Items = {}

local function looksLikeItem(value)
    return type(value) == 'table' and type(value.name) == 'string'
end

local function looksLikeItemList(value)
    if type(value) ~= 'table' then return false end
    local empty = true
    for _, entry in pairs(value) do
        empty = false
        if not looksLikeItem(entry) then return false end
    end
    return not empty
end

local function isEmptyTable(value)
    return type(value) == 'table' and next(value) == nil
end

-- Finds the item list inside decoded data: a list/map of items, or an object wrapping one.
local function findItemList(value, depth)
    depth = depth or 0
    if depth > 3 or type(value) ~= 'table' then return nil end
    if looksLikeItemList(value) or isEmptyTable(value) then return value end
    for _, key in ipairs({ 'items', 'inventory', 'data', 'slots', 'content' }) do
        local found = findItemList(value[key], depth + 1)
        if found then return found end
    end
    return nil
end

--- Decodes stored inventory data.
---@return table? decoded The whole decoded value (used for ak47 `type` lookups)
---@return table? items Normalized items { name, count, slot, metadata }
---@return string? err
function Items.Decode(raw)
    if raw == nil or raw == '' then return {}, {}, nil end
    local decoded = raw
    -- Some inventories store JSON inside a JSON string.
    for _ = 1, 2 do
        if type(decoded) ~= 'string' then break end
        local ok, result = pcall(json.decode, decoded)
        if not ok then return nil, nil, 'invalid JSON' end
        decoded = result
    end
    if decoded == nil then return {}, {}, nil end
    if type(decoded) ~= 'table' then return nil, nil, 'not an item list' end

    local list = findItemList(decoded)
    if not list then return decoded, nil, 'no item list found' end

    local items, used = {}, {}
    for key, entry in pairs(list) do
        local count = tonumber(entry.count or entry.amount or entry.quantity) or 1
        if count > 0 then
            local metadata = entry.metadata or entry.info
            if type(metadata) ~= 'table' then metadata = {} end
            local slot = tonumber(entry.slot) or tonumber(key)
            if slot and used[slot] then slot = nil end
            if slot then used[slot] = true end
            items[#items + 1] = { name = entry.name, count = math.floor(count), slot = slot, metadata = metadata }
        end
    end

    -- Items without (or with clashing) slots go in the first free slots.
    local nextSlot = 1
    for _, item in ipairs(items) do
        if not item.slot then
            while used[nextSlot] do nextSlot = nextSlot + 1 end
            item.slot, used[nextSlot] = nextSlot, true
        end
    end
    table.sort(items, function(a, b) return a.slot < b.slot end)
    return decoded, items, nil
end

local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end

local function isWeapon(name)
    return name:lower():sub(1, 7) == 'weapon_'
end

--- Applies renames and the weapon-name casing the target expects.
function Items.TargetName(name, format)
    name = Config.ItemRenames[name] or Config.ItemRenames[name:lower()] or name
    if isWeapon(name) then
        return format == 'ox' and name:upper() or name:lower()
    end
    return name
end

--- Encodes normalized items for the target format.
---@param items table Normalized items
---@param format 'ox'|'qb'
---@param keep? fun(name: string): boolean Return false to leave an item out
---@return string json
function Items.Encode(items, format, keep)
    local result = {}
    for _, item in ipairs(items) do
        local name = Items.TargetName(item.name, format)
        if not keep or keep(name) then
            local metadata = copy(item.metadata)
            if format == 'ox' then
                if isWeapon(name) then
                    metadata.serial = metadata.serial or metadata.serie
                    metadata.durability = metadata.durability or metadata.quality or 100
                    metadata.ammo = metadata.ammo or 0
                    metadata.components = metadata.components or metadata.attachments or {}
                    metadata.serie, metadata.quality, metadata.attachments = nil, nil, nil
                end
                result[#result + 1] = { slot = item.slot, name = name, count = item.count, metadata = next(metadata) and metadata or nil }
            else
                if isWeapon(name) then
                    metadata.serie = metadata.serie or metadata.serial
                    metadata.quality = metadata.quality or metadata.durability or 100
                    metadata.ammo = metadata.ammo or 0
                    metadata.attachments = metadata.attachments or metadata.components or {}
                    metadata.serial, metadata.durability, metadata.components = nil, nil, nil
                end
                result[#result + 1] = {
                    slot = item.slot, name = name, amount = item.count, info = metadata,
                    type = isWeapon(name) and 'weapon' or 'item',
                }
            end
        end
    end
    return json.encode(result)
end
