-- ============================================================================
-- qbx_vehiclekeys / client / slimjim
--
-- Third-eye the driver door of a locked, empty vehicle for a combined
-- "Slim Jim / Smash Window" prompt, vice_hud's GTA6-styled world-actions
-- list plus, for Slim Jim, its own "hold, release inside the zone" lockpick
-- ring. Only registers anything at all when vice_hud is running; without
-- it, this file is a no-op and the server behaves exactly as it did before
-- it existed (Smash Window still works through smashwindow.lua's own
-- ox_target option, see the guard on its registration).
--
-- Deliberately NOT built on LockpickDoor / lib.skillCheck
-- (client/functions.lua). That flow already exists, already works, and is
-- left completely alone; this is a second, parallel front end for the same
-- kind of theft, using vice_hud's ring instead of ox_lib's skill check, and
-- firing its own server event (qbx_vehiclekeys:server:slimJimmed) rather
-- than reusing functions.lua's locals, which aren't visible across files in
-- the same resource.
-- ============================================================================

if GetResourceState('vice_hud') ~= 'started' then return end

local config = require 'config.client'
local sjConfig = config.slimJim

if not sjConfig.enable then return end

local isSlimJimming = false
local promptedVehicle = nil -- the vehicle the world-actions prompt is currently showing for

