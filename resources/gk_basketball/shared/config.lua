Config = {}

-- Draws rim circles, scoring cylinders and ball trails near you. Turn on while
-- placing hoops, turn off for production.
Config.Debug = false

--------------------------------------------------------------------------------
-- Ball
--------------------------------------------------------------------------------

Config.Ball = {
    item  = 'basketball',       -- ox_inventory item name. Set to false to disable item use.
    model = `prop_bskball_01`,

    -- Hand bone the ball snaps to while you're lining up a shot. 28422 = PH_R_Hand.
    bone   = 28422,
    offset = vec3(0.03, 0.0, -0.13),

    radius = 0.12,              -- so a bouncing ball doesn't sink into the floor

    catchRadius   = 2.2,        -- how close you must be to pick a loose ball up
    renderDistance = 60.0,      -- loose balls further than this are ignored by your client
    despawnAfter  = 180,        -- seconds a loose, untouched ball survives (0 = never)
}

--------------------------------------------------------------------------------
-- Dribbling
--------------------------------------------------------------------------------

-- While you're carrying the ball it isn't glued to your hand — it bounces on a path
-- beside you, and the ped uses GTA's ball-carrying movement animations.
Config.Dribble = {
    enabled = true,             -- false puts the ball back in your hand, statically

    -- Where the ball meets the floor, relative to you. y is forward, x is to your
    -- right, z trims the contact point up or down. Floor level is measured from
    -- your feet, not your entity position (which sits about a metre up).
    --
    -- There's no bounce height to set: the top of every bounce is your hand.
    offset = vec3(0.42, 0.22, 0.0),

    idleRate = 1.5,             -- bounces per second standing still
    moveRate = 2.5,             -- bounces per second at a full run
    spin     = 260.0,           -- degrees per second the ball rolls, visual only

    -- Metres the bounce is pushed out in front of you at a full sprint, on top of
    -- offset.y. A dribbler at speed puts the ball ahead and runs onto it; pinned
    -- to your hip it reads as carrying rather than driving. 0 disables.
    lead = 0.9,

    -- Fraction of each bounce the ball rests in your hand before the next push
    -- down. 0 is a continuous bounce with no pause; past about 0.3 you start to
    -- look hesitant on the ball.
    handDwell = 0.18,

    -- Movement set worn while carrying the ball, via SetPedMovementClipset.
    --
    -- 'anim@move_m@trash' walks with one arm hanging low and loose at your side —
    -- the closest thing the base game has to a dribbling stance, and what shipped
    -- basketball resources use for it. 'anim@sports@ballgame@handball@' is the
    -- two-handed carry instead, which looks like you're holding the ball rather
    -- than working it. Set to false to leave your normal walk alone.
    clipset = 'anim@move_m@trash',

    --[[
        Optional extra: pump the arm on top of the clipset.

        GTA has no dribble clip anywhere, so this borrows an unrelated one — it's
        played on the upper body at zero playback rate and its phase is scrubbed
        from the bounce, `from` at the top and `to` at the bottom, locking the arm
        to the ball.

        Off by default, because every stock clip that moves the arm far enough to
        notice also bends the spine, and a ped folding in half after the ball
        looks far worse than a still arm. The bounce already ends in your hand,
        which is what carries the illusion.

        Worth a try anyway if you have an animation pack streamed, or just want to
        experiment: `/bball_hand <dict> <name> [from] [to]` swaps it live while
        you're holding a ball — no restart, no relog — and prints the current
        values to F8 when called bare. Start with a narrow window and widen it
        until the ped starts leaning.

            handAnim = { dict = 'pickup_object', name = 'pickup_low',
                         from = 0.08, to = 0.30 },
    ]]
    handAnim = false,
}

-- GTA's world gravity. Only change this if you've modified gravity server-side;
-- the shot solver uses it to build the arc.
Config.Gravity = 9.8

--------------------------------------------------------------------------------
-- Shooting
--------------------------------------------------------------------------------

