--[[
    Ball handling: spawning, holding, shooting, passing and picking up.

    Ownership model
    ---------------
    The ball is a client-created networked object. Whoever holds it owns it, and
    the server tracks two things only: who is currently carrying a ball, and which
    network ids are loose on the floor. That keeps the physics local (so it feels
    responsive) while still stopping a player from conjuring two balls at once.
]]

local held        = nil     -- entity id of the ball attached to my hand
local charging    = false
local charge      = 0.0
local chargeUp    = true
local busy        = false   -- true during an animation we shouldn't interrupt

BB.loose = {}               -- [netId] = { shooter = serverId, at = ms }

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function loadModel(model)
    if not IsModelInCdimage(model) then
        print(('^1[gk_basketball]^7 model %s is not in the game files'):format(model))
        return false
    end

    RequestModel(model)

    local deadline = GetGameTimer() + 10000
    while not HasModelLoaded(model) do
        if GetGameTimer() > deadline then
            print(('^1[gk_basketball]^7 timed out loading model %s'):format(model))
            return false
        end
        Wait(0)
    end

    return true
end

--- Plays an animation, giving up quietly if the dict never loads. A missing anim
--- should cost you the flourish, not the game.
local function playAnim(cfg, blendIn, onPed)
    if not cfg then return end

    RequestAnimDict(cfg.dict)

    local deadline = GetGameTimer() + 1000
    while not HasAnimDictLoaded(cfg.dict) do
        if GetGameTimer() > deadline then return end
        Wait(0)
    end

    TaskPlayAnim(onPed or PlayerPedId(), cfg.dict, cfg.name, blendIn or 4.0, -4.0, cfg.duration or -1, cfg.flag or 48, 0.0, false, false, false)
end

--- Plays one of our animations on any ped. The NPCs use the same strokes you do.
function BB.playAnim(ped, cfg)
    playAnim(cfg, nil, ped)
end

local function forwardVector()
    local rot = GetGameplayCamRot(2)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local cosX = math.abs(math.cos(x))
    return vec3(-math.sin(z) * cosX, math.cos(z) * cosX, math.sin(x))
end

local function nearestPlayer(radius)
    local me = PlayerPedId()
    local coords = GetEntityCoords(me)
    local best, bestDist

    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        if ped ~= me and DoesEntityExist(ped) then
            local dist = #(coords - GetEntityCoords(ped))
            if dist < (radius or 12.0) and (not bestDist or dist < bestDist) then
                best, bestDist = player, dist
            end
        end
    end

    return best, bestDist
end

function BB.isHolding()
    return held ~= nil and DoesEntityExist(held)
end

--------------------------------------------------------------------------------
-- Shot maths
--------------------------------------------------------------------------------

--- Velocity that carries an object from `from` to `to` in `time` seconds under gravity.
local function solveArc(from, to, time)
    return vec3(
        (to.x - from.x) / time,
        (to.y - from.y) / time,
        (to.z - from.z) / time + 0.5 * Config.Gravity * time
    )
end

BB.solveArc = solveArc

--- The hoop a shot taken this instant would go to, and how far away it is.
---
--- Shared by the aim marker and the shot itself, and it has to stay that way: run
--- two different queries and the marker becomes a liar, showing you one rim while
--- the ball leaves for another. Lives up here, above shoot(), because a local
--- declared further down the file isn't in scope for it.
local function targetHoop()
    if not Config.Shot.aimAssist then return nil end

    return BB.pickTargetHoop(BB.nearbyHoops(), GetEntityCoords(PlayerPedId()), forwardVector(),
        Config.Shot.maxRange, BB.myTeam)
end

--- Velocity for a loose throw along the camera direction, used when no hoop is
--- targeted and for a pass with nobody to pass to.
local function tossVelocity(fwd, power)
    local toss = Config.Toss

    -- Camera pitch runs to nearly straight up, and multiplying that by full power
    -- launches the ball into orbit — which is most of what "the ball flies too
    -- high" turns out to be whenever aim assist doesn't find a rim.
    local lift = BB.clamp(fwd.z, -0.35, toss.maxLift) + toss.upwardBias

    return vec3(fwd.x * power, fwd.y * power, lift * power)
end

