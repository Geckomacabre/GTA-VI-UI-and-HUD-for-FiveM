--[[
    Keeps a lightweight connected-player list for the Players tab. gk_*
    resources use ox_lib rather than qbx_core (see gk_armwrestle), so this
    doesn't reach for qbx_core's player object -- just id + name, which is
    all the Players tab shows.
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

--[[
    GET_PLAYER_PING is server-only (takes a playerSrc, unlike a client-side
    Player handle) -- see client/main.lua's header comment for the native
    mixup this replaces (a single-player-only native that isn't actually
    exposed in FiveM's Lua environment, confirmed via an in-game "attempt to
    call a nil value" crash). Requested on open and every refresh tick while
    the menu is open, same shape as the Players tab's own request/reply.
]]
RegisterServerEvent('gk_pausemenu:server:requestPing', function()
    local src = source
    TriggerClientEvent('gk_pausemenu:client:setPing', src, GetPlayerPing(src))
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

--[[
    Dashboard's Report card -- posts straight to Discord via a plain incoming
    webhook (no bot token, unlike SY_PauseMenu's avatar-fetch feature this
    doesn't replicate). Config.Report.Webhook left blank just logs to
    console instead of posting, same "unconfigured, don't error" pattern
    other webhook-gated resources on this server use.
]]
RegisterServerEvent('gk_pausemenu:server:report', function(category, subject, text)
    local src = source
    if Config.Report.Webhook == '' then
        print(('[gk_pausemenu] Report from %s (id %s) dropped: Config.Report.Webhook is not set. Subject: %s'):format(GetPlayerName(src), src, subject))
        return
    end

    local embed = {
        {
            title = ('[%s] %s'):format(category or 'Report', subject),
            description = text,
            color = 655104,
            footer = { text = ('%s (id %s)'):format(GetPlayerName(src), src) },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        },
    }

    PerformHttpRequest(Config.Report.Webhook, function() end, 'POST', json.encode({
        username = Config.Report.WebhookName,
        avatar_url = Config.Report.WebhookAvatar ~= '' and Config.Report.WebhookAvatar or nil,
        embeds = embed,
    }), { ['Content-Type'] = 'application/json' })
end)

-- Dashboard's Exit footer icon, confirmed client-side before this ever fires
-- (see client/main.lua's 'exit' NUI callback and html/app.js's confirm
-- modal) -- `source` here is always whoever clicked their own Exit button,
-- this can't be used to drop anyone else.
RegisterServerEvent('gk_pausemenu:server:exit', function()
    DropPlayer(source, 'You have disconnected from the server.')
end)
