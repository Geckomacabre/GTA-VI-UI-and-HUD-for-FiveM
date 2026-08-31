local config = require 'config.client'

---Grants keys for job shared vehicles
---@param vehicle number The entity number of the vehicle.
---@return boolean? `true` if the vehicle is shared for a player's job, `nil` otherwise.
function AreKeysJobShared(vehicle)
    local job = QBX.PlayerData.job.name
    local jobInfo = config.sharedKeys[job]

    if not jobInfo or (jobInfo.requireOnDuty and not QBX.PlayerData.job.onduty) then return end

    assert(jobInfo.vehicles, string.format('Vehicles not configured for the %s job.', job))
    return jobInfo.vehicles and jobInfo.vehicles[GetEntityModel(vehicle)] or jobInfo.classes and jobInfo.classes[GetVehicleClass(vehicle)]
end

---Checks if player has vehicle keys
---@param vehicle number
---@return boolean `true` if player has vehicle keys, `false` otherwise.
function HasKeys(vehicle)
    vehicle = vehicle or cache.vehicle
    if not vehicle then return false end
    local keysList = LocalPlayer.state.keysList
    if keysList then
        local sessionId = Entity(vehicle).state.sessionId
        if keysList[sessionId] then
            return true
        end
    end

    local owner = Entity(vehicle).state.owner
    if owner and QBX.PlayerData.citizenid == owner then
        lib.callback.await('qbx_vehiclekeys:server:giveKeys', false, VehToNet(vehicle))
        return true
    end

    return false
end

exports('HasKeys', HasKeys)

---Checks if player has vehicle keys of or access to the vehicle is provided as part of his job.
---@param vehicle number The entity number of the vehicle.
---@return boolean? `true` if player has access to the vehicle, `nil` otherwise.
function GetIsVehicleAccessible(vehicle)
    return HasKeys(vehicle) or AreKeysJobShared(vehicle)
end

local alertSend = false --Variable strictly related to sendPoliceAlertAttempt, not used elsewhere
function SendPoliceAlertAttempt(crime, vehicle)
    if alertSend then return end
    alertSend = true

    local hoursOffset = (24 + GetClockHours() - config.policeAlertNightStartHour) % 24; --Hour from the start of the night hours
    local chance = hoursOffset > config.policeAlertNightDuration
        and config.policeAlertChance
        or config.policeNightAlertChance

    if math.random() <= chance then
        config.alertPolice(crime, vehicle)
    end

    SetTimeout(config.alertCooldown, function()
        alertSend = false
    end)
end

---Gets bone coords
---@param entity number The entity index.
---@param boneName string The entity bone name.
---@return vector3 `Bone coords` if exists, `entity coords` otherwise.
local function getBoneCoords(entity, boneName)
    local boneIndex = GetEntityBoneIndexByName(entity, boneName)

    return boneIndex ~= -1
        and GetWorldPositionOfEntityBone(entity, boneIndex)
        or GetEntityCoords(entity)
end

---Checks if any of the bones are close enough to the coords
---@param coords vector3
---@param entity number
---@param bones table
---@param maxDistance number
---@return boolean? `true` if bone exists, `nil` otherwise.
local function getIsCloseToAnyBone(coords, entity, bones, maxDistance)
    for i = 1, #bones do
        local boneCoords = getBoneCoords(entity, bones[i])
        if #(coords - boneCoords) < maxDistance then
            return true
        end
    end
end

local doorBones = {'door_dside_f', 'door_dside_r', 'door_pside_f', 'door_pside_r'}

---Checking whether the character is close enough to the vehicle driver door.
---@param vehicle number The entity number of the vehicle.
---@param maxDistance number The max distance to check.
---@return boolean? `true` if the player ped is next to an open vehicle, `nil` otherwise.
local function getIsVehicleInRange(vehicle, maxDistance)
    local vehicles = GetGamePool('CVehicle')
    local pedCoords = GetEntityCoords(cache.ped)
    for i = 1, #vehicles do
        local v = vehicles[i]
        if not cache.vehicle or v ~= cache.vehicle then
            if vehicle == v and getIsCloseToAnyBone(pedCoords, vehicle, doorBones, maxDistance) then
                return true
            end
        end
    end
