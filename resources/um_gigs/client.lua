-- -----------------------------------------------------------------------------
-- um_gigs -- client
-- -----------------------------------------------------------------------------
-- One gig at a time, in two stages: get to the pickup, then get to the
-- drop-off. Everything else here hangs off those two facts.
--
-- NAVIGATION lives in vice_hud, not in this file and not in a map inside the
-- phone app. See Config.Nav: a gig sets the player's WAYPOINT, the engine
-- pathfinds to it, and vice_hud reads the next manoeuvre off that same route
-- and puts turn-by-turn on screen. That is the integration -- there is nothing
-- to export and nothing to draw.
-- -----------------------------------------------------------------------------

local job = nil         -- the active gig
local jobBlip = nil
local jobRadius = nil
local waypointSet = false
local passenger = nil   -- Ryde Me only: the NPC we spawned, if this is NPC work
local gigPed = nil      -- a ped we spawned for the current stage, if any
local gigZone = nil     -- an ox_target zone over someone else's ped, if any
local stage = nil       -- 'pickup' | 'dropoff'
local startedAt = 0
local incomingFare = nil    -- the pushed request currently up on the card
local incomingUntil = 0     -- GetGameTimer() when that card dies

-- How the ride went. Reset per gig, read once at the end.
local crashes = 0
local fastTicks, totalTicks = 0, 0
local sawWanted = false
local crashSpokeAt = 0

-- Speed limit tracking, Ryde Me only. postedLimit is the mph for the street
-- under the car, refreshed on a slower cadence than the watch loop because it
-- costs a street lookup; nil means unposted, which is not the same as zero.
local postedLimit = nil
local speedingSeconds = 0.0

-- "Just go, I will cover the ticket." Once this is true the meter comes off
-- the screen and the speeding rule stops counting for the rest of the ride.
local speedFreed = false
local speedRequestAt = nil  -- ms into the ride they will say it, or nil for never

-- The car the passenger actually got into. Its class is what the fare is
-- multiplied by, and it is the car the breakdown watch is watching.
local rideVeh = 0
local rideClass = nil
local rideVehLabel = nil
local fuelArmed = false     -- we saw a healthy tank, so a dry one means something

-- Rider mode, when YOU are the passenger.
local riderBlip = nil
local rideState = nil

--- Registers both apps with lb-phone. Two separate registrations on purpose:
--- they are different companies in fiction and different icons on the phone.
local function registerApps()
    for _, app in pairs(Config.Apps) do
        local ok, err = pcall(function()
            exports['lb-phone']:AddCustomApp({
                identifier = app.identifier,
                name = app.name,
                description = app.description,
                developer = app.developer,
                defaultApp = false,
                size = app.size,
                ui = app.ui,
                icon = app.icon,
            })
        end)

        if not ok then
            print(('^3[um_gigs]^7 could not register %s: %s'):format(app.name, err))
        end
    end
end

--- The player-facing name of an app.
---@param app string
---@return string
local function appLabel(app)
    return app == 'snarf' and 'Snarf' or 'rydeme'
end

local function clearBlip()
    if jobBlip and DoesBlipExist(jobBlip) then RemoveBlip(jobBlip) end
    if jobRadius and DoesBlipExist(jobRadius) then RemoveBlip(jobRadius) end
    jobBlip, jobRadius = nil, nil

    -- Only ever take the waypoint down if we were the one who put it up.
    -- Clearing a pin the player set themselves would be its own small bug.
    if waypointSet then
        SetWaypointOff()
        waypointSet = false
    end
end

--- The colour this app marks its stops in.
---@return table
local function markerColour()
    return Config.Marker[job and job.app or 'snarf'] or Config.Marker.snarf
end

--- Points the player at a stop.
---
--- The route itself is the GAME'S: SetNewWaypoint makes this the player's own
--- GPS destination, so the minimap draws its real road line to it and
--- vice_hud's turn-by-turn panel -- which reads whatever waypoint is set and
--- runs GENERATE_DIRECTIONS_TO_COORD against it -- starts calling the turns.
--- That is why there is no SetBlipRoute here any more and no map inside the
--- phone: a second, hand-drawn route would be a worse copy of one the player
--- already has, in a place they cannot look at while driving.
---@param coords vector3
---@param label string
---@param sprite number
local function routeTo(coords, label, sprite)
    clearBlip()

    -- A radius under the pin, so the stop is findable on the map before the
    -- marker itself is in draw distance.
    jobRadius = AddBlipForRadius(coords.x, coords.y, coords.z, Config.Marker.radius)
    SetBlipColour(jobRadius, 5)
    SetBlipAlpha(jobRadius, 90)

    jobBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(jobBlip, sprite)
    SetBlipColour(jobBlip, 5)
    SetBlipScale(jobBlip, 0.9)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(jobBlip)

    if Config.Nav.setWaypoint then
        SetNewWaypoint(coords.x, coords.y)
        waypointSet = true
    end
end

--- Config.Addresses are real road nodes now, so this is a safety net rather
--- than the load-bearing fix it used to be -- it still matters for a player
--- ride, where the pickup is wherever the rider happens to be standing and
--- that may well be up an alley.
---@param coords vector3
---@return vector3
local function snapToRoad(coords)
    local found, nodePos = GetClosestVehicleNodeWithHeading(coords.x, coords.y, coords.z, 1, 3.0, 0)
    if not found then return coords end

    return vec3(nodePos.x, nodePos.y, nodePos.z)
end

--- Looks a restaurant up by the id the offer carried.
---@param id string?
---@return table?
local function restaurantById(id)
    if not id then return end

    for _, r in ipairs(Config.Restaurants) do
        if r.id == id then return r end
    end
end

--- Drops whatever interaction the current stage put in the world.
local function clearInteraction()
    if gigZone then
        exports.ox_target:removeZone(gigZone)
        gigZone = nil
    end

    if gigPed and DoesEntityExist(gigPed) then
        exports.ox_target:removeLocalEntity(gigPed, 'um_gigs:interact')
        DeleteEntity(gigPed)
    end
    gigPed = nil
end

--- Spawns one of ours and stands it still.
---@param model number
---@param coords vector3
---@param heading number
---@return number?
local function spawnGigPed(model, coords, heading)
    if not lib.requestModel(model, 8000) then
        print('^1[um_gigs]^7 could not load ped model for this stop')
        return
    end

    -- Drop to the ground rather than trusting the configured z.
    local z = coords.z
    local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 1.0, false)
    if found then z = groundZ end

    local ped = CreatePed(4, model, coords.x, coords.y, z, heading or 0.0, false, true)
    SetModelAsNoLongerNeeded(model)

    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)

    return ped
end

--- Puts one ox_target option in the world for the current stage: on a ped we
--- spawned, or on a zone over a shop ped that is already standing there.
---@param opts table label, icon, coords, onSelect, and optionally ped/heading
local function addInteraction(opts)
    clearInteraction()

    local option = {
        name = 'um_gigs:interact',
        icon = opts.icon,
        label = opts.label,
        distance = Config.Customers.targetDistance,
        onSelect = opts.onSelect,
    }

    if opts.ped then
        gigPed = spawnGigPed(opts.ped, opts.coords, opts.heading)
        if gigPed then
            exports.ox_target:addLocalEntity(gigPed, { option })
            return
        end
        -- Fall through to a zone if the model would not load, so a failed
        -- spawn cannot leave the job with no way to finish it.
    end

    gigZone = exports.ox_target:addSphereZone({
        coords = opts.coords,
        radius = 1.8,
        options = { option },
    })
end

--- Tears the current gig down.
local function endJob()
    if passenger and DoesEntityExist(passenger) then
        DeleteEntity(passenger)
    end
    passenger = nil

    clearInteraction()
    clearBlip()
    lib.hideTextUI()

    job, stage = nil, nil
    crashes, fastTicks, totalTicks = 0, 0, 0
    sawWanted, crashSpokeAt = false, 0
    postedLimit, speedingSeconds = nil, 0.0
    speedFreed, speedRequestAt = false, nil
    rideVeh, rideClass, rideVehLabel = 0, nil, nil
    fuelArmed = false
