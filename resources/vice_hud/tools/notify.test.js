/* Checks the notification placement tie-in, end to end.
 *
 *   npm i fengari && node tools/notify.test.js
 *
 * Two pieces of real, shipped Lua run here under fengari:
 *
 *   1. the vice_hud hook inside ox_lib's notify.lua. That file is loaded into
 *      every resource that calls lib.notify, so it is the one place that can
 *      move EVERY resource's popups -- and it is also a file an ox_lib update
 *      will happily overwrite. This test is how you find that out.
 *
 *   2. vice_hud's own server.lua, which decides who may publish a layout for
 *      the whole server and scrubs the payload before every player applies it.
 *
 * Neither is reachable from the jsdom editor test, and both are the kind of
 * code where being wrong is quiet: a bad anchor makes ox_lib drop the
 * notification with no error, and a missing ace check makes any client the
 * server's HUD designer.
 */
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const root = path.dirname(__dirname).replace(/\\/g, '/') + '/';
const OX_NOTIFY = path.resolve(root, '../../[ox]/ox_lib/resource/interface/client/notify.lua')
  .replace(/\\/g, '/');

let fails = 0;
function ok(cond, label, extra) {
  if (cond) console.log('  PASS  ' + label);
  else { console.log('  FAIL  ' + label + (extra !== undefined ? '   -> ' + extra : '')); fails++; }
}

/** Run a Lua chunk and return whatever it prints, one line per print(). */
function runLua(chunk, label) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const out = [];
  // Capture print rather than letting it reach the terminal, so the assertions
  // below read the values instead of the person running the test.
  lua.lua_pushjsfunction(L, (S) => {
    const n = lua.lua_gettop(S);
    const parts = [];
    for (let i = 1; i <= n; i++) parts.push(lua.lua_tojsstring(S, i));
    out.push(parts.join('\t'));
    return 0;
  });
  lua.lua_setglobal(L, to_luastring('print'));

  const rc = lauxlib.luaL_loadbuffer(L, to_luastring(chunk), null, to_luastring('@' + label));
  if (rc !== lua.LUA_OK) throw new Error(label + ' failed to load: ' + lua.lua_tojsstring(L, -1));
  if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    throw new Error(label + ' failed to run: ' + lua.lua_tojsstring(L, -1));
  }
  return out;
}

/* -------------------------------------------------------------------------
   1. the ox_lib hook
   ---------------------------------------------------------------------- */
console.log('\n-- the hook inside ox_lib --');