Config.Shot = {
    -- true  : hold AIM (RMB / left trigger) to line up, then tap SHOOT (LMB / right
    --         trigger) when the meter is in the green. Letting go of aim cancels.
    -- false : hold SHOOT to charge and release it in the green, with no aim step.
    aimToShoot = true,

    -- The meter rises to 1.0 over chargeTime seconds, then falls back down, and
    -- keeps oscillating until you take the shot.
    chargeTime = 0.9,

    -- Release with the meter inside the sweet band for a perfect shot. Accuracy
    -- falls off linearly to 0 at the edges of the band.
    sweetSpot  = 0.82,
    sweetWidth = 0.14,

    -- With aim assist on, the ball is solved onto the hoop you're facing and then
    -- nudged off-target by your accuracy. With it off, the ball just launches
    -- along your camera direction and you aim manually (hard mode).
    aimAssist = true,

    maxRange   = 26.0,          -- beyond this, no hoop is targeted (free throw toss)
    closeRange = 4.0,           -- shots inside this distance ignore the distance penalty

    -- How much raw distance eats into a perfect release. 0 = distance is free,
    -- 1 = a max-range shot is a coin flip even on a perfect release.
    distancePenalty = 0.45,

    -- Metres of miss per metre of shot distance at zero accuracy. Lower these to
    -- make the game more forgiving; at 0.11 a sloppy release from the 3-point
    -- line misses about as often as it goes in.
    lateralError = 0.11,        -- left/right
    depthError   = 0.14,        -- short/long

    --[[
        Arc shape, and the only thing that controls it.

        The shot is solved to reach the rim in exactly `time` seconds, so a longer
        flight time is a higher arc — the ball has to be thrown up harder to still
        be in the air that long. Nothing else sets the height; there is no
        separate arc setting to reach for.

        Lower these to flatten shots and speed them up. Go too far and the ball
        arrives at the rim travelling almost horizontally, which rims out far more
        often, so treat about 0.4 base as the floor.

        These were briefly cut to 0.52/0.048 to answer a "flies too high"
        complaint that turned out to be aim assist dropping out and falling
        through to a loose toss — nothing to do with the arc. Cutting them made
        the descent shallower, which compounded the aimHeightOffset overshoot
        above, so they're back where they were.
    ]]
    flightTimeBase   = 0.62,
    flightTimePerMetre = 0.062,
    flightTimeMax    = 2.1,

    --[[
        How far above the rim plane the shot is aimed, to clear the front rim.

        Keep this small. The ball is solved to pass through a point this far
        above the rim while still travelling forward, so it only reaches rim
        height some distance *beyond* the basket — and scoring is a rim-plane
        crossing test, so that overshoot is a miss no matter how good the aim.

        How far past scales with how flat the arc is. At 8m with a 0.22 offset
        the ball crossed the rim plane about 0.7m long, against a rim radius of
        0.32: every shot sailed. At 0.06 it's under 0.15m, which is inside the
        hoop.
    ]]
    aimHeightOffset = 0.06,
    spin = 9.0,                 -- backspin, visual only

    -- Where the ball leaves you, measured from your head bone and pushed out
    -- along the line of the shot. Not off the hand bone: that ties the release to
    -- whatever the animation is doing and can put the ball behind your shoulder.
    --
    -- releaseForward has to stay clear of your own collision capsule or the
    -- physics engine eats the throw, so don't take it below about 0.35.
    releaseHeight  = 0.22,
    releaseForward = 0.42,

    -- Milliseconds between the shot animation starting and the ball leaving your
    -- hand, so the arm swings first. Your target and accuracy are locked in the
    -- instant you release the key, so this never changes where the shot goes —
    -- only when it looks like it left. /bball_windup <ms> tries values live.
    windUp = 220,
}

