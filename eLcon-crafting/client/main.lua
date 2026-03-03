local RESOURCE = GetCurrentResourceName()

local Stations = {}
local StationIndex = {}

local SpawnedProps = {}
local TargetZones = {}
local Blips = {}

local HasOxTarget = false
local HasOxLib = false

local NuiOpen = false
local IsCrafting = false
local ActiveCraftToken = nil

local CallbackId = 0
local PendingCallbacks = {}

local Editor = {
    active = false,
}

local function dbg(...)
    if not Config.Debug then return end
    print(('[%s]'):format(RESOURCE), ...)
end

local function tr(key)
    local lang = Config.Locales[Config.Language] or Config.Locales.en
    return (lang and lang[key]) or key
end

local function notify(msg, nType)
    nType = nType or 'inform'

    if HasOxLib and lib and lib.notify then
        lib.notify({
            title = 'Crafting',
            description = msg,
            type = nType,
        })
        return
    end

    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(msg))
    EndTextCommandThefeedPostTicker(false, false)
end

local function vec3From(tbl)
    return vec3(tonumber(tbl.x) or 0.0, tonumber(tbl.y) or 0.0, tonumber(tbl.z) or 0.0)
end

local function vec4From(tbl)
    return vec4(tonumber(tbl.x) or 0.0, tonumber(tbl.y) or 0.0, tonumber(tbl.z) or 0.0, tonumber(tbl.w) or 0.0)
end

local function tableCopy(tbl)
    if type(tbl) ~= 'table' then return tbl end
    local out = {}
    for k, v in pairs(tbl) do
        out[k] = tableCopy(v)
    end
    return out
end

local function waitForModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then
        return nil
    end

    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > timeout then
            return nil
        end
        Wait(0)
    end

    return hash
end

local function serverCallback(action, payload, timeout)
    CallbackId = CallbackId + 1
    local id = CallbackId
    local p = promise.new()
    PendingCallbacks[id] = p

    TriggerServerEvent('elcon-crafting:server:callback', id, action, payload)

    SetTimeout(timeout or 5000, function()
        if PendingCallbacks[id] then
            PendingCallbacks[id]:resolve(nil)
            PendingCallbacks[id] = nil
        end
    end)

    return Citizen.Await(p)
end

RegisterNetEvent('elcon-crafting:client:callbackResponse', function(cbId, result)
    local p = PendingCallbacks[cbId]
    if not p then return end
    PendingCallbacks[cbId] = nil
    p:resolve(result)
end)

local function clearTargetZones()
    if not HasOxTarget then return end
    for _, zoneId in pairs(TargetZones) do
        pcall(function()
            exports.ox_target:removeZone(zoneId)
        end)
    end
    TargetZones = {}
end

local function clearProps()
    for _, entity in pairs(SpawnedProps) do
        if DoesEntityExist(entity) then
            DeleteEntity(entity)
        end
    end
    SpawnedProps = {}
end

local function clearBlips()
    for _, blip in pairs(Blips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    Blips = {}
end

local function createBlip(station)
    if not Config.Blips.enabled then return end
    if not station.blip or not station.blip.enabled then return end

    local coords = vec3From(station.coords)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, station.blip.sprite or 566)
    SetBlipColour(blip, station.blip.color or 2)
    SetBlipScale(blip, station.blip.scale or 0.75)
    SetBlipAsShortRange(blip, Config.Blips.shortRange ~= false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(station.blip.name or station.label or 'Crafting')
    EndTextCommandSetBlipName(blip)

    Blips[station.id] = blip
end

local function draw2DText(x, y, text, scale)
    SetTextFont(4)
    SetTextScale(scale or 0.35, scale or 0.35)
    SetTextColour(255, 255, 255, 220)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function draw3DText(coords, text)
    local onScreen, _x, _y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end

    local camCoords = GetGameplayCamCoord()
    local dist = #(camCoords - coords)
    local scale = (1 / dist) * 1.2

    SetTextScale(0.0, 0.35 * scale)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 220)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(_x, _y)
end

local function getDistanceToStation(station)
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local c = vec3From(station.coords)
    return #(pos - c)
end

local function buildStationIndex()
    StationIndex = {}
    for _, station in ipairs(Stations) do
        StationIndex[station.id] = station
    end
end

local function setNuiOpen(state)
    NuiOpen = state
    SetNuiFocus(state, state)
    SendNUIMessage({ action = 'setVisible', visible = state })
end

local function openCraftNui(stationView)
    setNuiOpen(true)
    SendNUIMessage({
        action = 'openCraft',
        payload = stationView,
    })
