--[[ ===========================================================================
     vice_hud — client
     ---------------------------------------------------------------------------
     Gathers game state and pushes it to the NUI. Deliberately small: every
     numeric layout decision lives in the CSS, and every payload here is plain
     data, so a change to the look never requires touching this file.

     Public API (see README.md for detail):
         exports.vice_hud:ShowActionPrompt(id, label, key)
         exports.vice_hud:HideActionPrompt(id)
         exports.vice_hud:ShowHonorToast(mugshot, honor, emoji, reason)
         exports.vice_hud:ShowHonorChange(delta, mugshot)
         exports.vice_hud:SetHonorStanding(honor)   -- seed, draws nothing
         exports.vice_hud:ShowReputationToast(track, value, tier, reason)
         exports.vice_hud:SetReputationStanding(track, value, tier)  -- seed, draws nothing
         exports.vice_hud:SetHudVisible(visible)
         exports.vice_hud:SetHudOffsetX(pixels)
         exports.vice_hud:GetHudOffset(element)  -> x, y
     ========================================================================= ]]

local function ui(action, data)
    data = data or {}
    data.action = action
    SendNUIMessage(data)
end

-- =============================================================================
-- Focus mode — Franklin-style bullet time, toggled on the ARMOUR row.
-- -----------------------------------------------------------------------------
-- Deliberately timed off this thread's own Wait() calls rather than
-- GetGameTimer(): SetTimeScale slows the game clock down right along with the
-- world, so a duration counted in GetGameTimer() drifts the moment focus goes
-- active (fenix-police's arrest cinematic hit this and works around it the
-- same way). Wait() itself is real time regardless of SetTimeScale, so a
-- plain millisecond countdown driven by the loop's own tick stays correct.
-- =============================================================================

local focusMeter = 100.0
local focusActive = false
local focusRegenWaitMs = 0

local function rampTimeScale(from, to)
    local steps = Config.Focus.rampSteps
    for i = 1, steps do
        SetTimeScale(from + (to - from) * (i / steps))
        Wait(Config.Focus.rampStepMs)
    end
    SetTimeScale(to)
end

-- Grip boost while driving in Focus -- see Config.Focus.drivingGripBonus.
-- -----------------------------------------------------------------------------
-- _G.VicehudFocusActive is a plain global (all of this resource's client scripts
-- share one Lua state, so this needs no export) rather than a local, because
-- client_skills.lua's driving-skill handling boost ALSO writes
-- fTractionCurveMax/Min and fTractionLossMult on the driven vehicle, on its
-- own 200ms tick, straight from ITS OWN cached stock values -- a one-shot
-- write from here would just get silently overwritten within one tick.
-- client_skills.lua's drivingFactor() folds this flag into the same factor it
-- already reapplies continuously, so there is exactly one writer of those
-- fields whenever the skill system owns them.
_G.VicehudFocusActive = false

-- Fallback for when the skill system isn't the one writing those fields at
-- all (Config.Skills.enable or drivingAffectsHandling is false) -- in that
-- case nothing else ever touches vehicle handling, so a direct write here is
-- safe and Focus's driving assist still works without the skill system on.
local function skillsOwnDrivingHandling()
    local sk = Config.Skills
    return sk and sk.enable and sk.drivingAffectsHandling
end

local focusDrivingBase = nil
local focusDrivingVeh = nil

local function applyFocusDrivingBoost(veh)
    if focusDrivingBase then return end
    local okMax, curveMax = pcall(GetVehicleHandlingFloat, veh, 'CHandlingData', 'fTractionCurveMax')
    local okMin, curveMin = pcall(GetVehicleHandlingFloat, veh, 'CHandlingData', 'fTractionCurveMin')
    local okLoss, lossMult = pcall(GetVehicleHandlingFloat, veh, 'CHandlingData', 'fTractionLossMult')
    -- A read failure means this build's handling fields do not match --
    -- skip rather than write a value derived from a nil.
    if not (okMax and okMin and okLoss) then return end
    focusDrivingBase = { curveMax = curveMax, curveMin = curveMin, lossMult = lossMult }
    focusDrivingVeh = veh
    local bonus = Config.Focus.drivingGripBonus or 1.0
    pcall(SetVehicleHandlingFloat, veh, 'CHandlingData', 'fTractionCurveMax', curveMax * bonus)
    pcall(SetVehicleHandlingFloat, veh, 'CHandlingData', 'fTractionCurveMin', curveMin * bonus)
    pcall(SetVehicleHandlingFloat, veh, 'CHandlingData', 'fTractionLossMult', lossMult / bonus)
end

--- Put the boosted vehicle's traction back exactly as found. Must fire
--- before the vehicle changes hands (seat swap, player exits) so the boost
--- never becomes a free permanent upgrade for whoever drives it next.
local function restoreFocusDrivingBoost()
    local veh, base = focusDrivingVeh, focusDrivingBase
    focusDrivingVeh, focusDrivingBase = nil, nil
    if not (veh and base and DoesEntityExist(veh)) then return end
    pcall(SetVehicleHandlingFloat, veh, 'CHandlingData', 'fTractionCurveMax', base.curveMax)
    pcall(SetVehicleHandlingFloat, veh, 'CHandlingData', 'fTractionCurveMin', base.curveMin)
    pcall(SetVehicleHandlingFloat, veh, 'CHandlingData', 'fTractionLossMult', base.lossMult)
end

-- Tracks which vehicle (if any) currently carries the boost, polled only
-- while Focus is active -- Wait(100) is plenty for a seat/vehicle change to
-- be caught without costing anything the rest of the time.
CreateThread(function()
    while true do
        if focusActive then
            local ped = cache.ped or PlayerPedId()
            local veh = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or 0
            local isDriver = veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped
            _G.VicehudFocusActive = isDriver
            if not skillsOwnDrivingHandling() then
                if isDriver then
                    if veh ~= focusDrivingVeh then
                        restoreFocusDrivingBoost()
                        applyFocusDrivingBoost(veh)
                    end
                elseif focusDrivingVeh then
                    restoreFocusDrivingBoost()
                end
            end
            Wait(100)
        else
            _G.VicehudFocusActive = false
            Wait(200)
        end
    end
end)

local function exitFocus()
    if not focusActive then return end
    focusActive = false
    focusRegenWaitMs = Config.Focus.regenDelayMs
    -- Own animation rate reverts to normal immediately -- it's the ramp on
    -- SetTimeScale that needs to ease out, not this.
    SetPedMoveRateOverride(cache.ped or PlayerPedId(), 1.0)
    SetPedAccuracy(cache.ped or PlayerPedId(), Config.Focus.accuracyDefault)
    restoreFocusDrivingBoost()
    AnimpostfxStop('FocusIn')
    AnimpostfxPlay('FocusOut', 0, false)
    CreateThread(function() rampTimeScale(Config.Focus.timeScale, 1.0) end)
end

local function toggleFocus()
    if focusActive then
        exitFocus()
        return
    end
    if focusMeter < Config.Focus.minToActivate then return end
    focusActive = true
    SetPedAccuracy(cache.ped or PlayerPedId(), Config.Focus.accuracyBoost)
    AnimpostfxPlay('FocusIn', 0, true)
    CreateThread(function() rampTimeScale(1.0, Config.Focus.timeScale) end)
end

-- SET_PED_MOVE_RATE_OVERRIDE resets itself if it isn't reapplied every
-- frame, so the player's own movement/aim animations keep playing back at
-- roughly their normal apparent speed while SetTimeScale slows everything
-- else -- the actual "world slows, you don't" illusion Franklin's ability
-- relies on. Split into its own per-frame thread rather than folded into the
-- 50ms meter thread below, since this one genuinely needs Wait(0).
--
-- SET_PED_ACCURACY rides along in the same thread: it does not reset itself
-- every frame the way the move rate override does, but a ped swap mid-Focus
-- (death and respawn) would otherwise leave the fresh ped at default
-- accuracy for the rest of the activation -- reapplying alongside cache.ped
-- costs nothing and closes that gap the same way toggleFocus's one-shot
-- call cannot.
CreateThread(function()
    while true do
        if focusActive then
            local ped = cache.ped or PlayerPedId()
            SetPedMoveRateOverride(ped, 1.0 / Config.Focus.timeScale)
            SetPedAccuracy(ped, Config.Focus.accuracyBoost)
            Wait(0)
        else
            Wait(200)
        end
    end
end)

-- Bound as a controller chord (L3 + R3 together) rather than one key: each
-- stick click is its own FiveM keymapping (so both stay independently
-- remappable in Settings > Key Bindings > FiveM), and the toggle only fires
-- on the transition into "both currently held". A lone L3 or R3 press does
-- nothing, so this sits alongside GTA's own L3 (duck) and R3 (look
-- behind/cinematic slowmo) without ever firing by itself.
local focusL3Held, focusR3Held = false, false

local function checkFocusChord()
    if focusL3Held and focusR3Held then
        toggleFocus()
    end
end

lib.addKeybind({
    name = 'vicehud_focus_l3',
    description = 'Focus mode (hold together with R3)',
    defaultMapper = 'PAD_DIGITALBUTTON',
    defaultKey = 'L3_INDEX',
    onPressed = function() focusL3Held = true; checkFocusChord() end,
    onReleased = function() focusL3Held = false end,
})

lib.addKeybind({
    name = 'vicehud_focus_r3',
    description = 'Focus mode (hold together with L3)',
    defaultMapper = 'PAD_DIGITALBUTTON',
    defaultKey = 'R3_INDEX',
    onPressed = function() focusR3Held = true; checkFocusChord() end,
    onReleased = function() focusR3Held = false end,
})

-- Keyboard gets a single plain toggle -- there's no horn-style default
-- riding on any keyboard key the way there is on the controller's L3, so a
-- chord buys nothing there and just makes it slower to press.
lib.addKeybind({
    name = 'vicehud_focus_key',
    description = 'Toggle Focus (slow-mo)',
    defaultMapper = 'keyboard',
    defaultKey = 'B',
    onPressed = toggleFocus,
})

-- L3's default control is the horn (INPUT_VEH_HORN, control 86) in a
-- vehicle. Holding L3 alone must keep honking as normal -- only once R3
-- joins it (attempting or holding the chord) do we swallow the horn input,
-- so a solo L3 press is untouched but the chord doesn't blast the horn for
-- as long as both sticks (or L3 alone, mid-focus) stay down.
CreateThread(function()
    while true do
        if focusL3Held and (focusR3Held or focusActive) then
            DisableControlAction(0, 86, true)
            Wait(0)
        else
            Wait(200)
        end
    end
end)

-- 50ms tick: fine enough for a smooth-looking drain/refill, coarse enough
-- to not matter next to the 250ms status poll that actually reads focusMeter.
CreateThread(function()
    while true do
        Wait(50)
        if focusActive then
            focusMeter = math.max(0, focusMeter - (50 / (Config.Focus.drainSeconds * 1000)) * 100)
            if focusMeter <= 0 then
                focusMeter = 0
                exitFocus()
            end
        elseif focusMeter < 100 then
            if focusRegenWaitMs > 0 then
                focusRegenWaitMs = math.max(0, focusRegenWaitMs - 50)
            else
                focusMeter = math.min(100, focusMeter + (50 / (Config.Focus.refillSeconds * 1000)) * 100)
            end
        end
    end
end)

-- A resource restart mid-focus must not leave the player permanently in
-- slow motion — there is no ramp-out thread left alive to fix it once this
-- resource is gone.
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() and focusActive then
        SetTimeScale(1.0)
        SetPedMoveRateOverride(cache.ped or PlayerPedId(), 1.0)
        SetPedAccuracy(cache.ped or PlayerPedId(), Config.Focus.accuracyDefault)
        restoreFocusDrivingBoost()
        AnimpostfxStop('FocusIn')
    end
end)

-- =============================================================================
-- Minimap placement + publishing its rect to the NUI
-- =============================================================================

-- Screen-space pixel nudge for the native map. INTEGER by construction.
--
-- Lua 5.4's string.format('%d') throws "number has no integer representation"
-- on a float, and the editor accumulates this in steps of 0.1 * 8 = 0.8, so it
-- was never whole. That crashed /mapinfo. Rounding at every write keeps a pixel
-- offset an actual pixel offset and makes every %d downstream safe.
local function px(v)
    v = tonumber(v) or 0
    return math.floor(v + 0.5)
end

local mapDx, mapDy = 0, 0

-- Last rect published to the NUI, so an unchanged one is not re-sent.
local lastRectKey = nil

-- Crosshair on the centre of the published map rect. A measuring tool for
-- working out where the player blip actually sits relative to the map.
local showMapCross = false

-- Draw the three ENGINE component rects over the screen. /hudrects.
--
-- Added because the same question came up three times and was answered by
-- guesswork each time: a radius blip renders as a hard-edged RECTANGLE on the
-- minimap while the pause map draws it as a proper circle, which means some
-- clip region is not where the visible map is. `minimap`, `minimap_mask` and
-- `minimap_blur` are the only three rects this resource hands the engine, so
-- outlining all three against the drawn map says which one the overlay is
-- actually clipping to. That is a measurement; everything before it was a
-- hypothesis.
local showMapRects = false
local rectsWereShown = false

-- Publish a HAND-MEASURED rect instead of a derived one.
--
-- The derived rect converts safe-zone component units into screen percentages,
-- and that conversion is wrong: /hudcross puts the crosshair off the centre of
-- the drawn map, which is the proof. The relationship is not something that can
-- be worked out from outside the game -- several attempts were wrong -- so the
-- rect is measurable by hand instead. /hudslot moves it, /hudcross and
-- /hudframe show where it currently sits, and /hudexport reports it.
--
-- nil = derive it as before.
local manualRect = nil

-- Forward-declared so /hudtest (registered above the vehicle section) closes
-- over the real upvalue rather than a nil global.
local veh = { make = '', model = '', lock = 'unknown', fuel = 0, engine = false, health = 1000 }

-- Forward-declared for the same reason. Defined down in the /movehud section,
-- next to the caches it clears. /hudtest needs it too: the sample payloads it
-- pushes bypass the poll loop's change caches, so without a reset the fake
-- wanted level / vehicle panel / zone label sit on screen forever.
local resetPushCaches

-- Whether the /movehud editor is up, and whether WE are the ones holding NUI
-- focus. Declared HERE rather than beside the command, because the main poll
-- loop -- which is defined above it -- has to know: the minimap is hidden on
-- foot for anyone who prefers it that way, and hiding the map while the tool
-- for positioning the map is open leaves you tuning a black rectangle.
local editorOpen  = false
local weHoldFocus = false

-- GetGameTimer() deadline for the transient make/model panel; 0 = not showing.
local panelUntil = 0

-- Whether the vehicle panel (full plate OR the collapsed pips) is currently up.
-- Separate from panelUntil, which only ever means "the announcement window is
-- still open" -- it latches to 0 mid-drive while the pips are still drawn, so it
-- cannot be used to decide whether there is anything left to hide on exit.
local vehShown = false

-- Which radar-mask dictionary is currently stamped over GTA's, or nil.
--
-- Seeded from a KVP because the swap outlives the resource: if vice_hud applied
-- a mask and was then restarted, the replacement is still on the game's texture
-- and we are the only ones who know to remove it. The KVP stores the DICT NAME,
-- not just a yes/no, because with a family of masks "a mask is applied" is no
-- longer enough to know which one to take back off.
local maskAppliedDict = GetResourceKvpString('vice_hud:maskDict')
if not maskAppliedDict and GetResourceKvpString('vice_hud:maskApplied') == 'yes' then
    -- Upgrade from the old yes/no key, which only ever meant the single
    -- pre-family texture.
    maskAppliedDict = 'vice_minimap'
    DeleteResourceKvp('vice_hud:maskApplied')
end
local maskApplied = maskAppliedDict ~= nil

-- True while a swap is in flight.
--
-- applyMinimap is re-run by a watchdog twice a second, and both halves of a
-- swap Wait: removeMask rebuilds the scaleform, and applyMask can spend up to
-- four seconds waiting for a dictionary to stream. Without this guard the
-- watchdog re-enters during those Waits, sees a half-finished state and starts
-- a SECOND swap racing the first.
local maskBusy = false

-- Corner radius of the minimap mask, as a PERCENTAGE OF THE MASK'S HEIGHT.
--
-- This cannot be a continuous value. The rounding lives in the mask TEXTURE,
-- and the engine cannot build a texture at runtime, so the radius is a set of
-- pre-baked masks in stream/ and changing it swaps which one is replacing
-- `radarmasksm`. Regenerate them with `python tools/make_masks.py`; MASK_STEPS
-- must match that script's STEPS.
--
-- Anything set between steps snaps to the nearest one, so config.lua and
-- /movehud can both hand over a plain number without knowing the list.
local MASK_STEPS = { 0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 50 }

local function snapMaskRadius(v)
    v = tonumber(v) or 0
    local best, bestd = MASK_STEPS[1], math.huge
    for i = 1, #MASK_STEPS do
        local d = math.abs(MASK_STEPS[i] - v)
        -- `<=`, not `<`: a tie takes the HIGHER step. The list is not evenly
        -- spaced at the top (…44, 48, 50), so 50 minus the editor's step of 4
        -- is 46, exactly between 44 and 48 — with `<` that skipped 48 and the
        -- minus button appeared to jump two steps.
        if d <= bestd then best, bestd = MASK_STEPS[i], d end
    end
    return best
end

local maskRadius = snapMaskRadius(Config.MinimapCornerRadius or 8)

--- Texture dictionary holding the mask for the current radius.
local function maskDictFor(radius)
    return ('vice_mask_%02d'):format(snapMaskRadius(radius))
end

-- Handle for the 'minimap' scaleform, used to hide the native health/armour bars.
local minimapScaleform = nil

-- Live multipliers on Config.MinimapComponent, driven by /hudmap so the map can
-- be sized against the reference without a restart per attempt.
local mapScaleW, mapScaleH = Config.MinimapScale or 1.0, Config.MinimapScale or 1.0

-- The native map's nudge/size values live outside `layout` (the engine owns the
-- map, so there is no CSS offset to store), and used to be lost on every
-- restart — you would size the map in /movehud, save, and find it back at the
-- config values next session. Persist them alongside the layout KVP.
local KVP_MAP = 'vice_hud:map'

-- Bumped whenever the saved values stop meaning what they meant. A layout tuned
-- against the old geometry is discarded rather than re-applied to geometry it
-- was never measured against — otherwise a player who had ever nudged the map
-- keeps their old size forever and a config fix never reaches them.
--   2  mask and blur became relative to the map (they used to be absolute)
--   3  component reshaped to the mask's 2:1 aspect; maskMode defaults to 'full'
--   4  reverted to qbx_hud's square-map values; maskMode renamed to config/map
--   5  maskMode defaults to 'map' so the player blip is centred
--
-- NOT bumped for the mask corner radius (`rad`) either, for the same reason.
--
-- NOT bumped for the /hudblip mask deltas: ADDING an optional field does not
-- invalidate anything, because loadMapState defaults a missing one to 0. The
-- rule is "bump when a saved value stops meaning what it meant, or when a
-- DEFAULT moves" — bumping for a new field just throws away a player's tuning
-- for no reason.
--   6  component OFFSETS are scaled along with their sizes. Before this, only
--      w/h were multiplied by mapScaleW/H while x/y stayed absolute, so any
--      map that had been resized had its plane displaced inside its own mask —
--      which is what put the player arrow off centre, and put it further off
--      the smaller the map got. Every blip/mask nudge saved under the old
--      behaviour was measured against that displacement and is meaningless
--      without it.
local MAP_STATE_VERSION = 6

-- 'config' = the mask component values from config.lua, which are qbx_hud's.
-- 'map'    = mask laid exactly over the map component, for a texture that wants
--            that instead. Not what we ship, kept switchable and remembered.
local maskMode = 'map'

-- Live adjustment of the `minimap` COMPONENT, in safe-zone units. This is the
-- knob that moves the player blip inside the visible map.
--
-- It has to be this component and not the mask. qbx_hud's own source says so:
--     -- 0.0    = nav symbol and icons left
--     -- 0.1638 = nav symbol and icons stretched
--     SetMinimapComponentPosition('minimap', ...)
-- `minimap` positions the nav symbol and blips; `minimap_mask` is the window
-- you look through. An earlier version of this pointed the knob at the mask,
-- which did nothing at all in maskMode 'map' — there the mask MIRRORS the map,
-- so moving it moved the window and its contents together and cancelled out.
--
-- Deliberately a knob rather than a computed value: where the engine puts the
-- blip is not derivable from outside the game, and two attempts to model it
-- were wrong in opposite directions. Tune by eye, then bake the number in.
local blipDx, blipDy = 0.0, 0.0
local blipDw, blipDh = 0.0, 0.0

-- Does the blur component FOLLOW the map plane, or keep its own config rect?
--
-- Exactly the same idea as maskMode, which the mask has had all along, and the
-- absence of it here is what made the map so hard to tune. The drawn extent of
-- the minimap turns out to be the blur rect, while the player arrow and every
-- radius blip are drawn on the PLANE. Let those two be different rects and the
-- arrow sits off-centre and radius blips stop at an invisible edge.
--
-- 'plane' recomputes the blur from the plane on every apply, so it TRACKS: a
-- later change to Map width or Map height cannot pull them apart again.
-- /hudmatch blur does the same sum once, in absolute units, and drifts the next
-- time anything is resized -- which is why this is the default and that is the
-- manual fallback.
local blurMode = 'plane'

-- The BLUR component's own deltas.
--
-- `minimap_blur` had no adjustment and no editor row at all, which made it the
-- one component you could not touch — and on this config it is 1.6x the size of
-- the map component (blurW 0.262 vs w 0.1638), a ratio that survives every
-- scale because all three are multiplied together. When the drawn map turns out
-- to fill the BLUR rect while blips clip to the MAP rect, that gap is the whole
-- bug and there was no way to close it from inside the tool.
local blurDx, blurDy = 0.0, 0.0
local blurDw, blurDh = 0.0, 0.0

-- The north marker on the minimap's edge. VANILLA SHOWS IT.
--
-- This resource used to hide it unconditionally, with no setting and no note
-- saying why -- so "the north icon is missing" had no answer anywhere in the
-- config. It is vanilla information about the map, not a HUD element vice_hud
-- draws a replacement for, so the default is now to leave it alone.
local northBlip = true

-- Scale for the player's own blip (the white arrow). 0 = leave GTA's alone.
--
-- Worth its own control because the arrow does NOT scale with the map: shrink
-- the minimap components and the arrow keeps its absolute size, so a map at
-- 0.76 scale gets an arrow that reads proportionally larger, and a map scaled
-- up gets one that reads too small. Nothing else in here could correct that.
local playerBlipScale = 0.0

-- Radar zoom. 0 = do not touch it; GTA's own zoom stands.
--
-- Worth having because of what it is NOT. GTA draws the radar as a tilted
-- three-dimensional plane -- that perspective is in the engine's radar
-- renderer, and there is no native in this resource's reach that flattens it.
-- What zoom does is change how MUCH of that plane you are looking at: pulled
-- in, you see the well-behaved middle and the map reads flat; pulled out, you
-- see the steeply-angled far edge and it reads skewed. Together with the crop
-- rows and mask mode 'config', that is the whole of the "make it look 2D"
-- toolkit, and it is honest about being a mitigation rather than a switch.
local radarZoom = 0.0

-- The same idea for the mask, so the two can be moved independently and
-- whichever one actually shifts the arrow can be identified by eye.
local maskNudgeX, maskNudgeY = 0.0, 0.0

-- How much to CROP off each side of the visible window, in safe-zone units.
--
-- GTA draws the radar as a tilted 3D plane inside the `minimap` component, and
-- the plane does not fill it: there is dead space past the far edge, which
-- shows up as a flat dark band along the top of the map. Vanilla never shows it
-- because the stock mask texture has padding that hides it. Ours is full-bleed
-- (its shape covers 98.6% x 97.3% of the image), so it reveals the whole
-- component, band included.
--
-- Cropping the mask is the fix, and the amount depends on the tilt, which is
-- not something that can be worked out from here. So it is a knob: /hudcrop.
local cropT, cropB, cropL, cropR = 0.0, 0.0, 0.0, 0.0

-- Live override for SetMinimapClipType, set by /hudclip. nil = use the config
-- value. Held here rather than applied directly because the watchdog thread
-- re-runs applyMinimap twice a second and would otherwise undo the command.
local clipOverride = nil

--- Every value that decides the native map's geometry, as a plain table.
---
--- Split out of saveMapState because the same table is what /hudpublish sends
--- to the server: a map that is the wrong size is exactly the kind of thing you
--- want to fix once for everyone rather than per player.
local function mapStateTable()
    local capw, caph = GetActiveScreenResolution()
    return {
        v = MAP_STATE_VERSION,
        dx = mapDx, dy = mapDy, sw = mapScaleW, sh = mapScaleH, mask = maskMode,
        -- Resolution this dx/dy was tuned at. mapDx/mapDy are screen-space
        -- PIXELS (see the comment on their declaration), not a fraction of the
        -- screen, so the same saved number is the wrong nudge on a different
        -- resolution even at the same aspect ratio — a 40px nudge tuned at
        -- 1920 wide is only half as much of the screen at 3840 wide. Recorded
        -- so applyMapState can rescale it to whatever width the player is
        -- actually running now.
        capw = capw, caph = caph,
        rad = maskRadius,
        bdx = blipDx, bdy = blipDy, bdw = blipDw, bdh = blipDh,
        ubx = blurDx, uby = blurDy, ubw = blurDw, ubh = blurDh,
        north = northBlip, bscale = playerBlipScale, blurmode = blurMode,
        mnx = maskNudgeX, mny = maskNudgeY,
        rect = manualRect,
        crop = { t = cropT, b = cropB, l = cropL, r = cropR },
        zoom = radarZoom,
    }
end

local function saveMapState()
    local ok, enc = pcall(json.encode, mapStateTable())
    if ok then SetResourceKvp(KVP_MAP, enc) end
end

--- Apply a decoded map state. Shared by the KVP loader and by the server-wide
--- layout, so both paths land on exactly the same geometry.
local function applyMapState(d)
    if type(d) ~= 'table' then return false end
    if tonumber(d.v) ~= MAP_STATE_VERSION then return false end
    local dx, dy = tonumber(d.dx) or 0, tonumber(d.dy) or 0
    local capw, caph = tonumber(d.capw), tonumber(d.caph)
    if capw and capw > 0 and caph and caph > 0 then
        -- Rescale the pixel nudge to THIS resolution rather than replaying the
        -- raw number from whatever resolution it was tuned/published at — see
        -- the comment on mapStateTable's capw/caph. Missing on a state saved
        -- before this existed, so old saves fall through unscaled exactly as
        -- they always have.
        local rx, ry = GetActiveScreenResolution()
        if rx > 0 and ry > 0 then
            dx = dx * (rx / capw)
            dy = dy * (ry / caph)
        end
    end
    mapDx = px(dx)
    mapDy = px(dy)
    mapScaleW = tonumber(d.sw) or Config.MinimapScale or 1.0
    mapScaleH = tonumber(d.sh) or Config.MinimapScale or 1.0
    if d.mask == 'config' or d.mask == 'map' then maskMode = d.mask end
    -- Missing on a state saved before the radius existed; the config default
    -- then stands, which is the same shape those players already had.
    if d.rad ~= nil then maskRadius = snapMaskRadius(d.rad) end
    blipDx = tonumber(d.bdx) or 0.0
    blipDy = tonumber(d.bdy) or 0.0
    blipDw = tonumber(d.bdw) or 0.0
    blipDh = tonumber(d.bdh) or 0.0
    blurDx = tonumber(d.ubx) or 0.0
    blurDy = tonumber(d.uby) or 0.0
    blurDw = tonumber(d.ubw) or 0.0
    blurDh = tonumber(d.ubh) or 0.0
    -- `~= false` rather than `or true`: a stored `false` has to survive, and
    -- `false or true` is true.
    if d.north ~= nil then northBlip = d.north ~= false end
    playerBlipScale = tonumber(d.bscale) or 0.0
    if d.blurmode == 'plane' or d.blurmode == 'config' then
        blurMode = d.blurmode
    elseif blurDx ~= 0.0 or blurDy ~= 0.0 or blurDw ~= 0.0 or blurDh ~= 0.0 then
        -- A state saved before this setting existed, carrying hand-tuned blur
        -- deltas — almost certainly from /hudmatch blur, which was the only way
        -- to line the blur up back then. Those deltas were measured against the
        -- CONFIG rect, so honour that rather than adding them on top of a
        -- plane-following blur and double-correcting a map that already works.
        blurMode = 'config'
    end
    maskNudgeX = tonumber(d.mnx) or 0.0
    maskNudgeY = tonumber(d.mny) or 0.0
    radarZoom = tonumber(d.zoom) or 0.0
    if type(d.crop) == 'table' then
        cropT = tonumber(d.crop.t) or 0.0
        cropB = tonumber(d.crop.b) or 0.0
        cropL = tonumber(d.crop.l) or 0.0
        cropR = tonumber(d.crop.r) or 0.0
    end
    if type(d.rect) == 'table' and tonumber(d.rect.width) then
        manualRect = {
            left   = tonumber(d.rect.left)   or 0.0,
            width  = tonumber(d.rect.width)  or 10.0,
            bottom = tonumber(d.rect.bottom) or 10.0,
            height = tonumber(d.rect.height) or 10.0,
        }
        Config.Minimap.left   = manualRect.left
        Config.Minimap.width  = manualRect.width
        Config.Minimap.bottom = manualRect.bottom
        Config.Minimap.height = manualRect.height
    end
    return true