end

---Checks whether the player ped is standing close enough to one of a vehicle's
---door bones. Exposed for client/smashwindow.lua, which needs the same
---"am I actually at the door" test LockpickDoor does.
---@param vehicle number The entity number of the vehicle.
---@param maxDistance number
---@return boolean
function GetIsCloseToVehicleDoor(vehicle, maxDistance)
    return getIsCloseToAnyBone(GetEntityCoords(cache.ped), vehicle, doorBones, maxDistance) or false
end

---Chance to destroy lockpick
---@param isAdvancedLockedpick any
---@param vehicle number
local function breakLockpick(isAdvancedLockedpick, vehicle)
    local chance = math.random()
    local vehicleConfig = GetVehicleConfig(vehicle)
    if isAdvancedLockedpick then -- there is no benefit to using an advanced tool in the default configuration.
        if chance <= vehicleConfig.removeAdvancedLockpickChance then
            TriggerServerEvent("qb-vehiclekeys:server:breakLockpick", "advancedlockpick")
        end
    else
        if chance <= vehicleConfig.removeNormalLockpickChance then
            TriggerServerEvent("qb-vehiclekeys:server:breakLockpick", "lockpick")
        end
    end
end

---Will be executed when the lock opening is successful.
---@param vehicle number The entity number of the vehicle.
local function lockpickSuccessCallback(vehicle)
    TriggerServerEvent('hud:server:GainStress', math.random(1, 4))
    exports.qbx_core:Notify(locale("notify.vehicle_lockedpick"), 'success')
    TriggerServerEvent('qb-vehiclekeys:server:setVehLockState', NetworkGetNetworkIdFromEntity(vehicle), 1)
end

---Operations done after the LockpickDoor quickevent done.
---@param vehicle number The entity number of the vehicle.
---@param isAdvancedLockedpick boolean Determines whether an advanced lockpick was used.
---@param isSuccess boolean? Determines whether the lock has been successfully opened.
local function lockpickCallback(vehicle, isAdvancedLockedpick, isSuccess)
    if isSuccess then
        lockpickSuccessCallback(vehicle)
    else -- if player fails quickevent
        SendPoliceAlertAttempt('carjack', vehicle)
        SetVehicleAlarm(vehicle, false)
        SetVehicleAlarmTimeLeft(vehicle, config.vehicleAlarmDuration)
        TriggerServerEvent('hud:server:GainStress', math.random(1, 4))
        exports.qbx_core:Notify(locale('notify.failed_lockedpick'), 'error')
    end

    breakLockpick(isAdvancedLockedpick, vehicle)
end

