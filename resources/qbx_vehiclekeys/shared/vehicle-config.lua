local config = require 'config.shared'
local VEHICLES = exports.qbx_core:GetVehiclesByHash()

local function findConfigValue(filteredConfig, key, default)
    if filteredConfig.modelConfig?[key] ~= nil then
        return filteredConfig.modelConfig[key]
    elseif filteredConfig.categoryConfig?[key] ~= nil then
        return filteredConfig.categoryConfig[key]
    elseif filteredConfig.classConfig?[key] ~= nil then
        return filteredConfig.classConfig[key]
    elseif filteredConfig.typeConfig?[key] ~= nil then
        return filteredConfig.typeConfig[key]
    elseif filteredConfig.defaultConfig?[key] ~= nil then
        return filteredConfig.defaultConfig[key]
    else
        return default
    end
end

---Gets the vehicle's config
---@param vehicle number
---@return VehicleConfig
function GetVehicleConfig(vehicle)
    assert(vehicle and vehicle ~= 0, 'cannot get the vehicle config for a vehicle that doesn\'t exist')
    local model = GetEntityModel(vehicle)
    local class = IsDuplicityVersion() and exports.qbx_core:GetVehicleClass(model) or GetVehicleClass(vehicle)
    local filteredConfig = {
        modelConfig = config.vehicles.models[model],
        categoryConfig = config.vehicles.categories[VEHICLES[model]?.category],
        classConfig = config.vehicles.classes[class],
        typeConfig = config.vehicles.types[GetVehicleType(vehicle)],
        defaultConfig = config.vehicles.default
    }

    local noLock = findConfigValue(filteredConfig, 'noLock', false)
    local spawnLockedIfParked = noLock and 0.0 or findConfigValue(filteredConfig, 'spawnLockedIfParked', 1.0)
    local spawnLockedIfDriven = noLock and 0.0 or findConfigValue(filteredConfig, 'spawnLockedIfDriven', 1.0)
    local carjackingImmune = findConfigValue(filteredConfig, 'carjackingImmune', false)
    local lockpickImmune = findConfigValue(filteredConfig, 'lockpickImmune', false)
    -- Defaults to lockpickImmune so anything already unpickable stays unopenable
    -- unless a config entry explicitly says otherwise.
    local windowSmashImmune = findConfigValue(filteredConfig, 'windowSmashImmune', nil)
    if windowSmashImmune == nil then windowSmashImmune = lockpickImmune end
    local shared = findConfigValue(filteredConfig, 'shared', false)
    local removeNormalLockpickChance = findConfigValue(filteredConfig, 'removeNormalLockpickChance', 1.0)
    local removeAdvancedLockpickChance = findConfigValue(filteredConfig, 'removeAdvancedLockpickChance', 1.0)
    local findKeysChance = findConfigValue(filteredConfig, 'findKeysChance', 1.0)

    return {
        spawnLockedIfParked = spawnLockedIfParked,
        spawnLockedIfDriven = spawnLockedIfDriven,
        noLock = noLock,
        carjackingImmune = carjackingImmune,
        lockpickImmune = lockpickImmune,
        windowSmashImmune = windowSmashImmune,
        shared = shared,
        removeNormalLockpickChance = removeNormalLockpickChance,
        removeAdvancedLockpickChance = removeAdvancedLockpickChance,
        findKeysChance = findKeysChance,
    }
end