/* Checks the hunger/thirst cap on the health bar -- both ends of it.
 *
 *   npm i fengari jsdom && node tools/needs.test.js
 *
 * Hunger and thirst have no bars of their own. They cap the health bar: below a
 * threshold a darkened tail grows in from the right end, over health that cannot
 * be healed back into, and vice_hud actually enforces that by blocking passive
 * regeneration.
 *
 * Enforcement is the part that can hurt a live server, so most of what follows
 * is about the clamp NOT firing when it shouldn't: it must never lower health,
 * never fight a medkit, and never claw back the full health a respawn or an EMS
 * revive just handed over. That last one is why deliberate heals are told from
 * regeneration by SIZE rather than by reading framework death state -- 'dead'
 * and 'inlaststand' are QBX metadata, not statebags, so the obvious check would
 * have read nil and quietly capped every revived player.
 *
 * Runs the REAL readNeeds/enforceCap lifted out of client.lua with the natives
 * stubbed, then the real app.js against the real markup under jsdom.
 */
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const { JSDOM } = require('jsdom');

const root = path.dirname(__dirname).replace(/\\/g, '/') + '/';
const src = fs.readFileSync(root + 'client.lua', 'utf8');

let fails = 0;
function ok(cond, label, extra) {
  if (cond) console.log('  PASS  ' + label);
  else { console.log('  FAIL  ' + label + (extra !== undefined ? '   -> ' + extra : '')); fails++; }
}

/* =============================================================================
 * The cap
 * ========================================================================== */

// Lifted verbatim so this tests the shipped code rather than a paraphrase.
const a = src.indexOf('local function readNeeds()');
const b = src.indexOf('-- =============================================================================',
                      src.indexOf('local function enforceCap'));
if (a < 0 || b < 0) throw new Error('could not locate readNeeds in client.lua');
const chunk = src.slice(a, b);

function run(drive) {
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

  const stubs = `
    Config = { Needs = { enable = true, warnAt = 25, floorPct = 40,
                         enforce = true, healJumpPct = 10 } }
    LocalPlayer = { state = { hunger = 100, thirst = 100 } }
    __hp, __dead, __maxhp = 200, false, 200
    -- Every write the clamp makes, so the test can assert it fired once with the
    -- right value rather than only that the end state happened to look right.
    __sets = {}
    function GetEntityHealth() return __hp end
    function SetEntityHealth(_, v) __hp = v; __sets[#__sets + 1] = v end
    function IsEntityDead() return __dead end
    function RegisterCommand() end
    function PlayerPedId() return 1 end
    cache = {}
    function __n(v) return v == nil and 'nil' or string.format('%.1f', v) end
  `;
  const full = stubs + chunk + drive;
  if (lauxlib.luaL_loadbuffer(L, to_luastring(full), null, to_luastring('@needs')) !== lua.LUA_OK) {
    throw new Error('load failed: ' + lua.lua_tojsstring(L, -1));
  }
  if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    throw new Error('run failed: ' + lua.lua_tojsstring(L, -1));
  }
  return out;
}

console.log('\n-- the cap curve --');
{
  const g = run(`
    local function at(h, t)
      LocalPlayer.state.hunger, LocalPlayer.state.thirst = h, t
      local cap, cause = readNeeds()
      return __n(cap) .. '/' .. tostring(cause)
    end
    print('a|' .. at(100, 100))
    print('b|' .. at(26, 100))
    print('c|' .. at(25, 100))
    print('d|' .. at(12.5, 100))
    print('e|' .. at(0, 100))
  `).map(l => l.split('|'));
  ok(g[0][1] === 'nil/nil', 'well fed, no cap at all', g[0][1]);
  ok(g[1][1] === 'nil/nil', 'just above the threshold, still nothing', g[1][1]);
  ok(g[2][1] === 'nil/nil',
     'AT the threshold there is still no cap -- the tail appearing has to mean ' +
     'you crossed it, not that you touched it', g[2][1]);
  ok(g[3][1] === '70.0/hunger', 'halfway down from the threshold is halfway to the floor', g[3][1]);
  ok(g[4][1] === '40.0/hunger', 'and empty bottoms out at floorPct, not at zero', g[4][1]);
}

