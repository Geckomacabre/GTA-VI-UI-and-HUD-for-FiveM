/* Checks the skills XP curve and level resolution.
 *
 *   npm i fengari && node tools/skills.test.js
 *
 * Runs the REAL skills.lua under fengari. The curve is worth testing rather
 * than eyeballing for two reasons: a level IS the GTA stat value, so an
 * off-by-one is a stat the engine is actually using; and the shape of the curve
 * is a design decision that is easy to break by "tidying" the maths.
 *
 * It also prints the resulting progression so the numbers can be judged as
 * numbers instead of argued about in the abstract.
 */
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const root = path.dirname(__dirname).replace(/\\/g, '/') + '/';

let fails = 0;
function ok(cond, label, extra) {
  if (cond) console.log('  PASS  ' + label);
  else { console.log('  FAIL  ' + label + (extra !== undefined ? '   -> ' + extra : '')); fails++; }
}

function runLua(chunk) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const out = [];
  lua.lua_pushjsfunction(L, (S) => {
    const n = lua.lua_gettop(S);
    const parts = [];
    for (let i = 1; i <= n; i++) parts.push(lua.lua_tojsstring(S, i));
    out.push(parts.join('\t'));
    return 0;
  });
  lua.lua_setglobal(L, to_luastring('print'));
  if (lauxlib.luaL_loadbuffer(L, to_luastring(chunk), null, to_luastring('@skills')) !== lua.LUA_OK) {
    throw new Error('load failed: ' + lua.lua_tojsstring(L, -1));
  }
  if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    throw new Error('run failed: ' + lua.lua_tojsstring(L, -1));
  }
  return out;
}

const src = fs.readFileSync(root + 'skills.lua', 'utf8')
  // The trailing `return Skills` is a module convention; as a bare chunk it
  // would end execution before the drive code below.
  .replace(/\nreturn Skills\s*$/, '\n');

const drive = `
local function emit(k, v) print(k .. '|' .. tostring(v)) end

emit('count', #Skills.List)
emit('max', Skills.MAX_LEVEL)

-- Every skill must be uniquely identified and name a stat, or the client would
-- write a level into a stat that does not exist and fail silently.
local seenId, seenStat, dupes = {}, {}, 0
for i = 1, #Skills.List do
  local s = Skills.List[i]
  if seenId[s.id] or seenStat[s.stat] then dupes = dupes + 1 end
  seenId[s.id], seenStat[s.stat] = true, true
  if type(s.stat) ~= 'string' or s.stat == '' then dupes = dupes + 100 end
  if type(s.rate) ~= 'number' or s.rate <= 0 then dupes = dupes + 1000 end
  if type(s.unit) ~= 'string' then dupes = dupes + 10000 end
end
emit('dupes', dupes)
emit('byid', Skills.ById.stamina and Skills.ById.stamina.stat or 'MISSING')

-- The curve must rise, so a later level always costs more than an earlier one.
local rising = true
for n = 0, Skills.MAX_LEVEL - 2 do
  if Skills.xpToNext(n + 1) <= Skills.xpToNext(n) then rising = false end
end
emit('rising', rising)
emit('cost0', Skills.xpToNext(0))
emit('cost50', Skills.xpToNext(50))
emit('cost99', Skills.xpToNext(99))
emit('costMax', Skills.xpToNext(Skills.MAX_LEVEL))
emit('total', Skills.xpForLevel(Skills.MAX_LEVEL))

-- resolve() is the inverse of xpForLevel. If those two ever disagree the number
-- on screen and the stat handed to the engine come apart.
local roundTrip = true
for lvl = 0, Skills.MAX_LEVEL do
  local at = Skills.xpForLevel(lvl)
  local got = Skills.resolve(at)
  if got ~= lvl then roundTrip = false end
  -- One XP short of the threshold must still be the level below.
  if lvl > 0 and Skills.resolve(at - 1) ~= lvl - 1 then roundTrip = false end
end
emit('roundtrip', roundTrip)

local l, into, need, frac = Skills.resolve(0)
emit('zero', l .. ',' .. into .. ',' .. need .. ',' .. string.format('%.2f', frac))
l, into, need, frac = Skills.resolve(Skills.xpForLevel(3) + 50)
emit('mid', l .. ',' .. into .. ',' .. need .. ',' .. string.format('%.3f', frac))

-- Past the cap nothing may run away: no level above MAX, and no negative or
-- nonsensical progress to render.
l, into, need, frac = Skills.resolve(Skills.xpForLevel(Skills.MAX_LEVEL) + 999999)
emit('capped', l .. ',' .. into .. ',' .. need .. ',' .. string.format('%.2f', frac))
emit('negative', (Skills.resolve(-500)))

-- normalise() is the boundary against storage: a database row, an export, or a
-- KVP written by an older version.
local n1 = Skills.normalise(nil)
local n2 = Skills.normalise({ stamina = 'not a number', strength = -40, lung = 12.9, gone = 5 })
emit('norm_nil_stamina', n1.stamina)
emit('norm_keys', (function() local c = 0 for _ in pairs(n2) do c = c + 1 end return c end)())
emit('norm_junk', n2.stamina)
emit('norm_negative', n2.strength)
emit('norm_float', n2.lung)
emit('norm_unknown', tostring(n2.gone))

-- How long does a level actually take? Printed so the pacing is a decision
-- someone looked at, not an accident of the constants.
for i = 1, #Skills.List do
  local s = Skills.List[i]
  local id = s.id
  local units1 = Skills.xpToNext(0) / s.rate
  local units50 = Skills.xpToNext(50) / s.rate
  local unitsAll = Skills.xpForLevel(Skills.MAX_LEVEL) / s.rate
  print(('pace|%s|%.0f|%.0f|%.0f|%s'):format(id, units1, units50, unitsAll, s.unit))
end
`;

