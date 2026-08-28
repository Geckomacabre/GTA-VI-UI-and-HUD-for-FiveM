/* Guards the waypoint route colour against the "two lines on the map" bug.
 *
 *   npm i fengari && node tools/waypoint.test.js
 *
 * The route used to be recoloured with SET_BLIP_ROUTE(blip, true) +
 * SET_BLIP_ROUTE_COLOUR on the vanilla waypoint blip. That does not recolour
 * the line the game already draws -- it adds a SECOND one beside it. The fix
 * repaints HUD_COLOUR_WAYPOINT (and its light/dark companions) instead, so
 * this asserts both halves: the right palette slots get the pink, and no blip
 * route is created at all. Also checks the stop path puts Rockstar's purples
 * back, since REPLACE_HUD_COLOUR_WITH_RGBA outlives the resource.
 *
 * Runs the REAL config.lua + applyWaypointPalette under fengari. */
const fs = require('fs'), path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const root = path.dirname(__dirname).replace(/\\/g, '/') + '/';
const cfg = fs.readFileSync(root + 'config.lua', 'utf8');
const src = fs.readFileSync(root + 'client.lua', 'utf8');

const a = src.indexOf('local function applyWaypointPalette');
const b = src.indexOf('local function getWaypointCoords');
if (a < 0 || b < 0) throw new Error('block not found');
const chunk = cfg + '\n' + src.slice(a, b) +
  '\n__test = { apply = applyWaypointPalette }\n';

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const calls = [];
function push(name, fn) {
  lua.lua_pushjsfunction(L, fn);
  lua.lua_setglobal(L, to_luastring(name));
}
push('ReplaceHudColourWithRgba', (L) => {
  calls.push([1,2,3,4,5].map(i => lua.lua_tonumber(L, i)));
  return 0;
});
for (const n of ['SetBlipRoute','SetBlipRouteColour','SetBlipColour'])
  push(n, () => { calls.push([n]); return 0; });

if (lauxlib.luaL_loadstring(L, to_luastring(chunk)) !== lua.LUA_OK)
  throw new Error('load: ' + lua.lua_tojsstring(L, -1));
if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK)
  throw new Error('run: ' + lua.lua_tojsstring(L, -1));

let fails = 0;
const ok = (c, l, e) => c ? console.log('  PASS  ' + l)
  : (console.log('  FAIL  ' + l + (e !== undefined ? '  -> ' + JSON.stringify(e) : '')), fails++);

ok(calls.length === 3, 'three palette slots repainted at start', calls);
ok(JSON.stringify(calls) === JSON.stringify([
  [142,232,70,122,255],[150,245,172,195,255],[151,116,35,61,255]]),
  'start repaint = pink on 142/150/151', calls);
ok(!JSON.stringify(calls).includes('SetBlipRoute'), 'no second route is created');

// now the revert path
calls.length = 0;
lua.lua_getglobal(L, to_luastring('__test'));
lua.lua_getfield(L, -1, to_luastring('apply'));
lua.lua_pushboolean(L, true);
if (lua.lua_pcall(L, 1, 0, 0) !== lua.LUA_OK)
  throw new Error('revert: ' + lua.lua_tojsstring(L, -1));
ok(JSON.stringify(calls) === JSON.stringify([
  [142,164,76,242,255],[150,210,166,249,255],[151,82,38,121,255]]),
  'stop restores stock HUD_COLOUR_WAYPOINT purples', calls);

console.log(fails ? '\nFAILED ' + fails : '\nall ok');
process.exit(fails ? 1 : 0);
