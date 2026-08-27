/* Checks the stamina reader against a native that lies.
 *
 *   npm i fengari && node tools/stamina.test.js
 *
 * GetPlayerSprintStaminaRemaining is documented three different ways --
 * remaining vs depletion, 0..1 vs 0..100 -- and can be pinned outright by any
 * script calling ResetPlayerStamina. readStamina guesses the convention by
 * watching the value move. This exercises that guess against builds that
 * behave, builds that don't, and the one that actually bit:
 *
 *   a reading of -15% that never changes.
 *
 * That one is not cosmetic. exhaustionFrom(-15) clamps to FULL exhaustion, full
 * exhaustion disables the sprint control, and a player who cannot sprint can
 * never move the native -- so the wrong reading holds itself in place and looks
 * exactly like "stamina does not drain".
 *
 * Runs the REAL readStamina lifted out of client.lua, with the natives stubbed.
 */
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const root = path.dirname(__dirname).replace(/\\/g, '/') + '/';
const src = fs.readFileSync(root + 'client.lua', 'utf8');

let fails = 0;
function ok(cond, label, extra) {
  if (cond) console.log('  PASS  ' + label);
  else { console.log('  FAIL  ' + label + (extra !== undefined ? '   -> ' + extra : '')); fails++; }
}

// Lift the reader and the state it closes over, verbatim, so this tests the
// shipped code rather than a paraphrase of it.
const a = src.indexOf('local staminaMode   = nil');
const b = src.indexOf('-- =============================================================================', src.indexOf('local function readStamina'));
if (a < 0 || b < 0) throw new Error('could not locate readStamina in client.lua');
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

  // source = 'native' throughout: the shipped DEFAULT is the self-managed bar,
  // which resolves before the native is read at all. These cases are about the
  // opt-in interpretation path, so they have to ask for it.
  const stubs = `
    Config = {
      StaminaIsDepletion = true,
      Stamina = { source = 'native', sprintSeconds = 12.0, refillSeconds = 9.0,
                  regenDelayMs = 900, skillBonus = 0.0 },
    }
    __native, __sprinting = 100.0, false
    function GetPlayerSprintStaminaRemaining() return __native end
    function IsPedSprinting() return __sprinting end
  `;
  const full = stubs + chunk + drive;
  if (lauxlib.luaL_loadbuffer(L, to_luastring(full), null, to_luastring('@stamina')) !== lua.LUA_OK) {
    throw new Error('load failed: ' + lua.lua_tojsstring(L, -1));
  }
  if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    throw new Error('run failed: ' + lua.lua_tojsstring(L, -1));
  }
  return out;
}

/* THE DEFAULT. The self-managed bar, which is what ships and what almost
 * everyone will actually run. It has to be boring and exactly right: drains
 * while sprinting, pauses, refills, and never touches the native at all. */
console.log('\n-- the self-managed bar (the shipped default) --');
{
  const lines = run(`
    -- No source given at all: the default has to be manual without being asked.
    Config.Stamina = { sprintSeconds = 12.0, refillSeconds = 9.0,
                       regenDelayMs = 900, skillBonus = 0.0 }
    staminaMode = nil

    -- The native is deliberately hostile. Nothing below may depend on it.
    __native = -999.0

    local v = readStamina(0, 0, 200)
    print('default|' .. tostring(staminaMode) .. '|' .. string.format('%.1f', v))

    -- Six seconds of sprinting: half of a twelve-second bar.
    __sprinting = true
    for _ = 1, 30 do v = readStamina(0, 0, 200) end
    print('half|' .. string.format('%.1f', v))

    -- Six more empties it, and it must not go below zero.
    for _ = 1, 40 do v = readStamina(0, 0, 200) end
    print('empty|' .. string.format('%.1f', v))

    -- Stop. The hold means nothing comes back for the first 900ms.
    __sprinting = false
    for _ = 1, 4 do v = readStamina(0, 0, 200) end
    print('held|' .. string.format('%.1f', v))

    -- Then it refills, and stops at full.
    for _ = 1, 60 do v = readStamina(0, 0, 200) end
    print('refilled|' .. string.format('%.1f', v))
  `);
  const g = {}; lines.forEach(l => { const p = l.split('|'); g[p[0]] = p.slice(1); });

  ok(g.default[0] === 'manual', 'with no source configured it settles on manual', g.default[0]);
  ok(g.default[1] === '100.0', 'and starts full', g.default[1]);
  ok(g.half[0] === '50.0', 'six seconds of a twelve-second sprint is exactly half', g.half[0]);
  ok(g.empty[0] === '0.0', 'it empties and floors at zero', g.empty[0]);
  ok(g.held[0] === '0.0',
     'stopping does NOT refill immediately — the pause is what stops the bar ' +
     'snapping back and reading as decoration', g.held[0]);
  ok(g.refilled[0] === '100.0', 'then it refills to full and stops there', g.refilled[0]);
}

