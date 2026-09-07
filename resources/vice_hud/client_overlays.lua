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
-- Lockpick check — "hold, release inside the zone"
-- =============================================================================
-- The caller owns the button (its own lib.addKeybind, same pattern
-- qbx_vehiclekeys already uses for searching a car for keys) and just tells
-- this when the hold started and ended; this owns the ring's timing, the
-- zone, and the win/lose decision, then hands the result back as an event —
-- the same "plain data in, plain event out" shape the wheels use.

-- Wrapped in do...end for the same reason the interact-menu/controller
-- section is — see the comment there. Six locals, none referenced outside
-- this section (verified).
do
local lockpickActive = false
local lockpickZoneStart, lockpickZoneLen = 0, 10
local lockpickStartedAt = 0
local lockpickDurationMs = 3000

local function lockpickPct()
    return math.min(100, ((GetGameTimer() - lockpickStartedAt) / lockpickDurationMs) * 100)
end

--- cfg: { durationMs (time to fill the ring), zoneLen (0-100, width of the
--- win window), zoneStart (0-100, randomised within a sane range if
--- omitted), glyph (the button shown at the ring's centre, default 'R') }
--- Call the instant the player PRESSES the button.
exports('StartLockpickCheck', function(cfg)
    cfg = cfg or {}
    lockpickActive = true
    lockpickDurationMs = cfg.durationMs or 3000
    lockpickZoneLen = cfg.zoneLen or 10
    -- Kept off the very start and very end of the ring on purpose: a zone
    -- touching 0 is unreachable (there is no fill yet to be "inside" it the
    -- instant the check starts) and one touching 100 is indistinguishable
    -- from the auto-fail at full.
    lockpickZoneStart = cfg.zoneStart or math.random(30, 85 - lockpickZoneLen)
    lockpickStartedAt = GetGameTimer()
    ui('lockpick', { show = true, zoneStart = lockpickZoneStart, zoneLen = lockpickZoneLen, glyph = cfg.glyph or 'R' })
end)

--- Call the instant the button is RELEASED. Resolves the check immediately
--- against whatever the ring's fill actually is at that moment.
exports('ReleaseLockpickCheck', function()
    if not lockpickActive then return end
    lockpickActive = false
    local pct = lockpickPct()
    local success = pct >= lockpickZoneStart and pct <= (lockpickZoneStart + lockpickZoneLen)
    ui('lockpickResult', { success = success })
    TriggerEvent('vice_hud:lockpickResult', success)
end)

--- Aborts with no result event at all — for e.g. the vehicle driving off or
--- the player being interrupted mid-hold, where neither win nor lose is
--- the right read.
exports('CancelLockpickCheck', function()
    lockpickActive = false
    ui('lockpick', { show = false })
end)

CreateThread(function()
    while true do
        Wait(lockpickActive and 50 or 200)
        if lockpickActive then
            local pct = lockpickPct()
            ui('lockpickProgress', { pct = pct })
            if pct >= 100 then
                -- Ran the ring all the way out without releasing — an
                -- automatic fail, same as missing the zone on purpose.
                lockpickActive = false
                ui('lockpickResult', { success = false })
                TriggerEvent('vice_hud:lockpickResult', false)
            end
        end
    end
end)

RegisterCommand('hudlockpick', function(_, args)
    local zoneLen = tonumber(args[1]) or 12
    exports.vice_hud:StartLockpickCheck({ durationMs = 3000, zoneLen = zoneLen })
    print('^3[vice_hud]^7 /hudlockpick — ring started. /hudlockpickrelease to try releasing it now.')
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
-- Holds NUI focus while open — arrow keys / Enter / Escape drive the list —
-- released the same three ways /movehud's own focus is: on select/close,
-- on this resource (re)starting, and a watchdog in case whatever opened it
-- never tells it to close.

-- Wrapped in one do...end: this and the whole controller-support section
-- below it together add 14 top-level locals, all read/written only within
-- this combined region (nothing outside it references any of them). Lua's
-- 200-local-per-main-chunk cap is a hard PARSE-TIME limit — a script that
-- crosses it fails to load at all, silently, with nothing visible
-- server-side and only a client-console error to go on. A do...end block
-- lets these registers be reused once the block ends instead of staying
-- live for the rest of the file, which is what keeps client.lua under
-- that cap as it grows.
-- This panel used to be an NUI page with its own keyboard/controller polling
-- and SetNuiFocus juggling. ScaleformUI's UIMenu/MenuHandler owns all of
-- that itself now (input polling, Up/Down/Accept/Cancel, weapon-wheel/
-- attack/aim disabling while a menu is open) via the CreateThread loop
-- already running in vendor/ScaleformUI_Lua/src/ScaleformUI/mainScaleform.lua,
-- and reads controls natively rather than through NUI focus, so none of the
-- old SetNuiFocus/DisableControlAction/polling-thread machinery is needed
-- here any more.
do
local interactMenu = nil -- rebuilt fresh on every OpenInteractMenu call
-- true while THIS file is the one closing the menu (a select, or an explicit
-- CloseInteractMenu/releaseFocus) -- the old NUI version fired
-- vice_hud:interactClose ONLY for Cancel/Back, never for those, and
-- OnMenuClose below fires for every close path so it needs to tell them apart.
local suppressCloseEvent = false

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

-- ScaleformUI has no exact 'stamina'/'focus' badge -- these are the closest
-- built-in BadgeStyle icons (see vendor/ScaleformUI_Lua/src/Elements/Badge.lua)
-- until real custom icons are worth the runtime-texture-dict setup.
local BADGE_MAP = {
    stamina = BadgeStyle.HEALTH_HEART,
    focus   = BadgeStyle.STAR,
}

--[[ ---------------------------------------------------------------------------
     mz_textui-style reskin  --  BEGIN  (added by vice_hud; safe to delete, see
     git history for the pre-patch OpenInteractMenu)
     ---------------------------------------------------------------------------
     ScaleformUI's UIMenu is a compiled native scaleform, not an NUI page --
     there is no CSS here, so this can only push it AS CLOSE as its documented
     Lua API allows toward the naked-text, hard-outline look #prompts already
     uses for the single-option case (see this file's header comment and
     html/style.css's `.prompt`/`.glyph`, both of which credit the same
     reference textui by name). The banner image and the item list's own
     background panel are baked into the scaleform itself -- SetBannerColor
     only tints the banner, it does not remove it, and nothing in the
     documented API removes the list panel at all. What IS reachable:
       - HasInstructionalButtons(false): drops the bottom control-glyph bar,
         which is native GTA menu chrome mz_textui has none of.
       - MenuAlignment(RIGHT): anchors to the same side of the screen the
         single-option prompt and mz_textui itself both sit on, rather than
         the engine's left-aligned default -- so a player doesn't see the
         prompt jump from one corner to a completely different one depending
         on whether one option or several are on offer. True bottom-anchoring
         is not exposed by the API; the vertical position stays wherever
         ScaleformUI itself places a right-aligned menu.
       - Per-item HighlightColor: recoloured to the same live accent every
         other popup on this server already themes from (see resolveAccentColor
         below), so the one row a player is about to confirm reads as the
         same "accent means selected" language, not GTA's default blue
         highlight. There is no HighlightedTextColor (or even TextColor) in
         THIS Lua port despite both being documented -- only MainColor and
         HighlightColor exist on vendor/ScaleformUI_Lua's own UIMenuItem (see
         Items/_UIMenuItem.lua) -- so the text-on-highlight contrast is
         whatever ScaleformUI's compiled scaleform already does natively,
         same as every other UIMenu on this server.
     ]] --

--- Reads the same 'vice_hud:theme' state bag ox_lib/resource/client.lua and
--- (formerly) ox_target/client/vice_theme.lua already read -- personal
--- choice winning over the server-wide default, same convention as this
--- file's own theme.lua. Falls back to theme.lua's own DEFAULT.preset
--- ('earned') accent for the one tick before theme.lua's startup thread has
--- published anything yet.
local ACCENT_FALLBACK = '#5fd8c8'

local function resolveAccentColor()
    local ok, personal = pcall(function() return LocalPlayer.state['vice_hud:theme'] end)
    local t = (ok and type(personal) == 'table') and personal or GlobalState['vice_hud:theme']
    local hex = (type(t) == 'table' and type(t.accent) == 'string') and t.accent or ACCENT_FALLBACK
    return SColor.FromHex('#FF' .. hex:gsub('#', ''))
end
-- vice_hud: mz_textui-style reskin -- END (see below for the three more call
-- sites inside OpenInteractMenu itself) ---------------------------------

local function closeInteractMenuSilently()
    if interactMenu and interactMenu:Visible() then
        suppressCloseEvent = true
        interactMenu:Visible(false)
        suppressCloseEvent = false
    end
end

--- options: array of { label, badges: {'stamina'|'focus', ...}, selected }
--- selected (top-level, optional, 0-based): which row starts highlighted;
--- defaults to whichever option has selected=true, or the first one.
--- token (optional): opaque value echoed back on interactSelect/interactClose
--- so a caller can tell those events apart from another caller's menu (see
--- currentToken's comment above). Omit it and behaviour is exactly as before.
exports('OpenInteractMenu', function(options, selected, token)
    options = options or {}

    -- A caller opening over an already-open menu force-closes the PREVIOUS
    -- one -- that owner needs a real (non-suppressed) interactClose with ITS
    -- token so it resets instead of going stale, unlike the other
    -- closeInteractMenuSilently() call sites below (select/CloseInteractMenu/
    -- releaseFocus/onResourceStop), which are the current owner closing its
    -- own menu and already fire their own event or intentionally don't.
    if interactMenu and interactMenu:Visible() then
        local previousToken = currentToken
        suppressCloseEvent = true
        interactMenu:Visible(false)
        suppressCloseEvent = false
        TriggerEvent('vice_hud:interactClose', previousToken)
    end

    currentToken = token

    local startIndex = tonumber(selected)
    if startIndex == nil then
        startIndex = 0
        for i, o in ipairs(options) do
            if o.selected then startIndex = i - 1 break end
        end
    end

    -- Rebuilt on every open rather than reused: ScaleformUI menus are cheap
    -- to throw away, and a fresh menu means a caller changing `options`
    -- between calls can never see a stale item left over from the last one.
    -- Offset comes from Config.InteractMenu (ScaleformUI's 1280x720 space, see
    -- that block's comment). Read defensively so a config predating it still
    -- loads -- falling back to the old 0,0 top-of-screen placement rather than
    -- erroring on a nil index.
    local menuCfg = Config.InteractMenu or {}
    interactMenu = UIMenu.New('', '', menuCfg.offsetX or 0, menuCfg.offsetY or 0, false, '', '', false)
    interactMenu:CanPlayerCloseMenu(true)
    -- mz_textui-style reskin -- see this function's header comment above.
    interactMenu:MenuAlignment(MenuAlignment.RIGHT)
    interactMenu:HasInstructionalButtons(false)

    local accent = resolveAccentColor()

    for _, opt in ipairs(options) do
        local item = UIMenuItem.New(tostring(opt.label or ''), '')
        item:HighlightColor(accent)
        for _, badge in ipairs(opt.badges or {}) do
            local style = BADGE_MAP[badge]
            if style then item:LeftBadge(style) end
        end
        interactMenu:AddItem(item)
    end

    interactMenu.OnItemSelect = function(_, _, index)
        -- Old NUI version closed BEFORE firing the select event; keep that
        -- order in case a caller opens a new menu from inside its handler.
        closeInteractMenuSilently()
        -- ScaleformUI indices are 1-based; the public event contract here
        -- has always been 0-based (qbx_vehiclekeys already depends on it).
        TriggerEvent('vice_hud:interactSelect', index - 1, token)
    end
    interactMenu.OnMenuClose = function()
        -- Fires for EVERY close (Cancel/Back included) -- suppressCloseEvent
        -- is what keeps this matching the old contract of "only a Cancel
        -- fires interactClose".
        if not suppressCloseEvent then
            TriggerEvent('vice_hud:interactClose', token)
        end
    end

    interactMenu:Visible(true)
    interactMenu:CurrentSelection(startIndex + 1)

    -- Light rumble on open, matching ShowActionPrompt's own appear pulse
    -- (client.lua) so both textui pieces give the same "something just
    -- appeared" feedback. No sound here on purpose -- ScaleformUI's own
    -- menu-open cue already plays natively; adding vice_hud's would double up.
    --
    -- Invoked by hash, not the generated `SetControlShake` global -- see
    -- client.lua's promptRumble for why (confirmed nil live in-game despite
    -- being a real, long-standing native). This particular call site errored
    -- AFTER Visible(true) above had already run, so the menu was opened and
    -- then immediately torn down when the error propagated up through
    -- ox_target's driveUi and its pcall'd supervisor closed it again --
    -- looked like the menu never appeared at all.
    Citizen.InvokeNative(0x48B3886C1358D0D5, 0, 80, 15)
end)

exports('CloseInteractMenu', function()
    closeInteractMenuSilently()
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
    print('^3[vice_hud]^7 /hudinteract — sample data. Arrows to move, Enter to pick, Esc to cancel.')
end, false)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    closeInteractMenuSilently()
end)
end -- close the do opened above