end

--- Seconds allowed for this gig, from its route length.
---@return number
local function allowance()
    return (job.distance / 1000.0) * Config.SecondsPerKm
end

--- The ped of the player who booked a player ride, if they are streamed in.
---@return number
local function riderPed()
    if not job or not job.riderSrc then return 0 end

    local plyr = GetPlayerFromServerId(job.riderSrc)
    if plyr == -1 then return 0 end

    return GetPlayerPed(plyr)
end

-- Declared up front because the pickup stage installs the callback that ends
-- the job, and the drop-off stage is set up from inside the pickup callback.
local finish
local beginDropoff

--- Spawns the Ryde Me passenger at the pickup. They just stand there by the
--- road -- no ox_target option. You pull up and honk, same as a real rideshare.
local function spawnPassenger()
    local model = Config.Passengers.peds[math.random(#Config.Passengers.peds)]
    if not lib.requestModel(model, 8000) then return end

    local c = job.pickup
    passenger = CreatePed(4, model, c.x, c.y, c.z, job.pickupHeading or 0.0, false, true)
    SetModelAsNoLongerNeeded(model)

    SetEntityInvincible(passenger, true)
    SetBlockingOfNonTemporaryEvents(passenger, true)
    TaskStartScenarioInPlace(passenger, 'WORLD_HUMAN_STAND_MOBILE', 0, true)
end

--- Records what the fare is actually being driven in. The class is what the
--- server multiplies the fare by, and the vehicle is what the breakdown watch
--- watches, so both are pinned here rather than re-read later -- swapping cars
--- mid-ride must not silently re-price the job.
---@param veh number
local function noteRideVehicle(veh)
    rideVeh = veh
    rideClass = GetVehicleClass(veh)
    rideVehLabel = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(veh)))

    -- Only treat a dry tank as "ran out of fuel" if we saw a wet one first.
    -- Without a fuel resource running, the native reads whatever the engine
    -- last wrote, and a cold zero would end every ride the moment it started.
    fuelArmed = GetVehicleFuelLevel(veh) > (Config.Abort.fuelBelow + 2.0)

    local info = Config.VehicleClasses[rideClass]
    if info and info.mult ~= 1.0 then
        lib.notify({
            title = 'rydeme',
            description = ('%s fare rate: x%.2f'):format(info.label, info.mult),
            type = info.mult >= 1.0 and 'success' or 'inform',
            duration = 5000,
        })
    end
end

--- Decides, once per ride, whether this passenger is going to tell you to stop
--- reading the signs -- and when. Rolled at pickup rather than checked every
--- tick so the moment is fixed and the loop stays a comparison.
local function armSpeedRequest()
    speedFreed, speedRequestAt = false, nil

    if not Config.SpeedRequest.enabled then return end
    if job.mood and job.mood.hatesSpeed then return end

    local chance = (job.mood and job.mood.rush)
        and Config.SpeedRequest.rushChance
        or Config.SpeedRequest.chance

    if math.random() > chance then return end

    speedRequestAt = math.random(Config.SpeedRequest.minDelay, Config.SpeedRequest.maxDelay) * 1000
end

--- Starts the driving half of the gig.
---@param veh number the car the passenger is in
local function beginRide(veh)
    noteRideVehicle(veh)
    armSpeedRequest()

    stage = 'dropoff'
    startedAt = GetGameTimer()
    crashes, fastTicks, totalTicks = 0, 0, 0
    sawWanted = false
    speedingSeconds = 0.0

    routeTo(job.dropoff, job.dropoffLabel, 280)
end

--- Puts the NPC passenger in your car and starts the ride. Called from the
--- honk prompt in the main gig loop, so the vehicle check here is a guard.
local function loadPassenger()
    local veh = GetVehiclePedIsIn(cache.ped, false)
    if veh == 0 then
        lib.notify({ title = 'rydeme', description = 'You need to be in a vehicle.', type = 'error' })
        return
    end

    TaskEnterVehicle(passenger, veh, 10000, -2, 1.0, 1, 0)

    lib.notify({
        title = job.passengerName,
        description = job.mood.line,
        type = 'inform',
        duration = 8000,
    })

    beginRide(veh)
end

--- Collects the order at the restaurant.
local function collectOrder()
    if not lib.progressBar({
        duration = 6000,
        label = 'Collecting the order',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'mp_common', clip = 'givetake1_a' },
    }) then
        return
    end

    beginDropoff()

    lib.notify({
        title = 'Snarf',
        description = ('Order collected. %s'):format(job.note or 'Take it to the address.'),
        type = 'success',
        duration = 9000,
    })
end

