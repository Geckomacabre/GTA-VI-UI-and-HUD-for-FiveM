if not lib.checkDependency('ox_lib', '3.30.0', true) then return end

lib.locale()

local utils = require 'client.utils'
local state = require 'client.state'
-- The module itself is kept, not just the no-arg call: getTargetOptions(entity,
-- type, model) doubles as a read-only "does this entity have any options?"
-- probe (it builds a fresh table and touches none of options_mt's shared
-- state), which is what the proximity scan below uses to test candidates
-- without disturbing the live options object. See the vice_hud block.
local api = require 'client.api'
local options = api.getTargetOptions()

require 'client.debug'
require 'client.defaults'
require 'client.compat.qtarget'

-- SendNuiMessage was localized here for the eye/list NUI upstream used to
-- drive; the vice_hud textui migration further down replaces every call
-- site, so nothing in this file uses it any more (left undeleted upstream,
-- deleted here since an unused local serves no purpose in the patched file).
local GetEntityCoords = GetEntityCoords
local GetEntityType = GetEntityType
local HasEntityClearLosToEntity = HasEntityClearLosToEntity
local GetEntityBoneIndexByName = GetEntityBoneIndexByName
local GetEntityBonePosition_2 = GetEntityBonePosition_2
local GetEntityModel = GetEntityModel
local IsDisabledControlJustPressed = IsDisabledControlJustPressed
local DisableControlAction = DisableControlAction
local DisablePlayerFiring = DisablePlayerFiring
local GetModelDimensions = GetModelDimensions
local GetOffsetFromEntityInWorldCoords = GetOffsetFromEntityInWorldCoords
local currentTarget = {}
local currentMenu
local menuChanged
local menuHistory = {}
local nearbyZones

-- ox_target:toggleHotkey used to pick between hold-to-target and a toggle
-- keybind; both modes are gone now that targeting is always-on (see the
-- vice_hud textui migration's supervisor thread, below startTargeting),
-- so that convar is no longer read here at all.
local mouseButton = GetConvarInt('ox_target:leftClick', 1) == 1 and 24 or 25
local debug = GetConvarInt('ox_target:debug', 0) == 1
local vec0 = vec3(0, 0, 0)

--[[ ---------------------------------------------------------------------------
     vice_hud textui migration  --  BEGIN  (added by vice_hud; safe to delete,
     see client/main.lua.pre-vice_hud for the pre-patch original)
     ---------------------------------------------------------------------------
     Everything ABOVE this block (raycasting, zone/entity option resolution,
     shouldHide) is untouched -- that engine stays exactly as upstream wrote
     it. What changes is what happens once the visible option list for this
     tick is known: instead of SendNuiMessage-ing it to this resource's own
     web page (an eye reticle + click-to-open option list), it drives
     vice_hud's already-built textui/menu system instead -- ShowActionPrompt
     (hold-to-confirm) for the common single-option case, OpenInteractMenu
     (already used by qbx_vehiclekeys) for 2+ options. Because neither of
     those needs NUI focus, this also means ox_target never calls
     state.setNuiFocus(true, ...) any more -- see the deleted block inside
     startTargeting's CreateThread below.

     The upstream keybind (hold/toggle Alt to enter a targeting mode) is
     ALSO gone -- see the CreateThread supervisor right after
     startTargeting's definition, further down. Still fully aim-based (the
     raycast engine above is untouched), just no key to hold before it runs
     any more: a prompt appears whenever you're looking at something in
     range, GTA VI/RDR2 style, and the raycast/overlay loop runs
     continuously rather than only while a key was held. That also means
     the overlay thread's control-disabling (firing/melee suppression) had
     to become conditional on hasTarget instead of running for the whole
     loop -- see that thread's own comment for why.

     getResponse is moved up here (unchanged) from where upstream defines it
     right before RegisterNUICallback('select', ...), so invokeOption below
     can use it; RegisterNUICallback('select', ...) itself is deleted further
     down since nothing can ever click into a web page that's never focused.
     ]] --

