/* Checks the minimap corner-radius family.
 *
 *   npm i fengari && node tools/radius.test.js
 *
 * Run this after editing MASK_STEPS in client.lua or STEPS in make_masks.py --
 * the two have to agree, and a mismatch is silent in game (the mask simply
 * fails to stream and the map goes square).
 *
 * Runs the REAL snapMaskRadius / maskDictFor out of client.lua under fengari,
 * and checks every dict they can name actually exists in stream/ and contains a
 * usable mask. */
const fs = require('fs');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

// Resource root, with forward slashes so the paths below read the same on
// Windows and elsewhere.
const root = require('path').dirname(__dirname).replace(/\\/g, '/') + '/';
const src = fs.readFileSync(root + 'client.lua', 'utf8');

// Lift the two functions and their table verbatim, so this tests the shipped
// code rather than a copy of it.
const a = src.indexOf('local MASK_STEPS =');
const b = src.indexOf('local maskRadius = snapMaskRadius');
const c = src.indexOf('local function maskDictFor');
const d = src.indexOf('\nend', c) + 4;
if (a < 0 || b < 0 || c < 0) throw new Error('could not locate the radius helpers in client.lua');
const chunk = src.slice(a, b) + src.slice(c, d);

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

const harness = chunk + `
local out = {}
local function rec(v) out[#out+1] = tostring(v) .. '=' .. maskDictFor(v) .. '@' .. snapMaskRadius(v) end
for _, v in ipairs({ -10, 0, 1, 2, 3, 5, 8, 9, 13, 26, 45, 49, 50, 51, 999 }) do rec(v) end
-- Every step must round-trip to itself, or the panel would show a value that
-- snaps to something else the moment it is re-sent.
local rt = {}
for _, s in ipairs(MASK_STEPS) do
  if snapMaskRadius(s) ~= s then rt[#rt+1] = s end
end
-- Stepping by the editor's step size must always land on a real step.
local walk = {}
for _, s in ipairs(MASK_STEPS) do
  for _, delta in ipairs({ -4, 4 }) do
    local v = math.max(0, math.min(50, s + delta))
    walk[#walk+1] = s .. (delta > 0 and '+4' or '-4') .. '->' .. snapMaskRadius(v)
  end
end
local dicts = {}
for _, s in ipairs(MASK_STEPS) do dicts[#dicts+1] = maskDictFor(s) end
return table.concat(out, '\\n') .. '\\n@@RT@@' .. table.concat(rt, ',')
    .. '\\n@@DICTS@@' .. table.concat(dicts, ',')
    .. '\\n@@WALK@@' .. table.concat(walk, ' ')
`;

if (lauxlib.luaL_dostring(L, to_luastring(harness)) !== lua.LUA_OK) {
  console.log('LUA FAIL', lua.lua_tojsstring(L, -1));
  process.exit(1);
}
const res = lua.lua_tojsstring(L, -1);
const [mapping, rest] = res.split('\n@@RT@@');
const [rt, rest2] = rest.split('\n@@DICTS@@');
const [dicts, walk] = rest2.split('\n@@WALK@@');

let fails = 0;
const ok = (cond, label, extra) => {
  if (cond) console.log('  PASS  ' + label);
  else { console.log('  FAIL  ' + label + (extra !== undefined ? '  -> ' + extra : '')); fails++; }
};

console.log('snap / dict mapping:');
mapping.split('\n').forEach(l => console.log('   ' + l));

console.log('\nchecks:');
ok(rt === '', 'every baked step snaps to itself', rt);
ok(/-10=vice_mask_00/.test(mapping), 'negative clamps to the square mask');
ok(/999=vice_mask_50/.test(mapping), 'huge clamps to the stadium mask');
ok(/\b3=vice_mask_04/.test(mapping), '3 snaps up to 4');
ok(/\b13=vice_mask_12/.test(mapping), '13 snaps down to 12');
ok(/\b26=vice_mask_24/.test(mapping) || /\b26=vice_mask_28/.test(mapping), '26 snaps to a neighbour');

const streamDir = root + 'stream/';
const missing = dicts.split(',').filter(dn => !fs.existsSync(streamDir + dn + '.ytd'));
ok(missing.length === 0, 'every dict a step names exists in stream/', missing.join(', '));

// The editor steps by 4; nothing may land off-list.
const stepSet = new Set(dicts.split(',').map(n => parseInt(n.slice(-2), 10)));
const strays = walk.split(' ').filter(w => !stepSet.has(parseInt(w.split('->')[1], 10)));
ok(strays.length === 0, 'stepping by 4 always lands on a baked step', strays.join(' '));

// A single button press must move exactly one step, never two.
const idx = n => [...stepSet].sort((p,q)=>p-q).indexOf(n);
const jumps = walk.split(' ').filter(w => {
  const from = parseInt(w, 10), to = parseInt(w.split('->')[1], 10);
  const hop = Math.abs(idx(to) - idx(from));
  return hop > 1;
});
ok(jumps.length === 0, 'one press moves exactly one step', jumps.join(' '));

// And the files must be real masks, not the blank one that shipped mid-session.
const zlib = require('zlib');
const bad = [];
dicts.split(',').forEach(dn => {
  const raw = zlib.inflateRawSync(fs.readFileSync(streamDir + dn + '.ytd').subarray(16));
  const px = raw.subarray(8192);
  const alpha = (x, y) => px[((y * 512 + x) * 4) + 3];
  if (alpha(256, 128) !== 255) bad.push(dn + ' centre=' + alpha(256, 128));
  if (alpha(0, 0) !== 0) bad.push(dn + ' corner=' + alpha(0, 0));
  if (!raw.subarray(0, 8192).includes(Buffer.from('radarmasksm'))) bad.push(dn + ' name');
});
ok(bad.length === 0, 'every mask is opaque in the centre, clear at the corner, named radarmasksm', bad.join('; '));

console.log('\n' + (fails ? fails + ' FAILING' : 'all checks passed'));
process.exit(fails ? 1 : 0);
