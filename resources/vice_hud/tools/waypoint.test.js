/* Guards the waypoint route colour against the "two lines on the map" bug,
 * and against the pink/teal-by-gender split silently reverting to one colour.
 *
 *   npm i fengari && node tools/waypoint.test.js
 *
 * The route used to be recoloured with SET_BLIP_ROUTE(blip, true) +
 * SET_BLIP_ROUTE_COLOUR on the vanilla waypoint blip. That does not recolour
 * the line the game already draws, it adds a SECOND one beside it. The fix
 * repaints HUD_COLOUR_WAYPOINT (and its light/dark companions) instead, so
 * this asserts both halves: the right palette slots get the right accent
 * ('pink'|'teal', passed in by the caller, no longer an eager top-level
 * call, see applyWaypointPalette's own comment in client.lua for why), and no
 * blip route is created at all. Also checks the stop path puts Rockstar's
 * purples back, since REPLACE_HUD_COLOUR_WITH_RGBA outlives the resource.
 *
 * Runs the REAL config.lua + applyWaypointPalette under fengari. */
const fs = require('fs'), path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const root = path.dirname(__dirname).replace(/\\/g, '/') + '/';
const cfg = fs.readFileSync(root + 'config.lua', 'utf8');
const src = fs.readFileSync(root + 'client.lua', 'utf8');

// Not `local function` any more, it assigns a pre-declared upvalue (see
// the `local applyWaypointPalette` forward-declaration next to `updateNav`
// above its own do...end block, and that block's own comment for why: it's
// called from the main loop, well outside the block it's defined in, same
// as updateNav already was). This harness supplies that upvalue itself
// rather than lifting the real forward-declaration out too.
const a = src.indexOf('applyWaypointPalette = function');
const b = src.indexOf('local function getWaypointCoords');
if (a < 0 || b < 0) throw new Error('block not found');
const chunk = cfg + '\nlocal applyWaypointPalette\n' + src.slice(a, b) +
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

function apply(revert, accentKey) {
  calls.length = 0;
  lua.lua_getglobal(L, to_luastring('__test'));
  lua.lua_getfield(L, -1, to_luastring('apply'));
  lua.lua_pushboolean(L, revert);
  if (accentKey === undefined) lua.lua_pushnil(L);
  else lua.lua_pushstring(L, to_luastring(accentKey));
  if (lua.lua_pcall(L, 2, 0, 0) !== lua.LUA_OK)
    throw new Error('apply: ' + lua.lua_tojsstring(L, -1));
}

apply(false, 'pink');
ok(calls.length === 3, 'three palette slots repainted', calls);
ok(JSON.stringify(calls) === JSON.stringify([
  [142,252,116,164,255],[150,254,192,214,255],[151,126,58,82,255]]),
  'pink accent = pink RGB on 142/150/151', calls);
ok(!JSON.stringify(calls).includes('SetBlipRoute'), 'no second route is created');

apply(false, 'teal');
ok(JSON.stringify(calls) === JSON.stringify([
  [142,71,171,167,255],[150,172,217,215,255],[151,36,86,84,255]]),
  'teal accent = teal RGB on 142/150/151', calls);

apply(false, undefined);
ok(JSON.stringify(calls) === JSON.stringify([
  [142,252,116,164,255],[150,254,192,214,255],[151,126,58,82,255]]),
  'no accent key given falls back to pink', calls);

// now the revert path, same for either accent, since stock is shared
apply(true, 'teal');
ok(JSON.stringify(calls) === JSON.stringify([
  [142,164,76,242,255],[150,210,166,249,255],[151,82,38,121,255]]),
  'stop restores stock HUD_COLOUR_WAYPOINT purples', calls);

console.log(fails ? '\nFAILED ' + fails : '\nall ok');
process.exit(fails ? 1 : 0);