---@generic T
---@param option T
---@param server? boolean
---@return T
local function getResponse(option, server)
    local response = table.clone(option)
    response.entity = currentTarget.entity
    response.zone = currentTarget.zone
    response.coords = currentTarget.coords
    response.distance = currentTarget.distance

    if server then
        response.entity = response.entity ~= 0 and NetworkGetEntityIsNetworked(response.entity) and
            NetworkGetNetworkIdFromEntity(response.entity) or 0
    end

    response.icon = nil
    response.groups = nil
    response.items = nil
    response.canInteract = nil
    response.onSelect = nil
    response.export = nil
    response.event = nil
    response.serverEvent = nil
    response.command = nil

    return response
end

--- Same dispatch upstream's RegisterNUICallback('select', ...) body did,
--- just taking the option/zone directly (our own UI hands back the actual
--- table, not an index to re-resolve) instead of decoding NUI callback data.
---@param entry { option: OxTargetOption, zone: table? }
local function invokeOption(entry)
    local option, zone = entry.option, entry.zone
    if not option then return end

    if option.openMenu then
        local menuDepth = #menuHistory

        if option.name == 'builtin:goback' then
            option.menuName = option.openMenu
            option.openMenu = menuHistory[menuDepth]

            if menuDepth > 0 then
                menuHistory[menuDepth] = nil
            end
        else
            menuHistory[menuDepth + 1] = currentMenu
        end

        menuChanged = true
        currentMenu = option.openMenu ~= 'home' and option.openMenu or nil

        options:wipe()
    end

    currentTarget.zone = zone and zone.id or nil

    if option.onSelect then
        option.onSelect(option.qtarget and currentTarget.entity or getResponse(option))
    elseif option.export then
        exports[option.resource or zone.resource][option.export](nil, getResponse(option))
    elseif option.event then
        TriggerEvent(option.event, getResponse(option))
    elseif option.serverEvent then
        TriggerServerEvent(option.serverEvent, getResponse(option, true))
    elseif option.command then
        ExecuteCommand(option.command)
    end
end

-- 'prompt' | 'menu' | nil -- which of vice_hud's two UI pieces (if either)
-- is currently showing ox_target's options, so driveUi knows what to tear
-- down when the visible list changes shape or empties out.
local uiMode = nil
-- The flat list currently backing whichever UI is up -- resolved back into
-- on a vice_hud:interactSelect (menu case) or a completed hold (prompt
-- case), same purpose upstream's data[1]/data[2]/data[3] NUI indices served.
local currentInteractList = nil

-- How long the single-option textui prompt needs held before it fires,
-- matching the "hold-to-interact" feel this migration is modelled on
-- (RDR2 / GTA VI, and mz_textui, the reference this was built from) rather
-- than upstream's instant click. Tunable per-server; 1 is effectively a tap.
local textUiHoldMs = GetConvarInt('ox_target:textUiHoldMs', 350)

local function hideOxTargetUi()
    if uiMode == 'prompt' then
        exports.vice_hud:HideActionPrompt('ox_target')
    elseif uiMode == 'menu' then
        exports.vice_hud:CloseInteractMenu()
    end
    uiMode = nil
    currentInteractList = nil
end

