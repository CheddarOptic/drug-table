# eLcon-crafting

A fully configurable, server-authoritative crafting resource for FiveM with QBCore-friendly support and minimal framework coupling.

## Features

- `ox_inventory` ingredient and output handling
- `ox_target` crafting interaction (with optional `E` fallback)
- Configurable stations, props, zones, recipes, restrictions, cooldowns
- Multi-ingredient and multi-output recipes (with chance)
- Optional required tool item (not consumed)
- Optional skill check (ox_lib)
- Progress flow with ox_lib progress bar, plus fallback progress UI
- Admin in-game wizard (`/craftadmin`) for station + recipe management
- Ghost placement editor: rotate with scroll, `E` confirm, `Backspace` cancel
- JSON persistence (`stations.json`) with config defaults fallback
- Basic NUI crafting UI fallback if ox_lib menu is not used
- Blip support and optional webhook logging

## Resource Structure

- `fxmanifest.lua`
- `config.lua`
- `server/main.lua`
- `client/main.lua`
- `web/index.html`
- `web/style.css`
- `web/script.js`

## Requirements

- Required: `ox_inventory`
- Recommended: `ox_target`
- Optional but recommended: `ox_lib`
- Optional: `qb-core` (for permission/job/gang/police checks)

## Installation

1. Put folder in resources: `resources/[local]/eLcon-crafting`
2. Ensure dependencies in server cfg:
   - `ensure ox_inventory`
   - `ensure ox_target` (recommended)
   - `ensure ox_lib` (recommended)
   - `ensure qb-core` (if using QBCore checks)
3. Ensure this resource:
   - `ensure eLcon-crafting`

## Admin Permissions

ACE (txAdmin friendly):

```cfg
add_ace group.admin eLcon.crafting.admin allow
```

Optional QBCore permission check is also supported via `Config.Admin`.

## Usage

- Players interact at station target or press `E` fallback.
- Craft UI opens and displays recipes + available quantities.
- Server validates and processes all crafting logic.

Admin:

- Use `/craftadmin`
- Wizard flow:
  - Select/Create station
  - Manage recipes
  - Add ingredient/output rows
  - Save

## Data Persistence

- Saved file: `stations.json` inside resource
- If file does not exist or invalid, `Config.Stations` defaults are used

## Recipe Example

```lua
{
  id = 'lockpick_recipe',
  label = 'Lockpick',
  duration = 6000,
  canCraftMultiple = true,
  ingredients = {
    { item = 'metalscrap', amount = 3 },
    { item = 'plastic', amount = 2 },
  },
  outputs = {
    { item = 'lockpick', amount = 1, chance = 100 },
    { item = 'advancedlockpick', amount = 1, chance = 8 },
  },
  requiredTool = { item = 'screwdriverset' },
  minPolice = 1,
  cooldown = { player = 5000, station = 1500 }
}
```

## Notes

- All craft requests are server-authoritative.
- Client never dictates final outputs.
- Craft lock/rate limit and distance checks are applied server-side.