if (!fs.existsSync(OX_NOTIFY)) {
  console.log('  SKIP  ox_lib not found at ' + OX_NOTIFY);
} else {
  const notifySrc = fs.readFileSync(OX_NOTIFY, 'utf8');
  const patched = /vice_hud hook\s*--\s*BEGIN/.test(notifySrc);
  ok(patched, 'ox_lib/resource/interface/client/notify.lua still carries the vice_hud hook',
     patched ? '' : 'an ox_lib update has overwritten it - re-apply the hook, or notifications ' +
                    'go back to the top-right corner for everyone');

  if (patched) {
    // Stub just enough of the CFX client API for notify.lua to load. Nothing
    // here is a stand-in for the hook itself -- that runs verbatim.
    const stubs = `
      lib = {}
      local nuiSent = nil
      function SendNUIMessage(m) nuiSent = m end
      function RegisterNetEvent() end
      function GetSoundId() return 0 end
      function PlaySoundFrontend() end
      function ReleaseSoundId() end
      local realRequire = require
      require = function(name)
        if name == 'resource.settings' then
          return { notification_audio = false, notification_position = 'top-right' }
        end
        return realRequire(name)
      end
      LocalPlayer = { state = {} }
      GlobalState = {}
      function __lastNui() return nuiSent end
    `;

    const drive = `
      local function place(anchor, x, y)
        LocalPlayer.state['vice_hud:notify'] = { anchor = anchor, x = x, y = y }
      end
      local function fire()
        lib.notify({ title = 't', description = 'd' })
        local m = __lastNui()
        local s = m.data.style or {}
        local bits = { 'pos=' .. tostring(m.data.position) }
        for _, k in ipairs({ 'marginLeft', 'marginRight', 'marginTop', 'marginBottom' }) do
          if s[k] then bits[#bits+1] = k .. '=' .. tostring(s[k]) end
        end
        return table.concat(bits, ' ')
      end

      -- No placement at all: ox_lib must behave exactly as it did before.
      LocalPlayer.state['vice_hud:notify'] = nil
      print('none|' .. fire())

      place('top-right', 2, 3);    print('tr|' .. fire())
      place('top-left', 2, 3);     print('tl|' .. fire())
      place('bottom-right', 2, 3); print('br|' .. fire())
      place('bottom-left', -2, -3);print('bl|' .. fire())
      place('top', 2, 3);          print('top|' .. fire())
      place('center-right', 2, 3); print('cr|' .. fire())

      -- Zero nudge means "just the corner": no margins at all, so a plain
      -- corner move cannot disturb ox_lib's own spacing.
      place('bottom', 0, 0);       print('zero|' .. fire())

      -- The server-wide bag is the fallback when there is no personal one.
      LocalPlayer.state['vice_hud:notify'] = nil
      GlobalState['vice_hud:notify'] = { anchor = 'bottom-left', x = 1, y = 0 }
      print('global|' .. fire())

      -- ...and the personal one wins over it.
      LocalPlayer.state['vice_hud:notify'] = { anchor = 'top', x = 0, y = 0 }
      print('both|' .. fire())
    `;

    const lines = runLua(stubs + notifySrc + drive, 'notify.lua');
    const got = {};
    lines.forEach((l) => { const i = l.indexOf('|'); got[l.slice(0, i)] = l.slice(i + 1); });

    ok(got.none === 'pos=top-right', 'with no placement set, nothing is touched', got.none);

    // +x is right and +y is down on EVERY anchor. That is the whole contract:
    // the sign of a nudge must not depend on which corner you picked.
    ok(got.tr === 'pos=top-right marginRight=-2vw marginTop=3vh',
       'top-right: +x pulls off the right edge, +y pushes down', got.tr);
    ok(got.tl === 'pos=top-left marginLeft=2vw marginTop=3vh',
       'top-left: +x pushes off the left edge', got.tl);
    ok(got.br === 'pos=bottom-right marginRight=-2vw marginBottom=-3vh',
       'bottom-right: +y still means DOWN, i.e. closer to the edge', got.br);
    ok(got.bl === 'pos=bottom-left marginLeft=-2vw marginBottom=3vh',
       'bottom-left: negatives mirror cleanly', got.bl);
    ok(got.top === 'pos=top marginLeft=4vw marginTop=3vh',
       'a centred axis doubles the margin, because flex splits it in half', got.top);
    ok(got.cr === 'pos=center-right marginRight=-2vw marginTop=6vh',
       'center-right doubles the vertical one for the same reason', got.cr);
    ok(got.zero === 'pos=bottom', 'a zero nudge adds no margins at all', got.zero);
    ok(got.global === 'pos=bottom-left marginLeft=1vw',
       'the server-wide placement applies on its own', got.global);
    ok(got.both === 'pos=top', 'a personal placement wins over the server one', got.both);

    // Every value is a viewport percentage. A pixel anywhere in here would mean
    // the layout drifts between a 1080p and a 1440p player.
    const anyPx = Object.values(got).some((v) => /\dpx/.test(v));
    ok(!anyPx, 'nothing is measured in pixels, so one placement fits every resolution');
  }
}

/* -------------------------------------------------------------------------
   2. server.lua: who may publish, and what survives the trip
   ---------------------------------------------------------------------- */
