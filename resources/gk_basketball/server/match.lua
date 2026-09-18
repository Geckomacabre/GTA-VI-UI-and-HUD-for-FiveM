--[[
    Match state machine, one match per court.

        lobby  -> players sign up, no clock, baskets don't count
        countdown -> start called, tip-off pending
        live   -> clock running, baskets count
        ended  -> final score on screen, then back to lobby

    The server owns the score. Clients only report "the ball went through this rim",
    and even that is range-checked and rate-limited here.
]]

local matches   = {}    -- [courtId] = match
local playerOf  = {}    -- [src] = courtId
local lastScore = {}    -- [src] = ms, anti double-count

local function newMatch()
    return {
        state   = 'lobby',
        players = {},      -- [id] = { team, points, name, ai?, driver? }
        score   = { home = 0, away = 0 },
        clock   = nil,
        countdown = nil,
        result  = nil,
        nextAiId = -1,     -- NPCs use negative ids, which can never collide with a
                           -- real server id, so they slot into `players` unchanged
    }
end

--- Removes every NPC from a court and tells the drivers to delete the peds.
local function stopAI(courtId)
    local match = matches[courtId]
    if not match then return end

    for id, player in pairs(match.players) do
        if player.ai then
            if player.driver then
                TriggerClientEvent('gk_basketball:stopAI', player.driver, id)
            end
            match.players[id] = nil
        end
    end
end

--- True when a court has nobody real left on it.
local function humanCount(match)
    local n = 0
    for _, player in pairs(match.players) do
        if not player.ai then n = n + 1 end
    end
    return n
end

local function getMatch(courtId)
    if not BB.courts[courtId] then return end

    if not matches[courtId] then
        matches[courtId] = newMatch()
    end

    return matches[courtId]
end

local function teamCount(match, team)
    local n = 0
    for _, player in pairs(match.players) do
        if player.team == team then n = n + 1 end
    end
    return n
end

local function playerCount(match)
    local n = 0
    for _ in pairs(match.players) do n = n + 1 end
    return n
end

--- Flattens the match into the shape the HUD expects.
local function payload(match)
    local players = {}

    for src, player in pairs(match.players) do
        players[#players + 1] = {
            id     = src,
            name   = player.name,
            team   = player.team,
            points = player.points,
        }
    end

    table.sort(players, function(a, b)
        if a.points == b.points then return a.name < b.name end
        return a.points > b.points
    end)

    return {
        state     = match.state,
        score     = match.score,
        clock     = match.clock,
        countdown = match.countdown,
        players   = players,
        result    = match.result,
    }
end

local function sync(courtId)
    local match = matches[courtId]
    if not match then return end

    local data = payload(match)

    for src, player in pairs(match.players) do
        if not player.ai then
            TriggerClientEvent('gk_basketball:syncMatch', src, courtId, data)
        end
    end
end

local function announce(courtId, message, kind)
    local match = matches[courtId]
    if not match then return end

    for src, player in pairs(match.players) do
        if not player.ai then
            TriggerClientEvent('gk_basketball:notify', src, message, kind or 'inform')
        end
    end
end

--------------------------------------------------------------------------------
-- Joining and leaving
--------------------------------------------------------------------------------

local function removePlayer(src, reason)
    local courtId = playerOf[src]
    if not courtId then return end

    local match = matches[courtId]
    playerOf[src] = nil

    -- Covers leaving deliberately, wandering off court, and being dropped — playerDropped
    -- comes through here too, which is what stops buckets leaking.
    BB.leaveInstance(src)

    if match then
        match.players[src] = nil
    end

    TriggerClientEvent('gk_basketball:syncMatch', src, nil, nil)

    if reason then
        TriggerClientEvent('gk_basketball:notify', src, reason, 'inform')
    end

    if match then
        -- Retire any NPC this player was driving; nobody else can run it.
        for id, player in pairs(match.players) do
            if player.ai and player.driver == src then
                match.players[id] = nil
            end
        end

        -- Everyone real walked off: bin the match so the next group starts clean.
        if humanCount(match) == 0 then
            stopAI(courtId)
            matches[courtId] = nil
        else
            sync(courtId)
        end
    end
end

