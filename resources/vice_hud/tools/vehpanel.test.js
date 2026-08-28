/* Does the vehicle panel actually leave the screen when you leave the car?
 *
 *   npm i fengari && node tools/vehpanel.test.js
 *
 * The collapsed pips (lock / engine / fuel) are pushed every tick for the whole
 * drive, long after the announcement window has latched panelUntil back to 0.
 * The exit branch therefore cannot key its hide off panelUntil -- by then it is
 * already 0 and the hide never fires, which is the bug this covers.
 *
 * Runs the REAL vehicle branch lifted out of client.lua's status tick with the
 * natives stubbed, driving it through the full sequence: on foot, get in, drive
 * past the announcement deadline, get out.
 */
const fs = require('fs');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const src = fs.readFileSync(__dirname + '/../client.lua', 'utf8').split(/\r?\n/);
const first = src.findIndex(l => l.includes('local vehicle = cache.vehicle'));
if (first < 0) throw new Error('vehicle branch not found in client.lua');
// Walk to the `end` that closes the if/else at the branch's own indent.
const indent = src[first].match(/^\s*/)[0];
let last = -1;
for (let i = first + 1; i < src.length; i++) {
  if (src[i] === indent + 'end') { last = i; break; }
}
if (last < 0) throw new Error('could not find the end of the vehicle branch');
const branch = src.slice(first, last + 1).join('\n');

const harness = `
local pushes = {}
local now, radar = 0, nil
function GetGameTimer() return now end
function DisplayRadar(v) radar = v end
-- The poll loop no longer calls DisplayRadar directly: it goes through
-- setRadar, which also tells the page so the frame/badge/compass come down
-- with the map (see tools/radarchrome.test.js, which tests that half). This
-- slice does not include it, so stand in for it here.
function setRadar(v) DisplayRadar(v) end
function fuelLevel() return 55 end
function GetIsVehicleEngineRunning() return true end
function lockState() return 1 end
function GetVehicleEngineHealth() return 1000.0 end
function ui(name, data) if name == 'vehicle' then pushes[#pushes+1] = data end end

cache = { vehicle = nil }
veh = {}
panelUntil = 0
vehShown = false
minimapOnFoot, editorOpen = false, false

function tick() ${'\n'}${branch}${'\n'} end

function drive(t) now = t end
function lastPush() return pushes[#pushes] end
function pushCount() return #pushes end
function radarState() return radar end
`;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function run(code, what) {
  if (lauxlib.luaL_dostring(L, to_luastring(code)) !== lua.LUA_OK) {
    throw new Error(what + ': ' + lua.lua_tojsstring(L, -1));
  }
}
run(harness, 'harness');

function evalLua(expr) {
  run('__r = ' + expr, expr);
  lua.lua_getglobal(L, to_luastring('__r'));
  const t = lua.lua_type(L, -1);
  let v;
  if (t === lua.LUA_TNUMBER) v = lua.lua_tonumber(L, -1);
  else if (t === lua.LUA_TSTRING) v = lua.lua_tojsstring(L, -1);
  else if (t === lua.LUA_TBOOLEAN) v = lua.lua_toboolean(L, -1);
  else if (t === lua.LUA_TNIL) v = null;
  else v = '<' + t + '>';
  lua.lua_pop(L, 1);
  return v;
}

let failed = 0;
function check(name, cond) {
  console.log((cond ? '  ok   ' : '  FAIL ') + name);
  if (!cond) failed++;
}

// --- on foot, cold start: nothing should be pushed at all -------------------
run('drive(0) tick()', 'tick on foot');
check('on foot at start: no vehicle push', evalLua('pushCount()') === 0);

// --- get in ------------------------------------------------------------------
run("cache.vehicle = 1 panelUntil = 5000 drive(1000) tick()", 'tick in car');
check('in car: panel shown', evalLua("lastPush().show == true"));
check('in car: full plate, not collapsed', evalLua("lastPush().collapsed == false"));

// --- drive past the announcement deadline ------------------------------------
run('drive(9000) tick() tick()', 'tick mid-drive');
check('mid-drive: still shown', evalLua("lastPush().show == true"));
check('mid-drive: collapsed to pips', evalLua("lastPush().collapsed == true"));
check('mid-drive: announcement window latched shut', evalLua('panelUntil == 0'));

// --- get out: THE bug --------------------------------------------------------
const before = evalLua('pushCount()');
run('cache.vehicle = nil drive(10000) tick()', 'tick on exit');
check('on exit: a push was made', evalLua('pushCount()') === before + 1);
check('on exit: panel hidden', evalLua("lastPush().show == false"));
check('on exit: radar hidden with minimapOnFoot off', evalLua('radarState()') === false);

// --- and it does not spam the hide every tick afterwards ----------------------
const after = evalLua('pushCount()');
run('tick() tick() tick()', 'ticks on foot');
check('still on foot: hide sent once, not per tick', evalLua('pushCount()') === after);

// --- get back in: the panel comes back ---------------------------------------
run("cache.vehicle = 2 panelUntil = 20000 drive(11000) tick()", 'tick back in car');
check('back in car: panel shown again', evalLua("lastPush().show == true"));
run("cache.vehicle = nil drive(12000) tick()", 'tick out again');
check('out again: hidden again', evalLua("lastPush().show == false"));

console.log(failed ? `\n${failed} check(s) FAILED` : '\nall checks passed');
process.exit(failed ? 1 : 0);
