-- TSS-InventoryConverter by [TinySprite](https://tinysprite.dev/) | [Discord](https://discord.gg/ZMFfC54FdJ)
-- ALWAYS back up your database before converting.
Config = {
    -- Inventory you are converting FROM and TO:
    --   "ox"      ox_inventory
    --   "qb"      qb-inventory 2.x     (`inventories` table)
    --   "qb_old"  qb-inventory 1.x     (`stashitems`, `trunkitems`, `gloveboxitems`)
    --   "ps"      ps-inventory         (same tables as qb_old)
    --   "lj"      lj-inventory         (same tables as qb_old)
    --   "qs"      qs-inventory         (`inventory_stash`, `inventory_trunk`, `inventory_glovebox`)
    --   "ak47"    ak47_inventory       (`ak47_inventory`) - FROM only
    --   "custom"  your own layout, see `Presets.custom` in server/presets.lua
    From = "ak47",
    To = "ox",

    Framework = "qb",           -- "qb", "qbox" or "esx" - decides the player and vehicle tables

    Command = "convertinventory", -- Console only. `convertinventory` previews, `convertinventory confirm` writes

    -- What to convert
    Convert = {
        players = true,         -- player inventories
        stashes = true,
        trunks = true,
        gloveboxes = true,
    },

    Overwrite = false,          -- false = leave targets that already contain items untouched
    Backup = true,              -- copy every table that will be written to `<table>_bak_<date>` first

    -- Rename items while converting, e.g. ammo names differ between inventories
    -- [old name] = "new name"
    ItemRenames = {
        -- ["pistol_ammo"] = "ammo-9",      -- qb -> ox
        -- ["rifle_ammo"] = "ammo-rifle",   -- qb -> ox
        -- ["money"] = "cash",
    },
    DropUnknownItems = false,   -- true = leave out items the running inventory doesn't know (tss_bridge item list)

    -- ox_inventory only: who owns a converted stash. Checked in order, first match wins.
    -- `pattern` is a Lua pattern run on the stash name; `owner` is a capture index (1, 2...) or a fixed string.
    -- No match = shared stash (owner "").
    OxStashOwners = {
        { pattern = "[:_](%u%u%u%d%d%d%d%d)$", owner = 1 },   -- ends in a QB citizenid: warehouse:ABC12345 / bag_ABC12345 -> owner ABC12345
    },

    -- From ox_inventory to another inventory: stashes that have an owner get this name
    OwnedStashName = "%s_%s",   -- (stash name, owner)
}