--[[
    Drawn on the rim you're locked onto while you line up, so aim assist stops
    being invisible — you can see which basket you have and what it's worth before
    you commit, instead of finding out from the ball.

    Kept deliberately thin. This is not the placement tool's rim rendering: that
    draws the whole scoring cylinder, which is useful stood next to a hoop and
    turns into a green slab over the backboard from anywhere you'd actually shoot
    from. Set to false to aim blind.
]]
Config.AimMarker = {
    colour = { 90, 220, 130 },  -- rgb, matched to the meter's sweet band
    alpha  = 130,               -- rim disc opacity. Higher reads better in daylight

    label       = true,         -- points and range, above the backboard
    labelHeight = 1.35,         -- metres above the rim — needs to clear the board
    labelScale  = 0.5,
}

-- Fixed-power toss used for passes and for shots with no hoop in range.
Config.Toss = {
    minPower = 6.0,
    maxPower = 19.0,            -- at a full meter
    upwardBias = 0.16,          -- lifts the arc so passes don't drill into the floor

    -- Ceiling on how much of your camera pitch feeds the throw. Looking near
    -- straight up would otherwise send a full-power toss into orbit. 0.45 is
    -- about 24 degrees.
    maxLift = 0.45,
}

--------------------------------------------------------------------------------
-- Scoring geometry
--------------------------------------------------------------------------------

Config.Scoring = {
    -- Horizontal tolerance for a made shot, measured from the rim centre.
    -- A regulation rim is 0.23m; a little slack makes it feel fair on a laggy
    -- server. Raise toward 0.40 for arcade, drop to 0.26 for punishing.
    rimRadius = 0.32,

    threePointDistance = 7.0,   -- shot origin at or beyond this scores 3

    cooldown = 1200,            -- ms between scores from one player, anti double-count
    maxTrackTime = 20,          -- seconds a shot stays attributed to its shooter
}

--------------------------------------------------------------------------------
-- Instancing
--------------------------------------------------------------------------------

--[[
    A match runs in its own routing bucket. See server/instance.lua for the bucket range
    and how it was chosen against the rest of this server.

    This has a visible consequence worth knowing before you turn it on: while you are on
    the court you cannot see anyone who is not playing, and they cannot see you. That is
    the trade -- a court with no traffic driving across it, at the cost of not being able
    to watch a match from the sidelines.
]]
Config.Instance = {
    enabled = true,

    -- Ambient peds and traffic inside the instance. Off is the reason to instance.
    population = false,

    -- 'inactive' | 'relaxed' | 'strict'. Leave on 'inactive' unless you have also set
    -- Config.AI.enabled = false -- see the long note in server/instance.lua for why the
    -- stricter settings stop the NPC opponent appearing.
    lockdown = 'inactive',
}

--------------------------------------------------------------------------------
-- Match rules
--------------------------------------------------------------------------------

Config.Match = {
    minPlayers      = 2,
    maxPerTeam      = 5,
    duration        = 300,      -- seconds. 0 = no clock, play to the score limit
    scoreLimit      = 21,       -- first team here wins. 0 = clock only
    countdown       = 5,        -- seconds between start being called and tip-off
    courtRadius     = 40.0,     -- wander further than this and you're dropped
    endScreenTime   = 12,       -- seconds the final score stays up
    winReward       = 0,        -- cash per winning player. 0 = disabled

    -- Let anyone standing on a court grab a ball from the rack without owning the
    -- item. Set false to make the inventory item the only way to get one.
    freeBallsOnCourt = true,
    teams = {
        home = { label = 'Home', colour = '#4a9eff' },
        away = { label = 'Away', colour = '#ff6b4a' },
    },
}

--------------------------------------------------------------------------------
-- NPC opponent
--------------------------------------------------------------------------------

--[[
    The AI joins a team and shoots. It is driven by the client of whoever asked for
    it, because a ped needs local ownership to move and animate smoothly.

    Honest limit: it does not defend, block or steal. Contesting a shot would mean
    predicting and intercepting another player's ball, which is a much bigger job and
    looks bad when it goes wrong. This is a shooting contest, not full 1v1.
]]

