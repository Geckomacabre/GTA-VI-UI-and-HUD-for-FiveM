/* The minimap must survive an error in the status tick.
 *
 *   npm i fengari && node tools/radarsurvives.test.js
 *
 * This is a REGRESSION TEST FOR A REAL OUTAGE. The radar's visibility used to
 * be decided at the bottom of the poll loop's pcall'd body. The body starts
 * with the health/needs reads, so ANY error up there aborted the tick before
 * the radar was touched -- and the radar keeps whatever it was last given. For
 * a player whose saved preference is "no map on foot", the last thing it was
 * given was `hidden`, so the map could never come back: not on foot, not in a
 * car, not across a restart. One unrelated error deleted the minimap.
 *
 * The fix is that the decision now happens BEFORE the pcall. What this test
 * actually pins is that property, by driving the real loop body's structure
 * with a deliberately exploding tick.
 */
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const root = path.dirname(__dirname).replace(/\\/g, '/') + '/';
const src = fs.readFileSync(root + 'client.lua', 'utf8');

let fails = 0;
const ok = (c, l, e) => c ? console.log('  PASS  ' + l)
  : (console.log('  FAIL  ' + l + (e !== undefined ? '  -> ' + JSON.stringify(e) : '')), fails++);

/* Static guarantee first, because it is the one that cannot rot: the setRadar
   call in the poll loop must appear BEFORE that loop's `pcall`. If someone
   moves it back inside the body later, this fails immediately and says why. */
const end_ = src.indexOf('status tick error');            // the poll loop's own print
const start = src.lastIndexOf('while true do', end_);       // ITS while, not the first one
const loop = src.slice(start, end_);
const iRadar = loop.indexOf('setRadar(');
const iPcall = loop.indexOf('pcall(function()');
ok(iRadar !== -1 && iPcall !== -1 && iRadar < iPcall,
   'the poll loop decides the radar BEFORE entering its pcall',
   { setRadarAt: iRadar, pcallAt: iPcall });
ok(!loop.slice(iPcall).includes('setRadar('),
   'and nowhere inside the pcall, where an earlier error could skip it');

/* Then prove the property dynamically on the same shape: an exploding body
   must still leave the radar decided. */
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const radar = [];
lua.lua_pushjsfunction(L, (S) => { radar.push(lua.lua_toboolean(S, 1)); return 0; });
lua.lua_setglobal(L, to_luastring('DisplayRadar'));

const chunk = `
  local radarShown = nil
  local function setRadar(on)
    on = on and true or false
    DisplayRadar(on)
    radarShown = on
  end
  -- the loop body's shape, verbatim in structure: decide, then pcall
  local minimapOnFoot, editorOpen = false, false
  local cacheVehicle = nil
  function tick(explode)
    setRadar(cacheVehicle ~= nil or minimapOnFoot or editorOpen)
    local ok = pcall(function()
      if explode then error('nil entity, or a module that did not load') end
    end)
    return ok
  end
  function setVehicle(v) cacheVehicle = v end
  function setPref(v) minimapOnFoot = v end
`;
if (lauxlib.luaL_loadstring(L, to_luastring(chunk)) !== lua.LUA_OK)
  throw new Error('load: ' + lua.lua_tojsstring(L, -1));
if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK)
  throw new Error('run: ' + lua.lua_tojsstring(L, -1));

function call(name, arg) {
  lua.lua_getglobal(L, to_luastring(name));
  if (arg === undefined) lua.lua_pushnil(L);
  else if (typeof arg === 'boolean') lua.lua_pushboolean(L, arg);
  else lua.lua_pushnumber(L, arg);
  if (lua.lua_pcall(L, 1, 1, 0) !== lua.LUA_OK)
    throw new Error(name + ': ' + lua.lua_tojsstring(L, -1));
  const r = lua.lua_toboolean(L, -1); lua.lua_pop(L, 1); return r;
}

// On foot, preference "hidden": the map is hidden. That part is correct.
radar.length = 0;
call('tick', false);
ok(radar.length === 1 && radar[0] === false, 'on foot with the pref off, the map hides', radar);

// Now the tick starts erroring, and the player gets into a car.
radar.length = 0;
call('setVehicle', 1);
const survived = call('tick', true);
ok(survived === false, 'the exploding body is caught by the pcall (tick reports failure)');
ok(radar.length === 1 && radar[0] === true,
   'and the map STILL comes up in the car -- the outage was this assertion failing',
   radar);

// It also keeps working while the errors continue.
radar.length = 0;
call('tick', true); call('tick', true);
ok(radar.every(v => v === true) && radar.length === 2,
   'every subsequent broken tick still decides the radar', radar);

console.log(fails ? '\n' + fails + ' check(s) failed' : '\nall checks passed');
process.exit(fails ? 1 : 0);
