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
-- Unrepairable floor
--
-- Hitting Config.MinHonor isn't just "very devil" — it's permanent. The
-- moment a character's honor is clamped to the floor, metadata.honorBroken
-- latches true and NEVER clears, not even if honor is later raised back up
-- by good conduct. vice_hud reads this separately from the honor value/tier
-- (see IsHonorBroken() below and its own honor panel) and renders the devil
-- badge grey and cracked from then on, regardless of what the number does
-- afterward — the number can still move for other systems that read it
-- (qbx_vehiclekeys' tier scaling, etc.), only the "can this ever look normal
-- again" question is permanently answered.
--
-- This is deliberately a wall, not a second threshold to tune: it fires at
-- exactly Config.MinHonor, so a server owner who wants it easier/harder to
-- hit tunes MinHonor and the hooks that move honor toward it, not a
-- second number here.
-- ============================================================================


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
--   severity    'good' | 'bad' | 'terrible' -- which of vice_hud's three faces
--               the centre-screen change indicator shows for THIS deed. This
--               is independent of the tier badge in the corner (which always
--               reflects current standing, not the deed) and independent of
--               delta's sign/magnitude -- a small terrible-tagged hook still
--               pops the terrible face, a large bad-tagged one still doesn't.
--               Defaults to 'good'/'bad' by delta sign if omitted (see
--               server/main.lua's AdjustHonor), so this is optional for a hook
--               a server owner adds without picking a tier.
--
-- Both throttles are per-player and per-hook, held in memory only, and reset on
-- disconnect. A hook with neither fires every time it is called.
-- ============================================================================

-- ============================================================================
-- Escalation
--
-- Some crimes are only as bad as how they go. Robbing a till is theft; robbing
-- a till after shooting someone, or with police already on you, is a different
-- act. A hook that declares an `escalate` block swaps to those values instead
-- of its own whenever ANY condition below is true at the moment it fires, so
-- the SAME robbery can land as 'bad' or 'terrible' depending on what the
-- player did on the way to it.
--
-- Checked server-side in ApplyHook (server/main.lua) against state the server
-- already tracks: the wanted level qbx_honor's own client watcher reports, and
-- the timestamp of the last violent hook that player set off.
-- ============================================================================

Config.Escalation = {
    -- Cops are already on you when the crime pays out.
    whenWanted = true,

    -- You killed someone (kill_civilian / kill_cop) within the window below.
    -- This is what turns "robbed a store" into "robbed a store and shot the
    -- clerk" without needing the robbery script to tell us anything.
    whenRecentKill = true,
    recentKillWindowMs = 180000, -- 3 minutes

    -- Hooks whose firing marks a player as recently violent, for the check
    -- above. Not the same list as the 'terrible' severities: antagonizing or
    -- aiming at someone is unpleasant, not violent.
    violentHooks = {
        kill_civilian = true,
        kill_cop = true,
        kill_player = true,
    },
}

---@class HonorHookEscalation
---@field delta? number replaces the hook's delta when it fires
---@field label? string replaces the hook's label
---@field severity? 'good' | 'bad' | 'terrible' defaults to 'terrible'

---@class HonorHook
---@field delta number
---@field cooldownMs? number
---@field sessionCap? number
---@field label? string shown as the reason on vice_hud's honor panel
---@field severity? 'good' | 'bad' | 'terrible' which centre-popup face this deed shows
---@field escalate? HonorHookEscalation used instead when Config.Escalation matches

---@type table<string, HonorHook>
Config.Hooks = {
    -- ---------- Crimes ------------------------------------------------------

    -- qbx_honor's own client watcher (client/main.lua), per wanted-star increase.
    -- Deliberately just 'bad', not 'terrible' -- getting a star is the crime
    -- itself, not yet a choice about how you handle it. How the encounter ENDS
    -- is what kill_cop / complied_with_police below are for.
    wanted_level    = { delta = -5,  cooldownMs = 15000, label = 'Wanted by police', severity = 'bad' },

    -- qbx_honor's own conduct watcher (client/conduct.lua). See ConductWatcher
    -- below for what counts as a civilian and what counts as self-defence.
    kill_civilian   = { delta = -8,  cooldownMs = 4000, label = 'Killed a bystander', severity = 'terrible' },
    kill_animal     = { delta = -2,  cooldownMs = 4000, label = 'Killed an animal', severity = 'bad' },
    aim_at_civilian = { delta = -1,  cooldownMs = 45000, sessionCap = 6, label = 'Threatened a civilian', severity = 'bad' },
    -- qbx_honor's conduct watcher: the ox_target "Antagonize" option on a civilian.
    antagonize_npc  = { delta = -2,  cooldownMs = 45000, sessionCap = 8, label = 'Antagonized a civilian', severity = 'bad' },

    -- qbx_honor's own conduct watcher: a COP-type ped killed, full stop. Always
    -- 'terrible' -- unlike kill_civilian this skips the self-defence/armed-ped
    -- exemptions entirely (see classifyKill() in client/conduct.lua), because
    -- an officer engaging a wanted suspect isn't the same "innocent victim"
    -- case those exemptions exist for. Bigger delta than kill_civilian on
    -- purpose: killing law enforcement is the worse of the two.
    kill_cop        = { delta = -15, cooldownMs = 4000, label = 'Killed a police officer', severity = 'terrible' },

    -- qbx_honor's own conduct watcher: killing another PLAYER. Self-defence
    -- still applies (a player who shot you inside selfDefenceGraceMs is free,
    -- exactly as a ped would be), but armedPedsAreFairGame deliberately does
    -- NOT -- in a firefight practically everyone is holding a weapon, so
    -- honouring it here would exempt essentially every kill and make the hook
    -- decorative. Turn the whole thing off with ConductWatcher.penalisePlayerKills
    -- on a server where PvP is its own system with its own rules.
    kill_player     = { delta = -15, cooldownMs = 4000, label = 'Killed another person', severity = 'terrible' },

    -- fenix-police (issueTicket) / um_livingworld/arrest (reportArrest):
    -- submitted to a traffic stop or arrest instead of running or fighting.
    -- Small and cooled down hard -- this rewards the CHOICE to comply, not
    -- getting caught repeatedly.
    complied_with_police = { delta = 3, cooldownMs = 120000, label = 'Complied with police', severity = 'good' },

    -- qbx_honor's own conduct watcher: pulling a driver out of their car
    -- (IS_PED_JACKING, so an empty car you simply take isn't this - that's
    -- window_smash's territory). Theft with a victim present, hence a step
    -- above window_smash but still 'bad': nobody got hurt yet.
    carjack         = { delta = -4, cooldownMs = 30000, label = 'Carjacked a driver', severity = 'bad' },

    -- ---------- Robbery -----------------------------------------------------
    -- Robbery is theft until it turns violent, so these are 'bad' by default
    -- with an `escalate` block for the version where someone got shot or the
    -- police were already on you (see Config.Escalation above).

    -- jewelery_heist: robbing a vitrine.
    jewelry_heist   = { delta = -8, label = 'Robbed a jeweller', severity = 'bad',
        escalate = { delta = -16, label = 'Robbed a jeweller at gunpoint', severity = 'terrible' } },
    -- um_truckrobbery: looting a blown armoured truck. Blowing the doors is
    -- inherently loud, so this escalates more often than not - which is the
    -- point, not a bug.
    truck_robbery   = { delta = -10, label = 'Robbed an armoured truck', severity = 'bad',
        escalate = { delta = -18, label = 'Robbed an armoured truck in a firefight', severity = 'terrible' } },

    -- loaf_storerobbery: the till/safe paying out (hooked in that resource's
    -- OPEN framework adapter, which its own escrow_ignore exposes for exactly
    -- this - no bytecode is touched).
    store_robbery   = { delta = -6, label = 'Robbed a store', severity = 'bad',
        escalate = { delta = -14, label = 'Robbed a store at gunpoint', severity = 'terrible' } },
    -- um_rob_atm: cracking a cash machine. The smallest of the robberies -
    -- there is no one behind the counter to terrorise.
    atm_robbery     = { delta = -4, cooldownMs = 60000, label = 'Robbed an ATM', severity = 'bad',
        escalate = { delta = -10, label = 'Robbed an ATM with police on you', severity = 'terrible' } },
    -- loaf_bankrobbery: the big one.
    bank_robbery    = { delta = -12, label = 'Robbed a bank', severity = 'bad',
        escalate = { delta = -20, label = 'Robbed a bank in a firefight', severity = 'terrible' } },

    -- tk_drugs: a CLEAN sale is deliberately not here at all - no hook, no
    -- honor change. Dealing only costs you when it goes wrong in public: the
    -- buyer refuses you, or they get on the phone to the police.
    drug_deal_rejected = { delta = -2, cooldownMs = 60000, sessionCap = 10, label = 'Botched a drug deal', severity = 'bad' },
    drug_deal_caught   = { delta = -4, cooldownMs = 60000, label = 'Caught dealing drugs', severity = 'bad' },

    -- qbx_vehiclekeys: smashing a locked vehicle's window to break in.
    window_smash    = { delta = -4, label = 'Broke into a vehicle', severity = 'bad' },
    -- um_HouseRobberys: fencing what you carried out of someone's home.
    -- Plain theft - the fencing happens long after and nobody is present.
    house_robbery   = { delta = -6, label = 'Fenced stolen property', severity = 'bad' },
    -- caticus-chopshop: taking the cash payout for a stripped stolen car.
    chop_shop       = { delta = -5, label = 'Chopped a stolen car', severity = 'bad' },
    -- um_pawnshop: melting down jewellery so it can't be traced.
    pawn_melt       = { delta = -3,  cooldownMs = 120000, label = 'Melted down jewellery', severity = 'bad' },
    -- um_beg: selling to the hobo fence.
    hobo_fence      = { delta = -2,  cooldownMs = 120000, label = 'Sold to a fence', severity = 'bad' },
    -- um_beg: picking a stranger's pocket.
    pickpocket      = { delta = -3,  cooldownMs = 120000, label = 'Picked a pocket', severity = 'bad' },

    -- ---------- Good conduct ------------------------------------------------

    -- fusion_fishing: putting a landed fish back in the water instead of
    -- keeping it. Keeping the fish is deliberately neutral - no gain, no loss.
    fish_release    = { delta = 2,   cooldownMs = 30000, sessionCap = 20, label = 'Released a fish', severity = 'good' },
    -- qbx_honor's conduct watcher: the ox_target "Greet" option on a civilian.
    greet_npc       = { delta = 1,   cooldownMs = 180000, sessionCap = 6, label = 'Greeted a stranger', severity = 'good' },
    -- qbx_geocaching: finding or trading a cache.
    geocache        = { delta = 3, label = 'Found a geocache', severity = 'good' },
    -- qbox_bounties: collecting a lawful bounty.
    bounty          = { delta = 4, label = 'Collected a bounty', severity = 'good' },
    -- um_beg: finishing a job for the church.
    church_job      = { delta = 3, label = 'Helped at the church', severity = 'good' },
    -- um_beg: finishing an odd job, or washing a windshield for change.
    odd_job         = { delta = 1,   cooldownMs = 300000, sessionCap = 6, label = 'Did an odd job', severity = 'good' },
    -- Legal route/labour work: um_busjob, um_taxijob, um_garbagejob,
    -- um_truckerjob, oil_rigging (selling crude), wreck_salvage (selling
    -- scrap). These pay per passenger / per bag / per sale, so the throttle
    -- does the real work - honest labour nudges honor up over a shift, it
    -- doesn't grind it up.
    honest_work     = { delta = 1,   cooldownMs = 600000, sessionCap = 8, label = 'An honest day\'s work', severity = 'good' },
    -- qbox_barnfinds: paying to restore a derelict rather than stripping it.
    barn_find       = { delta = 2, label = 'Restored a derelict', severity = 'good' },
    -- petty_crime: breaking into a real vending machine. Loud/visible -
    -- pairs with a wanted-level bump (server/main.lua), unlike meter_theft.
    vending_robbery = { delta = -3, cooldownMs = 90000, label = 'Broke into a vending machine', severity = 'bad' },
    -- petty_crime: jimmying a real parking meter. Deliberately the smallest
    -- delta in this file, with the tightest cap - meant to be genuinely
    -- petty even if farmed all shift, not a real honor lever.
    meter_theft     = { delta = -1, cooldownMs = 60000, sessionCap = 10, label = 'Broke into a parking meter', severity = 'bad' },
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
        -- The player-model types. A REAL player never reaches this table --
        -- classifyKill()'s IsPedAPlayer branch catches them first and reports
        -- kill_player instead. These entries are for NPCs wearing a player
        -- model, which report the same types and were previously falling
        -- through to "gangs, criminals: free": the client log showed a long
        -- run of `fatal hit by us on ped N (type 0) -> no honor cost`, which
        -- is exactly that hole.
        [0] = true,  -- PLAYER_0
        [1] = true,  -- PLAYER_1
        [2] = true,  -- NETWORK_PLAYER
        [3] = true,  -- PLAYER_2
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

    -- A COP-type ped killed always reports 'kill_cop', not 'kill_civilian' --
    -- checked in classifyKill() BEFORE the self-defence/armed-ped exemptions
    -- civilianPedTypes gets, so an officer engaging a wanted suspect still
    -- costs full honor even though they shot first. [6] stays in
    -- civilianPedTypes too (below) so Greet/Antagonize still work on cops --
    -- this only changes what a KILL reports.
    copPedTypes = {
        [6] = true, -- COP
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

    -- Dragging a driver out of their car (IS_PED_JACKING -- an empty parked
    -- car is qbx_vehiclekeys' window_smash, not this). On by default: unlike
    -- aiming, this is a deliberate act with a victim, not something a player
    -- does by accident every few seconds.
    penaliseCarjacking = true,

    -- Killing another PLAYER (Config.Hooks.kill_player). Set false on a server
    -- where PvP is governed by its own rules and shouldn't touch honor at all.
    -- See that hook's comment for which exemptions apply and which don't.
    penalisePlayerKills = true,

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