--- Turns a meter release into an accuracy score in 0..1.
local function releaseAccuracy(value, distance)
    local shot = Config.Shot

    local off = math.abs(value - shot.sweetSpot) / shot.sweetWidth
    local acc = BB.clamp(1.0 - off, 0.0, 1.0)

    -- Long range chips away at even a perfect release.
    local span = math.max(shot.maxRange - shot.closeRange, 0.01)
    local far  = BB.clamp((distance - shot.closeRange) / span, 0.0, 1.0)

    return acc * (1.0 - far * shot.distancePenalty)
end

--- Moves the aim point off the rim centre according to how badly you released.
local function scatterAim(from, to, accuracy, distance)
    local miss = 1.0 - accuracy
    if miss <= 0.0 then return to end

    local dx, dy = to.x - from.x, to.y - from.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then return to end

    local dirX, dirY = dx / len, dy / len
    local perpX, perpY = -dirY, dirX

    local lateral = (math.random() * 2.0 - 1.0) * miss * distance * Config.Shot.lateralError
    local depth   = (math.random() * 2.0 - 1.0) * miss * distance * Config.Shot.depthError

    return vec3(
        to.x + perpX * lateral + dirX * depth,
        to.y + perpY * lateral + dirY * depth,
        to.z
    )
end

BB.scatterAim = scatterAim

--------------------------------------------------------------------------------
-- Dribbling
--------------------------------------------------------------------------------

--[[
    While you're carrying the ball it isn't parented to your hand — it's driven along
    a bounce path each frame. Attached entities inherit the bone's transform exactly,
    so a glued ball can only ever bob with the hand; it can never actually reach the
    floor. Positioning it ourselves is what makes a real dribble possible.

    The ball is frozen while dribbling so engine physics doesn't fight the positions
    we set, and unfrozen the moment it's released.
]]

local dribblePhase  = 0.0
local clipsetOn     = false
local clipsetToken  = 0

--- Streams the ball-carrying move set in and applies it. The load runs on its own
--- thread: a movement clipset can take several seconds to stream on a cold cache,
--- and blocking the caller for that long delayed the hold loop (and, with the old
--- one-second cap, usually gave up before it ever arrived — which is why the ped
--- kept its normal empty-handed walk while a ball floated next to it).
local function applyClipset()
    local clipset = Config.Dribble.clipset
    if not clipset or clipsetOn then return end

    -- Claimed up front so repeated calls don't stack requests. The token lets a
    -- clearClipset() that lands mid-load cancel this apply.
    clipsetOn = true
    clipsetToken = clipsetToken + 1
    local token = clipsetToken

    CreateThread(function()
        RequestAnimSet(clipset)

        local deadline = GetGameTimer() + 10000
        while not HasAnimSetLoaded(clipset) do
            if GetGameTimer() > deadline then
                if token == clipsetToken then clipsetOn = false end
                print(('^3[gk_basketball]^7 movement clipset %s never streamed in'):format(clipset))
                return
            end
            Wait(0)
        end

        if token == clipsetToken and clipsetOn then
            SetPedMovementClipset(PlayerPedId(), clipset, 1.0)
        end
    end)
end

local function clearClipset()
    if not clipsetOn then return end
    clipsetOn = false
    clipsetToken = clipsetToken + 1
    ResetPedMovementClipset(PlayerPedId(), 0.0)
end

--- Floor level under the ped.
---
--- A ped's entity position is the centre of its collision capsule — about a metre
--- off the ground — not its feet. Bouncing the ball from there put it up around
--- head height, floating beside the player and never reaching the floor. The foot
--- bones are the cheap, reliable way back down, and they stay correct on stairs,
--- slopes and while crouched.
local function feetZ(ped)
    local pedZ = GetEntityCoords(ped).z
    local left  = GetPedBoneCoords(ped, 14201, 0.0, 0.0, 0.0).z     -- SKEL_L_Foot
    local right = GetPedBoneCoords(ped, 52301, 0.0, 0.0, 0.0).z     -- SKEL_R_Foot

    -- Bones sit at the ankle; drop to the sole.
    local z = math.min(left, right) - 0.07

    -- If a bone lookup ever comes back as nonsense, fall back to the nominal
    -- capsule offset rather than dropping the ball through the map.
    if z > pedZ or pedZ - z > 1.6 then return pedZ - 0.98 end

    return z
end