end

--- Did this player ever tune the map themselves? Read before the KVP is
--- applied, because "has a personal map" is what decides whether the
--- server-wide one is allowed to overwrite it.
local hasPersonalMap = GetResourceKvpString(KVP_MAP) ~= nil

local function loadMapState()
    local raw = GetResourceKvpString(KVP_MAP)
    if not raw then return end
    local ok, d = pcall(json.decode, raw)
    if not ok or type(d) ~= 'table' then return end
    if not applyMapState(d) then
        DeleteResourceKvp(KVP_MAP)
        hasPersonalMap = false
        print('^3[vice_hud]^7 discarded a saved minimap layout from an older '
            .. 'version — the map is back at the config values.')
    end
end

-- Rebuilding the minimap means flicking the BIGMAP on and straight back off,
-- which is the only way to make SetMinimapComponentPosition take effect. That
-- leaves a window where the map is stuck in its big translucent unmasked state
-- if anything goes wrong in between — an error, or two rebuilds interleaving,
-- both of which have happened here.
--
-- One helper, guarded so rebuilds cannot overlap, and the "off" is in a
-- finaliser so it runs even if the enable errors.
local rebuilding = false

local function rebuildMinimap()
    if rebuilding then return end
    rebuilding = true
    local ok, err = pcall(function()
        SetRadarBigmapEnabled(true, false)
        Wait(0)
    end)
    -- Always restore, whatever happened above.
    SetRadarBigmapEnabled(false, false)
    rebuilding = false
    if not ok then
        print(('^1[vice_hud]^7 minimap rebuild failed: %s'):format(tostring(err)))
    end
end

-- Belt and braces: if the map is somehow left in bigmap while we are not
-- rebuilding, put it back. Cheap, and it turns a stuck map into a 1s blip
-- rather than something that needs a restart to notice.
CreateThread(function()
    while true do
        Wait(1000)
        if not rebuilding and IsBigmapActive() then
            SetRadarBigmapEnabled(false, false)
        end
    end
end)

-- Swaps GTA's square radar mask for the rounded one in stream/vice_minimap.ytd.
--
-- Streaming a dictionary is not instant, and the previous version bailed
-- silently on the first miss — which is almost certainly why the corners never
-- appeared. This retries, then reports what happened so a failure is visible
-- instead of looking like "the mask just doesn't work".
--- Stream `dict` and stamp its radarmasksm over GTA's. Returns true on success.
local function tryApplyDict(dict)
    for attempt = 1, 40 do                      -- ~4s at 100ms
        if not HasStreamedTextureDictLoaded(dict) then
            RequestStreamedTextureDict(dict, false)
        end
        if HasStreamedTextureDictLoaded(dict) then
            AddReplaceTexture('platform:/textures/graphics', 'radarmasksm', dict, 'radarmasksm')
            AddReplaceTexture('platform:/textures/graphics', 'radarmask1g', dict, 'radarmasksm')
            maskAppliedDict = dict
            SetResourceKvp('vice_hud:maskDict', dict)
            -- Clip type is NOT set here. It is owned by applyMinimap, which the
            -- watchdog re-runs twice a second — setting it here just meant the
            -- two fought, and clip type 1 would force a CIRCLE and throw away
            -- the rounded-rectangle shape the mask texture defines.
            -- Force the minimap to rebuild so the swapped mask actually takes.
            rebuildMinimap()
            print(('^2[vice_hud]^7 minimap mask applied (dict "%s", attempt %d)'):format(dict, attempt))
            return true
        end
        Wait(100)
    end
    return false
end

local function applyMask()
    local want = maskDictFor(maskRadius)

    -- Print immediately. If you run /hudmask and see NOTHING at all, the command
    -- never fired (script failed to load) — which is a different problem from
    -- the mask failing to apply, and worth telling apart.
    print(('^3[vice_hud]^7 applyMask: requesting texture dict "%s" (corner radius %d%%)...')
        :format(want, maskRadius))

    if tryApplyDict(want) then return true end

    -- The radius family is generated; the single pre-family texture is not, and
    -- is still shipped. Falling back to it means a missing or unbuilt step
    -- degrades to "rounded, wrong radius" instead of "square, looks broken".
    print(('^3[vice_hud]^7 dict "%s" never streamed in — falling back to "vice_minimap".'):format(want))
    if tryApplyDict('vice_minimap') then return true end

    maskApplied = false
    maskAppliedDict = nil
    DeleteResourceKvp('vice_hud:maskDict')
    print('^1[vice_hud]^7 minimap mask FAILED: no mask dictionary would stream in.')
    print(('  Expected stream/%s.ytd, texture inside named radarmasksm.'):format(want))
    print('  Rebuild the family with:  python tools/make_masks.py')
    return false
end

-- Undo the mask swap.
--
-- AddReplaceTexture is NOT scoped to the resource: restarting vice_hud leaves
-- the replacement stamped over GTA's mask for the rest of the game session.
-- That is why "vice_hud isn't touching the map any more" still showed a broken
-- map — stock component positions wearing a custom mask, which is worse than
-- either on its own. The replacement has to be removed explicitly.
local function removeMask()
    RemoveReplaceTexture('platform:/textures/graphics', 'radarmasksm')
    RemoveReplaceTexture('platform:/textures/graphics', 'radarmask1g')
    maskApplied = false
    maskAppliedDict = nil
    DeleteResourceKvp('vice_hud:maskDict')
    DeleteResourceKvp('vice_hud:maskApplied')
    -- Rebuild, or the scaleform keeps drawing the old mask.
    rebuildMinimap()
    print('^2[vice_hud]^7 minimap mask replacement removed — the stock mask is back.')
end

-- Both of these move Config.MinimapMask, not just the texture. applyMinimap
-- reconciles the flag against the live swap on every pass, so setting one
-- without the other meant the watchdog thread undid the command within 500ms.
RegisterCommand('hudmaskoff', function()
    Config.MinimapMask = false
    if maskBusy then return print('^3[vice_hud]^7 a mask swap is already in flight — try again in a moment.') end
    maskBusy = true
    CreateThread(function() removeMask() maskBusy = false end)
end, false)

-- Re-apply on demand, for testing without a restart.
--
-- Goes off and back on rather than straight on: AddReplaceTexture does not
-- stack, so re-applying over a live replacement would keep drawing the old
-- texture and make the command look like it did nothing.
--
-- Both commands honour maskBusy for the same reason applyMinimap does — the
-- watchdog is still running underneath and both halves of a swap Wait.
RegisterCommand('hudmask', function()
    Config.MinimapMask = true
    if maskBusy then return print('^3[vice_hud]^7 a mask swap is already in flight — try again in a moment.') end
    maskBusy = true
    CreateThread(function()
        if maskApplied then removeMask() end
        maskApplied = true
        applyMask()
        maskBusy = false
    end)
end, false)

--- Put GTA's minimap components back to their shipped values.
---
--- SetMinimapComponentPosition writes into the engine's own component table and
--- stays there for the whole game session, exactly like AddReplaceTexture.
--- Declining to call it leaves the LAST values vice_hud wrote in place — which
--- is why "vice_hud isn't touching the map" still drew a broken map, and why
--- removing the mask on top of stale geometry left a blank rectangle. There is
--- no engine call for "put it back", so the stock values are written explicitly.
local function restoreStockMinimap()
    SetMinimapComponentPosition('minimap',      'L', 'B',  0.0,   0.0, 0.1638, 0.183)
    SetMinimapComponentPosition('minimap_mask', 'L', 'B',  0.0,   0.0, 0.128,  0.20)
    SetMinimapComponentPosition('minimap_blur', 'L', 'B', -0.01,  0.0, 0.276,  0.300)
    SetMinimapClipType(0)
    SetBlipAlpha(GetNorthRadarBlip(), 255)
end

local function applyMinimap(rebuild)
    local rx, ry = GetActiveScreenResolution()
    if rx <= 0 then rx = 1920 end
    if ry <= 0 then ry = 1080 end

    -- Hands off the native map entirely when asked. Everything below this point
    -- repositions GTA's minimap components; skipping it leaves the stock map
    -- exactly as the engine drew it. The rect publish at the end still runs, so
    -- the NUI panels keep following the map.
    local untouched = Config.NativeMinimap == true

    -- Ultrawide correction. Credit to Dalrae, via qbx_hud.
    --
    -- This used to be deliberately OMITTED, on the reasoning that the NUI panels
    -- were anchored to a centred 16:9 stage and the map should stay at the
    -- safe-zone edge to match them. That reasoning was wrong: `.stage` is
    -- `width: 100vw` (style.css), so the panels sit at 1.75% of the PHYSICAL
    -- screen, while the safe-zone-anchored map lands ~10% in on a 21:9 display.
    -- That gap is the misalignment, and no amount of nudging fixed it because
    -- it scales with how wide the monitor is.
    local DEFAULT_ASPECT = 1920.0 / 1080.0
    local aspect = rx / ry
    local uwOffset = 0.0
    if aspect > DEFAULT_ASPECT then
        uwOffset = ((DEFAULT_ASPECT - aspect) / 3.6) - 0.008
    end

    -- fdx moves the ENGINE components; uiDx moves the NUI panels, and it
    -- deliberately leaves uwOffset out.
    --
    -- uwOffset's whole job is to cancel the extra inset GTA applies on a
    -- wider-than-16:9 screen, putting the map back at the same PHYSICAL place a
    -- 16:9 screen would draw it. So in physical-screen terms it contributes
    -- nothing, and folding it into the NUI rect double-counted it: on 3440x1440
    -- the zone bar and vehicle panel were told to sit at left = -17.8%, i.e.
    -- 612px off the left edge of the screen.
    local fdx, fdy = (mapDx / rx) + uwOffset, mapDy / ry
    local uiDx = mapDx / rx
    local M = Config.MinimapComponent

    -- SCALING A GROUP OF RECTANGLES HAS TO SCALE THEIR OFFSETS TOO.
    --
    -- This is the bug that made the player arrow drift off centre whenever the
    -- map was resized, and made it drift further the more it was resized.
    --
    -- The three components' SIZES were multiplied by mapScaleW/H while their
    -- POSITIONS were left as the absolute constants from the config: the map at
    -- y = -0.047, the blur at (-0.01, 0.025). That is not a resize, it is a
    -- deformation. The map's 0.047 drop below its mask is upstream's deliberate
    -- crop and it is expressed in the same units as the height it was measured
    -- against — so at scaleH 0.603 the plane still dropped a full 0.047 into a
    -- mask only 60% as tall, i.e. 1.66x the intended displacement. The arrow is
    -- drawn on the plane and the window is the mask, so that displacement IS
    -- the arrow being off centre.
    --
    -- Multiplying the offsets by the same factors makes this a similarity
    -- transform about the safe zone's bottom-left corner: every proportion
    -- inside the group is preserved and only the whole thing changes size.
    --
    -- NOT to be confused with an earlier attempt that made mask and blur
    -- RELATIVE TO the map. That re-anchored them and did change the shape.
    -- This does not touch the anchoring at all.
    local ox, oy = M.x * mapScaleW, M.y * mapScaleH

    -- The blur's effective rect. In 'plane' mode it IS the plane, deltas and
    -- all, so the two can never drift apart no matter what is rescaled later.
    local ubx, uby, ubw, ubh
    if blurMode == 'plane' then
        ubx = ox + fdx + blipDx + blurDx
        uby = oy + fdy + blipDy + blurDy
        ubw = (M.w * mapScaleW) + blipDw + blurDw
        ubh = (M.h * mapScaleH) + blipDh + blurDh
    else
        ubx = (M.blurX * mapScaleW) + fdx + blurDx
        uby = (M.blurY * mapScaleH) + fdy + blurDy
        ubw = (M.blurW * mapScaleW) + blurDw
        ubh = (M.blurH * mapScaleH) + blurDh
    end

    local mx, my, mw, mh
    if maskMode == 'map' then
        -- For a mask texture that wants to sit exactly on the map component
        -- instead of in its own window. Not what we ship; kept switchable.
        mx, my, mw, mh = ox, oy, M.w, M.h
    else
        mx, my, mw, mh = M.maskX * mapScaleW, M.maskY * mapScaleH, M.maskW, M.maskH
    end
    if untouched then
        restoreStockMinimap()
    else
        -- Only the map component carries the blip adjustment. The mask is
        -- built from the UNADJUSTED position, so the two move independently —
        -- that separation is the whole point, and without it maskMode 'map'
        -- makes the mask follow the map and the adjustment does nothing.
        SetMinimapComponentPosition('minimap',      'L', 'B',
            ox + fdx + blipDx, oy + fdy + blipDy,
            (M.w * mapScaleW) + blipDw, (M.h * mapScaleH) + blipDh)
        -- The window is the mask, inset by the crop. Insetting rather than
        -- resizing keeps the untouched sides exactly where they were, so
        -- cropping the top does not also shift the left edge.
        local kw = (mw * mapScaleW) - cropL - cropR
        local kh = (mh * mapScaleH) - cropT - cropB
        SetMinimapComponentPosition('minimap_mask', 'L', 'B',
            mx + fdx + maskNudgeX + cropL,
            my + fdy + maskNudgeY + cropB,
            math.max(0.001, kw), math.max(0.001, kh))
        SetMinimapComponentPosition('minimap_blur', 'L', 'B',
            ubx, uby, math.max(0.001, ubw), math.max(0.001, ubh))
        SetBlipAlpha(GetNorthRadarBlip(), northBlip and 255 or 0)
        SetMinimapClipType(clipOverride or M.clipType or 0)
        if playerBlipScale > 0.0 then
            -- pcall'd for the same reason as the zoom: the main player blip is
            -- not guaranteed to exist at every moment (respawn, cutscene), and
            -- a nil handle must not take the rest of the minimap setup with it.
            pcall(function() SetBlipScale(GetMainPlayerBlipId(), playerBlipScale + 0.0) end)
        end
        -- pcall'd: this is the one call here whose accepted range is not
        -- something this resource can verify from outside the game, and a
        -- refused zoom must not take the rest of the minimap setup with it.
        if radarZoom > 0.0 then
            pcall(SetRadarZoom, math.floor(radarZoom + 0.5))
        end
    end

    -- Component outlines for /hudrects. Computed from the SAME terms that were
    -- just handed to SetMinimapComponentPosition, converted with the same
    -- safe-zone maths the published map rect uses — so an outline that does not
    -- sit on the thing it names is itself the finding.
    if showMapRects and not untouched then
        local dInset = (1.0 - GetSafeZoneSize()) * 0.5
        local function sr(x, y, w, h)
            return {
                left   = (dInset + x + uiDx) * 100.0,
                -- Distance from the screen's BOTTOM to this rect's TOP edge,
                -- matching --map-bottom on the NUI side.
                bottom = (dInset - (y + fdy)) * 100.0 + h * 100.0,
                width  = w * 100.0,
                height = h * 100.0,
            }
        end
        ui('mapDebug', { show = true, rects = {
            { name = 'minimap',
              r = sr(ox + blipDx, oy + blipDy,
                     (M.w * mapScaleW) + blipDw, (M.h * mapScaleH) + blipDh) },
            { name = 'minimap_mask',
              r = sr(mx + maskNudgeX + cropL, my + maskNudgeY + cropB,
                     math.max(0.001, (mw * mapScaleW) - cropL - cropR),
                     math.max(0.001, (mh * mapScaleH) - cropT - cropB)) },
            -- sr() adds fdx/fdy itself, so hand it the rect WITHOUT them.
            { name = 'minimap_blur',
              r = sr(ubx - fdx, uby - fdy,
                     math.max(0.001, ubw), math.max(0.001, ubh)) },
        } })
    elseif rectsWereShown then
        -- Only on the way OFF. applyMinimap is re-run by a watchdog twice a
        -- second, and an unconditional hide would be two pointless NUI messages
        -- per second for the entire session.
        rectsWereShown = false
        ui('mapDebug', { show = false })
    end
    if showMapRects then rectsWereShown = true end

    -- SetMinimapComponentPosition only updates the component's stored values;
    -- the on-screen scaleform can keep its old geometry until it is rebuilt.
    -- That was why /hudmap and /mapmove printed new values but changed nothing.
    if rebuild then rebuildMinimap() end

    -- Rounded minimap corners: swap GTA's square radar mask for the rounded one
    -- in stream/vice_minimap.ytd.
    --
    -- This crashed once before with "access to <asset> is locked". That was NOT
    -- asset protection (the .ytd is a plain unencrypted RSC7 resource) — it was
    -- the manifest declaring the file in files{} while stream/ was also
    -- auto-loading it, registering the asset twice. Keep it out of files{}.
    if untouched then
        -- Skipping applyMask is not enough: a swap applied earlier in this game
        -- session is still live. Take it back off.
        if maskApplied and not maskBusy then
            maskBusy = true
            CreateThread(function() removeMask() maskBusy = false end)
        end
    elseif maskBusy then
        -- A swap is already in flight; let it finish. The next watchdog pass
        -- reconciles whatever is still out of date.
    elseif Config.MinimapMask and not maskApplied then
        maskApplied = true
        maskBusy = true
        CreateThread(function() applyMask() maskBusy = false end)
    elseif Config.MinimapMask and maskAppliedDict and maskAppliedDict ~= maskDictFor(maskRadius) then
        -- The radius moved, so a DIFFERENT texture is wanted. AddReplaceTexture
        -- does not stack: the old replacement has to come off first, or the
        -- engine keeps drawing the corners it already has and the slider looks
        -- like it does nothing.
        maskBusy = true
        CreateThread(function()
            removeMask()
            maskApplied = true
            applyMask()
            maskBusy = false
        end)
    elseif not Config.MinimapMask and maskApplied then
        -- Flag turned off while a swap is live: take it back off.
        maskBusy = true
        CreateThread(function() removeMask() maskBusy = false end)
    end

    -- Publish the minimap's on-screen rect so the NUI panels can sit exactly on
    -- its top edge.
    --
    -- Preferred source is glitchdetector's `minimap-anchor` resource, which
    -- computes the true rect and — importantly — accounts for the player's
    -- SAFE-ZONE setting. The fallback below is calibrated against a default
    -- safe zone only, so a player who has moved that slider would see the
    -- panels drift off the map. If the resource is present we use it.
    local rect
    if GetResourceState('minimap-anchor') == 'started' then
        local ok, anchor = pcall(function() return exports['minimap-anchor']:GetMinimapAnchor() end)
        if ok and type(anchor) == 'table' and anchor.width and anchor.width > 0 then
            -- Values come back normalised 0..1; the NUI wants percentages, and
            -- `bottom` is measured from the screen bottom up to the map's TOP.
            rect = {
                left   = anchor.left_x * 100,
                width  = anchor.width * 100,
                bottom = (1.0 - anchor.top_y) * 100,
                height = anchor.height * 100,
            }
        end
    end

    if not rect then
        -- Fallback: derive the rect from the SAFE ZONE rather than from measured
        -- constants. The old constants were taken off a reference capture at one
        -- aspect ratio and one safe-zone setting, so any player who had touched
        -- the Safe Zone Size slider — or was not on 16:9 — got panels that sat
        -- somewhere near the map rather than on it. GTA anchors the minimap to
        -- the safe zone, so the only way to follow it is to ask.
        --
        -- Safe-zone inset, as a fraction of the screen: the engine insets by
        -- 5% at the minimum slider setting and 0% at the maximum.
        local safeZone = GetSafeZoneSize()
        local inset    = (1.0 - safeZone) * 0.5

        -- What the player SEES is the intersection of the map component and its
        -- mask window, not the map component — GTA's mask is inset horizontally
        -- and overhangs vertically, so the map component alone is wrong on both
        -- axes. The zone bar and vehicle panel sit on this rect, so getting it
        -- from the map component left them floating off the visible edge.
        --
        -- blipDx/blipDy and blipDw/blipDh belong in these edges. The map
        -- component is POSITIONED at M.x + blipDx with size M.w*scale + blipDw
        -- (see applyMinimap), so leaving them out meant this intersection was
        -- computed against a plane that was not where the plane actually was.
        -- The visible result: nudging the player arrow, or trimming the plane,
        -- left the minimap frame and the zone/vehicle panels sitting off the
        -- map — the frame did not follow the arrow, it just stopped agreeing
        -- with it. In the ordinary case the mask is the smaller window, the
        -- intersection is the mask, and moving the arrow correctly moves
        -- nothing at all.
        local mapL = ox + blipDx
        local mapR = mapL + (M.w * mapScaleW) + blipDw
        local mskL = mx + maskNudgeX + cropL
        local mskR = mskL + (mw * mapScaleW) - cropL - cropR
        local visL, visR = math.max(mapL, mskL), math.min(mapR, mskR)

        local mapB = oy + blipDy
        local mapT = mapB + (M.h * mapScaleH) + blipDh
        local mskB = my + maskNudgeY + cropB
        local mskT = mskB + (mh * mapScaleH) - cropT - cropB
        local visB, visT = math.max(mapB, mskB), math.min(mapT, mskT)

        -- Component units are safe-zone-relative, so the on-screen rect is the
        -- inset plus the component's own offset and size.
        local floorY = (inset - (visB + fdy)) * 100.0    -- map's BOTTOM edge
        local height = (visT - visB) * 100.0

        rect = {
            left   = (inset + visL + uiDx) * 100.0,
            width  = (visR - visL) * 100.0,
            bottom = floorY + height,                    -- map's TOP edge
            height = height,
        }
    end

    -- A hand-measured rect wins over the derived one.
    if manualRect then
        rect = {
            left   = manualRect.left,
            width  = manualRect.width,
            bottom = manualRect.bottom,
            height = manualRect.height,
        }
    end

    rect.showFrame = Config.Minimap.showFrame and true or false
    rect.showCross = showMapCross and true or false

    -- The watchdog thread re-runs this twice a second to reassert the component
    -- positions. Only message the NUI when the rect actually moved, so an
    -- unchanged map is not re-published 120 times a minute.
    local key = ('%.3f|%.3f|%.3f|%.3f|%s|%s'):format(
        rect.left, rect.width, rect.bottom, rect.height,
        tostring(rect.showFrame), tostring(rect.showCross))
    if key ~= lastRectKey then
        lastRectKey = key
        ui('mapRect', rect)
    end
end

-- The mask can apply successfully and still not change the visible shape,
-- because SetMinimapClipType imposes its own clip that can override it.
-- This cycles the clip type live so the right one can be found by eye.
--   /hudclip 0   /hudclip 1   /hudclip 2   /hudclip 3
RegisterCommand('hudclip', function(_, args)
    local n = tonumber(args[1])
    if not n then
        print('^3[vice_hud]^7 usage: /hudclip <0|1|2|3>  — try each and watch the minimap corners')
        return
    end
    n = math.floor(n + 0.5)
    clipOverride = n
    applyMinimap(true)
    print(('^3[vice_hud]^7 SetMinimapClipType(%d) applied (until /mapreset)'):format(n))
end, false)

-- =============================================================================
-- Minimap-on-foot preference
-- =============================================================================

local KVP_MINIMAP = 'vice_hud:minimapOnFoot'
local minimapOnFoot = Config.MinimapOnFootDefault

local function loadMinimapPref()
    local saved = GetResourceKvpString(KVP_MINIMAP)
    if saved == 'always' then minimapOnFoot = true
    elseif saved == 'hidden' then minimapOnFoot = false end
end

RegisterCommand('hudminimap', function()
    minimapOnFoot = not minimapOnFoot
    SetResourceKvp(KVP_MINIMAP, minimapOnFoot and 'always' or 'hidden')
    if not IsPedInAnyVehicle(cache.ped or PlayerPedId(), false) then
        DisplayRadar(minimapOnFoot or editorOpen)
    end
    lib.notify({
        title = 'HUD',
        description = minimapOnFoot and 'Minimap always visible' or 'Minimap hidden while on foot',
        type = 'inform',
    })
end, false)

-- =============================================================================
-- HUD horizontal offset (for widescreen players who want it nudged)
-- =============================================================================

local KVP_OFFSET = 'vice_hud:offsetX'

local function applyOffset(px)
    ui('hudOffset', { x = px })
end

RegisterCommand('hudoffset', function(_, args)
    local px = tonumber(args[1])
    if not px then
        lib.notify({ title = 'HUD', description = 'Usage: /hudoffset <pixels>  (e.g. -120)', type = 'error' })
        return
    end
    SetResourceKvp(KVP_OFFSET, tostring(px))
    applyOffset(px)
    lib.notify({ title = 'HUD', description = ('HUD shifted %dpx'):format(math.floor(px + 0.5)),
        type = 'success' })
end, false)

-- =============================================================================
-- /hudmap — size the minimap against the reference, live
-- =============================================================================
-- Usage:  /hudmap 0.85 0.85     scale width/height (relative to current config)
--         /hudmap               print the current resolved values
--
-- Applies immediately, no restart. When it looks right, paste the printed
-- numbers into Config.MinimapComponent so they persist.
RegisterCommand('hudmap', function(_, args)
    local sw, sh = tonumber(args[1]), tonumber(args[2])
    local dx, dy = tonumber(args[3]), tonumber(args[4])
    if dx then mapDx = px(dx) end
    -- Screen-space pixels. The components are anchored 'B', so a POSITIVE dy
    -- moves the map UP.
    if dy then mapDy = px(dy) end
    if sw then
        mapScaleW = sw
        mapScaleH = sh or sw
    end
    if sw or dx or dy then
        applyMinimap(true)
        saveMapState()
    end

    local M = Config.MinimapComponent
    print(('^3[vice_hud]^7 scale W=%.3f H=%.3f   offset dx=%d dy=%d px')
        :format(mapScaleW, mapScaleH, mapDx, mapDy))
    print(('  the FRAME is drawn at left %.2f%% width %.2f%% height %.2f%% of the'):format(
        Config.Minimap.left, Config.Minimap.width, Config.Minimap.height))
    print('  16:9 stage. Aim for the map filling that frame exactly — if map')
    print('  content spills outside it, scale DOWN; if there is a gap, scale UP.')
    print('  paste into Config.MinimapComponent:')
    print(('    w     = %.4f,   h     = %.4f,'):format(M.w * mapScaleW, M.h * mapScaleH))
    print(('    maskW = %.4f,   maskH = %.4f,'):format(M.maskW * mapScaleW, M.maskH * mapScaleH))
    print(('    blurW = %.4f,   blurH = %.4f,'):format(M.blurW * mapScaleW, M.blurH * mapScaleH))
    print('  (x/y offsets are unchanged by scaling and stay as-is)')
    print('  then /hudslot to line the zone bar back up on the new top edge.')
end, false)