---@param vehicle number
---@return boolean
local function getIsPickable(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    if cache.vehicle then return false end -- already sat in something
    if GetVehicleDoorLockStatus(vehicle) < 2 then return false end -- not locked
    if not IsVehicleSeatFree(vehicle, -1) then return false end -- someone is in the driver's seat
    if GetIsVehicleAccessible(vehicle) then return false end -- we have keys / job access

    local vehicleConfig = GetVehicleConfig(vehicle)
    if vehicleConfig.noLock or vehicleConfig.shared or vehicleConfig.lockpickImmune then return false end

    return true
end

---Which lockpick tier the player is carrying, if any. Advanced preferred
---when they have both, no reason to burn the better tool if a plain one
---would do, but if all they brought was the good one, that's what's used.
---@return 'advanced'|'base'|nil
local function getLockpickTier()
    local okAdv, hasAdvanced = pcall(function() return exports.ox_inventory:Search('count', 'advancedlockpick') end)
    if okAdv and hasAdvanced and hasAdvanced > 0 then return 'advanced' end
    local okBase, hasBase = pcall(function() return exports.ox_inventory:Search('count', 'lockpick') end)
    if okBase and hasBase and hasBase > 0 then return 'base' end
    return nil
end

---Mirrors smashwindow.lua's own getHonorTuning() almost exactly, see that
---file's comment for the full reasoning. Not shared between the two: their
---locals aren't visible across files in the same resource, and extracting a
---module for a dozen lines would touch smashwindow.lua for no real gain.
---@return {durationMultiplier: number, alertChanceMultiplier: number}
local function getHonorTuning()
    if GetResourceState('qbx_honor') ~= 'started' then return sjConfig.honor.neutral end

    local ok, honor = pcall(function() return exports.qbx_honor:GetHonor() end)
    if not ok or type(honor) ~= 'number' then return sjConfig.honor.neutral end

    local tierOk, tier = pcall(function() return exports.qbx_honor:GetBadgeTier(honor) end)
    if not tierOk then tier = nil end

    return sjConfig.honor[tier or 'neutral'] or sjConfig.honor.neutral
end

---@param vehicle number
---@param tier 'advanced'|'base'
local function onSlimJimResult(vehicle, tier, success)
    if success then
        TriggerServerEvent('qbx_vehiclekeys:server:slimJimmed', NetworkGetNetworkIdFromEntity(vehicle))
        TriggerServerEvent('hud:server:GainStress', math.random(sjConfig.stressGain[1], sjConfig.stressGain[2]))
        exports.qbx_core:Notify(locale('notify.vehicle_lockedpick'), 'success')
    else
        exports.qbx_core:Notify(locale('notify.failed_lockedpick'), 'error')
        TriggerServerEvent('hud:server:GainStress', math.random(1, 4))

        -- Same durability fields LockpickDoor's own breakLockpick already
        -- reads (shared/vehicle-config.lua). A vehicle tuned harder to
        -- pick is harder for BOTH flows to walk away from, not just one.
        local vehicleConfig = GetVehicleConfig(vehicle)
        local breakChance = tier == 'advanced'
            and vehicleConfig.removeAdvancedLockpickChance
            or vehicleConfig.removeNormalLockpickChance
        if math.random() <= (breakChance or 0) then
            TriggerServerEvent('qb-vehiclekeys:server:breakLockpick', tier == 'advanced' and 'advancedlockpick' or 'lockpick')
        end

        local tuning = getHonorTuning()
        if math.random() <= (tuning.alertChanceMultiplier or 1.0) then
            SendPoliceAlertAttempt(locale('info.crime_smash'), vehicle)
        end
    end
end

local function slimJim(vehicle)
    if isSlimJimming then return end
    local tier = getLockpickTier()
    if not tier then
        exports.qbx_core:Notify(locale('notify.no_lockpick'), 'error')
        return
    end

    isSlimJimming = true
    local tuning = getHonorTuning()
    local duration = math.floor(sjConfig.ringDurationMs * (tuning.durationMultiplier or 1.0))
    local zoneLen = tier == 'advanced' and sjConfig.zoneLenAdvanced or sjConfig.zoneLenBase

    local resultHandled = false
    local function handleResult(success)
        if resultHandled then return end
        resultHandled = true
        isSlimJimming = false
        if DoesEntityExist(vehicle) and GetIsCloseToVehicleDoor(vehicle, sjConfig.maxDistance) then
            onSlimJimResult(vehicle, tier, success)
        end
    end

    -- vice_hud:lockpickResult is fired locally (TriggerEvent, not
    -- TriggerClientEvent, see StartLockpickCheck/ReleaseLockpickCheck in
    -- vice_hud/client.lua), so this is a plain client-side AddEventHandler,
    -- not a net event.
    local handler
    handler = AddEventHandler('vice_hud:lockpickResult', function(success)
        RemoveEventHandler(handler)
        handleResult(success)
    end)

    -- Cancel outright (no win, no lose) if the vehicle drives off or
    -- despawns mid-hold, same guard smashWindow's own progress bar has.
    CreateThread(function()
        while isSlimJimming do
            if not DoesEntityExist(vehicle) or not GetIsCloseToVehicleDoor(vehicle, sjConfig.maxDistance * 2) then
                RemoveEventHandler(handler)
                exports.vice_hud:CancelLockpickCheck()
                isSlimJimming = false
                return
            end
            Wait(200)
        end
    end)

    exports.vice_hud:StartLockpickCheck({ durationMs = duration, zoneLen = zoneLen, glyph = 'R' })
end

-- ---- the two options, each its own keybind (matching the reference: Slim
-- Jim and Smash Window are separate buttons, not a highlight-and-confirm
-- list) --------------------------------------------------------------------

-- FIXED 2026-08-28: the prompt vice_hud draws for these (see its "World
-- action prompt" section) says Slim Jim = Triangle, Smash Window = Circle.
-- The actual controller bindings did not match that, and the vice_hud side
-- rendered the label from a hardcoded string with no connection to either
-- binding, so a controller player saw "Triangle: Slim Jim" and pressing it
-- did nothing (Slim Jim was actually on Circle, per the OLD secondaryKey
-- below), while Smash Window had no controller binding at all.
--
-- Verified against FiveM's own docs (docs.fivem.net/docs/game-references/
-- input-mapper-parameter-ids/pad_digitalbuttonany/), not the previous
-- comments here, which guessed "RB/R1" and were wrong. RRIGHT_INDEX is a
-- FACE button (B/Circle), not a shoulder button:
--   RUP_INDEX    = Y / Triangle
--   RRIGHT_INDEX = B / Circle
-- vice_hud now RESOLVES the shown glyph from this same key (its own `.hash`,
-- below) instead of a separate hand-picked string, so the two can no longer
-- drift apart the way they just did. See ShowWorldActions in
-- vice_hud/client_overlays.lua.
local slimJimKeybind = lib.addKeybind({
    name = 'slimjim',
    description = locale('target.slim_jim'),
    defaultKey = 'R',
    defaultMapper = 'keyboard',
    secondaryMapper = 'PAD_DIGITALBUTTONANY',
    secondaryKey = 'RUP_INDEX',           -- Triangle/Y, matches the shown icon
    disabled = true,
    onPressed = function()
        if promptedVehicle and getIsPickable(promptedVehicle) then
            slimJim(promptedVehicle)
        end
    end,
    onReleased = function()
        if isSlimJimming then exports.vice_hud:ReleaseLockpickCheck() end
    end,
})

local smashKeybind = lib.addKeybind({
    name = 'slimjim_smashwindow',
    description = locale('target.smash_window'),
    defaultKey = 'F',
    defaultMapper = 'keyboard',
    -- Previously had no secondary binding at all. On a controller, Smash
    -- Window's icon (Circle) did nothing, full stop. RRIGHT_INDEX/Circle was
    -- free to take: it is the button Slim Jim's OWN old (wrong) binding used,
    -- moved here to where the shown icon actually says it should be.
    secondaryMapper = 'PAD_DIGITALBUTTONANY',
    secondaryKey = 'RRIGHT_INDEX',        -- Circle/B, matches the shown icon
    disabled = true,
    onPressed = function()
        if promptedVehicle and GetIsSmashable(promptedVehicle) then
            SmashWindow(promptedVehicle)
        end
    end,
})

-- ---- proximity/aim detection, and the combined prompt ---------------------
-- lib.getClosestVehicle mirrors exactly what LockpickDoor already uses to
-- find "the vehicle whose door I'm at" without needing ox_target at all.

CreateThread(function()
    while true do
        Wait(250)
        local vehicle = nil
        if not cache.vehicle and not isSlimJimming then
            local pedCoords = GetEntityCoords(cache.ped)
            local candidate = lib.getClosestVehicle(pedCoords, sjConfig.maxDistance * 2, false)
            if candidate and GetIsCloseToVehicleDoor(candidate, sjConfig.maxDistance)
                and (getIsPickable(candidate) or GetIsSmashable(candidate)) then
                vehicle = candidate
            end
        end

        if vehicle ~= promptedVehicle then
            promptedVehicle = vehicle
            if vehicle then
                local options = {}
                -- `key` is the keybind's OWN hash (ox_lib computes it as
                -- joaat('+'..name) | 0x80000000, same value GetControlInstructional
                -- Button resolves against for a custom RegisterKeyMapping),
                -- not a hand-picked icon name. vice_hud resolves the live glyph
                -- from this, so it can never show an icon this binding disagrees
                -- with. See the fix note on the keybinds above.
                if getIsPickable(vehicle) then
                    options[#options + 1] = { label = locale('target.slim_jim'), key = slimJimKeybind.hash }
                end
                if GetIsSmashable(vehicle) then
                    options[#options + 1] = { label = locale('target.smash_window'), key = smashKeybind.hash }
                end
                exports.vice_hud:ShowWorldActions(options)
                slimJimKeybind:disable(not getIsPickable(vehicle))
                smashKeybind:disable(not GetIsSmashable(vehicle))
            else
                exports.vice_hud:HideWorldActions()
                slimJimKeybind:disable(true)
                smashKeybind:disable(true)
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if promptedVehicle then exports.vice_hud:HideWorldActions() end
    if isSlimJimming then exports.vice_hud:CancelLockpickCheck() end
end)
