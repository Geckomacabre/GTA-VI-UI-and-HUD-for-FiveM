/* Per-aspect published map profiles.
 *
 *   npm i fengari && node tools/aspect.test.js
 *
 * The layout offsets are percentages and mean the same thing on every monitor.
 * The NATIVE MINIMAP does not: its values live in GTA's safe-zone-relative
 * component space, and the blip-centring offset in particular is, per
 * INTERNALS.md, "not derivable from outside the game" -- two attempts to model
 * it were wrong in opposite directions.
 *
 * So /hudpublish files the map under the aspect BUCKET it was tuned on, and a
 * player gets the profile for their own bucket, or the nearest published one.
 * Nothing is ever rescaled. This test covers the three pieces that have to
 * agree for that to work:
 *
 *   1. Config.AspectBucket   -- shared, so client and server name buckets alike
 *   2. server.lua sanitise   -- files the map, merges with what is there, and
 *                               does not trust a client-supplied bucket name
 *   3. pickMapForThisDisplay -- exact bucket, then nearest, then the flat field
 */
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib } = require('fengari');

const root = path.dirname(__dirname).replace(/\\/g, '/') + '/';

let fails = 0;
function ok(cond, label, extra) {
  if (cond) console.log('  PASS  ' + label);
  else { console.log('  FAIL  ' + label + (extra !== undefined ? '   -> ' + extra : '')); fails++; }
}

function runLua(chunk, label) {
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
  lua.lua_setglobal(L, 'print');
  if (lauxlib.luaL_dostring(L, Buffer.from(chunk, 'utf8')) !== lua.LUA_OK) {
    throw new Error(label + ': ' + lua.lua_tojsstring(L, -1));
  }
  return out;
}

const configSrc = fs.readFileSync(root + 'config.lua', 'utf8');

/* ---------------------------------------------------------------------------
   1. the shared bucket function
   ------------------------------------------------------------------------ */
console.log('\n-- aspect buckets --');
{
  const drive = `
    local function b(a) print(a .. '|' .. Config.AspectBucket(a)) end
    b(1.3333) b(1.6) b(1.7778) b(1.7777779) b(2.0) b(2.3889) b(2.3703) b(3.5556)
    print('nominal169|' .. tostring(Config.AspectNominal('16:9')))
    print('nominalJunk|' .. tostring(Config.AspectNominal('nope')))
    print('nilAspect|' .. Config.AspectBucket(nil))
  `;
  const got = {};
  runLua(configSrc + drive, 'config.lua').forEach((l) => {
    const i = l.indexOf('|'); got[l.slice(0, i)] = l.slice(i + 1);
  });

  ok(got['1.3333'] === '4:3', 'classic 4:3', got['1.3333']);
  ok(got['1.6'] === '16:10', '16:10', got['1.6']);
  ok(got['1.7778'] === '16:9', '16:9', got['1.7778']);
  // Boundaries sit in the GAPS between real aspects, so a panel reporting a
  // slightly different float cannot land in a neighbouring bucket.
  ok(got['1.7777779'] === '16:9', 'and 16:9 reported to seven decimal places', got['1.7777779']);
  ok(got['2.0'] === '2:1', '2:1', got['2.0']);
  ok(got['2.3889'] === '21:9', '21:9 (3440x1440)', got['2.3889']);
  ok(got['2.3703'] === '21:9', 'and 21:9 (2560x1080), which is a different ratio', got['2.3703']);
  ok(got['3.5556'] === '32:9', '32:9 (5120x1440)', got['3.5556']);

  ok(got.nominal169 === '1.7777777777778', 'a bucket knows its nominal aspect', got.nominal169);
  ok(got.nominalJunk === 'nil', 'and an unknown name has none, so it can be rejected', got.nominalJunk);
  ok(got.nilAspect === '16:9', 'a missing aspect falls back to 16:9 rather than erroring', got.nilAspect);
}

/* ---------------------------------------------------------------------------
   2. server.lua files the profile, and does not trust the client's name
   ------------------------------------------------------------------------ */
