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
    -- character -- where they logged out, or somewhere else entirely if an
    -- arrival scene below moves them) instead of going through the
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

    --#region Arrival scenes

    -- Singleplayer rarely drops you onto a character standing idle: the camera
    -- comes down on Michael finishing a cigarette or Franklin hanging up the
    -- phone. These are those scenes, lifted from Rockstar's own
    -- player_timetable_scene script (fetch it with
    -- `_tools/decompiled_scripts/fetch.py get player_timetable_scene` -- the
    -- loop/exit table is the function holding "SWITCH@FRANKLIN@STRIPCLUB", the
    -- prop table the one holding "prop_phone_ing_03"). The `sp` numbers below
    -- are Rockstar's scene ids from those tables, so each entry can be traced
    -- back to the original.
    --
    -- Every scene carries the spot(s) where Rockstar staged it, straight out of
    -- the `initial` script's scene-position table and player_timetable_scene's
    -- heading table. Singleplayer doesn't bring you back to where you left a
    -- character -- it cuts to them somewhere else, in the middle of something
    -- -- so most switches here do the same: the character is moved to one of
    -- those spots, and that becomes where they are now.
    --
    -- Left out: anything that needs a partner ped (Amanda, Lamar, Floyd, a
    -- bouncer), a vehicle, or furniture Rockstar spawns itself rather than one
    -- that's part of the map. Benches, beds and sofas are in the map, so those
    -- scenes are in. Yellow Jack's bar scene is out because int_yellowjack
    -- replaces that interior on this server.

    -- Chance (0-1) that a switch plays a scene at all. The rest of the time the
    -- character is standing wherever they logged out, the way it was before
    -- scenes existed.
    sceneChance = 0.8,

    -- Of the switches that do play a scene, the chance (0-1) it happens at one
    -- of Rockstar's spots rather than where the character logged out. The rest
    -- play one of the `here = true` scenes on the spot they logged out at.
    sceneRelocateChance = 0.65,

    -- Won't move a character onto a spot another player is standing within
    -- this many metres of. Another of that scene's spots is tried instead.
    sceneSpotClearance = 3.0,

    -- The player can walk out of a scene once its exit anim passes Rockstar's
    -- own `WalkInterruptible` (or `END_IN_WALK`) tag, the same rule
    -- singleplayer uses. For a clip without either tag, this phase (0-1) is
    -- used instead so nobody is ever locked into an anim to the very end.
    sceneBreakoutPhase = 0.5,

    -- Scenes marked `ground` lie, sit or do press-ups on the floor, so when
    -- they play where the character logged out, that spot's ground normal must
    -- have at least this much up in it (1.0 = perfectly flat). Stops a wake-up
    -- scene clipping into a hillside. Rockstar's own spots aren't checked.
    sceneMinFlatness = 0.95,

    -- `/relogscene [id] [here]` plays a scene with no switch, for trying them
    -- out: at one of its Rockstar spots (teleports you), or where you stand if
    -- `here` is given. No id = a random pick using the same rules as a real
    -- switch. false to disable.
    sceneTestCommand = 'relogscene',

    -- Each scene: `dict` + `loop` (held while the camera comes down; nil holds
    -- the first frame of `exit` instead, which is what Rockstar's exit-only
    -- scenes amount to) + `exit` (played on landing).
    --   weight    relative odds among the scenes that fit; 0 disables one
    --   spots     Rockstar's placements: `sp` is the scene id in
    --             player_timetable_scene / initial, `at` the scene origin and
    --             heading. `anim = true` marks the few Rockstar played as a
    --             plain anim on the ped rather than a scene anchored at `at`.
    --   here      can also play wherever the character logged out
    --   prop      held item: model, hand bone (28422 right, 60309 left), the
    --             exit phase it leaves the hand at, and whether it drops to the
    --             ground there or simply vanishes (tucked into a pocket)
    --   ground    needs flat ground when played `here` (see sceneMinFlatness)
    --   outdoors  never plays `here` inside an interior
    --   hours     {from, to} in-game hours it may play, wrapping past midnight
    --   flags     {loop, exit} anim flags where Rockstar overrode the default
    --             {9, 0}; 1545/1544 add no-collision + override-physics for
    --             scenes that sit inside furniture (toilet, sunlounger)
    --
    -- Generated from the decompiled scripts, not typed by hand; see HANDOFF.md
    -- before adding spots so the numbers stay traceable.
    scenes = {
        { id = 'cigarette', weight = 10, dict = 'switch@michael@smoking2', loop = 'LOOP', exit = 'EXIT', here = true,
          prop = { model = 'prop_cigar_01', bone = 28422, release = 0.85, drop = true },
          spots = {
            { sp = 81, at = vec4(-1313.7480, 121.4050, 56.6578, 315.0000) },
            { sp = 91, at = vec4(-1210.3170, -955.7397, 1.6553, 105.0795) },
            { sp = 92, at = vec4(-848.0614, 855.9160, 202.5614, 305.6530) },
            { sp = 93, at = vec4(-1268.6400, -711.4000, 22.4619, 117.0000) },
            { sp = 104, at = vec4(-1927.7800, -579.0700, 11.1705, 123.0000) },
            -- sp 126/304 (Trevor's trailer porch) dropped -- see note above sunlounger.
          } },
        -- cigarette_2 (sp 161, Michael's mansion patio) dropped -- house-anchored, no `here` fallback.
        { id = 'cigarette_pier', weight = 4, dict = 'switch@michael@pier', loop = 'pier_lean_smoke_idle', exit = 'pier_lean_smoke_outro',
          prop = { model = 'prop_cigar_01', bone = 28422, release = 0.85, drop = true },
          spots = {
            { sp = 103, at = vec4(-1731.9400, -1125.1300, 13.0176, 143.4931) },
          } },
        -- phone_call's only spot (187) was Franklin's Chamberlain Hills house; kept as
        -- a `here` scene, just no longer relocates the character there.
        { id = 'phone_call', weight = 8, dict = 'switch@franklin@on_cell', loop = '001914_01_FRAS_V2_2_ON_CELL_IDLE', exit = '001914_01_FRAS_V2_2_ON_CELL_EXIT', here = true,
          prop = { model = 'prop_phone_ing_03', bone = 28422, release = 0.85 },
          spots = {} },
        { id = 'phone_hang_up', weight = 6, dict = 'missheist_agency2aig_9', loop = 'Franklin_call_Michael_IDLE_PLAYER', exit = 'Franklin_call_Michael_EXIT_PLAYER', here = true,
          prop = { model = 'prop_phone_ing_03', bone = 28422, release = 0.85 },
          spots = {
            { sp = 233, at = vec4(-78.4023, -1019.2350, 28.5449, 109.0206) },
          } },
        -- Same as phone_call: sp 197 was Franklin's Chamberlain Hills house.
        { id = 'phone_pacing', weight = 5, dict = 'switch@franklin@walk_around_house', loop = 'IDLE_FRANKLIN', exit = 'EXIT_FRANKLIN', here = true,
          prop = { model = 'prop_phone_ing_03', bone = 28422, release = 0.7 },
          spots = {} },
        { id = 'phone_stripclub', weight = 3, dict = 'switch@franklin@stripclub', loop = '002113_02_FRAS_15_STRIPCLUB_IDLE', exit = '002113_02_FRAS_15_STRIPCLUB_EXIT',
          prop = { model = 'prop_phone_ing_03', bone = 28422, release = 0.9 },
          spots = {
            { sp = 11, at = vec4(115.1569, -1286.6840, 28.2613, 111.0000) },
          } },
        { id = 'phone_on_bench', weight = 6, dict = 'switch@michael@bench', loop = 'bench_on_phone_idle', exit = 'EXIT_FORWARD',
          prop = { model = 'prop_phone_ing', bone = 28422, release = 1.0 },
          spots = {
            { sp = 110, at = vec4(-95.5500, -415.1000, 35.6806, 133.0000) },
            { sp = 111, at = vec4(-1292.7010, -697.2287, 24.2677, 33.0000) },
            -- sp 131/132 (Trevor's trailer porch) dropped.
          } },
        { id = 'wipe_hands', weight = 6, dict = 'switch@franklin@chopshop', loop = 'BASE', exit = 'WipeHands', here = true,
          spots = {
            { sp = 223, at = vec4(473.3613, -1309.9950, 29.2326, 43.8200) },
          } },
        { id = 'wipe_off', weight = 5, dict = 'switch@franklin@chopshop', loop = 'BASE', exit = 'WipeRight', here = true,
          spots = {
            { sp = 224, at = vec4(480.9113, -1316.3550, 29.1966, 300.6152) },
          } },
        { id = 'check_shoe', weight = 5, dict = 'switch@franklin@chopshop', loop = 'BASE', exit = 'CheckShoe', here = true,
          spots = {
            { sp = 222, at = vec4(480.9113, -1316.3550, 29.1966, 300.6152) },
          } },
        { id = 'coffee_toss', weight = 6, dict = 'switch@franklin@throw_cup', loop = 'throw_cup_loop', exit = 'throw_cup_exit', here = true,
          prop = { model = 'p_amb_coffeecup_01', bone = 28422, release = 0.7, drop = true },
          spots = {
            { sp = 200, at = vec4(2.8895, -1607.2860, 29.2949, 130.8790) },
          } },
        { id = 'coffee_knocked', weight = 4, dict = 'switch@franklin@hit_cup_hand', loop = 'hit_cup_hand_loop', exit = 'hit_cup_hand_exit', here = true,
          prop = { model = 'p_amb_coffeecup_01', bone = 28422, release = 0.74, drop = true },
          spots = {
            { sp = 201, at = vec4(2.8895, -1607.2860, 29.2866, 130.8790) },
          } },
        { id = 'coffee_to_go', weight = 5, dict = 'switch@michael@cafe', loop = 'Cafe_Idle_PED', exit = 'Cafe_Exit_PED',
          prop = { model = 'p_ing_coffeecup_01', bone = 28422, release = 0.85, drop = true },
          spots = {
            { sp = 115, at = vec4(-511.7300, -21.8700, 45.5884, 69.0000) },
            { sp = 117, at = vec4(-834.5300, -350.7100, 38.6537, 285.2182) },
          } },
        -- trash_toss's only spot (198) was the curb outside Franklin's aunt's house.
        { id = 'trash_toss', weight = 5, dict = 'switch@franklin@garbage', loop = 'Garbage_Idle_PLYR', exit = 'Garbage_Toss_PLYR', here = true,
          prop = { model = 'prop_cs_rub_binbag_01', bone = 28422, release = 0.6645, drop = true },
          spots = {} },
        -- trash_toss_2 (sp 199, Franklin's Chamberlain Hills house yard) dropped --
        -- house-anchored, no `here` fallback.
        -- getting_dressed's only spot (178) was Franklin's Chamberlain Hills house.
        { id = 'getting_dressed', weight = 4, dict = 'switch@franklin@getting_ready', loop = '002334_02_FRAS_V2_11_GETTING_DRESSED_IDLE', exit = '002334_02_FRAS_V2_11_GETTING_DRESSED_EXIT', here = true,
          spots = {} },
        { id = 'notepad', weight = 5, dict = 'switch@trevor@at_the_docks', loop = '001209_01_TRVS_3_AT_THE_DOCKS_IDLE', exit = '001209_01_TRVS_3_AT_THE_DOCKS_EXIT', here = true,
          prop = { model = 'p_notepad_01_s', bone = 60309, release = 0.8989 },
          spots = {
            { sp = 250, at = vec4(288.0774, -3201.8810, 5.8080, 87.0000) },
            { sp = 251, at = vec4(-871.2493, 67.3477, 52.1137, 317.1471) },
            { sp = 252, at = vec4(-46.1798, -1474.1640, 32.0083, 2.6497) },
            { sp = 253, at = vec4(1876.0250, 2620.8270, 45.6722, 135.0000) },
          } },
        { id = 'saying_goodbye', weight = 4, dict = 'switch@michael@goodbye_to_soloman', loop = 'LOOP_Michael', exit = 'EXIT_Michael', here = true,
          spots = {
            { sp = 154, at = vec4(-718.8735, 256.4936, 79.8259, 212.8080) },
          } },
        { id = 'saying_goodbye_2', weight = 3, dict = 'switch@michael@goodbye_to_soloman', loop = '001400_01_MICS3_5_BYE_TO_SOLOMAN_IDLE', exit = '001400_01_MICS3_5_BYE_TO_SOLOMAN_EXIT',
          spots = {
            { sp = 153, at = vec4(-718.8135, 256.7636, 79.8384, 183.7500) },
          } },
        -- reading_script (sp 164, Michael's mansion) dropped -- house-anchored, no
        -- `here` fallback.
        { id = 'marina', weight = 3, dict = 'switch@michael@marina', loop = 'loop', exit = 'exit',
          spots = {
            { sp = 121, at = vec4(-831.3530, -1358.7480, 4.9732, 101.5000) },
          } },
        { id = 'gym_chin_ups', weight = 3, dict = 'switch@franklin@gym', loop = '001942_02_GC_FRAS_IG_5_BASE', exit = '001942_02_GC_FRAS_IG_5_EXIT',
          spots = {
            { sp = 202, at = vec4(-1244.8880, -1613.6560, 4.1295, 35.6040) },
          } },
        { id = 'garbage_taco', weight = 3, dict = 'switch@trevor@garbage_food', loop = 'LOOP_Trevor', exit = 'EXIT_Trevor',
          prop = { model = 'prop_taco_01', bone = 60309, release = 0.8308, drop = true },
          spots = {
            { sp = 243, at = vec4(433.8850, -1462.4780, 28.2735, 18.0000) },
          } },
        { id = 'leaving', weight = 6, dict = 'switch@franklin@exit_building', loop = 'loop', exit = 'switch_01', here = true,
          spots = {
            { sp = 226, at = vec4(28.9860, -1351.4120, 29.3437, 160.0000) },
            { sp = 227, at = vec4(-379.1773, 220.9259, 84.1440, 345.2510) },
            { sp = 230, at = vec4(-297.4081, -1332.3430, 31.3057, 316.3339) },
          } },
        { id = 'leaving_2', weight = 5, dict = 'switch@franklin@exit_building', loop = 'loop', exit = 'switch_02', here = true,
          spots = {
            { sp = 228, at = vec4(131.5816, -1303.5580, 29.1592, 210.0000) },
            { sp = 229, at = vec4(792.1553, -735.5871, 27.5721, 96.0116) },
          } },
        { id = 'leaving_shop', weight = 4, dict = 'switch@michael@exits_fancyshop', loop = '001405_01_MICS3_8_EXITS_FANCYSHOP_IDLE', exit = '001405_01_MICS3_8_EXITS_FANCYSHOP_EXIT', here = true,
          spots = {
            { sp = 160, at = vec4(-715.6204, -155.5691, 37.4023, 119.0000) },
          } },
        { id = 'leaving_barber', weight = 3, dict = 'switch@michael@exits_barber', loop = '001406_01_MICS3_7_EXITS_BARBER_IDLE', exit = '001406_01_MICS3_7_EXITS_BARBER_EXIT', here = true,
          spots = {
            { sp = 159, at = vec4(-823.2000, -187.0830, 37.7753, 297.5000) },
          } },
        { id = 'leaving_restaurant', weight = 3, dict = 'switch@michael@exit_restaurant', loop = 'mic_exit_restaurant_loop', exit = 'mic_exit_restaurant_exit', here = true,
          spots = {
            { sp = 95, at = vec4(394.6800, 176.8100, 103.8401, 70.0000) },
          } },
        { id = 'leaving_dispensary', weight = 4, dict = 'switch@franklin@dispensary', loop = 'exit_dispensary_idle', exit = 'exit_dispensary_outro', here = true,
          prop = { model = 'p_weed_bottle_s', bone = 28422, release = 0.65 },
          spots = {
            { sp = 194, at = vec4(-1153.5110, -1371.6520, 4.0730, 292.3920), anim = true },
            { sp = 195, at = vec4(-1162.9870, -1427.2640, 3.6370, 74.1158), anim = true },
          } },
        { id = 'leaving_lingerie_shop', weight = 2, dict = 'switch@trevor@lingerie_shop', loop = 'trev_exit_lingerie_shop_idle', exit = 'trev_exit_lingerie_shop_outro',
          spots = {
            { sp = 254, at = vec4(154.7300, -219.2100, 54.3030, 320.0000) },
          } },
        { id = 'leaving_funeral_home', weight = 2, dict = 'switch@trevor@funeral_home', loop = 'trvs_ig_11_loop', exit = 'trvs_ig_11_exit',
          spots = {
            { sp = 255, at = vec4(411.6250, -1488.9890, 30.1244, 30.2400) },
          } },
        { id = 'tai_chi', weight = 3, dict = 'switch@trevor@rand_temple', exit = 'TAI_CHI_Trevor', here = true, outdoors = true,
          spots = {
            { sp = 287, at = vec4(-888.4500, -853.1100, 19.5602, 279.0000) },
          } },
        { id = 'drunk_howling', weight = 3, dict = 'switch@trevor@drunk_howling', loop = 'loop', exit = 'exit', here = true, outdoors = true, hours = { 20, 5 },
          spots = {
            { sp = 289, at = vec4(440.6737, -228.7473, 55.9725, 348.4982) },
          } },
        { id = 'drunk_howling_2', weight = 2, dict = 'switch@trevor@drunk_howling_sc', loop = 'loop', exit = 'exit', here = true, outdoors = true, hours = { 20, 5 },
          spots = {
            { sp = 290, at = vec4(118.4869, -1286.4140, 28.2610, 231.0000) },
          } },
        { id = 'puking', weight = 3, dict = 'switch@trevor@puking_into_fountain', loop = 'trev_fountain_puke_loop', exit = 'trev_fountain_puke_exit', hours = { 20, 8 },
          spots = {
            { sp = 273, at = vec4(-118.1968, -442.9148, 35.2820, 207.0000) },
            { sp = 274, at = vec4(-1858.9570, 2071.2300, 140.3656, 9.0000) },
          } },
        { id = 'naked_on_bridge', weight = 2, dict = 'switch@trevor@naked_on_bridge', loop = '002055_01_TRVS_17_NAKED_ON_BRIDGE_IDLE', exit = '002055_01_TRVS_17_NAKED_ON_BRIDGE_EXIT', hours = { 5, 10 },
          spots = {
            { sp = 278, at = vec4(642.6800, -1001.2700, 36.8997, 326.2300) },
          } },
        { id = 'passed_out', weight = 5, dict = 'switch@trevor@slouched_get_up', loop = 'TREV_SLOUCHED_GET_UP_IDLE', exit = 'TREV_SLOUCHED_GET_UP_EXIT', here = true, ground = true, hours = { 5, 12 },
          prop = { model = 'prop_cs_beer_bot_01', bone = 28422, release = 0.527, drop = true },
          spots = {
            { sp = 240, at = vec4(1534.0430, 3613.1220, 34.3670, 355.8760), anim = true },
            { sp = 241, at = vec4(-175.4296, 6428.7500, 29.6226, 108.0000), anim = true },
            { sp = 242, at = vec4(-1654.9370, -147.5126, 57.4610, 13.7207), anim = true },
            { sp = 265, at = vec4(-438.0249, 1595.8950, 356.5938, 215.7260), anim = true },
            { sp = 266, at = vec4(-3067.8680, 130.6339, 9.9056, 68.8227), anim = true },
            { sp = 267, at = vec4(2209.6990, 4914.9140, 39.6760, 56.2037), anim = true },
            { sp = 268, at = vec4(1800.0310, 6293.4620, 48.6294, 33.0000), anim = true },
            { sp = 269, at = vec4(418.6078, -788.4689, 43.5311, 253.3395), anim = true },
            { sp = 270, at = vec4(2949.5670, 5755.3390, 317.8481, 258.0000), anim = true },
            { sp = 271, at = vec4(-1267.3890, -1098.8990, 6.8082, 26.3597) },
            { sp = 272, at = vec4(107.0137, -1316.0350, 28.2084, 276.6825), anim = true },
            { sp = 279, at = vec4(-145.8739, 868.3813, 231.6979, 155.6800), anim = true },
          } },
        { id = 'waking_up_outside', weight = 3, dict = 'switch@trevor@naked_island', loop = 'loop', exit = 'exit', here = true, ground = true, outdoors = true, hours = { 5, 12 },
          prop = { model = 'prop_cs_beer_bot_01', bone = 60309, release = 0.4548, drop = true },
          spots = {
            { sp = 280, at = vec4(2789.8450, -1453.7310, 0.5519, 310.4400) },
          } },
        -- press_ups's spots (181/182 Franklin's aunt's house, 183 his Chamberlain
        -- Hills house) were all house-anchored; kept as a `here` scene only.
        { id = 'press_ups', weight = 5, dict = 'switch@franklin@press_ups', loop = 'PressUps_LOOP', exit = 'PressUps_OUT', here = true, ground = true,
          spots = {} },
        -- Removed entirely below (2026-09-17): every remaining spot for these was
        -- inside or right on the porch of one of the three protagonists' own
        -- houses (Michael's Rockford Hills mansion, Franklin's aunt's Strawberry
        -- house or his own Chamberlain Hills house, Trevor's Sandy Shores
        -- trailer), and none of them have a `here` fallback. `club_chair`
        -- (Trevor's trailer, sp 129) is the one that floated a player above the
        -- chair -- the singleplayer furniture that anchors these scenes isn't
        -- guaranteed to exist in the same place on this server's map, and
        -- indoor/porch furniture is exactly where that shows up:
        --   sleeping_trailer (sp 84), bed_asleep (sp 175), bed_reading (sp 179/180),
        --   napping (sp 177), wakes_up_scared (sp 83), watching_tv (sp 85),
        --   watching_tv_2 (sp 191), watching_tv_3 (sp 291), on_the_sofa (sp 79),
        --   sitting (sp 128), club_chair (sp 129), sitting_2 (sp 130),
        --   wash_face (sp 124), head_in_sink (sp 315), cleaning_up (sp 186),
        --   snacking (sp 188), on_the_toilet (sp 234), smoking_meth (sp 40/245)
        { id = 'sunlounger', flags = { 1545, 1544 }, weight = 3, dict = 'switch@michael@sunlounger', loop = 'SunLounger_Idle', exit = 'SunLounger_GetUp', hours = { 9, 19 },
          spots = {
            { sp = 88, at = vec4(-1353.3110, 355.9345, 64.0704, 21.0000) },
            -- sp 184/185 (Franklin's Chamberlain Hills house) dropped.
          } },
    },

    --#endregion
}