-- Compatibility alias for the map-position command name used by the server's
-- other HUD resources. It accepts the same arguments as /hudmap.
RegisterCommand('mapmove', function(_, args)
    ExecuteCommand('hudmap ' .. table.concat(args or {}, ' '))
end, false)

-- =============================================================================
-- /hudslot — line the zone/vehicle panels up with the minimap's top edge
-- =============================================================================
-- Usage:  /hudslot <left%> <width%> <bottom%> <height%>   (% of the stage)
--         /hudslot                                        print current values
RegisterCommand('hudslot', function(_, args)
    if args[1] == 'reset' or args[1] == 'auto' then
        manualRect = nil
        lastRectKey = nil
        applyMinimap(false)
        saveMapState()
        print('^2[vice_hud]^7 map rect back to the derived one')
        return
    end

    local l, w, b, h = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if l or w or b or h then
        -- Seed from whatever is on screen now, so a single value can be nudged
        -- without having to restate the other three.
        local cur = manualRect or {
            left = Config.Minimap.left, width = Config.Minimap.width,
            bottom = Config.Minimap.bottom, height = Config.Minimap.height,
        }
        manualRect = {
            left   = l or cur.left,
            width  = w or cur.width,
            bottom = b or cur.bottom,
            height = h or cur.height,
        }
        Config.Minimap.left   = manualRect.left
        Config.Minimap.width  = manualRect.width
        Config.Minimap.bottom = manualRect.bottom
        Config.Minimap.height = manualRect.height
        lastRectKey = nil
        applyMinimap(false)
        saveMapState()
    end

    local M = Config.Minimap
    print('^3[vice_hud]^7 ===== map rect =====')
    print(('  source  %s'):format(manualRect and 'MANUAL (/hudslot)' or 'derived from the safe zone'))
    print(('  left %.2f%%   width %.2f%%   bottom %.2f%%   height %.2f%%')
        :format(M.left, M.width, M.bottom, M.height))
    print('')
    print('  This rect is what the zone bar, the vehicle panel, the minimap')
    print('  frame and the /hudcross marker all sit on. If the crosshair is not')
    print('  on the middle of the drawn map, this rect is wrong -- fix it here.')
    print('')
    print('  /hudframe            outline the rect on screen')
    print('  /hudcross            mark its centre')
    print('  /hudslot <l> <w> <b> <h>   set it, in %% of the screen')
    print('                       (any argument may be skipped with -)')
    print('  /hudslot auto        go back to the derived rect')
    print('')
    print('  left/bottom are measured from the LEFT and BOTTOM screen edges;')
    print('  bottom is to the rect TOP edge. Line the frame up with the map,')
    print('  then /hudexport and send it.')
end, false)

-- =============================================================================
-- /hudtest — diagnostic
-- =============================================================================
-- Pushes known-good sample data straight to the NUI, bypassing all game-state
-- gathering. If the panels appear after running this, the NUI and CSS are fine
-- and the fault is in the Lua data path; if they do not, the fault is in the
-- page. Also prints what the game state actually looks like right now.
RegisterCommand('hudtest', function()
    local ped = cache.ped or PlayerPedId()
    print('^3[vice_hud]^7 ---- state ----')
    print(('  cache.ped      = %s'):format(tostring(cache.ped)))
    print(('  cache.vehicle  = %s'):format(tostring(cache.vehicle)))
    print(('  InAnyVehicle   = %s'):format(tostring(IsPedInAnyVehicle(ped, false))))
    print(('  veh.make/model = "%s" / "%s"'):format(tostring(veh.make), tostring(veh.model)))
    print(('  veh.engine/hp  = %s / %s'):format(tostring(veh.engine), tostring(veh.health)))
    print(('  wantedLevel    = %s'):format(tostring(GetPlayerWantedLevel(PlayerId()))))
    print(('  sprintStamina  = %s  (raw native value — tells us if it is 0..1 or 0..100)')
        :format(tostring(GetPlayerSprintStaminaRemaining(PlayerId()))))
    print(('  sprintTime     = %s'):format(tostring(GetPlayerSprintTimeRemaining(PlayerId()))))
    print(('  health/armour  = %s / %s'):format(GetEntityHealth(ped), GetPedArmour(ped)))
    print(('  focusMeter/act = %s / %s'):format(focusMeter, tostring(focusActive)))
    print('^3[vice_hud]^7 pushing sample payloads to NUI...')

    ui('status', { health = 55, focus = 40, stamina = 60 })
    ui('wanted', { active = true, stars = 2, maxStars = Config.MaxStars or 6,
        tells = { 'outfit', 'voice', 'vehicle' } })
    ui('weapon', { armed = true, clip = 20, reserve = 80 })
    ui('zone', { zone = 'TEST ZONE', duration = 15000 })
    ui('vehicle', { show = true, make = 'TESTMAKE', model = 'TESTMODEL', fuel = 70,
        engineOn = true, engineHealth = 1000, lockState = 'locked' })
    -- A non-zero `delta` is what fires the centre-screen +/- indicator; without
    -- it /hudtest only ever showed the corner standing panel, so the one piece
    -- of the honor UI most worth eyeballing was the piece it never drew.
    ui('honor', {
        emoji  = Config.Honor.devil,
        reason = 'Killed a bystander',
        honor  = -50,
        delta  = -10,
        angelEmoji = Config.Honor.angel,
        devilEmoji = Config.Honor.devil,
        showValue  = Config.Honor.showValue,
        valueLabel = Config.Honor.valueLabel,
        holdMs     = Config.Honor.holdMs,
    })
    print(('  honor: the corner panel (for %sms) AND the centre +/- indicator should both show.')
        :format(Config.Honor.holdMs or 0))

    ui('reputation', {
        icon   = Config.Reputation.tracks.criminal.icon,
        label  = Config.Reputation.tracks.criminal.label,
        reason = 'Robbed an armoured truck',
        value  = 240,
        tier   = 3,
        delta  = 25,
        showValue = Config.Reputation.showValue,
        holdMs    = Config.Reputation.holdMs,
    })
    print(('  reputation: the corner panel (for %sms) AND the centre +N indicator should both show.')
        :format(Config.Reputation.holdMs or 0))
    print('^2[vice_hud]^7 sent. Panels should be visible for ~15s.')

    -- Hand the HUD back to reality afterwards.
    --
    -- The pushes above go STRAIGHT to the NUI, so the poll loop's change caches
    -- (lastWanted, lastCash, currentZone, panelUntil) still describe the real
    -- game state and it therefore has nothing new to send. Left alone, the fake
    -- two-star wanted level, the "police are searching the area" tells and the
    -- TESTMAKE / TESTMODEL vehicle panel stay on screen for the rest of the
    -- session — and the real zone label never comes back, because checkZone
    -- only pushes when the zone CHANGES.
    --
    -- Clearing the caches makes the next tick re-send the truth. Same call
    -- /movehud makes when it closes, for exactly the same reason.
    CreateThread(function()
        Wait(15000)
        if resetPushCaches then resetPushCaches() end
        print('^3[vice_hud]^7 /hudtest sample cleared — the HUD is back on real game state.')
    end)
end, false)

-- =============================================================================
-- /hudbrand — see a manufacturer badge without owning the car
-- =============================================================================
-- The vehicle panel draws the mark of the marque you are driving, and there are
-- sixty-six of them. Checking that one looks right should not require finding
-- one of their cars, so this pushes any make straight at the page:
--
--   /hudbrand Truffade      one marque, held for 20 seconds
--   /hudbrand               walks the whole roster, four seconds each
--
-- The page owns the table (html/makes.js) and Lua has no copy of it, which is
-- the point: there is one roster, it ships to the client, and a make this side
-- does not recognise still gets whatever the page decides. A name that is not
-- on the roster is not an error — it renders the plain plate, which is exactly
-- what an addon vehicle with no resolvable make does.
--
-- The roster walk is driven by the PAGE for the same reason: a second copy of
-- the list over here would be wrong the first time anyone regenerated the
-- first one.
RegisterCommand('hudbrand', function(_, args)
    if args[1] then
        -- Multi-word marques: "Western Motorcycle Company" arrives as three
        -- arguments and has to go back together before the page can match it.
        local make = table.concat(args, ' ')
        print(('^3[vice_hud]^7 /hudbrand — showing "%s" for 20s.'):format(make))
        ui('vehicle', {
            show = true, make = make, model = 'SAMPLE',
            fuel = 70, engineOn = true, engineHealth = 1000, lockState = 'locked',
        })
        CreateThread(function()
            Wait(20000)
            if resetPushCaches then resetPushCaches() end
        end)
        return
    end

    print('^3[vice_hud]^7 /hudbrand — walking the roster, 4s each. Run it again to stop.')
    ui('brandTour', { ms = 4000 })
end, false)

-- =============================================================================
-- /hudlogos — why is there no badge?
-- =============================================================================
-- Three faults look identical from the driver's seat and have three different
-- fixes, so this asks the PAGE what it can actually see rather than guessing:
--
--   ok = 0 out of 50        the marks did not ship. Almost always a server that
--                           has not rescanned the resource folder: adding files
--                           to fxmanifest needs `refresh` in the server console
--                           BEFORE `ensure vice_hud`, or the server keeps
--                           serving the old file list and every request 404s.
--   ok = 50, badged = false the marks are there and the panel is not asking for
--                           one. Either the vehicle's make did not resolve, or
--                           it is one of the sixteen marques that ship no badge
--                           (see the README) -- /hudbrand Truffade settles it.
--   ok = 50, badged = true  they loaded and something is hiding them. The rest
--                           of the line says which: display, opacity, and the
--                           size of both the image and the window it is clipped
--                           to. A zero anywhere is the culprit.
RegisterCommand('hudlogos', function()
    print('^3[vice_hud]^7 /hudlogos — asking the page what it can see...')
    ui('logoCheck', {})
end, false)

RegisterNUICallback('logoReport', function(data, cb)
    cb({})
    if type(data) ~= 'table' then return end
    if data.fatal then
        if data.fatal == 'no-table' then
            print('^1[vice_hud]^7 html/makes.js did not load, so the page has no')
            print('  manufacturer table and can never draw a badge. Everything else')
            print('  on the HUD works without it, which is why this is quiet.')
            print('')
            print('^3  The marks are NOT fetched from the internet^7 — they are 50 PNGs')
            print('  in html/logos/ that ship with the resource. makes.js and that')
            print('  folder are both NEW entries in fxmanifest, and a server only')
            print('  scans a resource folder on `refresh`. `restart` re-runs the')
            print('  scripts but keeps serving the file list from the last scan, so')
            print('  every request for the new files 404s.')
            print('')
            print('^2  In the SERVER console:^7  refresh   then   ensure vice_hud')
        elseif data.fatal == 'no-panel' then
            print('^1[vice_hud]^7 the vehicle panel is missing from the page — html/index.html')
            print('  is stale or was not served. Same fix: refresh, then ensure vice_hud.')
        elseif data.fatal == 'no-img' then
            print('^1[vice_hud]^7 the panel is there but has no badge element — html/index.html')
            print('  is an older copy than html/app.js. Same fix: refresh, then ensure vice_hud.')
        else
            print(('^1[vice_hud]^7 /hudlogos: %s'):format(tostring(data.fatal)))
        end
        return
    end

    local ok, total = tonumber(data.ok) or 0, tonumber(data.total) or 0
    local colour = (ok == total and total > 0) and '^2' or '^1'
    print(('%s[vice_hud]^7 marks loaded: %d / %d'):format(colour, ok, total))
    print(('  first URL the page asked for: %s'):format(tostring(data.sampleUrl)))
    if type(data.failed) == 'table' and #data.failed > 0 then
        print(('  failed (first few): %s'):format(table.concat(data.failed, ', ')))
    end
    print(('  panel badged = %s   src = "%s"'):format(tostring(data.badged), tostring(data.src)))
    print(('  image: display=%s opacity=%s size=%sx%s   clip window=%sx%s'):format(
        tostring(data.display), tostring(data.opacity),
        tostring(data.imgW), tostring(data.imgH),
        tostring(data.clipW), tostring(data.clipH)))

    if ok == 0 and total > 0 then
        print('^3  Nothing loaded.^7 The files are almost certainly not being served.')
        print('  In the SERVER console:  refresh   then   ensure vice_hud')
        print('  (`restart` alone does not rescan the folder, so files added to')
        print('   fxmanifest since the last refresh stay invisible.)')
    elseif ok == total and not data.badged then
        print('^3  The marks are fine and the panel is not asking for one.^7')
        print('  Try  /hudbrand Truffade  — if that shows a badge, the vehicle you')
        print('  were in either has no resolvable make or is one of the sixteen')
        print('  marques that ship no badge. /hudtest prints the resolved make.')
    end
end)

-- =============================================================================
-- Prompt glyphs — resolve the player's LIVE bind, keyboard or pad
-- =============================================================================

-- GetControlInstructionalButton returns GTA button-font ligatures for a pad.
-- Those do not exist in the NUI's fonts, so anything that is not plain printable
-- ASCII is replaced with a neutral marker rather than rendering as tofu.
local function safeLabel(str)
    if not str or str == '' then return nil end
    for i = 1, #str do
        local b = str:byte(i)
        if b < 0x20 or b > 0x7E then return '•' end
    end
    return str
end

local function resolveKey(key)
    if type(key) == 'string' then return key end
    if type(key) ~= 'number' then return nil end
    local ok, raw = pcall(GetControlInstructionalButton, 0, key, true)
    if not ok or not raw then return nil end
    return safeLabel(raw:sub(3))
end

local function usingPad()
    return not IsInputDisabled(2)
end

-- =============================================================================
-- Action prompts
-- =============================================================================

local prompts = {}          -- id -> { label, key }
local promptCount = 0
local lastDevice = nil

-- Forward declarations: HideActionPrompt is referenced by the resource-stop
-- handler below, and UpdateExhaustion by the main status loop, both of which
-- are written before the definitions.
local ShowActionPrompt, HideActionPrompt
local UpdateExhaustion

local function pushPrompt(id)
    local p = prompts[id]
    if not p then return end
    ui('prompt', {
        id = id, show = true, label = p.label,
        glyph = resolveKey(p.key), device = usingPad() and 'pad' or 'kbm',
    })
end

ShowActionPrompt = function(id, label, key)
    if not id then return end
    if not prompts[id] then promptCount = promptCount + 1 end
    prompts[id] = { label = label or '', key = key }
    pushPrompt(id)
end

HideActionPrompt = function(id)
    if not id or not prompts[id] then return end
    prompts[id] = nil
    promptCount = promptCount - 1
    ui('prompt', { id = id, show = false })
end

exports('ShowActionPrompt', ShowActionPrompt)
exports('HideActionPrompt', HideActionPrompt)

