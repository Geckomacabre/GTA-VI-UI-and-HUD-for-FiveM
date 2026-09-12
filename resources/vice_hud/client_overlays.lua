--[[
    vice_hud — overlays:  aim crosshair, kill mark, race lap timer, world-action
    prompt, the lockpick check, and the interact menu with its pad input.

    Split out of client.lua on 2026-08-28 for the reason described at the top of
    client_vitals.lua (Lua's 200-top-level-locals-per-chunk limit). Every line
    below is moved, not rewritten.

    This group is the cleanest seam in the whole file: it declares ONE top-level
    local, it needs exactly one name from client.lua (`ui`, duplicated below),
    and NOTHING in the rest of the resource reaches into it. Everything here is
    driven from outside through exports and commands, which is why it can sit in
    its own chunk with no shared state at all.

    Note the native-HUD suppressor that used to sit just above the crosshair
    stayed behind in client.lua: it owns the minimap scaleform, which belongs
    with the map code, not here.
]]

-- Its own copy of the NUI sender, exactly as client_skills.lua carries one:
-- every file here is a separate Lua chunk, so client.lua's `ui` is not in
-- scope, and four lines duplicated beats a global for something this small.
local function ui(action, data)
    data = data or {}
    data.action = action
    SendNUIMessage(data)
end

-- =============================================================================
-- Aim crosshair
-- =============================================================================
-- Two variants: a plain ring+dot while driving (drive-by shooting), a
-- three-tick reticle on foot that widens on each shot. See Config.Crosshair
-- for the reticleComponent caveat.
--
-- ui() is only called on an actual STATE CHANGE (active flips, or the mode
-- flips between foot/vehicle) even though this runs on Wait(0) -- streaming a
-- value every frame would spam SendNUIMessage for no reason, since the
-- widen/settle motion itself lives entirely in CSS (see style.css's
-- --spread). Only the two native calls that must run every frame regardless
-- (HideHudComponentThisFrame, and reading whether a shot fired this frame)
-- are actually in the tight loop.
if Config.Crosshair.enable then
    local crossActive, crossMode = false, 'foot'
    local crossWasShooting = false

    CreateThread(function()
        while true do
            Wait(0)
            local ped = cache.ped or PlayerPedId()
            local playerId = PlayerId()
            local armedGun = IsPedArmed(ped, 2)
            local aiming = armedGun and (IsPlayerFreeAiming(playerId) or IsPedShooting(ped))
            local mode = IsPedInAnyVehicle(ped, false) and 'vehicle' or 'foot'

            if aiming then
                HideHudComponentThisFrame(Config.Crosshair.reticleComponent)
                if not crossActive or mode ~= crossMode then
                    crossActive, crossMode = true, mode
                    ui('crosshair', { active = true, mode = mode })
                end
            elseif crossActive then
                crossActive = false
                ui('crosshair', { active = false })
            end

            -- Foot reticle only — the vehicle ring doesn't spread in the
            -- reference, so there's nothing to fire an event for there.
            local shooting = aiming and mode == 'foot' and IsPedShooting(ped)
            if shooting and not crossWasShooting then
                ui('crossFire', {})
            end
            crossWasShooting = shooting
        end
    end)
end

-- =============================================================================
-- Kill mark — the coloured cross that flashes on a kill
-- =============================================================================
-- One rule, written down so it can be retuned rather than re-guessed:
--
--   headshot AND we only ever hit them once   -> red    (clean one-shot headshot)
--   hit them more than once before they died  -> yellow (sloppy, took work)
--   anything else (a clean single non-head hit that still killed) -> white
--
-- "Headshot" asks GET_PED_LAST_DAMAGE_BONE and compares it to SKEL_Head
-- directly, NOT the damage event's own payload — see client_skills.lua's own
-- note on why CEventNetworkEntityDamage's argument layout isn't safe to index
-- by position for anything past victim/attacker.
-- Not `local`: client.lua is close to Lua's 200-local-per-chunk parse-time
-- cap. A plain global costs nothing against that limit.
HEAD_BONE = `SKEL_Head`

-- victim entity -> hits WE landed on them so far. Cleared the moment they
-- die (or the table would grow forever), so a target that gets away and
-- comes back starts a fresh count rather than inheriting an old one.
-- Not `local` — same reasoning as HEAD_BONE above.
killHits = {}

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    if not Config.Crosshair.enable then return end
    local victim, attacker = args[1], args[2]
    local ped = cache.ped or PlayerPedId()
    if attacker ~= ped or victim == ped then return end
    if not DoesEntityExist(victim) or not IsEntityAPed(victim) then return end

    killHits[victim] = (killHits[victim] or 0) + 1

    if IsPedDeadOrDying(victim, true) then
        local hits = killHits[victim]
        killHits[victim] = nil

        local headshot = false
        local boneOk, bone = GetPedLastDamageBone(victim)
        if boneOk then headshot = bone == HEAD_BONE end

        local quality = 'clean'
        if hits > 1 then quality = 'sloppy'
        elseif headshot then quality = 'headshot'
        end
        ui('crossKill', { quality = quality })
        if Config.Debug then
            print(('^3[vice_hud]^7 kill: hits=%s headshotBone=%s(%s) -> %s')
                :format(hits, tostring(headshot), tostring(bone), quality))
        end
    end
end)