/* The stamina SKILL has to lengthen the sprint, or a maxed skill would move the
 * GTA stat while this bar emptied at exactly its day-one rate. */
console.log('\n-- the stamina skill lengthens the bar --');
{
  const lines = run(`
    Config.Stamina = { sprintSeconds = 12.0, refillSeconds = 9.0,
                       regenDelayMs = 0, skillBonus = 1.0 }
    staminaMode = nil
    function SkillFitness() return 1.0 end       -- a maxed stamina skill

    __sprinting = true
    local v
    for _ = 1, 30 do v = readStamina(0, 0, 200) end   -- six seconds
    print('r|' .. string.format('%.1f', v))
  `);
  const g = lines[lines.length - 1].split('|');
  ok(g[1] === '75.0',
     'at skillBonus 1.0 a maxed skill doubles the sprint, so six seconds costs a quarter',
     g[1]);
}

/* A build that reports REMAINING on 0..100 and behaves. */
console.log('\n-- a native that behaves (remaining, 0..100) --');
{
  const lines = run(`
    local v, trusted
    -- Not sprinting yet: nothing is latched, so nothing is trusted.
    v, trusted = readStamina(0, 0, 200)
    print('idle|' .. v .. '|' .. tostring(trusted) .. '|' .. tostring(staminaMode))
    __sprinting = true
    for i = 1, 6 do
      __native = 100.0 - (i * 10)
      v, trusted = readStamina(0, 0, 200)
    end
    print('sprint|' .. string.format('%.1f', v) .. '|' .. tostring(trusted)
          .. '|' .. tostring(staminaMode) .. '|' .. tostring(staminaScale))
  `);
  const g = {}; lines.forEach(l => { const p = l.split('|'); g[p[0]] = p.slice(1); });
  ok(g.idle[1] === 'false' && g.idle[0] === '100.0',
     'before anything is latched it reports full and says so is NOT trustworthy', g.idle.join(','));
  ok(g.sprint[2] === 'remaining', 'a falling value while sprinting latches REMAINING', g.sprint[2]);
  ok(g.sprint[0] === '40.0', 'and 40 of a learned range of 100 reads as 40%', g.sprint[0]);
}

/* A build that reports DEPLETION on 0..1. */
console.log('\n-- a native that behaves (depletion, 0..1) --');
{
  const lines = run(`
    __sprinting = true
    local v
    for i = 0, 5 do
      __native = i * 0.15
      v = readStamina(0, 0, 200)
    end
    print('r|' .. string.format('%.1f', v) .. '|' .. tostring(staminaMode) .. '|' .. tostring(staminaScale))
  `);
  // The LAST line: readStamina prints its own detection message when it
  // latches, which lands ahead of anything the drive code prints.
  const g = lines[lines.length - 1].split('|');
  ok(g[2] === 'depletion', 'a rising value while sprinting latches DEPLETION', g[2]);
  ok(g[1] === '0.0', '0.75 of a learned range of 0.75 reads as empty', g[1]);
}

/* The native is pinned by something calling ResetPlayerStamina. */
console.log('\n-- a native something else is holding --');
{
  const lines = run(`
    __sprinting = true
    __native = 100.0
    local v
    for _ = 1, 20 do v = readStamina(0, 0, 200) end
    print('r|' .. tostring(staminaMode) .. '|' .. string.format('%.1f', v))
  `);
  const g = lines[lines.length - 1].split('|');
  ok(g[1] === 'manual', 'a frozen native falls back to the self-managed bar', g[1]);
  ok(+g[2] < 100, 'which then actually drains while sprinting', g[2]);
}

/* THE BUILD THIS WAS ACTUALLY REPORTED ON.
 * From /hudstamina in the wild: depletion, raw 0 .. 9.1 over a full sprint.
 * Not 0..1, not 0..100. Under the old fixed-scale maths a full sprint moved the
 * bar from 100% to 91%, which is exactly "stamina doesn't drain". */
