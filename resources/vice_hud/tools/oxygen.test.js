/* Checks the oxygen half of the stamina row -- both ends of it.
 *
 *   npm i fengari jsdom && node tools/oxygen.test.js
 *
 * Underwater breath shares the stamina bar instead of adding a fourth one, so
 * the feature is only correct if BOTH halves agree about which mode the row is
 * in. That makes it one test file rather than two: the real readOxygen from
 * client.lua under fengari, then the real app.js driving the real markup under
 * jsdom, checked against the payload the Lua half actually sends.
 *
 * The reader's whole difficulty is that nothing reports maximum breath. It
 * moves with the lung-capacity stat and with any script calling
 * SetPedMaxTimeUnderwater, so the ceiling is sampled at the surface -- as the
 * largest reading over a short window of surfaced ticks. Most of what follows is
 * about that sampling being wrong in the ways it can be wrong: never taken,
 * taken mid-refill, gone stale after the stat grew, or -- the one that bit --
 * held forever after dive gear raised it and then took it away again.
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
 * The reader
 * ========================================================================== */

// Lifted verbatim so this tests the shipped code rather than a paraphrase.
const a = src.indexOf('local oxygenSamples = {}');
const b = src.indexOf('-- =============================================================================',
                      src.indexOf('local function readOxygen'));
