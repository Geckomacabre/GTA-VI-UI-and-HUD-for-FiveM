/* The Lua half of the Slim Jim / Smash Window fix: the icon is RESOLVED from
 * the caller's own keybind, not a separately hand-picked string.
 *
 *   npm i fengari && node tools/worldactions.test.js
 *
 * Runs the real ShowWorldActions/waResolveKey/waUsingPad lifted out of
 * client_overlays.lua, with GetControlInstructionalButton stubbed to return
 * different button text for keyboard vs pad -- exactly the axis that broke
 * before: the shown icon and the working button had no connection to each
 * other and drifted apart. This pins that they cannot any more, because the
 * icon IS the resolution of the same key the caller's keybind fires on.
 */
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const root = path.dirname(__dirname).replace(/\\/g, '/') + '/';
const src = fs.readFileSync(root + 'client_overlays.lua', 'utf8');

let fails = 0;
const ok = (c, l, e) => c ? console.log('  PASS  ' + l)
  : (console.log('  FAIL  ' + l + (e !== undefined ? '  -> ' + JSON.stringify(e) : '')), fails++);

const a = src.indexOf('local function waSafeLabel');
const b = src.indexOf('\nend, false)', src.indexOf("RegisterCommand('hudworldactions'")) + '\nend, false)'.length;
if (a < 0 || b < 12) throw new Error('could not locate the world-actions block');

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const sent = [];
const push = (n, f) => { lua.lua_pushjsfunction(L, f); lua.lua_setglobal(L, to_luastring(n)); };
push('ui', (S) => {
  const action = lua.lua_tojsstring(S, 1);
  const opts = [];
  lua.lua_getfield(S, 2, to_luastring('options'));
  if (lua.lua_istable(S, -1)) {
    const n = lua.lua_objlen ? lua.lua_objlen(S, -1) : lua.lua_rawlen(S, -1);
    for (let i = 1; i <= n; i++) {
      lua.lua_rawgeti(S, -1, i);
      lua.lua_getfield(S, -1, to_luastring('label'));  const label = lua.lua_tojsstring(S, -1); lua.lua_pop(S, 1);
      lua.lua_getfield(S, -1, to_luastring('glyph'));  const glyph = lua.lua_tojsstring(S, -1); lua.lua_pop(S, 1);
      lua.lua_getfield(S, -1, to_luastring('device')); const device = lua.lua_tojsstring(S, -1); lua.lua_pop(S, 1);
      opts.push({ label, glyph, device });
      lua.lua_pop(S, 1);
    }
  }
  lua.lua_pop(S, 1);
  sent.push({ action, options: opts });
  return 0;
});
push('RegisterCommand', () => 0);
push('PlayerId', (S) => { lua.lua_pushnumber(S, 1); return 1; });
push('CreateThread', () => 0);   // the refresh thread; driven manually below

// A pad by default (usingPad = not IsInputDisabled(2)); toggled per test.
let inputDisabled = true;   // keyboard: control group 2 IS disabled while typing/aiming... 
push('IsInputDisabled', (S) => { lua.lua_pushboolean(S, inputDisabled); return 1; });
// GetControlInstructionalButton(0, key, true) -> "\x00\x00" + button text,
// matching the real native's "two-byte prefix" shape that resolveKey strips
// with :sub(3). Different text for the two hashes under test, and for
// keyboard vs pad, so a wrong resolution shows up as the wrong string.
push('GetControlInstructionalButton', (S) => {
  const key = lua.lua_tonumber(S, 2);
  const pad = !inputDisabled;
  let text;
  if (key === 111) text = pad ? 'Y' : 'R';       // slim jim's hash
  else if (key === 222) text = pad ? 'B' : 'F';  // smash window's hash
  else text = '?';
  lua.lua_pushstring(L, to_luastring('\0\0' + text));
  return 1;
});

// Real client_overlays.lua calls `exports('ShowWorldActions', fn)`. Stub
// `exports` to stash the function under a plain global instead, so this test
// can call the SAME closure the resource actually registers.
push('exports', (S) => {
  const name = lua.lua_tojsstring(S, 1);
  lua.lua_pushvalue(S, 2);
  lua.lua_setglobal(S, to_luastring('__exported_' + name));
  return 0;
});

if (lauxlib.luaL_loadstring(L, to_luastring(src.slice(a, b))) !== lua.LUA_OK)
  throw new Error('load: ' + lua.lua_tojsstring(L, -1));
if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK)
  throw new Error('run: ' + lua.lua_tojsstring(L, -1));

function callExported(name, arg) {
  lua.lua_getglobal(L, to_luastring('__exported_' + name));
  if (arg === undefined) { lua.lua_newtable(L); }
  else {
    lua.lua_newtable(L);
    arg.forEach((opt, i) => {
      lua.lua_newtable(L);
      lua.lua_pushstring(L, to_luastring(opt.label)); lua.lua_setfield(L, -2, to_luastring('label'));
      lua.lua_pushnumber(L, opt.key); lua.lua_setfield(L, -2, to_luastring('key'));
      lua.lua_rawseti(L, -2, i + 1);
    });
  }
  if (lua.lua_pcall(L, 1, 0, 0) !== lua.LUA_OK)
    throw new Error(name + ': ' + lua.lua_tojsstring(L, -1));
}

// ---- keyboard: the two options resolve to their REAL bound letters --------
inputDisabled = true;
sent.length = 0;
callExported('ShowWorldActions', [
  { label: 'Slim Jim', key: 111 },
  { label: 'Smash Window', key: 222 },
]);
ok(sent.length === 1 && sent[0].action === 'worldActions', 'ShowWorldActions pushes on the worldActions action');
const kbm = sent[0].options;
ok(kbm[0].glyph === 'R' && kbm[0].device === 'kbm', 'Slim Jim resolves to its real keyboard key (R)', kbm[0]);
ok(kbm[1].glyph === 'F' && kbm[1].device === 'kbm', 'Smash Window resolves to ITS real key (F), not Slim Jim\'s', kbm[1]);

// ---- pad: the SAME two keys resolve to the pad glyphs, correctly paired ---
inputDisabled = false;
sent.length = 0;
callExported('ShowWorldActions', [
  { label: 'Slim Jim', key: 111 },
  { label: 'Smash Window', key: 222 },
]);
const pad = sent[0].options;
ok(pad[0].glyph === 'Y' && pad[0].device === 'pad',
   'on pad, Slim Jim resolves to Y/Triangle -- the button the keybind is ACTUALLY on', pad[0]);
ok(pad[1].glyph === 'B' && pad[1].device === 'pad',
   'and Smash Window resolves to B/Circle -- not swapped with Slim Jim\'s', pad[1]);

// ---- this is the actual bug: the two keys must never resolve to the SAME
// glyph, or the icon would tell the player to press a button that fires the
// other action (exactly what shipped before this fix).
ok(pad[0].glyph !== pad[1].glyph, 'the two options never resolve to the same glyph', pad);

console.log(fails ? '\n' + fails + ' check(s) failed' : '\nall checks passed');
process.exit(fails ? 1 : 0);
