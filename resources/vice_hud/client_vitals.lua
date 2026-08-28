--[[
    vice_hud — vitals:  focus, stamina, oxygen, breath, hunger/thirst, fatigue.

    Split out of client.lua on 2026-08-28. Not a rewrite: every line below is
    the same code that was in client.lua, moved. The reason for the move is
    Lua's hard limit of 200 top-level locals PER CHUNK — client.lua was at 192
    and would simply stop loading (taking the whole HUD with it) a few features
    from now. Each file is its own chunk, so this bought ~47 back.

    These four subsystems were chosen first because they were already the least
    entangled part of the file: between them they referenced exactly ONE name
    defined elsewhere (`ui`, which is four lines and is duplicated below), and
    the rest of the resource reaches in through the six entry points published
    as `ViceVitals` at the bottom of this file.

    What still crosses the boundary, and nothing else:
      ViceVitals.readStamina / readOxygen / readNeeds / enforceCap
                                    — called by the main status loop each tick
      ViceVitals.updateExhaustion   — same, fed the stamina reading
      ViceVitals.focusMeter / focusActive
                                    — read by the loop and by /hudtest; these
                                      are FUNCTIONS, not values, because the
                                      meter changes and a copied number would
                                      go stale the moment it crossed the file.
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
-- The published surface
-- =============================================================================
-- Everything above is file-local. This table is the whole of what the rest of
-- the resource may touch, and it is deliberately small -- see the header.
-- A table rather than a set of bare globals (client_skills.lua's `SkillFitness`
-- pattern) because there are six of them and they belong to one subsystem.
ViceVitals = {
    readStamina      = readStamina,
    readOxygen       = readOxygen,
    readNeeds        = readNeeds,
    enforceCap       = enforceCap,
    updateExhaustion = function(stamina) return UpdateExhaustion(stamina) end,
    -- Functions, not values: see the header.
    focusMeter       = function() return focusMeter end,
    focusActive      = function() return focusActive end,
}
