Config = {}

-- How long the vehicle make/model panel stays up after getting in, in ms.
-- The reference footage never shows it persisting for a whole drive — it
-- announces the vehicle and then clears.
Config.VehiclePanelMs = 5000

-- Hide the native green/blue health+armour bars drawn around the minimap.
--
-- Done via the minimap scaleform's SETUP_HEALTH_ARMOUR method (param 3 = hide
-- both), which is what nbk_circle uses. It touches ONLY those bars.
--
-- This previously used DisplayHud(false), which also killed the radio display,
-- help text ("Press E to..."), subtitles and native notifications. That is what
-- broke the in-vehicle radio.
Config.HideNativeHealthBars = true

-- Native HUD pieces hidden every frame because vice_hud draws its own version.
-- Only list things we ACTUALLY replace — hiding a component we don't draw just
-- removes information from the player:
--    1 wanted stars   (we draw our own, top-right)
--    6 vehicle name   (the make/model panel replaces it)
--    7 area name      (the zone bar replaces it)
--    8 vehicle class
--    9 street name
--   20 weapon-wheel stats
-- Deliberately NOT hidden: 2 weapon icon, 3/4 cash, 16 radio — we don't render
-- substitutes for those, so they stay native.
Config.HiddenHudComponents = { 1, 6, 7, 8, 9, 20 }

-- Poll interval for the status/wanted loop, in ms. 250 keeps the wanted stars
-- responsive without being wasteful; nothing here is per-frame.
Config.Tick = 250

-- Default for "show the minimap while on foot" — ON. Each player can override
-- it with /hudminimap; their choice persists in KVP and beats this value.
Config.MinimapOnFootDefault = true

-- =============================================================================
-- Stamina
-- =============================================================================
-- WHERE THE BAR'S NUMBER COMES FROM.
--
-- 'manual' - vice_hud runs its own bar. Drains while you sprint, refills when
--            you stop, and that is the whole model. Predictable, identical on
--            every build, and it cannot disagree with itself.
--
-- 'native' - read GetPlayerSprintStaminaRemaining and try to interpret it.
--
-- The default is 'manual' because the native turned out not to be worth it. It
-- is documented three different ways (remaining vs depletion, 0..1 vs 0..100)
-- and on a real build it was none of them: a DEPLETION counter running 0 .. 9.1
-- whose ceiling moves with the player's MP0_STAMINA stat, and which no native
-- reports. Read as 0..100 that turned a full sprint into a move from 100% to
-- 91%. Read wrongly in the other direction it produced a constant -15%, which
-- clamped to full exhaustion, which disabled sprint, which meant the value
-- could never move again.
--
-- The 'native' path still exists and is better than it was - it learns the
-- range rather than assuming one. But a stamina bar's job is to be right, and a
-- self-managed one is right by construction.
Config.Stamina = {
    source = 'manual',

    -- Seconds of continuous sprinting to go from full to empty.
    sprintSeconds = 12.0,

    -- Seconds to refill from empty, once regeneration starts.
    refillSeconds = 9.0,

    -- Pause after you stop sprinting before it begins refilling, in ms. Without
    -- it the bar snaps back the instant you let go, which reads as the bar not
    -- meaning anything.
    regenDelayMs = 900,

    -- Let the stamina SKILL lengthen the sprint. At 1.0 a maxed skill doubles
    -- how long you can run; at 0 the skill changes nothing here (it still moves
    -- the native GTA stat either way).
    skillBonus = 1.0,
}

-- =============================================================================
-- Focus (Franklin-style bullet time)
-- =============================================================================
-- Toggled, not held: press the bind once to slow the world and start draining
-- the meter, press again (or let it hit empty) to snap back to normal speed.
-- Takes over the ARMOUR row rather than adding a fourth one -- armour is no
-- longer shown anywhere in this HUD as a result, which was a deliberate
-- trade the HUD's owner made in favour of keeping the stack at three rows.
Config.Focus = {
    -- Seconds of continuous use to drain the meter from full to empty.
    drainSeconds = 8.0,

    -- Seconds to refill from empty, once regeneration starts.
    refillSeconds = 12.0,

    -- Pause after leaving focus (toggled off, or emptied out) before it
    -- begins refilling, in ms. Same anti-snap reasoning as Stamina's.
    regenDelayMs = 1500,

    -- World time scale while focus is active. 1.0 is normal speed; lower is
    -- slower. 0.4 is a strong bullet-time feel without turning the world to
    -- a slideshow.
    timeScale = 0.4,

    -- Entering/leaving focus ramps SetTimeScale over this many steps rather
    -- than snapping it, so the transition reads as a wind-down/wind-up
    -- instead of a hard cut. Mirrors the cinematic ramp in
    -- sk_streetkings' speed-trap effect.
    rampSteps = 10,
    rampStepMs = 35,

    -- Meter must be at least this full to toggle focus ON. Stops a player
    -- triggering it with 1% left for a single frame of slow-mo.
    minToActivate = 15,

    -- Traction multiplier applied to the driven vehicle while Focus is
    -- active (and its inverse to traction loss), on top of the timescale
    -- trick. Franklin's SP ability pairs slow-mo with a grip boost -- without
    -- one, driving in Focus just feels like everything, including your own
    -- steering, slowed down together instead of the world crawling around you.
    drivingGripBonus = 1.35,

    -- SET_PED_ACCURACY value (0-100) applied to the player ped while Focus is
    -- active -- Michael's SP ability pairs slow-mo with tighter aim the same
    -- way Franklin's pairs it with grip. 90 is a strong steadying without
    -- making every shot a guaranteed hit.
    accuracyBoost = 90,

    -- Baseline SET_PED_ACCURACY restored on leaving Focus. There is no
    -- GET_PED_ACCURACY native to read back whatever the value actually was
    -- beforehand (unlike the vehicle handling floats above), so this is a
    -- fixed neutral value rather than a true restore -- fine as long as
    -- nothing else in the resource chain calls SetPedAccuracy on the player.
    accuracyDefault = 50,
}

