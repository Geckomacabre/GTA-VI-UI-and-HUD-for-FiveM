--[[ =========================================================================
     vice_hud — training: ways to earn the Health skill
     -------------------------------------------------------------------------
     Deliberate exercise. The ped plays a real GTA scenario (push-ups, sit-ups,
     free weights, bench press, chin-ups) and every `secs` a rep is counted and
     paid in Health XP. The Health skill (client_skills.lua) turns that XP into
     max health, and the HUD draws the longer bar.

     Jogging is not here: it is measured by the sampling loop in
     client_skills.lua, next to sprinting and swimming. Arm wrestling wins are
     paid by the server (see gk_armwrestle/server/match.lua).

     WHY REPS ARE TIMED, NOT COUNTED FROM THE ANIMATION
     A scenario exposes no rep events, and the loop lengths of these clips are
     not something a script can read. Time on an ACTIVE scenario is what can be
     observed, so a rep is `secs` of it. A set is capped (Config.Training.setReps)
     and followed by a compulsory rest, which is also what stops an idle ped
     farming XP: the ceiling is setReps x xp per restSeconds.

     ONLY THE HEALTH SKILL IS PAID. Stamina and focus are untouched by design.
     ====================================================================== --]]

local CFG = Config.Training
if not CFG or not CFG.enable then return end
-- client_skills.lua defines ViceSkillAward only when Config.Skills.enable is on;
-- without the skills system there is nothing to pay into.
if not Config.Skills or not Config.Skills.enable then return end

local exercising = false
local restUntil = 0

local function notify(description, kind)
    lib.notify({ id = 'vice_hud:train', title = 'Training', description = description,
                 type = kind or 'inform', duration = 3500 })
end

--- Anything that makes a workout the wrong thing to be doing right now.
local function blocked(ped)
    if IsEntityDead(ped) then return 'You are in no state to train.' end
    if IsPedInAnyVehicle(ped, false) then return 'Get out of the vehicle first.' end
    if IsPedSwimming(ped) or IsPedFalling(ped) or IsPedRagdoll(ped) then return 'Not here.' end
    if IsPedCuffed(ped) then return 'Not while restrained.' end
    if IsPedInMeleeCombat(ped) or IsPedShooting(ped) then return 'Not in the middle of a fight.' end
    return nil
end

local function stopped(ped)
    -- Movement or the cancel key ends the set. X (73) is the same cancel key the
    -- emote menus use, so it is already muscle memory.
    if IsControlJustPressed(0, 73) then return true end
    for _, c in ipairs({ 32, 33, 34, 35 }) do
        if math.abs(GetControlNormal(0, c)) > 0.5 then return true end
    end
    return false
end

