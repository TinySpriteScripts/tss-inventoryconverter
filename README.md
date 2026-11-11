# |‾‾‾|/‾‾‾\ /‾‾‾\
#   |  \__‾‾\\__‾‾\
#   |   |___/ |___/
# tinysprite.dev

# [`tss-inventoryconverter`] by [TinySprite](https://tinysprite.dev/) | [Discord](https://discord.gg/ZMFfC54FdJ)

Switching inventory? Move every player inventory, stash, trunk and glovebox from your old inventory to your new one with one console command.

> ## ⚠️ Read this first
> **This resource has not been tested with every inventory.** Each inventory stores its data differently, and some don't publish their database layout.
>
> **Please make a full backup of your database before you attempt to use this resource.** The script makes its own backup tables before writing, but they are not a replacement for a full database backup.
>
> Always run the preview first and check its log before converting.

---

## 📦 Dependencies
- [tss_bridge](https://github.com/TinySpriteScripts/tss_bridge) (**required**)
- [oxmysql](https://github.com/overextended/oxmysql)

---

## 🔁 Supported inventories

| Config name | Inventory | Convert from | Convert to |
| --- | --- | :---: | :---: |
| `ox` | ox_inventory | ✅ | ✅ |
| `qb` | qb-inventory 2.x (`inventories` table) | ✅ | ✅ |
| `qb_old` | qb-inventory 1.x (`stashitems`, `trunkitems`, `gloveboxitems`) | ✅ | ✅ |
| `ps` | ps-inventory | ✅ | ✅ |
| `lj` | lj-inventory | ✅ | ✅ |
| `qs` | qs-inventory | ✅ | ✅ |
| `ak47` | ak47_inventory | ✅ | ❌ (ak47 imports from ox itself) |
| `custom` | Anything else: describe its tables in `server/presets.lua` | ✅ | ✅ |

Frameworks: QBCore, Qbox and ESX (`Config.Framework`).

qs-inventory and ak47_inventory don't publish their database columns, so the script looks up the column names in your database. Always run the preview first and check the examples it prints.

---

## 🧰 How to use

1. Stop the server and **back up your database**.
2. Put `tss-inventoryconverter` in your resources and `ensure` it after `oxmysql` and `tss_bridge`.
3. Make sure the **new** inventory's SQL is imported, so its tables exist.
4. Set `Config.From`, `Config.To` and `Config.Framework` in `config.lua`.
5. Start the server, ideally with the **new** inventory running. The script then checks every item name against its item list.
6. In the server console run:
   ```
   convertinventory
   ```
   This is a **preview**: it reads everything and shows what would be written, with examples, without changing anything.
7. Check the output and the log file it saves (see [Logs](#-logs)): counts, skipped reasons, where each inventory goes and unknown items. Adjust the config if needed and preview again.
8. When it looks right, run:
   ```
   convertinventory confirm
   ```
   Every table that will be written is first copied to `<table>_bak_<date>_<time>`. Then the inventories are written.
9. Restart the server with the new inventory. Keep the `logs` folder, then remove `tss-inventoryconverter`.

---

## 📝 Logs

Every run saves a log file in the resource's `logs` folder. The console prints the full path.

- `preview_<date>_<time>.log`: what **would** happen. Nothing was written.
- `convert_<date>_<time>.log`: what was converted.

Each log contains:
- **Header**: date, from/to inventory, framework and the `Overwrite`, `Backup` and `DropUnknownItems` settings.
- **Summary**: the same as the console, including totals per type, skipped reasons, backup table names, unknown items and the final result.
- **Details**: one line per inventory:
  - `[WRITE]`: converted. Shows where it came from and where it went, and lists every item and amount by its new name (renamed items also show the old name).
  - `[SKIP]`: left untouched, with the reason (empty, target already has items, no owned vehicle with that plate, ...).
  - `[ERROR]`: could not be read, so it was left untouched.

```
[WRITE] trunk      ABC12345 (ak47_inventory.data) -> player_vehicles.trunk (plate ABC12345)
        water x3, WEAPON_PISTOL x1 (was weapon_pistol), ammo-9 x50 (was pistol_ammo)
[SKIP]  glovebox   XYZ98765 (ak47_inventory.data): no owned vehicle with that plate
```

Keep these logs. They show exactly what each player had, which helps if anyone reports missing items after the switch.

---

## ⚙️ Config

| Option | What it does |
| --- | --- |
| `From` / `To` | Inventories to convert from and to (see the table above). |
| `Framework` | `qb`, `qbox` or `esx`. Decides the player table (`players` / `users`) and vehicle table (`player_vehicles` / `owned_vehicles`). |
| `Convert` | Turn players, stashes, trunks or gloveboxes on or off. |
| `Overwrite` | `false` leaves targets that already contain items untouched. |
| `Backup` | Copy each target table before writing. |
| `ItemRenames` | Rename items while converting, e.g. ammo: `["pistol_ammo"] = "ammo-9"`. Weapon names get the right case automatically (`WEAPON_PISTOL` for ox, `weapon_pistol` for others). |
| `DropUnknownItems` | Leave out items your new inventory doesn't know. |
| `OxStashOwners` | Converting to ox: which stashes belong to a player. The default gives stashes ending in a citizenid (`bag_ABC12345`) that player as owner. |
| `OwnedStashName` | Converting from ox: the name given to stashes that have an owner. |

### What gets converted
- **Items**: the name, amount, slot and metadata/info. Weapon serials, durability/quality, ammo and attachments are moved to the field names the new inventory uses.
- **Trunks and gloveboxes**: only for plates that exist in your vehicle table (when converting to ox).
- **Players**: only for characters that exist. Inventories that share the same column and format (e.g. qb → qs) are already compatible and are skipped.
- **Not converted**: money accounts, shops, clothing and other inventory-specific extras.

### Another inventory?
Copy `Presets.custom` in `server/presets.lua`, fill in its tables and columns, and set `Config.From` or `Config.To` to `"custom"`. Or ask in our Discord and we'll add it.

---

## 📜 History
- v1.0.0 - TSS-Convert ak47-ox: ak47_inventory → ox_inventory
- v2.0.0 - Renamed to TSS-InventoryConverter: any supported inventory to any other, preview before writing, automatic backups, item renames and weapon metadata conversion

---

## 🔧 Support
Need help? Join our Discord: [Join Support Server](https://discord.gg/ZMFfC54FdJ)

**© TinySprite** — Quality resources built for FiveM servers.
