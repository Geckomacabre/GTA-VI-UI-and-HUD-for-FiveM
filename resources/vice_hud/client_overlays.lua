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
-- /hudcrosshair, /hudkillmark — preview without needing a real fight
-- =============================================================================
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
-- and just tell this what to show. Simplification: fixed screen position,
-- not truly world-anchored — see the comment on #world-actions in
-- index.html for why.
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
    for i = 1, #str do
        local b = str:byte(i)
        if b < 0x20 or b > 0x7E then return '•' end
    end
    return str
end

local function waResolveKey(key)
    if type(key) == 'string' then return key end
    if type(key) ~= 'number' then return nil end
    local ok, raw = pcall(GetControlInstructionalButton, 0, key, true)
    if not ok or not raw then return nil end
    return waSafeLabel(raw:sub(3))
end

local function waUsingPad() return not IsInputDisabled(2) end

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

--- options: array of { label, key } -- key is a native GTA control ID
--- (see PAD::IS_CONTROL_PRESSED's `action` param) or an ox_lib keybind's
--- own `.hash` field, exactly as ShowActionPrompt's `key` already works.
exports('ShowWorldActions', function(options)
    waOptions = options or {}
    local resolved, device = waResolveAll()
    waDevice = device
    ui('worldActions', { show = true, options = resolved })
end)
exports('HideWorldActions', function()
    waOptions = nil
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
do
local interactOpen = false
local interactHeldFocus = false
-- Mirrors what the NUI page is actually showing, so a controller Accept/
-- Cancel press (polled natively, further down) always confirms whatever is
-- really highlighted — kept in sync by app.js's moveInteractSel() posting
-- 'interactMove' on every keyboard nudge too, so mixing keyboard and
-- controller input on the same open menu can't leave this pointing at a
-- stale row.
local interactOptionsCache = {}
local interactSelCache = 0

local function closeInteractMenuInternal()
    interactOpen = false
    if interactHeldFocus then
        interactHeldFocus = false
        SetNuiFocus(false, false)
        -- SetNuiFocusKeepInput is what lets the controller poller further
        -- down keep reading IsControlJustPressed while this menu still has
        -- the mouse cursor — without it, granting cursor focus above would
        -- swallow controller input the same way it swallows mouse look.
        SetNuiFocusKeepInput(false)
    end
end

--- options: array of { label, badges: {'stamina'|'focus', ...}, selected }
--- selected (top-level, optional, 0-based): which row starts highlighted;
--- defaults to whichever option has selected=true, or the first one.
exports('OpenInteractMenu', function(options, selected)
    interactOpen = true
    interactHeldFocus = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    interactOptionsCache = options or {}
    interactSelCache = selected
    if interactSelCache == nil then
        interactSelCache = 0
        for i, o in ipairs(interactOptionsCache) do
            if o.selected then interactSelCache = i - 1 break end
        end
    end
    ui('interact', { show = true, options = interactOptionsCache, selected = interactSelCache })
end)

RegisterNUICallback('interactMove', function(data, cb)
    if data and type(data.index) == 'number' then interactSelCache = data.index end
    cb(1)
end)

exports('CloseInteractMenu', function()
    closeInteractMenuInternal()
    ui('interact', { show = false })
end)

RegisterNUICallback('interactSelect', function(data, cb)
    closeInteractMenuInternal()
    ui('interact', { show = false })
    -- The caller is expected to be listening for this — OpenInteractMenu
    -- hands back control here rather than taking an onSelect callback
    -- directly, so the export stays plain data in and a plain event out.
    TriggerEvent('vice_hud:interactSelect', data and data.index)
    cb(1)
end)

RegisterNUICallback('interactClose', function(_, cb)
    closeInteractMenuInternal()
    TriggerEvent('vice_hud:interactClose')
    cb(1)
end)

-- /hudfocus already broadcasts this to clear every focus-holding panel in
-- the resource, not just the editor — the interact menu is another one.
AddEventHandler('vice_hud:releaseFocus', function()
    closeInteractMenuInternal()
    ui('interact', { show = false })
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

AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    interactOpen, interactHeldFocus = false, false
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if interactHeldFocus then
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
    end
end)

CreateThread(function()
    while true do
        Wait(500)
        if not interactOpen and IsNuiFocused() and interactHeldFocus then
            interactHeldFocus = false
            SetNuiFocus(false, false)
            SetNuiFocusKeepInput(false)
            print('^3[vice_hud]^7 released stranded NUI focus (the interact menu was not open)')
        end
    end
end)

-- =============================================================================
-- Controller (and keyboard-equivalent) input for the interact menu
-- =============================================================================
-- GTA's own FRONTEND_* controls carry BOTH a keyboard and a controller
-- default already (docs.fivem.net/docs/game-references/controls), and
-- Rockstar scoped them specifically so they don't fight movement/jump/
-- attack/aim during normal play. This server already leans on the same
-- 201/202 pair (ACCEPT/CANCEL) for exactly this "confirm/cancel a context
-- menu" purpose in several other resources (um_spawn, rcore_spray, and
-- others), so none of this is a fresh convention:
--
--   D-pad Up/Down / Arrows     (188 / 187)                 move the highlighted row
--   A / Enter                  (201, FRONTEND_ACCEPT)      confirm the highlighted interact row
--   B / Backspace,Esc          (202, FRONTEND_CANCEL)      back out without picking
--
-- The one REAL collision, and the reason for the disable block below:
-- INPUT_SELECT_WEAPON (control 37) is ALSO Tab/LB by default. ox_inventory's
-- own weapon/item wheel (the real one, now that vice_hud's own has been
-- retired) already disables this itself while its wheel is open, so this
-- only has to cover the interact menu, along with attack/aim, so nothing
-- double-fires off a shared button while it's up.

local function anyMenuOpen() return interactOpen end

CreateThread(function()
    while true do
        Wait(anyMenuOpen() and 0 or 200)
        if anyMenuOpen() then
            DisableControlAction(0, 37, true) -- INPUT_SELECT_WEAPON (Tab/LB) — see note above
            DisableControlAction(0, 24, true) -- INPUT_ATTACK
            DisableControlAction(0, 25, true) -- INPUT_AIM
            DisablePlayerFiring(PlayerId(), true)
        end
    end
end)

-- ---- interact menu: mirrors the keyboard nav already in app.js ---------
CreateThread(function()
    while true do
        Wait(interactOpen and 0 or 200)
        if interactOpen then
            local total = #interactOptionsCache
            if total > 0 then
                if IsControlJustPressed(0, 187) then -- Down
                    interactSelCache = (interactSelCache + 1) % total
                    ui('interact', { show = true, options = interactOptionsCache, selected = interactSelCache })
                end
                if IsControlJustPressed(0, 188) then -- Up
                    interactSelCache = (interactSelCache - 1 + total) % total
                    ui('interact', { show = true, options = interactOptionsCache, selected = interactSelCache })
                end
            end
            if IsControlJustPressed(0, 201) then -- Accept
                local idx = interactSelCache
                closeInteractMenuInternal()
                ui('interact', { show = false })
                TriggerEvent('vice_hud:interactSelect', idx)
            end
            if IsControlJustPressed(0, 202) then -- Cancel
                closeInteractMenuInternal()
                ui('interact', { show = false })
                TriggerEvent('vice_hud:interactClose')
            end
        end
    end
end)
end -- close the do opened above local interactOpen
