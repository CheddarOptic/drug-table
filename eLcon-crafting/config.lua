Config = {}

Config.Debug = false
Config.Framework = 'qbcore' -- qbcore | auto

Config.UseOxTarget = true
Config.EnablePressEFallback = true
Config.UseOxLibCraftUI = true
Config.UseNuiFallback = true

Config.InteractionDistance = 2.2
Config.InteractionKey = 38 -- E

Config.Flags = {
    allowInVehicle = false,
    allowWhileDead = false,
    allowWhileCuffed = false,
}

Config.Admin = {
    acePermission = 'eLcon.crafting.admin',
    allowQBCorePermission = true,
    qbcorePermission = 'admin',
}

Config.PersistenceFile = 'stations.json'

Config.Blips = {
    enabled = true,
    shortRange = true,
}

Config.RateLimitMs = 750
Config.CraftDistanceTolerance = 3.0

Config.Webhook = {
    enabled = false,
    url = '',
    username = 'eLcon Crafting',
}

Config.PoliceJobs = {
    police = true,
    sheriff = true,
}

Config.Language = 'en'
Config.Locales = {
    en = {
        target_label = 'Open Crafting',
        no_permission = 'You do not have permission.',
        crafting_in_progress = 'You are already crafting.',
        invalid_recipe = 'Invalid recipe.',
        missing_items = 'Missing ingredients.',
        crafted_success = 'Craft complete.',
        craft_cancelled = 'Craft cancelled.',
        too_far = 'You moved too far away.',
        station_cooldown = 'Station is cooling down.',
        player_cooldown = 'You must wait before crafting again.',
        not_enough_police = 'Not enough police online.',
        restriction_fail = 'You cannot craft this recipe.',
        admin_menu = 'Crafting Admin',
        saved = 'Saved successfully.',
        deleted = 'Deleted successfully.',
        ui_no_ox_lib = 'ox_lib not found. Opening fallback NUI.',
        ui_no_fallback = 'No UI method available.',
    }
}

Config.Stations = {
    -- DO NOT EDIT BELOW THIS LINE unless you want to change factory defaults.
    -- Admin-created stations/recipes are saved in Config.PersistenceFile.
    {
        id = 'default_bench_1',
        label = 'Crafting Bench',
        title = 'Crafting Bench',
        model = 'gr_prop_gr_bench_02b',
        spawnProp = true,
        propFrozen = true,
        coords = { x = -593.15, y = -1614.58, z = 27.01, w = 178.56 },
        zone = {
            type = 'box',
            size = { x = 2.4, y = 1.8, z = 2.2 },
            offset = { x = 0.0, y = 0.0, z = 0.0 },
            rotation = 178.56,
            debug = false,
        },
        blip = {
            enabled = false,
            sprite = 566,
            color = 2,
            scale = 0.75,
            name = 'Crafting',
        },
        cooldown = {
            station = 0,
            player = 0,
        },
        recipes = {
            {
                id = 'bandage_recipe',
                label = 'Bandage',
                description = 'Basic medical wrap.',
                category = 'Medical',
                duration = 5000,
                canCraftMultiple = true,
                minPolice = 0,
                cooldown = {
                    player = 0,
                    station = 0,
                },
                requiredTool = {
                    item = 'weapon_hammer',
                    metadata = nil,
                },
                job = nil,
                gang = nil,
                grade = nil,
                animation = {
                    dict = 'amb@world_human_hammering@male@base',
                    clip = 'base',
                    flag = 49,
                },
                scenario = nil,
                ingredients = {
                    { item = 'cloth', amount = 2, metadata = nil },
                    { item = 'alcohol', amount = 1, metadata = nil },
                },
                outputs = {
                    { item = 'bandage', amount = 1, chance = 100, metadata = nil },
                    { item = 'painkillers', amount = 1, chance = 25, metadata = nil },
                },
            }
        }
    }
}
