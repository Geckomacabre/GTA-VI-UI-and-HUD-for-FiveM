-- ============================================================================
-- qbx_vehiclekeys / client / smashwindow
-- Upstate Mafia addition.
--
-- Third-eye the driver door of a locked vehicle you have no keys for and you
-- get a "Smash Window" option. Going ahead with it unlocks the doors, so the
-- resource's existing theft path (search for keys with [H], or a lockpick via
-- `lockpicks:UseLockpick`) takes over from there. This file deliberately does
-- not hand out keys or start the engine itself.
--
-- No tool is required. The cost is time, stress, a police alert and honor: how
-- long the smash takes and how likely the alert is are both scaled by the
-- player's qbx_honor tier (see config.client.smashWindow.honor). If qbx_honor
-- isn't running, everyone is treated as neutral and no honor is deducted.
-- ============================================================================

local config = require 'config.client'
local smashConfig = config.smashWindow

local isSmashing = false

---@param vehicle number The entity number of the vehicle.
---@return boolean `true` if this vehicle can currently have its window smashed.
-- Global for the same reason SmashWindow is: client/slimjim.lua's combined
-- prompt needs to ask this before offering the option, not just ox_target.
function GetIsSmashable(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    if cache.vehicle then return false end -- already sat in something
    if GetVehicleDoorLockStatus(vehicle) < 2 then return false end -- not locked
    if not IsVehicleSeatFree(vehicle, -1) then return false end -- someone is in the driver's seat
    if not IsVehicleWindowIntact(vehicle, 0) then return false end -- already put through
    if GetIsVehicleAccessible(vehicle) then return false end -- we have keys / job access

    local vehicleConfig = GetVehicleConfig(vehicle)
    if vehicleConfig.noLock or vehicleConfig.shared or vehicleConfig.windowSmashImmune then return false end

    -- No proximity test here: ox_target has already gated on distance and on the
    -- door bone before it calls this.
    return true
end

---Resolves the local player's honor tier into the tuning table for it.
---Falls back to the neutral tier whenever qbx_honor is absent or unreadable,
---so this resource never hard-depends on it.
---@return {durationMultiplier: number, alertChanceMultiplier: number} tierConfig
---@return 'angel'|'devil'|nil tier
local function getHonorTuning()
    if GetResourceState('qbx_honor') ~= 'started' then
        return smashConfig.honor.neutral, nil
    end

    local ok, honor = pcall(function() return exports.qbx_honor:GetHonor() end)
    if not ok or type(honor) ~= 'number' then
        return smashConfig.honor.neutral, nil
    end

    local tierOk, tier = pcall(function() return exports.qbx_honor:GetBadgeTier(honor) end)
    if not tierOk then tier = nil end

    return smashConfig.honor[tier or 'neutral'] or smashConfig.honor.neutral, tier
end

---@param vehicle number The entity number of the vehicle.
-- Global (not local) rather than the usual convention in this file: the
-- Slim Jim option this steps aside for below (see the ox_target guard just
-- below) is registered from a separate file, client/slimjim.lua, and calls
-- straight into this one function so the two options share one theft flow
-- rather than each reimplementing the smash.
function SmashWindow(vehicle)
    if isSmashing then return end
    isSmashing = true

    local tuning = getHonorTuning()
    local anim = config.anims.smashWindow.model[GetEntityModel(vehicle)]
        or config.anims.smashWindow.class[GetVehicleClass(vehicle)]
        or config.anims.smashWindow.default

    local isSuccess = lib.progressCircle({
        duration = math.floor(smashConfig.baseDurationMs * (tuning.durationMultiplier or 1.0)),
        label = locale('progress.smashing_window'),
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        anim = next(anim) and anim or nil,
        disable = {
            move = true,
            car = true,
            combat = true,
        },
    })

    -- Aborted, or the vehicle drove off / despawned mid-swing.
    if not isSuccess
        or not DoesEntityExist(vehicle)
        or not GetIsCloseToVehicleDoor(vehicle, smashConfig.maxDistance)
    then
        isSmashing = false
        return
    end

    SmashVehicleWindow(vehicle, 0) -- 0 = front driver-side window
    SetVehicleAlarm(vehicle, true)
    SetVehicleAlarmTimeLeft(vehicle, smashConfig.alarmDurationMs)
    StartVehicleAlarm(vehicle)

    TriggerServerEvent('qbx_vehiclekeys:server:smashedWindow', NetworkGetNetworkIdFromEntity(vehicle))
    TriggerServerEvent('hud:server:GainStress', math.random(smashConfig.stressGain[1], smashConfig.stressGain[2]))

    -- Rolled on top of SendPoliceAlertAttempt's own chance, so the honor tier can
    -- only ever pull the odds down from this resource's normal baseline.
    if math.random() <= (tuning.alertChanceMultiplier or 1.0) then
        SendPoliceAlertAttempt(locale('info.crime_smash'), vehicle)
    end

    exports.qbx_core:Notify(locale('notify.window_smashed'), 'success')
    isSmashing = false
end

-- An ox_target option on the driver door, not a dialog.
--
-- This started as a centred alertDialog fired the moment you tried a locked
-- door. That is a full-screen modal for a small, optional action - it stole
-- focus, interrupted whatever you were doing, and needed its own per-vehicle
-- cooldown so holding the enter key could not spam it. The target eye already
-- solves all of that: it only appears when you deliberately look at the door,
-- costs nothing when ignored, and needs no polling loop.
--
-- Steps aside when vice_hud is running: client/slimjim.lua registers its own
-- combined "Slim Jim / Smash Window" prompt in that case (both options
-- together, GTA6-styled), calling straight back into SmashWindow above for
-- the smash itself, so this ox_target registration would otherwise be a
-- second, redundant prompt stacked on top of that one. Nothing about
-- SmashWindow's own behaviour changes either way; this only decides which
-- front end offers it.
if smashConfig.enable and GetResourceState('ox_target') == 'started' and GetResourceState('vice_hud') ~= 'started' then
    exports.ox_target:addGlobalVehicle({
        {
            name = 'qbx_vehiclekeys:smashwindow',
            label = locale('target.smash_window'),
            icon = 'fas fa-hand-fist',
            distance = smashConfig.maxDistance,
            -- Restricted to the driver-side door bones, so you cannot smash your
            -- way in by aiming at the boot.
            bones = smashConfig.targetBones,
            canInteract = function(entity)
                return GetIsSmashable(entity)
            end,
            onSelect = function(data)
                SmashWindow(data.entity)
            end,
        }
    })
elseif smashConfig.enable and GetResourceState('vice_hud') ~= 'started' then
    -- Loud rather than silent: without this the option simply never appears and
    -- there is nothing on screen or in the log to say why.
    lib.print.warn('window smashing is enabled but ox_target is not started - the option will not appear')
end

---Mirrors a smash onto every other client, since SmashVehicleWindow is local.
RegisterNetEvent('qbx_vehiclekeys:client:windowSmashed', function(netId)
    if not NetworkDoesNetworkIdExist(netId) then return end

    local vehicle = NetToVeh(netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    SmashVehicleWindow(vehicle, 0)
end)