--[[
    Optional arm pump, off by default. See Config.Dribble.handAnim.

    An upper-body clip is played at zero playback rate and its phase is scrubbed
    from the bounce every frame, which pins the arm to the ball exactly: one value
    in, one value out, no solver in between that can decline. Upper-body plus
    secondary masking layers it over the movement clipset instead of fighting it
    for the whole skeleton.

    The mechanism works. The problem is the material: GTA has no dribble clip, and
    every stock clip that moves the arm far enough to read also flexes the spine,
    so the ped ends up folded over chasing the ball. Hence off by default, with
    /bball_hand to audition clips if you have better ones streamed.

    (An earlier pass used SET_IK_TARGET to point the palm at the ball. Better idea
    on paper, but that native's arm index is undocumented and inconsistent across
    builds, and a full-body movement clipset outranks the arm solver anyway.)
]]

local handAnimOn = false

-- A dict that will never load must not be retried: updateDribble calls the starter
-- every frame, so a bad clip name would otherwise spawn a thread per frame forever.
-- Cleared when /bball_hand points us at something new.
local handAnimBroken = false

local function startHandAnim()
    local cfg = Config.Dribble.handAnim
    if not cfg or handAnimOn or handAnimBroken then return end

    handAnimOn = true
    local dict, name = cfg.dict, cfg.name

    CreateThread(function()
        RequestAnimDict(dict)

        local deadline = GetGameTimer() + 5000
        while not HasAnimDictLoaded(dict) do
            if GetGameTimer() > deadline then
                handAnimOn, handAnimBroken = false, true
                print(('^3[gk_basketball]^7 hand anim dict %s never loaded'):format(dict))
                return
            end
            Wait(0)
        end

        -- Ball may already be gone, or /bball_hand may have swapped the clip out
        -- from under us, while the dict was streaming.
        if not handAnimOn or not BB.isHolding() then return end
        if Config.Dribble.handAnim.dict ~= dict or Config.Dribble.handAnim.name ~= name then return end

        -- 49 = looping + upper body + secondary. Playback rate 0 because the phase
        -- is ours to set.
        TaskPlayAnim(PlayerPedId(), dict, name, 8.0, -8.0, -1, 49, 0.0, false, false, false)
    end)
end

local function stopHandAnim()
    if not handAnimOn then return end
    handAnimOn = false

    local cfg = Config.Dribble.handAnim
    if cfg then StopAnimTask(PlayerPedId(), cfg.dict, cfg.name, 3.0) end
end

--- Pins the arm to this frame's bounce.
--- @param rise number 0 with the ball on the floor, 1 at the top of the bounce
local function moveHand(ped, rise)
    if not handAnimOn then return end

    local cfg = Config.Dribble.handAnim

    -- Phase runs from the clip's high pose to its low one, so the hand falls as
    -- the ball falls and lifts as it comes back up.
    SetEntityAnimCurrentTime(ped, cfg.dict, cfg.name, cfg.from + (cfg.to - cfg.from) * (1.0 - rise))
end

--- Retune the hand clip without a restart: /bball_hand <dict> <name> [from] [to]
--- Client-side and cosmetic, so it isn't ace-gated like the placement tools.
RegisterCommand('bball_hand', function(_, args)
    if not Config.Dribble.handAnim then
        if not args[1] then
            print('^3[gk_basketball]^7 hand anim is off. Turn it on with: /bball_hand <dict> <name> [from] [to]')
            return
        end

        -- Naming a clip is how you switch it on.
        Config.Dribble.handAnim = { dict = '', name = '', from = 0.0, to = 1.0 }
    end

    local cfg = Config.Dribble.handAnim

    if args[1] then
        stopHandAnim()

        cfg.dict = args[1]
        cfg.name = args[2] or cfg.name
        cfg.from = tonumber(args[3]) or cfg.from
        cfg.to   = tonumber(args[4]) or cfg.to

        -- New clip, so a previous dead end doesn't count against it.
        handAnimBroken = false

        if BB.isHolding() then startHandAnim() end
    end

    print(('^2[gk_basketball]^7 hand anim: %s / %s   phase %.2f..%.2f')
        :format(cfg.dict, cfg.name, cfg.from, cfg.to))
end, false)

