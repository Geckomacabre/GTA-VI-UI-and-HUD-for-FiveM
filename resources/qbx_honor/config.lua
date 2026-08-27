Config = {}

-- ============================================================================
-- Range
-- ============================================================================

Config.MinHonor     = -100
Config.MaxHonor     = 100
Config.DefaultHonor = 0 -- neutral starting value for a brand new character

-- ============================================================================
-- Badge thresholds
-- Honor >= AngelThreshold  -> 'angel' badge
-- Honor <= DevilThreshold  -> 'devil' badge
-- Anything in between      -> no badge (neutral)
--
-- vice_hud draws two separate things and they do NOT use the same face:
--   * the corner panel is the STANDING, so its badge is the tier for the
--     current value - these thresholds, mirrored in vice_hud's own Config.Honor.
--   * the centre-screen +/- indicator is the CHANGE, so its face follows the
--     direction honor just moved, which vice_hud picks itself.
-- qbx_honor therefore does not send an emoji at all; sending one would force
-- the standing badge to show the direction face instead of the tier face.
-- ============================================================================

Config.AngelThreshold = 40
Config.DevilThreshold = -40

Config.AngelEmoji = '😇'
Config.DevilEmoji = '😈'

-- ============================================================================
-- Feedback
--
-- The HUD panel is transient and owned by another resource, so when it does not
-- draw, an honor change is completely imperceptible - indistinguishable from a
-- broken honor system. That ambiguity cost a long debugging session once.
--
-- With this on, every honor change also raises an ox_lib/qbx_core notification
-- saying what happened and by how much. Turn it off once you are satisfied the
-- vice_hud panel is showing changes reliably and you want the HUD to be the
-- only feedback.
-- ============================================================================

Config.NotifyOnChange = false

-- Also post the change as a NATIVE GTA feed notification (the phone-style
-- ticker top-left). This is the one feedback path with no dependencies at all:
-- no NUI, no ox_lib, no vice_hud, no state bags. Everything else in this chain
-- can fail quietly - the HUD panel needs vice_hud to be started and drawing,
-- and ox_lib notifications are repositioned through a patch inside ox_lib that
-- silently drops anything it does not like. If the native ticker does not
-- appear, nothing reached the client at all, which is worth knowing for certain.
Config.NativeNotify = true

-- Traces every step of the chain to the server console and the client F8
-- console: file loaded -> event received -> hook applied -> honor written ->
-- client notified -> HUD drawn. Every stage prints, including the ones that
-- decide to do nothing and why.
--
-- This exists because the entire chain is pcall-wrapped for safety, which also
-- means a failure anywhere in it is completely silent. Leave it on until the
-- system is known good.
Config.Debug = true

-- ============================================================================
-- Hooks
--
-- Every honor change in the server comes through one of these named hooks, via
-- a single export:
--
--     exports.qbx_honor:ApplyHook(source, 'house_robbery')
--
-- That keeps the call sites scattered across other resources down to a genuine
-- one-liner with no numbers in them, so all tuning lives here and a server owner
-- never has to touch Lua in an unrelated resource to rebalance the economy.
--
--   delta       honor added (negative to subtract).
--   cooldownMs  minimum gap between two applications of this hook for one
--               player. Use it on hooks whose source event can fire rapidly
--               (per passenger, per pickpocket, per kill).
--   sessionCap  maximum total honor this hook may move for one player before
--               they reconnect. Use it on hooks that are otherwise farmable.
--   label       short human-readable reason, handed to vice_hud so the honor
--               panel can say what just moved the needle.
--
-- Both throttles are per-player and per-hook, held in memory only, and reset on
-- disconnect. A hook with neither fires every time it is called.
-- ============================================================================

---@class HonorHook
---@field delta number
---@field cooldownMs? number
---@field sessionCap? number
---@field label? string shown as the reason on vice_hud's honor panel