console.log('\n-- which one is low --');
{
  const g = run(`
    local function at(h, t)
      LocalPlayer.state.hunger, LocalPlayer.state.thirst = h, t
      local cap, cause = readNeeds()
      return __n(cap) .. '/' .. tostring(cause)
    end
    print('a|' .. at(100, 10))
    print('b|' .. at(10, 100))
    print('c|' .. at(10, 10))
    print('d|' .. at(20, 10))
  `).map(l => l.split('|'));
  ok(g[0][1] === '64.0/thirst', 'thirst drives it when thirst is lower', g[0][1]);
  ok(g[1][1] === '64.0/hunger', 'hunger when hunger is', g[1][1]);
  ok(g[2][1] === '64.0/hunger',
     'a tie goes to hunger, so the tint cannot flicker on whichever statebag ' +
     'replicated last', g[2][1]);
  ok(g[3][1] === '64.0/thirst', 'and the WORSE of the two sets the depth', g[3][1]);
}

console.log('\n-- before the character loads --');
{
  const g = run(`
    LocalPlayer.state.hunger, LocalPlayer.state.thirst = nil, nil
    print('a|' .. __n((readNeeds())))
    LocalPlayer.state.hunger, LocalPlayer.state.thirst = nil, 10
    print('b|' .. __n((readNeeds())))
    LocalPlayer.state.hunger, LocalPlayer.state.thirst = 'wat', nil
    print('c|' .. __n((readNeeds())))
  `).map(l => l.split('|'));
  ok(g[0][1] === 'nil',
     'no statebags yet is NOT the same as empty -- reading absent as zero would ' +
     'cap every player at the floor for the first seconds of every session', g[0][1]);
  ok(g[1][1] === '64.0', 'one present and one missing caps on what it actually knows', g[1][1]);
  ok(g[2][1] === 'nil', 'a non-numeric statebag is declined rather than thrown on', g[2][1]);
}

console.log('\n-- switched off --');
{
  const g = run(`
    LocalPlayer.state.hunger = 0
    Config.Needs.enable = false
    print('a|' .. __n((readNeeds())))
    Config.Needs.enable = true
    Config.Needs.warnAt = 0
    print('b|' .. __n((readNeeds())))
    Config.Needs = nil
    print('c|' .. __n((readNeeds())))
  `).map(l => l.split('|'));
  ok(g[0][1] === 'nil', 'disabled means no cap', g[0][1]);
  ok(g[1][1] === 'nil', 'a zero threshold means no cap rather than a divide by zero', g[1][1]);
  ok(g[2][1] === 'nil', 'and no config at all is handled', g[2][1]);
}

/* -----------------------------------------------------------------------------
 * Enforcement. maxHp 200 throughout, so the 0..100 bar and raw health differ by
 * exactly 100 and a cap of 70 is raw 170.
 * -------------------------------------------------------------------------- */

console.log('\n-- passive regen stops at the cap --');
{
  const g = run(`
    __hp = 150
    enforceCap(1, 70, 200)                 -- first tick: adopt the baseline
    -- Regenerate a point at a time, well under healJumpPct.
    for _ = 1, 40 do
      __hp = __hp + 1
      enforceCap(1, 70, 200)
    end
    print('a|' .. tostring(__hp))
    print('b|' .. tostring(#__sets))
  `).map(l => l.split('|'));
  ok(g[0][1] === '170',
     'regeneration is held exactly at the cap, not at full', g[0][1]);
  ok(Number(g[1][1]) > 0, 'and the clamp actually fired to do it', g[1][1]);
}