-- Clean up prompts belonging to a resource that stops, so a crashed script can
-- never leave a prompt stuck on screen.
AddEventHandler('onClientResourceStop', function(res)
    for id in pairs(prompts) do
        if id == res or id:sub(1, #res + 1) == res .. ':' then HideActionPrompt(id) end
    end
end)

-- Re-resolve glyphs when the input device changes, and only then.
CreateThread(function()
    while true do
        Wait(400)
        if promptCount > 0 then
            local device = usingPad() and 'pad' or 'kbm'
            if device ~= lastDevice then
                lastDevice = device
                local glyphs = {}
                for id, p in pairs(prompts) do glyphs[id] = resolveKey(p.key) end
                ui('promptGlyphs', { device = device, glyphs = glyphs })
            end
        end
    end
end)

-- =============================================================================
-- Honor toast
-- =============================================================================

-- Last honor value seen, so a push can be reported as a CHANGE (which drives
-- the centre-screen +/- indicator) as well as a standing (the corner mugshot).
-- nil means "not known yet": the first push is a standing, not a change, or
-- every player would get an indicator the moment they connected.
local lastHonor = nil

local function honorEmoji(honor)
    if honor >= Config.Honor.angelAt then return Config.Honor.angel
    elseif honor <= Config.Honor.devilAt then return Config.Honor.devil end
    return Config.Honor.neutral
end

local function ShowHonorToast(mugshot, honor, emoji, reason)
    local value = tonumber(honor)

    -- The face in the corner reflects where honor STANDS.
    if not emoji or emoji == '' then
        emoji = honorEmoji(value or 0)
    end

    local delta = 0
    if value and lastHonor and value ~= lastHonor then
        delta = value - lastHonor
    end
    if value then lastHonor = value end

    ui('honor', {
        mugshot = mugshot,
        emoji   = emoji,
        reason  = reason,
        honor   = value,
        delta   = delta,
        -- The centre indicator shows the face for the DIRECTION of the change,
        -- which is not necessarily the face for the current standing.
        angelEmoji = Config.Honor.angel,
        devilEmoji = Config.Honor.devil,
        showValue  = Config.Honor.showValue,
        valueLabel = Config.Honor.valueLabel,
        holdMs     = Config.Honor.holdMs,
    })
end

--- Seed the standing WITHOUT drawing anything.
---
--- The delta that fires the centre indicator is measured against the last value
--- this file saw, so a resource that knows the player's honor at spawn needs a
--- way to say so - otherwise the first real change of the session is reported
--- as a change from nothing and draws no indicator. Doing that through
--- ShowHonorToast instead would flash the panel at a player who has not done
--- anything yet, which is exactly the clutter the hold timer exists to avoid.
exports('SetHonorStanding', function(honor)
    local value = tonumber(honor)
    if value then lastHonor = value end
end)

--- Force the centre indicator, for callers that know the direction but not the
--- value (and for /hudtest).
exports('ShowHonorChange', function(delta, mugshot)
    ui('honor', {
        mugshot = mugshot,
        emoji   = honorEmoji(lastHonor or 0),
        honor   = lastHonor,
        delta   = tonumber(delta) or 0,
        angelEmoji = Config.Honor.angel,
        devilEmoji = Config.Honor.devil,
        showValue  = Config.Honor.showValue,
        valueLabel = Config.Honor.valueLabel,
        holdMs     = Config.Honor.holdMs,
    })
end)

exports('ShowHonorToast', ShowHonorToast)
exports('SetHudOffsetX', function(px) applyOffset(tonumber(px) or 0) end)

--- Hide or show the whole HUD, for cutscenes, camera modes and death screens.
--- The NUI has always understood this message; nothing could send it.
exports('SetHudVisible', function(visible)
    ui('hudVisible', { show = visible ~= false })
end)

-- Accept the event qbx_honor already fires, so no change is needed there.
RegisterNetEvent('vice_hud:honor', function(data)
    if type(data) ~= 'table' then return end
    ShowHonorToast(data.mugshot, data.honor, data.emoji, data.reason)
end)

-- =============================================================================
-- Reputation toast
-- =============================================================================
-- Same STATE/CHANGE split as honor above, per track: the corner panel shows
-- whichever track most recently changed, the centre popup fires on a
-- non-zero delta measured against the last value THIS FILE saw (not whatever
-- qbx_reputation says the delta was — same reasoning as honor's lastHonor:
-- the caller can be wrong about the direction, vice_hud deriving it itself
-- cannot disagree with itself).
--
-- No mugshot, no angel/devil face: reputation is not a moral axis, so the
-- panel is icon + label + value/tier, not a portrait.
local lastRepValue = {} -- [track] = number
local lastRepTier  = {} -- [track] = number

local function ShowReputationToast(track, value, tier, reason)
    local def = Config.Reputation.tracks[track]
    if not def then return end -- unknown track name; say nothing rather than draw a blank panel

    value = tonumber(value)
    tier  = tonumber(tier)

    local delta = 0
    if value and lastRepValue[track] and value ~= lastRepValue[track] then
        delta = value - lastRepValue[track]
    end
    if value then lastRepValue[track] = value end

    ui('reputation', {
        icon    = def.icon,
        label   = def.label,
        reason  = reason,
        value   = value,
        tier    = tier,
        delta   = delta,
        showValue = Config.Reputation.showValue,
        holdMs    = Config.Reputation.holdMs,
    })

    -- A tier crossing is a bigger deal than a routine tick. Rather than invent
    -- a second "big deal" animation, this reuses the skill-up toast that
    -- already means exactly that ("you levelled something up") -- see
    -- client_skills.lua. One id per track keeps a criminal tier-up from
    -- retriggering mid-animation if a trade tier-up lands in the same second.
    if tier and lastRepTier[track] and tier > lastRepTier[track] then
        ui('skillUp', {
            id    = 'rep_' .. track,
            label = def.label,
            level = tier,
            blurb = reason or ('Reached tier ' .. tier),
        })
    end
    if tier then lastRepTier[track] = tier end
end

--- Seed the standing WITHOUT drawing anything. Same rationale as
--- SetHonorStanding: a resource that knows the player's tracks at spawn
--- needs a way to say so, or the first real change of the session reports a
--- delta from nothing and a tier "crossed" from nothing.
exports('SetReputationStanding', function(track, value, tier)
    if not Config.Reputation.tracks[track] then return end
    value = tonumber(value)
    tier  = tonumber(tier)
    if value then lastRepValue[track] = value end
    if tier then lastRepTier[track] = tier end
end)

exports('ShowReputationToast', ShowReputationToast)

-- =============================================================================
-- Zone bar
-- =============================================================================

local currentZone = nil
local zoneReady = false

local function checkZone(ped)
    local label = GetLabelText(GetNameOfZone(GetEntityCoords(ped)))
    if label == currentZone then return end
    currentZone = label
    -- Skip the very first resolution after spawn so a popup doesn't fire on load.
    if not zoneReady then zoneReady = true return end
    ui('zone', { zone = label, water = IsPedSwimming(ped) })
end

-- =============================================================================
-- Turn-by-turn nav popup
-- =============================================================================
-- Uses the GAME'S OWN turn-by-turn generator, not a hand-rolled one.
--
-- PATHFIND::GENERATE_DIRECTIONS_TO_COORD walks the engine's real GPS route --
-- the same route the minimap draws its line along -- and hands back the next
-- manoeuvre plus the distance to the junction it happens at. An earlier
-- version here walked road nodes by hand with
-- GET_NTH_CLOSEST_VEHICLE_NODE_FAVOUR_DIRECTION, which was a greedy heuristic
-- over the road graph and NOT the route the game itself had chosen: it
-- regularly said "left" where the minimap line went right. That is the bug
-- this replaced, and it is why nothing here should go back to deriving a
-- direction from headings.
--
-- The direction codes are not guesses -- they are read off Rockstar's own
-- trevor3.c, which switches on this native's `direction` out-param and picks
-- a text label per case:
--     3 -> "TRV3_dirL"   left
--     4 -> "TRV3_dirR"   right
--     5 -> "TRV3_dirS"   straight on
--     1, 6, 7, 8 -> "TRV3_dirW"  wrong way / recalculating
--     0, 2 -> no label at all; the route is not resolved yet
-- trevor3 also lumps 1/6/7/8 together in its own "route changed, resay it"
-- test, which is the tell that they are all the same "you are not on the
-- route" state rather than four distinct manoeuvres.

-- Everything below down to updateNav's closing `end` is wrapped in a single
-- `do...end` block on purpose: client.lua's main chunk has a hard cap of 200
-- top-level locals (Lua's per-function register limit, enforced at parse
-- time -- FXServer refuses to even load the file past it, which is exactly
-- what happened here the first time this block was added as plain top-level
-- locals). Only `updateNav` is called from outside this block, so it alone
-- needs a real top-level local; everything else lives inside the `do` block
-- and goes out of scope (and off the main chunk's register count) at its `end`.
local updateNav
do

-- Rockstar's mapping, from trevor3.c (see the header comment above).
local DIR_LEFT, DIR_RIGHT, DIR_STRAIGHT = 3, 4, 5
local NAV_DIR = {
    [DIR_LEFT]     = { dir = 'left',     text = 'Turn Left' },
    [DIR_RIGHT]    = { dir = 'right',    text = 'Turn Right' },
    -- "Continue Straight" rather than "Straight" reads better but is by far
    -- the widest string this bar ever shows, and it is what first overflowed
    -- on a narrow aspect. The NUI shrinks to fit either way (fitBox in
    -- app.js), so this is about not spending that shrink on the common case.
    [DIR_STRAIGHT] = { dir = 'straight', text = 'Straight On' },
}
-- 1/6/7/8 all mean "not on the route"; the game says the same thing for each.
local NAV_LOST = { [1] = true, [6] = true, [7] = true, [8] = true }

local navShown = false     -- what the UI is currently displaying
local navShownAt = 0       -- GetGameTimer() when that last CHANGED
local navLast = nil        -- last good payload, reused while recalculating
local navRemaining = ''    -- throttled: the whole-route distance figure
local navRemainingAt = 0

local function navFormatDist(m)
    if not m or m < 0 then return '' end
    local ft = m * 3.28084
    if ft < 900.0 then
        return string.format('%d ft', math.floor(ft / 5.0 + 0.5) * 5)
    end
    local mi = m / 1609.344
    if mi < 10.0 then return string.format('%.2f mi', mi) end
    return string.format('%d mi', math.floor(mi + 0.5))
end

local colouredWaypointBlip = nil -- blip handle we've already recoloured, so a fresh waypoint gets recoloured too

local function getWaypointCoords()
    local blip = GetFirstBlipInfoId(8) -- 8 = the player's own waypoint cross
    if blip and blip ~= 0 and DoesBlipExist(blip) then
        local wc = Config.Nav.waypointColour
        if wc and blip ~= colouredWaypointBlip then
            SetBlipColour(blip, 84) -- required so SetBlipSecondaryColour's RGB actually takes
            SetBlipSecondaryColour(blip, wc.r, wc.g, wc.b) -- recolours the cross AND the route line
            colouredWaypointBlip = blip
        end
        return GetBlipInfoIdCoord(blip)
    end
    return nil
end

updateNav = function(ped)
    if not Config.Nav.enable then return end

    local wp = getWaypointCoords()
    if not wp then
        if navShown or navLast then
            navShown, navLast, navRemaining = false, nil, ''
            ui('nav', { active = false })
        end
        return
    end

    local now = GetGameTimer()

    -- The engine's own next manoeuvre along its own GPS route.
    local _, direction, _, distToJunction =
        GenerateDirectionsToCoord(wp.x, wp.y, wp.z, true)

    local entry = NAV_DIR[direction]
    if not entry then
        -- 0/2 (route not resolved) or 1/6/7/8 (off-route, recalculating).
        -- Keep showing the last good instruction rather than blanking: the
        -- native dips into these states for a tick or two at junctions and
        -- during recalculation, and reacting to each one is what made the
        -- popup flash. Only a cleared waypoint (handled above) takes it down.
        if navLast and navShown then ui('nav', navLast) end
        return
    end

    -- Whole-route distance for the badge on the map. Throttled -- this one is
    -- a real pathfind query, unlike the manoeuvre above.
    if navRemaining == '' or (now - navRemainingAt) > Config.Nav.routeIntervalMs then
        navRemainingAt = now
        local pos = GetEntityCoords(ped)
        local travel = CalculateTravelDistanceBetweenPoints(
            pos.x, pos.y, pos.z, wp.x, wp.y, wp.z)
        navRemaining = navFormatDist(travel)
    end

    -- Hysteresis, and a minimum time on screen. Without the second threshold
    -- the popup sat exactly on the boundary and blinked once a tick while
    -- distToJunction jittered across it; without the hold, a junction passed
    -- at speed could show and hide inside a few hundred ms.
    local near
    if navShown then
        near = distToJunction <= Config.Nav.farTurnMetres
        if not near and (now - navShownAt) < Config.Nav.minHoldMs then near = true end
    else
        near = distToJunction <= Config.Nav.nearTurnMetres
    end
    if near ~= navShown then
        navShown = near
        navShownAt = now
    end

    navLast = {
        active = true,
        near = near,
        instruction = entry.text,
        dir = entry.dir,
        distance = navFormatDist(distToJunction),
        remaining = navRemaining,
    }
    ui('nav', navLast)
end

end -- do (nav block, see comment above NAV_DIR)

-- =============================================================================
-- Vehicle panel
-- =============================================================================

-- (`veh` is forward-declared at the top of the file.)

-- Addon vehicles frequently have no resolvable make. A token that isn't a plain
-- word is discarded so the panel shows the model alone rather than a raw key.
local function cleanMake(token)
    if not token or token == '' then return '' end
    local label = GetLabelText(token)
    if label and label ~= '' and label ~= 'NULL' then return label end
    if token:match("^[%a][%a%s%-&']*$") then return token end
    return ''
end

local function resolveVehicle(vehicle)
    local model = GetEntityModel(vehicle)

    local make = cleanMake(GetMakeNameFromVehicleModel(model))

    local display = GetDisplayNameFromVehicleModel(model)
    local label = GetLabelText(display)
    local modelName
    if label and label ~= '' and label ~= 'NULL' then
        modelName = label
    elseif display and display ~= '' then
        modelName = display
    else
        modelName = 'VEHICLE'
    end

    -- Addon and utility vehicles frequently have no GXT entry, so both lookups
    -- fall through to the same raw spawn code and the panel renders it twice
    -- ("SEGWAYCIV / SEGWAYCIV"). If they collide, drop the make and let the
    -- model line stand alone.
    if make ~= '' and make:upper() == modelName:upper() then
        make = ''
    end

    veh.make, veh.model = make, modelName
end

local function lockState(vehicle)
    local ok, st = pcall(function() return Entity(vehicle).state.doorslockstate end)
    if not ok or st == nil then st = GetVehicleDoorLockStatus(vehicle) end
    if st == 2 then return 'locked' end
    if st == 1 then return 'unlocked' end
    return 'unknown'
end

local function fuelLevel(vehicle)
    -- LegacyFuel keeps the tank in the "_FUEL_LEVEL" decorator; fall back to the
    -- native so the pip still means something if that resource isn't present.
    if DecorExistOn(vehicle, '_FUEL_LEVEL') then
        return math.floor(DecorGetFloat(vehicle, '_FUEL_LEVEL') or 0)
    end
    return math.floor(GetVehicleFuelLevel(vehicle) or 0)
end

-- =============================================================================
-- Stamina
-- =============================================================================
-- GetPlayerSprintStaminaRemaining is inconsistently documented: on some builds
-- it returns REMAINING stamina (falls as you sprint), on others DEPLETION
-- (rises as you sprint), and the scale is either 0..1 or 0..100. Guessing wrong
-- gives a bar that sits permanently empty, which is exactly what happened.
--
-- So instead of assuming, watch it. While the player is actually sprinting,
-- compare successive samples: rising => depletion, falling => remaining. Latch
-- the answer the first time it moves and use it from then on.
local staminaMode   = nil     -- nil = undecided, 'depletion', 'remaining', 'manual'
local staminaScale  = nil     -- nil = undecided, 1.0 = native is 0..100, 100.0 = 0..1
local lastSprintRaw = nil
local sprintStuckMs = 0
local manualStamina = 100.0

-- How long the derived reading has been outside 0..100.
--
-- A value outside that range is PROOF the interpretation is wrong — not a
-- guess, a contradiction. The detection above can latch the wrong convention on
-- a build that reports something other than what either branch expects, and the
-- result is a reading like -15 that never moves. That is not a cosmetic bug:
-- exhaustionFrom(-15) clamps to FULL exhaustion, full exhaustion disables the
-- sprint control, and a player who cannot sprint can never move the native — so
-- the wrong reading holds itself in place forever and looks exactly like
-- "stamina does not drain".
--
-- The manual bar already exists for "this native is unusable". It just never
-- checked for this flavour of unusable.
local outOfRangeMs = 0

-- The native's full-scale value, LEARNED rather than assumed.
--
-- Measured on a real build: the depletion counter ran 0 .. 9.1 over one full
-- sprint. Not 0..1, not 0..100 — nine. And the ceiling is not fixed either, it
-- moves with the player's MP0_STAMINA stat, because a fitter character sprints
-- for longer before the counter tops out. No native reports that ceiling.
--
-- So assuming a scale cannot work on any build except the one it was guessed
-- for. At an assumed 0..100, a 0..9.1 native turned a full sprint into a move
-- from 100% to 91% — which is precisely what "stamina doesn't drain, it just
-- jitters" looks like from the outside.
--
-- Normalising against the largest value actually seen is correct for all three
-- ranges at once and needs no guess at all. It self-corrects: the first sprint
-- widens the range as it goes, and every sprint after it is accurate.
local staminaRange = 0.0
local RANGE_MIN = 0.05

-- ---- exhaustion state -------------------------------------------------------
-- Declared here rather than beside the exhaustion code below, because the
-- commands that report on it (/hudfatigue, /hudstamina) are registered in
-- between. A local declared after its reader is not an upvalue, it is a
-- different variable that happens to share a name — and in Lua that is a silent
-- nil rather than an error, so it only shows up when someone runs the command.
local exhaustLevel = 0.0      -- 0 = fresh, 1 = fully spent
local overExertMs  = 0.0      -- ms spent sprinting on empty
local lastVignette = -1

-- Accumulated over-exertion, 0..1. See Config.Exhaustion.fatigue.
--
-- Kept as its own value rather than folded into exhaustLevel because the two
-- answer different questions: exhaustLevel is "how empty are you right now",
-- fatigue is "how much have you spent without paying it back". The first
-- recovers the instant you stop; the second is the one that is supposed to
-- make repeatedly redlining yourself cost something.
local fatigue = 0.0

-- The most recent stamina reading, so the per-frame exhaustion thread can ask
-- "are they actually rested" without re-reading the native at a different
-- cadence than the status poll and disagreeing with the bar on screen.
local lastStaminaSeen = 100.0

-- Health this system has taken and has not given back yet.
--
-- Repayment is capped at this, so exhaustion can never hand out health it did
-- not first remove. That cap is the whole reason it is safe for a HUD to touch
-- health at all: it undoes its own effect and nothing else.
local fatigueDebt = 0.0

-- Sub-1 HP carried between frames, one accumulator per direction.
--
-- SetEntityHealth takes an INTEGER. At 0.25 hp/s and 60 fps a frame's drain is
-- 0.004 HP, and flooring that gives zero every single frame — the drain would
-- be exactly nothing, forever, while looking perfectly reasonable in the code.
local hpDrainCarry, hpHealCarry = 0.0, 0.0

--- Stamina, with a guaranteed-working fallback.
---
--- GetPlayerSprintStaminaRemaining is inconsistently documented (remaining vs
--- depletion, 0..1 vs 0..100) AND can be pinned by any script calling
--- ResetPlayerStamina. Rather than keep guessing, this watches it: while the
--- player is actually sprinting, a rising value means depletion, a falling one
--- means remaining. If it does not move at all for STUCK_LIMIT of sprinting,
--- something is holding it and we switch to a self-managed model so the bar
--- still does something sensible.
local STUCK_LIMIT = 1500      -- ms of sprinting with a frozen native

-- Smallest movement counted as "the value changed", in the native's OWN units.
-- Detection runs before the scale is known, and a 0..1 native only ever moves a
-- few hundredths per tick — the old threshold of 0.5 was in 0..100 units, so it
-- could never fire on such a build and a perfectly good native got written off
-- as frozen. Stamina moves monotonically while sprinting, so a small epsilon is
-- safe: nothing here jitters.
local DETECT_EPS  = 0.005

-- Manual model state. `regenHoldMs` is the pause after you stop sprinting
-- before the bar starts coming back — without it the bar snaps to full the
-- instant you let go of sprint, which makes it read as decoration.
local regenHoldMs = 0.0

--- Seconds of sprint the player gets, lengthened by the stamina skill.
---
--- Read through the skills system rather than hardcoded so the two agree: it
--- would be odd for a maxed stamina skill to move the GTA stat and leave this
--- bar emptying at exactly the same rate it did on day one.
local function sprintSeconds()
    local sc = Config.Stamina or {}
    local base = tonumber(sc.sprintSeconds) or 12.0
    local bonus = tonumber(sc.skillBonus) or 0.0
    if bonus > 0.0 and type(SkillFitness) == 'function' then
        local ok, fit = pcall(SkillFitness)
        if ok and type(fit) == 'number' then
            base = base * (1.0 + (bonus * math.max(0.0, math.min(1.0, fit))))
        end
    end
    return math.max(1.0, base)
end

--- Returns the 0..100 reading and whether it can be TRUSTED.
---
--- Until the convention is latched the reading is a coin flip, and guessing
--- wrong turns a full bar into an empty one - which then sits on screen
--- permanently, because the bar shows whenever stamina is below 100. So the
--- second return value is false until an actual sprint has settled the
--- question, and the caller reports "full" (i.e. hides the bar) until then.
local function readStamina(ped, playerId, dtMs)
    -- THE NORMAL PATH ENDS HERE.
    --
    -- 'manual' is the default, and it is resolved before the native is even
    -- read. Everything below this point exists for servers that opt into
    -- `source = 'native'`, and it must not run otherwise — a build with an odd
    -- native would otherwise drag the self-managed bar around with it, which is
    -- the whole class of problem this default exists to avoid.
    if staminaMode == nil and (Config.Stamina and Config.Stamina.source) ~= 'native' then
        staminaMode = 'manual'
        manualStamina = 100.0
    end

    if staminaMode == 'manual' then
        local sc = Config.Stamina or {}
        local step = (dtMs / 1000.0)

        if IsPedSprinting(ped) then
            regenHoldMs = tonumber(sc.regenDelayMs) or 900
            manualStamina = math.max(0.0, manualStamina - (100.0 / sprintSeconds()) * step)
        elseif regenHoldMs > 0.0 then
            -- Catching your breath. Nothing comes back yet.
            regenHoldMs = regenHoldMs - dtMs
        else
            local refill = math.max(0.5, tonumber(sc.refillSeconds) or 9.0)
            manualStamina = math.min(100.0, manualStamina + (100.0 / refill) * step)
        end
        return manualStamina, true
    end

    -- ---- native interpretation (opt-in) -------------------------------------
    -- Detection works in the native's OWN units throughout. Scaling first meant
    -- the tick that latched the scale still returned the unscaled value, so a
    -- 0..1 build reported 0.6 instead of 60 for one tick after detection.
    local native = GetPlayerSprintStaminaRemaining(playerId) or 0.0

    -- Learn the range from EVERY reading, including the ones taken before the
    -- mode latched. Tracking it further down meant the first two or three
    -- samples of a sprint — which on a 'remaining' native are the LARGEST ones
    -- there are — were seen and thrown away, so full scale was whatever the
    -- value happened to be a tick after detection finished. That made a bar
    -- that read 50% at what was really 40%.
    if native > staminaRange then staminaRange = native end

    -- Anything above 1.0 settles it immediately: this build counts 0..100.
    if staminaScale == nil and native > 1.0 then staminaScale = 1.0 end

    local sprinting = IsPedSprinting(ped)

    if staminaMode == nil then
        if sprinting then
            if lastSprintRaw ~= nil then
                local delta = native - lastSprintRaw
                if delta > DETECT_EPS then
                    staminaMode = 'depletion'
                elseif delta < -DETECT_EPS then
                    staminaMode = 'remaining'
                else
                    sprintStuckMs = sprintStuckMs + dtMs
                    if sprintStuckMs >= STUCK_LIMIT then
                        staminaMode = 'manual'
                        manualStamina = 100.0
                        print('^3[vice_hud]^7 stamina: native never moved while sprinting '
                            .. '(something is calling ResetPlayerStamina) — using a self-managed bar')
                    end
                end
                if staminaMode == 'depletion' or staminaMode == 'remaining' then
                    -- A whole sprint went by without a value above 1.0, so this
                    -- build really is reporting 0..1.
                    if staminaScale == nil then staminaScale = 100.0 end
                    -- staminaScale is informational now: the reading is
                    -- normalised against the observed range instead, because a
                    -- real build turned out to use neither of the two scales
                    -- this ever guessed between.
                    print(('^2[vice_hud]^7 stamina: native reports %s; range is being learned '
                        .. 'from what it actually does (run /hudstamina to see it)')
                        :format(staminaMode:upper()))
                end
            end
            lastSprintRaw = native
        else
            lastSprintRaw = nil
            sprintStuckMs = 0
        end
    end

    if staminaMode == nil then
        -- Still undecided. Config.StaminaIsDepletion is only a starting
        -- assumption, so report full rather than draw a bar off a reading that
        -- may well be inverted.
        return 100.0, false
    end

    -- The largest reading ever seen is full scale, in either mode: a depletion
    -- native tops out at full exertion, a remaining one when rested. Dividing
    -- by it removes the scale question entirely.
    if staminaRange < RANGE_MIN then
        -- Nothing meaningful seen yet. Report full and say it cannot be trusted
        -- rather than divide by something indistinguishable from zero.
        return 100.0, false
    end

    local frac = native / staminaRange
    local value = staminaMode == 'depletion' and (100.0 * (1.0 - frac)) or (100.0 * frac)

    -- A small overshoot is legitimate: a depletion native that does not stop at
    -- 100 puts this a point or two under zero at the bottom of a sprint. A
    -- reading that sits well outside the range is something else entirely.
    -- Normalising makes this unreachable for a well-behaved native, since frac
    -- cannot exceed 1. It stays because a NEGATIVE reading still can: that is
    -- neither a remaining value nor a depletion one, and it is the shape the
    -- original -15% report took.
    if value < -2.0 or value > 102.0 then
        outOfRangeMs = outOfRangeMs + dtMs
        if outOfRangeMs >= STUCK_LIMIT then
            staminaMode = 'manual'
            manualStamina = 100.0
            outOfRangeMs = 0
            print(('^3[vice_hud]^7 stamina: the native reads %.2f against a learned range of '
                .. '%.2f, which works out as %.1f%% — outside 0..100, so this build is '
                .. 'reporting something neither convention describes.')
                :format(native, staminaRange, value))
            print('  Switched to the self-managed bar. Run /hudstamina to see what the')
            print('  native is actually doing and report it if the bar feels wrong.')
            return manualStamina, true
        end
    else
        outOfRangeMs = 0
    end

    -- Clamped unconditionally. Everything downstream — the bar, exhaustion,
    -- fatigue, the health drain — is written against 0..100 and none of it
    -- should have to defend itself against a reading that is not.
    return math.max(0.0, math.min(100.0, value)), true
end

-- =============================================================================
-- Oxygen
-- =============================================================================
-- Breath shares the stamina row instead of adding a fourth bar -- see
-- Config.Oxygen for why that is safe. All this half has to do is answer "how
-- much breath, or none of your business because we are not underwater".
--
-- GetPlayerUnderwaterTimeRemaining returns SECONDS remaining, and nothing
-- reports the maximum: it moves with the lung-capacity stat and with any script
-- calling SetPedMaxTimeUnderwater. Hardcoding 10 would read wrong for every
-- trained character, so the ceiling is SAMPLED at the surface, where the native
-- reads full -- the same choice the stamina reader makes when it learns its
-- range rather than assuming one.
--
-- The sample is the largest reading over a short WINDOW of surfaced ticks, not
-- the largest ever seen. An all-time high is wrong on any server with dive gear:
-- um_divegear sets the maximum to 2000s with a tank on and back to 1s with it
-- off, so a latch that only ever grows would keep 2000 forever and read every
-- later unequipped dive as instantly empty. A window still spans the refill that
-- follows surfacing -- which is the reason not to just take the latest reading --
-- while letting the ceiling follow the gear back down.
local oxygenSamples = {}    -- recent SURFACED readings, oldest first
local oxygenMax = nil       -- largest of those, or nil before the first sample
local diveCeiling = nil     -- the ceiling in use for the dive currently underway

--- How many surfaced ticks the window holds.
local function oxygenWindow()
    local ms = (Config.Oxygen and Config.Oxygen.ceilingWindowMs) or 3000
    -- At least two, so a window shorter than one tick still averages something
    -- rather than degenerating into "the latest reading".
    return math.max(2, math.ceil(ms / (Config.Tick or 250)))
end

--- Record a surfaced reading and recompute the ceiling from the window.
local function sampleCeiling(v)
    oxygenSamples[#oxygenSamples + 1] = v
    -- Trimmed in a loop rather than once, so a Config.Tick change that shrinks
    -- the window takes effect immediately instead of leaving stale samples in.
    while #oxygenSamples > oxygenWindow() do table.remove(oxygenSamples, 1) end

    local m = oxygenSamples[1]
    for i = 2, #oxygenSamples do
        if oxygenSamples[i] > m then m = oxygenSamples[i] end
    end
    oxygenMax = m
end

--- Breath as 0..100, or nil when the player is not underwater.
---
--- nil is the mode switch: the page shows stamina on that row whenever the
--- oxygen key is absent, so exactly one value decides which state we are in and
--- there is nothing for two flags to disagree about.
local function readOxygen(ped, playerId)
    if not (Config.Oxygen and Config.Oxygen.enabled) then return nil end

    local remaining = GetPlayerUnderwaterTimeRemaining(playerId)
    if type(remaining) ~= 'number' then return nil end

    if not IsPedSwimmingUnderWater(ped) then
        -- Surfaced: the native is sitting at (or refilling toward) the full
        -- allowance, and this is the only place it can be observed.
        sampleCeiling(remaining)
        -- The dive is over, so the ceiling it was measured against goes with it.
        -- Holding it would carry a tank's 2000s into the next dive without one.
        diveCeiling = nil
        return nil
    end

    if not diveCeiling then
        -- First tick of a dive. Fix the ceiling now: sampling it mid-dive would
        -- read the draining value, and the bar would sit at 100% all the way
        -- down.
        diveCeiling = oxygenMax
        if not diveCeiling or diveCeiling <= 0.1 then
            diveCeiling = (Config.Oxygen and Config.Oxygen.defaultSeconds) or 10.0
        end
    end

    -- A dive can outlast the ceiling it started with, if gear went on in the
    -- water or the stat grew since the last surfacing. Believe the bigger number
    -- rather than clamping the bar to full and then dropping it in a step.
    if remaining > diveCeiling then diveCeiling = remaining end

    return math.max(0.0, math.min(100.0, (remaining / diveCeiling) * 100.0))
end

--- What the breath natives say right now, and what the bar does with it.
RegisterCommand('hudoxygen', function()
    local ped, playerId = cache.ped or PlayerPedId(), PlayerId()
    local raw = GetPlayerUnderwaterTimeRemaining(playerId)
    print(('^3[vice_hud]^7 underwater %s   breath %s   ceiling %s')
        :format(tostring(IsPedSwimmingUnderWater(ped)),
                type(raw) == 'number' and ('%.2fs'):format(raw) or tostring(raw),
                oxygenMax and ('%.2fs'):format(oxygenMax) or 'not sampled yet'))
    print(('  ceiling is the max of %d/%d surfaced samples; this dive is using %s')
        :format(#oxygenSamples, oxygenWindow(),
                diveCeiling and ('%.2fs'):format(diveCeiling) or 'nothing yet'))
    local pct = readOxygen(ped, playerId)
    print(('  the stamina row is showing %s')
        :format(pct and ('oxygen, %.0f%%'):format(pct) or 'stamina (not submerged)'))
end, false)

-- =============================================================================
-- Needs -- hunger and thirst
-- =============================================================================
-- Hunger and thirst have no bars of their own. They cap the HEALTH bar: below
-- Config.Needs.warnAt a darkened tail grows in from the right end of the health
-- track, marking health that cannot be healed back into until the player eats or
-- drinks. See Config.Needs for why a threshold rather than a permanent tail.
--
-- Both values come from the QBX statebags directly. qbx_core mirrors every
-- SetMetaData write into LocalPlayer.state.hunger / .thirst, so this is the same
-- number every other resource on the server is working from, with no bridge
-- event to subscribe to and nothing to ask the server for.

--- The health cap as 0..100 and which stat caused it, or nil when there is none.
---
--- nil is the signal, exactly as it is for oxygen: no cap key in the payload
--- means no tail, so one value decides it and nothing can disagree.
local function readNeeds()
    local cfg = Config.Needs
    if not (cfg and cfg.enable) then return nil end

    local hunger, thirst = LocalPlayer.state.hunger, LocalPlayer.state.thirst

    -- Before a character is loaded both are nil, and absent is NOT zero: reading
    -- a missing statebag as empty would cap every player at the floor for the
    -- first few seconds of every session. One present and one missing is treated
    -- as the missing one being fine, so a half-loaded state caps on what it
    -- actually knows.
    local haveNeeds = type(hunger) == 'number' or type(thirst) == 'number'
    hunger = type(hunger) == 'number' and math.max(0.0, math.min(100.0, hunger)) or 100.0
    thirst = type(thirst) == 'number' and math.max(0.0, math.min(100.0, thirst)) or 100.0

    -- The hunger/thirst cap, or nil if neither statebag exists yet or neither
    -- is low enough to bite.
    local needsCap, needsCause = nil, nil
    local warnAt = cfg.warnAt or 25
    if haveNeeds and warnAt > 0 then
        -- Ties go to hunger so the tint is deterministic, rather than depending
        -- on which of the two statebags happened to replicate last.
        local low, cause = hunger, 'hunger'
        if thirst < hunger then low, cause = thirst, 'thirst' end

        if low < warnAt then
            local floorPct = math.max(0.0, math.min(100.0, cfg.floorPct or 40))
            local t = (warnAt - low) / warnAt      -- 0 at the threshold, 1 at empty
            local rawCap = 100.0 - t * (100.0 - floorPct)
            needsCap, needsCause = math.max(floorPct, math.min(100.0, rawCap)), cause
        end
    end

    -- The flat regen ceiling applies whether or not hunger/thirst are involved
    -- at all -- it is a separate cap, not one more input into the same cap.
    -- Whichever of the two is lower is the one that actually limits healing.
    local ceiling = cfg.regenCeilingPct
    if ceiling and ceiling < 100.0 then
        ceiling = math.max(0.0, math.min(100.0, ceiling))
        if not needsCap or ceiling < needsCap then
            return ceiling, 'health'
        end
    end

    return needsCap, needsCause
end

-- What health settled at last tick, so a gain can be told from a loss. nil means
-- there is no baseline yet: on the first tick, and after every death.
local lastHealthRaw = nil

--- Hold health at the cap.
---
--- This blocks passive regeneration and nothing else. It never LOWERS health --
--- going hungry at full health costs nothing until the player takes a hit -- and
--- it never fights a deliberate heal, which is told apart from regeneration by
--- size rather than by asking the framework who is dead. See Config.Needs.
local function enforceCap(ped, cap, maxHp)
    local cfg = Config.Needs
    if not (cfg and cfg.enable and cfg.enforce) then
        lastHealthRaw = nil
        return
    end

    -- Death settles everything. Respawn hands back full health, and a baseline
    -- carried across it would read that as regeneration and claw it straight
    -- back off -- reviving players at the cap, looking exactly like a bug.
    if IsEntityDead(ped) then
        lastHealthRaw = nil
        return
    end

    -- A consumable is actively healing (health_items). Its ticks are small by
    -- design, so the size heuristic below can't tell them apart from passive
    -- regen -- this flag is the resource saying "this one's deliberate"
    -- directly instead. Track the baseline so enforcement resumes cleanly
    -- once it's done, but don't fight it while it's running.
    local raw = GetEntityHealth(ped)
    if type(raw) ~= 'number' then return end

    if LocalPlayer.state.healingItemActive then
        lastHealthRaw = raw
        return
    end

    -- First tick, or the first after a death. Adopt what we find: enforcing
    -- against a baseline that was never measured is guessing.
    if not lastHealthRaw then
        lastHealthRaw = raw
        return
    end

    local span = maxHp - 100
    if not cap or cap >= 100.0 or span <= 0 then
        lastHealthRaw = raw
        return
    end

    local gained = raw - lastHealthRaw
    if gained <= 0 then
        -- Damage, or nothing at all. Never our business.
        lastHealthRaw = raw
        return
    end

    -- Measured in points of the 0..100 bar rather than raw health, because
    -- maximum health is not always 200.
    if (gained / span) * 100.0 > (cfg.healJumpPct or 10) then
        -- A medkit, a revive, a script setting health outright. Not ours to undo.
        lastHealthRaw = raw
        return
    end

    local capRaw = math.floor(100 + (cap / 100.0) * span)
    -- max(), not capRaw alone: health already above the cap when the player got
    -- hungry is left where it is. The cap stops healing, it does not take.
    local allowed = math.max(lastHealthRaw, capRaw)
    if raw > allowed then
        SetEntityHealth(ped, allowed)
        lastHealthRaw = allowed
    else
        lastHealthRaw = raw
    end
end

--- Where the needs stand and what the health bar is doing about it.
RegisterCommand('hudneeds', function()
    local cfg = Config.Needs or {}
    print(('^3[vice_hud]^7 hunger %s   thirst %s   (warnAt %s, floor %s%%, enforce %s)')
        :format(tostring(LocalPlayer.state.hunger), tostring(LocalPlayer.state.thirst),
                tostring(cfg.warnAt), tostring(cfg.floorPct), tostring(cfg.enforce)))
    local cap, cause = readNeeds()
    if cap then
        print(('  capped at %.0f%% by %s; the tail covers the top %.0f%% of the bar')
            :format(cap, cause, 100 - cap))
    else
        print('  no cap -- both are above the threshold, so the health bar is untouched')
    end
    print(('  regen baseline: %s'):format(tostring(lastHealthRaw)))
end, false)

-- =============================================================================
-- Suppress GTA's native HUD
-- =============================================================================
-- Runs every frame: both DisplayHud and HideHudComponentThisFrame reset each
-- tick, so this has to be a per-frame thread rather than a one-shot.
CreateThread(function()
    while true do
        Wait(0)
        if Config.HideNativeHealthBars then
            -- Hides ONLY the health/armour bars drawn around the minimap, via the
            -- minimap scaleform's own SETUP_HEALTH_ARMOUR method (param 3 = hide
            -- both). This is what nbk_circle does.
            --
            -- The previous approach was DisplayHud(false), which also killed the
            -- radio, help text, subtitles and native notifications — that is what
            -- broke the in-vehicle radio display.
            if not minimapScaleform or not HasScaleformMovieLoaded(minimapScaleform) then
                minimapScaleform = RequestScaleformMovie('minimap')
            else
                BeginScaleformMovieMethod(minimapScaleform, 'SETUP_HEALTH_ARMOUR')
                ScaleformMovieMethodAddParamInt(3)
                EndScaleformMovieMethod()
            end
        end
        for i = 1, #Config.HiddenHudComponents do
            HideHudComponentThisFrame(Config.HiddenHudComponents[i])
        end
    end
end)

-- =============================================================================
-- Main loop
-- =============================================================================

local lastWanted = -1
local lastSpotted = false
local lastTellsKey = ''

--- True when a police ped actually has line of sight to the player.
--- This is what separates "they are hunting for you" (stars flash) from
--- "they can see you" (stars go solid red).
local function copsCanSeeMe(ped)
    if GetPlayerWantedLevel(PlayerId()) <= 0 then return false end
    local me = GetEntityCoords(ped)
    for _, cop in ipairs(GetGamePool('CPed')) do
        if cop ~= ped and not IsPedAPlayer(cop) and not IsPedDeadOrDying(cop, true)
           and GetPedRelationshipGroupHash(cop) == `COP` then
            if #(me - GetEntityCoords(cop)) < 90.0
               and HasEntityClearLosToEntity(cop, ped, 17) then
                return true
            end
        end
    end
    return false
end

--- Which of the outfit/voice/vehicle tells are still live, as an array of
--- strings matching html/app.js's TELL_SVG keys (array membership is the
--- signal — see renderTells()).
---
--- Backed by fenix-police's FenixPursuit.tells() when it's running: a real
--- comparison against what dispatch broadcast at the start of the pursuit
--- (see pursuit.lua's callItIn/tells), so changing clothes or switching cars
--- actually clears the matching tell. Falls back to "all three, always" —
--- this resource's original placeholder — when fenix-police isn't installed,
--- so a server without it sees the same thing this always showed.
local function getWantedTells(wanted)
    if wanted <= 0 then return {} end

    if GetResourceState('fenix-police') == 'started' then
        local ok, t = pcall(function() return exports['fenix-police']:GetTells() end)
        if ok and type(t) == 'table' then
            local out = {}
            if t.outfit then out[#out + 1] = 'outfit' end
            if t.voice then out[#out + 1] = 'voice' end
            if t.vehicle then out[#out + 1] = 'vehicle' end
            return out
        end
    end

    return { 'outfit', 'voice', 'vehicle' }
end

local lastCash = nil

-------------------------------------------------------------------------------
-- Police search-radius overlay (fed by fenix-police's contact model)
-------------------------------------------------------------------------------
-- Two AddBlipForRadius rings on the native minimap: an inner one at the fixed
-- "crime origin" size and an outer one tracking fenix-police's live, growing
-- search radius. Both are removed the moment fenix-police says contact is
-- regained (searchRadius drops to 0) or the player isn't wanted at all.
local searchInnerBlip, searchOuterBlip = nil, nil
local searchOuterRadius = nil -- radius the current outer blip was actually built with

local function clearSearchBlips()
    if searchInnerBlip then RemoveBlip(searchInnerBlip); searchInnerBlip = nil end
    if searchOuterBlip then RemoveBlip(searchOuterBlip); searchOuterBlip = nil end
    searchOuterRadius = nil
end

CreateThread(function()
    local cfgPS = Config.PoliceSearch
    if not cfgPS or not cfgPS.enable then return end

    local bounds -- { start, max }, fetched once from fenix-police and cached

    while true do
        Wait(cfgPS.pollMs or 1000)

        if GetResourceState(cfgPS.resource) ~= 'started' then
            clearSearchBlips()
            bounds = nil
            goto continue
        end

        if not bounds then
            local ok, b = pcall(function() return exports[cfgPS.resource]:SearchRadiusBounds() end)
            if ok and type(b) == 'table' then bounds = b end
        end

        do
            local ok, centre = pcall(function() return exports[cfgPS.resource]:SearchCentre() end)
            local okR, radius = pcall(function() return exports[cfgPS.resource]:SearchRadius() end)

            if not ok or type(centre) ~= 'table' or not okR or type(radius) ~= 'number' or radius <= 0 then
                clearSearchBlips()
            else
                -- ADD_BLIP_FOR_RADIUS has no "resize" native, so a moving radius
                -- means delete-and-recreate. Only bother once it has actually
                -- moved enough to be visible on the minimap.
                if (not searchOuterRadius) or (math.abs(radius - searchOuterRadius) > 2.0) then
                    clearSearchBlips()

                    local innerRadius = math.min((bounds and bounds.start) or radius, radius)

                    searchInnerBlip = AddBlipForRadius(centre.x, centre.y, centre.z, innerRadius)
                    SetBlipColour(searchInnerBlip, cfgPS.innerColour or 1)
                    SetBlipAlpha(searchInnerBlip, cfgPS.innerAlpha or 120)
                    SetBlipAsShortRange(searchInnerBlip, false)

                    searchOuterBlip = AddBlipForRadius(centre.x, centre.y, centre.z, radius)
                    SetBlipColour(searchOuterBlip, cfgPS.outerColour or 1)
                    SetBlipAlpha(searchOuterBlip, cfgPS.outerAlpha or 45)
                    SetBlipAsShortRange(searchOuterBlip, false)

                    searchOuterRadius = radius
                end
            end
        end

        ::continue::
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearSearchBlips() end
end)

-------------------------------------------------------------------------------
-- Duffle bag value (fed by wasabi_backpack's per-stash sell-price sum)
-------------------------------------------------------------------------------
CreateThread(function()
    local cfgD = Config.Duffle
    if not cfgD or not cfgD.enable then return end

    local lastDuffleValue = 'unset' -- distinct from nil, so the first hide still fires ui()

    local function pushDuffle(value)
        if value == lastDuffleValue then return end
        lastDuffleValue = value
        ui('duffle', { value = value })
    end

    while true do
        Wait(cfgD.pollMs or 3000)

        if GetResourceState(cfgD.resource) ~= 'started' then
            pushDuffle(nil)
            goto continue
        end

        -- Cheap local check first: no point round-tripping to the server for
        -- a player who isn't even carrying the item.
        local ok, count = pcall(function() return exports.ox_inventory:Search('count', cfgD.item) end)
        if not ok or not count or count < 1 then
            pushDuffle(nil)
            goto continue
        end

        local ok2, value = pcall(function()
            return lib.callback.await('wasabi_backpack:getDuffleValue', 500)
        end)
        pushDuffle((ok2 and type(value) == 'number') and value or nil)

        ::continue::
    end
end)

CreateThread(function()
    loadMinimapPref()
    loadMapState()
    local savedOffset = tonumber(GetResourceKvpString(KVP_OFFSET) or '')
    Wait(500)
    applyMinimap(true)

    -- AddReplaceTexture (and so the mask swap) does NOT survive a fresh game
    -- session, only a same-session resource restart — but the maskAppliedDict
    -- KVP it's seeded from can't tell those two apart, so on a genuine rejoin
    -- the code above believed the mask was already stamped and skipped
    -- applyMask entirely. That is why the mask only ever came back after
    -- opening /movehud and nudging the corner radius: THAT triggers the
    -- watchdog's "wrong dict" branch and forces a real reapply. Force the same
    -- real remove+reapply here on every start instead of trusting the flag.
    if Config.MinimapMask and not maskBusy then
        maskBusy = true
        CreateThread(function()
            if maskApplied then removeMask() end
            maskApplied = true
            applyMask()
            maskBusy = false
        end)
    end

    if savedOffset then applyOffset(savedOffset) end

    while true do
        Wait(Config.Tick)

        -- A single bad read (nil entity mid-restart, a stray arithmetic error)
        -- must not kill this thread forever — without the pcall it did, and
        -- the whole status/wanted/cash/vehicle stack went dark until a manual
        -- resource restart, with nothing on screen to say why.
        local ok, err = pcall(function()
        local ped = cache.ped or PlayerPedId()
        local playerId = PlayerId()

        -- ---- status -------------------------------------------------------
        -- GTA puts 100 at dead, not 0. The ceiling is 200 by default but a
        -- server can move it, and hardcoding 200 left the bar a few percent
        -- short of full on any server that did — so it never reached 100 and
        -- never hid itself.
        local maxHp = GetEntityMaxHealth(ped)
        if not maxHp or maxHp <= 100 then maxHp = 200 end

        -- The hunger/thirst cap, applied BEFORE health is read so the bar shows
        -- what the clamp settled on rather than trailing it by a tick.
        local cap, capCause = readNeeds()
        enforceCap(ped, cap, maxHp)

        local raw = GetEntityHealth(ped)
        local health = raw > 100 and ((raw - 100) / (maxHp - 100)) * 100 or 0

        -- `known` is false until a sprint has settled which convention the
        -- native uses; reporting full keeps the bar off screen until then.
        local stamina, staminaKnown = readStamina(ped, playerId, Config.Tick)
        if not staminaKnown then stamina = 100.0 end
        UpdateExhaustion(stamina)

        -- nil while surfaced, and an absent key is how the page knows the
        -- stamina row is showing stamina. Sent every tick either way, so
        -- surfacing switches the row back on the very next poll.
        local oxygen = readOxygen(ped, playerId)

        ui('status', {
            health  = math.floor(math.max(0, math.min(100, health))),
            focus   = math.floor(focusMeter),
            focusActive = focusActive,
            stamina = math.floor(math.max(0, math.min(100, stamina))),
            oxygen  = oxygen and math.floor(oxygen) or nil,
            -- Both absent unless there is a cap, so the tail's presence is the
            -- warning and no separate flag can contradict it.
            cap      = cap and math.floor(cap) or nil,
            capCause = cap and capCause or nil,
        })

        -- ---- wanted -------------------------------------------------------
        local wanted = GetPlayerWantedLevel(playerId)
        local spotted = wanted > 0 and copsCanSeeMe(ped) or false
        -- Computed every tick, not just when wanted/spotted change: a tell
        -- can clear (or reappear) mid-pursuit purely from the player changing
        -- clothes or vehicles, with wanted level and spotted state untouched.
        local tells = getWantedTells(wanted)
        local tellsKey = table.concat(tells, ',')
        if wanted ~= lastWanted or spotted ~= lastSpotted or tellsKey ~= lastTellsKey then
            lastWanted, lastSpotted, lastTellsKey = wanted, spotted, tellsKey
            ui('wanted', {
                active = wanted > 0,
                stars = wanted,
                maxStars = Config.MaxStars or 6,
                spotted = spotted,
                tells = tells,
            })
        end

        -- ---- weapon + ammo ------------------------------------------------
        -- The frames show clip/reserve for a ranged weapon and the icon alone
        -- for melee, so the ammo row is driven off whether the weapon takes
        -- ammo at all rather than off the count being non-zero.
        local _, wep = GetCurrentPedWeapon(ped, true)
        if wep and wep ~= `WEAPON_UNARMED` then
            local total  = GetAmmoInPedWeapon(ped, wep) or 0
            local inClip = select(2, GetAmmoInClip(ped, wep)) or 0
            local maxClip = select(2, GetMaxAmmoInClip(ped, wep, true)) or 0
            -- Icon comes from ox_inventory's own art via nui://, so the HUD and
            -- the inventory show the same image. WeaponIcons is generated in
            -- weapons.lua from ox_inventory/data/weapons.lua.
            local icon = WeaponIcons and WeaponIcons[wep] or nil
            if maxClip > 0 then
                ui('weapon', { armed = true, icon = icon, clip = inClip, reserve = math.max(0, total - inClip) })
            else
                ui('weapon', { armed = true, icon = icon })
            end
        else
            ui('weapon', { armed = false })
        end

        -- ---- money --------------------------------------------------------
        do
            local cash, bank
            local ok, pd = pcall(function() return exports.qbx_core:GetPlayerData() end)
            if ok and type(pd) == 'table' and type(pd.money) == 'table' then
                cash = pd.money.cash or pd.money.money
                bank = pd.money.bank
            end
            local key = tostring(cash) .. '|' .. tostring(bank)
            if key ~= lastCash then
                lastCash = key
                ui('cash', { cash = cash, bank = bank, show = true })
            end
        end

        -- ---- zone ---------------------------------------------------------
        checkZone(ped)

        -- ---- nav popup ------------------------------------------------------
        updateNav(ped)

        -- ---- vehicle ------------------------------------------------------
        -- The panel ANNOUNCES, then collapses. Getting into a car shows the
        -- full plate -- make, model, badge, status -- for a few seconds, and it
        -- then sheds everything that was the announcement and leaves the three
        -- status icons over the map for the rest of the drive. `panelUntil` is
        -- the announcement's deadline, set by the onCache('vehicle') handler so
        -- it re-triggers on every new vehicle.
        local vehicle = cache.vehicle
        if vehicle then
            DisplayRadar(true)
            veh.fuel = fuelLevel(vehicle)
            veh.engine = GetIsVehicleEngineRunning(vehicle)
            veh.lock = lockState(vehicle)
            -- Engine HEALTH as well as running/not, because "the engine is on"
            -- and "the engine is in one piece" are different questions and the
            -- pip is asked the second one. 1000 is factory-fresh, 0 is seized
            -- and on fire, and the native goes NEGATIVE for an engine beyond
            -- that -- so the page has to treat this as a number that can be
            -- below zero, not a percentage.
            veh.health = GetVehicleEngineHealth(vehicle) or 1000.0

            -- The panel is transient; the READINGS are not.
            --
            -- This used to stop pushing entirely once the announcement window
            -- closed, which was right when the panel was all there was. It is
            -- not right now: the collapsed strip keeps the fuel and engine
            -- gauges on screen for the whole drive, and a gauge nobody is
            -- feeding is worse than no gauge. So the push is unconditional
            -- while in a vehicle, and `collapsed` is what decides whether the
            -- page draws the whole plate or just the three icons.
            local full = panelUntil > 0 and GetGameTimer() < panelUntil
            if not full and panelUntil > 0 then
                -- Latch the window shut, once. `panelUntil` is only ever the
                -- announcement's deadline now, never "is anything showing".
                panelUntil = 0
            end
            ui('vehicle', {
                show = true, collapsed = not full,
                make = veh.make, model = veh.model,
                fuel = veh.fuel, engineOn = veh.engine, lockState = veh.lock,
                engineHealth = veh.health,
            })
            vehShown = true
        else
            -- `or editorOpen`: the editor's Minimap rows move and resize the
            -- native map, which is impossible to do by eye if the map is not
            -- drawn. Hidden again the moment the editor closes.
            DisplayRadar(minimapOnFoot or editorOpen)
            panelUntil = 0
            if vehShown then
                vehShown = false
                ui('vehicle', { show = false })
            end
        end
        end)
        if not ok then print('^1[vice_hud]^7 status tick error: ' .. tostring(err)) end
    end
end)

-- Resolve make/model once per vehicle rather than every tick, and cover the case
-- where the player is ALREADY in a vehicle when the resource starts (onCache
-- only fires on change, so without this the panel would stay blank until they
-- got out and back in).
lib.onCache('vehicle', function(value)
    if value then
        resolveVehicle(value)
        -- Start the transient window for the make/model panel.
        panelUntil = GetGameTimer() + Config.VehiclePanelMs
    end
end)

CreateThread(function()
    Wait(1000)
    if cache.vehicle then resolveVehicle(cache.vehicle) end
end)

-- Keep the minimap correct through resolution changes and screen-safe-zone
-- churn, and re-publish the rect so the NUI panels follow.
CreateThread(function()
    while true do
        Wait(500)
        -- Other HUD resources can reset these native component positions after
        -- this resource starts, and the safe-zone slider can move under us.
        -- Reassert ours so the map cannot silently grow back to another
        -- resource's scale. applyMinimap only messages the NUI when the
        -- resulting rect actually changes, so this is cheap to run on a timer.
        applyMinimap()
    end
end)

-- =============================================================================
-- Directional police lights
-- =============================================================================
-- Paints a red/blue glow on whichever screen edge an active siren is coming
-- from. Scans the vehicle pool on an interval (never per-frame) and pushes one
-- opacity per edge to the NUI, which does the pulsing in CSS.

--- Heading, in GTA's convention, from `from` to `to`.
--- GTA headings are degrees counter-clockwise from +Y (north), which is what
--- atan2(-dx, dy) produces directly.
local function headingTo(fromX, fromY, toX, toY)
    return math.deg(math.atan(-(toX - fromX), toY - fromY))
end

--- Wrap an angle into -180..180 so it can be compared as "how far off centre".
local function normaliseAngle(a)
    a = (a + 180.0) % 360.0
    if a < 0 then a = a + 360.0 end
    return a - 180.0
end

--- How strongly a siren at relative bearing `rel` lights each screen edge.
---
--- Spread across the two nearest edges rather than snapped to one. Snapping
--- meant a car circling you teleported between four fixed glows; weighting by
--- the cosine of the angle to each edge makes it sweep around the screen the
--- way the real light would. The opposite edge gets nothing, because cos is
--- negative there and is clamped away.
---
--- 0 is straight ahead; headings increase counter-clockwise, so positive is to
--- the LEFT of the camera.
local EDGE_ANGLE = { top = 0.0, left = 90.0, bottom = 180.0, right = -90.0 }

-- =============================================================================
-- Police light tuning  (/hudpolice edit)
-- =============================================================================
-- The FEEL of the effect — brightness, flash speed, lamp size/spread/drift,
-- edge focus, softness, and how far away it triggers — is editable in-game
-- instead of only in Config, because "does this look and trigger right" is a
-- judgement call nobody should have to make by editing numbers blind and
-- alt-tabbing to check. Config.PoliceLights still owns which vehicles count
-- and how often they're scanned: that's fixed behaviour, not feel, and has no
-- business being in this panel.
local KVP_POLICE = 'vice_hud:police'

local function defaultPoliceTune()
    return {
        -- 'edges'  four strips, tracking bearing
        -- 'radius' one lamp pair that tracks the exact bearing around the screen's perimeter
        -- 'custom' one lamp pair pinned exactly where you put it, ignoring bearing entirely
        mode         = 'edges',
        maxOpacity   = Config.PoliceLights.maxOpacity,
        flashMs      = Config.PoliceLights.flashMs,
        white        = Config.PoliceLights.white ~= false,
        whiteA       = 0.70,  -- white takedown alpha, 0-1
        whiteLampA   = 19,    -- white takedown ellipse radius, % of viewport (same axis convention as lampA/B)
        whiteLampB   = 30,
        lampA        = 16,    -- ellipse radius, % of viewport — same on every edge/position, never swapped
        lampB        = 24,
        spread       = 24,    -- edges: how far the two lamps sit from the edge midpoint, in %
                               -- radius: how far apart they sit around the perimeter, in degrees
        softness     = 68,    -- falloff stop, % — lower is a harder edge
        sweepAmt     = 1.6,   -- drift amplitude, vh/vw
        sweepMs      = 2600,  -- one drift cycle, ms
        focus        = Config.PoliceLights.focus or 1.6,   -- edges only: how tightly the glow hugs the nearest edge
        maxDistance  = Config.PoliceLights.maxDistance,    -- sirens further than this are ignored
        fullDistance = Config.PoliceLights.fullDistance,   -- full strength inside this range
        -- custom mode: fixed position of each lamp, % of viewport (0,0 = top-left)
        customRx = 15, customRy = 85,
        customBx = 85, customBy = 85,
        customWx = 50, customWy = 90,
    }
end

local PoliceTune = defaultPoliceTune()
do
    local raw = GetResourceKvpString(KVP_POLICE)
    if raw then
        local ok, dec = pcall(json.decode, raw)
        if ok and type(dec) == 'table' then
            for k, v in pairs(dec) do PoliceTune[k] = v end
        end
    end
end

local function savePoliceTune()
    local ok, enc = pcall(json.encode, PoliceTune)
    if ok then SetResourceKvp(KVP_POLICE, enc) end
end

-- Tracked with our own flag rather than IsNuiFocused(), for the same reason
-- the editor and skills panel do: another resource's legitimately focused
-- NUI must never be stolen out from under it.
local policeFocused = false
local policeEditorOpen = false

--- Pushes the current tunables to the NUI, plus whatever mode-specific
--- position/strength data `extra` carries (`edges` for edges mode, or
--- rx/ry/bx/by/wx/wy/strength for radius mode). One entry point for the real
--- scan and the editor's preview so they can never drift apart.
local function pushPoliceUi(active, extra)
    local payload = {
        active   = active,
        mode     = PoliceTune.mode or 'edges',
        flashMs  = PoliceTune.flashMs,
        white      = PoliceTune.white,
        whiteA     = PoliceTune.whiteA,
        whiteLampA = PoliceTune.whiteLampA,
        whiteLampB = PoliceTune.whiteLampB,
        lampA    = PoliceTune.lampA,
        lampB    = PoliceTune.lampB,
        spread   = PoliceTune.spread,
        softness = PoliceTune.softness,
        sweepAmt = PoliceTune.sweepAmt,
        sweepMs  = PoliceTune.sweepMs,
    }
    if type(extra) == 'table' then
        for k, v in pairs(extra) do payload[k] = v end
    end
    ui('police', payload)
end

local function clearPoliceUi()
    pushPoliceUi(false, { edges = { top = 0.0, right = 0.0, bottom = 0.0, left = 0.0 }, strength = 0.0 })
end

local function edgeWeights(rel, out)
    local focus = PoliceTune.focus or 1.6
    for edge, anchor in pairs(EDGE_ANGLE) do
        local d = math.rad(normaliseAngle(rel - anchor))
        local w = math.cos(d)
        out[edge] = w > 0.0 and (w ^ focus) or 0.0
    end
    return out
end

--- Maps a relative bearing to a point on the RECTANGLE the viewport forms
--- (not a circle or ellipse), so cardinal bearings land at the edge
--- midpoints exactly like edges mode, and diagonal bearings land exactly in
--- the corresponding corner instead of splitting into two separate edge
--- glows. Returns x, y as 0-100 (percent of viewport).
local function perimeterPoint(relDeg)
    local rad = math.rad(relDeg)
    -- 0 is straight ahead (top), positive is to the left, matching EDGE_ANGLE.
    local dx, dy = -math.sin(rad), -math.cos(rad)
    local t = 1.0 / math.max(math.abs(dx), math.abs(dy), 0.0001)
    return 50.0 + dx * t * 50.0, 50.0 + dy * t * 50.0
end

--- Shared detection math: walks active police sirens in range and calls
--- `fn(rel, strength)` for each one that's actually lighting something up.
--- Both scan modes below are just different ways of combining these calls —
--- the range, falloff and "which vehicles count" logic only lives here once.
local function forEachSiren(fn)
    local cfg = Config.PoliceLights
    local ped = cache.ped or PlayerPedId()
    local px, py = table.unpack(GetEntityCoords(ped))
    local camHeading = GetGameplayCamRot(2).z

    -- Clamped rather than trusted: the editor's two range sliders move
    -- independently, and a full-brightness range dragged past the detection
    -- range would divide by a negative number below.
    local maxDist  = PoliceTune.maxDistance or cfg.maxDistance
    local fullDist = math.min(PoliceTune.fullDistance or cfg.fullDistance, maxDist - 1)

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if cfg.classes[GetVehicleClass(vehicle)] then
            if (not cfg.requireSiren) or IsVehicleSirenOn(vehicle) then
                local vx, vy = table.unpack(GetEntityCoords(vehicle))
                local dist = #(vector2(px, py) - vector2(vx, vy))
                if dist <= maxDist then
                    local rel = normaliseAngle(headingTo(px, py, vx, vy) - camHeading)

                    -- Full strength inside fullDistance, linear fade to zero at
                    -- maxDistance.
                    local t = 1.0
                    if dist > fullDist then
                        t = 1.0 - ((dist - fullDist) / (maxDist - fullDist))
                    end
                    local strength = math.max(0.0, math.min(1.0, t)) * PoliceTune.maxOpacity
                    if strength > 0.0 then fn(rel, strength) end
                end
            end
        end
    end
end

--- Edges mode: strongest siren per edge wins; a single glow per edge reads
--- more clearly than summing several.
local function scanPoliceLightsEdges()
    local edges = { top = 0.0, right = 0.0, bottom = 0.0, left = 0.0 }
    local weights = { top = 0.0, right = 0.0, bottom = 0.0, left = 0.0 }
    local found = false

    forEachSiren(function(rel, strength)
        found = true
        edgeWeights(rel, weights)
        for edge, w in pairs(weights) do
            local v = strength * w
            if v > edges[edge] then edges[edge] = v end
        end
    end)

    return edges, found
end

--- Radius mode: only the single strongest siren gets to position the lamp —
--- averaging bearings from two different sirens would put the light
--- somewhere neither of them actually is.
local function scanPoliceLightsRadius()
    local bestStrength, bestRel, found = 0.0, 0.0, false

    forEachSiren(function(rel, strength)
        if strength > bestStrength then
            bestStrength, bestRel, found = strength, rel, true
        end
    end)

    return bestRel, bestStrength, found
end

CreateThread(function()
    local lastKey = nil
    while true do
        Wait(Config.PoliceLights.enable and Config.PoliceLights.scanMs or 2000)
        -- Skip real detection entirely while the editor is open: it drives its
        -- own preview, and the two pushing over each other every 250ms would
        -- flicker the panel between "your tuned preview" and "nothing nearby".
        if Config.PoliceLights.enable and not policeEditorOpen then
            local ok, err = pcall(function()
                if PoliceTune.mode == 'radius' or PoliceTune.mode == 'custom' then
                    -- Custom mode still uses the real scan for WHETHER a siren
                    -- is in range and HOW BRIGHT it should be — only the
                    -- position is pinned instead of tracking the bearing.
                    local rel, strength, found = scanPoliceLightsRadius()
                    local key = found and ('%.1f|%.2f'):format(rel, strength) or 'none'
                    if key ~= lastKey then
                        lastKey = key
                        if found then
                            local rx, ry, bx, by, wx, wy
                            if PoliceTune.mode == 'custom' then
                                rx, ry = PoliceTune.customRx, PoliceTune.customRy
                                bx, by = PoliceTune.customBx, PoliceTune.customBy
                                wx, wy = PoliceTune.customWx, PoliceTune.customWy
                            else
                                local half = PoliceTune.spread or 24
                                rx, ry = perimeterPoint(rel - half)
                                bx, by = perimeterPoint(rel + half)
                                wx, wy = perimeterPoint(rel)
                            end
                            pushPoliceUi(true, {
                                strength = strength, rx = rx, ry = ry, bx = bx, by = by, wx = wx, wy = wy,
                            })
                        else
                            clearPoliceUi()
                        end
                    end
                else
                    local edges, found = scanPoliceLightsEdges()

                    -- Only message the NUI when something actually changed,
                    -- rounded so tiny distance jitter doesn't spam every scan.
                    local key = ('%.2f|%.2f|%.2f|%.2f'):format(
                        edges.top, edges.right, edges.bottom, edges.left)
                    if key ~= lastKey then
                        lastKey = key
                        pushPoliceUi(found, { edges = edges })
                    end
                end
            end)
            if not ok then print('^1[vice_hud]^7 police light scan error: ' .. tostring(err)) end
        end
    end
end)

--- The editor's own preview. Edges mode lights both edges at the tuned
--- brightness. Radius mode holds still at `previewRel` — a real siren only
--- ever moves the lamp because YOU turned or it did, so the preview does not
--- spin on its own either; drag "Preview angle" to check a different corner.
local previewRel = -135.0  -- south-west, so the corner-merging is visible immediately
local function pushEditorPreview()
    if PoliceTune.mode == 'custom' then
        pushPoliceUi(true, {
            strength = PoliceTune.maxOpacity,
            rx = PoliceTune.customRx, ry = PoliceTune.customRy,
            bx = PoliceTune.customBx, by = PoliceTune.customBy,
            wx = PoliceTune.customWx, wy = PoliceTune.customWy,
        })
    elseif PoliceTune.mode == 'radius' then
        local half = PoliceTune.spread or 24
        local rx, ry = perimeterPoint(previewRel - half)
        local bx, by = perimeterPoint(previewRel + half)
        local wx, wy = perimeterPoint(previewRel)
        pushPoliceUi(true, {
            strength = PoliceTune.maxOpacity, rx = rx, ry = ry, bx = bx, by = by, wx = wx, wy = wy,
        })
    else
        pushPoliceUi(true, { edges = { top = 0.0, right = PoliceTune.maxOpacity, bottom = 0.0, left = PoliceTune.maxOpacity } })
    end
end

--- Closing the editor has to undo the preview and release focus, not just
--- hide the panel — the same reason /movehud's close does both.
local function closePoliceEditor()
    policeEditorOpen = false
    if policeFocused then
        policeFocused = false
        SetNuiFocus(false, false)
    end
    ui('policeEditor', { open = false })
    clearPoliceUi()
end

-- /hudpolice edit           opens the live-tuning panel
-- /hudpolice <edge> [0-1]   previews one edge without a real siren (edges mode only)
-- /hudpolice off            clears the preview
RegisterCommand('hudpolice', function(_, args)
    local edge = args[1]

    if edge == 'edit' then
        policeEditorOpen, policeFocused = true, true
        SetNuiFocus(true, true)
        ui('policeEditor', { open = true, values = PoliceTune, previewAngle = previewRel })
        pushEditorPreview()
        return
    end

    local amt  = tonumber(args[2]) or PoliceTune.maxOpacity
    local edges = { top = 0.0, right = 0.0, bottom = 0.0, left = 0.0 }
    if edge == 'off' then
        clearPoliceUi()
        print('^3[vice_hud]^7 police glow cleared')
        return
    end
    if edges[edge] == nil then
        print('^3[vice_hud]^7 usage: /hudpolice <top|right|bottom|left|off|edit> [0.0-1.0]')
        return
    end
    edges[edge] = amt
    pushPoliceUi(true, { edges = edges })
    print(('^3[vice_hud]^7 police glow: %s at %.2f'):format(edge, amt))
end, false)

RegisterNUICallback('policeTune', function(data, cb)
    if type(data) == 'table' and data.key ~= nil then
        PoliceTune[data.key] = data.value
        savePoliceTune()
    end
    if policeEditorOpen then pushEditorPreview() end
    cb(PoliceTune)
end)

RegisterNUICallback('policeMode', function(data, cb)
    if type(data) == 'table' and (data.mode == 'edges' or data.mode == 'radius' or data.mode == 'custom') then
        PoliceTune.mode = data.mode
        savePoliceTune()
    end
    if policeEditorOpen then pushEditorPreview() end
    cb(PoliceTune)
end)

--- The preview angle is deliberately NOT part of PoliceTune: it is a testing
--- aid for radius mode, not a setting, and has no business surviving into
--- the saved KVP.
RegisterNUICallback('policePreviewAngle', function(data, cb)
    if type(data) == 'table' and tonumber(data.angle) then
        previewRel = tonumber(data.angle)
    end
    if policeEditorOpen then pushEditorPreview() end
    cb({ ok = true })
end)

RegisterNUICallback('policeReset', function(_, cb)
    PoliceTune = defaultPoliceTune()
    DeleteResourceKvp(KVP_POLICE)
    if policeEditorOpen then pushEditorPreview() end
    cb(PoliceTune)
end)

RegisterNUICallback('policeEditorClose', function(_, cb)
    closePoliceEditor()
    cb({ ok = true })
end)

-- NUI focus is GLOBAL and survives this resource restarting, so a panel that
-- died holding it takes the player's hotbar keys with it until they rejoin.
-- Same safety net the editor and skills panel have, for the same reason.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if policeFocused then SetNuiFocus(false, false) end
end)

-- /hudfocus is the manual release for stranded NUI focus; it broadcasts this
-- so every panel in the resource clears itself rather than only one.
AddEventHandler('vice_hud:releaseFocus', function()
    policeFocused = false
    policeEditorOpen = false
end)

-- Preview without running yourself out:  /hudtired 0.8   |  /hudtired 0
--- Read or set accumulated fatigue.
---
--- A mechanic you cannot observe is a mechanic you cannot tune, and this one is
--- deliberately slow: it takes ~11 seconds at zero stamina to build up and only
--- unwinds once you are genuinely rested, so waiting for it to happen naturally
--- is a poor way to check whether it works at all.
---   /hudfatigue        print the live numbers
---   /hudfatigue 0.8    jump straight to that level
---   /hudfatigue reset  clear it
RegisterCommand('hudfatigue', function(_, args)
    local cfg = Config.Exhaustion
    local a = args[1]

    if a == 'reset' then
        fatigue = 0.0
        print('^2[vice_hud]^7 fatigue cleared')
    elseif tonumber(a) then
        fatigue = math.max(0.0, math.min(1.0, tonumber(a)))
    end

    local hurting = fatigue > cfg.fatigueHurtsAt
    local over = hurting
        and (fatigue - cfg.fatigueHurtsAt) / math.max(0.001, 1.0 - cfg.fatigueHurtsAt)
        or 0.0
    print(('^3[vice_hud]^7 fatigue %.3f   stamina %.1f   exhaustion %.3f')
        :format(fatigue, lastStaminaSeen, exhaustLevel))
    print(('  enabled %s   hurts above %.2f   %s')
        :format(tostring(cfg.fatigue), cfg.fatigueHurtsAt,
                hurting and ('COSTING %.2f hp/s right now'):format(cfg.fatigueHpPerSecond * over)
                         or 'not costing health'))
    print(('  rises %.3f/s at zero stamina; falls %.3f/s only once stamina >= %d')
        :format(cfg.fatigueRisePerSecond, cfg.fatigueFallPerSecond, cfg.fatigueRecoverAt))
    print(('  health floor %d (it wounds, it does not kill)'):format(100 + cfg.drainFloor))
    print(('  owed back %.1f hp   %s')
        :format(fatigueDebt,
                cfg.recoverHealth
                    and ('repaid at %.2f hp/s once stamina >= %d'):format(cfg.recoverHpPerSecond, cfg.fatigueRecoverAt)
                    or 'repayment is OFF — this health is gone until a medic'))
    if type(SkillFitness) == 'function' then
        local okFit, fit = pcall(SkillFitness)
        if okFit and type(fit) == 'number' then
            print(('  fitness %.2f from the stamina skill: rise x%.2f, recovery x%.2f')
                :format(fit, 1.0 - 0.5 * fit, 1.0 + 0.5 * fit))
        end
    end
end, false)

--- Watch GetPlayerSprintStaminaRemaining for a few seconds and report what it
--- actually does on THIS build.
---
--- The whole stamina reader is a guess about a native that is documented three
--- different ways, and every previous argument about it has been conducted
--- without data. This produces the data: sprint while it runs and it prints the
--- raw range, the direction, and what the current interpretation turns that
--- into. It also RE-ARMS detection, so a wrong latch can be corrected without a
--- resource restart.
RegisterCommand('hudstamina', function(_, args)
    local seconds = math.max(2, math.min(30, tonumber(args[1]) or 6))

    local function rearm()
        staminaMode, staminaScale = nil, nil
        lastSprintRaw, sprintStuckMs, outOfRangeMs = nil, 0, 0
        staminaRange, regenHoldMs = 0.0, 0.0
        manualStamina = 100.0
    end

    if args[1] == 'reset' then
        rearm()
        print('^2[vice_hud]^7 stamina re-armed')
        return
    end

    -- Switching without editing config.lua and restarting, because deciding
    -- which model suits a build is exactly the kind of thing you want to try
    -- both ways of in thirty seconds.
    if args[1] == 'manual' or args[1] == 'native' then
        Config.Stamina = Config.Stamina or {}
        Config.Stamina.source = args[1]
        rearm()
        print(('^2[vice_hud]^7 stamina source = %s (this session only — set it in '
            .. 'config.lua to keep it)'):format(args[1]))
        if args[1] == 'manual' then
            print(('  Self-managed: %.0fs to empty, %.0fs to refill, %dms pause first.')
                :format(Config.Stamina.sprintSeconds or 12, Config.Stamina.refillSeconds or 9,
                        Config.Stamina.regenDelayMs or 900))
        else
            print('  Reading the native. Sprint to let it work out the convention.')
        end
        return
    end

    if (Config.Stamina and Config.Stamina.source) ~= 'native' then
        print('^3[vice_hud]^7 stamina source is MANUAL — the native is not read at all,')
        print('  so sampling it tells you nothing about the bar on screen.')
        print(('  bar %.1f%%   %.0fs to empty (skill included), %.0fs to refill')
            :format(lastStaminaSeen, sprintSeconds(), (Config.Stamina or {}).refillSeconds or 9))
        print('  /hudstamina native   switch to reading the native, then sample it')
        return
    end

    print(('^3[vice_hud]^7 sampling the stamina native for %ds — SPRINT NOW'):format(seconds))
    print('  (source is NATIVE; /hudstamina manual switches to the self-managed bar)')
    print(('  current interpretation: mode %s   scale %s')
        :format(tostring(staminaMode), tostring(staminaScale)))

    CreateThread(function()
        local playerId = PlayerId()
        local lo, hi = math.huge, -math.huge
        local first, last
        local samples, sprintSamples = 0, 0
        local deadline = GetGameTimer() + seconds * 1000

        while GetGameTimer() < deadline do
            local v = GetPlayerSprintStaminaRemaining(playerId) or 0.0
            if first == nil then first = v end
            last = v
            if v < lo then lo = v end
            if v > hi then hi = v end
            samples = samples + 1
            if IsPedSprinting(cache.ped or PlayerPedId()) then
                sprintSamples = sprintSamples + 1
            end
            Wait(50)
        end

        print('^3[vice_hud]^7 ======== stamina native ========')
        print(('  samples %d   of which sprinting %d'):format(samples, sprintSamples))
        print(('  raw    first %.4f   last %.4f   min %.4f   max %.4f'):format(first or 0, last or 0, lo, hi))
        print(('  moved  %.4f  (%s)'):format(hi - lo,
            hi - lo < 0.0001 and 'FROZEN — something is calling ResetPlayerStamina'
            or (last > first and 'rose while sprinting => DEPLETION'
                             or 'fell while sprinting => REMAINING')))
        print(('  range  learned %.4f   (this sample topped out at %.4f)')
            :format(staminaRange, hi))
        print(('  mode %s   -> bar reads %.1f%%')
            :format(tostring(staminaMode), lastStaminaSeen))
        if staminaMode ~= 'manual' and staminaRange > 0 then
            print(('  a reading of %.4f is %.1f%% of the learned range')
                :format(last or 0, 100.0 * (last or 0) / staminaRange))
            print('  The range is the LARGEST value ever seen. If you have not yet')
            print('  sprinted to a standstill it is still an underestimate, and the')
            print('  bar will read low until you do — that corrects itself.')
        end
        if sprintSamples == 0 then
            print('  ^1You never sprinted.^7 Nothing above means anything — run it again')
            print('  and hold sprint for the whole window.')
        end
        print('  If the bar disagrees with the raw values, run /hudstamina reset')
        print('  and sprint again to re-arm detection.')
    end)
end, false)

RegisterCommand('hudtired', function(_, args)
    local lvl = tonumber(args[1])
    if not lvl then
        print('^3[vice_hud]^7 usage: /hudtired <0.0-1.0>')
        return
    end
    lvl = math.max(0.0, math.min(1.0, lvl))
    ui('exhaustion', {
        level = lvl,
        vignette = lvl * Config.Exhaustion.maxVignette,
        pulseMs = Config.Exhaustion.pulseMs,
    })
    print(('^3[vice_hud]^7 exhaustion preview: level %.2f  vignette %.3f')
        :format(lvl, lvl * Config.Exhaustion.maxVignette))
end, false)

-- =============================================================================
-- Exhaustion effects
-- =============================================================================
-- Gives the stamina bar consequences: the player slows as it empties, sprinting
-- is blocked once it is spent, and a mild vignette breathes in.
--
-- Driven by the same value the bar shows (see readStamina), so it stays honest
-- whether that value comes from the native or the self-managed fallback.

-- The exhaustion state itself is declared UP with the stamina reader, because
-- /hudfatigue and /hudstamina are registered between here and there and both
-- read it. Declared here, those commands closed over globals instead: nil, and
-- an immediate error out of string.format the first time either was run.

--- Take health, remembering how much so it can be given back.
local function takeHealth(ped, amount, floorHp)
    if amount <= 0.0 then return end
    hpDrainCarry = hpDrainCarry + amount
    if hpDrainCarry < 1.0 then return end

    local whole = math.floor(hpDrainCarry)
    hpDrainCarry = hpDrainCarry - whole

    local hp = GetEntityHealth(ped)
    local newHp = math.max(floorHp, hp - whole)
    if newHp < hp then
        fatigueDebt = fatigueDebt + (hp - newHp)
        SetEntityHealth(ped, newHp)
    end
end

--- Give back what was taken, and not one point more.
local function repayHealth(ped, amount)
    if amount <= 0.0 or fatigueDebt <= 0.0 then return end
    hpHealCarry = hpHealCarry + math.min(amount, fatigueDebt)
    if hpHealCarry < 1.0 then return end

    local whole = math.floor(hpHealCarry)
    hpHealCarry = hpHealCarry - whole
    whole = math.min(whole, math.floor(fatigueDebt))
    if whole <= 0 then return end

    local hp = GetEntityHealth(ped)
    local maxHp = GetEntityMaxHealth(ped)
    local newHp = math.min(maxHp, hp + whole)
    if newHp > hp then
        fatigueDebt = math.max(0.0, fatigueDebt - (newHp - hp))
        SetEntityHealth(ped, newHp)
    else
        -- Already at full: something else healed them. The debt is settled
        -- either way, and carrying it would mean handing out the same health
        -- twice the next time they took a scratch.
        fatigueDebt = 0.0
    end
end

--- 0..1 exhaustion from a 0..100 stamina reading.
local function exhaustionFrom(stamina)
    local cfg = Config.Exhaustion
    if stamina >= cfg.tiredAt then return 0.0 end
    return math.min(1.0, (cfg.tiredAt - stamina) / math.max(1, cfg.tiredAt))
end

CreateThread(function()
    while true do
        local cfg = Config.Exhaustion
        if not cfg.enable then
            Wait(1000)
        else
            Wait(0)
            local ok, err = pcall(function()
            local ped = cache.ped or PlayerPedId()
            local playerId = PlayerId()

            -- Push on with nothing left and it starts costing health. Gated on
            -- actually sprinting so standing still at 0 never hurts, floored so
            -- it can wound but not kill.
            local onFoot = not IsPedInAnyVehicle(ped, false)
            local dt = GetFrameTime()

            -- Death settles everything. Respawn hands back full health, so a
            -- debt carried across it would be health we never took, paid to
            -- someone who is already full.
            if IsEntityDead(ped) then
                fatigue, fatigueDebt = 0.0, 0.0
                hpDrainCarry, hpHealCarry = 0.0, 0.0
                overExertMs = 0.0
                goto continueExhaust
            end

            -- ---- fatigue ------------------------------------------------
            -- Rises with how spent you are, falls only once stamina is really
            -- back. A pause long enough to look recovered but not long enough
            -- to BE recovered banks nothing, which is the point.
            -- Being fit is worth something beyond the native stat: a trained
            -- player banks fatigue more slowly and sheds it faster. Guarded on
            -- the function existing, so the skills system being disabled or
            -- loading later cannot break exhaustion.
            local fit = 0.0
            if type(SkillFitness) == 'function' then
                local okFit, v = pcall(SkillFitness)
                if okFit and type(v) == 'number' then fit = math.max(0.0, math.min(1.0, v)) end
            end
            -- At full fitness: half the rise, half again the fall.
            local riseMul = 1.0 - (0.5 * fit)
            local fallMul = 1.0 + (0.5 * fit)

            if cfg.fatigue and onFoot then
                if exhaustLevel > 0.0 then
                    fatigue = math.min(1.0,
                        fatigue + cfg.fatigueRisePerSecond * exhaustLevel * riseMul * dt)
                elseif lastStaminaSeen >= cfg.fatigueRecoverAt then
                    fatigue = math.max(0.0, fatigue - cfg.fatigueFallPerSecond * fallMul * dt)
                end

                if fatigue > cfg.fatigueHurtsAt then
                    -- Ramped from nothing at the threshold to the full rate at
                    -- 1.0, so crossing the line warns before it bites.
                    local over = (fatigue - cfg.fatigueHurtsAt)
                                 / math.max(0.001, 1.0 - cfg.fatigueHurtsAt)
                    takeHealth(ped, cfg.fatigueHpPerSecond * over * dt, 100 + cfg.drainFloor)
                elseif cfg.recoverHealth and lastStaminaSeen >= cfg.fatigueRecoverAt then
                    -- Rested, and no longer in the red: pay it back. Gated on
                    -- the same "actually recovered" threshold that clears
                    -- fatigue, so catching your breath for two seconds does not
                    -- refund the cost of not having.
                    repayHealth(ped, cfg.recoverHpPerSecond * dt)
                end
            elseif not onFoot then
                -- Sitting in a vehicle is rest as far as this is concerned, and
                -- that includes paying the debt down.
                fatigue = math.max(0.0, fatigue - cfg.fatigueFallPerSecond * fallMul * dt)
                if cfg.recoverHealth then repayHealth(ped, cfg.recoverHpPerSecond * dt) end
            end

            -- ---- pushing on at zero -------------------------------------
            -- IsControlPressed, NOT IsPedSprinting. `spentAt` disables the
            -- sprint control before this threshold is reachable, so the ped is
            -- never sprinting here and this branch could never run — the whole
            -- health drain was dead code. Holding the key is what "still
            -- pushing" actually means once the game has stopped obeying it.
            if cfg.drainHealth and exhaustLevel >= 0.985
               and IsControlPressed(0, 21) and onFoot then
                overExertMs = overExertMs + dt * 1000.0
                if overExertMs > cfg.drainGraceMs then
                    takeHealth(ped, cfg.drainHpPerSecond * dt, 100 + cfg.drainFloor)
                end
            else
                overExertMs = 0.0
            end

            if exhaustLevel > 0.01 and onFoot then
                -- Slow them down on a curve rather than a cliff.
                local rate = 1.0 - ((1.0 - cfg.minMoveRate) * exhaustLevel)
                SetPedMoveRateOverride(ped, rate)

                -- Once spent, block sprint outright. INPUT_SPRINT is 21; the
                -- player can still walk and jog, they just cannot push it.
                if exhaustLevel >= 0.985 then
                    DisableControlAction(0, 21, true)
                end
            end

            ::continueExhaust::
            end)
            if not ok then print('^1[vice_hud]^7 exhaustion tick error: ' .. tostring(err)) end
        end
    end
end)

--- Called from the status poll so it shares the same stamina reading.
UpdateExhaustion = function(stamina)
    local cfg = Config.Exhaustion
    if not cfg.enable then return end

    lastStaminaSeen = stamina
    exhaustLevel = exhaustionFrom(stamina)

    -- The vignette shows whichever is worse: how empty you are RIGHT NOW, or
    -- how much exertion you have banked without paying it back. Without the
    -- second, fatigue would take health with nothing on screen explaining why —
    -- a mechanic the player cannot see is just unexplained damage.
    local shown = math.max(exhaustLevel, cfg.fatigue and fatigue or 0.0)

    -- Only message the NUI when the level actually moves, rounded so a jittery
    -- reading doesn't spam it every tick.
    local v = math.floor(shown * 20 + 0.5) / 20
    if v ~= lastVignette then
        lastVignette = v
        ui('exhaustion', {
            level    = v,
            vignette = v * cfg.maxVignette,
            pulseMs  = cfg.pulseMs,
        })
    end
end

-- =============================================================================
-- HUD editor
-- =============================================================================
-- Lets a player place every HUD element to suit their screen, and remembers it.
-- Offsets are in STAGE units (% of the centred 16:9 box), so a layout set at one
-- resolution still looks right at another.

-- Every element the editor and /hudmove can place. `speedlimit` and `seatbelt`
-- are owned by OTHER resources: vice_hud stores their offsets and broadcasts
-- them over the vice_hud:layout event, and each resource applies the offset to
-- its own NUI page.
local HUD_ELEMENTS = {
    status   = 'health / stamina bars (top-left)',
    topright = 'wanted stars, tells, ammo, weapon icon',
    money    = 'cash + bank (moves with topright)',
    tells    = 'the three round wanted tells',
    slots    = 'zone bar + vehicle panel, moved together',
    vehicle  = 'vehicle make/model panel (the upper one)',
    zone     = 'zone bar (the lower one)',
    vehpips  = 'lock / engine / fuel pips inside the vehicle panel',
    wanted   = '"cops are searching for you" box',
    honor    = 'honor standing (mugshot + face)',
    honorpop = 'centre-screen honor +/- indicator',
    reputation    = 'reputation standing (icon + track value)',
    reputationpop = 'centre-screen reputation +N indicator',
    prompts  = 'action prompts (bottom-right)',
    skillup  = 'skill level-up card',
    mapframe = 'minimap frame outline',
    speedlimit = 'speed limit sign (speedlimits resource)',
    seatbelt   = 'seatbelt icon (zseatbelt resource)',
    notify     = 'ox_lib notification popups (every resource)',
}

local KVP_BARS = 'vice_hud:barShape'

local barShape = GetResourceKvpString(KVP_BARS) or Config.StatusBarShape or 'pill'

local function pushHudConfig()
    ui('hudConfig', { barShape = barShape })
end

--- /hudbars            toggle pill <-> square
--- /hudbars pill|square  pick one
RegisterCommand('hudbars', function(_, args)
    local want = args[1]
    if want ~= 'pill' and want ~= 'square' then
        want = (barShape == 'pill') and 'square' or 'pill'
    end
    barShape = want
    SetResourceKvp(KVP_BARS, barShape)
    pushHudConfig()
    print(('^2[vice_hud]^7 status bars: %s'):format(barShape))
    lib.notify({ title = 'HUD', description = 'Status bars: ' .. barShape, type = 'success' })
end, false)

CreateThread(function()
    Wait(1400)          -- after the NUI is up
    pushHudConfig()
    -- Re-publish the map rect. applyMinimap suppresses an unchanged one, and
    -- its first push happens at Wait(500), which can beat the page being ready.
    lastRectKey = nil
    applyMinimap()
end)

local KVP_LAYOUT = 'vice_hud:layout'

-- Bumped when a saved layout stops meaning what it meant, exactly like
-- MAP_STATE_VERSION. Offsets are nudges away from where the HUD puts an element
-- by default, so if the default MOVES, every saved offset is now measured from
-- the wrong origin and re-applying it is worse than dropping it.
--   2  the minimap rect stopped double-counting the ultrawide offset. Anyone on
--      a wide monitor had nudged `slots` ~18% right to chase a zone bar that was
--      being positioned off the left of the screen; with the rect corrected,
--      that nudge would push it off the map in the other direction.
local LAYOUT_VERSION = 2
-- Seeded from Config.DefaultLayout so a player who has never opened /movehud
-- gets the tuned placement rather than the raw stylesheet. loadLayout REPLACES
-- this wholesale when a saved layout exists, so a player's own values are never
-- stacked on top of the defaults.
local function copyDefaultLayout()
    local out = {}
    for name, o in pairs(Config.DefaultLayout or {}) do
        local e = {}
        for k, v in pairs(o) do e[k] = v end
        out[name] = e
    end
    return out
end

local layout = copyDefaultLayout()

-- =============================================================================
-- Notification placement
-- =============================================================================
-- ox_lib draws notifications on its OWN NUI page, so no amount of CSS in this
-- resource can reach them. What CAN reach them is a small hook inside
-- ox_lib/resource/interface/client/notify.lua: that file is loaded into every
-- resource that calls lib.notify, so one hook covers all of them at once. It
-- reads two state bags and applies whichever it finds:
--
--   LocalPlayer.state['vice_hud:notify']   this player's own placement
--   GlobalState['vice_hud:notify']         the server-wide one (/hudpublish)
--
-- Personal wins over server-wide, matching how the rest of the layout works.
-- We publish the local bag here; server.lua owns the global one.
--
-- x/y are PERCENT OF THE SCREEN, never pixels, so a placement set on 1080p
-- lands in the same relative spot on 1440p or an ultrawide. Nothing is scaled:
-- the notification keeps whatever size ox_lib gives it.
local NOTIFY_ANCHORS = {
    'top-left', 'top', 'top-right',
    'center-left', 'center-right',
    'bottom-left', 'bottom', 'bottom-right',
}

local function notifyState()
    local o = layout.notify or {}
    local anchor = o.anchor
    -- Guard the anchor: it is the one field that is a NAME rather than a
    -- number, and ox_lib silently drops a notification whose position it does
    -- not recognise.
    local valid = false
    for _, a in ipairs(NOTIFY_ANCHORS) do
        if a == anchor then valid = true break end
    end
    if not valid then anchor = (Config.DefaultLayout.notify or {}).anchor or 'top-right' end
    return { anchor = anchor, x = o.x or 0.0, y = o.y or 0.0 }
end

--- Hand the current placement to every other resource. Cheap enough to call on
--- every nudge — a state bag write with an unchanged value is a no-op.
local function applyNotify()
    LocalPlayer.state:set('vice_hud:notify', notifyState(), false)
end

local function pushLayout()
    ui('layout', { offsets = layout })
    -- Broadcast so resources that own their own NUI can move too.
    TriggerEvent('vice_hud:layout', layout)
    applyNotify()
end

--- Other resources read their offset from here.
exports('GetHudOffset', function(name)
    local o = layout[name]
    return o and o.x or 0.0, o and o.y or 0.0, o and o.s or 1.0
end)

-- Arrow keys on the "Minimap position" / "Minimap size" rows land here. The
-- native map is engine-drawn, so CSS cannot touch it — we re-apply the
-- component values and force a scaleform rebuild instead.
--- A guard rail, not an opinion. It used to stop at 3.0, which is a taste
--- judgement dressed as a limit — and because the editor reports back whatever
--- this returns, hitting it looked exactly like the row being broken. The floor
--- is where the map stops having an area at all. Keep this in step with the
--- Map width / Map height rows in html/app.js.
local function clampMapScale(v)
    return math.max(0.01, math.min(20.0, tonumber(v) or 1.0))
end

--- Every native-minimap value the editor can tune, as plain numbers in the
--- units the panel shows them in.
---
--- The minimap is drawn by the engine, so none of this can be done in CSS. It
--- used to live only in chat commands, which meant the one part of the HUD that
--- needed the most fiddling was the one part you could not fiddle with in the
--- editor. Sending the values up front lets the panel show real numbers instead
--- of guessing at them.
local function nativeState()
    return {
        nudgeX = mapDx,
        nudgeY = mapDy,
        scaleW = mapScaleW,
        scaleH = mapScaleH,
        blipX  = blipDx * 1000.0,
        blipY  = blipDy * 1000.0,
        -- The map PLANE's own size, separate from Map width / Map height.
        --
        -- Map width/height scale the map, the mask and the blur together, which
        -- keeps them locked and is what you want for "make the minimap bigger".
        -- These two stretch only the `minimap` component — the plane the engine
        -- draws the world and its blips onto — while the mask window stays put.
        -- That is the ONLY control that changes the plane's aspect ratio, and a
        -- plane with the wrong aspect is what turns a radius blip's circle into
        -- an oval. They have always existed (/hudblip size) and were persisted,
        -- reset and printed by /mapinfo, but had no row in the editor, so the
        -- one thing that can fix a stretched blip was the one thing you could
        -- not reach from the tool built for fixing the map.
        blipW  = blipDw * 1000.0,
        blipH  = blipDh * 1000.0,
        blurX  = blurDx * 1000.0,
        blurY  = blurDy * 1000.0,
        blurW  = blurDw * 1000.0,
        blurH  = blurDh * 1000.0,
        north  = northBlip and 1 or 0,
        blipScale = playerBlipScale,
        blurMap = (blurMode == 'plane') and 1 or 0,
        cropT  = cropT * 1000.0,
        cropB  = cropB * 1000.0,
        cropL  = cropL * 1000.0,
        cropR  = cropR * 1000.0,
        rectL  = manualRect and manualRect.left   or Config.Minimap.left,
        rectW  = manualRect and manualRect.width  or Config.Minimap.width,
        rectB  = manualRect and manualRect.bottom or Config.Minimap.bottom,
        rectH  = manualRect and manualRect.height or Config.Minimap.height,
        rectManual = manualRect and 1 or 0,
        rounded = Config.MinimapMask and 1 or 0,
        radius  = maskRadius,
        zoom    = radarZoom,
        maskMap = (maskMode == 'map') and 1 or 0,
    }
end

--- Set one native value to an absolute number. Absolute rather than a delta so
--- the panel and the engine cannot drift apart if a message is dropped.
local function setNative(key, value)
    local v = tonumber(value)
    if not v then return end

    if key == 'nudgeX' then mapDx = px(v)
    elseif key == 'nudgeY' then mapDy = px(v)
    elseif key == 'scaleW' then mapScaleW = clampMapScale(v)
    elseif key == 'scaleH' then mapScaleH = clampMapScale(v)
    elseif key == 'blipX' then blipDx = v / 1000.0
    elseif key == 'blipY' then blipDy = v / 1000.0
    elseif key == 'blipW' then blipDw = v / 1000.0
    elseif key == 'blipH' then blipDh = v / 1000.0
    elseif key == 'blurX' then blurDx = v / 1000.0
    elseif key == 'blurY' then blurDy = v / 1000.0
    elseif key == 'blurW' then blurDw = v / 1000.0
    elseif key == 'blurH' then blurDh = v / 1000.0
    elseif key == 'blurMap' then blurMode = (v ~= 0) and 'plane' or 'config'
    elseif key == 'north' then northBlip = v ~= 0
    elseif key == 'blipScale' then playerBlipScale = math.max(0.0, v)
    elseif key == 'zoom' then radarZoom = math.max(0.0, v)
    elseif key == 'cropT' then cropT = math.max(0.0, v) / 1000.0
    elseif key == 'cropB' then cropB = math.max(0.0, v) / 1000.0
    elseif key == 'cropL' then cropL = math.max(0.0, v) / 1000.0
    elseif key == 'cropR' then cropR = math.max(0.0, v) / 1000.0
    elseif key == 'rectL' or key == 'rectW' or key == 'rectB' or key == 'rectH' then
        -- Touching any rect value switches the rect to manual: the derived one
        -- is all-or-nothing, so a half-overridden rect would be meaningless.
        manualRect = manualRect or {
            left = Config.Minimap.left, width = Config.Minimap.width,
            bottom = Config.Minimap.bottom, height = Config.Minimap.height,
        }
        -- The floor is 0.01 rather than 0.5 because 0.5 was a guess at "small
        -- enough", and the editor showed the guess back to you as if the number
        -- had not taken. A rect with no area is the only value that is actually
        -- unusable.
        if key == 'rectL' then manualRect.left = v
        elseif key == 'rectW' then manualRect.width = math.max(0.01, v)
        elseif key == 'rectB' then manualRect.bottom = v
        else manualRect.height = math.max(0.01, v) end
        Config.Minimap.left   = manualRect.left
        Config.Minimap.width  = manualRect.width
        Config.Minimap.bottom = manualRect.bottom
        Config.Minimap.height = manualRect.height
    elseif key == 'rounded' then
        -- The rounded shape comes from the mask TEXTURE, so this is the mask
        -- swap itself. applyMinimap reconciles the flag against the live swap,
        -- so flipping the flag is all that is needed.
        Config.MinimapMask = v ~= 0
    elseif key == 'radius' then
        -- Snapped, because only the baked steps exist as textures. The panel
        -- redraws from the value we report back, so it lands on a real step
        -- rather than showing a number no texture matches.
        maskRadius = snapMaskRadius(v)
        -- A radius is meaningless with the stock square mask, so asking for one
        -- turns the custom mask on rather than silently doing nothing.
        if not Config.MinimapMask then Config.MinimapMask = true end
    elseif key == 'maskMap' then
        maskMode = (v ~= 0) and 'map' or 'config'
    elseif key == 'rectManual' then
        if v == 0 then
            manualRect = nil
        else
            manualRect = manualRect or {
                left = Config.Minimap.left, width = Config.Minimap.width,
                bottom = Config.Minimap.bottom, height = Config.Minimap.height,
            }
        end
    else
        return
    end

    lastRectKey = nil
    applyMinimap(true)
    saveMapState()
end

RegisterNUICallback('mapTune', function(data, cb)
    if type(data) == 'table' and data.key then
        setNative(data.key, data.value)
    end
    cb(nativeState())
end)

RegisterNUICallback('mapAdjust', function(data, cb)
    if type(data) == 'table' then
        if data.dx then mapDx = px(mapDx + data.dx) end
        if data.dy then mapDy = px(mapDy + data.dy) end

        -- Resizing goes through mapScaleW/H rather than editing
        -- Config.MinimapComponent in place. The old version grew only `w` and
        -- `maskW` and left the mask/blur ratios to drift, so the mask stopped
        -- covering the map and the change read as "nothing happened, then the
        -- map went blurry at the edges". applyMinimap already multiplies all
        -- three components (map, mask, blur) by these, which keeps them
        -- locked together, and it means a reset is just "back to 1.0".
        if data.dw then mapScaleW = clampMapScale(mapScaleW + data.dw) end
        if data.dh then mapScaleH = clampMapScale(mapScaleH + data.dh) end
        if data.ds then
            mapScaleW = clampMapScale(mapScaleW * (1.0 + data.ds))
            mapScaleH = clampMapScale(mapScaleH * (1.0 + data.ds))
        end
        applyMinimap(true)
        -- Persist as you go. The map is engine state, not part of the layout
        -- preview, so cancelling the editor does not put it back — saving only
        -- on Enter meant a tuned map survived on screen but not to disk.
        saveMapState()
    end
    cb(nativeState())
end)

local function resetMinimap()
    mapDx, mapDy = 0, 0
    mapScaleW, mapScaleH = Config.MinimapScale or 1.0, Config.MinimapScale or 1.0
    maskMode = 'map'
    blipDx, blipDy, blipDw, blipDh = 0.0, 0.0, 0.0, 0.0
    blurDx, blurDy, blurDw, blurDh = 0.0, 0.0, 0.0, 0.0
    blurMode = 'plane'
    maskNudgeX, maskNudgeY = 0.0, 0.0
    radarZoom = 0.0
    northBlip = true
    playerBlipScale = 0.0
    pcall(function() SetBlipScale(GetMainPlayerBlipId(), 1.0) end)
    cropT, cropB, cropL, cropR = 0.0, 0.0, 0.0, 0.0
    maskRadius = snapMaskRadius(Config.MinimapCornerRadius or 8)
    manualRect = nil
    clipOverride = nil
    DeleteResourceKvp(KVP_MAP)
    applyMinimap(true)
end

-- "Reset this" / "Reset all" on a native row.
RegisterNUICallback('mapReset', function(_, cb)
    resetMinimap()
    cb(nativeState())
end)

-- Put the native map back to the config values without touching the rest of the
-- HUD layout. Worth having on its own: a bad size/nudge leaves the map looking
-- squashed or misaligned against its mask, and /hudreset is a bigger hammer.
RegisterCommand('mapreset', function()
    resetMinimap()
    print(('^2[vice_hud]^7 minimap restored to Config.MinimapComponent (scale %.2f, no nudge)')
        :format(Config.MinimapScale or 1.0))
    lib.notify({ title = 'HUD', description = 'Minimap reset', type = 'success' })
end, false)

--- Print exactly what the minimap is doing right now. Paste the output when
--- the map looks wrong — every value that decides its size and shape is here,
--- so it can be read rather than inferred from a screenshot.
RegisterCommand('mapinfo', function()
    local M = Config.MinimapComponent
    local rx, ry = GetActiveScreenResolution()
    local sz = GetSafeZoneSize()
    local aspect = rx / math.max(1, ry)

    -- The ultrawide correction applied on top of every x, so the printed
    -- component lines are what the ENGINE actually received, not the config.
    local DEFAULT_ASPECT = 1920.0 / 1080.0
    local uw = 0.0
    if aspect > DEFAULT_ASPECT then
        uw = ((DEFAULT_ASPECT - aspect) / 3.6) - 0.008
    end
    local fdx, fdy = (mapDx / rx) + uw, mapDy / ry

    print('^3[vice_hud]^7 ================ minimap ================')
    print(('  display      %dx%d   aspect %.4f   safeZoneSize %.3f')
        :format(px(rx), px(ry), aspect, sz))
    print(('  ultrawide    %+.6f  (0 on 16:9; credit Dalrae via qbx_hud)'):format(uw))
    print(('  scale        W %.3f  H %.3f        nudge  dx %d  dy %d px')
        :format(mapScaleW, mapScaleH, mapDx, mapDy))
    print(('  flags        NativeMinimap %s  Mask %s (applied %s)  maskMode %s  clip %s')
        :format(tostring(Config.NativeMinimap), tostring(Config.MinimapMask),
                tostring(maskApplied), maskMode, tostring(clipOverride or M.clipType or 0)))
    print(('  blip adjust  dx %+.4f  dy %+.4f   dw %+.4f  dh %+.4f   (/hudblip)')
        :format(blipDx, blipDy, blipDw, blipDh))
    print(('  blur adjust  dx %+.4f  dy %+.4f   dw %+.4f  dh %+.4f')
        :format(blurDx, blurDy, blurDw, blurDh))
    print(('  radar zoom   %s')
        :format(radarZoom > 0 and ('%d'):format(radarZoom) or "0 (GTA's own)"))
    print(('  vanilla map  north marker %s   player arrow %s')
        :format(northBlip and 'shown' or 'HIDDEN',
                playerBlipScale > 0 and ('%.2f'):format(playerBlipScale) or "GTA's own"))
    print(('  crop         top %+.4f  bottom %+.4f  left %+.4f  right %+.4f   (/hudcrop)')
        :format(cropT, cropB, cropL, cropR))
    print(('  NUI rect     %s'):format(manualRect
        and ('MANUAL  left %.2f%% width %.2f%% bottom %.2f%% height %.2f%%'):format(
            manualRect.left, manualRect.width, manualRect.bottom, manualRect.height)
        or 'derived from the safe zone (/hudslot to measure it by hand)'))
    print(('  saved KVP    %s'):format(GetResourceKvpString(KVP_MAP) or '(none)'))
    print('')
    -- Resolve the mask exactly as applyMinimap does, rather than echoing the
    -- config. Printing the raw config under this heading was actively
    -- misleading: in maskMode 'map' the engine gets the mask mirroring the map,
    -- not the config's mask values.
    local rmx, rmy, rmw, rmh
    if maskMode == 'map' then
        rmx, rmy, rmw, rmh = M.x * mapScaleW, M.y * mapScaleH, M.w, M.h
    else
        rmx, rmy, rmw, rmh = M.maskX, M.maskY, M.maskW, M.maskH
    end

    print('  What the engine is being told right now:')
    print(('    minimap      %+.4f %+.4f %.4f %.4f')
        :format((M.x * mapScaleW) + fdx + blipDx, (M.y * mapScaleH) + fdy + blipDy,
                (M.w * mapScaleW) + blipDw, (M.h * mapScaleH) + blipDh))
    print(('    minimap_mask %+.4f %+.4f %.4f %.4f')
        :format(rmx + fdx, rmy + fdy, rmw * mapScaleW, rmh * mapScaleH))
    -- Resolved the same way the mask above is, and for the same reason: in
    -- blurMode 'plane' (the DEFAULT) the engine gets the blur derived from the
    -- plane, not the config's blurX/Y/W/H. Printing the config values under
    -- "what the engine is being told right now" was simply untrue, and it is
    -- the line someone reads to decide whether the rects agree.
    local rbx, rby, rbw, rbh
    if blurMode == 'plane' then
        rbx = (M.x * mapScaleW) + fdx + blipDx + blurDx
        rby = (M.y * mapScaleH) + fdy + blipDy + blurDy
        rbw = (M.w * mapScaleW) + blipDw + blurDw
        rbh = (M.h * mapScaleH) + blipDh + blurDh
    else
        rbx = (M.blurX * mapScaleW) + fdx + blurDx
        rby = (M.blurY * mapScaleH) + fdy + blurDy
        rbw = (M.blurW * mapScaleW) + blurDw
        rbh = (M.blurH * mapScaleH) + blurDh
    end
    print(('    minimap_blur %+.4f %+.4f %.4f %.4f   (blurMode %s)')
        :format(rbx, rby, rbw, rbh, blurMode))
    print('')

    -- ---- coverage -----------------------------------------------------------
    -- How far the PLANE overhangs the MASK on each side.
    --
    -- This is the number that turns "the map is cut off" into something you can
    -- read, and it is the one thing /mapinfo never printed. The mask is the
    -- window; the plane is what is drawn behind it. So:
    --
    --   negative  the window is showing area the plane does not cover. That
    --             edge is CUT OFF, and no amount of nudging fixes it -- there
    --             is nothing there to move into view.
    --   zero      the two rects are flush. Nothing is cut off, but there is no
    --             slack either: the very first Blip X/Y nudge exposes an edge.
    --             This is what the SHIPPED defaults give you, because maskMode
    --             'map' makes the mask mirror the plane exactly.
    --   positive  spare map outside the window, which is what a blip nudge
    --             spends. THIS is what you need before centring the arrow.
    --
    -- Grow it with Plane width / Plane height in /movehud (blipW/blipH), which
    -- stretch the plane and leave the window alone.
    local planeL = (M.x * mapScaleW) + fdx + blipDx
    local planeB = (M.y * mapScaleH) + fdy + blipDy
    local planeR = planeL + (M.w * mapScaleW) + blipDw
    local planeT = planeB + (M.h * mapScaleH) + blipDh

    local maskL = rmx + fdx + maskNudgeX + cropL
    local maskB = rmy + fdy + maskNudgeY + cropB
    local maskR = maskL + (rmw * mapScaleW) - cropL - cropR
    local maskT = maskB + (rmh * mapScaleH) - cropT - cropB

    local ovL, ovR = maskL - planeL, planeR - maskR
    local ovB, ovT = maskB - planeB, planeT - maskT
    local worst = math.min(ovL, ovR, ovB, ovT)

    print('  Plane overhang past the mask (the slack a blip nudge spends):')
    print(('    left %+.1fpx   right %+.1fpx   bottom %+.1fpx   top %+.1fpx')
        :format(ovL * rx, ovR * rx, ovB * ry, ovT * ry))
    if worst < -0.0005 then
        print('    ^1CUT OFF^7 — a negative side means the window is showing area the')
        print('    plane does not cover. Grow the plane (Plane width / Plane height')
        print('    in /movehud) until every side is >= 0.')
    elseif worst < 0.0005 then
        print('    ^3FLUSH^7 — nothing is cut off, but there is no slack. The first')
        print('    Blip X / Blip Y nudge will expose an edge. If you need to centre')
        print('    the arrow, grow the plane FIRST (Plane width / Plane height),')
        print('    then nudge into the slack you just made.')
    else
        print('    ^2OK^7 — there is spare map on every side to nudge into.')
    end
    print('')

    if mapScaleW == 1.0 and mapScaleH == 1.0 and mapDx == 0 and mapDy == 0 then
        print('  Stock qbx_hud square-map values, unmodified.')
        print('  Size it with /movehud -> "Minimap size", then run /mapinfo again.')
    else
        print('  You have moved it off stock. To make this the default for')
        print('  everyone, paste into Config.MinimapComponent in config.lua:')
        print(('    w       = %8.4f,   h       = %8.4f,'):format(M.w * mapScaleW, M.h * mapScaleH))
        print(('    maskW   = %8.4f,   maskH   = %8.4f,'):format(M.maskW * mapScaleW, M.maskH * mapScaleH))
        print(('    blurW   = %8.4f,   blurH   = %8.4f,'):format(M.blurW * mapScaleW, M.blurH * mapScaleH))
        print(('  ...or just set Config.MinimapScale = %.3f and leave the ratios alone.')
            :format(mapScaleW))
        if mapScaleW ~= mapScaleH then
            print(('  NOTE: width and height are scaled differently (%.3f vs %.3f), so')
                :format(mapScaleW, mapScaleH))
            print('  MinimapScale alone cannot express this — use the w/h block above.')
        end
        if mapDx ~= 0 or mapDy ~= 0 then
            print(('  A %+d,%+d px nudge is also applied. It is stored per player;')
                :format(mapDx, mapDy))
            print('  /mapreset clears everything back to the config.')
        end
        print('')
        print(('  Report this line if the size should be generalised: %dx%d aspect %.4f safeZone %.3f scale %.3f/%.3f')
            :format(px(rx), px(ry), aspect, sz, mapScaleW, mapScaleH))
    end
    print('^3[vice_hud]^7 =========================================')
end, false)

-- Older name for the same report, kept so existing notes still work.
RegisterCommand('mapvalues', function()
    ExecuteCommand('mapinfo')
end, false)

--- /hudmaskmode            toggle between the two mask geometries
--- /hudmaskmode config|map    pick one explicitly
RegisterCommand('hudmaskmode', function(_, args)
    local want = args[1]
    if want ~= 'config' and want ~= 'map' then
        want = (maskMode == 'config') and 'map' or 'config'
    end
    maskMode = want
    saveMapState()
    applyMinimap(true)
    print(('^2[vice_hud]^7 mask mode = %s'):format(maskMode))
    print('  config = qbx_hud\'s mask window: NARROWER and TALLER than the map.')
    print('           That crop is deliberate. GTA draws the radar as a tilted 3D')
    print('           plane, and the crop keeps you on the well-behaved middle of')
    print('           it. Costs a blip that is off-centre by default.')
    print('  map    = mask mirrors the map. Shows the whole plane, including the')
    print('           steeply-angled edges, which can read as the map being skewed.')
    print('  If the map looks like it is at a weird ANGLE, try `config`, then')
    print('  re-centre the arrow with /hudblip.')
    lib.notify({ title = 'HUD', description = 'Mask mode: ' .. maskMode, type = 'inform' })
end, false)

--- Toggle vice_hud's minimap handling off/on without a restart. Off = GTA's
--- stock map, untouched. A restart is needed to put a swapped mask back.
RegisterCommand('hudnative', function()
    Config.NativeMinimap = not Config.NativeMinimap
    applyMinimap(true)
    if Config.NativeMinimap then
        print('^2[vice_hud]^7 native minimap: vice_hud is no longer touching the map.')
        print('  Anything still wrong with it comes from another resource or your')
        print('  Safe Zone Size setting. Restart the resource to undo the mask swap.')
    else
        print('^3[vice_hud]^7 vice_hud is positioning and masking the map again.')
    end
end, false)

--- Show/hide the NUI frame drawn on the map's intended rect. Turning it on is
--- the only practical way to aim the map: line the drawn map up inside it.
RegisterCommand('hudframe', function()
    Config.Minimap.showFrame = not Config.Minimap.showFrame
    applyMinimap(false)
    print(('^2[vice_hud]^7 map frame %s'):format(Config.Minimap.showFrame and 'ON' or 'off'))
end, false)

-- Last time the editor threw a sample notification up, so holding an arrow key
-- down does not fire one per frame.
local lastNotifyPreview = 0

RegisterNUICallback('layoutLive', function(data, cb)
    if type(data) == 'table' and type(data.offsets) == 'table' then
        TriggerEvent('vice_hud:layout', data.offsets)

        -- The notify row is the one element with nothing on screen to drag: a
        -- notification only exists while it is being shown. So show one. Without
        -- this you are nudging a number and hoping.
        if type(data.offsets.notify) == 'table' then
            layout.notify = data.offsets.notify
            applyNotify()
            local now = GetGameTimer()
            if editorOpen and now - lastNotifyPreview > 900 then
                lastNotifyPreview = now
                lib.notify({
                    id = 'vice_hud:preview',
                    title = 'Notifications',
                    description = 'This is where popups will appear.',
                    type = 'inform',
                    duration = 2500,
                })
            end
        end
    end
    cb({ ok = true })
end)

local function saveLayout()
    local ok, enc = pcall(json.encode, { v = LAYOUT_VERSION, offsets = layout })
    if ok then SetResourceKvp(KVP_LAYOUT, enc) end
    -- The two native-minimap rows in the editor are part of the same save.
    saveMapState()
end

-- Forward-declared: resetHudLayout has to re-apply the server-wide layout on
-- its way out, and applyServerLayout is defined below it, next to the rest of
-- the /hudpublish machinery.
local applyServerLayout

-- Restore the measured reference layout. Layout and horizontal-nudge values
-- are intentionally stored per player, so an old experimental adjustment can
-- otherwise survive resource updates and make a correct HUD look misplaced.
local function resetHudLayout()
    -- Back to the SHIPPED layout, not to nothing. "Reset" meaning "throw away
    -- the tuned placement and show the bare stylesheet" would be a worse
    -- starting point than the one the resource ships with.
    layout = copyDefaultLayout()
    DeleteResourceKvp(KVP_LAYOUT)
    DeleteResourceKvp(KVP_OFFSET)
    -- Reset means "give me what everyone else has", so the server-wide layout
    -- becomes eligible again.
    hasPersonalLayout = false
    hasPersonalMap = false
    -- Shares resetMinimap so /hudreset, /mapreset and the editor's "Reset all"
    -- land on the same place. This used to reset the map to scale 1.0 while the
    -- other two reset it to Config.MinimapScale.
    resetMinimap()
    applyOffset(0)
    if applyServerLayout then applyServerLayout(GlobalState['vice_hud:layout']) end
    pushLayout()
end

RegisterCommand('hudreset', function()
    resetHudLayout()
    lib.notify({ title = 'HUD', description = 'Reference layout restored', type = 'success' })
end, false)

--- Did this player ever save a layout of their own? Decides whether the
--- server-wide layout is allowed to overwrite an element (see applyServerLayout).
local hasPersonalLayout = false

local function loadLayout()
    local raw = GetResourceKvpString(KVP_LAYOUT)
    if not raw then return end
    local ok, dec = pcall(json.decode, raw)
    if not ok or type(dec) ~= 'table' then return end

    -- An unversioned save is the old bare offsets table, written before the
    -- minimap rect was corrected. Drop it rather than apply it.
    if tonumber(dec.v) ~= LAYOUT_VERSION or type(dec.offsets) ~= 'table' then
        DeleteResourceKvp(KVP_LAYOUT)
        print('^3[vice_hud]^7 discarded a saved HUD layout from an older version '
            .. '— elements are back at their default places. Re-run /movehud if '
            .. 'you had them where you wanted them.')
        return
    end

    layout = dec.offsets
    hasPersonalLayout = true
end

local function nudge(name, dx, dy)
    layout[name] = layout[name] or { x = 0.0, y = 0.0 }
    layout[name].x = (layout[name].x or 0.0) + dx
    layout[name].y = (layout[name].y or 0.0) + dy
end

--- /hudmove <element> <dx> <dy>   nudge by an amount (repeatable)
--- /hudmove <element> reset       clear just that element
--- /hudmove list                  show elements and current offsets
--- /hudmove reset                 clear everything
RegisterCommand('hudmove', function(_, args)
    local name = args[1]

    -- No arguments opens the EDITOR. `/hudmove` and `/movehud` are a keystroke
    -- apart and did completely different things, which is a trap; the menu is
    -- what people mean. `/hudmove list` still prints the text list.
    if not name then
        ExecuteCommand('movehud')
        return
    end

    if name == 'list' then
        print('^3[vice_hud]^7 /hudmove <element> <dx> <dy>   — nudge, in % of the 16:9 stage')
        print('               /hudmove <element> reset       — clear one')
        print('               /hudmove reset                 — clear all')
        print('  positive dx = right, positive dy = DOWN. Try 0.5 steps.')
        print('  elements:')
        for k, desc in pairs(HUD_ELEMENTS) do
            local o = layout[k]
            print(('    %-9s x=%+.2f y=%+.2f   %s')
                :format(k, o and o.x or 0.0, o and o.y or 0.0, desc))
        end
        return
    end

    if name == 'reset' then
        resetHudLayout()
        print('^2[vice_hud]^7 all HUD offsets and the horizontal nudge cleared')
        return
    end

    if not HUD_ELEMENTS[name] then
        print(('^1[vice_hud]^7 unknown element "%s" — run /hudmove list'):format(name))
        return
    end

    if args[2] == 'reset' then
        layout[name] = nil
        saveLayout(); pushLayout()
        print(('^2[vice_hud]^7 %s reset'):format(name))
        return
    end

    local dx, dy = tonumber(args[2]), tonumber(args[3])
    if not dx and not dy then
        print('^3[vice_hud]^7 usage: /hudmove ' .. name .. ' <dx> <dy>')
        return
    end

    nudge(name, dx or 0.0, dy or 0.0)
    saveLayout(); pushLayout()
    local o = layout[name]
    print(('^2[vice_hud]^7 %s now x=%+.2f y=%+.2f'):format(name, o.x, o.y))
end, false)

-- =============================================================================
-- Server-wide layout  (/hudpublish)
-- =============================================================================
-- Everything in /movehud is stored per player, which is right for a preference
-- and wrong for a mistake: if the shipped placement is off, every player on the
-- server sees it off and has to fix it themselves. /hudpublish takes whatever
-- the running player has tuned and makes it the DEFAULT for everyone.
--
-- The rule, per element, is "personal nudges win":
--   · a player who has never saved a layout gets the server one, whole
--   · a player who HAS saved one keeps every element they actually changed,
--     and picks up the server value for the elements they left alone
-- so publishing fixes the HUD for everyone without overwriting anyone's work.
--
-- The values are percentages of the screen, so nothing here is resolution- or
-- aspect-specific and nothing is ever rescaled: a 16:9 player and an ultrawide
-- player get the same element at the same relative place, at the same size.

--- Are two layout entries the same? Used to decide whether the player has
--- actually touched an element or is still sitting on the shipped default.
local function sameEntry(a, b)
    a, b = a or {}, b or {}
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end

--- Which published map profile applies to THIS display.
---
--- Three steps, and the order is the whole point:
---   1. the bucket this monitor is in, if it has been published;
---   2. otherwise the published bucket whose nominal aspect is nearest;
---   3. otherwise `sv.map`, the flat single-profile field.
---
--- (2) is a guess, but it is a guess between values that were each MEASURED on
--- a real screen, which is a different thing from computing one. (3) is what
--- keeps a layout.json published before any of this existed working unchanged,
--- and is also what a server with exactly one profile ends up using.
---
--- Deliberately no rescaling anywhere in here. INTERNALS.md records two
--- attempts to model this offset that were wrong in opposite directions.
---@param sv table
---@return table|nil
function pickMapForThisDisplay(sv)
    if type(sv) ~= 'table' then return nil end
    local maps = type(sv.maps) == 'table' and sv.maps or nil
    if not maps then return sv.map end

    local rx, ry = GetActiveScreenResolution()
    local aspect = rx / math.max(1, ry)
    local mine = Config.AspectBucket(aspect)

    if type(maps[mine]) == 'table' then return maps[mine] end

    -- Nearest published bucket. Compared on the NOMINAL aspect of each bucket
    -- rather than on this display's exact ratio, so the choice is stable: every
    -- 21:9 player picks the same neighbour regardless of whether their panel
    -- reports 2.3889 or 2.3703.
    local best, bestGap
    for name, m in pairs(maps) do
        if type(m) == 'table' then
            local nom = Config.AspectNominal(name)
            if nom then
                local gap = math.abs(nom - aspect)
                if not bestGap or gap < bestGap then best, bestGap = m, gap end
            end
        end
    end

    return best or sv.map
end

function applyServerLayout(sv)
    if type(sv) ~= 'table' then return end
    local defaults = Config.DefaultLayout or {}
    local took = 0

    if type(sv.offsets) == 'table' then
        for name, o in pairs(sv.offsets) do
            if type(o) == 'table' then
                -- Untouched means "still exactly what the resource shipped",
                -- which is the only thing we can compare against: the client
                -- never stored a per-element "the player edited this" flag.
                local untouched = not hasPersonalLayout or sameEntry(layout[name], defaults[name])
                if untouched then
                    local e = {}
                    for k, v in pairs(o) do e[k] = v end
                    layout[name] = e
                    took = took + 1
                end
            end
        end
    end

    -- The native map is all-or-nothing: its values are interdependent (mask,
    -- crop and component size only make sense together), so half a map from
    -- the server and half from the player would be a shape neither of them
    -- ever looked at.
    local svMap = pickMapForThisDisplay(sv)
    if type(svMap) == 'table' and not hasPersonalMap then
        if applyMapState(svMap) then
            lastRectKey = nil
            applyMinimap(true)
        end
    end

    if took > 0 then pushLayout() end
end

CreateThread(function()
    loadLayout()
    Wait(1200)          -- let the NUI come up first
    -- After loadLayout, so "has this player tuned it themselves" is already
    -- known, and after the wait, so the server has had time to replicate the
    -- global state to us.
    applyServerLayout(GlobalState['vice_hud:layout'])
    pushLayout()
end)

-- Someone published while we were connected. Re-run the same merge rather than
-- forcing a reconnect to pick it up.
AddStateBagChangeHandler('vice_hud:layout', 'global', function(_, _, value)
    if type(value) ~= 'table' then return end
    applyServerLayout(value)
end)

--- Push everything this player has tuned to the server as the new default.
--- Gated server-side on Config.PublishAce; the check here is only so the
--- refusal is immediate and explains itself.
RegisterCommand('hudpublish', function()
    local rx, ry = GetActiveScreenResolution()
    local aspect = rx / math.max(1, ry)
    TriggerServerEvent('vice_hud:publish', {
        offsets = layout,
        map = mapStateTable(),
        notify = notifyState(),
        -- Which display this map was tuned ON. The server files the map under
        -- this bucket so a player on the same kind of monitor gets it verbatim
        -- and nobody else is handed a shape measured for a different screen.
        -- See Config.AspectBuckets for why this is a bucket and not a formula.
        aspect = aspect,
        bucket = Config.AspectBucket(aspect),
    })
    print('^3[vice_hud]^7 sent this layout to the server. If you have permission it')
    print('  becomes the default for everyone; if you do not, nothing changes and')
    print('  the server prints why.')
end, false)

RegisterNetEvent('vice_hud:published', function(ok, why)
    lib.notify({
        title = 'HUD',
        description = ok and 'Layout published to the whole server' or (why or 'Not allowed'),
        type = ok and 'success' or 'error',
    })
    if not ok then print('^1[vice_hud]^7 publish refused: ' .. tostring(why)) end
end)

-- =============================================================================
-- /movehud — interactive editor
-- =============================================================================
-- Opens the NUI editor: pick an element from the list, move it with the arrow
-- keys (Shift for bigger steps), Enter to save, Esc to cancel. Far easier than
-- typing offsets, and the layout persists per player.

-- Closing the editor has to undo the PREVIEW state, not just hide the panel.
--
-- The main loop only pushes wanted/cash/zone when the value CHANGES, so after
-- the preview faked 3 stars and $28,163 the loop saw no change from the real
-- values it had already sent and stayed quiet — leaving the fake ones on screen
-- until something genuinely changed. Invalidating the caches forces the very
-- next tick to re-send the truth. Vehicle and honor are transient panels with
-- no cache, so those are cleared outright - honor will draw itself again the
-- next time it moves.
-- editorOpen / weHoldFocus are declared at the top of the file; the poll loop
-- needs editorOpen and is defined above this point.

function resetPushCaches()
    lastWanted, lastSpotted = -1, false
    lastCash = nil
    lastRectKey = nil
    currentZone = nil
    panelUntil = 0
    vehShown = false
    ui('vehicle', { show = false })
    ui('honor', { show = false })
    ui('reputation', { show = false })
end

RegisterCommand('movehud', function()
    editorOpen, weHoldFocus = true, true
    -- Immediately, not on the next poll tick: the Minimap rows are the first
    -- thing people reach for and the map has to already be on screen.
    DisplayRadar(true)
    SetNuiFocus(true, true)
    ui('openEditor', { offsets = layout, native = nativeState() })
end, false)

-- Every name someone might reasonably try.
for _, alias in ipairs({ 'hudmenu', 'hudeditor', 'hudedit' }) do
    RegisterCommand(alias, function() ExecuteCommand('movehud') end, false)
end

RegisterNUICallback('saveLayout', function(data, cb)
    if type(data) == 'table' and type(data.offsets) == 'table' then
        layout = data.offsets
        saveLayout()
    end
    editorOpen, weHoldFocus = false, false
    SetNuiFocus(false, false)
    pushLayout()
    resetPushCaches()
    lib.notify({ title = 'HUD', description = 'Layout saved', type = 'success' })
    cb({ ok = true })
end)

RegisterNUICallback('closeEditor', function(_, cb)
    editorOpen, weHoldFocus = false, false
    SetNuiFocus(false, false)
    -- Re-push the saved layout so a cancelled edit reverts on screen.
    pushLayout()
    resetPushCaches()
    cb({ ok = true })
end)

-- Never leave NUI focus behind.
--
-- NUI focus is GLOBAL and survives this resource restarting. ox_inventory's
-- hotbar (and plenty else) gates on IsNuiFocused(), so focus stranded by
-- /movehud silently kills the 1-5 item keys until the game is restarted —
-- with no error and nothing on screen to explain it.
--
-- The previous safety net here waited for ESC via IsControlJustPressed, which
-- could never fire: holding NUI focus is exactly what stops game controls from
-- registering. These three do work.

-- 1. A restart of this resource clears any focus the last instance stranded.
AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
end)

-- 2. Stopping the resource releases focus on the way out — and puts the engine
--    back the way we found it. SetMinimapComponentPosition and
--    AddReplaceTexture both write into state that OUTLIVES this resource, so
--    without this, stopping vice_hud left the map wearing vice_hud's geometry
--    and mask for the rest of the game session with nothing left running to
--    explain it.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    restoreStockMinimap()
    if maskApplied then removeMask() end
    if minimapScaleform then
        SetScaleformMovieAsNoLongerNeeded(minimapScaleform)
        minimapScaleform = nil
    end
end)

-- 3. If we hold focus while the editor is closed, something went wrong; take it
--    back. Tracked with our own flag rather than IsNuiFocused(), so another
--    resource's legitimately focused NUI is never stolen from underneath it.
CreateThread(function()
    while true do
        Wait(500)
        if not editorOpen and IsNuiFocused() and weHoldFocus then
            weHoldFocus = false
            SetNuiFocus(false, false)
            print('^3[vice_hud]^7 released stranded NUI focus (the HUD editor was not open)')
        end
    end
end)

--- Manual release, for when focus is stuck and the cause is not obvious. Safe
--- to run at any time: it only drops focus, it never takes it.
RegisterCommand('hudfocus', function()
    editorOpen, weHoldFocus = false, false
    SetNuiFocus(false, false)
    -- Broadcast, so this clears every panel in the resource and not just the
    -- editor. The skills panel holds focus too and lives in another file.
    TriggerEvent('vice_hud:releaseFocus')
    ui('skills', { show = false })
    print('^2[vice_hud]^7 NUI focus released — hotbar keys should respond again')
    lib.notify({ title = 'HUD', description = 'NUI focus released', type = 'success' })
end, false)

-- =============================================================================
-- /hudexport  —  hand the whole tuned HUD to someone else
-- =============================================================================
-- Everything a player tunes lives in KVP on their own machine: the layout
-- offsets AND the per-element typography, the native map's scale and nudge, the
-- bar shape, the HUD nudge. None of it is in the repo, so a restyle done
-- without it is working blind — and worse, offsets are nudges away from a
-- DEFAULT, so moving the default silently invalidates every one of them.
--
-- This prints the lot as one line of JSON. Paste that back and the values can be
-- baked into config.lua / style.css as the new defaults, at which point the
-- per-player nudges are redundant and can be cleared.
--
-- Output goes to the F8 console and to CitizenFX.log, so it can be copied even
-- when it is long.
local function collectHudState()
    local rx, ry = GetActiveScreenResolution()
    return {
        version    = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '?',
        resolution = { w = px(rx), h = px(ry) },
        aspect     = rx / math.max(1, ry),
        safeZone   = GetSafeZoneSize(),
        layout     = layout,
        map = {
            dx = mapDx, dy = mapDy,
            scaleW = mapScaleW, scaleH = mapScaleH,
            maskMode = maskMode,
            blipDx = blipDx, blipDy = blipDy, blipDw = blipDw, blipDh = blipDh,
            blurDx = blurDx, blurDy = blurDy, blurDw = blurDw, blurDh = blurDh,
            northBlip = northBlip, playerBlipScale = playerBlipScale,
            radarZoom = radarZoom,
            maskNudgeX = maskNudgeX, maskNudgeY = maskNudgeY,
            manualRect = manualRect,
            crop = { t = cropT, b = cropB, l = cropL, r = cropR },
            clipOverride = clipOverride,
            component = Config.MinimapComponent,
            minimapScale = Config.MinimapScale,
            mask = Config.MinimapMask,
            native = Config.NativeMinimap,
        },
        barShape      = barShape,
        offsetX       = tonumber(GetResourceKvpString(KVP_OFFSET) or '') or 0,
        minimapOnFoot = minimapOnFoot,
        maxStars      = Config.MaxStars,
    }
end

RegisterCommand('hudexport', function()
    local state = collectHudState()
    local ok, enc = pcall(json.encode, state)
    if not ok then
        print('^1[vice_hud]^7 export failed: ' .. tostring(enc))
        return
    end

    print('^3[vice_hud]^7 ===== HUD EXPORT — copy everything between the markers =====')
    print('>>>VICE_HUD_EXPORT_BEGIN')
    print(enc)
    print('<<<VICE_HUD_EXPORT_END')
    print('^3[vice_hud]^7 ===========================================================')
    print(('  %dx%d  aspect %.4f  safeZone %.3f'):format(
        px(state.resolution.w), px(state.resolution.h), state.aspect, state.safeZone))

    -- Readable summary too, so it can be sanity-checked at a glance.
    local n = 0
    for name, o in pairs(layout) do
        n = n + 1
        local bits = {}
        if (o.x or 0) ~= 0 or (o.y or 0) ~= 0 then
            bits[#bits+1] = ('move %+.2f,%+.2f'):format(o.x or 0, o.y or 0)
        end
        if o.sx and o.sx ~= 1 then bits[#bits+1] = ('w x%.2f'):format(o.sx) end
        if o.sy and o.sy ~= 1 then bits[#bits+1] = ('h x%.2f'):format(o.sy) end
        if o.fs then bits[#bits+1] = ('font x%.2f'):format(o.fs) end
        if o.ff then bits[#bits+1] = 'family set' end
        if o.fw then bits[#bits+1] = ('weight %s'):format(tostring(o.fw)) end
        if o.ls then bits[#bits+1] = ('spacing %.3f'):format(o.ls) end
        if o.op then bits[#bits+1] = ('opacity %.2f'):format(o.op) end
        if o.rad then bits[#bits+1] = ('radius x%.2f'):format(o.rad) end
        if #bits > 0 then
            print(('    %-11s %s'):format(name, table.concat(bits, ', ')))
        end
    end
    if n == 0 then
        print('  ^3NOTE:^7 no saved layout — nothing has been tuned, or /hudreset cleared it.')
    end
    lib.notify({ title = 'HUD', description = 'Exported to console (F8)', type = 'success' })
end, false)

--- Restore an export. Paste the JSON straight after the command.
--- Useful for moving a tuned HUD between machines, and for putting one back
--- after testing something destructive.
RegisterCommand('hudimport', function(_, args)
    local raw = table.concat(args or {}, ' ')
    if raw == '' then
        print('^3[vice_hud]^7 usage: /hudimport <the JSON from /hudexport>')
        return
    end
    local ok, d = pcall(json.decode, raw)
    if not ok or type(d) ~= 'table' then
        print('^1[vice_hud]^7 import failed: that is not valid JSON')
        return
    end

    if type(d.layout) == 'table' then
        layout = d.layout
        saveLayout()
        pushLayout()
    end
    if type(d.map) == 'table' then
        mapDx = px(d.map.dx)
        mapDy = px(d.map.dy)
        mapScaleW = tonumber(d.map.scaleW) or Config.MinimapScale or 1.0
        mapScaleH = tonumber(d.map.scaleH) or Config.MinimapScale or 1.0
        if d.map.maskMode == 'map' or d.map.maskMode == 'config' then
            maskMode = d.map.maskMode
        end
        blipDx = tonumber(d.map.blipDx) or 0.0
        blipDy = tonumber(d.map.blipDy) or 0.0
        blipDw = tonumber(d.map.blipDw) or 0.0
        blipDh = tonumber(d.map.blipDh) or 0.0
        blurDx = tonumber(d.map.blurDx) or 0.0
        blurDy = tonumber(d.map.blurDy) or 0.0
        blurDw = tonumber(d.map.blurDw) or 0.0
        blurDh = tonumber(d.map.blurDh) or 0.0
        radarZoom = tonumber(d.map.radarZoom) or 0.0
        playerBlipScale = tonumber(d.map.playerBlipScale) or 0.0
        -- `~= false`, not `or true`: an exported `false` has to survive, and
        -- `false or true` is true.
        if d.map.northBlip ~= nil then northBlip = d.map.northBlip ~= false end
        -- These two were exported but never read back, so an import silently
        -- dropped a hand-measured rect and any mask nudge.
        maskNudgeX = tonumber(d.map.maskNudgeX) or 0.0
        maskNudgeY = tonumber(d.map.maskNudgeY) or 0.0
        if type(d.map.crop) == 'table' then
            cropT = tonumber(d.map.crop.t) or 0.0
            cropB = tonumber(d.map.crop.b) or 0.0
            cropL = tonumber(d.map.crop.l) or 0.0
            cropR = tonumber(d.map.crop.r) or 0.0
        end
        if type(d.map.manualRect) == 'table' and tonumber(d.map.manualRect.width) then
            manualRect = {
                left   = tonumber(d.map.manualRect.left)   or 0.0,
                width  = tonumber(d.map.manualRect.width)  or 10.0,
                bottom = tonumber(d.map.manualRect.bottom) or 10.0,
                height = tonumber(d.map.manualRect.height) or 10.0,
            }
            Config.Minimap.left   = manualRect.left
            Config.Minimap.width  = manualRect.width
            Config.Minimap.bottom = manualRect.bottom
            Config.Minimap.height = manualRect.height
        end
        clipOverride = tonumber(d.map.clipOverride)
        lastRectKey = nil
        applyMinimap(true)
        saveMapState()
    end
    if d.barShape == 'pill' or d.barShape == 'square' then
        barShape = d.barShape
        SetResourceKvp(KVP_BARS, barShape)
        pushHudConfig()
    end
    if tonumber(d.offsetX) then
        SetResourceKvp(KVP_OFFSET, tostring(d.offsetX))
        applyOffset(tonumber(d.offsetX))
    end
    print('^2[vice_hud]^7 HUD state imported.')
    lib.notify({ title = 'HUD', description = 'HUD state imported', type = 'success' })
end, false)

-- =============================================================================
-- /hudblip  —  centre the player blip in the minimap
-- =============================================================================
-- The blip is drawn against the `minimap` component; the mask is the window you
-- look through. When they disagree the blip sits off-centre, and the amount is
-- not derivable from outside the game. So: nudge the mask until the blip is in
-- the middle, then report the number.
--
--   /hudblip                 show the current adjustment
--   /hudblip <dx> [dy]       move the mask, in THOUSANDTHS of a safe-zone unit
--   /hudblip size <dw> [dh]  grow/shrink the mask, same units
--   /hudblip reset           back to no adjustment
--
-- Moving the mask RIGHT (+dx) moves the blip LEFT within the visible map, and
-- vice versa -- you are moving the window, not the map under it.
--- Outline the three engine component rects over the screen.
---
--- The tool to reach for when something drawn ON the map -- a radius blip, an
--- area blip -- does not line up with the map itself. The pause map is the
--- control: if a radius reads as a circle there and a rectangle here, the blip
--- is fine and a clip region is wrong, and this says which one.
--- Snap one minimap component onto another.
---
--- The arithmetic is mechanical and getting it wrong by hand is how an evening
--- disappears, so it is a command rather than four numbers in a message. Which
--- direction you want depends on what /hudrects showed:
---
---   /hudmatch plane   grow the PLANE onto the blur. Use when the drawn map
---                     fills the blur rect and blips clip to the smaller plane.
---   /hudmatch blur    shrink the BLUR onto the plane. Use when the drawn map
---                     should be the plane's size and the blur is inflating it.
---
--- Try one, look, /mapreset if it is wrong. They are opposites, so one of the
--- two is the answer and neither costs anything to test.
RegisterCommand('hudmatch', function(_, args)
    local M = Config.MinimapComponent
    local which = args[1]

    -- REFUSED while the blur tracks the plane, which is the DEFAULT
    -- (`blurMode = 'plane'`, i.e. "Blur = map" / `follows map` in /movehud).
    --
    -- Every line below is written for blurMode 'config', where the blur is its
    -- own rect built from M.blurX/Y/W/H. In 'plane' mode it is instead derived
    -- from the plane -- `ubx = ox + fdx + blipDx + blurDx` -- so:
    --
    --   · there is nothing to match. The two rects are already the same rect by
    --     construction, at every scale, which is the whole point of that mode.
    --   · running it anyway CORRUPTS the blur, because the deltas it computes
    --     are then applied on top of a base that already contains them. With
    --     the shipped numbers, `/hudmatch blur` lands the blur at
    --     0.0656*scale wide instead of 0.1638*scale -- a map roughly 40% of the
    --     size it was, which is exactly what "hudmatch shrunk my minimap and
    --     did not fix the blip" is.
    --
    -- So this is a real refusal rather than a warning: the operation has no
    -- meaning in this mode and its only effect is damage.
    if blurMode == 'plane' then
        print('^3[vice_hud]^7 /hudmatch does nothing useful right now.')
        print('  "Blur = map" is ON (it is the default), so the blur already IS')
        print('  the map plane at every scale -- there are no two rects to snap')
        print('  together, and matching them anyway would shrink your map.')
        print('')
        print('  If the arrow is off centre, it is NOT a plane/blur mismatch.')
        print('  Run ^5/hudrects^7 to confirm the green and yellow outlines sit on')
        print('  each other, then use ^5Blip X^7 / ^5Blip Y^7 in /movehud (or /hudblip).')
        print('')
        print('  To use this command you would have to turn "Blur = map" OFF in')
        print('  /movehud first, which is only worth doing if you actually want')
        print('  the blur to be an independent rect.')
        return
    end

    if which == 'plane' then
        blipDx = ((M.blurX * mapScaleW) + blurDx) - (M.x * mapScaleW)
        blipDy = ((M.blurY * mapScaleH) + blurDy) - (M.y * mapScaleH)
        blipDw = ((M.blurW * mapScaleW) + blurDw) - (M.w * mapScaleW)
        blipDh = ((M.blurH * mapScaleH) + blurDh) - (M.h * mapScaleH)
        print('^2[vice_hud]^7 plane snapped onto the blur rect')
    elseif which == 'blur' then
        blurDx = ((M.x * mapScaleW) + blipDx) - (M.blurX * mapScaleW)
        blurDy = ((M.y * mapScaleH) + blipDy) - (M.blurY * mapScaleH)
        blurDw = ((M.w * mapScaleW) + blipDw) - (M.blurW * mapScaleW)
        blurDh = ((M.h * mapScaleH) + blipDh) - (M.blurH * mapScaleH)
        print('^2[vice_hud]^7 blur snapped onto the plane rect')
    else
        print('^3[vice_hud]^7 usage: /hudmatch plane   — grow the map plane onto the blur')
        print('                /hudmatch blur    — shrink the blur onto the map plane')
        print('  NOTE: "Blur = map" in /movehud does the second one PERMANENTLY and it')
        print('  TRACKS. This command is a one-off snapshot in absolute units, so it')
        print('  drifts out of line again the next time anything is rescaled.')
        print('  Run /hudrects first: the one you want is whichever rect the drawn')
        print('  map is NOT already sitting on.')
        return
    end

    lastRectKey = nil
    applyMinimap(true)
    saveMapState()
    ExecuteCommand('mapinfo')
end, false)

RegisterCommand('hudrects', function()
    showMapRects = not showMapRects
    lastRectKey = nil
    applyMinimap(false)
    print(('^2[vice_hud]^7 component outlines %s'):format(showMapRects and 'ON' or 'off'))
    if not showMapRects then return end
    print('  Three outlines, each labelled, drawn from the exact numbers this')
    print('  resource hands SetMinimapComponentPosition:')
    print('    ^2green^7   minimap        the PLANE the world and its blips draw onto')
    print('    ^5cyan^7    minimap_mask   the WINDOW that clips it')
    print('    ^3yellow^7  minimap_blur   the soft edge behind both')
    print('')
    print('  Screenshot it with a radius blip on screen and read off which')
    print('  outline the shaded area stops at:')
    print('    * stops at GREEN  -> the plane is smaller than the window. Grow it')
    print('                         with Plane width / Plane height in /movehud.')
    print('    * stops at CYAN   -> the mask is the constraint, which is normal.')
    print("    * stops at NEITHER-> the clip is GTA's own, not ours. Try")
    print('                         /hudmaskoff (or Custom mask -> stock) and')
    print('                         /hudmaskmode config to see if either moves it.')
    print('    * stops at YELLOW -> the BLUR is what is really deciding the drawn')
    print('                         size, and the arrow is on the GREEN rect, so')
    print('                         it sits off centre by exactly the gap between')
    print('                         those two centres. See the measurement below.')
    print('    * outline is not on the drawn map at all -> the component numbers')
    print('      and the drawn map disagree, which is a different fix again.')

    -- The measurement, so the yellow case does not have to be eyeballed.
    --
    -- This is the single most-confused thing about this tool, and confusing it
    -- costs you your map: when the drawn map fills the BLUR, the fix is
    -- `/hudmatch plane` -- GROW the plane onto the blur, keeping the size you
    -- can see. `/hudmatch blur` does the opposite, shrinking the blur down onto
    -- the (smaller) plane, and the map visibly loses whatever the ratio below
    -- says. Both are "matching the rects"; only one keeps your map.
    local M = Config.MinimapComponent
    local pw = (M.w * mapScaleW) + blipDw
    local ph = (M.h * mapScaleH) + blipDh
    local bw, bh, bx, by
    if blurMode == 'plane' then
        bw, bh = pw + blurDw, ph + blurDh
        bx = (M.x * mapScaleW) + blipDx + blurDx
        by = (M.y * mapScaleH) + blipDy + blurDy
    else
        bw, bh = (M.blurW * mapScaleW) + blurDw, (M.blurH * mapScaleH) + blurDh
        bx, by = (M.blurX * mapScaleW) + blurDx, (M.blurY * mapScaleH) + blurDy
    end
    local pxc = (M.x * mapScaleW) + blipDx + pw * 0.5
    local pyc = (M.y * mapScaleH) + blipDy + ph * 0.5
    local dx, dy = (bx + bw * 0.5) - pxc, (by + bh * 0.5) - pyc
    local rx2, ry2 = GetActiveScreenResolution()

    print('')
    print(('  blur is %.2fx the plane wide, %.2fx tall   (blurMode %s)')
        :format(bw / math.max(1e-6, pw), bh / math.max(1e-6, ph), blurMode))
    print(('  their centres are %+.0f px, %+.0f px apart on this display')
        :format(dx * rx2, dy * ry2))
    if math.abs(dx) > 0.002 or math.abs(dy) > 0.002 then
        print('  ^3That gap IS how far off centre the arrow looks.^7')
        if bw > pw then
            print('    If the map fills the YELLOW outline, run ^5/hudmatch plane^7 --')
            print(('    it grows the plane onto the blur and your map keeps its size.'))
            print(('    ^1Not^7 /hudmatch blur: that shrinks the drawn map to %.0f%% of'):format(
                pw / math.max(1e-6, bw) * 100.0))
            print('    what you can see now, which is the wrong half of the fix.')
        else
            print('    The plane is the LARGER rect here, so /hudmatch blur is the')
            print('    one that keeps your map size.')
        end
    else
        print('  ^2The two centres agree, so this is not what is moving your arrow.^7')
    end
end, false)

RegisterCommand('hudcross', function()
    showMapCross = not showMapCross
    lastRectKey = nil                     -- force a re-publish
    applyMinimap(false)
    print(('^2[vice_hud]^7 map centre crosshair %s'):format(showMapCross and 'ON' or 'off'))
    print('  The pink cross marks the CENTRE of the rect vice_hud thinks the map')
    print('  occupies. Sit still and compare it with the player arrow:')
    print('    * arrow ON the cross          -> the blip is centred, nothing to do')
    print('    * arrow off, cross ON the map -> the blip is offset inside the map')
    print('    * cross not on the map at all -> the published RECT is wrong, not')
    print('                                     the blip. Say so; it is a different fix.')
end, false)

-- =============================================================================
-- /hudblip  —  find what actually moves the player blip
-- =============================================================================
-- Three attempts to work this out from the component geometry have been wrong,
-- so this stops guessing and moves each component independently. Whichever one
-- shifts the ARROW relative to the MAP is the answer.
--
--   /hudblip                        show the current state
--   /hudblip map  <dx> [dy]         move the `minimap` component
--   /hudblip mask <dx> [dy]         move the `minimap_mask` component
--   /hudblip size <dw> [dh]         resize the `minimap` component
--   /hudblip reset                  clear everything
--
-- Units are THOUSANDTHS of a safe-zone unit. Start at 40 -- big enough to see.
RegisterCommand('hudblip', function(_, args)
    local a1, a2, a3 = args[1], tonumber(args[2]), tonumber(args[3])

    if a1 == 'reset' then
        blipDx, blipDy, blipDw, blipDh = 0.0, 0.0, 0.0, 0.0
        maskNudgeX, maskNudgeY = 0.0, 0.0
        applyMinimap(true)
        saveMapState()
        print('^2[vice_hud]^7 blip adjustment cleared')
    elseif a1 == 'map' and a2 then
        blipDx = a2 / 1000.0
        if a3 then blipDy = a3 / 1000.0 end
        applyMinimap(true) saveMapState()
    elseif a1 == 'mask' and a2 then
        maskNudgeX = a2 / 1000.0
        if a3 then maskNudgeY = a3 / 1000.0 end
        applyMinimap(true) saveMapState()
    elseif a1 == 'size' and a2 then
        blipDw = a2 / 1000.0
        blipDh = (a3 or a2) / 1000.0
        applyMinimap(true) saveMapState()
    elseif a1 and tonumber(a1) then
        -- A bare number means the MAP component. That is the one that actually
        -- moves the arrow, so it earns the shorthand.
        blipDx = tonumber(a1) / 1000.0
        if a2 then blipDy = a2 / 1000.0 end
        applyMinimap(true) saveMapState()
    elseif a1 then
        print('^3[vice_hud]^7 usage: /hudblip <dx> [dy]   (moves the map component)')
        print('                /hudblip mask <dx> [dy]   |   /hudblip size <dw> [dh]')
        print('                /hudblip reset')
    end

    local th = function(v) return math.floor(v * 1000 + 0.5) end
    print('^3[vice_hud]^7 ===== blip adjustment =====')
    print(('  minimap      dx %+d  dy %+d   size dw %+d  dh %+d')
        :format(th(blipDx), th(blipDy), th(blipDw), th(blipDh)))
    print(('  minimap_mask dx %+d  dy %+d'):format(th(maskNudgeX), th(maskNudgeY)))
    print('')
    print('  HOW TO FIND IT (about a minute):')
    print('    1. /hudcross          -- puts a pink cross on the map centre')
    print('    2. /hudblip map 40    -- does the ARROW move relative to the MAP?')
    print('    3. /hudblip map 0     -- undo, then')
    print('    4. /hudblip mask 40   -- does the ARROW move relative to the MAP?')
    print('  Report which of the two moved the arrow WITHOUT dragging the whole')
    print('  map with it. If BOTH just slide the entire minimap, say that -- it')
    print('  means the blip is welded to the map and the fix is elsewhere.')
end, false)

-- =============================================================================
-- /hudcrop  —  trim the dead space off the minimap
-- =============================================================================
-- Also available in /movehud, on the Minimap rows, which is the easier way.
--
-- GTA renders the radar as a tilted 3D plane, and that plane does not fill the
-- `minimap` component. Past its far edge there is nothing to draw, which shows
-- as a flat dark band along the TOP of the map. Vanilla hides it because the
-- stock mask texture carries padding; ours is full-bleed and so shows the lot.
--
--   /hudcrop                    show the current crop
--   /hudcrop top <n>            trim n off the top (also bottom, left, right)
--   /hudcrop <t> <b> <l> <r>    set all four
--   /hudcrop reset              back to no crop
--
-- Units are THOUSANDTHS of a safe-zone unit.
RegisterCommand('hudcrop', function(_, args)
    local a1, a2 = args[1], tonumber(args[2])
    local changed = false

    if a1 == 'reset' then
        cropT, cropB, cropL, cropR = 0.0, 0.0, 0.0, 0.0
        changed = true
    elseif a1 == 'top' and a2 then    cropT = math.max(0.0, a2) / 1000.0 changed = true
    elseif a1 == 'bottom' and a2 then cropB = math.max(0.0, a2) / 1000.0 changed = true
    elseif a1 == 'left' and a2 then   cropL = math.max(0.0, a2) / 1000.0 changed = true
    elseif a1 == 'right' and a2 then  cropR = math.max(0.0, a2) / 1000.0 changed = true
    elseif a1 and tonumber(a1) then
        cropT = math.max(0.0, tonumber(a1)) / 1000.0
        cropB = math.max(0.0, tonumber(args[2]) or 0) / 1000.0
        cropL = math.max(0.0, tonumber(args[3]) or 0) / 1000.0
        cropR = math.max(0.0, tonumber(args[4]) or 0) / 1000.0
        changed = true
    elseif a1 then
        print('^3[vice_hud]^7 usage: /hudcrop top|bottom|left|right <n>')
        print('                /hudcrop <top> <bottom> <left> <right>   |   /hudcrop reset')
        return
    end

    if changed then
        lastRectKey = nil
        applyMinimap(true)
        saveMapState()
    end

    local th = function(v) return math.floor(v * 1000 + 0.5) end
    print(('^3[vice_hud]^7 crop  top %+d  bottom %+d  left %+d  right %+d')
        :format(th(cropT), th(cropB), th(cropL), th(cropR)))
    print('  Easier in /movehud -> Minimap -> Crop top. The dark band along the')
    print('  top of the map is dead space past the far edge of the radar plane.')
end, false)
