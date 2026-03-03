local RESOURCE = GetCurrentResourceName()
local QBCore = nil

local Stations = {}
local ActiveCrafts = {}
local PlayerCooldowns = {}
local StationCooldowns = {}
local LastRequestAt = {}

local function dbg(...)
    if not Config.Debug then return end
    print(('[%s]'):format(RESOURCE), ...)
end

local function tr(key)
    local lang = Config.Locales[Config.Language] or Config.Locales.en
    return (lang and lang[key]) or key
end

local function deepCopy(tbl)
    if type(tbl) ~= 'table' then return tbl end
    local copy = {}
    for k, v in pairs(tbl) do
        copy[k] = deepCopy(v)
    end
    return copy
end

local function trim(value)
    if type(value) ~= 'string' then return value end
    return value:gsub('^%s+', ''):gsub('%s+$', '')
end

local function sanitizeId(value, fallback)
    value = trim(value or '')
    if value == '' then return fallback end
    value = value:gsub('[^%w_%-]', '_'):sub(1, 50)
    if value == '' then
        return fallback
    end
    return value
end

local function num(value, fallback)
    local n = tonumber(value)
    if not n then return fallback end
    return n
end

local function vec4table(coords)
    if type(coords) ~= 'table' then
        return { x = 0.0, y = 0.0, z = 0.0, w = 0.0 }
    end
    return {
        x = num(coords.x, 0.0),
        y = num(coords.y, 0.0),
        z = num(coords.z, 0.0),
        w = num(coords.w, 0.0),
    }
end

local function vec3table(coords)
    if type(coords) ~= 'table' then
        return { x = 0.0, y = 0.0, z = 0.0 }
    end
    return {
        x = num(coords.x, 0.0),
        y = num(coords.y, 0.0),
        z = num(coords.z, 0.0),
    }
end

local function sanitizeIngredient(input)
    if type(input) ~= 'table' then return nil end
    local item = sanitizeId(input.item, nil)
    local amount = math.max(1, math.floor(num(input.amount, 1)))
    if not item then return nil end

    local metadata = nil
    if type(input.metadata) == 'table' then
        metadata = input.metadata
    end

    return {
        item = item,
        amount = amount,
        metadata = metadata,
    }
end

local function sanitizeOutput(input)
    if type(input) ~= 'table' then return nil end
    local item = sanitizeId(input.item, nil)
    local amount = math.max(1, math.floor(num(input.amount, 1)))
    if not item then return nil end

    local chance = num(input.chance, 100)
    chance = math.max(0, math.min(100, chance))

    local metadata = nil
    if type(input.metadata) == 'table' then
        metadata = input.metadata
    end

    return {
        item = item,
        amount = amount,
        chance = chance,
        metadata = metadata,
    }
end