console.log('\n-- it never takes health away --');
{
  const g = run(`
    -- Already above the cap when the player gets hungry. This must cost nothing.
    __hp = 200
    enforceCap(1, 70, 200)
    for _ = 1, 10 do enforceCap(1, 70, 200) end
    print('a|' .. tostring(__hp) .. '/' .. tostring(#__sets))

    -- Now take damage straight through the cap line. Also untouched.
    __hp = 160
    enforceCap(1, 70, 200)
    print('b|' .. tostring(__hp) .. '/' .. tostring(#__sets))

    -- And regen back up from below only goes as far as the cap.
    for _ = 1, 30 do __hp = __hp + 1; enforceCap(1, 70, 200) end
    print('c|' .. tostring(__hp))
  `).map(l => l.split('|'));
  ok(g[0][1] === '200/0',
     'health already above the cap is left alone -- going hungry at full health ' +
     'costs nothing until something takes a bite', g[0][1]);
  ok(g[1][1] === '160/0', 'and damage through the cap line is never our business', g[1][1]);
  ok(g[2][1] === '170', 'healing back up stops at the cap', g[2][1]);
}

console.log('\n-- a deliberate heal is let through --');
{
  const g = run(`
    __hp = 120
    enforceCap(1, 70, 200)
    __hp = 200                             -- a medkit: an 80-point jump
    enforceCap(1, 70, 200)
    print('a|' .. tostring(__hp) .. '/' .. tostring(#__sets))
    -- The baseline moved with it, so the next regen tick does not undo it either.
    __hp = 200
    enforceCap(1, 70, 200)
    print('b|' .. tostring(__hp))
  `).map(l => l.split('|'));
  ok(g[0][1] === '200/0',
     'a jump bigger than healJumpPct is a medkit or a revive, and is honoured', g[0][1]);
  ok(g[1][1] === '200', 'and it is not clawed back on the following tick', g[1][1]);
}

console.log('\n-- death and respawn --');
{
  const g = run(`
    __hp = 150
    enforceCap(1, 70, 200)
    __dead = true
    enforceCap(1, 70, 200)                 -- dead: baseline dropped
    print('a|' .. tostring(lastHealthRaw))
    __dead, __hp = false, 200              -- respawned at full
    enforceCap(1, 70, 200)
    print('b|' .. tostring(__hp) .. '/' .. tostring(#__sets))
    enforceCap(1, 70, 200)
    print('c|' .. tostring(__hp))
  `).map(l => l.split('|'));
  ok(g[0][1] === 'nil', 'death clears the baseline', g[0][1]);
  ok(g[1][1] === '200/0',
     'so a respawn at full health is adopted, NOT read as regeneration and ' +
     'clamped back down to the cap', g[1][1]);
  ok(g[2][1] === '200', 'and it stays adopted on the tick after', g[2][1]);
}

console.log('\n-- enforcement off, and no cap --');
{
  const g = run(`
    Config.Needs.enforce = false
    __hp = 150
    for _ = 1, 60 do __hp = __hp + 1; enforceCap(1, 70, 200) end
    print('a|' .. tostring(__hp) .. '/' .. tostring(#__sets))

    Config.Needs.enforce = true
    __hp = 150
    enforceCap(1, nil, 200)
    for _ = 1, 60 do __hp = __hp + 1; enforceCap(1, nil, 200) end
    print('b|' .. tostring(__hp) .. '/' .. tostring(#__sets))
  `).map(l => l.split('|'));
  ok(g[0][1] === '210/0',
     'with enforce off the tail is only a warning and healing is untouched', g[0][1]);
  ok(g[1][1] === '210/0', 'and with no cap there is nothing to enforce', g[1][1]);
}

console.log('\n-- a raised maximum health --');
{
  // maxHp 400 means the 0..100 bar spans 300 raw points, so a 70% cap is raw
  // 310 and healJumpPct is 30 raw points -- both have to scale or the clamp
  // fires on ordinary regen and refuses ordinary medkits.
  const g = run(`
    __hp = 200
    enforceCap(1, 70, 400)
    for _ = 1, 200 do __hp = __hp + 1; enforceCap(1, 70, 400) end
    print('a|' .. tostring(__hp))
  `).map(l => l.split('|'));
  ok(g[0][1] === '310', 'the cap is a percentage of the real range, not of 200', g[0][1]);
}

