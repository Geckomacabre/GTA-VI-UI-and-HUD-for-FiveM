/* The turn-by-turn popup is a DRIVING instrument, it must not show on foot.
 *
 *   npm i fengari && node tools/navfoot.test.js
 *
 * Runs the REAL updateNav out of client.lua with the natives stubbed, and
 * asserts on what it pushes to the NUI. The interesting case is not "nothing
 * happens on foot", it is that LEAVING a vehicle mid-route sends an explicit
 * {active=false} teardown, because the page only fades the bar out when it is
 * told to. Without that the popup would freeze on screen with a stale
 * instruction for as long as the player stayed out of the car.
 */
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const root = path.dirname(__dirname).replace(/\\/g, '/') + '/';
const src = fs.readFileSync(root + 'client.lua', 'utf8').replace(/\r\n/g, '\n'); // normalise CRLF: client.lua is CRLF on disk, and this file's \n-only string searches below assumed LF
const cfg = fs.readFileSync(root + 'config.lua', 'utf8');

let fails = 0;
const ok = (c, l, e) => c ? console.log('  PASS  ' + l)
  : (console.log('  FAIL  ' + l + (e !== undefined ? '  -> ' + JSON.stringify(e) : '')), fails++);

// The nav block is wrapped in one top-level `do ... end` (the 200-local cap),
// so lift from the line after that `do` (the DIR_* constants NAV_DIR is
// keyed on live there) through the end of updateNav, re-declaring updateNav
// as a local here since the real one is forward-declared above the block.
const a = src.indexOf('do\n', src.indexOf('local updateNav')) + 3;
const b = src.indexOf('\nend\n', src.indexOf('updateNav = function(ped)')) + 5;
if (a < 0 || b < 5) throw new Error('could not locate updateNav in client.lua');
const chunk = cfg + '\nlocal updateNav\n' + src.slice(a, b) +
  '\n__test = { updateNav = updateNav }\n';

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

const sent = [];
let inVehicle = true;
const push = (name, fn) => { lua.lua_pushjsfunction(L, fn); lua.lua_setglobal(L, to_luastring(name)); };

// `ui` is the resource's own NUI sender; capture the action + active flag.
push('ui', (S) => {
  const action = lua.lua_tojsstring(S, 1);
  lua.lua_getfield(S, 2, to_luastring('active'));
  const active = lua.lua_toboolean(S, -1);
  sent.push({ action, active });
  return 0;
});
push('GetGameTimer', (S) => { lua.lua_pushnumber(S, 1000); return 1; });
push('GetEntityCoords', (S) => { lua.lua_newtable(S); return 1; });
push('CalculateTravelDistanceBetweenPoints', (S) => { lua.lua_pushnumber(S, 500); return 1; });
push('DoesBlipExist', (S) => { lua.lua_pushboolean(S, true); return 1; });
push('GetFirstBlipInfoId', (S) => { lua.lua_pushnumber(S, 7); return 1; });
push('ReplaceHudColourWithRgba', () => 0);
// A waypoint 40m from a LEFT turn, comfortably inside nearTurnMetres.
push('GetBlipInfoIdCoord', (S) => {
  lua.lua_newtable(S);
  for (const k of ['x', 'y', 'z']) {
    lua.lua_pushnumber(S, 100); lua.lua_setfield(S, -2, to_luastring(k));
  }
  return 1;
});
push('GenerateDirectionsToCoord', (S) => {
  lua.lua_pushboolean(S, true); lua.lua_pushnumber(S, 3);
  lua.lua_pushnumber(S, 0); lua.lua_pushnumber(S, 40);
  return 4;
});
// ox_lib's cache table: cache.vehicle is the on-foot test.
lua.lua_newtable(L);
lua.lua_setglobal(L, to_luastring('cache'));
function setVehicle(v) {
  inVehicle = v;
  lua.lua_getglobal(L, to_luastring('cache'));
  if (v) lua.lua_pushnumber(L, 42); else lua.lua_pushnil(L);
  lua.lua_setfield(L, -2, to_luastring('vehicle'));
  lua.lua_pop(L, 1);
}
setVehicle(true);

if (lauxlib.luaL_loadstring(L, to_luastring(chunk)) !== lua.LUA_OK)
  throw new Error('load: ' + lua.lua_tojsstring(L, -1));
if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK)
  throw new Error('run: ' + lua.lua_tojsstring(L, -1));

function tick() {
  lua.lua_getglobal(L, to_luastring('__test'));
  lua.lua_getfield(L, -1, to_luastring('updateNav'));
  lua.lua_pushnumber(L, 1);
  if (lua.lua_pcall(L, 1, 0, 0) !== lua.LUA_OK)
    throw new Error('updateNav: ' + lua.lua_tojsstring(L, -1));
  lua.lua_pop(L, 1);
}

// Driving, near a junction: the popup is pushed active.
tick();
ok(sent.length === 1 && sent[0].action === 'nav' && sent[0].active === true,
   'driving toward a junction pushes an active nav payload', sent);

// Step out of the car mid-route.
sent.length = 0;
setVehicle(false);
tick();
ok(sent.length === 1 && sent[0].active === false,
   'leaving the vehicle sends an explicit teardown, so the bar fades instead ' +
   'of freezing on screen', sent);

// Still on foot: silence, not a teardown every tick.
sent.length = 0;
tick(); tick(); tick();
ok(sent.length === 0, 'on foot it then stays quiet rather than re-sending', sent);

// Back in the car: it comes straight back.
sent.length = 0;
setVehicle(true);
tick();
ok(sent.length === 1 && sent[0].active === true, 'getting back in restores it', sent);

console.log(fails ? '\n' + fails + ' check(s) failed' : '\nall checks passed');
process.exit(fails ? 1 : 0);
