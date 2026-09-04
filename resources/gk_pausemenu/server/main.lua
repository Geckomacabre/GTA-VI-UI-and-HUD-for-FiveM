--[[
    Keeps a lightweight connected-player list for the Players tab. gk_*
    resources use ox_lib rather than qbx_core (see gk_armwrestle), so this
    doesn't reach for qbx_core's player object -- just id + name, which is
    all the Players tab shows.

    Used to also bridge qbx_garages' server-only GetGarages export to
    clients, back when the Map tab's Locations panel was a hand-typed
    Config.Locations list that needed garages added in separately (see
    client/blips.lua's header comment for the whole history). Now that the
    Locations panel scans every real native blip directly, qbx_garages'
    own blips show up automatically like any other resource's -- nothing
    left here to bridge.
]]

local function currentPlayers()
    local list = {}
    for _, id in ipairs(GetPlayers()) do
        list[#list + 1] = { id = tonumber(id), name = GetPlayerName(id) }
    end
    return list
end

RegisterServerEvent('gk_pausemenu:server:requestPlayers', function()
    local src = source
    TriggerClientEvent('gk_pausemenu:client:setPlayers', src, currentPlayers())
end)

AddEventHandler('playerJoining', function()
    TriggerClientEvent('gk_pausemenu:client:setPlayers', -1, currentPlayers())
end)

AddEventHandler('playerDropped', function()
    -- Runs before the player is removed from GetPlayers() on some builds, so
    -- defer one tick to make sure the list we broadcast is already correct.
    SetTimeout(0, function()
        TriggerClientEvent('gk_pausemenu:client:setPlayers', -1, currentPlayers())
    end)
end)
