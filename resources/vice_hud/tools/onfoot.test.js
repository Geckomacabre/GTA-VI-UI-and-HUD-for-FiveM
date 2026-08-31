/* "Hide the minimap on foot" -- the preference, the toggle, and the decision.
 *
 *   npm i fengari && node tools/onfoot.test.js
 *
 * Runs the REAL block out of client.lua: the KVP load, setRadar, and the
 * /hudminimap toggle, plus the poll loop's own decision line lifted verbatim
 * from the loop so the test cannot drift from what actually ships.
 *
 * Three separate things have to agree for this feature to work, and each has
 * broken on its own at least once: what the toggle stores, what a fresh session
 * loads back, and what the loop decides every tick. So all three are checked
 * against the full truth table rather than "it worked when I tried it".
 */
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const root = path.dirname(__dirname).replace(/\\/g, '/') + '/';
const src = fs.readFileSync(root + 'client.lua', 'utf8').replace(/\r\n/g, '\n'); // normalise CRLF: client.lua is CRLF on disk, and this file's \n-only string searches below assumed LF

let fails = 0;
const ok = (c, l, e) => c ? console.log('  PASS  ' + l)
  : (console.log('  FAIL  ' + l + (e !== undefined ? '  -> ' + JSON.stringify(e) : '')), fails++);

// The preference block, verbatim.
const a = src.indexOf("local KVP_MINIMAP = 'vice_hud:minimapOnFoot'");
const b = src.indexOf('\nend, false)', src.indexOf("RegisterCommand('hudminimap'")) + '\nend, false)'.length;
if (a < 0 || b < 12) throw new Error('could not locate the on-foot block');

// The loop's decision, lifted verbatim so a change there breaks this test.
// `setRadar\(.*cache\.vehicle` rather than anchoring on the exact opening
// parens: the call gained an extra `(... ) and not LocalPlayer.state.invOpen`
// wrapper without changing that cache.vehicle is still the first real
// condition it checks.
const decision = /^\s*(setRadar\(.*cache\.vehicle.*)$/m.exec(src);
if (!decision) throw new Error('could not find the poll loop decision line');
console.log('  (decision under test: ' + decision[1] + ')\n');

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const radar = [];
const push = (n, f) => { lua.lua_pushjsfunction(L, f); lua.lua_setglobal(L, to_luastring(n)); };
// DisplayRadar is stubbed in Lua below so the harness can model the engine
// actually obeying (or not obeying) the call.
push('ui', () => 0);
push('RegisterNUICallback', () => 0);
push('PlayerPedId', (S) => { lua.lua_pushnumber(S, 1); return 1; });

const chunk = `
  Config = { MinimapOnFootDefault = true }
  cache = { ped = 1, vehicle = nil }
  LocalPlayer = { state = { invOpen = false } }
  lib = { notify = function() end }
  local editorOpen = false
  local resetPushCaches, lastRectKey
  __radar = {}
  function DisplayRadar(v)
    __wanted = v                   -- mirrors client.lua's own radarWanted
    __radar[#__radar+1] = v
    __radarHidden = not v          -- the engine obeys, unless a test says otherwise
  end
  __kvp = nil
  function GetResourceKvpString() return __kvp end
  function SetResourceKvp(_, v) __kvp = v end
  function IsPedInAnyVehicle() return cache.vehicle ~= nil end
  local __cmds = {}
  function RegisterCommand(name, fn) __cmds[name] = fn end
  -- The per-frame hide-enforcement thread is a real part of the block now.
  -- CreateThread is a no-op here (there is no scheduler), and the engine is
  -- stubbed as "the radar does whatever it was last told", which is the case
  -- where nothing is fighting us. The FIGHT case gets its own drive below.
  function CreateThread(fn) __enforce = fn end
  function Wait() end
  __radarHidden = false
  function IsRadarHidden() return __radarHidden end
` + src.slice(a, b) + `
  -- the poll loop's decision, verbatim
  function tickDecision() ${decision[1]} end
  function runCmd(n) __cmds[n]() end
  function stored() return __kvp end
  function lastRadar() if #__radar == 0 then return nil end return __radar[#__radar] end
  function clearRadar() __radar = {} end
  -- Model another resource switching the map back on, and one frame of
  -- vice_hud's enforcement thread body, written to the same rule as the real
  -- one: re-assert ONLY a hide, and only when the engine disagrees with us.
  function fightBack() __radarHidden = false end
  function hideExternally() __radarHidden = true end
  function radarIsHidden() return __radarHidden end
  function enforceFrame()
    if __wanted == false and not __radarHidden then DisplayRadar(false) end
  end
  function pref() return minimapOnFoot end
  function loadPref() loadMinimapPref() end
  function setEditor(v) editorOpen = v end
  function setVehicle(v) cache.vehicle = v end
  function setInvOpen(v) LocalPlayer.state.invOpen = v end
`;
if (lauxlib.luaL_loadstring(L, to_luastring(chunk)) !== lua.LUA_OK)
  throw new Error('load: ' + lua.lua_tojsstring(L, -1));
if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK)
  throw new Error('run: ' + lua.lua_tojsstring(L, -1));