---@type table<string, HonorHook>
Config.Hooks = {
    -- ---------- Crimes ------------------------------------------------------

    -- qbx_honor's own client watcher (client/main.lua), per wanted-star increase.
    wanted_level    = { delta = -5,  cooldownMs = 15000, label = 'Wanted by police' },

    -- qbx_honor's own conduct watcher (client/conduct.lua). See ConductWatcher
    -- below for what counts as a civilian and what counts as self-defence.
    kill_civilian   = { delta = -8,  cooldownMs = 4000, label = 'Killed a bystander' },
    kill_animal     = { delta = -2,  cooldownMs = 4000, label = 'Killed an animal' },
    aim_at_civilian = { delta = -1,  cooldownMs = 45000, sessionCap = 6, label = 'Threatened a civilian' },
    -- qbx_honor's conduct watcher: the ox_target "Antagonize" option on a civilian.
    antagonize_npc  = { delta = -2,  cooldownMs = 45000, sessionCap = 8, label = 'Antagonized a civilian' },

    -- jewelery_heist: robbing a vitrine.
    jewelry_heist   = { delta = -8, label = 'Robbed a jeweller' },
    -- qbx_vehiclekeys: smashing a locked vehicle's window to break in.
    window_smash    = { delta = -4, label = 'Broke into a vehicle' },
    -- um_HouseRobberys: fencing what you carried out of someone's home.
    house_robbery   = { delta = -6, label = 'Fenced stolen property' },
    -- um_truckrobbery: looting a blown armoured truck.
    truck_robbery   = { delta = -10, label = 'Robbed an armoured truck' },
    -- caticus-chopshop: taking the cash payout for a stripped stolen car.
    chop_shop       = { delta = -5, label = 'Chopped a stolen car' },
    -- um_pawnshop: melting down jewellery so it can't be traced.
    pawn_melt       = { delta = -3,  cooldownMs = 120000, label = 'Melted down jewellery' },
    -- um_beg: selling to the hobo fence.
    hobo_fence      = { delta = -2,  cooldownMs = 120000, label = 'Sold to a fence' },
    -- um_beg: picking a stranger's pocket.
    pickpocket      = { delta = -3,  cooldownMs = 120000, label = 'Picked a pocket' },

    -- ---------- Good conduct ------------------------------------------------

    -- fusion_fishing: putting a landed fish back in the water instead of
    -- keeping it. Keeping the fish is deliberately neutral - no gain, no loss.
    fish_release    = { delta = 2,   cooldownMs = 30000, sessionCap = 20, label = 'Released a fish' },
    -- qbx_honor's conduct watcher: the ox_target "Greet" option on a civilian.
    greet_npc       = { delta = 1,   cooldownMs = 180000, sessionCap = 6, label = 'Greeted a stranger' },
    -- qbx_geocaching: finding or trading a cache.
    geocache        = { delta = 3, label = 'Found a geocache' },
    -- qbox_bounties: collecting a lawful bounty.
    bounty          = { delta = 4, label = 'Collected a bounty' },
    -- um_beg: finishing a job for the church.
    church_job      = { delta = 3, label = 'Helped at the church' },
    -- um_beg: finishing an odd job, or washing a windshield for change.
    odd_job         = { delta = 1,   cooldownMs = 300000, sessionCap = 6, label = 'Did an odd job' },
    -- Legal route work: um_busjob, um_taxijob, um_garbagejob, um_truckerjob.
    -- These pay per passenger / per bag, so the throttle does the real work -
    -- honest labour nudges honor up over a shift, it doesn't grind it up.
    honest_work     = { delta = 1,   cooldownMs = 600000, sessionCap = 8, label = 'An honest day\'s work' },
    -- qbox_barnfinds: paying to restore a derelict rather than stripping it.
    barn_find       = { delta = 2, label = 'Restored a derelict' },
}

-- ============================================================================
-- Conduct watcher (client/conduct.lua)
-- The RDR2-style part: honor reacts to how you treat the people and animals
-- around you, with no dependency on any other resource.
-- ============================================================================

Config.ConductWatcher = {
    -- Master switch for the whole file.
    enabled = true,

    -- Killing peds of these types counts as killing an innocent. GTA V ped
    -- types; see PED_TYPE_* . Deliberately includes emergency services and the
    -- people RDR2 would call bystanders, and deliberately excludes gang and
    -- criminal types (7-19, 22), which cost nothing to put down.
    civilianPedTypes = {
        [4] = true,  -- CIVMALE
        [5] = true,  -- CIVFEMALE
        [6] = true,  -- COP
        [20] = true, -- MEDIC
        [21] = true, -- FIREMAN
        [23] = true, -- BUM
        [24] = true, -- PROSTITUTE
        [27] = true, -- SWAT
    },

    animalPedTypes = {
        [28] = true, -- ANIMAL
    },

    -- A ped that damaged you within this window is treated as an aggressor, so
    -- killing it costs nothing. This is what stops honor from punishing you for
    -- surviving a mugging or a shootout you did not start.
    selfDefenceGraceMs = 25000,

    -- Peds that are visibly holding a weapon when they die are also treated as
    -- fair game. Heuristic: a dead ped usually still reports its weapon for a
    -- moment, but not always, which is what selfDefenceGraceMs is really for.
    armedPedsAreFairGame = true,

    -- Greeting / Antagonizing. Both are ox_target options on any ped (filtered
    -- to civilianPedTypes inside onSelect - see client/conduct.lua), so this is
    -- just ox_target's own targeting distance for both. The real anti-farm is
    -- Config.Hooks.greet_npc / antagonize_npc's cooldown/cap.
    interactionDistance = 2.5,

    -- Pointing a gun at a civilian. Off by default: it fires on a very common
    -- action and gets noisy fast. Turn it on for a stricter, more RDR2-ish server.
    penaliseAiming = false,

    -- ------------------------------------------------------------------------
    -- Ambient reactions. World-state texture, not a hook - no honor or
    -- reputation changes, just nearby civilians occasionally reacting to a
    -- player who has built up enough qbx_reputation to be recognizable. Only
    -- runs at all once a track is at tier 3+, so it costs nothing for anyone
    -- who hasn't earned a reaction yet (see the early-out in client/conduct.lua).
    -- ------------------------------------------------------------------------
    Ambient = {
        enabled = true,

        -- How often the scan for nearby civilians runs. Randomised between
        -- these so a room full of players doesn't all tick on the same beat.
        intervalMsMin = 4000,
        intervalMsMax = 7000,

        radius = 15.0,

        -- Of the eligible civilians found each scan, react to at most this
        -- many. This is meant to read as "someone nearby occasionally
        -- notices you", not "the whole street turns to look" every few
        -- seconds - reacting to every eligible ped at once would be the
        -- latter and read as a bug, not ambience.
        maxReactionsPerScan = 1,

        -- Chance (percent) that an eligible, off-cooldown civilian reacts at
        -- all this scan. Keeps it rare enough to notice, not constant.
        chancePercent = 20,

        -- Per-ped cooldown after it reacts once, so the same passerby
        -- doesn't glance at you every scan while you stand near them.
        cooldownMs = 60000,

        tierThreshold = 3, -- same tier this resource's Greet/Antagonize reactions branch at
    },
}