if (a < 0 || b < 0) throw new Error('could not locate readOxygen in client.lua');
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
    Config = { Tick = 250,
               Oxygen = { enabled = true, defaultSeconds = 10.0, ceilingWindowMs = 3000 } }
    __breath, __under = 10.0, false
    function GetPlayerUnderwaterTimeRemaining() return __breath end
    function IsPedSwimmingUnderWater() return __under end
    -- The lifted section registers its diagnostic command at load.
    function RegisterCommand() end
    function PlayerPedId() return 1 end
    function PlayerId() return 0 end
    cache = {}
    function __pct(v) return v == nil and 'nil' or string.format('%.1f', v) end
  `;
  const full = stubs + chunk + drive;
  if (lauxlib.luaL_loadbuffer(L, to_luastring(full), null, to_luastring('@oxygen')) !== lua.LUA_OK) {
    throw new Error('load failed: ' + lua.lua_tojsstring(L, -1));
  }
  if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    throw new Error('run failed: ' + lua.lua_tojsstring(L, -1));
  }
  return out;
}

console.log('\n-- surfaced --');
{
  const g = run(`
    __under, __breath = false, 10.0
    print('a|' .. __pct(readOxygen(1, 0)))
    print('b|' .. tostring(oxygenMax))
  `).map(l => l.split('|'));
  ok(g[0][1] === 'nil',
     'at the surface it returns nil, which is what leaves the row showing stamina', g[0][1]);
  ok(g[1][1] === '10.0', 'and the surface reading is what teaches it the ceiling', g[1][1]);
}

console.log('\n-- a trained diver --');
{
  // The bug this exists to catch: assuming vanilla 10s for a character whose
  // lung capacity has been trained. 12 of 24 seconds is half a bar, and with a
  // hardcoded ceiling it would read full for the entire first half of the dive.
  const g = run(`
    __under, __breath = false, 24.0
    readOxygen(1, 0)                       -- surface: learn 24s
    __under, __breath = true, 12.0
    print('a|' .. __pct(readOxygen(1, 0)))
    __breath = 6.0
    print('b|' .. __pct(readOxygen(1, 0)))
    __breath = 0.0
    print('c|' .. __pct(readOxygen(1, 0)))
  `).map(l => l.split('|'));
  ok(g[0][1] === '50.0', 'half of a learned 24s ceiling is half a bar, not full', g[0][1]);
  ok(g[1][1] === '25.0', 'and a quarter is a quarter', g[1][1]);
  ok(g[2][1] === '0.0',
     'out of breath reads 0, NOT nil -- nil means surfaced, and confusing the two ' +
     'would hide the bar at the one moment it matters most', g[2][1]);
}

console.log('\n-- the ceiling is the largest reading in the window --');
{
  // Surfacing refills breath over a second or so. Sampling the LATEST reading
  // rather than the largest would pin the ceiling to whatever the refill
  // happened to be at, and the next dive would start somewhere above 100%.
  const g = run(`
    __under = false
    __breath = 4.0;  readOxygen(1, 0)      -- caught mid-refill
    __breath = 13.0; readOxygen(1, 0)
    __breath = 20.0; readOxygen(1, 0)      -- actually full
    __breath = 19.0; readOxygen(1, 0)      -- a jittery reading afterwards
    print('a|' .. tostring(oxygenMax))
    __under, __breath = true, 10.0
    print('b|' .. __pct(readOxygen(1, 0)))
  `).map(l => l.split('|'));
  ok(g[0][1] === '20.0', 'the largest reading in the window wins, not the latest', g[0][1]);
  ok(g[1][1] === '50.0', 'so the dive is measured against the real ceiling', g[1][1]);
}

console.log('\n-- a dive taken before ever surfacing --');
{
  const g = run(`
    __under, __breath = true, 5.0          -- oxygenMax never sampled
    print('a|' .. __pct(readOxygen(1, 0)))
  `).map(l => l.split('|'));
  ok(g[0][1] === '50.0',
     'with no sample yet it falls back to the configured default rather than ' +
     'dividing by nothing', g[0][1]);
}

console.log('\n-- the ceiling going stale --');
{
  // The stat grew since the last surfacing, so the dive outlasts what was
  // learned. Clamping would peg the bar at 100% and then drop it in a step.
  const g = run(`
    __under, __breath = false, 10.0
    readOxygen(1, 0)
    __under, __breath = true, 30.0         -- more breath than the ceiling
    print('a|' .. __pct(readOxygen(1, 0)))
    print('b|' .. tostring(diveCeiling))
    __breath = 15.0
    print('c|' .. __pct(readOxygen(1, 0)))
  `).map(l => l.split('|'));
  ok(g[0][1] === '100.0', 'a dive longer than the ceiling it started with reads full', g[0][1]);
  ok(g[1][1] === '30.0', 'and raises the ceiling for this dive on the spot', g[1][1]);
  ok(g[2][1] === '50.0', 'so the rest of the dive is measured against the new one', g[2][1]);
}

console.log('\n-- dive gear, on and then off --');
{
  // THE ONE THAT BIT. um_divegear sets maximum breath to 2000s with a tank on
  // and back to 1s with it off. A ceiling that only ever grew kept the 2000
  // forever, so every later unequipped dive read as instantly empty -- a bar
  // pinned at zero that no amount of surfacing could clear.
  //
  // A 3000ms window at a 250ms tick is 12 samples, so twelve surfaced ticks is
  // exactly what it takes to forget the tank.
  const g = run(`
    __under, __breath = false, 2000.0      -- tank on
    readOxygen(1, 0)
    __under, __breath = true, 1000.0
    print('a|' .. __pct(readOxygen(1, 0)))

    -- Surface, take the tank off, and stand there.
    __under, __breath = false, 1.0
    for _ = 1, 12 do readOxygen(1, 0) end
    print('b|' .. tostring(oxygenMax))

    __under, __breath = true, 0.5
    print('c|' .. __pct(readOxygen(1, 0)))
  `).map(l => l.split('|'));
  ok(g[0][1] === '50.0', 'with a tank on, half of 2000s is half a bar', g[0][1]);
  ok(g[1][1] === '1.0',
     'the window forgets the tank once it is off, instead of holding 2000s forever',
     g[1][1]);
  ok(g[2][1] === '50.0',
     'so an unequipped dive reads honestly rather than pinned at empty', g[2][1]);
}

console.log('\n-- the ceiling does not move mid-dive --');
{
  // The ceiling is fixed at the first submerged tick. Re-sampling underwater
  // would read the DRAINING value, the window would fill with it, and the bar
  // would sit at 100% the whole way down.
  const g = run(`
    __under, __breath = false, 20.0
    readOxygen(1, 0)
    __under = true
    __breath = 20.0; print('a|' .. __pct(readOxygen(1, 0)))
    __breath = 15.0; print('b|' .. __pct(readOxygen(1, 0)))
    __breath = 10.0; print('c|' .. __pct(readOxygen(1, 0)))
    __breath =  5.0; print('d|' .. __pct(readOxygen(1, 0)))
  `).map(l => l.split('|'));
  const seq = g.map(x => x[1]).join(',');
  ok(seq === '100.0,75.0,50.0,25.0',
     'a dive draws down evenly instead of hanging at full', seq);
}

console.log('\n-- switched off, and a native that misbehaves --');
{
  const g = run(`
    Config.Oxygen.enabled = false
    __under, __breath = true, 5.0
    print('a|' .. __pct(readOxygen(1, 0)))
    Config.Oxygen = nil
    print('b|' .. __pct(readOxygen(1, 0)))
    Config.Oxygen = { enabled = true, defaultSeconds = 10.0 }
    __breath = nil
    print('c|' .. __pct(readOxygen(1, 0)))
    __breath = 'wat'
    print('d|' .. __pct(readOxygen(1, 0)))
  `).map(l => l.split('|'));
  ok(g[0][1] === 'nil', 'disabled means the row never leaves stamina mode', g[0][1]);
  ok(g[1][1] === 'nil', 'and so does no Oxygen config at all', g[1][1]);
  ok(g[2][1] === 'nil', 'a nil reading is declined rather than thrown on', g[2][1]);
  ok(g[3][1] === 'nil', 'so is a non-numeric one', g[3][1]);
}

console.log('\n-- the payload keeps a zero --');
{
  // `oxygen and math.floor(oxygen) or nil` reads like the classic broken
  // ternary. It is fine HERE only because 0 is truthy in Lua, and that is worth
  // pinning down: if it ever stopped being true the bar would vanish at exactly
  // zero breath.
  const g = run(`
    local function payload(v) return v and math.floor(v) or nil end
    print('a|' .. tostring(payload(0.4)))
    print('b|' .. tostring(payload(nil)))
  `).map(l => l.split('|'));
  ok(g[0][1] === '0', 'floor(0.4) is 0 and survives the and/or, so empty still sends 0', g[0][1]);
  ok(g[1][1] === 'nil', 'while surfaced sends no key at all', g[1][1]);
}

/* =============================================================================
 * The row
 * ========================================================================== */

console.log('\n-- the row swaps mode --');

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
const row = doc.getElementById('s-stamina');
const fillPct = () => {
  const t = row.querySelector('.sfill').style.transform;
  return Math.round(parseFloat(/scaleX\(([\d.]+)\)/.exec(t)[1]) * 100);
};
const glyph = () => row.querySelector('.sic').textContent;
const colour = () => window.getComputedStyle(row.querySelector('.sfill')).backgroundColor;

const boltGlyph = glyph();
const staminaColour = colour();

// Surfaced, and tired. The ordinary case.
msg({ action: 'status', health: 100, armor: 0, stamina: 40 });
ok(!row.classList.contains('oxygen'), 'no oxygen key means the row is the stamina row');
ok(fillPct() === 40, 'and it shows stamina', fillPct());
ok(!row.classList.contains('hidden'), 'visible because stamina is down');

// Underwater with FULL stamina: the row has to appear anyway, because a full
// breath still means a clock is running.
msg({ action: 'status', health: 100, armor: 0, stamina: 100, oxygen: 100 });
ok(row.classList.contains('oxygen'), 'an oxygen key switches the row into oxygen mode');
ok(!row.classList.contains('hidden'),
   'and shows it at FULL breath, which stamina at 100 would never do');
ok(fillPct() === 100, 'reading the breath, not the stamina', fillPct());
ok(glyph() !== boltGlyph, 'the glyph changed', JSON.stringify(glyph()));
ok(colour() !== staminaColour, 'so did the colour', colour() + ' vs ' + staminaColour);

// Mid-dive. Stamina underneath is irrelevant and must not leak through.
msg({ action: 'status', health: 100, armor: 0, stamina: 12, oxygen: 35 });
ok(fillPct() === 35, 'mid-dive it shows breath, not the stamina underneath it', fillPct());

// Empty breath is the moment the bar matters most.
msg({ action: 'status', health: 100, armor: 0, stamina: 12, oxygen: 0 });
ok(fillPct() === 0 && !row.classList.contains('hidden'),
   'out of breath the row is empty and still on screen');

// Surfacing, still winded from the swim.
msg({ action: 'status', health: 100, armor: 0, stamina: 12 });
ok(!row.classList.contains('oxygen'), 'surfacing puts the row straight back to stamina');
ok(glyph() === boltGlyph, 'with its own glyph back', JSON.stringify(glyph()));
ok(colour() === staminaColour, 'and its own colour', colour());
ok(fillPct() === 12, 'showing the stamina it had all along', fillPct());

// Surfacing with everything nominal: the row should go, but on the anti-flicker
// hold rather than instantly, same as every other bar.
msg({ action: 'status', health: 100, armor: 0, stamina: 100 });
ok(!row.classList.contains('hidden'),
   'a fully nominal surfacing does not blink the row out on the same tick');

console.log(fails ? '\n' + fails + ' check(s) failed' : '\nall checks passed');
process.exit(fails ? 1 : 0);