end

local function openCraftingWithOxLib(stationView)
    local station = stationView.station
    local recipes = stationView.recipes or {}

    local options = {}
    for _, recipe in ipairs(recipes) do
        local can1 = recipe.availability and recipe.availability['1'] and recipe.availability['1'].canCraft
        local statusText = can1 and 'Ready' or (recipe.availability and recipe.availability['1'] and recipe.availability['1'].reason or 'Blocked')

        options[#options + 1] = {
            title = recipe.label,
            description = ('%s\nTime: %sms\n%s'):format(recipe.description or '', recipe.duration or 0, statusText),
            icon = 'hammer',
            arrow = true,
            onSelect = function()
                local qtyOptions = {
                    {
                        title = 'Craft x1',
                        icon = '1',
                        disabled = not (recipe.availability and recipe.availability['1'] and recipe.availability['1'].canCraft),
                        description = recipe.availability and recipe.availability['1'] and recipe.availability['1'].reason,
                        onSelect = function()
                            TriggerServerEvent('elcon-crafting:server:requestCraft', station.id, recipe.id, 1)
                        end,
                    }
                }

                if recipe.canCraftMultiple then
                    qtyOptions[#qtyOptions + 1] = {
                        title = 'Craft x5',
                        icon = '5',
                        disabled = not (recipe.availability and recipe.availability['5'] and recipe.availability['5'].canCraft),
                        description = recipe.availability and recipe.availability['5'] and recipe.availability['5'].reason,
                        onSelect = function()
                            TriggerServerEvent('elcon-crafting:server:requestCraft', station.id, recipe.id, 5)
                        end,
                    }
                    qtyOptions[#qtyOptions + 1] = {
                        title = 'Craft x10',
                        icon = '10',
                        disabled = not (recipe.availability and recipe.availability['10'] and recipe.availability['10'].canCraft),
                        description = recipe.availability and recipe.availability['10'] and recipe.availability['10'].reason,
                        onSelect = function()
                            TriggerServerEvent('elcon-crafting:server:requestCraft', station.id, recipe.id, 10)
                        end,
                    }
                end

                local ingredientLines = {}
                for _, ingredient in ipairs(recipe.ingredients or {}) do
                    ingredientLines[#ingredientLines + 1] = ('- %s x%s'):format(ingredient.item, ingredient.amount)
                end
                local outputLines = {}
                for _, output in ipairs(recipe.outputs or {}) do
                    outputLines[#outputLines + 1] = ('+ %s x%s (%s%%)'):format(output.item, output.amount, output.chance or 100)
                end

                local detailDesc = ('Ingredients:\n%s\n\nOutputs:\n%s'):format(
                    #ingredientLines > 0 and table.concat(ingredientLines, '\n') or 'None',
                    #outputLines > 0 and table.concat(outputLines, '\n') or 'None'
                )

                qtyOptions[#qtyOptions + 1] = {
                    title = 'Recipe Details',
                    description = detailDesc,
                    disabled = true,
                }

                local qtyId = ('elcon_crafting_qty_%s_%s'):format(station.id, recipe.id)
                lib.registerContext({
                    id = qtyId,
                    title = recipe.label,
                    menu = ('elcon_crafting_station_%s'):format(station.id),
                    options = qtyOptions,
                })
                lib.showContext(qtyId)
            end,
        }
    end

    local id = ('elcon_crafting_station_%s'):format(station.id)
    lib.registerContext({
        id = id,
        title = station.title or station.label or 'Crafting',
        options = options,
    })
    lib.showContext(id)
end

local function openCraftingStation(stationId)
    local stationView = serverCallback('getStationView', { stationId = stationId }, 8000)
    if not stationView then
        notify('Failed loading station data.', 'error')
        return
    end

    if Config.UseOxLibCraftUI and HasOxLib and lib and lib.registerContext then
        openCraftingWithOxLib(stationView)
    elseif Config.UseNuiFallback then
        openCraftNui(stationView)
    else
        notify(tr('ui_no_fallback'), 'error')
    end
end

local function registerStationTarget(station)
    if not HasOxTarget or not Config.UseOxTarget then return end

    local coords = vec3From(station.coords)
    local size = vec3From(station.zone and station.zone.size or { x = 2.0, y = 2.0, z = 2.0 })
    local offset = vec3From(station.zone and station.zone.offset or { x = 0.0, y = 0.0, z = 0.0 })
    local rotation = (station.zone and station.zone.rotation) or station.coords.w or 0.0

    local zoneId = exports.ox_target:addBoxZone({
        coords = coords + offset,
        size = size,
        rotation = rotation,
        debug = station.zone and station.zone.debug == true,
        drawSprite = Config.Debug,
        options = {
            {
                name = ('elcon_crafting_%s'):format(station.id),
                icon = 'fa-solid fa-hammer',
                label = tr('target_label'),
                distance = Config.InteractionDistance + 1.0,
                onSelect = function()
                    openCraftingStation(station.id)
                end,
            }
        }
    })

    TargetZones[station.id] = zoneId
end

local function spawnStationProp(station)
    if not station.spawnProp then return end

    local hash = waitForModel(station.model)
    if not hash then
        dbg('Model not found:', station.model)
        return
    end

    local c = vec4From(station.coords)
    local object = CreateObject(hash, c.x, c.y, c.z, false, false, false)
    if object == 0 then
        SetModelAsNoLongerNeeded(hash)
        return
    end

    SetEntityHeading(object, c.w)
    PlaceObjectOnGroundProperly(object)
    FreezeEntityPosition(object, station.propFrozen ~= false)
    SetEntityAsMissionEntity(object, true, false)

    SpawnedProps[station.id] = object
    SetModelAsNoLongerNeeded(hash)
end

local function buildStations(data)
    clearTargetZones()
    clearProps()
    clearBlips()

    Stations = data or {}
    buildStationIndex()

    for _, station in ipairs(Stations) do
        spawnStationProp(station)
        createBlip(station)
        registerStationTarget(station)
    end

    dbg(('Registered %s stations'):format(#Stations))
end

RegisterNetEvent('elcon-crafting:client:syncStations', function(data)
    buildStations(data)
end)

RegisterNetEvent('elcon-crafting:client:notify', function(msg, nType)
    notify(msg, nType)
end)

local function doSkillCheckIfNeeded(data)
    if not data.skillCheck then return true end
    if not HasOxLib or not lib or not lib.skillCheck then
        return true
    end

    return lib.skillCheck({ 'easy', 'easy', 'medium' }, { 'e', 'q', 'r' })
end

local function startAnim(data)
    local ped = PlayerPedId()

    if data.scenario and data.scenario ~= '' then
        TaskStartScenarioInPlace(ped, data.scenario, 0, true)
        return
    end

    if data.animation and data.animation.dict and data.animation.clip then
        RequestAnimDict(data.animation.dict)
        local timeout = GetGameTimer() + 4000
        while not HasAnimDictLoaded(data.animation.dict) do
            if GetGameTimer() > timeout then break end
            Wait(0)
        end

        if HasAnimDictLoaded(data.animation.dict) then
            TaskPlayAnim(
                ped,
                data.animation.dict,
                data.animation.clip,
                3.0,
                3.0,
                data.duration,
                data.animation.flag or 49,
                0.0,
                false,
                false,
                false
            )
        end
    end
end

local function runProgressFallback(data)
    local ped = PlayerPedId()
    local startTime = GetGameTimer()
    local endAt = startTime + data.duration
    local cancelled = false
    local reason = tr('craft_cancelled')

    while GetGameTimer() < endAt do
        Wait(0)
        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
        DisableControlAction(0, 21, true)

        local stationCoords = vec3(data.stationCoords.x, data.stationCoords.y, data.stationCoords.z)
        local playerCoords = GetEntityCoords(ped)
        if #(playerCoords - stationCoords) > (data.maxDistance + 0.5) then
            cancelled = true
            reason = tr('too_far')
            break
        end

        if IsControlJustReleased(0, 177) then
            cancelled = true
            reason = tr('craft_cancelled')
            break
        end

        local pct = math.floor(((GetGameTimer() - startTime) / data.duration) * 100)
        draw2DText(0.5, 0.9, ('Crafting... %s%% (Backspace to cancel)'):format(pct), 0.35)
    end

    ClearPedTasks(ped)

    return not cancelled, reason
end

RegisterNetEvent('elcon-crafting:client:startProgress', function(data)
    if IsCrafting then return end

    IsCrafting = true
    ActiveCraftToken = data.token

    local ped = PlayerPedId()

    if not Config.Flags.allowInVehicle and IsPedInAnyVehicle(ped, false) then
        TriggerServerEvent('elcon-crafting:server:finishCraft', data.token, true, 'Cannot craft in vehicle.')
        IsCrafting = false
        ActiveCraftToken = nil
        return
    end

    if not Config.Flags.allowWhileDead and IsEntityDead(ped) then
        TriggerServerEvent('elcon-crafting:server:finishCraft', data.token, true, 'Cannot craft while dead.')
        IsCrafting = false
        ActiveCraftToken = nil
        return
    end

    if not Config.Flags.allowWhileCuffed and LocalPlayer.state.isHandcuffed then
        TriggerServerEvent('elcon-crafting:server:finishCraft', data.token, true, 'Cannot craft while cuffed.')
        IsCrafting = false
        ActiveCraftToken = nil
        return
    end

    if not doSkillCheckIfNeeded(data) then
        TriggerServerEvent('elcon-crafting:server:finishCraft', data.token, true, 'Skill check failed.')
        IsCrafting = false
        ActiveCraftToken = nil
        return
    end

    startAnim(data)

    local completed = false
    local cancelReason = tr('craft_cancelled')

    if HasOxLib and lib and lib.progressBar then
        local distanceCancelled = false

        CreateThread(function()
            while IsCrafting and ActiveCraftToken == data.token and lib.progressActive and lib.progressActive() do
                Wait(150)
                local playerCoords = GetEntityCoords(ped)
                local stationCoords = vec3(data.stationCoords.x, data.stationCoords.y, data.stationCoords.z)
                if #(playerCoords - stationCoords) > (data.maxDistance + 0.5) then
                    distanceCancelled = true
                    cancelReason = tr('too_far')
                    if lib.cancelProgress then
                        lib.cancelProgress()
                    end
                    break
                end
            end
        end)

        local ok = lib.progressBar({
            duration = data.duration,
            label = 'Crafting...',
            canCancel = true,
            useWhileDead = Config.Flags.allowWhileDead,
            disable = {
                move = true,
                car = true,
                combat = true,
            },
        })

        completed = ok == true and not distanceCancelled
        if not completed and distanceCancelled then
            cancelReason = tr('too_far')
        end
    else
        completed, cancelReason = runProgressFallback(data)
    end

    ClearPedTasks(ped)

    if completed then
        TriggerServerEvent('elcon-crafting:server:finishCraft', data.token, false)
    else
        TriggerServerEvent('elcon-crafting:server:finishCraft', data.token, true, cancelReason)
    end

    IsCrafting = false
    ActiveCraftToken = nil
end)

CreateThread(function()
    while true do
        Wait(1000)
        HasOxTarget = Config.UseOxTarget and GetResourceState('ox_target') == 'started'
        HasOxLib = GetResourceState('ox_lib') == 'started'
    end
end)

CreateThread(function()
    Wait(500)
    HasOxTarget = Config.UseOxTarget and GetResourceState('ox_target') == 'started'
    HasOxLib = GetResourceState('ox_lib') == 'started'
    TriggerServerEvent('elcon-crafting:server:requestData')
end)

CreateThread(function()
    while true do
        Wait(250)

        if HasOxTarget or not Config.EnablePressEFallback or NuiOpen or IsCrafting then
            Wait(500)
        else
            local ped = PlayerPedId()
            local pCoords = GetEntityCoords(ped)

            local nearestStation = nil
            local nearestDist = 9999.0
            for _, station in ipairs(Stations) do
                local sCoords = vec3From(station.coords)
                local dist = #(pCoords - sCoords)
                if dist < nearestDist then
                    nearestDist = dist
                    nearestStation = station
                end
            end

            if nearestStation and nearestDist <= (Config.InteractionDistance + 0.8) then
                local textPos = vec3From(nearestStation.coords) + vec3(0.0, 0.0, 1.05)
                draw3DText(textPos, '[E] Craft')
                if IsControlJustReleased(0, Config.InteractionKey) then
                    openCraftingStation(nearestStation.id)
                end
                Wait(0)
            else
                Wait(450)
            end
        end
    end
end)

RegisterNUICallback('craftRequest', function(data, cb)
    local stationId = data and data.stationId
    local recipeId = data and data.recipeId
    local qty = tonumber(data and data.quantity) or 1

    if stationId and recipeId then
        TriggerServerEvent('elcon-crafting:server:requestCraft', stationId, recipeId, qty)
    end

    cb({ ok = true })
end)

RegisterNUICallback('close', function(_, cb)
    setNuiOpen(false)
    cb({ ok = true })
end)

-- Admin editor
local function adminAllowed()
    return serverCallback('isAdmin', {}, 4000) == true
end

local function drawEditorHelp(coords, heading)
    draw2DText(0.5, 0.83, ('[SCROLL] Rotate | [E] Confirm | [BACKSPACE] Cancel'), 0.35)
    draw2DText(0.5, 0.86, ('x: %.3f y: %.3f z: %.3f h: %.2f'):format(coords.x, coords.y, coords.z, heading), 0.35)
end

local function getPlacementCoords(baseCoords)
    local ped = PlayerPedId()
    local pcoords = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)

    local target = baseCoords or (pcoords + forward * 2.0)

    local ok, gz = GetGroundZFor_3dCoord(target.x, target.y, target.z + 2.0, false)
    if ok then
        target = vec3(target.x, target.y, gz)
    end

    return target
end

local function startGhostPlacement(model, startVec4)
    local hash = waitForModel(model)
    if not hash then
        notify(('Invalid model: %s'):format(model), 'error')
        return nil
    end

    local startCoords = startVec4 and vec3(startVec4.x, startVec4.y, startVec4.z) or nil
    local heading = startVec4 and startVec4.w or GetEntityHeading(PlayerPedId())
    local coords = getPlacementCoords(startCoords)

    local ghost = CreateObject(hash, coords.x, coords.y, coords.z, false, false, false)
    if ghost == 0 then
        return nil
    end

    SetEntityAlpha(ghost, 180, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    SetEntityHeading(ghost, heading)
    SetEntityInvincible(ghost, true)
    pcall(function()
        SetEntityDrawOutline(ghost, true)
        SetEntityDrawOutlineColor(80, 220, 120, 180)
    end)

    Editor.active = true

    while Editor.active do
        Wait(0)

        local latestCoords = getPlacementCoords(coords)
        coords = vec3(latestCoords.x, latestCoords.y, latestCoords.z)

        if IsControlJustPressed(0, 14) then
            heading = heading + 2.5
        elseif IsControlJustPressed(0, 15) then
            heading = heading - 2.5
        end

        SetEntityCoordsNoOffset(ghost, coords.x, coords.y, coords.z, false, false, false)
        SetEntityHeading(ghost, heading)

        drawEditorHelp(coords, heading)

        if IsControlJustReleased(0, 38) then
            Editor.active = false
            break
        end

        if IsControlJustReleased(0, 177) then
            DeleteEntity(ghost)
            SetModelAsNoLongerNeeded(hash)
            Editor.active = false
            return nil
        end
    end

    DeleteEntity(ghost)
    SetModelAsNoLongerNeeded(hash)

    return { x = coords.x, y = coords.y, z = coords.z, w = heading }
end

local function parseJsonField(raw)
    if not raw or raw == '' then return nil end
    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == 'table' then
        return decoded
    end
    return nil
end

local function buildStationInput(default)
    if not HasOxLib or not lib or not lib.inputDialog then
        notify('ox_lib is required for admin wizard UI.', 'error')
        return nil
    end

    local dialog = lib.inputDialog('Station Setup', {
        { type = 'input', label = 'Station ID', default = default and default.id or '', required = true },
        { type = 'input', label = 'Label', default = default and default.label or 'Crafting Station', required = true },
        { type = 'input', label = 'Title', default = default and default.title or 'Crafting', required = true },
        { type = 'input', label = 'Model', default = default and default.model or 'prop_tool_bench02', required = true },
        { type = 'checkbox', label = 'Spawn Prop', checked = default and default.spawnProp ~= false or true },
        { type = 'number', label = 'Zone X', default = default and default.zone and default.zone.size and default.zone.size.x or 2.0, required = true },
        { type = 'number', label = 'Zone Y', default = default and default.zone and default.zone.size and default.zone.size.y or 2.0, required = true },
        { type = 'number', label = 'Zone Z', default = default and default.zone and default.zone.size and default.zone.size.z or 2.2, required = true },
    })

    if not dialog then return nil end

    return {
        id = dialog[1],
        label = dialog[2],
        title = dialog[3],
        model = dialog[4],
        spawnProp = dialog[5] == true,
        zone = {
            type = 'box',
            size = { x = tonumber(dialog[6]) or 2.0, y = tonumber(dialog[7]) or 2.0, z = tonumber(dialog[8]) or 2.2 },
            offset = default and default.zone and default.zone.offset or { x = 0.0, y = 0.0, z = 0.0 },
            rotation = default and default.zone and default.zone.rotation or 0.0,
            debug = false,
        },
        propFrozen = true,
        blip = default and default.blip or { enabled = false, sprite = 566, color = 2, scale = 0.75, name = 'Crafting' },
        cooldown = default and default.cooldown or { station = 0 },
    }
end

local function saveStationWizard(existing)
    local st = buildStationInput(existing)
    if not st then return end

    local placed = startGhostPlacement(st.model, existing and existing.coords or nil)
    if not placed then
        notify('Placement cancelled.', 'error')
        return
    end

    st.coords = placed
    st.zone.rotation = placed.w

    TriggerServerEvent('elcon-crafting:server:admin:saveStation', st)
end

local function ingredientEditor(current)
    local list = current or {}

    while true do
        local menu = {
            id = 'elcon_ing_editor',
            title = 'Ingredients',
            options = {
                {
                    title = 'Add Ingredient',
                    icon = 'plus',
                    onSelect = function()
                        local d = lib.inputDialog('Ingredient', {
                            { type = 'input', label = 'Item', required = true },
                            { type = 'number', label = 'Amount', required = true, default = 1 },
                            { type = 'input', label = 'Metadata JSON (optional)', required = false },
                        })
                        if d then
                            list[#list + 1] = {
                                item = d[1],
                                amount = tonumber(d[2]) or 1,
                                metadata = parseJsonField(d[3]),
                            }
                        end
                    end,
                }
            }
        }

        for idx, ing in ipairs(list) do
            menu.options[#menu.options + 1] = {
                title = ('%s x%s'):format(ing.item, ing.amount),
                description = 'Remove',
                icon = 'trash',
                onSelect = function()
                    table.remove(list, idx)
                end,
            }
        end

        menu.options[#menu.options + 1] = {
            title = 'Done',
            icon = 'check',
            onSelect = function()
                lib.hideContext(false)
            end,
        }

        lib.registerContext(menu)
        lib.showContext('elcon_ing_editor')

        local done = false
        while not done do
            Wait(100)
            if not lib.getOpenContextMenu() then
                done = true
            end
        end

        local confirm = lib.alertDialog({
            header = 'Done editing ingredients?',
            content = ('Rows: %s'):format(#list),
            centered = true,
            cancel = true,
            labels = { confirm = 'Yes', cancel = 'Continue' }
        })

        if confirm == 'confirm' then
            break
        end
    end

    return list
end

local function outputEditor(current)
    local list = current or {}

    while true do
        local menu = {
            id = 'elcon_out_editor',
            title = 'Outputs',
            options = {
                {
                    title = 'Add Output',
                    icon = 'plus',
                    onSelect = function()
                        local d = lib.inputDialog('Output', {
                            { type = 'input', label = 'Item', required = true },
                            { type = 'number', label = 'Amount', required = true, default = 1 },
                            { type = 'number', label = 'Chance %', required = true, default = 100 },
                            { type = 'input', label = 'Metadata JSON (optional)', required = false },
                        })
                        if d then
                            list[#list + 1] = {
                                item = d[1],
                                amount = tonumber(d[2]) or 1,
                                chance = tonumber(d[3]) or 100,
                                metadata = parseJsonField(d[4]),
                            }
                        end
                    end,
                }
            }
        }

        for idx, out in ipairs(list) do
            menu.options[#menu.options + 1] = {
                title = ('%s x%s (%s%%)'):format(out.item, out.amount, out.chance or 100),
                description = 'Remove',
                icon = 'trash',
                onSelect = function()
                    table.remove(list, idx)
                end,
            }
        end

        menu.options[#menu.options + 1] = {
            title = 'Done',
            icon = 'check',
            onSelect = function()
                lib.hideContext(false)
            end,
        }

        lib.registerContext(menu)
        lib.showContext('elcon_out_editor')

        local done = false
        while not done do
            Wait(100)
            if not lib.getOpenContextMenu() then
                done = true
            end
        end

        local confirm = lib.alertDialog({
            header = 'Done editing outputs?',
            content = ('Rows: %s'):format(#list),
            centered = true,
            cancel = true,
            labels = { confirm = 'Yes', cancel = 'Continue' }
        })

        if confirm == 'confirm' then
            break
        end
    end

    return list
end

local function recipeWizard(station, existing)
    local recipe = tableCopy(existing or {
        id = ('recipe_%s_%s'):format(station.id, math.random(100, 999)),
        label = 'New Recipe',
        description = '',
        category = 'General',
        duration = 5000,
        canCraftMultiple = true,
        minPolice = 0,
        cooldown = { player = 0, station = 0 },
        requiredTool = nil,
        job = nil,
        gang = nil,
        grade = nil,
        scenario = nil,
        animation = nil,
        skillCheck = false,
        ingredients = {},
        outputs = {},
    })

    local running = true
    while running do
        local menuId = 'elcon_recipe_wizard'
        lib.registerContext({
            id = menuId,
            title = ('Recipe Wizard: %s'):format(recipe.label),
            options = {
                {
                    title = 'Step 1: Basics',
                    description = 'ID, label, duration, restrictions',
                    onSelect = function()
                        local d = lib.inputDialog('Recipe Basics', {
                            { type = 'input', label = 'Recipe ID', default = recipe.id, required = true },
                            { type = 'input', label = 'Label', default = recipe.label, required = true },
                            { type = 'input', label = 'Description', default = recipe.description, required = false },
                            { type = 'input', label = 'Category', default = recipe.category or 'General', required = false },
                            { type = 'number', label = 'Duration ms', default = recipe.duration or 5000, required = true },
                            { type = 'checkbox', label = 'Craft x5/x10 enabled', checked = recipe.canCraftMultiple == true },
                            { type = 'number', label = 'Min Police', default = recipe.minPolice or 0, required = true },
                            { type = 'input', label = 'Job (optional)', default = recipe.job or '', required = false },
                            { type = 'input', label = 'Gang (optional)', default = recipe.gang or '', required = false },
                            { type = 'number', label = 'Min Job Grade (optional)', default = recipe.grade or 0, required = false },
                            { type = 'number', label = 'Player Cooldown ms', default = recipe.cooldown and recipe.cooldown.player or 0, required = false },
                            { type = 'number', label = 'Station Cooldown ms', default = recipe.cooldown and recipe.cooldown.station or 0, required = false },
                            { type = 'checkbox', label = 'Enable Skill Check', checked = recipe.skillCheck == true },
                        })
                        if d then
                            recipe.id = d[1]
                            recipe.label = d[2]
                            recipe.description = d[3] or ''
                            recipe.category = d[4] or 'General'
                            recipe.duration = tonumber(d[5]) or 5000
                            recipe.canCraftMultiple = d[6] == true
                            recipe.minPolice = tonumber(d[7]) or 0
                            recipe.job = d[8] ~= '' and d[8] or nil
                            recipe.gang = d[9] ~= '' and d[9] or nil
                            recipe.grade = tonumber(d[10]) and math.floor(tonumber(d[10])) or nil
                            recipe.cooldown = {
                                player = tonumber(d[11]) or 0,
                                station = tonumber(d[12]) or 0,
                            }
                            recipe.skillCheck = d[13] == true
                        end
                    end,
                },
                {
                    title = 'Step 2: Ingredients',
                    description = ('Rows: %s'):format(#(recipe.ingredients or {})),
                    onSelect = function()
                        recipe.ingredients = ingredientEditor(recipe.ingredients or {})
                    end,
                },
                {
                    title = 'Step 3: Outputs',
                    description = ('Rows: %s'):format(#(recipe.outputs or {})),
                    onSelect = function()
                        recipe.outputs = outputEditor(recipe.outputs or {})
                    end,
                },
                {
                    title = 'Step 4: Tool / Anim',
                    description = 'Optional required tool and animation/scenario',
                    onSelect = function()
                        local d = lib.inputDialog('Tool + Animation', {
                            { type = 'input', label = 'Required Tool Item (optional)', default = recipe.requiredTool and recipe.requiredTool.item or '', required = false },
                            { type = 'input', label = 'Tool Metadata JSON (optional)', default = recipe.requiredTool and json.encode(recipe.requiredTool.metadata or {}) or '', required = false },
                            { type = 'input', label = 'Scenario (optional)', default = recipe.scenario or '', required = false },
                            { type = 'input', label = 'Anim Dict (optional)', default = recipe.animation and recipe.animation.dict or '', required = false },
                            { type = 'input', label = 'Anim Clip (optional)', default = recipe.animation and recipe.animation.clip or '', required = false },
                            { type = 'number', label = 'Anim Flag', default = recipe.animation and recipe.animation.flag or 49, required = false },
                        })
                        if d then
                            recipe.requiredTool = nil
                            if d[1] and d[1] ~= '' then
                                recipe.requiredTool = {
                                    item = d[1],
                                    metadata = parseJsonField(d[2]),
                                }
                            end

                            recipe.scenario = d[3] ~= '' and d[3] or nil

                            if d[4] ~= '' and d[5] ~= '' then
                                recipe.animation = {
                                    dict = d[4],
                                    clip = d[5],
                                    flag = tonumber(d[6]) or 49,
                                }
                            else
                                recipe.animation = nil
                            end
                        end
                    end,
                },
                {
                    title = 'Save Recipe',
                    icon = 'floppy-disk',
                    onSelect = function()
                        if #(recipe.ingredients or {}) == 0 or #(recipe.outputs or {}) == 0 then
                            notify('Recipe needs at least one ingredient and output.', 'error')
                            return
                        end
                        TriggerServerEvent('elcon-crafting:server:admin:saveRecipe', station.id, recipe)
                        running = false
                    end,
                },
                {
                    title = 'Cancel',
                    icon = 'xmark',
                    onSelect = function()
                        running = false
                    end,
                }
            }
        })

        lib.showContext(menuId)

        while running and lib.getOpenContextMenu() == menuId do
            Wait(100)
        end

        Wait(50)
    end
end

local function manageStationRecipes(station)
    if not HasOxLib or not lib then return end

    local options = {
        {
            title = 'Add Recipe',
            icon = 'plus',
            onSelect = function()
                recipeWizard(station, nil)
            end,
        }
    }

    for _, recipe in ipairs(station.recipes or {}) do
        options[#options + 1] = {
            title = recipe.label,
            description = recipe.id,
            icon = 'hammer',
            arrow = true,
            onSelect = function()
                lib.registerContext({
                    id = 'elcon_recipe_actions',
                    title = recipe.label,
                    options = {
                        {
                            title = 'Edit Recipe',
                            icon = 'pen',
                            onSelect = function()
                                recipeWizard(station, recipe)
                            end,
                        },
                        {
                            title = 'Delete Recipe',
                            icon = 'trash',
                            onSelect = function()
                                TriggerServerEvent('elcon-crafting:server:admin:deleteRecipe', station.id, recipe.id)
                            end,
                        }
                    }
                })
                lib.showContext('elcon_recipe_actions')
            end,
        }
    end

    lib.registerContext({
        id = 'elcon_station_recipe_menu',
        title = ('Recipes: %s'):format(station.label),
        options = options,
    })

    lib.showContext('elcon_station_recipe_menu')
end

local function stationActionsMenu(station)
    if not HasOxLib or not lib then return end

    lib.registerContext({
        id = 'elcon_station_actions',
        title = ('Station: %s'):format(station.label),
        options = {
            {
                title = 'Move Station (Ghost Preview)',
                icon = 'arrows-up-down-left-right',
                onSelect = function()
                    local newCoords = startGhostPlacement(station.model, station.coords)
                    if not newCoords then return end

                    local updated = tableCopy(station)
                    updated.coords = newCoords
                    updated.zone.rotation = newCoords.w
                    TriggerServerEvent('elcon-crafting:server:admin:saveStation', updated)
                end,
            },
            {
                title = 'Edit Station Setup',
                icon = 'pen',
                onSelect = function()
                    saveStationWizard(station)
                end,
            },
            {
                title = 'Manage Recipes',
                icon = 'list',
                onSelect = function()
                    manageStationRecipes(station)
                end,
            },
            {
                title = 'Delete Station',
                icon = 'trash',
                onSelect = function()
                    TriggerServerEvent('elcon-crafting:server:admin:deleteStation', station.id)
                end,
            },
        }
    })

    lib.showContext('elcon_station_actions')
end

local function openAdminMenu()
    if not HasOxLib or not lib then
        notify('ox_lib is required for admin wizard UI.', 'error')
        return
    end

    local options = {
        {
            title = 'Create Station',
            description = 'Step-by-step: model -> ghost placement -> zone save',
            icon = 'plus',
            onSelect = function()
                saveStationWizard(nil)
            end,
        }
    }

    for _, station in ipairs(Stations) do
        options[#options + 1] = {
            title = station.label,
            description = station.id,
            icon = 'location-dot',
            onSelect = function()
                stationActionsMenu(station)
            end,
        }
    end

    lib.registerContext({
        id = 'elcon_crafting_admin',
        title = tr('admin_menu'),
        options = options,
    })

    lib.showContext('elcon_crafting_admin')
end

RegisterCommand('craftadmin', function()
    if not adminAllowed() then
        notify(tr('no_permission'), 'error')
        return
    end

    openAdminMenu()
end, false)

RegisterKeyMapping('craftadmin', 'Open Crafting Admin', 'keyboard', 'F6')

AddEventHandler('onResourceStop', function(res)
    if res ~= RESOURCE then return end
    clearTargetZones()
    clearProps()
    clearBlips()
    if NuiOpen then
        setNuiOpen(false)
    end
end)