--- list: array of { option, zone } for everything currently NOT hidden,
--- built fresh each time buildVisibleList() below runs. nil/empty hides
--- whichever UI piece (if any) is currently up.
local function driveUi(list)
    if not list or #list == 0 then
        hideOxTargetUi()
        return
    end

    if #list == 1 then
        -- A re-render that resolved to the exact same single option (e.g. a
        -- zone re-ran canInteract and nothing actually changed) must NOT
        -- re-call ShowActionPrompt -- that resets hold progress on every
        -- call, so doing it here would make an in-progress hold visibly
        -- stutter back to empty for no reason.
        if uiMode == 'prompt' and currentInteractList and currentInteractList[1]
            and currentInteractList[1].option == list[1].option then
            currentInteractList = list -- keep the zone reference current regardless
            return
        end

        if uiMode == 'menu' then exports.vice_hud:CloseInteractMenu() end
        uiMode = 'prompt'
        currentInteractList = list

        exports.vice_hud:ShowActionPrompt('ox_target', list[1].option.label or '', mouseButton, {
            hold = textUiHoldMs,
            onHeld = function()
                if uiMode ~= 'prompt' or not currentInteractList then return end
                local entry = currentInteractList[1]
                hideOxTargetUi()
                if entry then invokeOption(entry) end
            end,
        })
        return
    end

    if uiMode == 'prompt' then exports.vice_hud:HideActionPrompt('ox_target') end
    uiMode = 'menu'
    currentInteractList = list

    local mapped = {}
    for i, entry in ipairs(list) do
        mapped[i] = { label = entry.option.label or '' }
    end
    -- 'ox_target' as the token: vice_hud:interactSelect/interactClose echo
    -- it back, so the handlers below (registered once, at file scope) can
    -- tell a fire meant for THIS menu apart from e.g. qbx_vehiclekeys'
    -- Slim Jim menu, which uses the same global events. See
    -- client_overlays.lua's OpenInteractMenu comment for why that matters.
    exports.vice_hud:OpenInteractMenu(mapped, 0, 'ox_target')
end

AddEventHandler('vice_hud:interactSelect', function(index, token)
    if token ~= 'ox_target' or uiMode ~= 'menu' or not currentInteractList then return end
    local entry = currentInteractList[index + 1]
    hideOxTargetUi()
    if entry then invokeOption(entry) end
end)

AddEventHandler('vice_hud:interactClose', function(token)
    if token ~= 'ox_target' or uiMode ~= 'menu' then return end
    uiMode = nil
    currentInteractList = nil
end)

-- ---------------------------------------------------------------------------
-- Proximity targeting
-- ---------------------------------------------------------------------------
-- Upstream is purely aim-based: an option only resolves for whatever the
-- camera raycast physically hits. That means walking up to a dumpster shows
-- nothing unless you also look straight at it, which is not how a GTA VI /
-- RDR2 style prompt behaves.
--
-- ZONES already did proximity -- utils.getNearbyZones() takes coords, it was
-- just being handed the raycast's endpoint instead of the player, so that's
-- a one-argument change in the loop below.
--
-- ENTITY options (addModel / addLocalEntity / addGlobalPed / ...) are the
-- half that needed real work, and the half the dumpster falls under: those
-- are keyed to a specific entity, so something has to FIND the entity when
-- the player isn't aiming at one. Hence a throttled game-pool scan.
--
-- Aim still wins: the loop only falls back to this candidate when the
-- raycast didn't land on anything that has options, so deliberately looking
-- at one of several nearby things still picks that one.
local proximityRadius = (GetConvarInt('ox_target:proximityRadius', 3) or 3) + 0.0
local proximityInterval = GetConvarInt('ox_target:proximityInterval', 250)

-- GetEntityType's own enum (1 ped / 2 vehicle / 3 object) mapped to the pool
-- each lives in, so a hit carries the type shouldHide/options:set expect
-- without a second native call per candidate.
local PROXIMITY_POOLS = {
    [1] = 'CPed',
    [2] = 'CVehicle',
    [3] = 'CObject',
}

---Whether a getTargetOptions() probe carries anything at all worth showing.
---`global` is always a table (peds/vehicles/objects), so it has to be
---length-checked rather than nil-checked, unlike the other three.
local function probeHasOptions(probe)
    if not probe then return false end
    if probe.global and #probe.global > 0 then return true end
    if probe.model and #probe.model > 0 then return true end
    if probe.entity and #probe.entity > 0 then return true end
    if probe.localEntity and #probe.localEntity > 0 then return true end
    return false
end

local proximityLastScan = 0
local proximityEntity, proximityType, proximityModel, proximityCoords