--- Run one set of an exercise. `entity` is the gym prop for exercises that need
--- one (bench, chin-up bar); `at` = { x, y, z, h } is a placed gym station (the
--- ped is put to work exactly there, facing that way). Both nil for the
--- exercises that work anywhere.
local function train(key, entity, at)
    local ex = CFG.exercises[key]
    if not ex or exercising then return false end

    local ped = cache.ped or PlayerPedId()
    local why = blocked(ped)
    if why then notify(why, 'error') return false end

    local now = GetGameTimer()
    if now < restUntil then
        notify(('Catch your breath: %d s.'):format(math.ceil((restUntil - now) / 1000)), 'inform')
        return false
    end

    exercising = true

    if at then
        TaskStartScenarioAtPosition(ped, ex.scenario, at.x, at.y, at.z, at.h, 0, true, true)
    elseif ex.atProp and entity and DoesEntityExist(entity) then
        local c = GetEntityCoords(entity)
        TaskStartScenarioAtPosition(ped, ex.scenario, c.x, c.y, c.z, GetEntityHeading(entity), 0, true, true)
    else
        TaskStartScenarioInPlace(ped, ex.scenario, 0, true)
    end

    -- The scenario can refuse (occupied, no room, bad model). Give it a moment
    -- rather than paying for a set that never started.
    local started = false
    for _ = 1, 30 do
        Wait(100)
        if IsPedActiveInScenario(ped) then started = true break end
    end
    if not started then
        ClearPedTasks(ped)
        exercising = false
        notify('Cannot do that here.', 'error')
        return false
    end

    local reps, elapsed, lostFor = 0, 0.0, 0.0
    local last = GetGameTimer()
    local target = CFG.setReps or 25

    lib.showTextUI(('%s  0/%d  ·  [X] stop'):format(ex.label, target))

    while exercising do
        Wait(0)
        local t = GetGameTimer()
        local dt = (t - last) / 1000.0
        last = t

        if IsEntityDead(ped) or stopped(ped) then break end

        if IsPedActiveInScenario(ped) then
            lostFor = 0.0
            elapsed = elapsed + dt
            if elapsed >= ex.secs then
                elapsed = elapsed - ex.secs
                reps = reps + 1
                ViceSkillAward('health', ex.xp)
                lib.showTextUI(('%s  %d/%d  ·  [X] stop'):format(ex.label, reps, target))
                if reps >= target then
                    restUntil = GetGameTimer() + (CFG.restSeconds or 60) * 1000
                    notify(('%d reps. You are winded, rest a minute.'):format(reps), 'success')
                    break
                end
            end
        else
            -- Knocked out of the scenario (hit, bumped, another script's task).
            lostFor = lostFor + dt
            if lostFor > 1.0 then break end
        end
    end

    lib.hideTextUI()
    if IsPedActiveInScenario(ped) then ClearPedTasks(ped) end
    exercising = false
    return reps > 0
end

exports('Train', train)

-- Anywhere-exercises as commands. Bench and chin-ups need a real prop, so they
-- are target-only.
for key, ex in pairs(CFG.exercises) do
    if not ex.atProp and not ex.station then
        RegisterCommand(key, function() CreateThread(function() train(key) end) end, false)
    end
end

RegisterCommand('train', function()
    local opts = {}
    for key, ex in pairs(CFG.exercises) do
        if not ex.atProp and not ex.station then
            opts[#opts + 1] = { title = ex.label, description = ('%d Health XP per rep'):format(ex.xp),
                                onSelect = function() CreateThread(function() train(key) end) end }
        end
    end
    table.sort(opts, function(a, b) return a.title < b.title end)
    lib.registerContext({ id = 'vice_hud_train', title = 'Train', options = opts })
    lib.showContext('vice_hud_train')
end, false)

-- Placed gym stations (data/gym.json, authored from em_toolkit). The server
-- sends the whole list on join and on every change; the zones are rebuilt from
-- it rather than patched, so a delete cannot leave a stale target behind.
local stations = {}
local zoneIds = {}
local targetReady = false

local function clearZones()
    for _, id in ipairs(zoneIds) do pcall(function() exports.ox_target:removeZone(id) end) end
    zoneIds = {}
end

local function buildZones()
    clearZones()
    if not targetReady then return end
    for _, st in ipairs(stations) do
        local ex = CFG.exercises[st.exercise]
        if ex then
            local ok, id = pcall(function()
                return exports.ox_target:addSphereZone({
                    coords = vec3(st.x, st.y, st.z + 1.0),
                    radius = st.radius or CFG.stationRadius or 1.2,
                    debug = false,
                    options = { {
                        name = 'vice_hud_gym_' .. st.id,
                        label = st.label or ex.label,
                        icon = 'fa-solid fa-dumbbell',
                        distance = CFG.targetDistance or 2.0,
                        canInteract = function() return not exercising end,
                        onSelect = function() CreateThread(function() train(st.exercise, nil, st) end) end,
                    } },
                })
            end)
            if ok and id then zoneIds[#zoneIds + 1] = id end
        end
    end
end

RegisterNetEvent('vice_hud:gym:sync', function(list)
    stations = type(list) == 'table' and list or {}
    buildZones()
end)

--- Where each station's target is, for the em_toolkit builder's preview.
exports('GetGymTargets', function()
    local out = {}
    for _, st in ipairs(stations) do out[st.id] = vec3(st.x, st.y, st.z + 1.0) end
    return out
end)

CreateThread(function()
    Wait(2000)
    TriggerServerEvent('vice_hud:gym:request')
end)

-- Gym props. Waits for ox_target instead of assuming start order.
CreateThread(function()
    local waited = 0
    while GetResourceState('ox_target') ~= 'started' and waited < 30000 do Wait(500) waited = waited + 500 end
    if GetResourceState('ox_target') ~= 'started' then
        print('^3[vice_hud]^7 ox_target not running: gym targets skipped (commands still work)')
        return
    end
    targetReady = true
    buildZones()

    local function option(key, icon)
        local ex = CFG.exercises[key]
        return {
            name = 'vice_hud_train_' .. key,
            label = ex.label,
            icon = icon,
            distance = CFG.targetDistance or 2.0,
            canInteract = function() return not exercising end,
            onSelect = function(data) CreateThread(function() train(key, data.entity) end) end,
        }
    end

    local m = CFG.models
    exports.ox_target:addModel(m.bench,   { option('bench',   'fa-solid fa-dumbbell') })
    exports.ox_target:addModel(m.chinups, { option('chinups', 'fa-solid fa-person-walking-arrow-loop-left') })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if exercising then lib.hideTextUI() end
    clearZones()
end)
