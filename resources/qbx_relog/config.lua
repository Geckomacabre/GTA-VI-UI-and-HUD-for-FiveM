Config = {
    commandName = 'relog',

    -- Seconds a player must wait between relogs. Set to 0 to disable.
    cooldown = 0,

    -- Seconds the player must stand still / not act before the relog goes through.
    -- Prevents combat logging. Set to 0 to relog instantly.
    -- Only applies to the full /relog back to the character picker; the
    -- quick-switch wheel uses `switchDelay` below.
    delay = 10,

    -- Same idea for the quick-switch wheel. Kept separate because switching to
    -- another of your own characters is the singleplayer-style convenience
    -- feature, not a way out of a fight -- but it's still a way to disappear,
    -- so it isn't free either.
    switchDelay = 5,

    -- Block relogging while dead or in laststand.
    blockWhenDead = true,

    -- Block relogging while cuffed.
    blockWhenCuffed = true,

    -- Block relogging while in a vehicle.
    blockInVehicle = false,

    --#region Quick-switch wheel

    -- Hold this key to open the character switcher: your characters' faces
    -- appear in the corner, you point at one, and releasing the key does the
    -- real singleplayer switch cinematic (up into the clouds, down onto the new
    -- character where they last logged out) instead of going through the
    -- qbx_core multicharacter screen.
    wheelKey = 'B',

    -- Milliseconds the key must be held before the switcher opens. A shorter
    -- tap does nothing, so the key stays usable for something else if you
    -- rebind.
    wheelHoldMs = 250,

    -- Distance from the bottom-right corner, in container units (cqw across,
    -- cqh down) so the strip keeps its proportions at any resolution. The
    -- corner is the one place vice_hud's own chrome never reaches -- the map
    -- stack owns bottom-left and the vitals own the middle.
    wheelMargin = { right = 2.4, bottom = 4.4 },

    -- How far the mouse has to travel sideways to move the highlight one card.
    -- Higher = twitchier. The mouse wheel and the arrow keys always step
    -- exactly one card regardless.
    wheelSensitivity = 1.6,

    -- Singleplayer slows time while its switch wheel is open. Off by default:
    -- on a populated server a local time scale makes everyone else look like
    -- they're teleporting for as long as you hold the key.
    wheelSlowMotion = false,

    -- Safety valve: close the switcher on its own after this many milliseconds,
    -- in case the key-up never arrives (alt-tab, focus loss, NUI stealing it).
    wheelMaxOpenMs = 30000,

    --#endregion

    --#region Honor badge

    -- Mirrors qbx_honor's config, the same way vice_hud's Config.Honor does.
    -- A client cannot read another resource's Lua state, and qbx_honor's
    -- GetBadgeTier export is server side, so the thresholds are restated here
    -- rather than bought with a callback per character every time the strip
    -- opens. If you retune qbx_honor, retune these and vice_hud's copy too.
    honorAngelAt = 40,
    honorDevilAt = -40,
    honorDefault = 0,

    honorAngelEmoji = '😇',
    honorDevilEmoji = '😈',

    --#endregion

    --#region Switch cinematic

    -- SWITCH_TO_MULTI_FIRSTPART's switchType. 1 is the long "three steps out"
    -- pull-up into the clouds, which is what singleplayer uses for a switch to
    -- a character across the map. 0/2/3 are the short one-step variants.
    switchType = 1,

    -- Milliseconds to hold up in the clouds after the new character has loaded,
    -- before descending. Covers the async appearance apply from
    -- illenium-appearance and gives the destination time to stream in.
    switchSkyHoldMs = 1200,

    -- Give up on the cinematic and fall back to a plain fade if the engine
    -- hasn't reached the in-the-air state within this long.
    switchTimeoutMs = 10000,

    --#endregion
}