---Nearest entity within proximityRadius that actually has options registered
---for it. Throttled (proximityInterval) rather than run per tick: this walks
---three game pools, and CObject alone is routinely hundreds of entities --
---fine a few times a second, not fine every frame.
local function scanNearbyEntities(playerCoords)
    local now = GetGameTimer()
    if now - proximityLastScan < proximityInterval then return end
    proximityLastScan = now

    local bestEntity, bestType, bestModel, bestCoords, bestDistance

    for entityType, pool in pairs(PROXIMITY_POOLS) do
        local entities = GetGamePool(pool)

        for i = 1, #entities do
            local entity = entities[i]

            -- The player's own ped and the vehicle they're sitting in are
            -- always within arm's reach; prompting on them constantly would
            -- make the HUD useless while driving.
            if entity ~= cache.ped and entity ~= cache.vehicle then
                local coords = GetEntityCoords(entity)
                local distance = #(playerCoords - coords)

                if distance <= proximityRadius and (not bestDistance or distance < bestDistance) then
                    local model = GetEntityModel(entity)

                    if probeHasOptions(api.getTargetOptions(entity, entityType, model)) then
                        bestEntity, bestType, bestModel = entity, entityType, model
                        bestCoords, bestDistance = coords, distance
                    end
                end
            end
        end
    end

    proximityEntity, proximityType = bestEntity, bestType
    proximityModel, proximityCoords = bestModel, bestCoords
end

