--[[
    Ball bookkeeping.

    The server never touches ball physics — it only decides who is allowed to be
    holding one, and keeps the list of loose balls so clients know what they can
    pick up. That gives us the responsiveness of local physics without letting a
    player spawn an armful of basketballs.
]]

local carrying = {}    -- [src] = true
local loose    = {}    -- [netId] = { shooter = src, at = os.time() }

local function giveBall(source)
    carrying[source] = true
    TriggerClientEvent('gk_basketball:giveBall', source)
end

local function dropCarried(source)
    carrying[source] = nil
end

--------------------------------------------------------------------------------
-- Getting a ball
--------------------------------------------------------------------------------

-- ox_inventory item use (client export calls through to here).
RegisterNetEvent('gk_basketball:useItem', function()
    local source = source

    if carrying[source] then
        TriggerClientEvent('gk_basketball:notify', source, Config.Text.hands_full, 'error')
        return
    end

    if not Config.Ball.item then return end

    if not exports.ox_inventory:RemoveItem(source, Config.Ball.item, 1) then
        TriggerClientEvent('gk_basketball:notify', source, Config.Text.no_ball, 'error')
        return
    end

    giveBall(source)
end)

-- Ball rack on a court: no item needed.
RegisterNetEvent('gk_basketball:requestBall', function(courtId)
    local source = source

    if not Config.Match.freeBallsOnCourt then return end
    if carrying[source] then
        TriggerClientEvent('gk_basketball:notify', source, Config.Text.hands_full, 'error')
        return
    end

    local court = BB.courts[courtId]
    if not court then return end

    -- Must actually be standing on the court.
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return end
    if #(GetEntityCoords(ped) - court.centre) > Config.Match.courtRadius then return end

    giveBall(source)
end)

--------------------------------------------------------------------------------
-- Losing a ball
--------------------------------------------------------------------------------

-- Shot, passed or tossed: the ball is now loose and anyone may grab it.
RegisterNetEvent('gk_basketball:ballReleased', function(netId)
    local source = source

    if not carrying[source] then return end
    if type(netId) ~= 'number' then return end

    dropCarried(source)

    local data = { shooter = source, at = os.time() }
    loose[netId] = data

    TriggerClientEvent('gk_basketball:setLooseBall', -1, netId, data)
end)

-- Put away: returns the inventory item if we can.
RegisterNetEvent('gk_basketball:stowBall', function()
    local source = source
    if not carrying[source] then return end

    dropCarried(source)

    if Config.Ball.item then
        exports.ox_inventory:AddItem(source, Config.Ball.item, 1)
    end
end)

lib.callback.register('gk_basketball:pickupBall', function(source, netId)
    if carrying[source] then return false end
    if not loose[netId] then return false end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 then
        loose[netId] = nil
        TriggerClientEvent('gk_basketball:setLooseBall', -1, netId, nil)
        return false
    end

    -- Range check against the real entity position, not a client claim.
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end

    if #(GetEntityCoords(ped) - GetEntityCoords(entity)) > Config.Ball.catchRadius + 1.5 then
        return false
    end

    loose[netId] = nil
    DeleteEntity(entity)
    TriggerClientEvent('gk_basketball:setLooseBall', -1, netId, nil)

    carrying[source] = true
    return true
end)

--------------------------------------------------------------------------------
-- Housekeeping
--------------------------------------------------------------------------------

-- Sweep balls whose entity has gone (client left, stream-out) or that have sat
-- untouched for too long.
CreateThread(function()
    while true do
        Wait(15000)

        local now = os.time()
        local expiry = Config.Ball.despawnAfter

        for netId, data in pairs(loose) do
            local entity = NetworkGetEntityFromNetworkId(netId)
            local gone   = not entity or entity == 0 or not DoesEntityExist(entity)
            local stale  = expiry > 0 and (now - data.at) > expiry

            if gone or stale then
                if not gone then DeleteEntity(entity) end
                loose[netId] = nil
                TriggerClientEvent('gk_basketball:setLooseBall', -1, netId, nil)
            end
        end
    end
end)

AddEventHandler('playerJoining', function()
    TriggerClientEvent('gk_basketball:syncLooseBalls', source, loose)
end)

AddEventHandler('playerDropped', function()
    dropCarried(source)
end)