function call(name, arg) {
  lua.lua_getglobal(L, to_luastring(name));
  let n = 0;
  if (arg !== undefined) {
    n = 1;
    if (arg === null) lua.lua_pushnil(L);
    else if (typeof arg === 'boolean') lua.lua_pushboolean(L, arg);
    else lua.lua_pushnumber(L, arg);
  }
  if (lua.lua_pcall(L, n, 1, 0) !== lua.LUA_OK)
    throw new Error(name + ': ' + lua.lua_tojsstring(L, -1));
  const t = lua.lua_type(L, -1);
  const v = t === lua.LUA_TBOOLEAN ? lua.lua_toboolean(L, -1)
          : t === lua.LUA_TSTRING ? lua.lua_tojsstring(L, -1)
          : t === lua.LUA_TNIL ? null : '<' + t + '>';
  lua.lua_pop(L, 1);
  return v;
}
const lastRadar = () => call('lastRadar');

// ---- the toggle stores what it says -----------------------------------------
ok(call('pref') === true, 'starts at Config.MinimapOnFootDefault (visible)');
lua.lua_getglobal(L, to_luastring('runCmd'));
lua.lua_pushstring(L, to_luastring('hudminimap'));
lua.lua_pcall(L, 1, 0, 0);
ok(call('pref') === false, 'one /hudminimap turns the on-foot map OFF');
ok(call('stored') === 'hidden', 'and stores "hidden" so it survives a restart', call('stored'));
ok(lastRadar() === false, 'and hides it immediately, without waiting for a tick');

// ---- the loop agrees, every tick --------------------------------------------
call('clearRadar');
call('tickDecision');
ok(lastRadar() === false, 'ON FOOT, pref off  -> the poll loop keeps it hidden');

call('setVehicle', 1); call('clearRadar'); call('tickDecision');
ok(lastRadar() === true, 'IN A CAR, pref off -> shown');

// ---- the inventory screen overrides everything else --------------------
// Still in the car from the case above: without this override the map would
// stay shown, and the frame/badge floating over the inventory NUI is exactly
// the bug this override exists to fix.
call('setInvOpen', true); call('clearRadar'); call('tickDecision');
ok(lastRadar() === false, 'IN A CAR with the inventory open -> hidden anyway');

call('setInvOpen', false); call('clearRadar'); call('tickDecision');
ok(lastRadar() === true, 'closing the inventory -> shown again (still in the car)');

call('setVehicle', null); call('clearRadar'); call('tickDecision');
ok(lastRadar() === false, 'back on foot     -> hidden again');

