local config = require 'config.server'

---@param veh number
---@param state string
local function setLockState(veh, state)
	if type(state) ~= 'string' or not DoesEntityExist(veh) then return end
    local vehicleConfig = GetVehicleConfig(veh)
    if vehicleConfig.noLock or vehicleConfig.shared then return end
    Entity(veh).state:set('doorslockstate', state == 'lock' and 2 or 1, true)
end
exports('SetLockState', setLockState)

lib.callback.register('qbx_vehiclekeys:server:findKeys', function(source, netId)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if math.random() <= GetVehicleConfig(vehicle).findKeysChance then
        GiveKeys(source, vehicle)
        return true
    end
end)

lib.callback.register('qbx_vehiclekeys:server:carjack', function(source, netId, weaponTypeGroup)
    local chance = config.carjackChance[weaponTypeGroup] or 0.5
    if math.random() <= chance then
        local vehicle = NetworkGetEntityFromNetworkId(netId)
        GiveKeys(source, vehicle)
        setLockState(vehicle, 'unlock')
        return true
    end
end)

RegisterNetEvent('qbx_vehiclekeys:server:playerEnteredVehicleWithEngineOn', function(netId)
    local src = source
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not GetIsVehicleEngineRunning(vehicle) then return end
    GiveKeys(src, vehicle)
end)

---TODO: secure this event
RegisterNetEvent('qbx_vehiclekeys:server:tookKeys', function(netId)
    GiveKeys(source, NetworkGetEntityFromNetworkId(netId))
end)

---TODO: secure this event
RegisterNetEvent('qbx_vehiclekeys:server:hotwiredVehicle', function(netId)
    GiveKeys(source, NetworkGetEntityFromNetworkId(netId))
end)

---Upstate Mafia: a player put a locked vehicle's driver window through
---(see client/smashwindow.lua). The client only reports it; this handler decides
---whether it's plausible, unlocks the doors, mirrors the broken glass to everyone
---else, and takes the honor hit.
RegisterNetEvent('qbx_vehiclekeys:server:smashedWindow', function(netId)
    local src = source
    if type(netId) ~= 'number' then return end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    local vehicleConfig = GetVehicleConfig(vehicle)
    if vehicleConfig.noLock or vehicleConfig.shared or vehicleConfig.windowSmashImmune then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    if #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > 10.0 then return end

    setLockState(vehicle, 'unlock')
    TriggerClientEvent('qbx_vehiclekeys:client:windowSmashed', -1, netId)

    -- Honor: breaking into someone else's car is a straightforward crime against
    -- a person. Amount tuned in qbx_honor/config.lua (Config.Hooks.window_smash).
    pcall(function() exports.qbx_honor:ApplyHook(src, 'window_smash') end)
end)

RegisterNetEvent('qb-vehiclekeys:server:breakLockpick', function(itemName)
    if not (itemName == 'lockpick' or itemName == 'advancedlockpick') then return end
    exports.ox_inventory:RemoveItem(source, itemName, 1)
end)

---A player worked a locked vehicle's door with a Slim Jim (see
---client/slimjim.lua) and won vice_hud's lockpick check. Deliberately NOT
---routed through the generic qb-vehiclekeys:server:setVehLockState above.
---That event does no validation at all (any client could unlock any
---vehicle by firing it), which is fine for the legitimate uses it already
---has and not fine for a theft outcome. Mirrors smashedWindow's own
---handler immediately above almost exactly, distance check and honor hook
---included; the only real difference is there is no glass to mirror to
---other clients here.
RegisterNetEvent('qbx_vehiclekeys:server:slimJimmed', function(netId)
    local src = source
    if type(netId) ~= 'number' then return end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    local vehicleConfig = GetVehicleConfig(vehicle)
    if vehicleConfig.noLock or vehicleConfig.shared or vehicleConfig.lockpickImmune then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    if #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > 10.0 then return end

    setLockState(vehicle, 'unlock')

    -- Reuses window_smash's own hook rather than a dedicated slim_jim entry,
    -- see the reasoning in config/client.lua's slimJim block: both are
    -- the same act, illegally entering someone else's vehicle.
    pcall(function() exports.qbx_honor:ApplyHook(src, 'window_smash') end)
end)

RegisterNetEvent('qb-vehiclekeys:server:setVehLockState', function(netId, state)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
	if type(state) ~= 'number' or not DoesEntityExist(vehicle) then return end
    if state == 2 then state = 'lock' else state = 'unlock' end
	setLockState(vehicle, state)
end)
