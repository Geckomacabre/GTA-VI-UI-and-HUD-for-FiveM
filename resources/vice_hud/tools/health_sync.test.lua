-- Headless check of the Health skill's max-health sync, running the REAL
-- client_skills.lua against a stubbed engine.  Run from the resource folder:
--     lua tools/health_sync.test.lua
local fails, total = 0, 0
local function ok(c, msg) total = total + 1 if not c then fails = fails + 1 print('  FAIL  ' .. msg) else print('  PASS  ' .. msg) end end

-- ---- engine state ----------------------------------------------------------
local ped = { max = 200, hp = 200, dead = false, running = false, sprinting = false, x = 0.0 }
local vec = {}
vec.__index = vec
vec.__sub = function(a, b) return setmetatable({ x = a.x - b.x }, vec) end
vec.__len = function(a) return math.abs(a.x) end

Config = { Skills = { enable = true, tick = 200, saveMs = 30000, maxStep = 40.0, healthMaxBonus = 60, jogStaminaFactor = 0.4,
                      statPrefix = 'MP0_', announce = false } }
cache = { ped = 1, vehicle = 0 }
local threads, handlers, net, saved = {}, {}, {}, 0
function CreateThread(f) threads[#threads + 1] = coroutine.create(f) end
function Wait() coroutine.yield() end
function RegisterNetEvent(n, f) net[n] = f end
function AddEventHandler(n, f) handlers[n] = f end
function RegisterCommand() end
function RegisterNUICallback() end
local ex = {}
function exports(n, f) ex[n] = f end
function SendNUIMessage() end
function TriggerServerEvent(n) if n == 'vice_hud:skills:save' then saved = saved + 1 end end
function GetCurrentResourceName() return 'vice_hud' end
function GetHashKey() return 1 end
function StatSetInt() end
function StatGetInt() return 0 end
lib = { notify = function() end }
function PlayerPedId() return 1 end
function DoesEntityExist() return true end
function IsEntityDead() return ped.dead end
function GetEntityMaxHealth() return ped.max end
function GetEntityHealth() return ped.hp end
function SetPedMaxHealth(_, v) ped.max = v if ped.hp > v then ped.hp = v end end
function SetEntityMaxHealth(_, v) ped.max = v if ped.hp > v then ped.hp = v end end
function SetEntityHealth(_, v) ped.hp = v end
function GetEntityCoords() return setmetatable({ x = ped.x }, vec) end
function IsPedRunning() return ped.running end
function IsPedSprinting() return ped.sprinting end
function IsPedSwimmingUnderWater() return false end
function GetPedStealthMovement() return 0 end
function IsPedArmed() return false end
function GetVehicleClass() return 0 end
setmetatable(_G, { __index = function(_, k) if k:match('^[A-Z]') then return function() return false end end end })

dofile('skills.lua')
dofile('client_skills.lua')

local function tick() for _, co in ipairs(threads) do if coroutine.status(co) ~= 'dead' then assert(coroutine.resume(co)) end end end
local function setLevel(l, id) net['vice_hud:skills:load']({ [id or 'health'] = Skills.xpForLevel(l) }) end

print('-- max health from the Health level')
net['vice_hud:skills:load']({})
tick()
ok(SkillMaxHealth() == 200, 'level 0 is the stock 200 hp')
setLevel(100)
ok(SkillMaxHealth() == 260, 'level 100 is 200 + healthMaxBonus (260)')
setLevel(50)
ok(SkillMaxHealth() == 230, 'level 50 is halfway (230)')

print('-- a full ped stays full when max rises')
ped.max, ped.hp = 200, 200
setLevel(100); tick()
ok(ped.max == 260, 'the ped max health was raised to 260')
ok(ped.hp == 260, 'full at 200/200 becomes full at 260/260, not 200/260')

print('-- a hurt ped stays hurt')
ped.max, ped.hp = 200, 200
setLevel(0); tick()
ped.hp = 150
setLevel(100); tick()
ok(ped.hp == 150, 'a ped at 150 stays at 150 when max rises')
ok(ped.max == 260, 'and the max still rose')

print('-- another resource resets max to 200')
ped.max, ped.hp = 260, 260; tick()
ped.max, ped.hp = 200, 200   -- reset AND clamp, as the engine does
tick()
ok(ped.max == 260, 'max health is re-asserted')
ok(ped.hp == 260, 'a ped that was full stays full after the reset')

ped.max, ped.hp = 260, 230; tick()
ped.max, ped.hp = 200, 200   -- clamped down from 230
tick()
ok(ped.max == 260 and ped.hp == 230, 'a ped at 230 is put back to 230, not healed or left at 200')

print('-- death and revive')
ped.max, ped.hp = 260, 260; tick()
ped.dead, ped.hp = true, 0
tick()
ok(ped.hp == 0, 'nothing is written to a dead ped')
ped.dead, ped.max, ped.hp = false, 200, 200   -- revive resets max to 200 at full
tick()
ok(ped.max == 260 and ped.hp == 260, 'a revive at full lands at full of the trained max')

print('-- switched off')
Config.Skills.healthMaxBonus = 0
ped.max, ped.hp = 200, 200; tick()
ok(ped.max == 200, 'healthMaxBonus = 0 leaves max health alone')
Config.Skills.healthMaxBonus = 60

print('-- jogging pays Health, sprinting does not')
setLevel(0)
ped.x = 0.0; tick()                -- first sample sets lastPos
ped.running, ped.sprinting = true, false
for i = 1, 10 do ped.x = ped.x + 3.0; tick() end     -- 30 m at a jog
local xp = ex.GetSkill('health').xp
ok(math.abs(ex.GetSkill('stamina').xp - 30 * 0.5 * 0.4) < 0.5, 'the same 30 m jog pays ~6 Stamina XP (0.4 of the sprint rate)')
ok(math.abs(xp - 30 * 0.35) < 1.0, ('30 m jogged pays ~10.5 Health XP (got %.1f)'):format(xp))
local stam0 = ex.GetSkill('stamina').xp
ped.running, ped.sprinting = true, true
for i = 1, 10 do ped.x = ped.x + 6.0; tick() end     -- 60 m sprinted
ok(ex.GetSkill('health').xp == xp, 'sprinting adds no Health XP')
ok(ex.GetSkill('stamina').xp > stam0, 'sprinting still pays Stamina, unchanged')
ped.running, ped.sprinting = false, false
for i = 1, 10 do ped.x = ped.x + 1.0; tick() end     -- walking
ok(ex.GetSkill('health').xp == xp, 'walking adds no Health XP')


print(('\n%d/%d passed'):format(total - fails, total))
os.exit(fails == 0 and 0 or 1)