const lines = runLua(src + drive);
const got = {};
const pace = [];
lines.forEach((l) => {
  const p = l.split('|');
  if (p[0] === 'pace') pace.push(p.slice(1));
  else got[p[0]] = p[1];
});

console.log('\n-- definitions --');
ok(+got.count === 8, 'eight skills defined', got.count);
ok(+got.dupes === 0, 'each has a unique id and stat, a positive rate and a named unit', got.dupes);
ok(got.byid === 'STAMINA', 'the id index is built', got.byid);
ok(+got.max === 100, 'levels run 0..100, matching the GTA stat range exactly', got.max);

console.log('\n-- the curve --');
ok(got.rising === 'true', 'every level costs more than the one before it');
ok(+got.cost0 === 100, 'first level costs 100', got.cost0);
ok(+got.cost99 > +got.cost50 && +got.cost50 > +got.cost0, 'and it keeps rising to the cap',
   got.cost0 + ' / ' + got.cost50 + ' / ' + got.cost99);
// Quadratic, not exponential: the last ten levels must not cost more than the
// first ninety, which is what makes a cap reachable rather than theoretical.
const lastTen = 10 * +got.cost99;
ok(lastTen < +got.total / 2, 'the last ten levels are not most of the grind',
   'last10~' + lastTen + ' of ' + got.total);
ok(+got.costMax === 0, 'nothing is owed past the cap', got.costMax);

console.log('\n-- resolving xp back into a level --');
ok(got.roundtrip === 'true', 'resolve() is the exact inverse of xpForLevel() at every level');
ok(got.zero === '0,0,100,0.00', 'zero xp is level 0 with a full bar to go', got.zero);
ok(got.mid === '3,50,154,0.325', 'mid-level progress reports the fraction into the level', got.mid);
ok(got.capped === '100,0,0,1.00', 'past the cap it pins at 100 with a full bar', got.capped);
ok(+got.negative === 0, 'negative xp cannot produce a negative level', got.negative);

console.log('\n-- storage boundary --');
ok(+got.norm_nil_stamina === 0, 'a missing store yields every skill at zero');
ok(+got.norm_keys === 8, 'normalise always returns every skill', got.norm_keys);
ok(+got.norm_junk === 0, 'a non-numeric value becomes zero rather than propagating', got.norm_junk);
ok(+got.norm_negative === 0, 'a negative value becomes zero', got.norm_negative);
ok(+got.norm_float === 12, 'floats are floored, because xp is whole', got.norm_float);
ok(got.norm_unknown === 'nil', 'a key that is no longer a skill is dropped', got.norm_unknown);

console.log('\n-- pacing, for judging the numbers --');
console.log('  skill      lvl 0->1      lvl 50->51        0->100   unit');
pace.forEach(([id, a, b, c, unit]) => {
  console.log('  ' + id.padEnd(10) + a.padStart(8) + b.padStart(14) + c.padStart(14) + '   ' + unit);
});

console.log('\n' + (fails ? fails + ' FAILING' : 'all checks passed'));
process.exit(fails ? 1 : 0);