--- Every visible (non-hidden) option for this tick, flattened out of
--- `options` (menu/global options) and `nearbyZones` (zone options) -- the
--- same two sources upstream's SendNuiMessage(json.encode({event='setTarget',
--- ...})) sent wholesale, just filtered and flattened instead of nested.
local function buildVisibleList()
    local list = {}

    for _, v in pairs(options) do
        for i = 1, #v do
            local option = v[i]
            if not option.hide then
                list[#list + 1] = { option = option, zone = nil }
            end
        end
    end

    for i = 1, #nearbyZones do
        local zone = nearbyZones[i]
        local zoneOptions = zone.options
        for j = 1, #zoneOptions do
            local option = zoneOptions[j]
            if not option.hide then
                list[#list + 1] = { option = option, zone = zone }
            end
        end
    end

    return list
end
-- vice_hud textui migration -- END (see below for two more small edits in
-- startTargeting and the deleted RegisterNUICallback('select', ...)) -------

---@param option OxTargetOption
---@param distance number
---@param endCoords vector3
---@param entityHit? number
---@param entityType? number
---@param entityModel? number | false
local function shouldHide(option, distance, endCoords, entityHit, entityType, entityModel)
    if option.menuName ~= currentMenu then
        return true
    end

    if distance > (option.distance or 7) then
        return true
    end

    if option.groups and not utils.hasPlayerGotGroup(option.groups) then
        return true
    end

    if option.items and not utils.hasPlayerGotItems(option.items, option.anyItem) then
        return true
    end

    local bone = entityModel and option.bones or nil

    if bone then
        ---@cast entityHit number
        ---@cast entityType number
        ---@cast entityModel number

        local _type = type(bone)

        if _type == 'string' then
            local boneId = GetEntityBoneIndexByName(entityHit, bone)

            if boneId ~= -1 and #(endCoords - GetEntityBonePosition_2(entityHit, boneId)) <= 2 then
                bone = boneId
            else
                return true
            end
        elseif _type == 'table' then
            local closestBone, boneDistance

            for j = 1, #bone do
                local boneId = GetEntityBoneIndexByName(entityHit, bone[j])

                if boneId ~= -1 then
                    local dist = #(endCoords - GetEntityBonePosition_2(entityHit, boneId))

                    if dist <= (boneDistance or 1) then
                        closestBone = boneId
                        boneDistance = dist
                    end
                end
            end

            if closestBone then
                bone = closestBone
            else
                return true
            end
        end
    end

    local offset = entityModel and option.offset or nil

    if offset then
        ---@cast entityHit number
        ---@cast entityType number
        ---@cast entityModel number

        if not option.absoluteOffset then
            local min, max = GetModelDimensions(entityModel)
            offset = (max - min) * offset + min
        end

        offset = GetOffsetFromEntityInWorldCoords(entityHit, offset.x, offset.y, offset.z)

        if #(endCoords - offset) > (option.offsetSize or 1) then
            return true
        end
    end

    if option.canInteract then
        local success, resp = pcall(option.canInteract, entityHit, distance, endCoords, option.name, bone)
        return not success or not resp
    end
end

local function startTargeting()
    if state.isDisabled() or state.isActive() or IsNuiFocused() or IsPauseMenuActive() then return end

    state.setActive(true)

    local flag = 511
    local hit, entityHit, endCoords, distance, lastEntity, entityType, entityModel, hasTarget, zonesChanged
    local zones = {}

    CreateThread(function()
        local dict, texture = utils.getTexture()
        local lastCoords

        while state.isActive() do
            lastCoords = endCoords == vec0 and lastCoords or endCoords or vec0

            if debug then
                DrawMarker(28, lastCoords.x, lastCoords.y, lastCoords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.2, 0.2,
                    0.2,
                    ---@diagnostic disable-next-line: param-type-mismatch
                    255, 42, 24, 100, false, false, 0, true, false, false, false)
            end

            utils.drawZoneSprites(dict, texture)

            -- Only suppress firing/melee while something is actually being
            -- offered RIGHT NOW (hasTarget true -- a prompt or menu is up),
            -- not for the whole time this loop runs. That distinction did
            -- not matter upstream, where this loop only ran for as long as
            -- Alt was held -- a deliberate, brief, opt-in window. Now that
            -- targeting is always-on (see the keybind removal below), an
            -- unconditional disable here would lock players out of firing
            -- and melee attacks permanently, for the entire time this
            -- resource runs. hasTarget is the same upvalue the main loop
            -- below sets; both closures share it since they're defined in
            -- the same startTargeting() call.
            if hasTarget then
                DisablePlayerFiring(cache.playerId, true)
                DisableControlAction(0, 25, true)
                DisableControlAction(0, 140, true)
                DisableControlAction(0, 141, true)
                DisableControlAction(0, 142, true)
            end

            -- Upstream granted NUI focus + cursor here on a mouseButton
            -- press so the player could click an option in its own web
            -- page's list. Neither of vice_hud's replacements need that:
            -- ShowActionPrompt's hold is polled directly (mouseButton is
            -- still the control, see driveUi below, just read without ever
            -- touching NUI focus) and OpenInteractMenu's ScaleformUI menu
            -- reads keyboard/controller input on its own. See this file's
            -- header block for the rest of this migration.

            Wait(0)
        end

        SetStreamedTextureDictAsNoLongerNeeded(dict)
    end)

    while state.isActive() do
        if not state.isNuiFocused() and lib.progressActive() then
            state.setActive(false)
            break
        end

        local playerCoords = GetEntityCoords(cache.ped)
        hit, entityHit, endCoords = lib.raycast.fromCamera(flag, 4, 20)
        distance = #(playerCoords - endCoords)

        if entityHit ~= 0 and entityHit ~= lastEntity then
            local success, result = pcall(GetEntityType, entityHit)
            entityType = success and result or 0
        end

        if entityType == 0 then
            local _flag = flag == 511 and 26 or 511
            local _hit, _entityHit, _endCoords = lib.raycast.fromCamera(_flag, 4, 20)
            local _distance = #(playerCoords - _endCoords)

            if _distance < distance then
                flag, hit, entityHit, endCoords, distance = _flag, _hit, _entityHit, _endCoords, _distance

                if entityHit ~= 0 then
                    local success, result = pcall(GetEntityType, entityHit)
                    entityType = success and result or 0
                end
            end
        end

        -- vice_hud: proximity fallback. If the raycast didn't land on
        -- anything carrying options, substitute the nearest entity that
        -- does, so walking up to a dumpster works without aiming at it.
        -- Aim deliberately wins when it DID hit something with options --
        -- that's what still lets you pick a specific one out of a cluster.
        --
        -- endCoords/distance are reassigned along with the entity because
        -- shouldHide measures both against the option (its `distance`, and
        -- its bone/offset checks) -- leaving them pointing at wherever the
        -- camera happened to hit would hide the substituted entity's own
        -- options immediately.
        scanNearbyEntities(playerCoords)

        -- entityModel is only refreshed further down (inside the
        -- entityChanged branch), so it still describes the PREVIOUS entity
        -- at this point -- probing with it would test the wrong model on
        -- the tick the raycast moves onto something new. Read it fresh.
        local aimedHasOptions = false

        if entityHit > 0 then
            local success, aimedModel = pcall(GetEntityModel, entityHit)
            aimedHasOptions = probeHasOptions(api.getTargetOptions(entityHit, entityType, success and aimedModel or nil))
        end

        if not aimedHasOptions then
            if proximityEntity and DoesEntityExist(proximityEntity) then
                entityHit = proximityEntity
                entityType = proximityType
                endCoords = proximityCoords
                distance = #(playerCoords - proximityCoords)
            end
        end

        -- Player coords, NOT the raycast endpoint: zones are a proximity
        -- concept ("am I standing in it"), and feeding them the endpoint is
        -- what made a zone only register while you were also looking into it.
        nearbyZones, zonesChanged = utils.getNearbyZones(playerCoords)

        local entityChanged = entityHit ~= lastEntity
        local newOptions = (zonesChanged or entityChanged or menuChanged) and true

        if entityHit > 0 and entityChanged then
            currentMenu = nil

            if flag ~= 511 then
                entityHit = HasEntityClearLosToEntity(entityHit, cache.ped, 7) and entityHit or 0
            end

            if lastEntity ~= entityHit and debug then
                if lastEntity then
                    SetEntityDrawOutline(lastEntity, false)
                end

                if entityType ~= 1 then
                    SetEntityDrawOutline(entityHit, true)
                end
            end

            if entityHit > 0 then
                local success, result = pcall(GetEntityModel, entityHit)
                entityModel = success and result
            end
        end

        -- hasTarget is either a NUMBER (options.size) or the boolean `true`
        -- (set below once more than one option is visible), so a bare
        -- `hasTarget > 1` throws "attempt to compare boolean with number"
        -- the moment an entity changes while 2+ options were showing.
        -- Upstream had the same latent bug but self-healed: releasing Alt
        -- called state.setActive(false), so the next press started clean.
        -- With the keybind gone (always-on targeting) that error instead
        -- kills the supervisor thread AND leaves state stuck active, which
        -- bricks targeting until the resource restarts -- so it has to be
        -- an explicit boolean check, not an implicit numeric comparison.
        if hasTarget and (zonesChanged or entityChanged and (hasTarget == true or hasTarget > 1)) then
            driveUi(nil)

            if entityChanged then options:wipe() end

            if debug and lastEntity > 0 then SetEntityDrawOutline(lastEntity, false) end

            hasTarget = false
        end

        if newOptions and entityModel and entityHit > 0 then
            options:set(entityHit, entityType, entityModel)
        end

        lastEntity = entityHit
        currentTarget.entity = entityHit
        currentTarget.coords = endCoords
        currentTarget.distance = distance
        local hidden = 0
        local totalOptions = 0

        for k, v in pairs(options) do
            local optionCount = #v
            local dist = k == '__global' and 0 or distance
            totalOptions += optionCount

            for i = 1, optionCount do
                local option = v[i]
                local hide = shouldHide(option, dist, endCoords, entityHit, entityType, entityModel)

                if option.hide ~= hide then
                    option.hide = hide
                    newOptions = true
                end

                if hide then hidden += 1 end
            end
        end

        if zonesChanged then table.wipe(zones) end

        for i = 1, #nearbyZones do
            local zoneOptions = nearbyZones[i].options
            local optionCount = #zoneOptions
            totalOptions += optionCount
            zones[i] = zoneOptions

            for j = 1, optionCount do
                local option = zoneOptions[j]
                local hide = shouldHide(option, distance, endCoords, entityHit)

                if option.hide ~= hide then
                    option.hide = hide
                    newOptions = true
                end

                if hide then hidden += 1 end
            end
        end

        if newOptions then
            if hasTarget == 1 and (totalOptions - hidden) > 1 then
                hasTarget = true
            end

            if hasTarget and hidden == totalOptions then
                if hasTarget and hasTarget ~= 1 then
                    hasTarget = false
                    driveUi(nil)
                end
            elseif menuChanged or hasTarget ~= 1 and hidden ~= totalOptions then
                hasTarget = options.size

                if currentMenu and options.__global[1]?.name ~= 'builtin:goback' then
                    table.insert(options.__global, 1,
                        {
                            icon = 'fa-solid fa-circle-chevron-left',
                            label = locale('go_back'),
                            name = 'builtin:goback',
                            menuName = currentMenu,
                            openMenu = 'home'
                        })
                end

                driveUi(buildVisibleList())
            end

            menuChanged = false
        end

        -- Unconditional now (was gated behind the now-deleted toggleHotkey
        -- convar) -- always-on targeting has to stop for the pause menu
        -- regardless, there's no keybind-mode distinction left to gate it on.
        if IsPauseMenuActive() then
            state.setActive(false)
        end

        if not hasTarget or hasTarget == 1 then
            flag = flag == 511 and 26 or 511
        end

        Wait(hit and 50 or 100)
    end

    if lastEntity and debug then
        SetEntityDrawOutline(lastEntity, false)
    end

    state.setNuiFocus(false)
    driveUi(nil) -- targeting itself stopped -- tear down whichever UI piece is up, if any
    table.wipe(currentTarget)
    options:wipe()

    if nearbyZones then table.wipe(nearbyZones) end
end

-- Always-on: no keybind gates targeting any more, matching a GTA VI/RDR2
-- style prompt that just appears when you're looking at something, rather
-- than upstream's hold-Alt-to-enter-targeting-mode design. Still fully
-- aim-based -- the raycast/option-resolution engine above is untouched,
-- this only removes the key that used to have to be held before any of it
-- ran. The old 'ox_target' keybind (LMENU by default) and the
-- ox_target:toggleHotkey convar it read are both gone; neither means
-- anything once there's no key to bind.
--
-- startTargeting() already guards against running twice, while disabled,
-- while NUI-focused, or while the pause menu is open (its first line), and
-- already calls state.setActive(false) itself the moment any of those
-- become true, or a progress bar starts, which is what makes it return.
-- This supervisor just keeps calling it again once whatever stopped it
-- clears -- Wait(250) between attempts is only felt while something IS
-- blocking it; a normal running session blocks inside startTargeting()
-- itself for as long as it's active.
CreateThread(function()
    while true do
        -- pcall, and an unconditional state reset after it, because this
        -- supervisor is now the ONLY thing keeping targeting alive. An
        -- error anywhere inside startTargeting's main loop propagates
        -- straight up into THIS thread (only the overlay runs in its own
        -- CreateThread), so without pcall a single runtime error kills the
        -- supervisor permanently -- and because the error skips the
        -- function's own cleanup, state.isActive() stays true, which makes
        -- every future startTargeting() call return immediately anyway.
        -- That combination bricked targeting until a resource restart; see
        -- the hasTarget comparison fix above for the bug that first hit it.
        -- Upstream never needed this: the keybind's onReleased always reset
        -- the state, so an error there was invisible and self-healing.
        local ok, err = pcall(startTargeting)

        if not ok then
            print(('^1[ox_target]^7 targeting loop errored, restarting it: %s'):format(err))
        end

        -- Runs after a clean exit too -- harmless there (startTargeting
        -- already cleared it), and the one thing that guarantees a crashed
        -- run can't leave the state latched on.
        state.setActive(false)
        driveUi(nil)

        Wait(250)
    end
end)

-- getResponse and the option-dispatch logic that used to live in
-- RegisterNUICallback('select', ...) here were moved up to the vice_hud
-- textui migration block near the top of this file (getResponse and
-- invokeOption) -- see that block's header comment. The NUI callback itself
-- is gone: ox_target's own web page is never given NUI focus any more (see
-- the deleted block inside startTargeting's CreateThread), so nothing could
-- ever post to it.
