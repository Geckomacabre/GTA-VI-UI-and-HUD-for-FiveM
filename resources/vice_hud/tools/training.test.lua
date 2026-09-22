-- Headless check of client_training.lua on a virtual clock.  Run from the
-- resource folder:   lua tools/training.test.lua
local fails, total = 0, 0
local function ok(c, msg) total = total + 1 if not c then fails = fails + 1 print('  FAIL  ' .. msg) else print('  PASS  ' .. msg) end end

local clock, threads = 0, {}
local ped = { active = false, refuse = false, dead = false, moving = false, xPressed = false }
local awards, notes, texts, cmds, targets, cleared = {}, {}, {}, {}, {}, 0
local exp, net, zones, removed, tasks = {}, {}, {}, 0, {}
function vec3(x, y, z) return { x = x, y = y, z = z } end
function RegisterNetEvent(n, f) net[n] = f end
function TriggerServerEvent() end

function GetGameTimer() return clock end
function CreateThread(f) threads[#threads + 1] = { co = coroutine.create(f), at = clock } end
function Wait(ms) coroutine.yield(ms or 0) end
function RegisterCommand(n, f) cmds[n] = f end
function AddEventHandler() end
-- exports.ox_target:addModel(...)
_G.exports = setmetatable({}, { __call = function(_, n, f) exp[n] = f end,
    __index = function(_, k) if k == 'ox_target' then return {
        addModel = function(_, models, opts) targets[#targets + 1] = { models = models, opts = opts } end,
        addSphereZone = function(_, z) zones[#zones + 1] = z return #zones end,
        removeZone = function() removed = removed + 1 end } end end })
function GetCurrentResourceName() return 'vice_hud' end
function GetResourceState() return 'started' end
cache = { ped = 1 }
lib = { notify = function(t) notes[#notes + 1] = t.description end,
        showTextUI = function(t) texts[#texts + 1] = t end, hideTextUI = function() end,
        registerContext = function() end, showContext = function() end }
Config = { Skills = { enable = true }, Training = {
    enable = true, targetDistance = 2.0, setReps = 25, restSeconds = 60,
    exercises = {
        pushups = { label = 'Push-ups', scenario = 'S1', secs = 3.0, xp = 20 },
        bench   = { label = 'Bench press', scenario = 'S2', secs = 4.5, xp = 34, atProp = true },
        weights = { label = 'Free weights', scenario = 'S3', secs = 4.0, xp = 28, station = true },
        chinups = { label = 'Chin-ups', scenario = 'S4', secs = 4.0, xp = 30, atProp = true },
    },
    models = { bench = { 'b1' }, weights = { 'w1' }, chinups = { 'c1' } } } }
function ViceSkillAward(id, amt) awards[#awards + 1] = { id, amt } end
function PlayerPedId() return 1 end
function IsEntityDead() return ped.dead end
function IsPedInAnyVehicle() return false end
function IsPedSwimming() return false end
function IsPedFalling() return false end
function IsPedRagdoll() return false end
function IsPedCuffed() return false end
function IsPedInMeleeCombat() return false end
function IsPedShooting() return false end
function IsControlJustPressed() return ped.xPressed end
function GetControlNormal() return ped.moving and 1.0 or 0.0 end
function TaskStartScenarioInPlace() ped.active = not ped.refuse end
function TaskStartScenarioAtPosition(_, sc, x, y, z, h) tasks[#tasks + 1] = { sc, x, y, z, h } ped.active = not ped.refuse end
function IsPedActiveInScenario() return ped.active end
function ClearPedTasks() ped.active = false cleared = cleared + 1 end
function DoesEntityExist() return true end
function GetEntityCoords() return { x = 0, y = 0, z = 0 } end
function GetEntityHeading() return 0.0 end

dofile('client_training.lua')

-- Run every thread on the virtual clock until all are idle or `limit` ms pass.
local function run(limit)
    local stop = clock + limit
    while clock < stop do
        local live = false
        for _, t in ipairs(threads) do
            if coroutine.status(t.co) ~= 'dead' then
                live = true
                if t.at <= clock then
                    local okc, wait = coroutine.resume(t.co)
                    assert(okc, wait)
                    t.at = clock + math.max(wait or 0, 16)
                end
            end
        end
        if not live then return end
        clock = clock + 16
    end
end
local function xpTotal() local n = 0 for _, a in ipairs(awards) do n = n + a[2] end return n end

print('-- a full set')
cmds.pushups(); run(120000)
ok(#awards == 25, ('25 reps are paid over a full set (got %d)'):format(#awards))
ok(xpTotal() == 25 * 20, ('all of it Health XP at 20 per rep (got %d)'):format(xpTotal()))
ok(awards[1][1] == 'health', 'and only Health is ever paid')
ok(ped.active == false, 'the ped is released when the set ends')

print('-- rest')
local before = #awards
cmds.pushups(); run(2000)
ok(#awards == before, 'a new set within the rest period pays nothing')
ok(notes[#notes]:find('breath'), 'and says why')
clock = clock + 61000
cmds.pushups(); run(10000)
ok(#awards > before, 'after the rest a set can start again')

print('-- stopping early')
awards = {}; clock = clock + 120000; ped.active = false
cmds.pushups(); run(3300)
ok(#awards == 1, ('one rep after ~3.3 s (got %d)'):format(#awards))
ped.moving = true; run(400); ped.moving = false
local n = #awards; run(20000)
ok(#awards == n, 'moving ends the set: no further reps')
ok(ped.active == false, 'and the scenario is cleared')

print('-- a scenario that refuses to start')
awards = {}; clock = clock + 120000; ped.refuse = true
cmds.pushups(); run(5000)
ok(#awards == 0, 'no XP for a set that never started')
ok(notes[#notes]:find('Cannot'), 'and it says so')
ped.refuse = false

print('-- knocked out of the scenario')
awards = {}; clock = clock + 120000
cmds.pushups(); run(3300)
ped.active = false; run(5000)
local m = #awards
run(20000)
ok(m <= 1 and #awards == m, 'losing the scenario for over a second ends the set')

print('-- gym props')
ok(#targets == 2, ('ox_target got the bench and chin-up model groups only (got %d)'):format(#targets))
ok(cmds.bench == nil, 'prop-only exercises are not commands')
ok(cmds.weights == nil, 'free weights are not a command any more')

print('-- placed gym stations')
run(2500)   -- let the ox_target wait loop finish
net['vice_hud:gym:sync']({ { id = 'gym_1', exercise = 'weights', x = 10.0, y = 20.0, z = 30.0, h = 90.0, radius = 1.5, label = 'Bench corner' },
                           { id = 'gym_2', exercise = 'nonsense', x = 0.0, y = 0.0, z = 0.0, h = 0.0 } })
ok(#zones == 1, ('one sphere zone per valid station; an unknown exercise is skipped (got %d)'):format(#zones))
ok(zones[1].radius == 1.5 and zones[1].coords.z == 31.0, 'radius honoured, target 1 m above the stored floor')
ok(zones[1].options[1].label == 'Bench corner', 'the station label is the target label')
awards = {}; clock = clock + 120000; ped.active = false
zones[1].options[1].onSelect(); run(4200)
ok(#tasks > 0 and tasks[#tasks][1] == 'S3' and tasks[#tasks][2] == 10.0 and tasks[#tasks][5] == 90.0,
   'the scenario starts exactly at the station, facing its heading')
ok(#awards == 1 and awards[1][2] == 28, 'and a rep pays the weights XP')
net['vice_hud:gym:sync']({})
ok(removed >= 1, 'a new sync clears the old zones first, so a deleted station leaves no target')

print(('\n%d/%d passed'):format(total - fails, total))
os.exit(fails == 0 and 0 or 1)