console.log('\n-- publishing files the map under its own bucket --');
{
  const serverSrc = fs.readFileSync(root + 'server.lua', 'utf8');
  const shimmed = serverSrc.replace(
    /RegisterNetEvent\('vice_hud:publish', function\(payload\)(\s*)local src = source/,
    "RegisterNetEvent('vice_hud:publish', function(payload, __src)$1local src = __src"
  );
  if (shimmed === serverSrc) throw new Error('could not bind `source` in server.lua');

  const stubs = `
    local handlers = {}
    function RegisterNetEvent(n, fn) handlers[n] = fn end
    function AddEventHandler() end
    function TriggerClientEvent() end
    function RegisterCommand() end
    function GetCurrentResourceName() return 'vice_hud' end
    function LoadResourceFile() return nil end
    function SaveResourceFile() return true end
    function IsPlayerAceAllowed() return true end
    function GetPlayerName() return 'tester' end
    -- Same shape as notify.test.js's: __newindex has to STORE, because
    -- GlobalState.set is assigned through it and then read back through
    -- __index. A __newindex that discards silently loses the method and
    -- server.lua's GlobalState:set() call dies on a nil.
    local globals = {}
    GlobalState = setmetatable({}, {
      __index = function(_, k) return globals[k] end,
      __newindex = function(_, k, v) globals[k] = v end,
    })
    GlobalState.set = function(_, k, v) globals[k] = v end
    json = { encode = function() return '{}' end, decode = function() return nil end }
  `;

  const drive = `
    -- Tune on 16:9 and publish.
    handlers['vice_hud:publish']({
      offsets = {}, map = { tag = 'wide', scaleW = 0.663 }, aspect = 1920/1080,
      bucket = 'LIES',   -- a client claiming to be something it is not
    }, 1)
    print('after169|' .. tostring(PUB().maps['16:9'] and PUB().maps['16:9'].tag))
    print('lieIgnored|' .. tostring(PUB().maps['LIES']))

    -- Now publish from an ultrawide. The 16:9 profile must survive.
    handlers['vice_hud:publish']({
      offsets = {}, map = { tag = 'uw', scaleW = 0.9 }, aspect = 3440/1440,
    }, 1)
    print('after219|' .. tostring(PUB().maps['21:9'] and PUB().maps['21:9'].tag))
    print('kept169|' .. tostring(PUB().maps['16:9'] and PUB().maps['16:9'].tag))
    print('flat|' .. tostring(PUB().map.tag))
  `;

  // server.lua keeps `published` as a local upvalue; expose a reader for it.
  const withPeek = shimmed + '\nfunction PUB() return published end\n';
  const got = {};
  // config.lua ahead of server.lua, exactly as fxmanifest orders them:
  // shared_scripts load before server_scripts, which is what puts Config in
  // scope for the bucket call in sanitise().
  runLua(configSrc + stubs + withPeek + drive, 'server.lua').forEach((l) => {
    const i = l.indexOf('|'); got[l.slice(0, i)] = l.slice(i + 1);
  });

  ok(got.after169 === 'wide', 'a 16:9 publish is filed under 16:9', got.after169);
  ok(got.lieIgnored === 'nil',
     'and the bucket name is recomputed from the aspect, not taken from the client',
     got.lieIgnored);
  ok(got.after219 === 'uw', 'a later ultrawide publish is filed under 21:9', got.after219);
  ok(got.kept169 === 'wide',
     'and does NOT wipe the 16:9 profile -- publishing merges, so an admin can '
     + 'tune each display once', got.kept169);
  ok(got.flat === 'uw', 'the flat map field is the most recent, for old clients', got.flat);
}

/* ---------------------------------------------------------------------------
   3. the client picks the right one
   ------------------------------------------------------------------------ */
console.log('\n-- and the client picks the profile for its own display --');
{
  // pickMapForThisDisplay is a global in client.lua. Lifting just that function
  // out keeps this test off the other 4000 lines and their natives.
  const clientSrc = fs.readFileSync(root + 'client.lua', 'utf8');
  // \r? throughout: this repo is checked out with CRLF endings on Windows, and
  // a bare \n never matches \r\n -- the function is found on Linux/macOS and
  // "not found in client.lua" on Windows, which looks like the function was
  // deleted rather than like a line-ending mismatch.
  const m = clientSrc.match(/function pickMapForThisDisplay\(sv\)[\s\S]*?\r?\nend\r?\n/);
  if (!m) throw new Error('pickMapForThisDisplay not found in client.lua');

  const drive = `
    local RES = { 1920, 1080 }
    function GetActiveScreenResolution() return RES[1], RES[2] end
    ${m[0]}

    local maps = { ['16:9'] = { tag = 'wide' }, ['32:9'] = { tag = 'ultra' } }

    RES = { 1920, 1080 }
    print('exact|' .. tostring(pickMapForThisDisplay({ maps = maps }).tag))

    -- 21:9 was never published. 3440x1440 is 2.389, which is 0.61 from 16:9
    -- (1.778) and 1.17 from 32:9 (3.556) -- so an ultrawide player lands on the
    -- 16:9 profile, not the 32:9 one. Worth spelling out because the intuition
    -- runs the other way: "ultrawide, so take the widest profile" is wrong, and
    -- taking the NEAREST measured value is the whole point.
    RES = { 3440, 1440 }
    print('nearest|' .. tostring(pickMapForThisDisplay({ maps = maps }).tag))

    -- 16:10 (1.6) is nearer 16:9 than 32:9.
    RES = { 1920, 1200 }
    print('nearest2|' .. tostring(pickMapForThisDisplay({ maps = maps }).tag))

    -- No per-aspect profiles at all: a layout.json published before any of this
    -- existed must keep working.
    RES = { 1920, 1080 }
    print('legacy|' .. tostring(pickMapForThisDisplay({ map = { tag = 'old' } }).tag))

    -- Nothing published at all.
    print('none|' .. tostring(pickMapForThisDisplay({})))
    print('junk|' .. tostring(pickMapForThisDisplay(nil)))
  `;

  const got = {};
  runLua(configSrc + drive, 'pickMapForThisDisplay').forEach((l) => {
    const i = l.indexOf('|'); got[l.slice(0, i)] = l.slice(i + 1);
  });

  ok(got.exact === 'wide', 'an exact bucket match wins', got.exact);
  ok(got.nearest === 'wide',
     'an unpublished aspect falls back to the NEAREST published bucket -- for '
     + '21:9 that is 16:9 (0.61 away), not 32:9 (1.17 away)', got.nearest);
  ok(got.nearest2 === 'wide', 'and 16:10 lands on 16:9 too', got.nearest2);
  ok(got.legacy === 'old', 'a layout with only the flat map field still applies', got.legacy);
  ok(got.none === 'nil', 'nothing published means nothing applied', got.none);
  ok(got.junk === 'nil', 'and a junk payload does not throw', got.junk);
}

console.log(fails ? '\n' + fails + ' FAILING' : '\nall checks passed');
process.exit(fails ? 1 : 0);