Config.AI = {
    enabled = true,

    model = `a_m_y_downtown_01`,
    fallbackModel = `a_m_y_beach_01`,

    maxPerCourt = 3,            -- how many NPCs one court will take

    difficulties = {
        {
            id    = 'easy',
            label = 'Easy — Streetballer',
            name  = 'Streetballer',

            moveSpeed = 1.3,        -- ped move blend ratio
            setupTime = 2.6,        -- seconds spent lining up before shooting
            restTime  = 2.2,        -- seconds after a shot before going again

            -- Feeds straight into the same accuracy the human release produces, so
            -- 1.0 is a dead-centre shot and 0.0 is the worst possible release.
            accuracy = 0.42,
            range    = { 2.0, 7.0 },   -- how far out it will shoot from
        },
        {
            id    = 'normal',
            label = 'Normal — Baller',
            name  = 'Baller',

            moveSpeed = 2.0,
            setupTime = 1.9,
            restTime  = 1.6,

            accuracy = 0.68,
            range    = { 2.0, 9.0 },
        },
        {
            id    = 'hard',
            label = 'Hard — Pro',
            name  = 'Pro',

            moveSpeed = 2.8,
            setupTime = 1.3,
            restTime  = 1.1,

            accuracy = 0.9,
            range    = { 3.0, 11.0 },
        },
    },
}

--------------------------------------------------------------------------------
-- Courts
--------------------------------------------------------------------------------

-- Courts are defined by their hoops, which you place in-game with /bball_place
-- and which live in data/hoops.json. A court's centre is the average of its
-- hoops, so you don't configure positions here at all.
--
-- This table is optional and only supplies display names and blips.
Config.Courts = {
    -- ['chamberlain'] = { label = 'Chamberlain Hills', blip = true },
}

Config.Blip = {
    enabled = true,
    sprite  = 313,
    colour  = 2,
    scale   = 0.75,
}

-- Ace permission needed for /bball_place, /bball_delhoop and /bball_hoops.
-- Grant with: add_ace group.admin gk_basketball.manage allow
Config.ManageAce = 'gk_basketball.manage'

--------------------------------------------------------------------------------
-- Placement tool
--------------------------------------------------------------------------------

Config.Placement = {
    step     = 0.05,    -- metres the marker moves per frame on a nudge
    fineStep = 0.01,    -- while holding LEFT ALT

    flySpeed = 11.0,    -- noclip speed in m/s
    flyBoost = 4.0,     -- multiplier while holding SHIFT
}