/* =============================================================================
 * The tail
 * ========================================================================== */

console.log('\n-- the tail --');

const dom = new JSDOM(fs.readFileSync(root + 'html/index.html', 'utf8'),
                      { url: 'http://localhost/', runScripts: 'outside-only', pretendToBeVisual: true });
const { window } = dom;
const doc = window.document;
window.Element.prototype.scrollIntoView = function () {};
const st = doc.createElement('style');
st.textContent = fs.readFileSync(root + 'html/style.css', 'utf8');
doc.head.appendChild(st);
window.GetParentResourceName = () => 'vice_hud';
window.fetch = () => Promise.resolve({ json: () => Promise.resolve({}) });
window.eval(fs.readFileSync(root + 'html/app.js', 'utf8'));
doc.dispatchEvent(new window.Event('DOMContentLoaded'));

const msg = (data) => window.dispatchEvent(new window.MessageEvent('message', { data }));
const row = doc.getElementById('s-health');
const tail = row.querySelector('.scap');
const scale = (el) => {
  const m = /scaleX\(([\d.]+)\)/.exec(el.style.transform || '');
  return m ? Math.round(parseFloat(m[1]) * 100) : null;
};
const tint = () => {
  const cs = window.getComputedStyle(tail);
  return cs.backgroundColor + ' | ' + cs.borderLeftColor;
};

// Fed and healthy: nothing at all.
msg({ action: 'status', health: 100, armor: 0, stamina: 100 });
ok(scale(tail) === 0, 'no cap, no tail', scale(tail));
ok(!tail.classList.contains('hunger') && !tail.classList.contains('thirst'),
   'and no cause tint');

// Starving at FULL health. The row has to appear on the cap alone.
msg({ action: 'status', health: 100, armor: 0, stamina: 100, cap: 70, capCause: 'hunger' });
ok(!row.classList.contains('hidden'),
   'a cap shows the health row even at 100 health, which health alone never would');
ok(scale(tail) === 30, 'the tail covers everything above the cap', scale(tail));
ok(scale(row.querySelector('.sfill')) === 100,
   'while the FILL stays full -- the cap dims the end of the bar, it does not ' +
   'shorten it, or a capped player would look wounded when they are not',
   scale(row.querySelector('.sfill')));
ok(tail.classList.contains('hunger') && !tail.classList.contains('thirst'),
   'tinted for food');
const hungerTint = tint();

// Same cap, other cause.
msg({ action: 'status', health: 100, armor: 0, stamina: 100, cap: 70, capCause: 'thirst' });
ok(tail.classList.contains('thirst') && !tail.classList.contains('hunger'),
   'tinted for water instead');
ok(tint() !== hungerTint, 'and the two actually look different', tint() + ' vs ' + hungerTint);

// Starving AND hurt: both readings on one row, independently.
msg({ action: 'status', health: 55, armor: 0, stamina: 100, cap: 40, capCause: 'thirst' });
ok(scale(row.querySelector('.sfill')) === 55 && scale(tail) === 60,
   'fill reads health and tail reads the cap, at the same time and separately',
   scale(row.querySelector('.sfill')) + ' / ' + scale(tail));

// Drank something.
msg({ action: 'status', health: 55, armor: 0, stamina: 100 });
ok(scale(tail) === 0, 'the tail goes when the cap does', scale(tail));
ok(!tail.classList.contains('thirst'), 'and takes its tint with it');
ok(!row.classList.contains('hidden'), 'the row stays for the health that is still down');

console.log(fails ? '\n' + fails + ' check(s) failed' : '\nall checks passed');
process.exit(fails ? 1 : 0);