local function sanitizeRecipe(input, fallbackId)
    if type(input) ~= 'table' then return nil end

    local recipe = {
        id = sanitizeId(input.id, fallbackId),
        label = tostring(trim(input.label or 'Recipe')):sub(1, 64),
        description = tostring(trim(input.description or '')):sub(1, 255),
        category = tostring(trim(input.category or 'General')):sub(1, 32),
        duration = math.max(1000, math.floor(num(input.duration, 5000))),
        canCraftMultiple = input.canCraftMultiple == true,
        minPolice = math.max(0, math.floor(num(input.minPolice, 0))),
        cooldown = {
            player = math.max(0, math.floor(num(input.cooldown and input.cooldown.player, 0))),
            station = math.max(0, math.floor(num(input.cooldown and input.cooldown.station, 0))),
        },
        requiredTool = nil,
        job = input.job,
        gang = input.gang,
        grade = input.grade and math.floor(num(input.grade, 0)) or nil,
        animation = nil,
        scenario = input.scenario and tostring(input.scenario):sub(1, 64) or nil,
        skillCheck = input.skillCheck == true,
        ingredients = {},
        outputs = {},
    }

    if type(input.requiredTool) == 'table' then
        local toolItem = sanitizeId(input.requiredTool.item, nil)
        if toolItem then
            recipe.requiredTool = {
                item = toolItem,
                metadata = type(input.requiredTool.metadata) == 'table' and input.requiredTool.metadata or nil,
            }
        end
    end

    if type(input.animation) == 'table' then
        recipe.animation = {
            dict = tostring(input.animation.dict or ''):sub(1, 80),
            clip = tostring(input.animation.clip or ''):sub(1, 80),
            flag = math.floor(num(input.animation.flag, 49)),
        }
        if recipe.animation.dict == '' or recipe.animation.clip == '' then
            recipe.animation = nil
        end
    end

    if type(input.ingredients) == 'table' then
        for _, ingredient in ipairs(input.ingredients) do
            local clean = sanitizeIngredient(ingredient)
            if clean then recipe.ingredients[#recipe.ingredients + 1] = clean end
        end
    end

    if type(input.outputs) == 'table' then
        for _, output in ipairs(input.outputs) do
            local clean = sanitizeOutput(output)
            if clean then recipe.outputs[#recipe.outputs + 1] = clean end
        end
    end

    if #recipe.ingredients == 0 or #recipe.outputs == 0 then
        return nil
    end

    return recipe
end

local function sanitizeStation(input, fallbackId)
    if type(input) ~= 'table' then return nil end

    local station = {
        id = sanitizeId(input.id, fallbackId),
        label = tostring(trim(input.label or 'Crafting Station')):sub(1, 64),
        title = tostring(trim(input.title or input.label or 'Crafting')):sub(1, 64),
        model = tostring(trim(input.model or 'prop_tool_bench02')):sub(1, 64),
        spawnProp = input.spawnProp == true,
        propFrozen = input.propFrozen ~= false,
        coords = vec4table(input.coords),
        zone = {
            type = 'box',
            size = vec3table(input.zone and input.zone.size),
            offset = vec3table(input.zone and input.zone.offset),
            rotation = num(input.zone and input.zone.rotation, input.coords and input.coords.w or 0.0),
            debug = input.zone and input.zone.debug == true or false,
        },
        blip = {
            enabled = input.blip and input.blip.enabled == true or false,
            sprite = math.floor(num(input.blip and input.blip.sprite, 566)),
            color = math.floor(num(input.blip and input.blip.color, 2)),
            scale = num(input.blip and input.blip.scale, 0.75),
            name = tostring(input.blip and input.blip.name or input.label or 'Crafting'):sub(1, 64),
        },
        cooldown = {
            station = math.max(0, math.floor(num(input.cooldown and input.cooldown.station, 0))),
            player = math.max(0, math.floor(num(input.cooldown and input.cooldown.player, 0))),
        },
        recipes = {},
    }

    station.zone.size.x = math.max(0.4, station.zone.size.x)
    station.zone.size.y = math.max(0.4, station.zone.size.y)
    station.zone.size.z = math.max(0.4, station.zone.size.z)

    if type(input.recipes) == 'table' then
        for i, recipe in ipairs(input.recipes) do
            local cleanRecipe = sanitizeRecipe(recipe, ('recipe_%s_%s'):format(station.id, i))
            if cleanRecipe then
                station.recipes[#station.recipes + 1] = cleanRecipe
            end
        end
    end

    return station
end

local function sanitizeAllStations(stationsInput)
    local out = {}
    if type(stationsInput) ~= 'table' then
        return out
    end

    for i, station in ipairs(stationsInput) do
        local cleanStation = sanitizeStation(station, ('station_%s'):format(i))
        if cleanStation then
            out[#out + 1] = cleanStation
        end
    end

    return out
end

local function getQBCore()
    if QBCore then return QBCore end
    if Config.Framework ~= 'qbcore' and Config.Framework ~= 'auto' then return nil end

    if GetResourceState('qb-core') == 'started' then
        local ok, obj = pcall(function() return exports['qb-core']:GetCoreObject() end)
        if ok and obj then
            QBCore = obj
        end
    end

    return QBCore
end

local function getPlayerObject(source)
    local core = getQBCore()
    if not core then return nil end
    return core.Functions.GetPlayer(source)
end

local function getPlayerInfo(source)
    local player = getPlayerObject(source)
    if not player then
        return {
            job = nil,
            jobGrade = 0,
            gang = nil,
            gangGrade = 0,
            citizenid = nil,
        }
    end

    local data = player.PlayerData or {}
    local job = data.job or {}
    local gang = data.gang or {}

    return {
        job = job.name,
        jobGrade = (job.grade and (job.grade.level or job.grade)) or 0,
        gang = gang.name,
        gangGrade = (gang.grade and (gang.grade.level or gang.grade)) or 0,
        citizenid = data.citizenid,
    }
end

local function hasAcePermission(source)
    return IsPlayerAceAllowed(source, Config.Admin.acePermission)
end

local function hasQBCorePermission(source)
    if not Config.Admin.allowQBCorePermission then return false end

    local core = getQBCore()
    if not core or not core.Functions or not core.Functions.HasPermission then
        return false
    end

    local ok, result = pcall(function()
        return core.Functions.HasPermission(source, Config.Admin.qbcorePermission)
    end)

    return ok and result == true
end

local function isAdmin(source)
    return hasAcePermission(source) or hasQBCorePermission(source)
end

local function logToDiscord(message)
    if not Config.Webhook.enabled or Config.Webhook.url == '' then return end
    PerformHttpRequest(Config.Webhook.url, function() end, 'POST', json.encode({
        username = Config.Webhook.username,
        content = message,
    }), { ['Content-Type'] = 'application/json' })
end

local function getStationById(stationId)
    for _, station in ipairs(Stations) do
        if station.id == stationId then
            return station
        end
    end
end

local function getRecipeById(station, recipeId)
    if not station or not station.recipes then return nil end
    for _, recipe in ipairs(station.recipes) do
        if recipe.id == recipeId then
            return recipe
        end
    end
end

local function getItemCount(source, item, metadata)
    if GetResourceState('ox_inventory') ~= 'started' then return 0 end
    local ok, result = pcall(function()
        return exports.ox_inventory:Search(source, 'count', item, metadata)
    end)
    if not ok then
        return 0
    end
    return tonumber(result) or 0
end

local function hasItem(source, item, amount, metadata)
    return getItemCount(source, item, metadata) >= amount
end

local function canCarry(source, item, amount, metadata)
    if GetResourceState('ox_inventory') ~= 'started' then return false end
    local ok, result = pcall(function()
        return exports.ox_inventory:CanCarryItem(source, item, amount, metadata)
    end)
    if not ok then return false end
    return result == true
end

local function removeItem(source, item, amount, metadata)
    local ok, result = pcall(function()
        return exports.ox_inventory:RemoveItem(source, item, amount, metadata)
    end)
    return ok and result == true
end

local function addItem(source, item, amount, metadata)
    local ok, result = pcall(function()
        return exports.ox_inventory:AddItem(source, item, amount, metadata)
    end)
    return ok and result == true
end

local function matchGroupRestriction(playerValue, requirement)
    if not requirement then return true end

    if type(requirement) == 'string' then
        return playerValue == requirement
    end

    if type(requirement) == 'table' then
        if requirement.name then
            return playerValue == requirement.name
        end

        for _, allowed in ipairs(requirement) do
            if playerValue == allowed then
                return true
            end
        end
    end

    return false
end

local function onlinePoliceCount()
    local count = 0
    local players = GetPlayers()
    for _, src in ipairs(players) do
        local info = getPlayerInfo(tonumber(src))
        if info.job and Config.PoliceJobs[info.job] then
            count = count + 1
        end
    end
    return count
end

local function isOnCooldown(source, station, recipe)
    local now = GetGameTimer()
    local recipePlayerCd = (recipe.cooldown and recipe.cooldown.player) or 0
    local recipeStationCd = (recipe.cooldown and recipe.cooldown.station) or 0
    local stationPlayerCd = (station.cooldown and station.cooldown.player) or 0
    local stationStationCd = (station.cooldown and station.cooldown.station) or 0

    local playerCd = math.max(recipePlayerCd, stationPlayerCd, 0)
    local stationCd = math.max(recipeStationCd, stationStationCd, 0)

    if playerCd > 0 then
        local key = ('%s:%s:%s'):format(source, station.id, recipe.id)
        local untilAt = PlayerCooldowns[key]
        if untilAt and now < untilAt then
            return true, 'player'
        end
    end

    if stationCd > 0 then
        local key = ('%s:%s'):format(station.id, recipe.id)
        local untilAt = StationCooldowns[key]
        if untilAt and now < untilAt then
            return true, 'station'
        end
    end

    return false
end

local function applyCooldown(source, station, recipe)
    local now = GetGameTimer()

    local playerCd = math.max((recipe.cooldown and recipe.cooldown.player) or 0, (station.cooldown and station.cooldown.player) or 0)
    local stationCd = math.max((recipe.cooldown and recipe.cooldown.station) or 0, (station.cooldown and station.cooldown.station) or 0)

    if playerCd > 0 then
        PlayerCooldowns[('%s:%s:%s'):format(source, station.id, recipe.id)] = now + playerCd
    end

    if stationCd > 0 then
        StationCooldowns[('%s:%s'):format(station.id, recipe.id)] = now + stationCd
    end
end

local function canCraftByState(source)
    local ped = GetPlayerPed(source)
    if ped == 0 then return false, 'Invalid ped.' end

    if not Config.Flags.allowInVehicle then
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle and vehicle ~= 0 then
            return false, 'Cannot craft in vehicle.'
        end
    end

    if not Config.Flags.allowWhileDead and IsEntityDead(ped) then
        return false, 'Cannot craft while dead.'
    end

    if not Config.Flags.allowWhileCuffed then
        local state = Player(source) and Player(source).state
        if state and (state.isHandcuffed or state.cuffed) then
            return false, 'Cannot craft while cuffed.'
        end
    end

    return true
end

local function distanceToStation(source, station)
    local ped = GetPlayerPed(source)
    if ped == 0 then return 9999.0 end

    local coords = GetEntityCoords(ped)
    local dx = coords.x - station.coords.x
    local dy = coords.y - station.coords.y
    local dz = coords.z - station.coords.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function canCraftRecipe(source, station, recipe, quantity)
    quantity = math.max(1, math.floor(quantity))
    local info = getPlayerInfo(source)
    local canByState, stateReason = canCraftByState(source)
    if not canByState then
        return false, stateReason
    end

    if recipe.job and not matchGroupRestriction(info.job, recipe.job) then
        return false, tr('restriction_fail')
    end

    if recipe.gang and not matchGroupRestriction(info.gang, recipe.gang) then
        return false, tr('restriction_fail')
    end

    local gradeReq = recipe.grade
    if gradeReq and info.jobGrade < gradeReq then
        return false, tr('restriction_fail')
    end

    local minPolice = recipe.minPolice or 0
    if minPolice > 0 and onlinePoliceCount() < minPolice then
        return false, tr('not_enough_police')
    end

    local onCd, cdType = isOnCooldown(source, station, recipe)
    if onCd then
        if cdType == 'station' then
            return false, tr('station_cooldown')
        end
        return false, tr('player_cooldown')
    end

    if recipe.requiredTool and recipe.requiredTool.item then
        if not hasItem(source, recipe.requiredTool.item, 1, recipe.requiredTool.metadata) then
            return false, ('Missing tool: %s'):format(recipe.requiredTool.item)
        end
    end

    for _, ingredient in ipairs(recipe.ingredients) do
        local need = ingredient.amount * quantity
        if not hasItem(source, ingredient.item, need, ingredient.metadata) then
            return false, tr('missing_items')
        end
    end

    -- Ensure inventory can take guaranteed outputs.
    for _, output in ipairs(recipe.outputs) do
        if (output.chance or 100) >= 100 then
            local amount = output.amount * quantity
            if not canCarry(source, output.item, amount, output.metadata) then
                return false, ('Cannot carry %s x%s'):format(output.item, amount)
            end
        end
    end

    return true
end

local function getRecipeAvailability(source, station, recipe)
    local options = { 1 }
    if recipe.canCraftMultiple then
        options[#options + 1] = 5
        options[#options + 1] = 10
    end

    local availability = {}
    for _, qty in ipairs(options) do
        local ok, reason = canCraftRecipe(source, station, recipe, qty)
        availability[tostring(qty)] = {
            canCraft = ok,
            reason = ok and nil or reason,
        }
    end

    return availability
end

local function getStationViewData(source, stationId)
    local station = getStationById(stationId)
    if not station then return nil end

    local recipes = {}
    for _, recipe in ipairs(station.recipes or {}) do
        recipes[#recipes + 1] = {
            id = recipe.id,
            label = recipe.label,
            description = recipe.description,
            category = recipe.category,
            duration = recipe.duration,
            canCraftMultiple = recipe.canCraftMultiple,
            minPolice = recipe.minPolice,
            skillCheck = recipe.skillCheck == true,
            requiredTool = recipe.requiredTool,
            ingredients = deepCopy(recipe.ingredients),
            outputs = deepCopy(recipe.outputs),
            availability = getRecipeAvailability(source, station, recipe),
        }
    end

    return {
        station = {
            id = station.id,
            label = station.label,
            title = station.title,
            coords = station.coords,
        },
        recipes = recipes,
    }
end

local function saveStations()
    local encoded = json.encode(Stations)
    if not encoded then
        print(('[%s] Failed to encode station JSON.'):format(RESOURCE))
        return false
    end

    local ok = SaveResourceFile(RESOURCE, Config.PersistenceFile, encoded, -1)
    if not ok then
        print(('[%s] Failed to save %s'):format(RESOURCE, Config.PersistenceFile))
        return false
    end

    dbg('Saved stations to', Config.PersistenceFile)
    return true
end

local function loadStations()
    local raw = LoadResourceFile(RESOURCE, Config.PersistenceFile)
    if raw and raw ~= '' then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then
            Stations = sanitizeAllStations(decoded)
            dbg('Loaded stations from JSON:', #Stations)
            return
        end
    end

    Stations = sanitizeAllStations(Config.Stations or {})
    dbg('Loaded stations from config.lua:', #Stations)
end

local function syncStations(target)
    local payload = deepCopy(Stations)
    if target then
        TriggerClientEvent('elcon-crafting:client:syncStations', target, payload)
    else
        TriggerClientEvent('elcon-crafting:client:syncStations', -1, payload)
    end
end

local function notify(source, msg, nType)
    TriggerClientEvent('elcon-crafting:client:notify', source, msg, nType or 'inform')
end

local function makeToken(source)
    return ('%s:%s:%s'):format(source, math.random(10000, 99999), GetGameTimer())
end

local function rateLimited(source)
    local now = GetGameTimer()
    local last = LastRequestAt[source] or 0
    if now - last < Config.RateLimitMs then
        return true
    end
    LastRequestAt[source] = now
    return false
end

local function finalizeCraft(source, active)
    local station = getStationById(active.stationId)
    if not station then
        return false, 'Station missing'
    end

    local recipe = getRecipeById(station, active.recipeId)
    if not recipe then
        return false, 'Recipe missing'
    end

    local distance = distanceToStation(source, station)
    if distance > (Config.CraftDistanceTolerance + 0.5) then
        return false, tr('too_far')
    end

    local ok, reason = canCraftRecipe(source, station, recipe, active.quantity)
    if not ok then
        return false, reason
    end

    -- Remove ingredients first.
    for _, ingredient in ipairs(recipe.ingredients) do
        local amount = ingredient.amount * active.quantity
        local removed = removeItem(source, ingredient.item, amount, ingredient.metadata)
        if not removed then
            return false, ('Failed removing %s x%s'):format(ingredient.item, amount)
        end
    end

    local rewarded = {}

    for _, output in ipairs(recipe.outputs) do
        local total = 0
        local chance = output.chance or 100

        for _ = 1, active.quantity do
            if math.random(1, 100) <= chance then
                total = total + output.amount
            end
        end

        if total > 0 then
            if addItem(source, output.item, total, output.metadata) then
                rewarded[#rewarded + 1] = ('%s x%s'):format(output.item, total)
            else
                print(('[%s] Could not give output %s x%s to %s'):format(RESOURCE, output.item, total, source))
            end
        end
    end

    applyCooldown(source, station, recipe)

    local msg = ('[%s] %s crafted %s x%s at %s'):format(
        RESOURCE,
        GetPlayerName(source) or ('src:%s'):format(source),
        recipe.id,
        active.quantity,
        station.id
    )

    print(msg)
    if #rewarded > 0 then
        print(('[%s] Rewards: %s'):format(RESOURCE, table.concat(rewarded, ', ')))
    end
    logToDiscord(msg)

    return true
end

local function ensureDataFolder()
    local existing = LoadResourceFile(RESOURCE, Config.PersistenceFile)
    if existing ~= nil then return end
    saveStations()
end

AddEventHandler('onResourceStart', function(res)
    if res ~= RESOURCE then return end
    math.randomseed(os.time())
    loadStations()
    ensureDataFolder()
    Wait(250)
    syncStations()
end)

AddEventHandler('playerDropped', function()
    local source = source
    ActiveCrafts[source] = nil
    LastRequestAt[source] = nil
end)

RegisterNetEvent('elcon-crafting:server:requestData', function()
    syncStations(source)
end)

RegisterNetEvent('elcon-crafting:server:requestCraft', function(stationId, recipeId, quantity)
    local source = source

    if type(stationId) ~= 'string' or type(recipeId) ~= 'string' then return end
    quantity = math.floor(num(quantity, 1))
    if quantity < 1 or quantity > 10 then quantity = 1 end
    if quantity ~= 1 and quantity ~= 5 and quantity ~= 10 then quantity = 1 end

    if ActiveCrafts[source] then
        notify(source, tr('crafting_in_progress'), 'error')
        return
    end

    if rateLimited(source) then
        notify(source, 'Too many requests.', 'error')
        return
    end

    local station = getStationById(stationId)
    if not station then
        notify(source, tr('invalid_recipe'), 'error')
        return
    end

    local recipe = getRecipeById(station, recipeId)
    if not recipe then
        notify(source, tr('invalid_recipe'), 'error')
        return
    end

    if quantity > 1 and not recipe.canCraftMultiple then
        quantity = 1
    end

    local distance = distanceToStation(source, station)
    if distance > (Config.CraftDistanceTolerance + 1.5) then
        notify(source, tr('too_far'), 'error')
        return
    end

    local ok, reason = canCraftRecipe(source, station, recipe, quantity)
    if not ok then
        notify(source, reason or tr('restriction_fail'), 'error')
        return
    end

    local token = makeToken(source)
    ActiveCrafts[source] = {
        token = token,
        stationId = stationId,
        recipeId = recipeId,
        quantity = quantity,
        startedAt = GetGameTimer(),
    }

    TriggerClientEvent('elcon-crafting:client:startProgress', source, {
        token = token,
        stationId = stationId,
        recipeId = recipeId,
        quantity = quantity,
        duration = recipe.duration,
        animation = recipe.animation,
        scenario = recipe.scenario,
        stationCoords = station.coords,
        maxDistance = Config.CraftDistanceTolerance,
        skillCheck = recipe.skillCheck == true,
    })
end)

RegisterNetEvent('elcon-crafting:server:finishCraft', function(token, wasCancelled, reason)
    local source = source
    local active = ActiveCrafts[source]

    if not active then return end
    if type(token) ~= 'string' or token ~= active.token then
        ActiveCrafts[source] = nil
        return
    end

    if wasCancelled then
        ActiveCrafts[source] = nil
        notify(source, reason or tr('craft_cancelled'), 'error')
        return
    end

    local ok, err = finalizeCraft(source, active)
    ActiveCrafts[source] = nil

    if not ok then
        notify(source, err or tr('missing_items'), 'error')
        return
    end

    notify(source, tr('crafted_success'), 'success')
end)

RegisterNetEvent('elcon-crafting:server:callback', function(cbId, action, payload)
    local source = source
    if type(cbId) ~= 'number' or type(action) ~= 'string' then return end

    local result = nil

    if action == 'isAdmin' then
        result = isAdmin(source)
    elseif action == 'getStationView' then
        if type(payload) == 'table' and type(payload.stationId) == 'string' then
            result = getStationViewData(source, payload.stationId)
        end
    elseif action == 'getStations' then
        result = deepCopy(Stations)
    end

    TriggerClientEvent('elcon-crafting:client:callbackResponse', source, cbId, result)
end)

RegisterNetEvent('elcon-crafting:server:admin:saveStation', function(data)
    local source = source
    if not isAdmin(source) then
        notify(source, tr('no_permission'), 'error')
        return
    end

    local clean = sanitizeStation(data, ('station_%s'):format(#Stations + 1))
    if not clean then
        notify(source, 'Invalid station data.', 'error')
        return
    end

    local replaced = false
    for idx, station in ipairs(Stations) do
        if station.id == clean.id then
            clean.recipes = Stations[idx].recipes or {}
            Stations[idx] = clean
            replaced = true
            break
        end
    end

    if not replaced then
        Stations[#Stations + 1] = clean
    end

    saveStations()
    syncStations()
    notify(source, tr('saved'), 'success')
end)

RegisterNetEvent('elcon-crafting:server:admin:deleteStation', function(stationId)
    local source = source
    if not isAdmin(source) then
        notify(source, tr('no_permission'), 'error')
        return
    end

    if type(stationId) ~= 'string' then return end

    local new = {}
    local removed = false
    for _, station in ipairs(Stations) do
        if station.id ~= stationId then
            new[#new + 1] = station
        else
            removed = true
        end
    end

    Stations = new

    if removed then
        saveStations()
        syncStations()
        notify(source, tr('deleted'), 'success')
    else
        notify(source, 'Station not found.', 'error')
    end
end)

RegisterNetEvent('elcon-crafting:server:admin:saveRecipe', function(stationId, recipeData)
    local source = source
    if not isAdmin(source) then
        notify(source, tr('no_permission'), 'error')
        return
    end

    if type(stationId) ~= 'string' or type(recipeData) ~= 'table' then return end

    local station = getStationById(stationId)
    if not station then
        notify(source, 'Station not found.', 'error')
        return
    end

    local clean = sanitizeRecipe(recipeData, ('recipe_%s_%s'):format(stationId, #station.recipes + 1))
    if not clean then
        notify(source, 'Invalid recipe data.', 'error')
        return
    end

    local replaced = false
    for i, recipe in ipairs(station.recipes) do
        if recipe.id == clean.id then
            station.recipes[i] = clean
            replaced = true
            break
        end
    end

    if not replaced then
        station.recipes[#station.recipes + 1] = clean
    end

    saveStations()
    syncStations()
    notify(source, tr('saved'), 'success')
end)

RegisterNetEvent('elcon-crafting:server:admin:deleteRecipe', function(stationId, recipeId)
    local source = source
    if not isAdmin(source) then
        notify(source, tr('no_permission'), 'error')
        return
    end

    local station = getStationById(stationId)
    if not station then
        notify(source, 'Station not found.', 'error')
        return
    end

    local new = {}
    local removed = false
    for _, recipe in ipairs(station.recipes) do
        if recipe.id ~= recipeId then
            new[#new + 1] = recipe
        else
            removed = true
        end
    end

    station.recipes = new

    if removed then
        saveStations()
        syncStations()
        notify(source, tr('deleted'), 'success')
    else
        notify(source, 'Recipe not found.', 'error')
    end
end)
