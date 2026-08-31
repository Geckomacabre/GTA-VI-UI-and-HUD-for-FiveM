/* The health row shows while the weapon/item wheel is held (Tab), or while
 * the full F2 inventory screen is open.
 *
 *   npm i fengari && node tools/wheelheld.test.js
 *
 * ROUND 2: the first version of this also OR'd in IsDisabledControlPressed(0,
 * 37), reasoning that ox_inventory disables control 37 while it owns Tab.
 * That reasoning was flagged unverified (no running game to check against),
 * and it was wrong in a specific, reproducible way: this server's
 * ox_inventory config disables control 37 on almost every frame the
 * inventory is CLOSED (`not EnableWeaponWheel`, the default) -- so
 * IsDisabledControlPressed read true nearly all the time regardless of
 * whether Tab was actually held, and the health row never went nominal again
 * ("stays on screen even when full", reported after the fix shipped).
 *
 * IsControlPressed alone is correct: it reports the raw physical input for a
 * normal digital button (Tab/INPUT_SELECT_WEAPON is one) regardless of
 * whether DisableControlAction was called on it that frame -- disabling only
 * suppresses the GAME's own reaction, not what this native reports back.
 * This pins that wheelHeld() reflects ONLY the plain control read, and does
 * NOT reference IsDisabledControlPressed at all -- so a future "fix" can't
 * silently reintroduce the same bug.
 *
 * ROUND 3: also true whenever LocalPlayer.state.invOpen is set. ox_inventory
 * sets that state bag flag itself on open/close, so checking a full
 * inventory of medical items doesn't leave the health row hidden at full
 * health, same complaint as the Tab-wheel case above.
 */
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const root = path.dirname(__dirname).replace(/\\/g, '/') + '/';
const src = fs.readFileSync(root + 'client.lua', 'utf8').replace(/\r\n/g, '\n'); // normalise CRLF: client.lua is CRLF on disk, and this file's \n-only string searches below assumed LF

let fails = 0;
const ok = (c, l, e) => c ? console.log('  PASS  ' + l)
  : (console.log('  FAIL  ' + l + (e !== undefined ? '  -> ' + JSON.stringify(e) : '')), fails++);

const a = src.indexOf('local function wheelHeld()');
const b = src.indexOf('\nend\n', a) + 5;
if (a < 0 || b < 5) throw new Error('could not locate wheelHeld() in client.lua');
const body = src.slice(a, b);

ok(!/IsDisabledControlPressed/.test(body),
   'wheelHeld() does not reference IsDisabledControlPressed at all -- ' +
   'the specific native that caused round 1\'s "always shown" bug');

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
let pressed = false;
// Deliberately do NOT define IsDisabledControlPressed in this harness -- if
// wheelHeld() were to call it, the load below would fail with "attempt to
// call a nil value", which is a second, independent guard against the same
// regression alongside the static check above.
lua.lua_pushjsfunction(L, (S) => {
  const action = lua.lua_tonumber(S, 2);
  lua.lua_pushboolean(S, action === 37 && pressed); return 1;
});
lua.lua_setglobal(L, to_luastring('IsControlPressed'));

// LocalPlayer.state is a real FiveM state bag in the game; here it's just a
// plain mutable table the JS side below can flip between cases the same way
// it flips `pressed` above.
if (lauxlib.luaL_dostring(L, to_luastring(
  "LocalPlayer = { state = { invOpen = false } }")) !== lua.LUA_OK)
  throw new Error('setup: ' + lua.lua_tojsstring(L, -1));

if (lauxlib.luaL_loadstring(L, to_luastring(body +
  '\n__test = { wheelHeld = wheelHeld }\n')) !== lua.LUA_OK)
  throw new Error('load: ' + lua.lua_tojsstring(L, -1));
if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK)
  throw new Error('run: ' + lua.lua_tojsstring(L, -1));

function setInvOpen(v) {
  if (lauxlib.luaL_dostring(L, to_luastring(
    'LocalPlayer.state.invOpen = ' + (v ? 'true' : 'false'))) !== lua.LUA_OK)
    throw new Error('setInvOpen: ' + lua.lua_tojsstring(L, -1));
}

function held() {
  lua.lua_getglobal(L, to_luastring('__test'));
  lua.lua_getfield(L, -1, to_luastring('wheelHeld'));
  if (lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) throw new Error(lua.lua_tojsstring(L, -1));
  const v = lua.lua_toboolean(L, -1);
  lua.lua_pop(L, 2);
  return v;
}

pressed = false;
ok(held() === false, 'not held, inventory closed -> false (this is the state the row must go nominal in)');

pressed = true;
ok(held() === true, 'Tab held -> true');

pressed = false;
setInvOpen(true);
ok(held() === true, 'inventory open (Tab not held) -> true');

setInvOpen(false);
ok(held() === false, 'inventory closed again, Tab not held -> false');

console.log(fails ? '\n' + fails + ' check(s) failed' : '\nall checks passed');
process.exit(fails ? 1 : 0);