-- =============================================================================
-- Oxygen
-- =============================================================================
-- Underwater breath rides the STAMINA row rather than adding a fourth bar. The
-- two are mutually exclusive in practice -- you are sprinting or you are
-- submerged, and there is no moment where you need to read both at once -- so
-- one track can carry both as long as it says which one it is showing. It does:
-- the icon becomes a bubble and the fill turns blue.
--
-- This keeps the nominal state of the top-left corner EMPTY, which is the whole
-- point of the status stack. A fourth permanent bar would have cost that.
Config.Oxygen = {
    enabled = true,

    -- Fallback ceiling, in seconds, used only until a real one has been
    -- sampled. There is no native that reports maximum breath: it moves with
    -- the lung-capacity stat and with anything calling SetPedMaxTimeUnderwater,
    -- so readOxygen learns it at the surface instead of assuming it. 10s is
    -- vanilla's untrained value and is only ever seen on a dive taken before
    -- the player has surfaced once.
    defaultSeconds = 10.0,

    -- How far back the ceiling looks, in ms. The ceiling is the largest surfaced
    -- reading within this window rather than the largest ever seen, so that dive
    -- gear can raise it AND lower it again: um_divegear sets maximum breath to
    -- 2000s with a tank on and 1s with it off, and a ceiling that only grew
    -- would read every later unequipped dive as instantly empty. Long enough to
    -- span the refill that follows surfacing, short enough to forget the tank a
    -- few seconds after it comes off.
    ceilingWindowMs = 3000,
}

-- =============================================================================
-- Needs -- hunger and thirst
-- =============================================================================
-- Hunger and thirst do not get bars. They get a CAP on the health bar: a
-- darkened tail on the right end of the health track marking health you cannot
-- heal back into until you eat or drink. The fill itself stays literally health,
-- so "am I about to die" is still readable at a glance, and one row carries both
-- facts instead of two rows carrying one each.
--
-- Both values are read straight off the QBX statebags (LocalPlayer.state.hunger
-- and .thirst, 0..100). Nothing is polled from the server and no bridge event is
-- listened for: qbx_core syncs every SetMetaData write into those statebags, so
-- they are already the truth every other resource is working from.
--
-- qbx_core separately removes 5-10 health every few seconds once either value
-- reaches zero. This sits ABOVE that and does not replace it.
Config.Needs = {
    enable = true,

    -- The cap only exists below this. Above it there is no tail and, if health
    -- is full, nothing on screen at all.
    --
    -- This threshold is the whole reason the feature does not ruin the top-left
    -- corner. Hunger drains about 4.2 per minute server-side, so a tail sized
    -- from the raw value would be on screen essentially always, and the status
    -- stack's one rule -- empty unless something is wrong -- would be gone. With
    -- a threshold the tail APPEARING is itself the warning.
    warnAt = 25,

    -- Where the cap bottoms out, as a percentage of the health bar. Between
    -- warnAt and 0 the cap slides from 100 down to this, so at warnAt 25 and
    -- floorPct 40: hunger 25 -> cap 100, hunger 12.5 -> cap 70, hunger 0 -> 40.
    --
    -- 40 matches Config.Exhaustion.drainFloor for the same reason: starving
    -- should hurt, not kill. Dying of hunger is qbx_core's business.
    floorPct = 40,

    -- Whether the cap is real or only drawn. With this off the tail still shows
    -- as a warning but nothing stops you healing through it.
    enforce = true,

    -- What counts as a deliberate heal, in points of the 0..100 bar.
    --
    -- The cap blocks passive regeneration and nothing else -- it never REDUCES
    -- health, so going hungry at full health costs you nothing until you take a
    -- hit. Telling regeneration apart from a medkit or an EMS revive is done by
    -- SIZE: a regen tick over Config.Tick is a fraction of a point, while a heal
    -- is a jump. Anything bigger than this is let through untouched.
    --
    -- Measuring it beats asking the framework. 'dead' and 'inlaststand' are QBX
    -- metadata rather than statebags, so LocalPlayer.state.dead reads nil, and a
    -- HUD that guessed wrong there would be a HUD that stops medics reviving
    -- hungry players. Size needs nobody's cooperation.
    healJumpPct = 10,

    -- A second, FLAT cap that applies regardless of hunger/thirst: passive
    -- regen never climbs health past this percentage on its own, full belly
    -- or not. Getting past it takes a deliberate heal -- Zombix, food, or any
    -- other health_items consumable, which already bypasses this cap the same
    -- way it bypasses the hunger/thirst one (see healingItemActive/healJumpPct
    -- above; nothing extra was needed for that).
    --
    -- Whichever of this and the hunger/thirst cap is LOWER wins, so a starving
    -- player at 40% is still capped at 40%, not pulled back up to this. nil or
    -- 100 disables it and restores the old hunger/thirst-only behaviour.
    regenCeilingPct = 62,
}