console.log('\n-- publishing a layout for the whole server --');
{
  const serverSrc = fs.readFileSync(root + 'server.lua', 'utf8');

  // The REAL config.lua, not a hand-written stub. server.lua reaches into
  // Config for the aspect-bucket helpers when it files a published map, and a
  // stub that only carried PublishAce meant this test failed the moment it did.
  // config.lua is a shared_script, so loading it first is also what actually
  // happens in game.
  const stubs = fs.readFileSync(root + 'config.lua', 'utf8') + `
    Config.PublishAce = 'vice_hud.publish'
    local handlers, globals, saved = {}, {}, {}
    local acl = { [1] = { ['vice_hud.publish'] = true } }   -- player 1 is an admin

    function RegisterNetEvent(name, fn) handlers[name] = fn end
    function AddEventHandler(name, fn) handlers[name] = fn end
    function RegisterCommand(name, fn) handlers['cmd:' .. name] = fn end
    function GetCurrentResourceName() return 'vice_hud' end
    function GetPlayerName(id) return 'player' .. tostring(id) end
    function IsPlayerAceAllowed(src, ace) return (acl[src] or {})[ace] == true end
    function LoadResourceFile() return nil end
    function SaveResourceFile(_, name, data) saved[name] = data return true end
    function TriggerClientEvent(evt, src, okFlag, why)
      __reply = { evt = evt, src = src, ok = okFlag, why = why }
    end
    GlobalState = setmetatable({}, {
      __index = function(_, k) return globals[k] end,
      __newindex = function(_, k, v) globals[k] = v end,
    })
    GlobalState.set = function(_, k, v) globals[k] = v end
    json = {
      encode = function(t)
        -- Only needs to prove the payload is serialisable and round-trippable.
        local function enc(v)
          if type(v) == 'table' then
            local parts = {}
            local keys = {}
            for k in pairs(v) do keys[#keys+1] = tostring(k) end
            table.sort(keys)
            for _, k in ipairs(keys) do
              local val = v[k] ~= nil and v[k] or v[tonumber(k)]
              parts[#parts+1] = k .. ':' .. enc(val)
            end
            return '{' .. table.concat(parts, ',') .. '}'
          end
          return tostring(v)
        end
        return enc(t)
      end,
      decode = function(s) error('not used') end,
    }
    function __publish(src, payload) handlers['vice_hud:publish'](payload, src) end
    function __globals() return globals end
    function __saved() return saved end
  `;

  // server.lua reads `source`, which fengari has no notion of. Bind it from the
  // second argument the harness passes in, so the real handler body is unchanged.
  // Newline-agnostic on purpose: this tree is CRLF, and an anchor written with
  // a bare \n would fail on a server.lua nobody had touched.
  const shimmed = serverSrc.replace(
    /RegisterNetEvent\('vice_hud:publish', function\(payload\)(\s*)local src = source/,
    "RegisterNetEvent('vice_hud:publish', function(payload, __src)$1local src = __src"
  );
  if (shimmed === serverSrc) throw new Error('could not bind `source` in server.lua');

  const drive = `
    local good = {
      offsets = {
        status = { x = 1.5, y = -2.0, sx = 1.25, al = 'center' },
        notify = { x = 3.0, y = 4.0, anchor = 'bottom-left' },
      },
      map = { v = 3, sw = 0.9 },
      notify = { anchor = 'bottom-left', x = 3.0, y = 4.0 },
    }

    -- A player with no ace must not be able to restyle everyone's HUD.
    __publish(2, good)
    print('denied|' .. tostring(__reply.ok) .. '|' .. tostring(__globals()['vice_hud:layout']))

    __publish(1, good)
    local g = __globals()
    print('allowed|' .. tostring(__reply.ok))
    print('notifybag|' .. g['vice_hud:notify'].anchor .. '|' .. g['vice_hud:notify'].x)
    print('status|' .. tostring(g['vice_hud:layout'].offsets.status.x)
          .. '|' .. tostring(g['vice_hud:layout'].offsets.status.al))
    print('written|' .. tostring(__saved()['layout.json'] ~= nil))

    -- Hostile payload from an admin's own client: junk keys, an anchor ox_lib
    -- would silently drop, and a nudge that would park the HUD off the planet.
    __publish(1, {
      offsets = {
        status = { x = 1e9, y = -1e9, evil = 'rm -rf', ff = 'Arial' },
        ['../../etc'] = { x = 1 },
        notify = { anchor = 'somewhere-else' },
      },
      notify = { anchor = 'somewhere-else', x = 'nonsense', y = 2 },
    })
    local g2 = __globals()['vice_hud:layout']
    print('clamped|' .. tostring(g2.offsets.status.x) .. '|' .. tostring(g2.offsets.status.y))
    print('stripped|' .. tostring(g2.offsets.status.evil) .. '|' .. tostring(g2.offsets.status.ff))
    print('badkey|' .. tostring(g2.offsets['../../etc']))
    print('anchor|' .. __globals()['vice_hud:notify'].anchor
          .. '|' .. tostring(__globals()['vice_hud:notify'].x))
  `;

  const lines = runLua(stubs + shimmed + drive, 'server.lua');
  const got = {};
  lines.forEach((l) => { const i = l.indexOf('|'); got[l.slice(0, i)] = l.slice(i + 1); });

  ok(got.denied === 'false|nil', 'a player without the ace is refused and changes nothing', got.denied);
  ok(got.allowed === 'true', 'a player with the ace publishes');
  ok(got.notifybag === 'bottom-left|3.0', 'the notification placement lands in its own global bag', got.notifybag);
  ok(got.status === '1.5|center', 'offsets and text alignment survive the trip', got.status);
  ok(got.written === 'true', 'and the layout is written to layout.json, so it outlives a restart');

  // ±500 matches POS_PROPS in html/app.js on purpose. If the server narrowed
  // that further, publishing would move an element the tuner had just placed.
  ok(got.clamped === '500.0|-500.0',
     'an absurd nudge is clamped, at the same limit the editor enforces', got.clamped);
  ok(got.stripped === 'nil|Arial', 'unknown keys are dropped, known ones kept', got.stripped);
  ok(got.badkey === 'nil', 'an element name that is not an identifier is dropped', got.badkey);
  ok(got.anchor === 'top-right|0.0',
     'an anchor ox_lib does not know falls back rather than silently killing every notification', got.anchor);
}

console.log('\n' + (fails ? fails + ' FAILING' : 'all checks passed'));
process.exit(fails ? 1 : 0);