-- =============================================================================
-- Third eye — the 2+-option interact reticle
-- =============================================================================
-- A SEPARATE element from #crosshair above, not a new mode on it: that one
-- is gated to an armed weapon actually being aimed (see its own header
-- comment), and this has to show while unarmed too -- opening a vehicle's
-- interact menu is usually not done with a gun out. Purely a display, same
-- as ShowWorldActions: ox_target/client/main.lua's driveUi is what decides
-- when 2+ options have resolved from an actual aim hit (never proximity
-- alone -- see that file's probeOptionCount), this just shows/hides the
-- marker on command.
exports('SetThirdEyeActive', function(active)
    ui('thirdEye', { active = active and true or false })
end)

-- =============================================================================
-- /hudcrosshair, /hudkillmark, /hudthirdeye — preview without needing a real fight
-- =============================================================================
RegisterCommand('hudthirdeye', function()
    exports.vice_hud:SetThirdEyeActive(true)
    print('^3[vice_hud]^7 /hudthirdeye — /hudthirdeyeoff to clear.')
end, false)
RegisterCommand('hudthirdeyeoff', function() exports.vice_hud:SetThirdEyeActive(false) end, false)

RegisterCommand('hudcrosshair', function(_, args)
    local mode = (args[1] == 'vehicle') and 'vehicle' or 'foot'
    ui('crosshair', { active = true, mode = mode })
    print(('^3[vice_hud]^7 /hudcrosshair %s — /hudcrosshair off to clear, or fire a weapon to override it.'):format(mode))
end, false)
RegisterCommand('hudcrosshairoff', function() ui('crosshair', { active = false }) end, false)

RegisterCommand('hudkillmark', function(_, args)
    local quality = args[1]
    if quality ~= 'headshot' and quality ~= 'sloppy' and quality ~= 'clean' then
        print('^3[vice_hud]^7 usage: /hudkillmark headshot|sloppy|clean')
        return
    end
    ui('crosshair', { active = true, mode = 'foot' })
    ui('crossKill', { quality = quality })
end, false)

-- =============================================================================
-- Race lap / checkpoint HUD
-- =============================================================================
-- Fed entirely by whatever race resource is running — sk_streetkings today
-- (see its race_singleplayer_c.lua / race_multiplayer_c.lua), via plain data.
-- vice_hud draws it and does not know sk_streetkings exists.
--
-- elapsedMs is a snapshot, not a stream: the caller is expected to push this
-- only on real events (run start, a checkpoint hit, finish/abort) — the NUI
-- side ticks the displayed time smoothly on its own between pushes (see
-- onLapHud in app.js) rather than needing this called every frame.
exports('SetLapTimer', function(data)
    if not data or data.show == false then
        ui('lapHud', { show = false })
        return
    end
    ui('lapHud', {
        show = true,
        lap = data.lap,
        laps = data.laps,
        cp = data.cp,
        cpTotal = data.cpTotal,
        elapsedMs = data.elapsedMs,
        running = data.running,
    })
end)

RegisterCommand('hudlaptimer', function()
    exports.vice_hud:SetLapTimer({ lap = 1, laps = 2, cp = 10, cpTotal = 16, elapsedMs = 19950, running = true })
    print('^3[vice_hud]^7 /hudlaptimer — sample data, /hudlaptimeroff to clear.')
end, false)
RegisterCommand('hudlaptimeroff', function() exports.vice_hud:SetLapTimer({ show = false }) end, false)

-- =============================================================================
-- World action prompt — a short list of button-glyph + label choices
-- =============================================================================
-- Purely a display: it has no selection logic of its own, because the
-- reference itself pairs each option with its OWN dedicated button (Slim
-- Jim = Triangle, Smash Window = Circle) rather than a highlight-and-
-- confirm list — so the caller is expected to poll its own keybind per
-- option (lib.addKeybind, same as qbx_vehiclekeys already does elsewhere)
-- and just tell this what to show. World-anchored when the caller passes
-- coords (see waCoords, below) — a caller that omits it (qbx_vehiclekeys
-- today) still gets the original fixed screen position.
--
-- FIXED 2026-08-28: this used to take a hand-picked `button` STRING
-- ('triangle'/'circle') with nothing tying it to what the caller's keybind
-- was actually bound to. That let the two drift apart -- and they had:
-- qbx_vehiclekeys showed a triangle for Slim Jim while the working pad
-- button underneath it was Circle, and Smash Window's real button (Circle)
-- had no controller binding at all. Pressing the icon the player was
-- LOOKING AT did nothing, because that icon was never connected to any
-- input in the first place. See qbx_vehiclekeys/client/slimjim.lua for the
-- other half of this fix.
--
-- Now `key` (a control ID, or an ox_lib keybind's own `.hash`) is what the
-- caller passes, and the glyph shown is RESOLVED from it, live, the exact
-- same way the Action Prompts system above does for its own prompts
-- (resolveKey/usingPad, duplicated here rather than reached for across the
-- client.lua/client_overlays.lua split -- see the `ui()` helper at the top
-- of this file for the established precedent). The icon can no longer
-- disagree with the binding: it IS the binding, resolved.

-- GetControlInstructionalButton returns GTA button-font ligatures for a pad,
-- which do not exist in the NUI's fonts -- see the identical helper and
-- comment in client.lua's Action Prompts section, which this mirrors.
local function waSafeLabel(str)
    if not str or str == '' then return nil end

    -- Multi-digit = a raw internal icon index, not a key label; see the
    -- identical guard in client.lua's safeLabel for the full reasoning.
    -- Single digits are kept, because 1-9 are real keys.
    if #str > 1 and str:match('^%d+$') then return nil end

    for i = 1, #str do
        local b = str:byte(i)
        if b < 0x20 or b > 0x7E then return '•' end
    end
    return str
end

-- IS_USING_KEYBOARD_AND_MOUSE rather than IsInputDisabled(2) -- see the
-- identical usingPad() in client.lua for why that check was not reliable.
local function waUsingPad()
    local ok, kbm = pcall(IsUsingKeyboardAndMouse, 2)
    if ok and kbm ~= nil then return not kbm end

    return not IsInputDisabled(2)
end

-- Mirrors client.lua's resolveKey exactly -- see its comments. mouseButton
-- (ox_target/client/main.lua) is passed in here too, as ShowWorldActions' own
-- `key` for a prop's world prompt, so this path had the same "100" bug.
local WA_MOUSE_BUTTON_LABELS = { [24] = 'LMB', [25] = 'RMB' }

local function waResolveKey(key)
    if type(key) == 'string' then return key end
    if type(key) ~= 'number' then return nil end

    if not waUsingPad() and WA_MOUSE_BUTTON_LABELS[key] then
        return WA_MOUSE_BUTTON_LABELS[key]
    end

    local ok, raw = pcall(GetControlInstructionalButton, 0, key, true)
    if not ok or not raw then return nil end
    return waSafeLabel(raw:sub(3))
end

local waOptions = nil     -- the last { label, key } list shown, for the refresh thread
local waDevice = nil

local function waResolveAll()
    local device = waUsingPad() and 'pad' or 'kbm'
    local resolved = {}
    if waOptions then
        for i, opt in ipairs(waOptions) do
            resolved[i] = { label = opt.label, glyph = waResolveKey(opt.key), device = device }
        end
    end
    return resolved, device
end

-- World-anchoring -- closes the gap #world-actions in index.html and the
-- comment above `#world-actions` in style.css both flag: this used to be a
-- fixed screen position with no connection to the world point it's about.
--
-- `coords` (optional, a vector3) is the third piece: when given, a
-- per-frame thread below projects it every tick via
-- GetScreenCoordFromWorldCoord and pushes the result as its own lightweight
-- message (worldActionsPos) rather than folding it into ShowWorldActions's
-- own ui('worldActions', ...) push -- that message rebuilds the whole
-- options list DOM (see onWorldActions in app.js), which running it every
-- frame would do for nothing; same reasoning as onPromptProgress writing
-- the action-prompt hold ring as its own direct style update instead of a
-- full renderPrompts() every tick. A caller that omits `coords`
-- (qbx_vehiclekeys today) gets nothing from that thread at all --
-- #world-actions just stays on its own CSS fixed position, unchanged from
-- before this existed.
local waCoords = nil

-- Also drives the icon-only-at-range / full-label-up-close split ("both" of
-- the two prop-prompt options considered): computed locally here each frame
-- against the live player position rather than requiring ox_target to keep
-- re-pushing its own distance, since this thread already has to run every
-- tick anyway to track the projection. Roughly ox_target's own default
-- interact range (see ox_target:proximityRadius); not pixel/gameplay tuned.
local WA_COMPACT_DISTANCE = 1.5

--- options: array of { label, key } -- key is a native GTA control ID
--- (see PAD::IS_CONTROL_PRESSED's `action` param) or an ox_lib keybind's
--- own `.hash` field, exactly as ShowActionPrompt's `key` already works.
--- coords (optional): vector3 world point to anchor the prompt to -- see
--- the world-anchoring comment above. Omit it for the old fixed-position
--- behaviour.
exports('ShowWorldActions', function(options, coords)
    waOptions = options or {}
    waCoords = coords
    local resolved, device = waResolveAll()
    waDevice = device
    ui('worldActions', { show = true, options = resolved })
end)
exports('HideWorldActions', function()
    waOptions = nil
    waCoords = nil
    ui('worldActions', { show = false })
end)

-- Re-resolve when the input device changes, same pattern as the Action
-- Prompts refresh thread -- so a mid-prompt controller/keyboard swap updates
-- the icon instead of leaving it wrong until the caller happens to re-push.
CreateThread(function()
    while true do
        Wait(400)
        if waOptions then
            local device = waUsingPad() and 'pad' or 'kbm'
            if device ~= waDevice then
                waDevice = device
                local resolved = waResolveAll()
                ui('worldActions', { show = true, options = resolved })
            end
        end
    end
end)

-- The world-anchoring thread itself -- see waCoords's own comment above for
-- why this is a separate push from ShowWorldActions/the refresh thread.
-- Idles at Wait(200) while nothing is world-anchored (still cheap enough to
-- just poll rather than restructure around an event) and only runs every
-- frame while waCoords is actually set.
CreateThread(function()
    while true do
        if waCoords then
            local playerCoords = GetEntityCoords(cache.ped or PlayerPedId())
            local onScreen, sX, sY = GetScreenCoordFromWorldCoord(waCoords.x, waCoords.y, waCoords.z)
            ui('worldActionsPos', {
                show = onScreen,
                x = sX,
                y = sY,
                compact = #(playerCoords - waCoords) > WA_COMPACT_DISTANCE,
            })
            Wait(0)
        else
            Wait(200)
        end
    end
end)

RegisterCommand('hudworldactions', function()
    -- 51 = INPUT_CONTEXT ('E' on keyboard), 47 = INPUT_DETONATE ('Y'/Triangle
    -- on pad) -- real GTA control IDs, purely so this demo resolves to
    -- something real on both devices without needing a live ox_lib keybind.
    exports.vice_hud:ShowWorldActions({
        { label = 'Slim Jim', key = 47 },
        { label = 'Smash Window', key = 51 },
    })
    print('^3[vice_hud]^7 /hudworldactions — sample data. /hudworldactionsoff to clear.')
end, false)
RegisterCommand('hudworldactionsoff', function() exports.vice_hud:HideWorldActions() end, false)

-- =============================================================================
-- Lockpick check — analog direction-fill ring
-- =============================================================================
-- The caller owns the button (its own lib.addKeybind, same pattern
-- qbx_vehiclekeys already uses for searching a car for keys) and just tells
-- this when the hold started and ended; this owns the ring, the direction/
-- completion decision, and hands the result back as an event — the same
-- "plain data in, plain event out" shape the wheels use.
--
-- REWORKED AGAIN 2026-09-12, this time replacing the "release inside a
-- target zone" mechanic entirely, per the user-approved HTML mockup
-- (lockpick_preview.html) worked out over many rounds of feedback against
-- the GTA VI: An Extended Look trailer footage. There is no more zone and
-- no more release-based resolution at all:
--   * dragging right-to-left fills the ring, anchored growing from the
--     right; dragging left-to-right fills it identically, anchored growing
--     from the left -- both LOOK the same the whole time you're mid-drag.
--   * reaching 100% right-to-left is the real pick (success).
--   * reaching 100% left-to-right is a trap: it trips an "alarm" outcome
--     instead, meant to eventually wire into a car alarm elsewhere (see
--     exports('LockpickAlarm'-adjacent event below) -- NOT built here.
-- Direction/fill are derived live every tick from where the input currently
-- sits, not from an accumulated "effort" score -- see lockpickTick() below.
--
-- Wrapped in do...end for the same reason the interact-menu/controller
-- section is — see the comment there.
do
local lockpickActive = false
local lockpickPct = 0   -- current fill, 0-100, always re-derived live (see lockpickTick)
local lockpickDir = -1  -- -1 = right-to-left (the real pick), 1 = left-to-right (the trap)

-- INPUT_LOOK_LR (control ID 1 — confirmed against _tools/fivem_docs' own
-- game-references/controls table, NOT guessed: that page lists it as bound
-- to "RIGHT STICK X" on a pad AND to raw mouse-movement ("MOUSE RIGHT") on
-- keyboard, which is exactly the dual pad-stick/mouse-delta signal this
-- minigame needs). Only the horizontal axis matters now -- the mockup's own
-- `dir`/`pct` logic is driven purely by dx, never dy (dy only ever moved
-- the mockup's centre glyph for visual noise, which this port simplifies
-- away, see lockpickTick's comment below). INPUT_ATTACK (24) is the same
-- LMB control already used elsewhere in this file (see
-- WA_MOUSE_BUTTON_LABELS[24] = 'LMB' above) — reused here as the "is the
-- mouse player dragging" gate.
local LOCKPICK_CONTROL_LOOK_LR = 1
local LOCKPICK_CONTROL_ATTACK  = 24

-- Below this stick deflection, the pad isn't meaningfully steering — reads
-- as centred/idle rather than "barely pushed", absorbing analog deadzone
-- noise so a resting pad doesn't register a phantom direction.
local LOCKPICK_IDLE_THRESHOLD = 0.12

-- GET_CONTROL_NORMAL's mouse-driven value for LOOK_LR is a raw per-frame
-- look-camera delta (tuned for camera turn speed), not a position — unlike
-- a pad's stick, which reports where it physically IS this frame. The
-- mockup's `dx = current.x - dragStart.x` needs an actual position, so for
-- mouse it's reconstructed by summing that per-frame delta for as long as
-- LMB is held — arithmetically this sum always equals "how far the mouse
-- has moved since LMB went down", i.e. a genuine net position, not an
-- "integrated effort" score. Scaled up for the same reason the old
-- effort-based build scaled it: nowhere near a usable range unscaled on a
-- deliberate drag. Not measured against a live client (see this repo's own
-- note on why: FiveM client crashes on this dev PC) — a human needs to
-- feel this in-game and this constant is the one to retune.
local LOCKPICK_MOUSE_SCALE = 6.0

-- How far the reconstructed mouse position (in LOCKPICK_MOUSE_SCALE-d
-- units, see above) has to travel from centre to reach a full 100% fill —
-- the direct analog of the mockup's "Fill sensitivity" slider (default
-- 160, in raw drag pixels). There is no equivalent slider here, just this
-- one constant; a caller wanting an easier/harder check no longer has a
-- knob for it now that the mechanic is purely positional (see
-- StartLockpickCheck's own comment on why cfg.durationMs/zoneLen are gone).
local LOCKPICK_MOUSE_SENSITIVITY = 220

-- How fast the reconstructed mouse position decays back toward centre once
-- LMB is released mid-check (the mockup's own "Decay rate" slider, in the
-- same units as LOCKPICK_MOUSE_SENSITIVITY per second) — letting go doesn't
-- freeze progress in place, it drains back down, same read as the mockup's
-- own tick() "not dragging" branch.
local LOCKPICK_MOUSE_DECAY_PER_SEC = 90

local lockpickMouseDx = 0 -- reconstructed net mouse position since LMB was last (re)pressed, see comment above

--- Reads this frame's signed, normalised drag position as -1.0..1.0
--- (negative = pushed toward right-to-left / the real pick, positive =
--- pushed toward left-to-right / the trap), disabling the controls it
--- reads so a lockpick doesn't ALSO spin the camera or fire a weapon while
--- it's being worked (DisableControlAction has to be called every frame it
--- should apply, and read back via GetDisabledControlNormal/
--- IsDisabledControlPressed instead of the un-disabled natives once it has
--- — see PAD::DISABLE_CONTROL_ACTION / PAD::GET_DISABLED_CONTROL_NORMAL /
--- PAD::IS_DISABLED_CONTROL_PRESSED, all confirmed via _tools/nativedb).
---
--- Pad: the stick's OWN current x-deflection IS a position already (a
--- physical stick doesn't need reconstructing the way a mouse delta does)
--- — read directly, no accumulation, matching the mockup's "current
--- position relative to where the hold started, not integrated effort over
--- time" requirement to the letter.
--- Mouse: gated on LMB actually being held (waUsingPad()'s counterpart,
--- WA_MOUSE_BUTTON_LABELS[24], is the established "24 = LMB" precedent in
--- this file); while held, LOOK_LR's per-frame delta accumulates into
--- lockpickMouseDx (see its own comment above); while not held, that
--- accumulator decays back toward 0 instead of freezing.
local function lockpickReadDx(dtMs)
    DisableControlAction(0, LOCKPICK_CONTROL_LOOK_LR, true)
    DisableControlAction(0, LOCKPICK_CONTROL_ATTACK, true)

    if waUsingPad() then
        local sx = GetDisabledControlNormal(0, LOCKPICK_CONTROL_LOOK_LR)
        if math.abs(sx) < LOCKPICK_IDLE_THRESHOLD then return 0 end
        return math.max(-1, math.min(1, sx))
    end

    if not IsDisabledControlPressed(0, LOCKPICK_CONTROL_ATTACK) then
        -- LMB not held: drain the reconstructed position back toward 0,
        -- same feel as the mockup's own decay-while-not-dragging branch.
        local decayStep = LOCKPICK_MOUSE_DECAY_PER_SEC * (dtMs / 1000)
        if lockpickMouseDx > 0 then
            lockpickMouseDx = math.max(0, lockpickMouseDx - decayStep)
        else
            lockpickMouseDx = math.min(0, lockpickMouseDx + decayStep)
        end
        return lockpickMouseDx / LOCKPICK_MOUSE_SENSITIVITY
    end

    local mx = GetDisabledControlNormal(0, LOCKPICK_CONTROL_LOOK_LR)
    lockpickMouseDx = lockpickMouseDx + mx * LOCKPICK_MOUSE_SCALE
    lockpickMouseDx = math.max(-LOCKPICK_MOUSE_SENSITIVITY, math.min(LOCKPICK_MOUSE_SENSITIVITY, lockpickMouseDx))
    return lockpickMouseDx / LOCKPICK_MOUSE_SENSITIVITY
end

--- Re-derives lockpickPct/lockpickDir for this frame from the current input
--- position (dtMs = real elapsed time, used only for the mouse's own
--- decay-while-released branch above) and returns both. Positional, not
--- effort-accumulated, exactly like the mockup's own tick(): pct is always
--- `abs(dx) * 100`, dir is always `dx < 0 and -1 or 1`, recomputed fresh
--- every frame rather than built up over time.
local function lockpickTick(dtMs)
    local dx = lockpickReadDx(dtMs)
    lockpickDir = dx < 0 and -1 or 1
    lockpickPct = math.max(0, math.min(100, math.abs(dx) * 100))
    return lockpickPct, lockpickDir
end

--- cfg: { key (a control ID, or an ox_lib keybind's own `.hash` — resolved
--- LIVE into a text glyph via waResolveKey, the same "the icon IS the
--- binding, resolved" pattern ShowWorldActions/action prompts already use
--- elsewhere in this file, rather than a hand-picked string that can drift
--- out of sync with what's actually bound), glyph (legacy raw string
--- fallback for a caller not yet passing `key` — kept so
--- qbx_vehiclekeys/client/slimjim.lua's existing `glyph = 'R'` call keeps
--- working unchanged).
---
--- zoneLen/zoneStart are GONE: there is no more target zone at all (see the
--- do...end's own header comment for the mechanic this replaced). A caller
--- still passing them is harmless — they're just never read.
---
--- durationMs is ALSO gone as a fill-rate knob: the fill is now purely
--- positional (see lockpickTick), so there is no rate or duration left to
--- size. A caller still passing it is likewise harmless.
--- Call the instant the player PRESSES the button.
exports('StartLockpickCheck', function(cfg)
    cfg = cfg or {}
    lockpickActive = true
    lockpickPct = 0
    lockpickDir = -1
    lockpickMouseDx = 0
    local glyph = cfg.key ~= nil and waResolveKey(cfg.key) or cfg.glyph
    ui('lockpick', { show = true, glyph = glyph or 'R' })
end)

--- Call the instant the button is RELEASED. There is no more release-based
--- win/lose check at all — completion is purely "pct reached 100, which
--- direction was it" (see the CreateThread loop below), decided mid-hold,
--- not on release. Releasing before that just abandons the attempt with no
--- outcome, same as CancelLockpickCheck — kept as its own export (rather
--- than folded into Cancel) because "the player let go" and "the caller is
--- force-ending this" are different callers' events even though they now
--- do the same thing here.
exports('ReleaseLockpickCheck', function()
    if not lockpickActive then return end
    lockpickActive = false
    ui('lockpick', { show = false })
end)

--- Aborts with no result event at all — for e.g. the vehicle driving off or
--- the player being interrupted mid-hold, where neither success nor the
--- alarm is the right read.
exports('CancelLockpickCheck', function()
    lockpickActive = false
    ui('lockpick', { show = false })
end)

-- Wait(0) now, not a slower poll: reading analog stick/mouse deflection and
-- disabling its controls both need to happen every rendered frame to feel
-- responsive and to keep DisableControlAction actually in effect (it only
-- holds for the frame it's called on) — a slower poll would both miss fast
-- stick flicks and let the camera/weapon controls sneak back in for most
-- frames at 60fps.
CreateThread(function()
    local lastTick = GetGameTimer()
    while true do
        Wait(lockpickActive and 0 or 200)
        local now = GetGameTimer()
        local dtMs = now - lastTick
        lastTick = now
        if lockpickActive then
            local pct, dir = lockpickTick(dtMs)
            ui('lockpickProgress', { pct = pct, dir = dir })
            if pct >= 100 then
                lockpickActive = false
                if dir < 0 then
                    -- Right-to-left to 100% — the real pick.
                    ui('lockpickResult', { success = true })
                    TriggerEvent('vice_hud:lockpickResult', true)
                else
                    -- Left-to-right to 100% — looked identical to progress
                    -- the whole time, but this is the trap: fire a
                    -- DISTINCT outcome rather than folding it into
                    -- lockpickResult's boolean, so a caller can tell "you
                    -- finished it the wrong way" apart from "you didn't
                    -- finish it" and eventually wire a real car alarm to
                    -- it — that wiring is a different resource's job, not
                    -- built here. Bare TriggerEvent, no payload: there's
                    -- nothing to report beyond "it happened".
                    ui('lockpickAlarm', {})
                    TriggerEvent('vice_hud:lockpickAlarm')
                end
            end
        end
    end
end)

RegisterCommand('hudlockpick', function()
    exports.vice_hud:StartLockpickCheck({ key = 51 })
    print('^3[vice_hud]^7 /hudlockpick — ring started, drag right-to-left to pick it (left-to-right traps the alarm instead). /hudlockpickrelease to abandon it now.')
end, false)
RegisterCommand('hudlockpickrelease', function() exports.vice_hud:ReleaseLockpickCheck() end, false)
end -- close the do opened above local lockpickActive

-- =============================================================================
-- Interact menu — Phase 1 of the ox_target-replacement project
-- =============================================================================
-- Just a data-driven option list. No targeting geometry, no raycast, no
-- zones — that engine, and any real migration of the 166 files this server
-- has calling ox_target today, is a separate, later project; reimplementing
-- all of that blind in one pass with no live game to test against was
-- explicitly ruled out. This resource has no idea what calls it.
--
-- NUI-based (html/index.html's #interact, html/app.js's onInteract /
-- moveInteractSel / confirmInteract / closeInteract), holding NUI focus
-- while open so the page's own keyboard (arrows/Enter/Escape) and mouse
-- (click a row) handling both just work.
--
-- [Fix, 2026-09-09] This briefly ran through ScaleformUI's UIMenu instead of
-- this NUI panel, because ScaleformUI's own input polling avoided
-- SetNuiFocus. That trade turned out to cost far more than it saved:
-- ScaleformUI eagerly holds several scaleform handles for the ENTIRE client
-- session -- including three for a pause-menu system nothing in this
-- resource ever opens -- badly enough to starve OTHER resources' own
-- RequestScaleformMovie calls (fenix-police's BUSTED arrest screen, and
-- previously um_spawn's map scaleform -- see the removed
-- client_scaleform_safety.lua's own history for that report). ScaleformUI
-- has been removed from this resource entirely rather than patched further,
-- which fixes that starvation at the source instead of chasing it resource
-- by resource. This NUI panel was never actually deleted when the Lua side
-- moved to ScaleformUI, so this just rewires Lua back to talk to it -- no
-- controller-specific input polling is restored here (out of scope for this
-- pass; keyboard and mouse are fully functional).
--
-- Released the same three ways /movehud's own focus is: on select/close, on
-- this resource (re)starting, and /hudfocus's broadcast in case whatever
-- opened it never tells it to close.
do
local menuOpen = false     -- true while #interact has NUI focus
local interactAnchor = nil -- world point to track, or nil for the fixed CSS position

-- Opaque value the current menu's OPENER passed to OpenInteractMenu, echoed
-- back on both events. Two callers (qbx_vehiclekeys and, as of the ox_target
-- migration, ox_target itself) can now both have a menu open across
-- different moments; without a token, a caller has no way to tell "was that
-- interactSelect/interactClose meant for MY menu" and a force-close-by-a-
-- new-opener used to look identical to nothing having happened at all --
-- the previous caller's own state (e.g. ox_target's uiMode) would go stale,
-- silently misattributing the NEXT select it saw to the wrong option. A
-- caller that doesn't pass a token gets nil back, same as before this
-- existed, so this is backward compatible with any caller ignoring it.
local currentToken = nil

-- Genuinely silent: hiding the NUI panel and dropping focus never makes the
-- page itself post interactSelect/interactClose back (only the PLAYER
-- confirming/cancelling does that, via the keydown/click handlers in
-- app.js) -- unlike the old ScaleformUI version, there is no close-triggered
-- callback here to suppress.
local function closeInteractMenuSilently()
    if menuOpen then
        menuOpen = false
        SetNuiFocus(false, false)
    end
    ui('interact', { show = false })
    interactAnchor = nil
end

-- World-anchoring tracking thread -- confirmed live feedback (2026-09-07):
-- the menu sat at a fixed screen position no matter what it was about,
-- instead of appearing near the reticle/bone ox_target resolved it from.
-- Same mechanism ShowWorldActions already uses above (waCoords) -- a
-- per-frame thread projects a world point via GetScreenCoordFromWorldCoord
-- and pushes it as its own lightweight message (see onInteractPos in
-- app.js) rather than folding it into the full 'interact' open message,
-- which rebuilds the whole option list DOM. interactAnchor nil (the default
-- -- qbx_vehiclekeys and any caller that omits it) leaves the menu at its
-- fixed CSS position, untouched by this thread.
CreateThread(function()
    while true do
        if interactAnchor and menuOpen then
            local onScreen, sX, sY = GetScreenCoordFromWorldCoord(interactAnchor.x, interactAnchor.y, interactAnchor.z)
            ui('interactPos', { show = onScreen, x = sX, y = sY })
            Wait(0)
        else
            Wait(200)
        end
    end
end)

--- options: array of { label, badges: {'stamina'|'focus', ...}, selected }
--- selected (top-level, optional, 0-based): which row starts highlighted;
--- defaults to whichever option has selected=true, or the first one.
--- token (optional): opaque value echoed back on interactSelect/interactClose
--- so a caller can tell those events apart from another caller's menu (see
--- currentToken's comment above).
--- anchor (optional): a vector3 world point (e.g. the bone/offset ox_target
--- already resolved, or the aim raycast's endpoint) to track the menu to
--- instead of the fixed CSS position -- see interactAnchor's comment above.
exports('OpenInteractMenu', function(options, selected, token, anchor)
    options = options or {}

    -- A caller opening over an already-open menu force-closes the PREVIOUS
    -- one -- that owner needs a real interactClose with ITS token so it
    -- resets instead of going stale.
    if menuOpen then
        local previousToken = currentToken
        closeInteractMenuSilently()
        TriggerEvent('vice_hud:interactClose', previousToken)
    end

    currentToken = token
    interactAnchor = anchor

    local startIndex = tonumber(selected)
    if startIndex == nil then
        startIndex = 0
        for i, o in ipairs(options) do
            if o.selected then startIndex = i - 1 break end
        end
    end

    local payload = { show = true, options = options, selected = startIndex }

    -- Anchor's first frame: compute it up front rather than waiting for the
    -- tracking thread's next tick, so an anchored menu never flashes at the
    -- fixed position for even one frame before jumping to the real spot.
    if anchor then
        local onScreen, sX, sY = GetScreenCoordFromWorldCoord(anchor.x, anchor.y, anchor.z)
        payload.anchored, payload.onScreen, payload.x, payload.y = true, onScreen, sX, sY
    end

    ui('interact', payload)
    menuOpen = true
    SetNuiFocus(true, true)

    -- Light rumble on open, matching ShowActionPrompt's own appear pulse
    -- (client.lua) so both textui pieces give the same "something just
    -- appeared" feedback.
    --
    -- Invoked by hash, not the generated `SetControlShake` global -- see
    -- client.lua's promptRumble for why (confirmed nil live in-game despite
    -- being a real, long-standing native). This particular call site errored
    -- AFTER the menu had already been shown above, so it opened and then
    -- immediately got torn down when the error propagated up through
    -- ox_target's driveUi and its pcall'd supervisor closed it again --
    -- looked like the menu never appeared at all.
    Citizen.InvokeNative(0x48B3886C1358D0D5, 0, 80, 15)
end)

exports('CloseInteractMenu', function()
    closeInteractMenuSilently()
end)

-- The other half of moveInteractSel's own comment in app.js: Lua doesn't
-- track a selection cache of its own (no controller-side polling to keep in
-- sync with in this pass), so there's nothing to do here beyond ack'ing the
-- fetch -- kept registered so a future controller-input pass has a slot
-- ready and so app.js's post() never quietly 404s in the meantime.
RegisterNUICallback('interactMove', function(_, cb)
    cb({ ok = true })
end)

RegisterNUICallback('interactSelect', function(data, cb)
    local index = tonumber(data and data.index) or 0
    local token = currentToken
    closeInteractMenuSilently()
    TriggerEvent('vice_hud:interactSelect', index, token)
    cb({ ok = true })
end)

RegisterNUICallback('interactClose', function(_, cb)
    local token = currentToken
    closeInteractMenuSilently()
    TriggerEvent('vice_hud:interactClose', token)
    cb({ ok = true })
end)

-- /hudfocus already broadcasts this to clear every focus-holding panel in
-- the resource, not just the editor — the interact menu is another one.
AddEventHandler('vice_hud:releaseFocus', function()
    closeInteractMenuSilently()
end)

RegisterCommand('hudinteract', function()
    exports.vice_hud:OpenInteractMenu({
        { label = 'Logger Beer' },
        { label = 'Lavazas Beer' },
        { label = 'Blitz Berry Smoothie', badges = { 'stamina', 'focus' } },
        { label = 'Blitz Green Smoothie', badges = { 'stamina' } },
    }, 0)
    print('^3[vice_hud]^7 /hudinteract — sample data. Arrows/click to move, Enter/click to pick, Esc to cancel.')
end, false)

-- NUI focus is GLOBAL and survives this resource restarting, so a panel
-- that died holding it takes the player's hotbar keys with it until they
-- rejoin. Same safety net client_skills.lua's own panel has.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if menuOpen then SetNuiFocus(false, false) end
end)
end -- close the do opened above
