--[[
    Courts: derived from the hoop list, given blips and ox_target interactions.

    Hoops are server-authoritative (data/hoops.json). The client asks for them on
    join and gets pushed a fresh list whenever an admin places or removes one.
]]

BB.hoops   = {}     -- flat array of every hoop on the map
BB.courts  = {}     -- keyed by court id, built by BB.buildCourts
BB.match   = nil    -- my current match state, mirrored from the server
BB.myTeam  = nil
BB.court   = nil    -- court id I'm signed up to

local zones = {}
local blips = {}
local nearbyCache, nearbyCacheAt = {}, 0

--------------------------------------------------------------------------------
-- Small UI helpers, shared by the other client files
--------------------------------------------------------------------------------

function BB.notify(message, kind)
    lib.notify({ title = 'Basketball', description = message, type = kind or 'inform' })
end

local hintText, hintAt, hintWatchdog

-- Keeps a text UI alive while something calls showHint every frame, and hides it
-- shortly after the calls stop. One watchdog thread total, however often callers
-- change the text.
function BB.showHint(text)
    hintAt = GetGameTimer()

    if hintText ~= text then
        hintText = text
        lib.showTextUI(text, { position = 'left-center' })
    end

    if hintWatchdog then return end
    hintWatchdog = true

    CreateThread(function()
        while hintText and GetGameTimer() - hintAt < 300 do Wait(100) end

        hintWatchdog = nil

        if hintText then
            hintText = nil
            lib.hideTextUI()
        end
    end)
end

function BB.hideHint()
    if hintText then
        hintText = nil
        lib.hideTextUI()
    end
end

--- Difficulty picker for the NPC. A context menu rather than one target option per
--- difficulty, so the marker doesn't fill up with variants.
function BB.showDifficultyMenu(courtId)
    local options = {}

    for _, entry in ipairs(Config.AI.difficulties) do
        options[#options + 1] = {
            title       = entry.label,
            description = Config.Text.ai_description,
            icon        = 'fas fa-robot',
            onSelect    = function()
                TriggerServerEvent('gk_basketball:addAI', courtId, entry.id)
            end,
        }
    end

    lib.registerContext({
        id      = 'gk_basketball_ai',
        title   = Config.Text.ai_menu_title,
        options = options,
    })

    lib.showContext('gk_basketball_ai')
end

--------------------------------------------------------------------------------
-- Hoop lookup
--------------------------------------------------------------------------------