call('setEditor', true); call('clearRadar'); call('tickDecision');
ok(lastRadar() === true, 'ON FOOT with /movehud open -> shown, so it can be tuned');
call('setEditor', false);

// ---- and a fresh session loads it back --------------------------------------
lua.lua_getglobal(L, to_luastring('runCmd'));
lua.lua_pushstring(L, to_luastring('hudminimap'));
lua.lua_pcall(L, 1, 0, 0);                       // back to visible
ok(call('stored') === 'always', 'toggling back stores "always"', call('stored'));
call('loadPref');
ok(call('pref') === true, 'and a reload of that KVP restores "visible"');

lua.lua_getglobal(L, to_luastring('runCmd'));
lua.lua_pushstring(L, to_luastring('hudminimap'));
lua.lua_pcall(L, 1, 0, 0);                       // hidden again
call('loadPref');
ok(call('pref') === false, 'a reload of "hidden" restores hidden -- the restart case');
call('clearRadar'); call('tickDecision');
ok(lastRadar() === false, 'and the first tick of that session hides the map');

// ---- the case that actually bites: another resource fighting us -------------
/* DISPLAY_RADAR is one global flag and the LAST caller wins. vice_hud asks four
   times a second (the poll tick); a resource that asks every frame simply
   overrules it, and "hide on foot" looks broken with nothing in either console
   to explain why. client.lua's per-frame enforcement thread exists for exactly
   this, and it reads IS_RADAR_HIDDEN rather than assuming its own call stuck. */
call('clearRadar');
call('tickDecision');                     // on foot, pref off -> asks for hidden
ok(lastRadar() === false, 'we ask for the map to be hidden');
call('fightBack');                        // something else switches it back on
ok(call('radarIsHidden') === false, 'and something else switches it back on');

call('enforceFrame');
ok(lastRadar() === false && call('radarIsHidden') === true,
   'the per-frame enforcement puts the hide back -- this is what makes the ' +
   'preference stick against another resource');

// A SHOW must never be re-asserted: something else hiding the map (a cutscene,
// an interior, a phone) is legitimate, and fighting it would make vice_hud the
// very thing this thread exists to survive.
call('setVehicle', 1);
call('tickDecision');                     // in a car -> asks for shown
call('clearRadar');
call('hideExternally');
call('enforceFrame');
ok(lastRadar() === null,
   'but a SHOW is never re-asserted, so anything else may still hide the map',
   lastRadar());

// ---- the startup race this test exists to catch -----------------------------
/* loadMinimapPref() used to run inside a CreateThread, alongside loadMapState,
   with no ordering guarantee against the poll loop's OWN CreateThread -- two
   independent threads, either could run first. If the poll loop's first tick
   won that race, it read Config.MinimapOnFootDefault (visible) instead of the
   saved preference and showed the map for at least one tick before flipping
   back off -- a real "it's on, then it turns off" flash on every load, which
   is what a report of "it disappeared for a second, then came right back"
   would look like read backwards.

   loadMinimapPref() is called synchronously right after its own definition
   now, in the main chunk -- not inside any thread -- so this is a structural
   check: is the call there, unconditionally, at the top level? */
const defStart = src.indexOf('local function loadMinimapPref');
const defEnd = src.indexOf('\nend\n', defStart) + 1;   // the FUNCTION's own end,
                                                        // not the if/elseif's inline one
// A REAL top-level CreateThread( statement, not the word appearing inside a
// comment (as it does in the explanatory comment right after defEnd).
const nextThread = src.indexOf('\nCreateThread(', defEnd);
const between = src.slice(defEnd, nextThread);
ok(/^local ok, err = pcall\(loadMinimapPref\)\s*$/m.test(between),
   'loadMinimapPref() is called synchronously (via pcall) right after its definition, ' +
   'before the next CreateThread -- not raced against one', between.trim());

console.log(fails ? '\n' + fails + ' check(s) failed' : '\nall checks passed');
process.exit(fails ? 1 : 0);