--- Moves to the drop-off. Snarf gets a customer to hand the bag to; a Ryde Me
--- passenger is already in the car, so that one stays a pull-over-and-park.
function beginDropoff()
    stage = 'dropoff'
    startedAt = GetGameTimer()
    routeTo(job.dropoff, job.dropoffLabel, 280)

    if job.app ~= 'snarf' then
        clearInteraction()
        return
    end

    addInteraction({
        ped = Config.Customers.peds[math.random(#Config.Customers.peds)],
        coords = job.dropoff,
        heading = 0.0,
        icon = 'fa-solid fa-bag-shopping',
        label = 'Hand over the order',
        onSelect = function() finish() end,
    })
end

--- Lets the NPC passenger out and walks them off, instead of the car just
--- swallowing them. Runs on its own thread so the animation plays out after
--- the job has already ended -- nothing about payment or the next request
--- should wait on a ped finding a spot on the pavement.
---@param p number the passenger ped, taken out of the `passenger` upvalue
local function dismissPassenger(p)
    if not DoesEntityExist(p) then return end

    local veh = GetVehiclePedIsIn(p, false)
    if veh ~= 0 then TaskLeaveVehicle(p, veh, 0) end

    CreateThread(function()
        local waited = 0
        while DoesEntityExist(p) and IsPedInAnyVehicle(p, false, false) and waited < 8000 do
            Wait(200)
            waited = waited + 200
        end

        if DoesEntityExist(p) then
            SetEntityInvincible(p, false)
            SetBlockingOfNonTemporaryEvents(p, false)
            TaskWanderStandard(p, 10.0, 10)
        end

        Wait(15000)
        if DoesEntityExist(p) then DeleteEntity(p) end
    end)
end

--- Detaches the NPC passenger from job state before endJob() deletes whoever
--- is still sitting in `passenger` on the spot. That blunt path stays as-is
--- for a cancelled ride, where there is no dignified way out anyway.
local function releasePassenger()
    if job.app ~= 'rydeme' or not passenger then return end

    local p = passenger
    passenger = nil
    dismissPassenger(p)
end

--- Hands the gig in and reports how it went.
function finish()
    local taken = (GetGameTimer() - startedAt) / 1000
    local late = taken > allowance()

    TriggerServerEvent('um_gigs:server:complete', {
        app = job.app,
        offerId = job.id,
        late = late,
        seconds = math.floor(taken),
        crashes = crashes,
        speedFraction = totalTicks > 0 and (fastTicks / totalTicks) or 0,
        speedingSeconds = math.floor(speedingSeconds),
        wanted = sawWanted,
        speedFreed = speedFreed,
        hurried = speedFreed and (taken <= allowance() * Config.SpeedRequest.bonusUnderFraction),
        vehicleClass = rideClass,
    })

    releasePassenger()
    endJob()
end

--- The fare is over and it is not your fault, or at least not in a way the app
--- distinguishes: the engine is dead or the tank is dry, with somebody in the
--- back. No pay either way.
---@param reason 'fuel'|'engine'
local function abortRide(reason)
    if not job then return end

    TriggerServerEvent('um_gigs:server:abort', {
        app = job.app,
        offerId = job.id,
        reason = reason,
    })

    lib.notify({
        title = 'rydeme',
        description = reason == 'fuel'
            and 'Out of fuel. Your passenger got out and the fare ended.'
            or 'The car is finished. Your passenger got out and the fare ended.',
        type = 'error',
        duration = 9000,
    })

    releasePassenger()
    endJob()
end

-- -----------------------------------------------------------------------------
-- Main gig loop
-- -----------------------------------------------------------------------------

CreateThread(function()
    local showing = false
    local parkedSince = nil -- Ryde Me dropoff: when the car settled in the circle

    while true do
        local wait = 800

        if job then
            local pos = GetEntityCoords(cache.ped)
            local target = stage == 'pickup' and job.pickup or job.dropoff
            local dist = #(pos - target)
            local dropoffZone = stage == 'dropoff' and job.app == 'rydeme'

            local prompt, action, key, released

            -- ---- a real passenger walking to your car -----------------------
            -- No honk, no marker interaction: they open the door themselves,
            -- because they are a person and that is what a person does.
            if stage == 'pickup' and job.playerRide then
                local veh = GetVehiclePedIsIn(cache.ped, false)
                local rp = riderPed()

                if veh ~= 0 and rp ~= 0 and IsPedInVehicle(rp, veh, false) then
                    TriggerServerEvent('um_gigs:server:riderAboard')
                    beginRide(veh)
                    lib.notify({
                        title = 'rydeme',
                        description = ('%s is in. Take them to %s.')
                            :format(job.passengerName, job.dropoffLabel),
                        type = 'success',
                    })
                elseif dist < Config.RiderMode.pickupRadius then
                    prompt = ('Waiting for %s to get in'):format(job.passengerName)
                    wait = 200
                end
            end

            if job and dist < Config.Marker.drawDistance then
                wait = 0

                -- Drawn every frame, which is why this sits inside the branch
                -- that drops the wait to zero. Without it the job ends at "the
                -- route line stopped somewhere near here". The Ryde Me
                -- drop-off gets a bigger circle: it is a park-and-wait, not a
                -- walk-up, and needs room to actually stop a car in it.
                local col = markerColour()
                local scale = dropoffZone and Config.RydeMe.markerScale or Config.Marker.scale
                DrawMarker(
                    Config.Marker.type,
                    target.x, target.y, target.z - 0.95,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, 0.0,
                    scale.x, scale.y, scale.z,
                    col.r, col.g, col.b, Config.Marker.alpha,
                    false, false, 2, false, nil, nil, false
                )

                -- Ryde Me, NPC work: the passenger appears when you pull up and
                -- waits by the road. You pull alongside and honk to wave them
                -- into the car, like a real rideshare.
                if stage == 'pickup' and job.app == 'rydeme' and not job.playerRide then
                    if not passenger then spawnPassenger() end

                    if dist < 6.0 and GetVehiclePedIsIn(cache.ped, false) ~= 0 then
                        prompt = 'Honk to wave them over'
                        action = loadPassenger
                        key, released = 86, false -- INPUT_VEH_HORN, held not tapped
                    end
                end

                -- Ryde Me drop-off: nobody to press E for, so this is park and
                -- wait -- roll to a stop inside the (bigger) circle and they
                -- let themselves out after a beat.
                if dropoffZone and dist < Config.RydeMe.dropoffRadius then
                    local veh = GetVehiclePedIsIn(cache.ped, false)
                    local speed = veh ~= 0 and GetEntitySpeed(veh) or 0.0

                    if veh ~= 0 and speed <= Config.RydeMe.parkedSpeed then
                        parkedSince = parkedSince or GetGameTimer()

                        if GetGameTimer() - parkedSince >= Config.RydeMe.parkedHold then
                            if showing then lib.hideTextUI(); showing = false end
                            parkedSince = nil
                            finish()
                        else
                            prompt = 'Parking...'
                        end
                    else
                        parkedSince = nil
                        prompt = 'Pull in and park to drop them off'
                    end
                else
                    parkedSince = nil
                end
            elseif job then
                parkedSince = nil
            end

            if prompt then
                if not showing then showing = true; lib.showTextUI(prompt) end

                if action then
                    local pressed
                    if released then
                        pressed = IsControlJustReleased(0, key)
                    else
                        pressed = IsControlJustPressed(0, key)
                    end
                    if pressed then
                        lib.hideTextUI(); showing = false
                        action()
                    end
                end
            elseif showing then
                showing = false
                lib.hideTextUI()
            end
        elseif showing then
            showing = false
            lib.hideTextUI()
        end

        Wait(wait)
    end
end)

-- -----------------------------------------------------------------------------
-- The drive watch
-- -----------------------------------------------------------------------------

--- The posted limit under the car, in mph, or nil where the street is unposted.
--- Read from the standalone `speedlimits` resource rather than a copy of its
--- table, so this can never disagree with the sign the player is looking at.
--- pcall'd because that resource is optional: if it is not running, every
--- street reads as unposted and the whole speeding rule quietly switches off.
---@return number?
local function speedLimitHere()
    if GetResourceState('speedlimits') ~= 'started' then return nil end

    local pos = GetEntityCoords(cache.ped)
    local ok, mph = pcall(function()
        return exports.speedlimits:getSpeedLimitAtCoords(pos.x, pos.y, pos.z)
    end)

    return ok and tonumber(mph) or nil
end

--- The passenger, unprompted, telling you to stop reading the signs.
local function fireSpeedRequest()
    speedRequestAt = nil
    speedFreed = true

    lib.notify({
        title = job.passengerName or 'Passenger',
        description = Config.SpeedRequest.lines[math.random(#Config.SpeedRequest.lines)],
        type = 'inform',
        duration = 9000,
    })
end

--- Whether the fare's car has given up. Only ever consulted with a passenger
--- aboard, which is the only time it costs anything.
---@return string? reason
local function breakdownReason()
    if not Config.Abort.enabled then return nil end
    if rideVeh == 0 or not DoesEntityExist(rideVeh) then return nil end

    -- Only judge the car while the player is actually in it. Getting out to
    -- check something must not read as a breakdown, and a wreck the player
    -- already abandoned is a different problem.
    if GetVehiclePedIsIn(cache.ped, false) ~= rideVeh then return nil end

    if GetVehicleEngineHealth(rideVeh) <= Config.Abort.engineHealthBelow
        or not IsVehicleDriveable(rideVeh, false)
    then
        return 'engine'
    end

    if fuelArmed and GetVehicleFuelLevel(rideVeh) <= Config.Abort.fuelBelow then
        return 'fuel'
    end

    return nil
end

--- Watches the drive while a Ryde Me passenger is aboard. Its own thread, and a
--- fixed tick: the main loop waits 800ms away from a waypoint and 0ms near one,
--- which was too slow to catch a real crash, fast enough to log the same scrape
--- repeatedly, and made the "how much of the trip was fast" fraction depend on
--- how close to the drop-off you happened to be.
CreateThread(function()
    local lastSpeed = 0.0
    local lastCrashAt = 0
    local lastLimitCheck = 0
    local lastPing = 0

    while true do
        local watching = job ~= nil and job.app == 'rydeme' and stage == 'dropoff'

        if watching then
            local veh = GetVehiclePedIsIn(cache.ped, false)
            local speed = veh ~= 0 and GetEntitySpeed(veh) or 0.0
            local now = GetGameTimer()

            totalTicks = totalTicks + 1
            if speed > Config.Driving.fastSpeed then fastTicks = fastTicks + 1 end

            -- ---- the car packing in --------------------------------------
            local dead = breakdownReason()
            if dead then
                abortRide(dead)
                goto continue
            end

            -- ---- the police ----------------------------------------------
            -- Latched, not sampled: losing the stars again before the drop-off
            -- does not un-happen the sirens from the back seat.
            if Config.Wanted.enabled and not sawWanted and GetPlayerWantedLevel(PlayerId()) > 0 then
                sawWanted = true
                lib.notify({
                    title = job.passengerName or 'Passenger',
                    description = Config.Wanted.lines[math.random(#Config.Wanted.lines)],
                    type = 'error',
                    duration = 9000,
                })
            end

            -- ---- "put your foot down" ------------------------------------
            if speedRequestAt and (now - startedAt) >= speedRequestAt then
                fireSpeedRequest()
            end

            -- ---- posted limits -------------------------------------------
            -- Skipped wholesale once the passenger has waived it: there is no
            -- penalty to accrue, and the meter that shows it is gone too.
            if Config.SpeedLimit.enabled and not speedFreed and veh ~= 0 then
                if (now - lastLimitCheck) > 1000 then
                    lastLimitCheck = now
                    postedLimit = speedLimitHere()
                end

                -- Over the posted limit plus grace costs a slow drip of rating.
                -- Tick is 100ms, so this accumulates in real seconds.
                if postedLimit then
                    local mph = speed * 2.23694
                    if mph > (postedLimit + Config.SpeedLimit.graceMph) then
                        speedingSeconds = speedingSeconds + 0.1
                    end
                end
            else
                postedLimit = nil
            end

            -- ---- collisions ------------------------------------------------
            -- A collision only counts if you were moving and lost speed for it.
            -- HasEntityCollidedWithAnything on its own is true for curbs, walls
            -- you are parked against and most kerb-mounting, so every trip used
            -- to end with "3 bumps".
            if veh ~= 0
                and HasEntityCollidedWithAnything(veh)
                and lastSpeed >= Config.Driving.crashMinSpeed
                and (lastSpeed - speed) >= Config.Driving.crashSpeedDrop
                and (now - lastCrashAt) > 3000
            then
                crashes = crashes + 1
                lastCrashAt = now

                -- They say something the first time and then let it lie. A
                -- running commentary on every scrape is worse than silence.
                if crashSpokeAt == 0 then
                    crashSpokeAt = now
                    lib.notify({
                        title = job.passengerName or 'Passenger',
                        description = Config.Driving.crashLines[math.random(#Config.Driving.crashLines)],
                        type = 'error',
                        duration = 6000,
                    })
                end
            end

            -- ---- keep the rider's map honest -------------------------------
            if job.playerRide and (now - lastPing) > (Config.RiderMode.trackInterval * 1000) then
                lastPing = now
                local p = GetEntityCoords(cache.ped)
                TriggerServerEvent('um_gigs:server:driverPing', p.x, p.y, p.z, rideVehLabel, rideClass)
            end

            lastSpeed = speed
        else
            lastSpeed = 0.0
        end

        ::continue::
        Wait(watching and 100 or 500)
    end
end)

--- Keeps a player ride's pickup pointed at the rider while they are still on
--- foot. Re-setting the waypoint every few seconds regardless would ping the
--- map constantly, so it only moves when they have actually gone somewhere.
CreateThread(function()
    while true do
        Wait(Config.RiderMode.trackInterval * 1000)

        if job and job.playerRide and stage == 'pickup' then
            local rp = riderPed()

            if rp ~= 0 then
                local at = GetEntityCoords(rp)
                if #(at - job.pickup) > 40.0 then
                    job.pickup = snapToRoad(at)
                    routeTo(job.pickup, job.pickupLabel, 198)
                end
            end

            local p = GetEntityCoords(cache.ped)
            TriggerServerEvent('um_gigs:server:driverPing', p.x, p.y, p.z, rideVehLabel, rideClass)
        end
    end
end)

-- -----------------------------------------------------------------------------
-- Speedometer
-- -----------------------------------------------------------------------------

--- One line of the speedometer readout.
local function drawMeterText(text, x, y, scale, r, g, b)
    SetTextFont(4)
    SetTextScale(scale, scale)
    SetTextColour(r, g, b, 220)
    SetTextCentre(true)
    SetTextOutline()
    SetTextEntry('STRING')
    AddTextComponentSubstringPlayerName(text)
    DrawText(x, y)
end

--- The speedometer, drawn only while a Ryde Me passenger is aboard AND the
--- speeding rule is still live. It exists so the penalty is legible rather
--- than a mystery deduction at the end of the ride -- which is exactly why it
--- disappears the moment the passenger waives it. Once there is nothing to
--- lose, a limit readout is just clutter telling you off for nothing.
CreateThread(function()
    while true do
        local showing = Config.SpeedLimit.enabled
            and Config.SpeedLimit.showMeter
            and not speedFreed
            and job ~= nil and job.app == 'rydeme' and stage == 'dropoff'
            and GetVehiclePedIsIn(cache.ped, false) ~= 0

        if showing then
            local veh = GetVehiclePedIsIn(cache.ped, false)
            local mph = GetEntitySpeed(veh) * 2.23694
            local over = postedLimit ~= nil
                and mph > (postedLimit + Config.SpeedLimit.graceMph)

            -- Red the moment it is actually costing you, white otherwise.
            local r, g, b = 255, 255, 255
            if over then r, g, b = 255, 45, 149 end

            drawMeterText(('%d MPH'):format(math.floor(mph + 0.5)), 0.5, 0.86, 0.55, r, g, b)
            drawMeterText(
                postedLimit and ('LIMIT %d'):format(postedLimit) or 'UNPOSTED',
                0.5, 0.895, 0.32, 200, 200, 200
            )
        end

        Wait(showing and 0 or 500)
    end
end)

-- -----------------------------------------------------------------------------
-- Incoming requests
-- -----------------------------------------------------------------------------

--- Resolves whatever request is currently on the card. The keybinds and the
--- phone screen both land here, and the player will press them at random
--- times, so a card that is not up is the normal case rather than an error.
---@param accept boolean
---@return table? result
local function resolveIncomingFare(accept)
    local offer = incomingFare
    if not offer then return end

    incomingFare = nil
    lib.hideTextUI()

    if not accept then
        TriggerServerEvent('um_gigs:server:declineFare', offer.app, offer.id)
        return { ok = true, declined = true }
    end

    local result = lib.callback.await('um_gigs:server:accept', false, offer.app, offer.id)
    if not result or not result.ok then
        lib.notify({
            title = appLabel(offer.app),
            description = (result and result.message) or 'That fare is gone.',
            type = 'error',
        })
    end

    return result
end

-- The keybind path cannot block, so it hands off to a thread; the NUI path
-- already runs on one and wants the answer back.
RegisterCommand('gigaccept', function()
    CreateThread(function() resolveIncomingFare(true) end)
end, false)
RegisterCommand('gigdecline', function() resolveIncomingFare(false) end, false)

-- Real keybinds rather than polling IsControlJustPressed, because the polled
-- version could not work. INPUT_CONTEXT does not fire while seated, which is
-- exactly where a driver is when dispatch reaches them; and E in a vehicle is
-- already the horn, which this resource uses to load a passenger, so E could
-- not have meant "accept" as well. Y and N are uncontested, and being real
-- keybinds these are rebindable from the pause menu like anything else.
RegisterKeyMapping('gigaccept', 'Gig work: accept incoming fare', 'keyboard', 'Y')
RegisterKeyMapping('gigdecline', 'Gig work: decline incoming fare', 'keyboard', 'N')

--- The real-life bit: on duty does not mean "go check the app", it means the
--- app pushes a request at you with a clock running. Accept it, decline it, or
--- let it time out -- either way it is gone from in front of you the moment
--- the clock ends, same as the real thing.
RegisterNetEvent('um_gigs:client:incomingFare', function(offer, responseWindow)
    if job or incomingFare then return end

    incomingFare = offer
    incomingUntil = GetGameTimer() + (responseWindow * 1000)

    local appName = appLabel(offer.app)
    local ok = pcall(function()
        exports['lb-phone']:SendNotification({
            app = offer.app,
            title = offer.playerRide
                and ('Ride request -- $%d'):format(offer.pay)
                or ('%s -- $%d'):format(offer.kindLabel or 'New fare', offer.pay),
            content = offer.playerRide
                and ('%s needs a lift to %s.'):format(offer.passengerName, offer.dropoffLabel)
                or ('Pickup at %s. Respond fast, it will not wait.'):format(offer.pickupLabel),
        })
    end)
    if not ok then
        lib.notify({ title = appName, description = 'Incoming fare -- respond fast.', type = 'inform' })
    end

    CreateThread(function()
        -- Display only: the keybinds and the phone screen do the accepting.
        -- The `not job` half covers taking something else while this card is
        -- still up, so the push does not go on fighting the job's own text UI
        -- for the rest of its countdown.
        while incomingFare == offer and not job and GetGameTimer() < incomingUntil do
            local secondsLeft = math.ceil((incomingUntil - GetGameTimer()) / 1000)

            lib.showTextUI(('%s  |  %s  |  $%d  |  %.1fkm to %s  \n[Y] Accept     [N] Decline     %ds')
                :format(
                    appName,
                    offer.playerRide and 'RIDER' or (offer.kindLabel or 'Fare'),
                    offer.pay,
                    offer.distance / 1000.0,
                    offer.dropoffLabel,
                    secondsLeft
                ))

            Wait(250)
        end

        -- Nobody pressed anything before the clock ran out.
        if incomingFare == offer then
            incomingFare = nil
            lib.hideTextUI()
            TriggerServerEvent('um_gigs:server:declineFare', offer.app, offer.id)
            lib.notify({ title = appName, description = 'Fare timed out.', type = 'inform' })
        end
    end)
end)

--- The board refilled while your phone was in your pocket. Board apps only --
--- a dispatch app has nothing to announce, because its work arrives as a
--- request rather than as a list that got longer.
RegisterNetEvent('um_gigs:client:workAvailable', function(app, count)
    local ok = pcall(function()
        exports['lb-phone']:SendNotification({
            app = app,
            title = count == 1 and 'One job available' or ('%d jobs available'):format(count),
            content = 'New deliveries on the board.',
        })
    end)

    if not ok then
        lib.notify({
            title = appLabel(app),
            description = 'New work on the board.',
            type = 'inform',
        })
    end
end)

-- -----------------------------------------------------------------------------
-- Rider mode, when YOU are the passenger
-- -----------------------------------------------------------------------------

local function clearRiderBlip()
    if riderBlip and DoesBlipExist(riderBlip) then RemoveBlip(riderBlip) end
    riderBlip = nil
end

RegisterNetEvent('um_gigs:client:driverAt', function(x, y, z)
    if not riderBlip or not DoesBlipExist(riderBlip) then
        riderBlip = AddBlipForCoord(x, y, z)
        SetBlipSprite(riderBlip, 225)     -- a car
        SetBlipColour(riderBlip, 5)
        SetBlipScale(riderBlip, 0.85)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName('Your ride')
        EndTextCommandSetBlipName(riderBlip)
    else
        SetBlipCoords(riderBlip, x, y, z)
    end
end)

RegisterNetEvent('um_gigs:client:rideUpdate', function(state, reason)
    rideState = state

    local text = ({
        assigned = 'A driver accepted. They are on the way.',
        onboard  = 'On the way. Sit back.',
        done     = 'You have arrived. Rate your driver in the app.',
        cancelled = reason or 'Your ride was cancelled.',
        expired  = reason or 'No drivers available. You have been refunded.',
    })[state]

    if state ~= 'assigned' and state ~= 'onboard' then clearRiderBlip() end

    if text then
        local ok = pcall(function()
            exports['lb-phone']:SendNotification({
                app = 'rydeme',
                title = 'rydeme',
                content = text,
            })
        end)
        if not ok then
            lib.notify({ title = 'rydeme', description = text, type = 'inform' })
        end
    end
end)

-- -----------------------------------------------------------------------------
-- NPC drivers: the budget option, bought outright instead of dispatched
-- -----------------------------------------------------------------------------
-- See Config.RiderMode.npc. Entirely local theatre: this car and its driver
-- exist only on this machine, the same way a Ryde Me NPC passenger already
-- does not exist for anyone but the driver carrying them. The server has
-- already taken the fare by the time this runs; nothing here reports back,
-- because there is nothing left to keep in sync.

--- A road node roughly `distance` out from `origin`, in a random direction.
--- Puts the car somewhere plausible to arrive FROM rather than conjuring it
--- up on top of the player.
---@param origin vector3
---@param distance number
---@return vector3 coords, number heading
local function nearbyRoadNode(origin, distance)
    local angle = math.random() * 2 * math.pi
    local probe = vec3(
        origin.x + math.cos(angle) * distance,
        origin.y + math.sin(angle) * distance,
        origin.z
    )

    local found, nodePos, heading = GetClosestVehicleNodeWithHeading(probe.x, probe.y, probe.z, 1, 3.0, 0)
    if found then return nodePos, heading end

    return origin, 0.0
end

-- The live state behind the phone's NPC-ride screen: where the car is,
-- what leg it is on, and the Speed Up / End Fare flags the app can set.
-- nil whenever no NPC ride is in progress. Exposed read-only through
-- getLive; only this file ever writes to it.
local npcRide = nil

local SCRIPT_TASK_PERFORM_SEQUENCE = GetHashKey('SCRIPT_TASK_PERFORM_SEQUENCE')

--- Drives `driver`/`veh` to `dest`, then parks -- as ONE task rather than a
--- bare drive-to-coord on its own. This is the exact pattern Rockstar's own
--- taxi script (taxiservice.c) uses for both legs of a taxi job, adopted
--- after a hand-rolled single TaskVehicleDriveToCoordLongrange produced a
--- driver that got out of the car mid-ride and a fare that ended two blocks
--- in: a drive task with nothing chained after it leaves the ped mid-lane at
--- the end of it with no follow-up task, and it is exactly that gap ambient
--- AI climbs into.
---@param driver number
---@param veh number
---@param dest vector3
---@param speed number
---@param driveStyle number
local function driveAndPark(driver, veh, dest, speed, driveStyle)
    local seq = OpenSequenceTask()
    TaskVehicleDriveToCoordLongrange(0, veh, dest.x, dest.y, dest.z, speed, driveStyle, 20.0)
    TaskVehiclePark(0, veh, dest.x, dest.y, dest.z, 0.0, 0, 20.0, true) -- mode 0: ignore heading
    CloseSequenceTask(seq)
    TaskPerformSequence(driver, seq)
    ClearSequenceTask(seq)
end

--- Whether `driver` has finished the sequence driveAndPark started -- the
--- same signal (GET_SCRIPT_TASK_STATUS == finished) taxiservice.c itself
--- waits on, rather than a raw distance check that can fire while the car is
--- still cornering past the point on its way to actually stopping there.
---@param driver number
---@return boolean
local function sequenceFinished(driver)
    return GetScriptTaskStatus(driver, SCRIPT_TASK_PERFORM_SEQUENCE) == 7
end

--- Drives an NPC to the player, waits for them to get in, drives them to
--- `dest`, then cleans itself up. Distance and timeout checks remain as a
--- safety net alongside sequenceFinished() -- GTA's vehicle AI occasionally
--- gets a car stuck on scenery, and a fare that can never end is worse than
--- one that ends early having still gotten most of the way there.
---@param dest vector3
---@param destLabel string
---@param fare number
local function runNpcRide(dest, destLabel, fare)
    local cfg = Config.RiderMode.npc

    lib.notify({
        title = 'rydeme',
        description = ('$%d paid. A driver is on the way.'):format(fare),
        type = 'inform',
    })

    local playerPos = GetEntityCoords(cache.ped)
    local spawnPos, spawnHeading = nearbyRoadNode(playerPos, cfg.spawnDistance)

    local model = cfg.vehicles[math.random(#cfg.vehicles)]
    if not lib.requestModel(model, 8000) then
        lib.notify({ title = 'rydeme', description = 'Could not find you a driver. Refunding.', type = 'error' })
        TriggerServerEvent('um_gigs:server:npcRideFailed', fare)
        return
    end

    -- isNetwork = false on both: this car and its driver are local-only, per
    -- Config.RiderMode.npc's whole design -- nobody else's client needs to
    -- know they exist.
    local veh = CreateVehicle(model, spawnPos.x, spawnPos.y, spawnPos.z, spawnHeading, false, true)
    SetModelAsNoLongerNeeded(model)
    SetVehicleDoorsLocked(veh, 1)
    SetVehicleOnGroundProperly(veh)

    local driverModel = Config.Passengers.peds[math.random(#Config.Passengers.peds)]
    lib.requestModel(driverModel, 8000)
    local driver = CreatePedInsideVehicle(veh, 4, driverModel, -1, false, true)
    SetModelAsNoLongerNeeded(driverModel)

    SetEntityInvincible(veh, true)
    SetEntityInvincible(driver, true)
    SetBlockingOfNonTemporaryEvents(driver, true)
    SetDriverAbility(driver, 1.0)
    SetDriverAggressiveness(driver, 0.0)
    -- Stops the game's ambient AI from ever overriding what this script tasks
    -- the ped with -- taxiservice.c sets this the moment the ped is put in
    -- the car, not partway through, and that timing turned out to matter.
    SetPedKeepTask(driver, true)

    npcRide = { phase = 'approach', driverVeh = veh, dest = dest, destLabel = destLabel, speedBoost = false }

    -- ---- leg one: the car comes to you -------------------------------------
    -- Driven in short attempts rather than one long wait: GTA's vehicle AI
    -- occasionally reports a drive task "finished" (or just runs out the
    -- clock) while the car is stuck on scenery or boxed in by traffic, still
    -- nowhere near pickupRadius. Falling through to TaskEnterVehicle from
    -- there is what used to warp the player across the map into a car that
    -- never actually arrived -- so this only ever boards you once the car has
    -- genuinely pulled up, re-routing it within the overall time budget
    -- otherwise.
    local speed, style, boosted = cfg.approachSpeed, cfg.driveStyle, false
    local overallDeadline = GetGameTimer() + cfg.timeoutSeconds * 1000
    local arrived = false

    lib.showTextUI('Your ride is on the way...')

    while DoesEntityExist(veh) and not arrived and GetGameTimer() < overallDeadline do
        driveAndPark(driver, veh, playerPos, speed, style)
        local attemptDeadline = math.min(overallDeadline, GetGameTimer() + cfg.attemptSeconds * 1000)

        while DoesEntityExist(veh)
            and not sequenceFinished(driver)
            and #(GetEntityCoords(veh) - GetEntityCoords(cache.ped)) > cfg.pickupRadius
            and GetGameTimer() < attemptDeadline
        do
            if npcRide.speedBoost and not boosted then
                boosted = true
                speed = speed * 1.6
                style = cfg.rushedDriveStyle
                SetDriverAggressiveness(driver, 1.0)
                driveAndPark(driver, veh, playerPos, speed, style)
            end
            Wait(250)
        end

        if DoesEntityExist(veh) and #(GetEntityCoords(veh) - GetEntityCoords(cache.ped)) <= cfg.pickupRadius then
            arrived = true
        end
    end
    lib.hideTextUI()

    if not DoesEntityExist(veh) then npcRide = nil; return end

    if not arrived then
        -- The car never actually made it. Boarding from here would mean
        -- teleporting the player to wherever it got stuck, which is worse
        -- than admitting the driver could not reach them -- refunded the same
        -- way a failed spawn is, since neither is the player's fault.
        lib.notify({
            title = 'rydeme',
            description = 'Your driver could not reach you. Refunding your fare.',
            type = 'error',
        })
        TriggerServerEvent('um_gigs:server:npcRideFailed', fare)
        npcRide = nil
        DeleteEntity(veh)
        DeleteEntity(driver)
        return
    end

    -- Hold the car at idle rather than clearing its task outright -- an empty
    -- task list on a ped "sitting in vehicle" is exactly what let ambient AI
    -- take over and climb out on its own, which is the bug this whole
    -- function was rewritten to fix. taxiservice.c holds the same way.
    TaskVehicleTempAction(driver, veh, 1, 1000000) -- 1: brake, held
    SetPedKeepTask(driver, true)

    -- A short honk once it has actually pulled up -- the beat a real
    -- rideshare driver gives you before you walk over, rather than the car
    -- just sitting there mute.
    StartVehicleHorn(veh, 350, GetHashKey('NORMAL'), false)

    -- ---- get in -------------------------------------------------------------
    -- Auto-walk-and-board, the same idea um_beg uses for a car that pulls up
    -- to give: TaskEnterVehicle handles both the approach and the climb-in as
    -- one task, so ordering a ride does not also mean walking over and
    -- mashing E yourself. ClearPedTasks first for the same reason um_beg
    -- clears before its own TaskGoToEntity -- an idle/ambient task already on
    -- the ped can otherwise block the new one from taking over. Only reached
    -- once `arrived` is true, so the car is always genuinely within
    -- pickupRadius here -- a short, natural walk-up rather than a long-range
    -- warp.
    lib.showTextUI('Getting in...')
    ClearPedTasks(cache.ped)
    TaskEnterVehicle(cache.ped, veh, 20000, 0, 1.0, 1, 0)

    local boardDeadline = GetGameTimer() + 20000
    while DoesEntityExist(veh) and GetVehiclePedIsIn(cache.ped, false) ~= veh and GetGameTimer() < boardDeadline do
        Wait(200)
    end
    lib.hideTextUI()

    if not DoesEntityExist(veh) or GetVehiclePedIsIn(cache.ped, false) ~= veh then
        -- Walked off instead of getting in, or the car never made it. An NPC
        -- fare is bought outright rather than held, so there is nothing to
        -- refund here -- only a failed SPAWN (above) counts as the app's
        -- fault rather than the player's.
        npcRide = nil
        if DoesEntityExist(veh) then DeleteEntity(veh) end
        if DoesEntityExist(driver) then DeleteEntity(driver) end
        return
    end

    if Config.Nav.setWaypoint then SetNewWaypoint(dest.x, dest.y) end
    lib.notify({ title = 'rydeme', description = ('On the way to %s.'):format(destLabel), type = 'inform' })

    npcRide.phase = 'boarded'

    -- ---- leg two: the car takes you there ------------------------------------
    -- Same reasoning as leg one's approach: a drive task that reports
    -- "finished" (or a deadline that just runs out) while the car is still
    -- nowhere near the destination used to end the fare right there anyway,
    -- putting you out wherever it got stuck instead of at the actual
    -- drop-off. This re-routes it within the overall time budget until it
    -- genuinely gets there, and says so honestly if it never does rather than
    -- claiming "arrived" at the wrong spot.
    speed, style, boosted = cfg.dropoffSpeed, cfg.driveStyle, false
    local dropoffDeadline = GetGameTimer() + cfg.timeoutSeconds * 1000
    local reachedDest = false

    while DoesEntityExist(veh)
        and GetVehiclePedIsIn(cache.ped, false) == veh
        and not reachedDest
        and GetGameTimer() < dropoffDeadline
        and not npcRide.endRequested
    do
        driveAndPark(driver, veh, dest, speed, style)
        local attemptDeadline = math.min(dropoffDeadline, GetGameTimer() + cfg.attemptSeconds * 1000)

        while DoesEntityExist(veh)
            and GetVehiclePedIsIn(cache.ped, false) == veh
            and not sequenceFinished(driver)
            and #(GetEntityCoords(veh) - dest) > cfg.arriveRadius
            and GetGameTimer() < attemptDeadline
            and not npcRide.endRequested
        do
            if npcRide.speedBoost and not boosted then
                boosted = true
                speed = speed * 1.6
                style = cfg.rushedDriveStyle
                SetDriverAggressiveness(driver, 1.0)
                driveAndPark(driver, veh, dest, speed, style)
                lib.notify({ title = 'rydeme', description = 'Your driver puts their foot down.', type = 'inform' })
            end
            Wait(250)
        end

        if DoesEntityExist(veh) and #(GetEntityCoords(veh) - dest) <= cfg.arriveRadius then
            reachedDest = true
        end
    end

    if DoesEntityExist(veh) and GetVehiclePedIsIn(cache.ped, false) == veh then
        local message, kind
        if npcRide.endRequested then
            message, kind = 'Fare ended early.', 'inform'
        elseif reachedDest then
            message, kind = 'You have arrived.', 'success'
        else
            message, kind = 'Your driver got stuck short of the address -- this is as close as they could get.', 'inform'
        end

        lib.notify({ title = 'rydeme', description = message, type = kind })
        TaskLeaveVehicle(cache.ped, veh, 0)
    end

    -- The rating screen is the last thing the app shows for this ride --
    -- npcRateDriver clears npcRide once submitted, or a timeout does if the
    -- player never opens the app back up to answer it.
    if npcRide then
        npcRide.phase = 'done'
        CreateThread(function()
            Wait(60000)
            if npcRide and npcRide.phase == 'done' then npcRide = nil end
        end)
    end

    Wait(2500)
    if DoesEntityExist(veh) then DeleteEntity(veh) end
    if DoesEntityExist(driver) then DeleteEntity(driver) end
end

RegisterNetEvent('um_gigs:client:npcRideStart', function(dest, destLabel, fare)
    if npcRide then return end -- already got one going; do not spawn a second
    CreateThread(function() runNpcRide(vec3(dest.x, dest.y, dest.z), destLabel, fare) end)
end)

RegisterNUICallback('um_gigs:npcSpeedUp', function(_, cb)
    if npcRide then npcRide.speedBoost = true end
    cb({ ok = true })
end)

--- "Let me out here." Only meaningful once boarded -- the approach leg has
--- its own way to bail (just do not get in), and ending before that would
--- have nothing to end.
RegisterNUICallback('um_gigs:npcEndRide', function(_, cb)
    if npcRide and npcRide.phase == 'boarded' then npcRide.endRequested = true end
    cb({ ok = true })
end)

--- A rating for the AI, kept exactly as serious as that sounds: nobody reads
--- it, nothing downstream changes because of it. It exists because being
--- asked to rate your ride is the joke the rest of this app is already
--- telling, and an NPC fare should not be the one experience that skips it.
RegisterNUICallback('um_gigs:npcRateDriver', function(data, cb)
    local stars = math.max(1, math.min(5, math.floor(tonumber(data and data.stars) or 5)))
    lib.notify({
        title = 'rydeme',
        description = ('You rated your driver %d/5. They will never know.'):format(stars),
        type = 'inform',
    })
    npcRide = nil
    cb({ ok = true })
end)

-- -----------------------------------------------------------------------------
-- NUI. Both apps talk to the same callbacks and say which one they are, so the
-- two UIs stay thin and the logic lives in one place.
-- -----------------------------------------------------------------------------

RegisterNUICallback('um_gigs:getState', function(data, cb)
    local app = data and data.app
    if app ~= 'snarf' and app ~= 'rydeme' then return cb({ offers = {}, rating = 0 }) end

    local res = lib.callback.await('um_gigs:server:getState', false, app)

    if not res then
        -- A nil here means the server callback errored or never answered. The
        -- fallback below is indistinguishable from an honestly empty board in
        -- the UI, which is what made this hard to see the first time.
        print(('^1[um_gigs]^7 no answer from server for %s -- check the server console'):format(app))
    end

    cb(res or { offers = {}, rating = 0, serverFailed = true })
end)

--- Answered locally, with no server round trip. The countdown on an incoming
--- request has to tick smoothly and the client already knows the deadline --
--- asking the server for it once a second would be a lot of traffic to
--- re-derive a number we set ourselves.
RegisterNUICallback('um_gigs:getLive', function(_, cb)
    local out = { hasJob = job ~= nil, stage = stage, rideState = rideState }

    if incomingFare then
        out.incoming = incomingFare
        out.incomingSeconds = math.max(0, math.ceil((incomingUntil - GetGameTimer()) / 1000))
    end

    if job then
        out.job = {
            pay = job.pay,
            kindLabel = job.kindLabel,
            pickupLabel = job.pickupLabel,
            dropoffLabel = job.dropoffLabel,
            passengerName = job.passengerName,
            playerRide = job.playerRide or false,
            stage = stage,
        }

        -- The "phone mounted on the dash" HUD: a live map, current speed, and
        -- the posted limit, the same information a real nav app puts on
        -- screen while driving. Ryde Me only -- Snarf has no speed mechanic
        -- and nobody is watching how you drive to a restaurant.
        local target = stage == 'pickup' and job.pickup or job.dropoff
        if job.app == 'rydeme' and target then
            out.target = { x = target.x, y = target.y }

            local pos = GetEntityCoords(cache.ped)
            out.pos = { x = pos.x, y = pos.y }

            local veh = GetVehiclePedIsIn(cache.ped, false)
            if veh ~= 0 then
                out.speedMph = math.floor((GetEntitySpeed(veh) * 2.23694) + 0.5)
            end

            -- Over-limit is only real during the watched dropoff leg, and
            -- only if the passenger has not waived it -- identical gating to
            -- the world-space speedometer and the rating penalty it mirrors.
            -- The app should never warn about a rule that is not live.
            if stage == 'dropoff' and Config.SpeedLimit.enabled and not speedFreed then
                out.speedLimit = postedLimit
                out.overLimit = postedLimit ~= nil and out.speedMph ~= nil
                    and out.speedMph > (postedLimit + Config.SpeedLimit.graceMph)
            end
        end
    end

    -- The rider-side view of an NPC ride: where the car is relative to you
    -- (approach) or to your destination (boarded), plus whatever Speed Up has
    -- done to it. Nothing here is server state -- see the npcRide upvalue.
    if npcRide then
        local npcOut = {
            phase = npcRide.phase,
            destLabel = npcRide.destLabel,
            speedBoost = npcRide.speedBoost or false,
        }

        if npcRide.driverVeh and DoesEntityExist(npcRide.driverVeh) then
            local vp = GetEntityCoords(npcRide.driverVeh)
            npcOut.driverPos = { x = vp.x, y = vp.y }
        end

        if npcRide.phase ~= 'done' then
            local pp = GetEntityCoords(cache.ped)
            npcOut.pos = { x = pp.x, y = pp.y }
            npcOut.destPos = { x = npcRide.dest.x, y = npcRide.dest.y }
        end

        out.npcRide = npcOut
    end

    cb(out)
end)

RegisterNUICallback('um_gigs:getProfile', function(data, cb)
    local app = data and data.app
    if app ~= 'rydeme' and app ~= 'snarf' then return cb({ rating = 0, history = {} }) end

    local res = lib.callback.await('um_gigs:server:getProfile', false, app)
    cb(res or { rating = 0, history = {} })
end)

RegisterNUICallback('um_gigs:setAvatar', function(data, cb)
    local app = data and data.app
    if app ~= 'rydeme' and app ~= 'snarf' then return cb({ ok = false }) end

    local ok = lib.callback.await('um_gigs:server:setAvatar', false, app, data.avatar)
    cb({ ok = ok == true })
end)

RegisterNUICallback('um_gigs:accept', function(data, cb)
    if job then
        cb({ ok = false, message = 'Finish the one you have first.' })
        return
    end

    -- Accepting the card that is already up goes through the same path the Y
    -- key does, so the text UI and the countdown come down with it.
    if incomingFare and incomingFare.id == data.id then
        cb(resolveIncomingFare(true) or { ok = false, message = 'That fare is gone.' })
        return
    end

    local result = lib.callback.await('um_gigs:server:accept', false, data.app, data.id)
    cb(result or { ok = false, message = 'That job is gone.' })
end)

RegisterNUICallback('um_gigs:decline', function(_, cb)
    resolveIncomingFare(false)
    cb({ ok = true })
end)

RegisterNUICallback('um_gigs:setDuty', function(data, cb)
    local app = data and data.app
    if app ~= 'snarf' and app ~= 'rydeme' then return cb({ ok = false }) end

    TriggerServerEvent('um_gigs:server:setDuty', app, data.on and true or false)
    cb({ ok = true })
end)

RegisterNUICallback('um_gigs:cancel', function(_, cb)
    if job then
        TriggerServerEvent('um_gigs:server:cancel', job.app)
        endJob()
    end
    cb({ ok = true })
end)

--- Turns a bare (x, y) into a usable destination: real ground height, snapped
--- to the nearest road, with a street name. Shared by both ways of picking a
--- point on the Ride tab, so a tapped pin and a read-back waypoint behave
--- identically once they reach this.
---
--- GetGroundZFor_3dCoord's own docs say it only resolves "when the
--- coordinates are within the client's render distance" -- and
--- RequestCollisionAtCoord alone does not put a genuinely distant point (the
--- entire reason a map picker exists) inside that, which is why this failed
--- on almost every tap rather than just the far ones: most of a full map is
--- outside render distance from wherever the player is actually standing.
---
--- SetFocusPosAndVel is the actual fix, not RequestCollisionAtCoord: it
--- overrides where the game renders and streams terrain to an arbitrary
--- point without moving the player or camera there -- the trick teleport and
--- spawn-selector menus use to check a destination before sending anyone to
--- it. ClearFocus hands the override back once this is done with it.
---@param x number
---@param y number
---@param fallbackLabel string used only if the point turns out to be unnamed
---@return table
local function resolveDestPoint(x, y, fallbackLabel)
    SetFocusPosAndVel(x, y, 300.0, 0.0, 0.0, 0.0)
    RequestCollisionAtCoord(x, y, 300.0)

    -- Polled every frame rather than every 100ms: the whole time this loop
    -- runs, the world is streaming in around the TAPPED point instead of the
    -- player, which is what makes their own surroundings visibly drop to LOD
    -- models while this is up. Checking every tick instead of every 100ms
    -- means the common case -- a point that resolves in a handful of frames
    -- -- hands focus back almost immediately instead of always burning
    -- however many whole 100ms steps it took to line up with a check.
    local found, z = false, 30.0
    local deadline = GetGameTimer() + 3000
    while not found and GetGameTimer() < deadline do
        found, z = GetGroundZFor_3dCoord(x, y, 1000.0, false)
        if not found then Wait(0) end
    end

    if not found then
        ClearFocus()
        return { ok = false, message = 'Could not find ground there. Try somewhere else on the map.' }
    end

    -- Snap to the nearest road and read the street name -- still under the
    -- same focus override, since both of these are just as tied to the world
    -- actually being streamed in as the ground check above was. Clearing
    -- focus before this would only move the failure here instead of fixing
    -- it.
    local px, py, pz = x, y, z
    local nodeFound, nodePos = GetClosestVehicleNodeWithHeading(x, y, z, 1, 3.0, 0)
    if nodeFound then px, py, pz = nodePos.x, nodePos.y, nodePos.z end

    local street = GetStreetNameFromHashKey(GetStreetNameAtCoord(px, py, pz))
    local label = (street ~= '') and street or fallbackLabel

    ClearFocus()

    return { ok = true, x = px, y = py, z = pz, label = label }
end

--- A tap on the Ride tab's own map.
RegisterNUICallback('um_gigs:resolveMapPoint', function(data, cb)
    local x, y = tonumber(data and data.x), tonumber(data and data.y)
    if not x or not y then return cb({ ok = false, message = 'Bad map point.' }) end

    cb(resolveDestPoint(x, y, 'Dropped pin'))
end)

--- Where the player actually is, purely to centre the map on them when the
--- picker opens blank -- this has no bearing on pricing, which is always
--- computed server-side off the request's own coordinates.
RegisterNUICallback('um_gigs:getMyCoords', function(_, cb)
    local pos = GetEntityCoords(cache.ped)
    cb({ ok = true, x = pos.x, y = pos.y })
end)

--- Reads whatever waypoint the player has ALREADY set on their own map -- a
--- shortcut into the same map picker, for someone who already knows exactly
--- where they are going and set a pin for it there instead of in the app.
RegisterNUICallback('um_gigs:getMyWaypoint', function(_, cb)
    local blip = GetFirstBlipInfoId(8) -- 8 = the player's own waypoint cross
    if not DoesBlipExist(blip) then
        return cb({ ok = false, message = 'Open your map and drop a waypoint first, then come back here.' })
    end

    local pos = GetBlipCoords(blip)
    cb(resolveDestPoint(pos.x, pos.y, 'Your waypoint'))
end)

RegisterNUICallback('um_gigs:quoteRide', function(data, cb)
    local res = lib.callback.await('um_gigs:server:quoteRide', false, {
        custom = data and data.custom,
        npc = data and data.npc or false,
    })
    cb(res or { ok = false })
end)

RegisterNUICallback('um_gigs:requestRide', function(data, cb)
    local opts = {
        index = data and data.index,
        custom = data and data.custom,
        npc = data and data.npc or false,
    }

    -- Caught here rather than only server-side: the server has no concept of
    -- an NPC ride at all (it is bought outright, not booked), so it cannot
    -- refuse a second one on its own. This is a courtesy check, not a lock --
    -- two clicks in the same frame could still both pass it -- but it is
    -- what stops the ordinary double-tap from spawning two cars and paying
    -- for both.
    if opts.npc and npcRide then
        return cb({ ok = false, message = 'Finish your current ride first.' })
    end

    local res = lib.callback.await('um_gigs:server:requestRide', false, opts)

    -- An NPC ride never goes through the searching/assigned/onboard states --
    -- it is bought, not booked -- so it has no business setting rideState.
    if res and res.ok and not res.npc then rideState = 'searching' end

    cb(res or { ok = false, message = 'Could not reach rydeme.' })
end)

RegisterNUICallback('um_gigs:cancelRide', function(_, cb)
    local res = lib.callback.await('um_gigs:server:cancelRide', false)
    rideState = nil
    clearRiderBlip()
    cb(res or { ok = false })
end)

RegisterNUICallback('um_gigs:rateDriver', function(data, cb)
    local res = lib.callback.await(
        'um_gigs:server:rateDriver', false, data and data.stars, data and data.comment)
    rideState = nil
    cb(res or { ok = false })
end)

-- -----------------------------------------------------------------------------
-- Job lifecycle
-- -----------------------------------------------------------------------------

RegisterNetEvent('um_gigs:client:startJob', function(assigned)
    if job then return end

    job = assigned
    job.pickup = vec3(assigned.pickup.x, assigned.pickup.y, assigned.pickup.z)
    job.dropoff = vec3(assigned.dropoff.x, assigned.dropoff.y, assigned.dropoff.z)

    -- Road-snapping is a Ryde Me fix: you pull up there, so the stop has to be
    -- somewhere a car can reach. Config.Addresses are already road nodes, so
    -- this matters mainly for a player ride: the pickup is wherever the rider
    -- happens to be standing, and the dropoff might be a waypoint they set on
    -- their own map rather than a curated address, so both ends get snapped
    -- now rather than trusting the pin. Snarf is a walk-up-to-the-ped delivery
    -- and is meant to put you at the actual door, not the nearest drivable
    -- point, so it stays exempt.
    if job.app == 'rydeme' then
        job.pickup = snapToRoad(job.pickup)
        job.dropoff = snapToRoad(job.dropoff)
    end

    stage = 'pickup'
    startedAt = GetGameTimer()
    crashes, fastTicks, totalTicks = 0, 0, 0
    sawWanted, crashSpokeAt = false, 0
    postedLimit, speedingSeconds = nil, 0.0
    speedFreed, speedRequestAt = false, nil
    rideVeh, rideClass, rideVehLabel = 0, nil, nil
    fuelArmed = false

    routeTo(job.pickup, job.pickupLabel, job.app == 'snarf' and 267 or 198)

    -- Snarf: someone at the counter hands the order over. Burger Shot already
    -- has an ox_inventory shop ped standing on the spot, so there we put a zone
    -- over them instead of spawning a second body in the same place.
    if job.app == 'snarf' then
        local r = restaurantById(job.restaurantId)

        addInteraction({
            ped = (r and not r.shopPed) and r.ped or nil,
            coords = job.pickup,
            heading = r and r.heading or 0.0,
            icon = 'fa-solid fa-bag-shopping',
            label = 'Collect the order',
            onSelect = function() collectOrder() end,
        })
    end

    lib.notify({
        title = appLabel(job.app),
        description = job.app == 'snarf'
            and ('Collect from %s.'):format(job.pickupLabel)
            or ('Collect %s from %s.'):format(job.passengerName, job.pickupLabel),
        type = 'inform',
    })
end)

RegisterNetEvent('um_gigs:client:cancelJob', function()
    releasePassenger()
    endJob()
end)

CreateThread(function()
    -- lb-phone needs to be up before an app can be added to it.
    while GetResourceState('lb-phone') ~= 'started' do Wait(500) end
    Wait(2000)
    registerApps()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearRiderBlip()
    endJob()
end)
