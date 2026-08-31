local config = require 'config.server'

---@param src number
---@return number?
local function getClosestPlayer(src)
    local playerCoords = GetEntityCoords(GetPlayerPed(src))
    local nearbyPlayers = lib.getNearbyPlayers(playerCoords, config.distanceToHandKeys)
    local closestPlayer
    local closestDistance = config.distanceToHandKeys
    for i = 1, #nearbyPlayers do
        local nearbyPlayer = nearbyPlayers[i]
        if nearbyPlayer.id ~= src then
            local distance = #(nearbyPlayer.coords - playerCoords)
            if not distance or distance <= closestDistance then
                closestPlayer = nearbyPlayer
                closestDistance = distance
            end
        end
    end
    return closestPlayer?.id
end

---@param source number
---@param target? number
---@param enforceSrcHasKeys boolean if true, source must have keys to transfer
local function transferKeys(source, target, enforceSrcHasKeys)
    local playerPed = GetPlayerPed(source)
    local playerCoords = GetEntityCoords(playerPed)
    local vehicle = lib.getClosestVehicle(playerCoords, 5.0)
    if not vehicle then
        exports.qbx_core:Notify(source, locale('notify.vehicle_not_near'), 'error')
        return
    end
    if enforceSrcHasKeys and not HasKeys(source, vehicle) then
        exports.qbx_core:Notify(source, locale('notify.no_keys'), 'error')
        return
    end
    if target and type(target) == 'number' then
        GiveKeys(target, vehicle)
    elseif GetVehiclePedIsIn(playerPed, false) == vehicle then -- Give keys to everyone in vehicle
        for i = -1, 7 do
            local ped = GetPedInVehicleSeat(vehicle, i)
            local serverId = ped and NetworkGetEntityOwner(ped)
            if serverId and serverId ~= source then
                GiveKeys(serverId, vehicle)
            end
        end

        exports.qbx_core:Notify(source, locale('notify.gave_keys'))
    else -- Give keys to closest player
        local closestPlayer = getClosestPlayer(source)
        if closestPlayer then
            GiveKeys(closestPlayer, vehicle)
            exports.qbx_core:Notify(source, locale('notify.gave_keys'))
        else
            exports.qbx_core:Notify(source, locale('notify.not_near'), 'error')
        end
    end
end

lib.addCommand(locale('addcom.givekeys'), {
    help = locale('addcom.givekeys_help'),
    params = {
        {
            name = locale('addcom.givekeys_id'),
            type = 'playerId',
            help = locale('addcom.givekeys_id_help'),
            optional = true
        },
    },
    restricted = false,
}, function (source, args)
    transferKeys(source, args[locale('addcom.givekeys_id')], true)
end)

lib.addCommand(locale('addcom.addkeys'), {
    help = locale('addcom.addkeys_help'),
    params = {
        {
            name = locale('addcom.addkeys_id'),
            type = 'playerId',
            help = locale('addcom.addkeys_id_help'),
            optional = true,
        },
    },
    restricted = 'group.admin',
}, function (source, args)
    local playerId = args[locale('addcom.addkeys_id')]
    transferKeys(source, playerId, false)
end)