-- UNUSED as a fallback, and deliberately so - kept only to document that the
-- convention is a per-build question rather than a setting.
--
-- readStamina() watches the native while you sprint, latches the real convention
-- AND the real scale (0..1 vs 0..100), and prints what it found. Until it has
-- latched, the bar reports full and stays hidden rather than drawing a reading
-- that might be inverted. Guessing here was what pinned the stamina bar at zero
-- and left it on screen permanently.
Config.StaminaIsDepletion = true

-- Minimap placement. These reproduce the native minimap's on-screen rect so the
-- NUI panels above it can line up. They are measured from the component
-- positions applied in client.lua; the natives expose no getter.
-- Measured off a real 3440x1440 capture of this server's minimap, expressed as
-- percentages of the 16:9 STAGE (not the raw viewport) since that is what the
-- NUI positions against:
--   left   1.72%   (matches the safe-zone edge once the ultrawide offset is
--                   removed from SetMinimapComponentPosition)
--   width  14.06%  (the mask crops the component narrower than its 0.1638 param)
--   bottom 22.6%   (screen bottom -> minimap top edge)
-- Leave the native minimap COMPLETELY alone: no component repositioning, no
-- mask swap, no clip type. GTA draws its stock map exactly as Rockstar ships
-- it, and vice_hud only reads where that map is so the zone bar and vehicle
-- panel can sit on top of it.
--
-- This is the baseline to fall back to whenever the map looks wrong: it removes
-- vice_hud from the equation entirely, so anything still wrong with the map is
-- coming from somewhere else (a tile pack, another HUD resource, the Safe Zone
-- slider). Toggle live with /hudnative.
Config.NativeMinimap = false

-- Swap GTA's radar mask for stream/vice_minimap.ytd?
--
-- ON. The stock GTA mask has SQUARE corners, so rounded corners are impossible
-- without this.
--
-- The texture in stream/vice_minimap.ytd was long assumed broken. It is not,
-- but until 2026-08-22 it was HALF right, and the half that was missing is why
-- the corners never rounded.
--
-- Decompressed and measured: RSC7 ytd, one texture named radarmasksm, 512x256,
-- D3DFMT_A8R8G8B8, no mips. The rounded-rectangle shape was painted in RGB
-- only, and the ALPHA channel was a uniform 255 across all 131072 pixels.
--
-- An earlier note here claimed GTA reads the shape out of RGB. It does not:
-- it reads ALPHA, and a uniform-255 alpha is a plain opaque rectangle, which
-- is exactly the square-cornered map that kept showing up on screen. The
-- screenshots were the measurement; the RGB theory was only ever a guess that
-- happened to explain the file rather than the symptom.
--
-- The fix was to copy the luminance into the alpha channel. RGB is untouched,
-- so the shape now reads correctly whichever channel the shader samples. The
-- pre-fix file is kept as vice_minimap.ytd.orig-rgbonly at the resource ROOT --
-- NOT in stream/, which FiveM scans automatically.
--
-- Measured shape: the white region covers 98.6% x 97.3% of the image, so it is
-- FULL-BLEED, its aspect is 2.03:1, and its corners carry a ~21px radius,
-- 8.4% of its height. That is exactly the shape the reference footage shows.
--
-- It is FULL-BLEED, which is why maskMode defaults to 'map' (mask laid exactly
-- over the map component) rather than 'config'. qbx's maskX/Y/W/H below are
-- tuned for THEIR `squaremap` texture, which has padding; pairing them with a
-- full-bleed texture puts the visible window off-centre from the map component,
-- and the PLAYER BLIP — which is drawn centred on the map component, not on the
-- mask — then sits 14% right and 17% low instead of in the middle.
-- /hudmaskoff takes the mask back off live without a restart.
Config.MinimapMask = true