RegisterNetEvent('gk_basketball:join', function(courtId)
    local source = source

    if playerOf[source] then
        TriggerClientEvent('gk_basketball:notify', source, Config.Text.already_in, 'error')
        return
    end

    local match = getMatch(courtId)
    if not match then return end

    if match.state == 'live' or match.state == 'countdown' then
        -- Late joiners are allowed, they just start on 0.
    end

    -- Put them on the smaller side.
    local home, away = teamCount(match, 'home'), teamCount(match, 'away')
    local team = home <= away and 'home' or 'away'

    if math.min(home, away) >= Config.Match.maxPerTeam then
        TriggerClientEvent('gk_basketball:notify', source, Config.Text.court_full, 'error')
        return
    end

    match.players[source] = {
        team   = team,
        points = 0,
        name   = GetPlayerName(source) or ('Player ' .. source),
    }
    playerOf[source] = courtId

    -- Into the court's own instance. Everyone on a court ends up in the same bucket
    -- because it is derived from the court, not from who arrived first.
    BB.enterInstance(source, courtId)

    TriggerClientEvent('gk_basketball:notify', source,
        Config.Text.joined:format(Config.Match.teams[team].label), 'success')

    sync(courtId)
end)

RegisterNetEvent('gk_basketball:leave', function()
    removePlayer(source, Config.Text.left)
end)

--- Adds an NPC to the court on the smaller team.
RegisterNetEvent('gk_basketball:addAI', function(courtId, difficultyId)
    local source = source

    if not Config.AI.enabled then return end
    if playerOf[source] ~= courtId then return end

    local match = matches[courtId]
    if not match then return end

    local bots = 0
    for _, player in pairs(match.players) do
        if player.ai then bots = bots + 1 end
    end

    if bots >= Config.AI.maxPerCourt then
        TriggerClientEvent('gk_basketball:notify', source, Config.Text.ai_full, 'error')
        return
    end

    local skill
    for _, entry in ipairs(Config.AI.difficulties) do
        if entry.id == difficultyId then skill = entry break end
    end
    if not skill then return end

    local home, away = teamCount(match, 'home'), teamCount(match, 'away')
    local team = home <= away and 'home' or 'away'

    if math.min(home, away) >= Config.Match.maxPerTeam then
        TriggerClientEvent('gk_basketball:notify', source, Config.Text.court_full, 'error')
        return
    end

    local aiId = match.nextAiId
    match.nextAiId = aiId - 1

    match.players[aiId] = {
        team   = team,
        points = 0,
        name   = skill.name,
        ai     = skill.id,
        driver = source,
    }

    TriggerClientEvent('gk_basketball:startAI', source, aiId, team, skill.id)

    announce(courtId, Config.Text.ai_joined:format(
        skill.name, Config.Match.teams[team].label), 'inform')

    sync(courtId)
end)

-- The driver couldn't spawn the ped, so don't leave a ghost on the scoreboard.
RegisterNetEvent('gk_basketball:aiFailed', function(aiId)
    local source = source
    local courtId = playerOf[source]
    local match = courtId and matches[courtId]

    if not match then return end

    local player = match.players[aiId]
    if player and player.ai and player.driver == source then
        match.players[aiId] = nil
        TriggerClientEvent('gk_basketball:notify', source, Config.Text.ai_failed, 'error')
        sync(courtId)
    end
end)

AddEventHandler('playerDropped', function()
    removePlayer(source)
    lastScore[source] = nil
end)

--------------------------------------------------------------------------------
-- Starting and ending
--------------------------------------------------------------------------------

local function finish(courtId)
    local match = matches[courtId]
    if not match then return end

    local home, away = match.score.home, match.score.away
    local winner = home > away and 'home' or (away > home and 'away' or nil)

    match.state  = 'ended'
    match.clock  = nil
    match.result = { winner = winner, home = home, away = away }

    if winner then
        announce(courtId, Config.Text.match_won:format(
            Config.Match.teams[winner].label, math.max(home, away), math.min(home, away)), 'success')

        if Config.Match.winReward > 0 then
            for src, player in pairs(match.players) do
                if player.team == winner and not player.ai then
                    local ok = pcall(function()
                        exports.ox_inventory:AddItem(src, 'money', Config.Match.winReward)
                    end)
                    if ok then
                        TriggerClientEvent('gk_basketball:notify', src,
                            Config.Text.reward:format(Config.Match.winReward), 'success')
                    end
                end
            end
        end
    else
        announce(courtId, Config.Text.match_draw:format(home, away), 'inform')
    end

    sync(courtId)

    SetTimeout(Config.Match.endScreenTime * 1000, function()
        local current = matches[courtId]
        if not current or current.state ~= 'ended' then return end

        current.state  = 'lobby'
        current.score  = { home = 0, away = 0 }
        current.result = nil
        current.clock  = nil

        for _, player in pairs(current.players) do
            player.points = 0
        end

        sync(courtId)
    end)
end

local function startMatch(src, courtId)
    if playerOf[src] ~= courtId then return end

    local match = matches[courtId]
    if not match or match.state ~= 'lobby' then return end

    if playerCount(match) < Config.Match.minPlayers then
        TriggerClientEvent('gk_basketball:notify', src,
            Config.Text.need_players:format(Config.Match.minPlayers), 'error')
        return
    end

    match.state     = 'countdown'
    match.countdown = Config.Match.countdown
    sync(courtId)