console.log('\n-- a 0..9.1 depletion native (the reported build) --');
{
  const lines = run(`
    __sprinting = true
    local seen = {}
    -- One full sprint: the counter climbs 0 -> 9.1 and the ped gives up.
    for i = 0, 91 do
      __native = i * 0.1
      local v = readStamina(0, 0, 100)
      if i == 0 or i == 45 or i == 91 then seen[#seen+1] = string.format('%.1f', v) end
    end
    print('first|' .. table.concat(seen, ','))
    print('range|' .. string.format('%.2f', staminaRange) .. '|' .. tostring(staminaMode))

    -- A SECOND sprint, now that the range is known, must track properly.
    __native = 0.0;  local a = readStamina(0, 0, 100)
    __native = 4.55; local b = readStamina(0, 0, 100)
    __native = 9.1;  local c = readStamina(0, 0, 100)
    print('second|' .. string.format('%.0f,%.0f,%.0f', a, b, c))
  `);
  const g = {}; lines.forEach(l => { const p = l.split('|'); g[p[0]] = p.slice(1); });

  ok(g.range[0] === '9.10', 'the range is learned from what the native actually did', g.range[0]);
  ok(g.range[1] === 'depletion', 'and the mode is still read correctly', g.range[1]);
  ok(g.second[0] === '100,50,0',
     'a later sprint reads full -> half -> empty, instead of 100 -> 99 -> 91',
     g.second[0]);
  // The old maths on this build: 100 - 9.1 = 90.9. That is the bug, stated as
  // a number so nobody reintroduces the assumption.
  ok(g.second[0].split(',')[2] === '0',
     'a fully depleted native reads as EMPTY, not as 91%', g.second[0]);
}

/* The -15% that started all this.
 *
 * It can no longer HAPPEN, which is a better outcome than detecting it. The old
 * maths subtracted the native from a fixed 100, so a native reading 115 gave
 * -15%. Normalising against the observed range gives "115 out of a range of
 * 115" = fully depleted = 0%. The pathological value is not caught and
 * recovered from; it is simply not producible. */
console.log('\n-- a native that runs past the assumed scale --');
{
  const lines = run(`
    __sprinting = true
    __native = 10.0; readStamina(0, 0, 200)
    __native = 40.0; readStamina(0, 0, 200)      -- rising => depletion
    print('latched|' .. tostring(staminaMode))

    __native = 115.0
    local v, sawNegative = nil, false
    for _ = 1, 25 do
      v = readStamina(0, 0, 200)
      if v < 0 then sawNegative = true end
    end
    print('r|' .. string.format('%.1f', v) .. '|' .. tostring(sawNegative)
          .. '|' .. tostring(staminaMode) .. '|' .. string.format('%.1f', staminaRange))
  `);
  const g = {}; lines.forEach(l => { const p = l.split('|'); g[p[0]] = p.slice(1); });

  ok(g.latched[0] === 'depletion', 'the mode latches as it did in the wild', g.latched[0]);
  ok(g.r[1] === 'false',
     'a native past the assumed scale never produces a negative reading — the old ' +
     '100-minus-native maths is what turned 115 into -15%', g.r[1]);
  ok(g.r[0] === '0.0', 'it reads as fully depleted, which is what it means', g.r[0]);
  ok(g.r[2] === 'depletion',
     'and there is nothing to fall back FROM, because nothing went wrong', g.r[2]);
  ok(g.r[3] === '115.0', 'the range simply widened to fit it', g.r[3]);
}

/* A genuinely impossible reading still has to be caught. Normalisation cannot
 * save a NEGATIVE native: that is neither a remaining value nor a depletion
 * one, and no range makes it mean anything. */
console.log('\n-- a native that goes negative --');
{
  const lines = run(`
    __sprinting = true
    __native = 10.0; readStamina(0, 0, 200)
    __native = 40.0; readStamina(0, 0, 200)
    __native = -60.0
    local v
    for _ = 1, 25 do v = readStamina(0, 0, 200) end
    print('r|' .. tostring(staminaMode) .. '|' .. string.format('%.1f', v))
  `);
  const g = lines[lines.length - 1].split('|');
  ok(g[1] === 'manual',
     'held long enough, an impossible reading falls back to the self-managed bar', g[1]);
  ok(+g[2] >= 0 && +g[2] <= 100, 'and the player is left with a usable number', g[2]);
}

/* A depletion native that overshoots slightly at the bottom of a sprint is
 * legitimate and must NOT trigger the fallback. */
console.log('\n-- a small, honest overshoot --');
{
  const lines = run(`
    __sprinting = true
    __native = 10.0; readStamina(0, 0, 200)
    __native = 40.0; readStamina(0, 0, 200)
    __native = 101.0
    local v
    for _ = 1, 30 do v = readStamina(0, 0, 200) end
    print('r|' .. string.format('%.1f', v) .. '|' .. tostring(staminaMode))
  `);
  const g = lines[lines.length - 1].split('|');
  ok(g[2] === 'depletion', 'one point past the end does not throw away a working native', g[2]);
  ok(g[1] === '0.0', 'it just reads as empty', g[1]);
}

console.log('\n' + (fails ? fails + ' FAILING' : 'all checks passed'));
process.exit(fails ? 1 : 0);
