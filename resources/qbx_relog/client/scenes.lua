-- Arrival scenes: where the character is, and what they're doing, when the
-- switch camera lands.
--
-- Singleplayer doesn't bring you back to where you left a character. It cuts to
-- them somewhere else -- on a bench on the phone, asleep in the trailer, coming
-- out of the barber's -- in the middle of something. Rockstar's
-- player_timetable_scene does that in two halves, and so does this file:
--
--   stage()  while the camera is still up in the clouds -- the ped is already at
--            its spot, so load the dict, put the prop in the hand, start the
--            scene's looping idle. The descent then comes down onto someone
--            already mid-cigarette.
--   play()   once the switch has finished -- play the exit anim, let go of the
--            prop at the phase Rockstar lets go of it, and hand control back
--            when the clip passes its WalkInterruptible tag.
--
-- A scene is played either at one of Rockstar's own spots (the character is
-- moved there first; see pickSpot) or, for scenes marked `here`, wherever the
-- character logged out. The scene list and every spot live in Config.scenes.

Relog = Relog or {}

-- ANIMATION_FLAGS, as Rockstar's scripts spell them.
local AF_LOOPING = 1
local AF_HOLD_LAST_FRAME = 2
local AF_NOT_INTERRUPTABLE = 8

-- func_8's defaults in player_timetable_scene: loop 9, exit 0.
local DEFAULT_FLAGS = { AF_LOOPING | AF_NOT_INTERRUPTABLE, 0 }

-- Blend speeds singleplayer uses here: INSTANT_BLEND_IN for the loop so the
-- pose is already set when the camera arrives, NORMAL_BLEND_IN into the exit,
-- REALLY_SLOW_BLEND_OUT back to the ordinary idle.
local INSTANT_BLEND_IN = 1000.0
local NORMAL_BLEND_IN = 8.0
local NORMAL_BLEND_OUT = -8.0
local REALLY_SLOW_BLEND_OUT = -1.5

-- TASK_PLAY_ANIM_ADVANCED's rotation order, as Rockstar passes it (EULER_YXZ).
local ROT_ORDER = 2

-- Held off until the exit anim can be walked out of, so a stray click doesn't
-- draw a weapon through the middle of a phone call.
local BLOCKED_CONTROLS = {
    21,  -- INPUT_SPRINT
    22,  -- INPUT_JUMP
    23,  -- INPUT_ENTER
    24,  -- INPUT_ATTACK
    25,  -- INPUT_AIM
    37,  -- INPUT_SELECT_WEAPON
    44,  -- INPUT_COVER
    140, -- INPUT_MELEE_ATTACK_LIGHT
    141, -- INPUT_MELEE_ATTACK_HEAVY
    142, -- INPUT_MELEE_ATTACK_ALTERNATE
    257, -- INPUT_ATTACK2
}

local INPUT_MOVE_LR = 30
local INPUT_MOVE_UD = 31

---@type string? id of the last scene played, so the same one doesn't come up twice running
local lastSceneId

---@class StagedScene
---@field scene table the Config.scenes entry
---@field spot table? the Rockstar spot it's anchored to; nil when played where the character stood
---@field ped number the ped it was staged on
---@field prop number? the held object, until it's let go of

---@type StagedScene?
local current

--#region Helpers

---ENTITY::FIND_ANIM_EVENT_PHASE. Invoked by hash: FiveM's Lua binding types the
---two outputs as Any*, which marshals them as ints and reads the float phase
---back as garbage.
---@return number? phase where the tag starts, nil if the clip doesn't have it
local function eventPhase(dict, clip, event)
    local ok, found, start = pcall(Citizen.InvokeNative, 0x07F1BE2BCCAA27A7, dict, clip, event,
        Citizen.PointerValueFloat(), Citizen.PointerValueFloat(), Citizen.ReturnResultAnyway())
    -- A raw invoke may hand the BOOL back as a number, and 0 is truthy in Lua.
    if ok and (found == true or (type(found) == 'number' and found ~= 0)) then return start end
end

---@param hours {[1]: integer, [2]: integer}
---@param hour integer
local function inHours(hours, hour)
    local from, to = hours[1], hours[2]
    if from <= to then return hour >= from and hour < to end
    return hour >= from or hour < to
end

---@param scene table
---@param index 1|2 1 = loop, 2 = exit
local function flagsOf(scene, index)
    return (scene.flags or DEFAULT_FLAGS)[index]
end

