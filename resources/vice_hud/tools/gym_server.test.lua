-- Headless check of server_gym.lua: validation, ids, persistence, sync.
-- Run from the resource folder:   lua tools/gym_server.test.lua
local fails, total = 0, 0
local function ok(c, msg) total = total + 1 if not c then fails = fails + 1 print('  FAIL  ' .. msg) else print('  PASS  ' .. msg) end end

local exp, net, sent, files = {}, {}, {}, {}
-- Tiny stand-in for FiveM's json: enough to round-trip the station list.
json = {
    encode = function(t) files.__last = t return 'ENC' end,
    decode = function(s) if s == 'ENC' then return files.__last end return {} end,
}
function exports(n, f) exp[n] = f end
function RegisterNetEvent(n, f) net[n] = f end
function TriggerClientEvent(n, target, list) sent[#sent + 1] = { n, target, list } end
function GetCurrentResourceName() return 'vice_hud' end
function LoadResourceFile(_, f) return files[f] end
local writeOk = true
function SaveResourceFile(_, f, data) if not writeOk then return false end files[f] = data return true end
source = 5

Config = { Training = { stationRadius = 1.2, exercises = {
    weights = { station = true }, bench = { atProp = true }, pushups = {} } } }
dofile('server_gym.lua')

print('-- validation')
local r = exp.SaveGymStation({ exercise = 'pushups', x = 1, y = 2, z = 3 })
ok(not r.ok, 'an exercise that is neither a station nor a prop one is refused')
ok(not exp.SaveGymStation({ exercise = 'weights', x = 0/0, y = 2, z = 3 }).ok, 'NaN coordinates are refused')
ok(not exp.SaveGymStation({ exercise = 'weights', x = 99999, y = 2, z = 3 }).ok, 'coordinates off the map are refused')
ok(not exp.SaveGymStation('junk').ok, 'a non-table is refused')
ok(#exp.GetGymStations() == 0, 'and nothing was stored by any of that')

print('-- saving')
r = exp.SaveGymStation({ exercise = 'weights', x = 10.5, y = -20, z = 30, h = 450, radius = 99, label = string.rep('x', 100) })
ok(r.ok and r.id == 'gym_1', 'the first station is gym_1')
local st = exp.GetGymStations()[1]
ok(st.radius == 4.0, 'a huge radius is clamped to 4 m')
ok(#st.label == 40, 'a long label is cut to 40 characters')
ok(st.h == 90.0, 'heading is wrapped into 0..360')
ok(sent[#sent][1] == 'vice_hud:gym:sync' and sent[#sent][2] == -1, 'every client is told')

r = exp.SaveGymStation({ exercise = 'bench', x = 1, y = 1, z = 1 })
ok(r.id == 'gym_2', 'ids count up')
r = exp.SaveGymStation({ id = 'gym_1', exercise = 'weights', x = 11, y = 1, z = 1 })
ok(r.ok and #exp.GetGymStations() == 2 and exp.GetGymStations()[1].x == 11, 'saving with an id replaces that station')
ok(not exp.SaveGymStation({ id = 'gym_77', exercise = 'weights', x = 1, y = 1, z = 1 }).ok, 'an unknown id is refused rather than invented')
ok(exp.SaveGymStation({ id = '../../evil', exercise = 'weights', x = 1, y = 1, z = 1 }).id == 'gym_3', 'a malformed id is ignored and a fresh one issued')

print('-- removing')
ok(exp.RemoveGymStation('gym_2').ok and #exp.GetGymStations() == 2, 'a station can be removed')
ok(not exp.RemoveGymStation('gym_2').ok, 'removing it again reports failure')
r = exp.SaveGymStation({ exercise = 'weights', x = 5, y = 5, z = 5 })
ok(r.id == 'gym_4', 'ids are never reused while a higher one exists')

print('-- persistence and failure')
writeOk = false
ok(not exp.SaveGymStation({ exercise = 'weights', x = 1, y = 1, z = 1 }).ok, 'a failed write is reported, not swallowed')
writeOk = true

files['data/gym.json'] = 'ENC'
files.__last = { { id = 'gym_9', exercise = 'weights', x = 1, y = 2, z = 3, h = 0, radius = 1 },
                 { id = 'gym_10', exercise = 'pushups', x = 1, y = 2, z = 3 },
                 { exercise = 'weights', x = 1, y = 2, z = 3 } }
dofile('server_gym.lua')
ok(#exp.GetGymStations() == 1 and exp.GetGymStations()[1].id == 'gym_9',
   'on load a station with a bad exercise or no id is dropped, the good one kept')

print('-- a joining player')
sent = {}
net['vice_hud:gym:request']()
ok(sent[1] and sent[1][2] == 5 and #sent[1][3] == 1, 'gets the list, and only that player is sent it')

print(('\n%d/%d passed'):format(total - fails, total))
os.exit(fails == 0 and 0 or 1)
