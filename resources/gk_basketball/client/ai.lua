--[[
    NPC players.

    Driving model
    -------------
    An NPC is a normal member of the match — it has a team, it appears on the
    scoreboard, and its baskets count. It's driven by the client of whoever added it,
    because a ped needs local ownership to move and animate smoothly. The server just
    records that the slot is an NPC and who drives it.

    Playing model
    -------------
    Pick a spot in range of a hoop, walk there, line up, shoot. The shot reuses the
    same ballistic solver and the same scatter model as a human release, with accuracy
    coming from the difficulty rather than from meter timing — so an NPC misses in
    exactly the same ways a player does, off the rim and in and out.

    It does not defend. See the note in Config.AI.
]]

local bots = {}     -- [aiId] = { ped, team, skill, state, nextAt, ball, hoop }

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function loadModel(model)
    if not IsModelInCdimage(model) then return false end

    RequestModel(model)

    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(model) do
        if GetGameTimer() > deadline then return false end
        Wait(0)
    end

    return true
end

local function skillById(id)
    for _, entry in ipairs(Config.AI.difficulties) do
        if entry.id == id then return entry end
    end

    return Config.AI.difficulties[1]
end

--- A hoop this bot is allowed to score on, honouring team baskets.
local function pickHoop(bot)
    local candidates = {}

    for _, hoop in ipairs(BB.hoops) do
        if hoop.court == BB.court and not (hoop.team and hoop.team == bot.team) then
            candidates[#candidates + 1] = hoop
        end
    end

    if #candidates == 0 then return end

    return candidates[math.random(#candidates)]
end

--- Somewhere to shoot from: a random bearing at a random distance in range.
local function pickSpot(bot, hoop)
    local min, max = bot.skill.range[1], bot.skill.range[2]
    local dist = min + math.random() * (max - min)
    local angle = math.random() * math.pi * 2.0

    return vec3(
        hoop.coords.x + math.cos(angle) * dist,
        hoop.coords.y + math.sin(angle) * dist,
        hoop.coords.z - 3.05
    )
end

--------------------------------------------------------------------------------
-- Shooting
--------------------------------------------------------------------------------

local function shoot(bot)
    local ped  = bot.ped
    local hoop = bot.hoop
    if not hoop then return end

    local origin = GetEntityCoords(ped)
    local dist   = BB.dist2d(origin, hoop.coords)

    -- Face the hoop.
    local heading = math.deg(math.atan(hoop.coords.y - origin.y, hoop.coords.x - origin.x)) - 90.0
    SetEntityHeading(ped, heading % 360.0)

    local model = Config.Ball.model
    if not loadModel(model) then return end

    local release = vec3(origin.x, origin.y, origin.z + 1.55)
    local ball = CreateObject(model, release.x, release.y, release.z, true, true, false)
    SetModelAsNoLongerNeeded(model)

    if not ball or ball == 0 then return end

    local netId = ObjToNet(ball)
    SetNetworkIdCanMigrate(netId, true)
    SetEntityRecordsCollisions(ball, true)
    SetEntityNoCollisionEntity(ball, ped, true)
    ActivatePhysics(ball)

    -- Same scatter model as a human shot, so an NPC misses the same way you do.
    local target = vec3(hoop.coords.x, hoop.coords.y, hoop.coords.z + Config.Shot.aimHeightOffset)
    local aim    = BB.scatterAim(release, target, bot.skill.accuracy, dist)
    local time   = math.min(
        Config.Shot.flightTimeBase + dist * Config.Shot.flightTimePerMetre,
        Config.Shot.flightTimeMax)

    local vel = BB.solveArc(release, aim, time)

    -- A body created this frame isn't in the simulation yet, so give it a tick
    -- before the throw — same reason the player's shot waits one.
    Wait(0)
    if not DoesEntityExist(ball) then return end

    SetEntityVelocity(ball, vel.x, vel.y, vel.z)

    -- "This frame only" pass-through, held open until the ball is clear of the
    -- shooter. A single call lets it collide with its own thrower next tick.
    CreateThread(function()
        local deadline = GetGameTimer() + 700

        while DoesEntityExist(ball) and DoesEntityExist(ped) and GetGameTimer() < deadline do
            SetEntityNoCollisionEntity(ball, ped, true)

            if #(GetEntityCoords(ball) - GetEntityCoords(ped)) > 1.5 then return end
            Wait(0)
        end
    end)

    BB.playAnim(ped, Config.Anims.shoot)

    bot.ball = netId
    BB.trackShot(netId, origin, hoop, bot.skill.accuracy, bot.aiId)
end

--------------------------------------------------------------------------------
-- Brain
--------------------------------------------------------------------------------

local function think(bot)
    local now = GetGameTimer()
    if now < bot.nextAt then return end

    if bot.state == 'idle' then
        bot.hoop = pickHoop(bot)
        if not bot.hoop then
            bot.nextAt = now + 3000
            return
        end

        local spot = pickSpot(bot, bot.hoop)
        TaskGoStraightToCoord(bot.ped, spot.x, spot.y, spot.z, bot.skill.moveSpeed, 8000, 0.0, 0.5)

        bot.state  = 'moving'
        bot.nextAt = now + math.floor(bot.skill.setupTime * 1000.0)

    elseif bot.state == 'moving' then
        ClearPedTasks(bot.ped)
        shoot(bot)

        bot.state  = 'resting'
        bot.nextAt = now + math.floor(bot.skill.restTime * 1000.0)

    else
        bot.state  = 'idle'
        bot.nextAt = now
    end
end

CreateThread(function()
    while true do
        local wait = 500

        if next(bots) then
            wait = 200
            local live = BB.match and BB.match.state == 'live'

            for aiId, bot in pairs(bots) do
                if not bot.ped or not DoesEntityExist(bot.ped) then
                    bots[aiId] = nil
                elseif live then
                    think(bot)
                end
            end
        end

        Wait(wait)
    end
end)

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function despawn(aiId)
    local bot = bots[aiId]
    if not bot then return end

    if bot.ped and DoesEntityExist(bot.ped) then
        SetEntityAsMissionEntity(bot.ped, true, true)
        DeleteEntity(bot.ped)
    end

    bots[aiId] = nil
end

RegisterNetEvent('gk_basketball:startAI', function(aiId, team, difficultyId)
    local court = BB.courts[BB.court]
    if not court then return end

    despawn(aiId)

    local model = Config.AI.model
    if not loadModel(model) then
        model = Config.AI.fallbackModel
        if not loadModel(model) then
            TriggerServerEvent('gk_basketball:aiFailed', aiId)
            return
        end
    end

    local at = court.centre
    local ped = CreatePed(4, model, at.x, at.y, at.z, 0.0, false, true)
    SetModelAsNoLongerNeeded(model)

    if not ped or ped == 0 then
        TriggerServerEvent('gk_basketball:aiFailed', aiId)
        return
    end

    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedDiesWhenInjured(ped, false)
    SetPedCanBeTargetted(ped, false)
    SetEntityAsMissionEntity(ped, true, true)

    bots[aiId] = {
        aiId   = aiId,
        ped    = ped,
        team   = team,
        skill  = skillById(difficultyId),
        state  = 'idle',
        nextAt = GetGameTimer() + 1500,
    }
end)

RegisterNetEvent('gk_basketball:stopAI', function(aiId)
    if aiId then
        despawn(aiId)
        return
    end

    for id in pairs(bots) do despawn(id) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    for id in pairs(bots) do despawn(id) end
end)
