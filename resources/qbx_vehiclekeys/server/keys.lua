local config = require 'config.server'
local debug = GetConvarInt(('%s-debug'):format(GetCurrentResourceName()), 0) == 1

---@alias CitizenId string
---@alias SessionId integer
---@type table<CitizenId, table<SessionId, boolean>>
local loggedOutKeys = {} ---holds key status for some time after player logs out (Prevents frustration by crashing the client)

---@alias LogoutTime integer
---@type table<CitizenId, LogoutTime>
local logedOutTime = {} ---Life timestamp of the keys of a character who has logged out

---Gets Citizen Id based on source
---@param source number ID of the player
---@return string? citizenid The player CitizenID, nil otherwise.
local function getCitizenId(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return end

    return player.PlayerData.citizenid
end

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local src = source
    local citizenId = getCitizenId(src)
    if not citizenId then return end
    if loggedOutKeys[citizenId] then
        Player(src).state:set('keysList', loggedOutKeys[citizenId], true)
        loggedOutKeys[citizenId] = nil
        logedOutTime[citizenId] = nil
    end
end)

local function onPlayerUnload(src)
    local citizenId = getCitizenId(src)
    if not citizenId then return end
    loggedOutKeys[citizenId] = Player(src).state.keysList
    logedOutTime[citizenId] = os.time()
end

RegisterNetEvent('QBCore:Server:OnPlayerUnload', onPlayerUnload)

AddEventHandler('playerDropped', function()
    onPlayerUnload(source)
end)

---Removes old keys from server memory
lib.cron.new('*/'..config.runClearCronMinutes ..' * * * *', function ()
    local time = os.time()
    local seconds = config.runClearCronMinutes * 60
    for citizenId, lifetime in pairs(logedOutTime) do
        if lifetime + seconds < time then
            loggedOutKeys[citizenId] = nil
            logedOutTime[citizenId] = nil
        end
    end
end, {debug = debug})

--- Removing the vehicle keys from the user
---@param source number ID of the player
---@param vehicle number
---@param skipNotification? boolean
function RemoveKeys(source, vehicle, skipNotification)
    local citizenid = getCitizenId(source)
    if not citizenid then return end

    local keys = Player(source).state.keysList
    if not keys then return end

    local sessionId = Entity(vehicle).state.sessionId
    if not keys[sessionId] then return end
    keys[sessionId] = nil

    Player(source).state:set('keysList', keys, true)

    TriggerClientEvent('qbx_vehiclekeys:client:OnLostKeys', source)
    if not skipNotification then
        exports.qbx_core:Notify(source, locale('notify.keys_removed'))
    end

    return true
end

exports('RemoveKeys', RemoveKeys)

---@param source number
---@param vehicle number
---@param skipNotification? boolean
function GiveKeys(source, vehicle, skipNotification)
    local citizenid = getCitizenId(source)
    if not citizenid then return end

    local sessionId = Entity(vehicle).state.sessionId or exports.qbx_core:CreateSessionId(vehicle)
    local keys = Player(source).state.keysList or {}
    if keys[sessionId] then return end

    keys[sessionId] = true

    Player(source).state:set('keysList', keys, true)
    if not skipNotification then
        exports.qbx_core:Notify(source, locale('notify.keys_taken'))
    end
    return true
end

exports('GiveKeys', GiveKeys)

---@param src number
---@param vehicle number
---@return boolean
function HasKeys(src, vehicle)
    local keysList = Player(src).state.keysList
    if keysList then
        local sessionId = Entity(vehicle).state.sessionId
        if keysList[sessionId] then
            return true
        end
    end

    local owner = Entity(vehicle).state.owner
    if owner and getCitizenId(src) == owner then
        GiveKeys(src, vehicle)
        return true
    end

    return false
end

exports('HasKeys', HasKeys)

lib.callback.register('qbx_vehiclekeys:server:giveKeys', function(source, netId)
    GiveKeys(source, NetworkGetEntityFromNetworkId(netId))
end)

AddStateBagChangeHandler('vehicleid', '', function(bagName, _, vehicleId)
    local vehicle = GetEntityFromStateBagName(bagName)
    if not vehicle or vehicle == 0 then return end
    local owner = exports.qbx_vehicles:GetPlayerVehicle(vehicleId)?.citizenid
    if not owner then return end
    Entity(vehicle).state:set('owner', owner, true)
end)