-- Corner radius of that mask, as a PERCENTAGE OF THE MASK'S HEIGHT.
--
-- Why this is a stepped value and not a free number: the rounding lives in the
-- TEXTURE, and GTA cannot build a texture at runtime. So each step is a
-- pre-baked file in stream/ -- vice_mask_00 .. vice_mask_50 -- and changing the
-- radius swaps which dictionary is replacing `radarmasksm`. Anything set
-- between steps snaps to the nearest one.
--
-- Baked steps: 0 4 8 12 16 20 24 28 32 36 40 44 48 50.
--   0  = full-bleed square (still not GTA's mask, which has padding)
--   8  = the shape the reference footage shows, and what shipped before
--   50 = a stadium; the corner arc meets at the half-height
-- Regenerate or change the steps with `python tools/make_masks.py`, then keep
-- MASK_STEPS in client.lua in step with that script.
--
-- NOTE the on-screen corner is not a perfect circle at any setting: the mask is
-- 2:1 but the map component it stretches over is not, so the arc is squashed by
-- whatever that ratio works out to. That is exactly why this is a slider you
-- set by eye in /movehud -> Minimap position -> Corner radius, rather than a
-- number computed from the texture.
Config.MinimapCornerRadius = 8

-- Uniform size multiplier on Config.MinimapComponent.
--
-- 1.0 = qbx_hud's square map at its stock size. LEAVE IT unless you have
-- actually looked at it: the reference footage is for DESIGN (shape, colour,
-- what sits where), not for dimensions, and sizing this to match a screenshot
-- of someone else's monitor is how it ended up wrong twice.
--
-- Scales map, mask and blur together from the bottom-left, so the shape holds.
-- Set it by eye with /movehud (Minimap size), which saves per player; /mapinfo
-- then prints the resolved numbers to paste back here.
Config.MinimapScale = 0.663

Config.Minimap = {
    -- Measured frame-by-frame off the GTA6 reference (2282x1286 capture):
    --   left 1.75%   width 15.8%   top 82.1%  (=> bottom 17.9%)   height 15.4%
    -- The frame is an NUI outline drawn over the native map. Aligning the two
    -- reliably needs in-game trial and error, and a frame that misses its map
    -- looks worse than none — so it is OFF by default. Turn it on once
    -- /hudslot has it seated, or leave it off and the map simply has no border.
    showFrame = false,

    left   = 1.75,
    width  = 15.8,
    bottom = 17.9,
    height = 15.4,   -- used by the NUI map frame
}

-- VERBATIM from qbx_hud's square-map preset. Do not "improve" these.
--   https://github.com/Qbox-project/qbx_hud  client/main.lua
--
-- Every number below, including the ones that look wrong, is upstream's:
--
--   minimap       0.0    -0.047   0.1638  0.183
--   minimap_mask  0.0     0.0     0.128   0.20
--   minimap_blur -0.01    0.025   0.262   0.300
--   SetMinimapClipType(0)
--
-- The map sitting at y = -0.047 while its mask sits at y = 0.0 IS THE DESIGN,
-- not a mistake. The mask is the visible window, so the offset crops the map
-- deliberately — that crop is what produces the square-map shape. I previously
-- read the mismatch as a bug and "corrected" the mask to follow the map, which
-- changed the shape and broke it. It is upstream, it is in wide production use,
-- and it is correct.
--
-- Sizing is NOT done by editing these. Use /movehud (Minimap size / position),
-- which scales map, mask and blur together and saves per player, then /mapinfo
-- to print the resolved values.
Config.MinimapComponent = {
    x       =  0.0,
    y       = -0.047,
    w       =  0.1638,
    h       =  0.183,

    -- qbx's mask window. Only used in maskMode 'config'; our full-bleed texture
    -- uses 'map' instead, where the mask mirrors the map component exactly.
    -- Keep these for a texture that has padding baked in, like qbx's own.
    maskX   =  0.0,
    maskY   =  0.0,
    maskW   =  0.128,
    maskH   =  0.20,

    blurX   = -0.01,
    blurY   =  0.025,
    blurW   =  0.262,
    blurH   =  0.300,

    -- 0 = square/rounded-rect clip. 1 forces a CIRCLE and throws away the
    -- rounded-rectangle shape the mask texture defines.
    clipType = 0,
}

-- Status bar corners: 'pill' (fully rounded caps) or 'square'.
-- Change live with /hudbars; the choice is remembered per player.
Config.StatusBarShape = 'square'

-- How many wanted star SLOTS the row shows.
--
-- Six, matching the GTA6 footage. GetPlayerWantedLevel only ever reports up to
-- five, so the leftmost slot is decorative and never lights — that is the point.
-- Stars fill from the RIGHT, so five stars lights slots 2-6 and leaves the
-- outermost one empty, exactly as the reference frames show.
--
-- Set to 5 if you would rather every slot be reachable.
Config.MaxStars = 6

-- =============================================================================
-- Duffle bag value
-- =============================================================================
-- What the duffle bag on the player's back is worth at a fence/pawn shop
-- right now, shown next to cash/bank. wasabi_backpack owns the item and the
-- stash it opens into; this only asks it "what's the sellable stuff in there
-- worth", via lib.callback since that's a cross-inventory read the client
-- can't answer on its own. Entirely optional: if wasabi_backpack isn't
-- running, or the player isn't carrying the item, the row just hides.
Config.Duffle = {
    enable = true,

    -- Resource that owns the item, the per-bag stash, and the
    -- 'wasabi_backpack:getDuffleValue' callback that sums it.
    resource = 'wasabi_backpack',

    -- ox_inventory item name to check for. Matches data/items.lua's
    -- ['dufflebag'] entry -- change both together if you rename it.
    item = 'dufflebag',

    -- How often (ms) to ask the server. This is a network round trip, unlike
    -- the cash/bank row above (read straight off qbx_core's client cache), so
    -- it runs on its own slower thread rather than every main-loop tick.
    pollMs = 3000,
}

-- =============================================================================
-- Police search-radius overlay
-- =============================================================================
-- Two circles drawn on the native minimap while `fenix-police` reports it has
-- lost contact and is sweeping for the player: an inner ring at the fixed
-- "crime origin" size, and an outer ring that grows with fenix-police's own
-- live search radius. No circles show while cops still have eyes on the
-- player (searchRadius() is 0 during active contact) or while nobody is
-- wanted at all.
--
-- Entirely optional: if `fenix-police` isn't running, this whole block is a
-- no-op.
Config.PoliceSearch = {
    enable = true,

    -- Resource that owns FenixPursuit.isSearching/.searchRadius/.targetCoords
    -- and exports SearchCentre/SearchRadiusBounds off them.
    resource = 'fenix-police',

    -- How often (ms) to re-read the exports and, if the radius has moved
    -- enough to matter, recreate the circle blips. ADD_BLIP_FOR_RADIUS has no
    -- "resize" native, so a moving radius means delete-and-recreate rather
    -- than a live update -- this interval is the tradeoff between that cost
    -- and how stale the ring looks while it grows.
    pollMs = 1000,

    -- Colour index 1 = red (see SET_BLIP_COLOUR / gtaforums blip colour
    -- chart). Alpha 0-255. Inner ring stays small and opaque; outer ring
    -- grows and stays faint, matching "dark red where it happened, a lighter
    -- red for how far they might be looking".
    innerColour = 1,
    innerAlpha  = 120,
    outerColour = 1,
    outerAlpha  = 45,
}

-- =============================================================================
-- Turn-by-turn navigation popup
-- =============================================================================
-- Shown above the minimap whenever the player has a GPS waypoint set. The
-- manoeuvre comes from the GAME'S OWN route, via
-- PATHFIND::GENERATE_DIRECTIONS_TO_COORD -- see the long comment above the
-- nav block in client.lua for the direction codes and where they came from.
Config.Nav = {
    enable = true,

    -- How often (ms) to recompute the WHOLE-ROUTE distance figure shown on
    -- the map badge. The next-manoeuvre call is cheap and runs every
    -- Config.Tick; only this one is a real pathfind query worth throttling.
    routeIntervalMs = 3000,

    -- The popup comes ON once the next junction is within this many metres --
    -- "appear for the thing that matters, then get out of the way", rather
    -- than sitting on screen for a whole straight stretch of the drive.
    nearTurnMetres = 180.0,

    -- ...and only goes OFF again past this one. The gap between the two is
    -- deliberate: with a single threshold the popup blinked once a tick while
    -- the distance jittered either side of it. Must be > nearTurnMetres.
    farTurnMetres = 260.0,

    -- Once shown, stay shown at least this long. Stops a junction taken at
    -- speed from flashing up and vanishing again inside a few hundred ms.
    minHoldMs = 2500,

    -- Recolours the waypoint cross AND the GPS route line (both minimap and
    -- pause-menu map). nil keeps the game's default yellow.
    --
    -- A real HUD_COLOUR_* palette index, NOT an RGB triple -- SET_BLIP_COLOUR
    -- and SET_BLIP_ROUTE_COLOUR both only accept the game's own named
    -- colours, there is no custom-RGB passthrough for either despite
    -- community claims otherwise (confirmed wrong in-game: the route line
    -- ignored a custom RGB entirely and stayed default purple). 24 is
    -- HUD_COLOUR_PINK, verified against FiveM's own HudColor enum
    -- (github.com/d0p3t/fivem-js, src/enums/HudColor.ts) rather than guessed.
    -- Other options nearby in that same enum: 21 purple, 22 purple (light),
    -- 23 purple (dark), 126 pink (light).
    waypointColour = 24,
}

-- =============================================================================
-- Default HUD layout
-- =============================================================================
-- The shipped placement, tuned by eye in /movehud on a 3440x1440 display and
-- exported with /hudexport. These are the values a player sees BEFORE they
-- touch anything; a saved layout replaces this table wholesale, so nothing is
-- applied twice.
--
-- Units are percentages of the stage (the viewport), so they hold across
-- resolutions. Per element:
--   x, y    offset from where the CSS puts it. +x right, +y down.
--   sx, sy  width / height scale.
--   fs      font-size multiplier      fw  font-weight     ff  font-family
--   ls      letter-spacing (em)       op  opacity         rad corner-radius
-- Anything omitted uses the stylesheet's own value.
--
-- `speedlimit` and `seatbelt` are drawn by OTHER resources; vice_hud only
-- stores their offsets and broadcasts them on the vice_hud:layout event, so
-- they belong here too or those resources snap back to their own defaults.
--
-- Edit by playing, not by hand: /movehud, then /hudexport prints a fresh block.
-- Exported from a tuned game with /hudexport and pasted here verbatim, so a
-- fresh install looks like the screenshots rather than like the raw
-- stylesheet. It is the same data /hudpublish writes into layout.json --
-- layout.json (loaded by server.lua) is what actually applies server-wide;
-- this table is the fallback a client uses when there is none, and what
-- /hudreset returns to.
--
-- Some of these are deliberate PREFERENCES, not neutral defaults. Worth
-- knowing before wondering why something looks the way it does:
--   navpopup / zone / slots  set to GTA Art Deco at a thin weight, which is
--                            what the reference footage uses. The stylesheet's
--                            own default for the nav bar is Helvetica 700;
--                            these rows override it.
--   zone.al = 'left'         the zone name is ragged-left rather than centred.
--   skillup.op = 0           the skill level-up card is fully transparent,
--                            i.e. the feature runs but never draws. Remove
--                            this row to get it back.
Config.DefaultLayout = {
    status        = { x = 0.3, y = 1.1, sx = 1.45, sy = 1.45, fs = 1.75, ic = 1 },
    topright      = { x = 0.2, y = 1, sx = 1.25, sy = 1.25 },
    money         = { x = 0, y = -0.6, sx = 1.05, sy = 1.05, fs = 1.1, ic = 1.05 },
    tells         = { x = 0.1, y = 0, sx = 1, sy = 1, fs = 1, ic = 1 },
    wanted        = { x = 0.4, y = 0.5, sx = 0.9, sy = 0.85, fs = 1.25, fw = 100, op = 1, rad = 1.1, ic = 1, ff = 'system-ui, sans-serif' },
    honor         = { x = -1.9, y = -7.3, sx = 1.1, sy = 1 },
    honorpop      = { x = 46.3, y = 0.1, sx = 1.1, sy = 1.1, fs = 0.45, ic = 1 },
    reputation    = { x = 81, y = -17.6, sx = 1, sy = 1 },
    reputationpop = { x = 46.8, y = -3.2, sx = 0.45, sy = 0.45 },
    prompts       = { x = -0.4, y = 0.1, sx = 1, sy = 1 },
    skillup       = { x = 0, y = 0, sx = 1, sy = 1, op = 0 },
    focusfx       = { x = 0, y = 0, sx = 1, sy = 1 },
    mapframe      = { x = -0.3, y = 0.3, sx = 1.18, sy = 1.2, fs = 1, rad = 1.3, ic = 1, sp = 1 },
    navpopup      = { x = 0, y = 0, sx = 1, sy = 1, fw = 100, ff = "'GTAArtDeco', 'HelveticaNeueHUD', sans-serif" },
    navcompass    = { x = 0, y = 16.6, sx = 1, sy = 1, op = 0.3 },
    slots         = { x = -0.25, y = -6, sx = 1.17, sy = 1.05, fs = 0.8, fw = 400, ls = -0.005, op = 0.85, rad = 0.3, ic = 0.9, ff = "'GTAArtDeco', 'HelveticaNeueHUD', sans-serif", sm = 'none', al = 'center' },
    zone          = { x = 0, y = 0, sx = 1, sy = 1, fs = 1.3, fw = 100, ls = 0.085, rad = 0, ff = "'GTAArtDeco', 'HelveticaNeueHUD', sans-serif", al = 'left' },
    vehicle       = { x = 0, y = 0, sx = 1, sy = 1, fs = 1.45, fw = 400, ls = 0.085, rad = 1.1, ic = 1, sp = 1, sm = 'auto' },
    vehpips       = { x = 0, y = 0, sx = 1.2, sy = 1.2, fs = 1.05, ls = 0, rad = 1.3, ic = 0.8, sp = 0.6 },
    vehlogo       = { x = -0.1, y = 0, sx = 1.55, sy = 0.9, op = 1 },
    speedlimit    = { x = 13.2, y = 4.8, sx = 0.65, sy = 0.65 },
    seatbelt      = { x = -30.6, y = -12.9, sx = 1, sy = 1 },
    notify        = { x = 1.1, y = 1.9, sx = 1, sy = 1, anchor = 'center-left' },
}

-- Honor badge thresholds. Mirrors qbx_honor's config so the toast agrees with
-- whatever that resource decided.
Config.Honor = {
    angelAt = 40,
    devilAt = -40,
    angel   = '😇',
    devil   = '😈',
    neutral = '',

    -- Write the numeric standing next to the mugshot, and the reason for the
    -- change underneath it. Set false for the reference treatment, where the
    -- panel is the mugshot and its face and nothing else.
    showValue = true,
    valueLabel = 'HONOR',

    -- How long the corner panel stays up after honor moves, in ms. The panel is
    -- deliberately NOT permanent: it is a readout you get when something
    -- happens, not furniture parked in the corner all session.
    -- Set 0 to keep it on screen until something hides it.
    holdMs = 6000,
}

-- Reputation panel. Unlike honor this is not a moral axis — no angel/devil
-- faces, no mugshot — so the shape is icon + label per track rather than
-- thresholds. Labels/icons live here rather than in qbx_reputation's config
-- because qbx_reputation only knows metadata keys and tier numbers; how a
-- track is PRESENTED is a HUD concern, same split as Config.Honor above.
Config.Reputation = {
    tracks = {
        criminal    = { icon = '🗡️', label = 'CRIMINAL' },
        trade       = { icon = '💰', label = 'TRADE' },
        exploration = { icon = '🧭', label = 'EXPLORATION' },
    },

    -- Write the numeric value (and tier) next to the label, and the reason for
    -- the change underneath it. Same meaning as Config.Honor.showValue.
    showValue = true,

    -- How long the corner panel stays up after a track moves, in ms. Same
    -- "readout, not furniture" rule as honor. Set 0 to keep it on screen until
    -- something hides it.
    holdMs = 6000,
}


-- =============================================================================
-- Directional police lights
-- =============================================================================
-- Paints a soft red/blue pulse on the screen edge nearest an active siren, so
-- you can feel which direction the police are coming from without looking at
-- the minimap.
Config.PoliceLights = {
    enable      = true,

    -- How often to scan for sirens, in ms. This walks the vehicle pool, so it
    -- is deliberately not per-frame.
    scanMs      = 250,

    -- Sirens further than this are ignored entirely.
    maxDistance = 140.0,

    -- Below this distance the glow is at full strength; it fades linearly out
    -- to maxDistance.
    fullDistance = 25.0,

    -- Ceiling on the glow's opacity, 0.0-1.0.
    --
    -- This was 0.20 back when the layers cross-faded smoothly and any real
    -- strength read as a coloured slab over the screen. They now fire in short
    -- hard bursts, which reads as light rather than tint, so it can carry much
    -- more punch without muddying the picture.
    maxOpacity  = 0.55,

    -- Length of one full lightbar cycle: red double-tap, white pop, blue
    -- double-tap, white pop. Lower is more frantic. 700-1000 looks right.
    flashMs     = 900,

    -- The white takedown pops between the colours. Turn off for a plain
    -- red/blue bar.
    white       = true,

    -- How sharply the glow is confined to the edge nearest the siren.
    -- 1.0 blends broadly across neighbouring edges, higher values tighten it
    -- onto one. The glow is spread across the two nearest edges rather than
    -- snapped to one, so a car circling you sweeps around the screen instead of
    -- jumping between four fixed positions.
    focus       = 1.6,

    -- Vehicle classes treated as police. 18 = emergency.
    classes     = { [18] = true },

    -- Require the siren to actually be ON, not merely a police vehicle.
    requireSiren = true,
}

-- =============================================================================
-- Exhaustion
-- =============================================================================
-- What actually HAPPENS as the stamina bar empties. Without this the bar is
-- decoration: it drains and the player notices no difference.
--
-- Note these effects are driven by the bar's own value, so they behave the same
-- whether the bar is reading the game's native stamina or running on the
-- self-managed fallback (see readStamina in client.lua).
Config.Exhaustion = {
    enable = true,

    -- Below this the player starts slowing and the screen effect fades in.
    tiredAt = 35,

    -- At or below this, sprinting is blocked entirely — they can still jog.
    spentAt = 5,

    -- Move rate at 0 stamina. 1.0 = normal, lower = slower. Applied on a curve
    -- between tiredAt and 0 rather than snapping.
    minMoveRate = 0.72,

    -- Screen vignette strength at 0 stamina, 0.0-1.0. Deliberately mild — this
    -- is a breathing cue, not a damage effect.
    maxVignette = 0.34,

    -- Heartbeat/breathing pulse period in ms at full exhaustion.
    pulseMs = 1100,

    -- Pushing on with nothing left starts costing health. Only applies while
    -- the player is actually HOLDING sprint at zero stamina — standing still
    -- never hurts you.
    --
    -- This checks the sprint KEY, not IsPedSprinting. It cannot check the ped:
    -- `spentAt` disables the sprint control before this threshold is reached, so
    -- the ped is never sprinting when this would fire and the whole branch was
    -- unreachable. Holding the key is the honest measure of "still pushing".
    drainHealth      = true,
    drainGraceMs     = 3000,   -- how long you can push before it bites
    drainHpPerSecond = 0.4,    -- health per second once it does
    drainFloor       = 40,     -- never drops you below this; it hurts, not kills

    -- ---- Fatigue: exertion that does not reset when you catch your breath ---
    --
    -- The drain above is instantaneous — it asks "are you at zero right now".
    -- That is not what running yourself into the ground feels like: sprint,
    -- stop for two seconds, sprint again, repeat, and every individual moment
    -- passes the test while the cumulative cost is never paid.
    --
    -- Fatigue is that cost. It RISES while you are spending stamina you do not
    -- have, and falls only once stamina is genuinely back up past
    -- fatigueRecoverAt — so a short pause banks nothing. Past fatigueHurtsAt it
    -- costs health continuously, whether or not you are still moving, because
    -- by then the damage is the debt rather than the act.
    fatigue = true,

    -- Fatigue gained per second at ZERO stamina. Scaled by how spent you are,
    -- so being mildly tired accumulates slowly and being empty accumulates
    -- fast. At 0.09 a player who sits at zero takes ~11s to reach full.
    fatigueRisePerSecond = 0.09,

    -- Fatigue shed per second, but ONLY while stamina is at or above
    -- fatigueRecoverAt. This is the whole mechanic: recovery has to be earned
    -- by actually resting, not by tapping the sprint key on and off.
    fatigueFallPerSecond = 0.05,
    fatigueRecoverAt     = 80,

    -- Above this fatigue, health starts going. The loss ramps from nothing at
    -- the threshold to fatigueHpPerSecond at full, so crossing the line is a
    -- warning rather than a cliff. Shares drainFloor — it wounds, not kills.
    fatigueHurtsAt     = 0.55,
    fatigueHpPerSecond = 0.25,

    -- ---- paying it back ----------------------------------------------------
    --
    -- Health taken by exhaustion is a DEBT, not a wound. GTA's own regeneration
    -- is slow, caps well short of full, and is switched off entirely on plenty
    -- of servers — so without this, twenty minutes of running left a permanent
    -- dent that only a medic could fix. That is a punishment for playing, not a
    -- mechanic.
    --
    -- Repayment is deliberately limited to EXACTLY what this system took. Not
    -- "heal the player": vice_hud is a HUD, and a HUD that quietly restores
    -- health fights every injury, downed-state and ambulance script on the
    -- server. Undoing its own effect is defensible; healing is not its call.
    recoverHealth      = true,
    recoverHpPerSecond = 0.6,   -- repaid faster than it drains, so resting works
}

-- =============================================================================
-- Server-wide layout
-- =============================================================================
-- /hudpublish takes whatever the running player has tuned and makes it the
-- DEFAULT for everyone on the server. Players who have tuned an element
-- themselves keep their own value for that element; everyone else gets yours.
-- The published layout is written to layout.json inside this resource, so it
-- survives restarts and can be committed.
--
-- Gated on an ACE permission. Add this to server.cfg for the people who should
-- be allowed to publish:
--
--   add_ace group.admin vice_hud.publish allow
--
-- `command` is accepted as well, because anyone who already holds it can run
-- any command on the box anyway.
Config.PublishAce = 'vice_hud.publish'

-- =============================================================================
-- Skills and XP
-- =============================================================================
-- Doing a thing makes you better at that thing. Each skill's LEVEL is written
-- straight into the matching GTA player stat, which is what makes it a game
-- mechanic rather than a number on a panel: MP0_STAMINA really does lengthen
-- your sprint, MP0_STRENGTH really does raise melee damage.
--
-- The skills themselves, the XP curve and how much each activity is worth live
-- in skills.lua, next to the maths. `tools/skills.test.js` prints how much of
-- each activity a level actually costs — run it after changing any rate rather
-- than guessing at the pacing.
Config.Skills = {
    enable = true,

    -- Which character slot's stats to write. Freemode peds use MP0_; a server
    -- running singleplayer models wants SP0_. Getting this wrong is silent —
    -- the stat write succeeds against a slot nothing is reading.
    statPrefix = 'MP0_',

    -- Where a brand-new character starts, in levels.
    --
    -- NOT zero, and that is the whole point. A skill level IS the GTA stat, so
    -- starting at zero writes MP0_STAMINA = 0 and hands every new player the
    -- worst sprint in the game — strictly worse than they were before this
    -- resource existed. A system that makes the game worse the moment it is
    -- installed is not a progression system, it is a penalty.
    --
    -- 50 leaves an average character and a full half of the range to earn.
    -- Only applied the FIRST time a player is seen; it never overwrites
    -- progress. An existing character sitting below it can be brought up with
    -- `setskill <id> all 50` from the console.
    startingLevel = 50,

    -- How often the tracker samples, in ms. Everything it measures is distance
    -- or elapsed time, so this is a sampling rate rather than a deadline; 200
    -- is smooth enough for a progress bar and cheap enough to leave running.
    tick = 200,

    -- How often unsaved XP is pushed to the server, in ms. XP is also flushed
    -- on level-up and on disconnect, so this is the ceiling on how much a crash
    -- can cost, not the normal path.
    saveMs = 30000,

    -- Ignore absurd single-sample distances. A teleport, a spawn or a lift in a
    -- vehicle would otherwise bank thousands of metres of "sprinting" in one
    -- sample. This is the largest distance one tick may legitimately cover.
    maxStep = 40.0,

    -- Show a toast when a skill levels up.
    announce = true,

    -- Feed skills back into the exhaustion model: a fitter player builds
    -- fatigue more slowly and recovers from it faster. At 1.0 a maxed stamina
    -- skill halves the rate fatigue accumulates.
    fitnessAffectsFatigue = true,

    -- MP0_DRIVING_ABILITY (the native stat the driving skill writes) has no
    -- gameplay hook for a freemode ped -- Rockstar wires the grip assist that
    -- stat controls into the SINGLEPLAYER protagonists' ability scripts, which
    -- never run for MP0_. The level goes up, the stat write succeeds, and
    -- nothing about actually driving changes. This gives the skill a real
    -- effect instead: a traction adjustment applied straight to the vehicle.
    drivingAffectsHandling = true,

    -- Total swing in traction across the full 0..100 skill range, as a
    -- fraction. Centred on level 50 (Config.Skills.startingLevel, "an average
    -- character") so a brand-new character drives exactly stock. At 0.20,
    -- level 0 corners at 0.80x stock traction and level 100 at 1.20x.
    drivingGripBonus = 0.20,
}

-- =============================================================================
-- Aspect buckets  --  used by /hudpublish
-- =============================================================================
-- The layout offsets are percentages of the screen, so they mean the same thing
-- on every monitor and are published as one set. THE NATIVE MINIMAP IS NOT LIKE
-- THAT. Its values live in GTA's safe-zone-relative component space, and how
-- that space maps to what you actually see depends on the display's aspect
-- ratio -- which is exactly why the ultrawide correction in client.lua has to
-- exist at all for the map's own X position.
--
-- The blip centring is the sharp end of this. INTERNALS.md is blunt about it:
-- the offset is "not derivable from outside the game", and two attempts to
-- model it were wrong in opposite directions. So this does NOT try to rescale
-- a published value onto a different aspect -- that is the mistake that has
-- already been made twice.
--
-- Instead the server can hold ONE PUBLISHED MAP PER BUCKET. An admin runs
-- /hudpublish on a 16:9 machine and every 16:9 player gets it; run it again
-- later from an ultrawide and ultrawide players get that one, with the 16:9
-- profile left untouched. A player on an aspect nobody has published lands on
-- the nearest bucket that HAS been published, which is a better guess than a
-- computed one and an honest one.
--
-- Buckets are named rather than numeric so a published layout.json is readable
-- and hand-editable. The boundaries sit in the gaps between real display
-- aspects, not at them, so a monitor that reports 1.7777779 instead of 1.7778
-- cannot fall into the wrong one.
Config.AspectBuckets = {
    -- { name, upper bound (exclusive), nominal aspect for nearest-match }
    { '4:3',   1.45, 4 / 3 },        -- 1.333
    { '16:10', 1.70, 16 / 10 },      -- 1.600
    { '16:9',  1.90, 16 / 9 },       -- 1.778
    { '2:1',   2.15, 2.0 },          -- 2.000  (18:9 phones, some laptops)
    { '21:9',  2.60, 43 / 18 },      -- 2.389  (3440x1440, 2560x1080)
    { '32:9',  math.huge, 32 / 9 },  -- 3.556  (5120x1440)
}

--- Which bucket an aspect ratio falls in.
--- Shared so the client and the server cannot disagree about the name: the
--- client asks "what am I", the server asks "what did the publisher have", and
--- one of those answering differently would silently file a profile where
--- nobody looks for it.
---@param aspect number
---@return string
function Config.AspectBucket(aspect)
    aspect = tonumber(aspect) or (16 / 9)
    for i = 1, #Config.AspectBuckets do
        if aspect < Config.AspectBuckets[i][2] then return Config.AspectBuckets[i][1] end
    end
    return Config.AspectBuckets[#Config.AspectBuckets][1]
end

--- The nominal aspect a bucket name stands for, for nearest-match.
---@param name string
---@return number|nil
function Config.AspectNominal(name)
    for i = 1, #Config.AspectBuckets do
        if Config.AspectBuckets[i][1] == name then return Config.AspectBuckets[i][3] end
    end
    return nil
end