--------------------------------------------------------------------------------
-- Controls (see https://docs.fivem.net/docs/game-references/controls/)
--------------------------------------------------------------------------------

-- These are FiveM control ids, not key codes, so every one is already bound to both
-- a key and a gamepad button by the game. The controller equivalents are noted
-- below; nothing extra is needed for pad support.
Config.Keys = {
    aim    = 25,    -- INPUT_AIM       RMB    / left trigger
    shoot  = 24,    -- INPUT_ATTACK    LMB    / right trigger
    pass   = 51,    -- INPUT_CONTEXT   E      / dpad right
    stow   = 47,    -- INPUT_DETONATE  G      / dpad down
    pickup = 51,    -- INPUT_CONTEXT   E      / dpad right
}

--------------------------------------------------------------------------------
-- Animations
--------------------------------------------------------------------------------

-- Every name here was checked against the GTA V animation database (patch v1734)
-- rather than guessed. Set any entry to false to play no animation for that action.
--
-- 'anim@sports@ballgame@handball@' is real and does contain 'ball_idle', a proper
-- holding-a-ball idle. It contains no throw, though — the whole dict is 14 clips of
-- idle/walk/run/sprint/stop while carrying a ball — so the shot falls back to an
-- overhand melee throw, which is what pickle_throwables uses too.
--
-- Also in that dict if you ever want to go further: ball_walk, ball_run, ball_sprint
-- and the ball_wstop_*/ball_rstop_* stops. Driving those off player speed would make
-- carrying the ball look considerably better than a static idle.
--
-- A dict that fails to load is skipped rather than hung on, and an anim name that
-- doesn't exist is given up on after a few attempts instead of retried every frame.
-- There's no `idle` entry any more: carrying the ball is handled by the movement
-- clipset in Config.Dribble, which covers idle, walk, run, sprint and the stops
-- rather than freezing you in a single pose.
Config.Anims = {
    -- An overhand throw. Tried 'amb@prop_human_movie_bulb@exit' / 'exit' here —
    -- the lightbulb scenario exit that gusti-basketball shoots with — and it
    -- doesn't work: it's a *scenario exit*, so it opens in the raised pose and
    -- unwinds from it, with the hand tracking back over the head rather than
    -- pushing forward. Shots read as being flung from behind you.
    --
    -- /bball_anim shoot <dict> <name> tries others live.
    shoot  = { dict = 'melee@thrown@streamed_core',     name = 'plyr_takedown_front', flag = 48, duration = 700 },
    pass   = { dict = 'mp_common',                      name = 'givetake1_b',         flag = 48, duration = 600 },
    pickup = { dict = 'pickup_object',                  name = 'pickup_low',          flag = 48, duration = 700 },
    stow   = { dict = 'pickup_object',                  name = 'putdown_low',         flag = 48, duration = 700 },
}

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

Config.Text = {
    pickup_ball     = '[E] Pick up basketball',
    holding_hint    = 'Hold [RMB] Aim  •  [LMB] Shoot  •  [E] Pass  •  [G] Put away',
    aiming_hint     = 'Release [LMB] in the green  •  [RMB] to cancel',
    aiming_notarget = 'No hoop in your sights  •  this will be a loose throw',
    court_join      = 'Join pickup game',
    court_leave     = 'Leave game',
    court_start     = 'Start match',
    court_ball      = 'Grab a basketball',
    court_ai        = 'Add an AI player',

    ai_menu_title   = 'Add an AI player',
    ai_description  = 'Shoots for your team. Does not defend.',
    ai_joined       = '%s joined the %s team.',
    ai_full         = 'This court already has enough AI players.',
    ai_failed       = 'Could not spawn the AI player.',
    court_label     = 'Basketball Court',

    joined          = 'You joined the %s team.',
    left            = 'You left the game.',
    already_in      = 'You are already in a game.',
    court_full      = 'That team is full.',
    need_players    = 'Need at least %s players to start.',
    match_starting  = 'Tip-off in %s...',
    match_live      = 'Game on!',
    match_won       = '%s wins %s - %s!',
    match_draw      = 'Draw, %s - %s.',
    left_court      = 'You left the court and were removed from the game.',
    scored          = '%s scores %s!',
    scored_self     = 'You scored %s points!',
    swish           = 'Swish!',
    no_ball         = 'You need a basketball.',
    hands_full      = 'You are already holding a ball.',
    reward          = 'You earned $%s for the win.',

    -- Drawn natively as a panel on the left of the screen for the whole placement
    -- session, one array entry per line. Empty strings are spacers.
    --
    -- ~y~ ~w~ ~c~ ~g~ ~r~ are GTA's text colour codes (yellow, white, grey, green,
    -- red). This is deliberately not ox_lib's text UI: that renders markdown and is
    -- built for one-line transient prompts, not a dozen lines that must stay up.
    placement_panel = {
        '~y~PLACING A RIM',
        '',
        '~w~W A S D~c~   fly around',
        '~w~SPACE / CTRL~c~   fly up / down',
        '~w~SHIFT~c~   fly faster',
        '',
        '~w~Arrows~c~ or ~w~NUM 8 2 4 6~c~   move rim',
        '~w~PgUp PgDn~c~ or ~w~NUM + -~c~   rim height',
        '~w~ALT~c~   hold for fine steps',
        '',
        '~g~ENTER~c~ save      ~r~BACKSPACE~c~ cancel',
    },
}