end

RegisterNetEvent('gk_basketball:start', function(courtId)
    startMatch(source, courtId)
end)

--------------------------------------------------------------------------------
-- Scoring
--------------------------------------------------------------------------------

RegisterNetEvent('gk_basketball:scored', function(data)
    local source = source

    if type(data) ~= 'table' then return end

    local hoop = BB.findHoop(data.hoop)
    if not hoop then return end

    local courtId = playerOf[source]
    local match   = courtId and matches[courtId]

    -- A basket reported for an NPC is credited to the NPC, but only if the reporter
    -- really is its driver.
    local scorer, isBot = source, false

    if data.aiId then
        local bot = match and match.players[data.aiId]
        if not bot or not bot.ai or bot.driver ~= source then return end
        scorer, isBot = data.aiId, true
    end

    -- Rate limit per scorer, not per client: one player driving three NPCs would
    -- otherwise have their baskets cancel each other out.
    local now = GetGameTimer()
    if lastScore[scorer] and now - lastScore[scorer] < Config.Scoring.cooldown then return end

    -- Verify a human shooter is actually near the hoop, which stops a spoofed event
    -- from someone on the other side of the map. An NPC's ped only exists on its
    -- driver's client, so there is nothing to check server-side; the driver is
    -- already known-good from the check above.
    if not isBot then
        local ped = GetPlayerPed(source)
        if not ped or ped == 0 then return end

        if #(GetEntityCoords(ped) - BB.vec(hoop.coords)) > Config.Shot.maxRange + 12.0 then
            return
        end
    end

    local points = (data.points == 3) and 3 or 2
    lastScore[scorer] = now

    -- Freeplay, a lobby, or a basket on someone else's court: just flavour, no score.
    if not match or match.state ~= 'live' or hoop.court ~= courtId then
        TriggerClientEvent('gk_basketball:notify', source, Config.Text.scored_self:format(points), 'success')
        TriggerClientEvent('gk_basketball:scoreFlash', source, hoop.id, points, data.clean == true)
        return
    end

    local player = match.players[scorer]
    if not player then return end

    -- Scoring in the basket your own team defends credits the other side.
    local team = player.team
    if hoop.team and hoop.team == player.team then
        team = player.team == 'home' and 'away' or 'home'
    else
        player.points = player.points + points
    end

    match.score[team] = match.score[team] + points

    for src, member in pairs(match.players) do
        if not member.ai then
            TriggerClientEvent('gk_basketball:scoreFlash', src, hoop.id, points, data.clean == true)
        end
    end

    announce(courtId, Config.Text.scored:format(player.name, points), 'success')
    sync(courtId)

    if Config.Match.scoreLimit > 0 and match.score[team] >= Config.Match.scoreLimit then
        finish(courtId)
    end
end)

--------------------------------------------------------------------------------
-- Clock
--------------------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(1000)

        for courtId, match in pairs(matches) do
            local court = BB.courts[courtId]

            -- Drop anyone who wandered off the court.
            if court and (match.state == 'live' or match.state == 'countdown') then
                for src, player in pairs(match.players) do
                    -- NPCs have no ped on the server and never wander off.
                    if not player.ai then
                        local ped = GetPlayerPed(src)
                        if not ped or ped == 0 then
                            removePlayer(src)
                        elseif #(GetEntityCoords(ped) - court.centre) > Config.Match.courtRadius then
                            removePlayer(src, Config.Text.left_court)
                        end
                    end
                end
            end

            match = matches[courtId]

            if match then
                if match.state == 'countdown' then
                    match.countdown = (match.countdown or 0) - 1

                    if match.countdown <= 0 then
                        match.state     = 'live'
                        match.countdown = nil
                        match.clock     = Config.Match.duration > 0 and Config.Match.duration or nil
                        announce(courtId, Config.Text.match_live, 'success')
                    else
                        announce(courtId, Config.Text.match_starting:format(match.countdown))
                    end

                    sync(courtId)

                elseif match.state == 'live' and match.clock then
                    match.clock = match.clock - 1

                    if match.clock <= 0 then
                        match.clock = 0
                        finish(courtId)
                    else
                        sync(courtId)
                    end
                end
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Commands (fallback for anyone without ox_target bound)
--------------------------------------------------------------------------------

RegisterCommand('bball', function(source, args)
    if source == 0 then return end

    local action = (args[1] or ''):lower()

    if action == 'leave' then
        removePlayer(source, Config.Text.left)
    elseif action == 'start' then
        local courtId = playerOf[source]
        if courtId then
            startMatch(source, courtId)
        end
    else
        TriggerClientEvent('gk_basketball:notify', source,
            'Use the court marker to join. /bball start or /bball leave once you are in.', 'inform')
    end
end, false)