local islockpickingProcessLocked = false -- lock flag
---Lockpicking quickevent.
---@param isAdvancedLockedpick boolean Determines whether an advanced lockpick was used
---@param maxDistance number? The max distance to check.
---@param customChallenge boolean? lockpick challenge
function LockpickDoor(isAdvancedLockedpick, maxDistance, customChallenge)
    maxDistance = maxDistance or 2
    local pedCoords = GetEntityCoords(cache.ped)
    local vehicle = lib.getClosestVehicle(pedCoords, maxDistance * 2, false) -- The difference between the door and the center of the vehicle

    if not vehicle then return end

    local isDriverSeatFree = IsVehicleSeatFree(vehicle, -1)

    if GetVehicleDoorLockStatus(vehicle) < 2 then exports.qbx_core:Notify(locale('notify.vehicle_is_unlocked'), 'error') return end

    --- player may attempt to open the lock if:
    if not isDriverSeatFree -- no one in the driver's seat
        or not getIsCloseToAnyBone(pedCoords, vehicle, doorBones, maxDistance) -- the player's ped is close enough to the driver's door
        or GetVehicleConfig(vehicle).lockpickImmune
    then return end

    local skillCheckConfig = config.skillCheck[isAdvancedLockedpick and 'advancedLockpick' or 'lockpick']

    skillCheckConfig = skillCheckConfig.model[GetEntityModel(vehicle)]
        or skillCheckConfig.class[GetVehicleClass(vehicle)]
        or skillCheckConfig.default
    if not next(skillCheckConfig) then return end

    if islockpickingProcessLocked then return end -- start of the critical section
    islockpickingProcessLocked = true -- one call per player at a time

    CreateThread(function()
        local anim = config.anims.lockpick.model[GetEntityModel(vehicle)]
            or config.anims.lockpick.class[GetVehicleClass(vehicle)]
            or config.anims.lockpick.default
        lib.playAnim(cache.ped, anim.dict, anim.clip, 3.0, 3.0, -1, 16, 0, false, false, false) -- lock opening animation
        local isSuccess = customChallenge or lib.skillCheck(skillCheckConfig.difficulty, skillCheckConfig.inputs)

        if getIsVehicleInRange(vehicle, maxDistance) then -- the action will be aborted if the opened vehicle is too far.
            lockpickCallback(vehicle, isAdvancedLockedpick, isSuccess)
        end

        Wait(config.lockpickCooldown)
        islockpickingProcessLocked = false -- end of the critical section
    end)
end

---Will be executed when the lock opening is successful.
---@param vehicle number The entity number of the vehicle.
local function hotwireSuccessCallback(vehicle)
    TriggerServerEvent('qbx_vehiclekeys:server:hotwiredVehicle', VehToNet(vehicle))
end

---Operations done after the LockpickDoor quickevent done.
---@param vehicle number The entity number of the vehicle.
---@param isAdvancedLockedpick boolean Determines whether an advanced lockpick was used.
---@param isSuccess boolean? Determines whether the lock has been successfully opened.
local function hotwireCallback(vehicle, isAdvancedLockedpick, isSuccess)
    if isSuccess then
        hotwireSuccessCallback(vehicle)
    else -- if player fails quickevent
        SendPoliceAlertAttempt('carjack', vehicle)
        TriggerServerEvent('hud:server:GainStress', math.random(1, 4))
        exports.qbx_core:Notify(locale('notify.failed_lockedpick'), 'error')
    end

    breakLockpick(isAdvancedLockedpick, vehicle)
end

local isHotwiringProcessLocked = false -- lock flag
---Hotwiring with a tool quickevent.
---@param vehicle number The entity number of the vehicle.
---@param isAdvancedLockedpick boolean Determines whether an advanced lockpick was used
---@param customChallenge boolean? lockpick challenge
function Hotwire(vehicle, isAdvancedLockedpick, customChallenge)
    if cache.seat ~= -1 or GetIsVehicleAccessible(vehicle) then return end
    local skillCheckConfig = config.skillCheck[isAdvancedLockedpick and 'advancedHotwire' or 'hotwire']

    skillCheckConfig = skillCheckConfig.model[GetEntityModel(vehicle)]
        or skillCheckConfig.class[GetVehicleClass(vehicle)]
        or skillCheckConfig.default
    if not next(skillCheckConfig) then return end

    if isHotwiringProcessLocked then return end -- start of the critical section
    isHotwiringProcessLocked = true -- one call per player at a time

    CreateThread(function()
        local anim = config.anims.hotwire.model[GetEntityModel(vehicle)]
        or config.anims.hotwire.class[GetVehicleClass(vehicle)]
        or config.anims.hotwire.default
        lib.playAnim(cache.ped, anim.dict, anim.clip, 3.0, 3.0, -1, 16, 0, false, false, false) -- lock opening animation
        local isSuccess = customChallenge or lib.skillCheck(skillCheckConfig.difficulty, skillCheckConfig.inputs)

        hotwireCallback(vehicle, isAdvancedLockedpick, isSuccess)

        Wait(config.hotwireCooldown)
        isHotwiringProcessLocked = false -- end of the critical section
    end)
end