--- Hoops close enough to matter for scoring and aiming. Recomputed twice a second
--- rather than every frame; the scoring loop calls this a lot.
function BB.nearbyHoops()
    local now = GetGameTimer()

    if now - nearbyCacheAt > 500 then
        nearbyCacheAt = now
        nearbyCache = {}

        local coords = GetEntityCoords(PlayerPedId())

        for _, hoop in ipairs(BB.hoops) do
            if #(coords - hoop.coords) < Config.Ball.renderDistance then
                nearbyCache[#nearbyCache + 1] = hoop
            end
        end
    end

    return nearbyCache
end

function BB.nearestCourt()
    local coords = GetEntityCoords(PlayerPedId())
    local best, bestDist

    for id, court in pairs(BB.courts) do
        local dist = #(coords - court.centre)
        if not bestDist or dist < bestDist then
            best, bestDist = id, dist
        end
    end

    return best, bestDist
end

--------------------------------------------------------------------------------
-- Blips and target zones
--------------------------------------------------------------------------------

local function clearWorld()
    for _, zone in ipairs(zones) do exports.ox_target:removeZone(zone) end
    for _, blip in ipairs(blips) do RemoveBlip(blip) end
    zones, blips = {}, {}
end

--[[
    ox_target has to be up before the world can be built, because the interaction points
    are its zones.

    Both routes into BB.setHoops can now fire during startup: global state replicates on
    join, and this script starts at the same moment as every other client script. The
    fetch this replaced was safe here only by accident, because a round trip to the server
    is always several frames. So the dependency is now explicit.
]]
local function whenTargetReady(fn)
    if GetResourceState('ox_target') == 'started' then return fn() end

    CreateThread(function()
        local deadline = GetGameTimer() + 20000

        while GetResourceState('ox_target') ~= 'started' do
            if GetGameTimer() > deadline then
                print('^1[gk_basketball]^7 ox_target never started — no court interaction points')
                return
            end

            Wait(100)
        end

        fn()
    end)
end

local function buildWorld()
    clearWorld()

    for id, court in pairs(BB.courts) do
        local courtCfg = Config.Courts[id]

        if Config.Blip.enabled and (not courtCfg or courtCfg.blip ~= false) then
            local blip = AddBlipForCoord(court.centre.x, court.centre.y, court.centre.z)
            SetBlipSprite(blip, Config.Blip.sprite)
            SetBlipColour(blip, Config.Blip.colour)
            SetBlipScale(blip, Config.Blip.scale)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(court.label)
            EndTextCommandSetBlipName(blip)
            blips[#blips + 1] = blip
        end

        zones[#zones + 1] = exports.ox_target:addSphereZone({
            coords = court.centre,
            radius = 2.5,
            debug  = Config.Debug,
            options = {
                {
                    name     = 'gk_basketball:join:' .. id,
                    label    = Config.Text.court_join,
                    icon     = 'fas fa-basketball',
                    canInteract = function() return BB.court == nil end,
                    onSelect = function() TriggerServerEvent('gk_basketball:join', id) end,
                },
                {
                    name     = 'gk_basketball:start:' .. id,
                    label    = Config.Text.court_start,
                    icon     = 'fas fa-stopwatch',
                    canInteract = function()
                        return BB.court == id and BB.match and BB.match.state == 'lobby'
                    end,
                    onSelect = function() TriggerServerEvent('gk_basketball:start', id) end,
                },
                {
                    name     = 'gk_basketball:ball:' .. id,
                    label    = Config.Text.court_ball,
                    icon     = 'fas fa-hand',
                    canInteract = function()
                        return Config.Match.freeBallsOnCourt and not BB.isHolding()
                    end,
                    onSelect = function() TriggerServerEvent('gk_basketball:requestBall', id) end,
                },
                {
                    name     = 'gk_basketball:ai:' .. id,
                    label    = Config.Text.court_ai,
                    icon     = 'fas fa-robot',
                    canInteract = function()
                        return Config.AI.enabled and BB.court == id
                    end,
                    onSelect = function() BB.showDifficultyMenu(id) end,
                },
                {
                    name     = 'gk_basketball:leave:' .. id,
                    label    = Config.Text.court_leave,
                    icon     = 'fas fa-door-open',
                    canInteract = function() return BB.court == id end,
                    onSelect = function() TriggerServerEvent('gk_basketball:leave') end,
                },
            },
        })
    end
end

function BB.setHoops(hoops)
    BB.hoops = {}

    for _, hoop in ipairs(hoops or {}) do
        BB.hoops[#BB.hoops + 1] = {
            id     = hoop.id,
            court  = hoop.court,
            team   = hoop.team,
            coords = BB.vec(hoop.coords),
        }
    end

    BB.courts = BB.buildCourts(BB.hoops)
    nearbyCacheAt = 0
    whenTargetReady(buildWorld)
end

--------------------------------------------------------------------------------
-- Match state
--------------------------------------------------------------------------------

RegisterNetEvent('gk_basketball:notify', function(message, kind)
    BB.notify(message, kind)
end)

--[[
    Hoops arrive as global state, in two ways that between them cover every case:
    this handler for a change made while we are already running, and the read below
    for whatever was already published when we started.

    Both are needed. A handler registered after the value replicated is never called
    retroactively, and a value that never changes again would never reach us through
    the handler alone.
]]
AddStateBagChangeHandler(BB.STATE_HOOPS, 'global', function(_, _, value)
    if value then BB.setHoops(value) end
end)

RegisterNetEvent('gk_basketball:syncMatch', function(court, state)
    BB.court = court
    BB.match = state
    BB.myTeam = nil

    if state and state.players then
        local me = GetPlayerServerId(PlayerId())
        for _, player in ipairs(state.players) do
            if player.id == me then
                BB.myTeam = player.team
                break
            end
        end
    end

    BB.updateHud(court and state or nil)
end)

-- Whatever was already published before this script started.
local published = GlobalState[BB.STATE_HOOPS]

if published then BB.setHoops(published) end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearWorld()
    BB.hideHint()
end)