---@param pool table[]
---@return table?
local function weightedPick(pool)
    local total = 0
    for i = 1, #pool do total += pool[i].weight or 1 end

    local roll = math.random() * total
    for i = 1, #pool do
        roll -= pool[i].weight or 1
        if roll <= 0 then return pool[i] end
    end

    return pool[#pool]
end

---Never the same one twice running, unless it's the only one there is.
---@param pool table[]
local function dropLast(pool)
    if #pool < 2 or not lastSceneId then return end

    for i = #pool, 1, -1 do
        if pool[i].id == lastSceneId then
            table.remove(pool, i)
            return
        end
    end
end

---Plays a clip either on the ped where it stands, or anchored to a spot's
---origin the way Rockstar's synchronized scenes are. TASK_PLAY_ANIM_ADVANCED
---at the scene origin is what player_timetable_scene itself uses for its
---single-ped placements, and unlike a local synchronized scene it's an ordinary
---anim task, so other players see it too.
---@param staged StagedScene
local function playClip(staged, clip, blendIn, blendOut, flags)
    local scene, spot, ped = staged.scene, staged.spot, staged.ped

    if spot and not spot.anim then
        local at = spot.at
        TaskPlayAnimAdvanced(ped, scene.dict, clip, at.x, at.y, at.z, 0.0, 0.0, at.w,
            blendIn, blendOut, -1, flags, 0.0, ROT_ORDER, 0)
    else
        TaskPlayAnim(ped, scene.dict, clip, blendIn, blendOut, -1, flags, 0.0, false, false, false)
    end
end

---Lets go of the held prop: dropped props fall and stay (the cup Franklin
---throws), the rest disappear the way a phone goes back into a pocket.
---@param staged StagedScene
local function releaseProp(staged)
    local prop = staged.prop
    if not prop then return end
    staged.prop = nil

    if not DoesEntityExist(prop) then return end

    if staged.scene.prop.drop then
        DetachEntity(prop, true, true)
        SetEntityDynamic(prop, true)
        SetObjectAsNoLongerNeeded(prop)
    else
        DeleteObject(prop)
    end
end

--#endregion

--#region Picking

---@return 'none'|'relocate'|'here'
local function roll()
    if math.random() >= Config.sceneChance then return 'none' end
    return math.random() < Config.sceneRelocateChance and 'relocate' or 'here'
end

---@param at vector4
---@return boolean
local function spotIsClear(at)
    local clearance = Config.sceneSpotClearance
    local own = PlayerId()

    for _, player in ipairs(GetActivePlayers()) do
        if player ~= own and #(GetEntityCoords(GetPlayerPed(player)) - at.xyz) < clearance then
            return false
        end
    end

    return true
end

---Picks a scene and one of Rockstar's spots for it, for moving the character
---there. Called before the ped is placed, so only the time of day matters.
---@return table? scene
---@return table? spot
local function pickSpot()
    local hour = GetClockHours()
    local pool = {}

    for _, scene in ipairs(Config.scenes) do
        if (scene.weight or 1) > 0 and scene.spots and #scene.spots > 0
            and not (scene.hours and not inHours(scene.hours, hour)) then
            pool[#pool + 1] = scene
        end
    end

    dropLast(pool)

    -- A taken spot costs that scene, not the whole arrival: try the rest.
    while #pool > 0 do
        local scene = weightedPick(pool) --[[@as table]]

        local spots = {}
        for _, spot in ipairs(scene.spots) do
            if spotIsClear(spot.at) then spots[#spots + 1] = spot end
        end

        if #spots > 0 then return scene, spots[math.random(#spots)] end

        for i = #pool, 1, -1 do
            if pool[i] == scene then table.remove(pool, i) end
        end
    end
end

---Everything about where the character landed that a `here` scene might care
---about. Needs the ped already placed and its collision loaded, which
---placeAt() waits for.
---@param ped number
local function describeSpot(ped)
    local coords = GetEntityCoords(ped)
    local found, groundZ, normal = GetGroundZAndNormalFor_3dCoord(coords.x, coords.y, coords.z + 1.0)

    return {
        indoors = GetInteriorFromEntity(ped) ~= 0,
        -- The saved position is the ped's root, about a metre up; much more
        -- than that means the ground found is a floor below, not the one
        -- the character is standing on.
        flat = found and normal.z >= Config.sceneMinFlatness and coords.z - groundZ < 1.6,
        hour = GetClockHours(),
    }
end

---Picks a `here` scene that suits where the character is standing right now.
---@return table? scene nil means land the ordinary way
local function pickHere()
    local ped = PlayerPedId()
    if IsEntityDead(ped) or not IsPedOnFoot(ped) or IsEntityInWater(ped) then return end

    local spot = describeSpot(ped)
    local pool = {}

    for _, scene in ipairs(Config.scenes) do
        if scene.here and (scene.weight or 1) > 0
            and not (scene.outdoors and spot.indoors)
            and not (scene.ground and not spot.flat)
            and not (scene.hours and not inHours(scene.hours, spot.hour)) then
            pool[#pool + 1] = scene
        end
    end

    dropLast(pool)
    if #pool == 0 then return end

    return weightedPick(pool)
end

---@param id string
---@return table?
local function find(id)
    for _, scene in ipairs(Config.scenes) do
        if scene.id == id then return scene end
    end
end

---Rolls whether an arrival scene plays this switch and picks one to fit,
---relocating the character to one of Rockstar's spots first if the roll calls
---for it. Called while the switch camera is still up in the clouds, so the
---teleport for a `relocate` scene is never seen.
---@return table? scene nil means land the ordinary way
---@return table? spot the spot moved to, for stage() to anchor on
local function pick()
    local outcome = roll()
    if outcome == 'none' then return end

    if outcome == 'relocate' then
        local scene, spot = pickSpot()
        if scene then
            Relog.switch.placeAt(spot.at)
            return scene, spot
        end
        -- No relocate scene had a free spot; fall back to a `here` scene.
    end

    return pickHere()
end

--#endregion

--#region Playing

---Cuts a scene short: prop gone, anim cleared. For a new switch starting, the
---resource stopping, or anything else that means the scene no longer applies.
local function stop()
    local staged = current
    current = nil
    if not staged then return end

    if staged.prop and DoesEntityExist(staged.prop) then DeleteObject(staged.prop) end
    staged.prop = nil

    local scene = staged.scene
    if DoesEntityExist(staged.ped) and (IsEntityPlayingAnim(staged.ped, scene.dict, scene.exit, 3)
        or (scene.loop and IsEntityPlayingAnim(staged.ped, scene.dict, scene.loop, 3))) then
        ClearPedTasks(staged.ped)
    end

    RemoveAnimDict(scene.dict)
end

---Sets the scene up on the player ped: prop in hand, idle looping. Meant for
---while the switch camera is up in the air, so none of it is seen happening.
---The ped must already be where the scene happens -- at `spot.at` if a spot is
---given.
---@param scene table
---@param spot table? one of scene.spots; nil plays it wherever the ped stands
---@return StagedScene? staged nil if the dict wouldn't load; land normally
local function stage(scene, spot)
    stop()

    local ped = PlayerPedId()

    -- lib.requestAnimDict / requestModel raise rather than return false.
    if not pcall(lib.requestAnimDict, scene.dict, 5000) then
        lib.print.warn(('arrival scene %s: anim dict %s did not load'):format(scene.id, scene.dict))
        return
    end

    ---@type StagedScene
    local staged = { scene = scene, spot = spot, ped = ped }

    if scene.prop then
        local ok, model = pcall(lib.requestModel, scene.prop.model, 5000)
        if ok then
            local coords = GetEntityCoords(ped)
            local prop = CreateObject(model, coords.x, coords.y, coords.z, true, true, false)
            SetModelAsNoLongerNeeded(model)

            -- Zero offset is correct: the clips are authored with the prop
            -- sitting exactly on the hand's prop bone.
            AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, scene.prop.bone),
                0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
            staged.prop = prop
        end
        -- A missing prop is cosmetic; the scene still plays without it.
    end

    if scene.loop then
        playClip(staged, scene.loop, INSTANT_BLEND_IN, NORMAL_BLEND_OUT, flagsOf(scene, 1))
    elseif not spot or spot.anim then
        -- Exit-only scene: hold its first frame (phase-controlled at 0) so the
        -- descent lands on the starting pose rather than a plain idle.
        TaskPlayAnim(ped, scene.dict, scene.exit, INSTANT_BLEND_IN, NORMAL_BLEND_OUT, -1,
            AF_HOLD_LAST_FRAME, 0.0, true, false, false)
    end
    -- An anchored exit-only scene has no way to freeze on frame 0; the ped is
    -- already stood on the origin, facing the right way, which is the pose the
    -- exit starts from anyway.

    current = staged
    lastSceneId = scene.id
    return staged
end

---@return boolean
local function wantsToMove()
    return math.abs(GetDisabledControlNormal(0, INPUT_MOVE_LR)) > 0.25
        or math.abs(GetDisabledControlNormal(0, INPUT_MOVE_UD)) > 0.25
end

---Plays the exit anim of a staged scene, blocking until it's over. Call once
---the switch camera is back on the ground.
---@param staged StagedScene
local function play(staged)
    if current ~= staged then return end

    local scene, ped = staged.scene, staged.ped

    -- illenium-appearance can still swap the ped late on a slow load. If it
    -- did, the prop is on a ped that no longer exists and the new one never
    -- got the idle; drop the scene rather than pop into the exit from nothing.
    if PlayerPedId() ~= ped or IsEntityDead(ped) then
        stop()
        return
    end

    playClip(staged, scene.exit, NORMAL_BLEND_IN, REALLY_SLOW_BLEND_OUT, flagsOf(scene, 2))

    local started = GetGameTimer() + 1000
    while not IsEntityPlayingAnim(ped, scene.dict, scene.exit, 3) and GetGameTimer() < started do Wait(0) end

    local breakout = eventPhase(scene.dict, scene.exit, 'WalkInterruptible')
        or eventPhase(scene.dict, scene.exit, 'END_IN_WALK')
        or Config.sceneBreakoutPhase

    -- Backstop for a clip that somehow never reports finishing.
    local giveUpAt = GetGameTimer() + math.floor(GetAnimDuration(scene.dict, scene.exit) * 1000) + 3000

    while current == staged do
        if not IsEntityPlayingAnim(ped, scene.dict, scene.exit, 3) then break end
        if PlayerPedId() ~= ped or IsEntityDead(ped) or IsPedRagdoll(ped) then break end
        if GetGameTimer() > giveUpAt then break end

        local phase = GetEntityAnimCurrentTime(ped, scene.dict, scene.exit)

        if staged.prop and phase >= scene.prop.release then releaseProp(staged) end

        if phase >= breakout then
            if wantsToMove() then
                ClearPedTasks(ped)
                break
            end
        else
            for i = 1, #BLOCKED_CONTROLS do DisableControlAction(0, BLOCKED_CONTROLS[i], true) end
        end

        Wait(0)
    end

    -- Cut short before the prop's moment: it still leaves the hand the way it
    -- would have, rather than staying glued to a ped that's walked off.
    releaseProp(staged)

    if current == staged then
        current = nil
        RemoveAnimDict(scene.dict)
    end
end

--#endregion

if Config.sceneTestCommand then
    ---@param id string?
    ---@param here boolean
    local function test(id, here)
        local scene, spot

        if id then
            scene = find(id)
            if not scene then
                local ids = {}
                for i, s in ipairs(Config.scenes) do ids[i] = s.id end
                exports.qbx_core:Notify(('No scene "%s". Try: %s'):format(id, table.concat(ids, ', ')), 'error')
                return
            end
            if here and not scene.here then
                exports.qbx_core:Notify(('%s only plays at its own spots.'):format(id), 'error')
                return
            end
            if not here then
                if not (scene.spots and #scene.spots > 0) then
                    exports.qbx_core:Notify(('%s has no spots left; try "%s here".'):format(id, id), 'error')
                    return
                end
                spot = scene.spots[math.random(#scene.spots)]
            end
        elseif here then
            scene = pickHere()
        else
            scene, spot = pickSpot()
        end

        if not scene then
            exports.qbx_core:Notify('No scene fits right now.', 'error')
            return
        end

        exports.qbx_core:Notify(spot and ('Scene: %s (sp %d)'):format(scene.id, spot.sp)
            or ('Scene: %s'):format(scene.id), 'inform')

        if spot then
            DoScreenFadeOut(300)
            while not IsScreenFadedOut() do Wait(0) end
            Relog.switch.placeAt(spot.at)
        end

        local staged = stage(scene, spot)
        if spot then DoScreenFadeIn(300) end
        if not staged then return end

        -- Long enough to see the idle, as the switch descent would show it.
        Wait(1500)
        play(staged)
    end

    RegisterCommand(Config.sceneTestCommand, function(_, args)
        local here = args[1] == 'here' or args[2] == 'here'
        local id = args[1] ~= 'here' and args[1] or nil
        test(id, here)
    end, false)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    stop()
end)

Relog.scenes = {
    roll = roll,
    pickSpot = pickSpot,
    pickHere = pickHere,
    pick = pick,
    stage = stage,
    play = play,
    stop = stop,
}
