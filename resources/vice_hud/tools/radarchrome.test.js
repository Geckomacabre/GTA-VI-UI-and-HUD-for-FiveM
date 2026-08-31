/* setRadar() is the single gate between the engine's radar and the page.
 *
 *   npm i fengari && node tools/radarchrome.test.js
 *
 * Two of its four callers sit inside the 250ms poll loop, so the thing worth
 * pinning is that it reports TRANSITIONS, not ticks, otherwise the page would
 * take a mapRect message four times a second forever. Runs the real setRadar
 * lifted out of client.lua.
 */
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const root = path.dirname(__dirname).replace(/\\/g, '/') + '/';
const src = fs.readFileSync(root + 'client.lua', 'utf8').replace(/\r\n/g, '\n'); // normalise CRLF: client.lua is CRLF on disk, and this file's \n-only string searches below assumed LF

let fails = 0;
const ok = (c, l, e) => c ? console.log('  PASS  ' + l)
  : (console.log('  FAIL  ' + l + (e !== undefined ? '  -> ' + JSON.stringify(e) : '')), fails++);

const a = src.indexOf('local radarShown = nil');
const b = src.indexOf('\nend\n', src.indexOf('local function setRadar')) + 5;
if (a < 0 || b < 5) throw new Error('could not locate setRadar in client.lua');
const chunk = src.slice(a, b) + '\n__test = { setRadar = setRadar }\n';

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const radar = [];   // every DisplayRadar call
const sent = [];    // every ui() push
const push = (n, f) => { lua.lua_pushjsfunction(L, f); lua.lua_setglobal(L, to_luastring(n)); };
push('DisplayRadar', (S) => { radar.push(lua.lua_toboolean(S, 1)); return 0; });
push('ui', (S) => {
  const action = lua.lua_tojsstring(S, 1);
  lua.lua_getfield(S, 2, to_luastring('visible'));
  sent.push({ action, visible: lua.lua_toboolean(S, -1) });
  return 0;
});

if (lauxlib.luaL_loadstring(L, to_luastring(chunk)) !== lua.LUA_OK)
  throw new Error('load: ' + lua.lua_tojsstring(L, -1));
if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK)
  throw new Error('run: ' + lua.lua_tojsstring(L, -1));

function call(on) {
  lua.lua_getglobal(L, to_luastring('__test'));
  lua.lua_getfield(L, -1, to_luastring('setRadar'));
  lua.lua_pushboolean(L, on);
  if (lua.lua_pcall(L, 1, 0, 0) !== lua.LUA_OK)
    throw new Error('setRadar: ' + lua.lua_tojsstring(L, -1));
  lua.lua_pop(L, 1);
}

// First call: the native fires and the page is told, since nil is not false.
call(false);
ok(radar.length === 1 && radar[0] === false, 'the native is called every time');
ok(sent.length === 1 && sent[0].action === 'mapRect' && sent[0].visible === false,
   'the first call reports to the page on the mapRect action', sent);

// The poll loop hammering the same state must not keep pushing.
sent.length = 0;
call(false); call(false); call(false);
ok(radar.length === 4, 'the native still gets every call (it is cheap and idempotent)');
ok(sent.length === 0, 'but an unchanged state pushes nothing', sent);

// A real transition does push, once.
call(true); call(true);
ok(sent.length === 1 && sent[0].visible === true, 'a transition pushes exactly once', sent);

// And back again.
sent.length = 0;
call(false);
ok(sent.length === 1 && sent[0].visible === false, 'and again on the way back', sent);

console.log(fails ? '\n' + fails + ' check(s) failed' : '\nall checks passed');
process.exit(fails ? 1 : 0);