--- Retune any Config.Anims entry live: /bball_anim <key> <dict> <name> [duration]
--- Auditioning a shot clip otherwise means a resource restart and a walk back to
--- a court for every guess.
RegisterCommand('bball_anim', function(_, args)
    local key = args[1]

    if not key or Config.Anims[key] == nil then
        local keys = {}
        for name in pairs(Config.Anims) do keys[#keys + 1] = name end
        table.sort(keys)

        print(('^3[gk_basketball]^7 /bball_anim <%s> <dict> <name> [duration]')
            :format(table.concat(keys, '|')))
        return
    end

    if args[2] then
        -- An entry set to false is off; naming a clip switches it back on, but
        -- then there's no existing clip name to fall back on.
        if not Config.Anims[key] then
            if not args[3] then
                print(('^3[gk_basketball]^7 %s is off — give both a dict and a clip name to turn it on'):format(key))
                return
            end

            Config.Anims[key] = { flag = 48, duration = 700 }
        end

        local cfg = Config.Anims[key]
        cfg.dict = args[2]
        cfg.name = args[3] or cfg.name
        cfg.duration = tonumber(args[4]) or cfg.duration
    end

    local cfg = Config.Anims[key]

    if not cfg then
        print(('^3[gk_basketball]^7 %s is off'):format(key))
        return
    end

    print(('^2[gk_basketball]^7 %s: %s / %s   duration %s'):format(key, cfg.dict, cfg.name, cfg.duration))
end, false)

--- How long after the shot animation starts the ball leaves: /bball_windup <ms>
RegisterCommand('bball_windup', function(_, args)
    local ms = tonumber(args[1])
    if ms then Config.Shot.windUp = math.floor(BB.clamp(ms, 0.0, 3000.0)) end

    print(('^2[gk_basketball]^7 shot wind-up: %sms'):format(Config.Shot.windUp))
end, false)

--- Advances the bounce and puts the ball where it should be this frame.
local function updateDribble()
    local cfg = Config.Dribble
    local ped = PlayerPedId()

    -- Cheap no-op once it's running. Here rather than only in takeBall so the arm
    -- comes back after an aim, a cancelled shot or a /bball_hand swap.
    startHandAnim()

    -- Bounce faster the quicker you're moving, so a sprint looks driven rather than
    -- like the ball is idling next to you.
    local drive = BB.clamp(GetEntitySpeed(ped) / 7.0, 0.0, 1.0)
    local rate  = cfg.idleRate + (cfg.moveRate - cfg.idleRate) * drive

    dribblePhase = (dribblePhase + GetFrameTime() * rate) % 1.0

    --[[
        Bounce shape: hand at phase 0, floor at the midpoint, hand again at the
        end, then a short rest in the hand before the next push.

        The curve is the real one. Height under gravity is parabolic in *time*,
        so the ball leaves the hand slowly, is quickest at the floor, and decays
        again on the way up. A sine — or a parabola anchored the other way round —
        gets this backwards and reads as floaty.
    ]]
    local active = 1.0 - cfg.handDwell
    local rise   = 1.0

    if dribblePhase < active then
        local q = math.abs(2.0 * (dribblePhase / active) - 1.0)
        rise = 1.0 - (1.0 - q) * (1.0 - q)
    end

    -- Push the contact point out ahead of you as you get moving. A dribbler at
    -- speed puts the ball in front and runs onto it — kept pinned to your hip at
    -- a sprint it looks like you're carrying it, not driving it.
    local lead = cfg.offset.y + drive * cfg.lead

    --[[
        The top of every bounce is the hand itself, not a fixed height beside you.

        That is the whole trick. What reads as a dribble is the ball arriving
        somewhere the hand actually is — miss that and it doesn't matter how the
        arm moves, the ball looks like it's bouncing on its own next to a person
        who happens to be standing there. Which is exactly what it looked like.
    ]]
    local off   = Config.Ball.offset
    local hand  = GetPedBoneCoords(ped, Config.Ball.bone, off.x, off.y, off.z)
    local down  = GetOffsetFromEntityInWorldCoords(ped, cfg.offset.x, lead, 0.0)
    local floor = feetZ(ped) + Config.Ball.radius + cfg.offset.z

    SetEntityCoordsNoOffset(held,
        down.x + (hand.x - down.x) * rise,
        down.y + (hand.y - down.y) * rise,
        floor  + (hand.z - floor)  * rise,
        false, false, false)

    SetEntityRotation(held, (dribblePhase * cfg.spin) % 360.0, 0.0, GetEntityHeading(ped), 2, true)

    -- Same number the ball is using, so the two can't drift apart. Off by default:
    -- see the note on Config.Dribble.handAnim.
    moveHand(ped, rise)
end

--- Snaps the ball into your hand, for lining up a shot.
local function holdInHand()
    local ped = PlayerPedId()
    local off = Config.Ball.offset
    local hand = GetPedBoneCoords(ped, Config.Ball.bone, off.x, off.y, off.z)

    -- Lining up a shot, so let the carry pose settle rather than freezing the arm
    -- at whatever phase of the bounce we happened to stop on.
    stopHandAnim()

    SetEntityCoordsNoOffset(held, hand.x, hand.y, hand.z, false, false, false)
end

--------------------------------------------------------------------------------
-- Ball lifecycle
--------------------------------------------------------------------------------

--- Gives me a fresh ball. Called after the server has agreed I may have one.
function BB.takeBall()
    if BB.isHolding() then return end

    local model = Config.Ball.model
    if not loadModel(model) then return end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local ball = CreateObject(model, coords.x, coords.y, coords.z + 0.5, true, true, false)
    SetModelAsNoLongerNeeded(model)

    if not ball or ball == 0 then return end

    local netId = ObjToNet(ball)
    SetNetworkIdCanMigrate(netId, true)
    SetEntityRecordsCollisions(ball, true)

    -- We drive the position ourselves from here until it's released.
    SetEntityCollision(ball, false, false)
    FreezeEntityPosition(ball, true)

    held = ball
    dribblePhase = 0.0

    if Config.Dribble.enabled then
        applyClipset()
        startHandAnim()
    end

    BB.startHoldLoop()
end

--- The point the ball leaves you from. Callers solve their arc against this and
--- hand the same value to launch(), so the trajectory starts exactly where the
--- maths assumed it would.
---
--[[
    Where the ball leaves you.

    Anchored to your own body and pushed out along the line of the shot — not
    along whatever the animation is doing with your hand. Driving it off the hand
    bone tied the release to the clip, and a clip whose hand tracks back over the
    head put the ball behind the shoulder, so shots looked flung from behind you.
    Hand position is animator's business; where a shot starts is ours.

    Flattened to the ground plane on purpose: "out in front of me" shouldn't move
    up and down with camera pitch, and the offset has to stay big enough
    horizontally to clear your own collision capsule or the throw gets eaten.
]]
--- @param towards vector3|nil Direction the shot is going. Defaults to the camera.
local function releasePoint(towards)
    local shot = Config.Shot
    local head = GetPedBoneCoords(PlayerPedId(), 31086, 0.0, 0.0, 0.0)  -- SKEL_Head
    local dir  = towards or forwardVector()

    local len = math.sqrt(dir.x * dir.x + dir.y * dir.y)
    if len < 0.0001 then
        return vec3(head.x, head.y, head.z + shot.releaseHeight)
    end

    return vec3(
        head.x + (dir.x / len) * shot.releaseForward,
        head.y + (dir.y / len) * shot.releaseForward,
        head.z + shot.releaseHeight
    )
end

--- Detaches the ball, hands it to the physics engine and launches it.
--- @param velocity vector3
--- @param from vector3 Release point, from releasePoint()
--- @return number|nil netId
local function launch(velocity, from)
    if not BB.isHolding() then return end

    local ball = held
    local ped  = PlayerPedId()
    held = nil

    clearClipset()
    stopHandAnim()

    -- Hand it back to the physics engine.
    DetachEntity(ball, true, true)
    SetEntityCoordsNoOffset(ball, from.x, from.y, from.z, false, false, false)
    SetEntityCollision(ball, true, true)
    SetEntityNoCollisionEntity(ball, ped, true)
    FreezeEntityPosition(ball, false)
    ActivatePhysics(ball)

    -- An unfrozen body is only re-inserted into the simulation on the *next* tick.
    -- Velocity set in the same frame as the unfreeze is discarded, which is what
    -- left shots dropping straight down at the shooter's feet.
    Wait(0)

    if not DoesEntityExist(ball) then return end

    SetEntityVelocity(ball, velocity.x, velocity.y, velocity.z)

    -- Purely cosmetic backspin, and not present in every build.
    if SetEntityAngularVelocity then
        SetEntityAngularVelocity(ball, -Config.Shot.spin, 0.0, 0.0)
    end

    -- The release point is still close to the shooter, and the third argument to
    -- SetEntityNoCollisionEntity is "this frame only" — a single call let the ball
    -- collide with its own thrower on the very next tick. Keep asking until it is
    -- clear of them.
    CreateThread(function()
        local deadline = GetGameTimer() + 700

        while DoesEntityExist(ball) and GetGameTimer() < deadline do
            SetEntityNoCollisionEntity(ball, ped, true)

            if #(GetEntityCoords(ball) - GetEntityCoords(ped)) > 1.5 then return end
            Wait(0)
        end
    end)

    return ObjToNet(ball)
end

--- /bball_shotdebug prints what each shot actually solved. A missed shot looks
--- the same from outside whether aim assist picked the wrong rim, picked nothing,
--- or picked correctly and the arc was off — this says which.
local shotDebug = false

RegisterCommand('bball_shotdebug', function()
    shotDebug = not shotDebug
    print(('^2[gk_basketball]^7 shot debug %s'):format(shotDebug and 'on' or 'off'))
end, false)

--- Shoots at the hoop you're facing, or tosses the ball if there isn't one.
local function shoot(value)
    busy = true

    local ped    = PlayerPedId()
    local origin = GetEntityCoords(ped)
    local fwd    = forwardVector()
    local shot   = Config.Shot

    -- Target and accuracy are locked in at the moment you released the key, before
    -- the wind-up, so the animation delay can't change the outcome of your shot.
    -- Same lookup the aim marker was drawing, so you get the rim you were shown.
    local hoop, distance = targetHoop()
    local accuracy = hoop and releaseAccuracy(value, distance) or 0.0

    playAnim(Config.Anims.shoot)
    Wait(Config.Shot.windUp)

    -- Start the ball on the line to the basket, so it can never look like it left
    -- from behind you however the camera happens to be sitting.
    local release = releasePoint(hoop
        and vec3(hoop.coords.x - origin.x, hoop.coords.y - origin.y, 0.0)
        or nil)

    local netId

    if hoop then
        local target = vec3(hoop.coords.x, hoop.coords.y, hoop.coords.z + shot.aimHeightOffset)
        local time   = math.min(shot.flightTimeBase + distance * shot.flightTimePerMetre, shot.flightTimeMax)
        local aim    = scatterAim(release, target, accuracy, distance)

        netId = launch(solveArc(release, aim, time), release)
    else
        -- No hoop in range: straight camera-direction toss, power from the meter.
        local toss  = Config.Toss
        local power = toss.minPower + (toss.maxPower - toss.minPower) * value

        netId = launch(tossVelocity(fwd, power), release)
    end

    if netId then
        BB.trackShot(netId, origin, hoop, accuracy)
        TriggerServerEvent('gk_basketball:ballReleased', netId)
    end

    if shotDebug then
        local v = vec3(0.0, 0.0, 0.0)

        if netId and NetworkDoesNetworkIdExist(netId) then
            local ball = NetToObj(netId)
            if ball ~= 0 and DoesEntityExist(ball) then v = GetEntityVelocity(ball) end
        end

        if hoop then
            print(('^2[gk_basketball]^7 hoop %s  dist %.1fm  rim z %.2f  release z %.2f  flight %.2fs  accuracy %.2f  vel %.1f/%.1f/%.1f')
                :format(hoop.id, distance, hoop.coords.z, release.z,
                    math.min(shot.flightTimeBase + distance * shot.flightTimePerMetre, shot.flightTimeMax),
                    accuracy, v.x, v.y, v.z))
        else
            print(('^3[gk_basketball]^7 NO TARGET — loose toss at meter %.2f  vel %.1f/%.1f/%.1f')
                :format(value, v.x, v.y, v.z))
        end
    end

    Wait(400)
    ClearPedTasks(ped)
    busy = false
end

--- Lobs the ball at the nearest player.
local function pass()
    busy = true

    local target = nearestPlayer(20.0)
    local ped    = PlayerPedId()

    playAnim(Config.Anims.pass)
    Wait(Config.Shot.windUp)

    local fwd    = forwardVector()
    local coords = GetEntityCoords(ped)
    local toPed  = target and GetEntityCoords(GetPlayerPed(target)) or nil

    -- Same rule as a shot: leave along the line the ball is going.
    local release = releasePoint(toPed
        and vec3(toPed.x - coords.x, toPed.y - coords.y, 0.0)
        or nil)

    local netId

    if target then
        -- Aim at chest height so it's catchable rather than rolling past their feet.
        local dest = toPed + vec3(0.0, 0.0, 1.0)
        local time = BB.clamp(#(dest - release) / 12.0, 0.35, 1.4)

        netId = launch(solveArc(release, dest, time), release)
    else
        netId = launch(tossVelocity(fwd, Config.Toss.minPower), release)
    end

    if netId then
        BB.trackShot(netId, GetEntityCoords(ped), nil, 0.0)
        TriggerServerEvent('gk_basketball:ballReleased', netId)
    end

    Wait(350)
    ClearPedTasks(ped)
    busy = false
end

--- Puts the ball back in your inventory, or just drops it if that fails.
local function stow()
    if not BB.isHolding() then return end

    busy = true
    clearClipset()
    stopHandAnim()
    playAnim(Config.Anims.stow)
    Wait(650)

    local ball = held
    held = nil

    DeleteEntity(ball)
    TriggerServerEvent('gk_basketball:stowBall')

    ClearPedTasks(PlayerPedId())
    busy = false
end

--------------------------------------------------------------------------------
-- Hold loop: draws the power meter and reads the controls
--------------------------------------------------------------------------------

--[[
    Lights up the rim you're locked onto.

    Deliberately not BB.drawRim. That one stacks six translucent spheres to show
    the scoring cylinder, which is exactly right when you're stood a metre away
    placing a hoop — and from out on the arc those spheres pack into a solid slab
    that covers the backboard you're trying to aim at.

    An aiming marker has one job and a hard constraint: say which rim without
    hiding it. So: a thin disc on the rim plane itself, and a label parked above
    the backboard where there's nothing to obscure.
]]
local function drawAimMarker(hoop, distance)
    local cfg = Config.AimMarker
    if not cfg or not hoop then return end

    local c = hoop.coords
    local r, g, b = cfg.colour[1], cfg.colour[2], cfg.colour[3]
    local size = Config.Scoring.rimRadius * 2.0

    -- Sits in the rim plane, so from below — where you shoot from — it outlines
    -- the hole rather than blocking it.
    DrawMarker(25, c.x, c.y, c.z + 0.03, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        size, size, size, r, g, b, cfg.alpha, false, false, 2, false)

    if not cfg.label then return end

    SetTextScale(0.0, cfg.labelScale)
    SetTextFont(4)
    SetTextColour(r, g, b, 225)
    SetTextOutline()
    SetTextCentre(true)
    SetDrawOrigin(c.x, c.y, c.z + cfg.labelHeight, 0)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(('%d PT   %.1fm'):format(
        distance >= Config.Scoring.threePointDistance and 3 or 2, distance))
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function drawMeter()
    local shot = Config.Shot

    local w, h = 0.16, 0.014
    local x, y = 0.5, 0.86

    -- Track
    DrawRect(x, y, w + 0.006, h + 0.006, 0, 0, 0, 160)
    DrawRect(x, y, w, h, 40, 40, 44, 220)

    -- Sweet band
    local bandW = (shot.sweetWidth * 2.0) * w
    local bandX = (x - w / 2) + shot.sweetSpot * w
    DrawRect(bandX, y, bandW, h, 90, 220, 130, 110)

    -- Fill
    if charge > 0.0 then
        DrawRect((x - w / 2) + (charge * w) / 2, y, charge * w, h, 255, 190, 60, 235)
    end

    -- Release marker
    DrawRect((x - w / 2) + charge * w, y, 0.0025, h + 0.008, 255, 255, 255, 255)
end

--- Advances the oscillating meter one frame.
local function tickMeter()
    local step = GetFrameTime() / Config.Shot.chargeTime
    charge = charge + (chargeUp and step or -step)

    if charge >= 1.0 then
        charge, chargeUp = 1.0, false
    elseif charge <= 0.0 then
        charge, chargeUp = 0.0, true
    end
end

--- Everything drawn while you're lining a shot up: the meter, the rim you have,
--- and a hint that tells you which of those two situations you're in.
local function showAim()
    drawMeter()

    local hoop, distance = targetHoop()

    if hoop then
        drawAimMarker(hoop, distance)
        BB.showHint(Config.Text.aiming_hint)
    else
        BB.showHint(Config.Text.aiming_notarget)
    end
end

local function takeShot()
    local value = charge
    charging, charge = false, 0.0
    CreateThread(function() shoot(value) end)
end

function BB.startHoldLoop()
    CreateThread(function()
        local keys = Config.Keys

        while BB.isHolding() do
            if not busy then
                -- These would otherwise throw a punch every time you shoot.
                DisableControlAction(0, 140, true)
                DisableControlAction(0, 141, true)
                DisableControlAction(0, 142, true)
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)

                if Config.Shot.aimToShoot then
                    -- Hold aim to line up, tap shoot to release. Letting go of aim
                    -- without shooting cancels and puts you back to dribbling.
                    if IsDisabledControlPressed(0, keys.aim) then
                        if not charging then
                            charging, charge, chargeUp = true, 0.0, true
                        end

                        tickMeter()
                        showAim()
                        holdInHand()

                        if IsDisabledControlJustPressed(0, keys.shoot) then
                            takeShot()
                        end
                    else
                        if charging then charging, charge = false, 0.0 end

                        if IsDisabledControlJustReleased(0, keys.pass) then
                            CreateThread(pass)
                        elseif IsDisabledControlJustReleased(0, keys.stow) then
                            CreateThread(stow)
                        else
                            BB.showHint(Config.Text.holding_hint)
                        end

                        if Config.Dribble.enabled then updateDribble() else holdInHand() end
                    end
                else
                    -- Legacy scheme: hold shoot to charge, release it in the green.
                    if IsDisabledControlPressed(0, keys.shoot) then
                        if not charging then
                            charging, charge, chargeUp = true, 0.0, true
                        end

                        tickMeter()
                        showAim()
                        holdInHand()
                    elseif charging then
                        takeShot()
                    elseif IsDisabledControlJustReleased(0, keys.pass) then
                        CreateThread(pass)
                    elseif IsDisabledControlJustReleased(0, keys.stow) then
                        CreateThread(stow)
                    else
                        BB.showHint(Config.Text.holding_hint)

                        if Config.Dribble.enabled then updateDribble() else holdInHand() end
                    end
                end
            end

            Wait(0)
        end

        charging, charge = false, 0.0
        clearClipset()
        stopHandAnim()
        BB.hideHint()
    end)
end

--------------------------------------------------------------------------------
-- Picking up loose balls
--------------------------------------------------------------------------------

CreateThread(function()
    while true do
        local wait = 500

        if not BB.isHolding() and not busy and not BB.placing and next(BB.loose) then
            local coords = GetEntityCoords(PlayerPedId())
            local nearest, nearestDist

            for netId in pairs(BB.loose) do
                if NetworkDoesNetworkIdExist(netId) then
                    local ball = NetToObj(netId)
                    if ball ~= 0 and DoesEntityExist(ball) then
                        local dist = #(coords - GetEntityCoords(ball))
                        if dist < Config.Ball.renderDistance then
                            wait = 0
                            if dist < Config.Ball.catchRadius and (not nearestDist or dist < nearestDist) then
                                nearest, nearestDist = netId, dist
                            end
                        end
                    end
                end
            end

            if nearest then
                BB.showHint(Config.Text.pickup_ball)

                if IsControlJustReleased(0, Config.Keys.pickup) then
                    busy = true
                    playAnim(Config.Anims.pickup)

                    local ok = lib.callback.await('gk_basketball:pickupBall', false, nearest)
                    Wait(450)
                    ClearPedTasks(PlayerPedId())
                    busy = false

                    if ok then BB.takeBall() end
                end
            end
        end

        Wait(wait)
    end
end)

--------------------------------------------------------------------------------
-- Server messages
--------------------------------------------------------------------------------

-- The server has approved a ball for me (item use, court rack, or a catch).
RegisterNetEvent('gk_basketball:giveBall', function()
    BB.takeBall()
end)

RegisterNetEvent('gk_basketball:setLooseBall', function(netId, data)
    BB.loose[netId] = data

    if not data then
        BB.untrackShot(netId)
    end
end)

RegisterNetEvent('gk_basketball:syncLooseBalls', function(balls)
    BB.loose = balls or {}
end)

-- ox_inventory item use.
exports('useBasketball', function()
    if BB.isHolding() then
        BB.notify(Config.Text.hands_full, 'error')
        return false
    end

    TriggerServerEvent('gk_basketball:useItem')
    return true
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    -- Leaving the ball-carrying walk applied would follow you around after a restart.
    clearClipset()
    stopHandAnim()

    if held and DoesEntityExist(held) then DeleteEntity(held) end

    for netId in pairs(BB.loose) do
        if NetworkDoesNetworkIdExist(netId) then
            local ball = NetToObj(netId)
            if ball ~= 0 and DoesEntityExist(ball) then DeleteEntity(ball) end
        end
    end
end)
