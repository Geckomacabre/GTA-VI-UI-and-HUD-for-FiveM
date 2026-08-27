-- -----------------------------------------------------------------------------
-- um_gigs -- server
-- -----------------------------------------------------------------------------
-- Two apps with one job loop underneath, but two different SHAPES of work:
--
--   Snarf  is a board. Offers sit in `boards.snarf`, everyone sees the same
--          list, you pick one off it. That is what couriering looks like.
--   RydeMe is dispatch. There is no list. A request is built for one driver at
--          the moment it is offered to them, it lives in `pendingFare` while
--          their clock runs, and it is gone the instant that clock stops. The
--          whole point of Config.DispatchOnly is that a rideshare with a
--          permanent menu of fares is not a rideshare.
--
-- On top of that, Ryde Me has a rider side: `rideRequests` holds fares that a
-- real player asked for, with real money held against them.
-- -----------------------------------------------------------------------------

-- app -> list of live offers. Only ever populated for BOARD apps; a dispatch
-- app's requests are built on demand and never pooled.
local boards = { snarf = {} }
local active = {}    -- src -> the gig they took
local duty = {}      -- src -> { snarf = bool, goober = bool }
local lastPing = {}  -- src .. app -> os.time() of the last "jobs available" ping
local nextId = 0

-- src .. app -> the offer table currently sitting in front of them, waiting on
-- a response, and when their clock runs out. Dispatch apps keep the whole offer
-- here (there is no board to look it up in); board apps keep it too so the
-- phone screen can render the same card the text UI is showing.
local pendingFare = {}
local pendingUntil = {}
-- src .. app -> os.time() before which this driver is not to be offered
-- anything. Rolled randomly each time, which is what stops dispatch having a
-- rhythm (see Config.Dispatch).
local nextDispatch = {}

-- Rider mode. id -> request. `riderRide[src]` is the reverse index so a rider
-- can find their own without a scan.
local rideRequests = {}
local riderRide = {}
local nextRideId = 0

-- driverSrc -> { rideId, driverName } waiting on the RIDER to leave a rating.
local awaitingRating = {}

local function dbg(fmt, ...)
    if Config.Debug then print(('^5[um_gigs]^7 ' .. fmt):format(...)) end
end

-- -----------------------------------------------------------------------------
-- Rating and history
-- -----------------------------------------------------------------------------

--- Reads the rating straight off PlayerData rather than through GetMetadata.
--- GetMetadata bails with a bare `return` when the player is not loaded, and a
--- bare return is zero values, not nil -- so `tonumber(GetMetadata(...))` was
--- calling tonumber with no arguments at all, which throws. That killed the
--- whole state callback, and an empty app is what the player saw.
---@param src number
---@return number
local function getRating(src)
    local player = exports.qbx_core:GetPlayer(src)

    if not player then
        dbg('no loaded player for %s -- using the default rating', src)
        return Config.Rating.start
    end

    return tonumber(player.PlayerData.metadata.gig_rating) or Config.Rating.start
end

---@param src number
---@param delta number
---@return number
local function moveRating(src, delta)
    local r = getRating(src) + delta
    r = math.max(Config.Rating.min, math.min(Config.Rating.max, r))

    -- No player means nothing to write to, and SetMetadata would no-op silently.
    if not exports.qbx_core:GetPlayer(src) then
        print(('^1[um_gigs]^7 cannot save rating for %s -- player not loaded'):format(src))
        return r
    end

    exports.qbx_core:SetMetadata(src, 'gig_rating', r)
    return r
end

---@param a vector3|table
---@param b vector3|table
---@return number
local function dist(a, b)
    return #(vec3(a.x, a.y, a.z) - vec3(b.x, b.y, b.z))
end

local function pick(list) return list[math.random(#list)] end

--- Weighted pick over a list of tables carrying a numeric `weight`.
---@param list table
---@return table
local function pickWeighted(list)
    local total = 0
    for _, e in ipairs(list) do total = total + (e.weight or 1) end

    local roll = math.random() * total
    for _, e in ipairs(list) do
        roll = roll - (e.weight or 1)
        if roll <= 0 then return e end
    end

    return list[#list]
end

--- Where a player is standing, as a plain table, or nil if they are not really
--- there. Server-side GetEntityCoords is authoritative and needs no client
--- round trip, which is what lets dispatch offer a pickup near the driver.
---@param src number
---@return vector3?
local function playerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end

    local c = GetEntityCoords(ped)
    -- A player still streaming in reads as the origin; treat that as unknown
    -- rather than dispatching every new arrival a fare from Vespucci docks.
    if c.x == 0.0 and c.y == 0.0 then return nil end

    return c
end

---@param src number
---@return string
local function playerName(src)
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return 'Rider' end

    local info = player.PlayerData.charinfo
    if info and info.firstname then
        return info.firstname .. (info.lastname and (' ' .. info.lastname:sub(1, 1) .. '.') or '')
    end

    return player.PlayerData.name or 'Rider'
end

--- The rider-facing history behind the Driver Profile screen. Stored as JSON
--- on player metadata, same trick as gig_rating -- it needs to survive a
--- reconnect, and this is not enough data to want its own table.
---@param src number
---@return table
local function loadHistory(src)
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return {} end

    local raw = player.PlayerData.metadata.gig_goober_history
    if not raw or raw == '' then return {} end

    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return {} end

    return decoded
end

---@param src number
---@param entry table
local function pushHistory(src, entry)
    if not exports.qbx_core:GetPlayer(src) then return end

    local history = loadHistory(src)
    table.insert(history, 1, entry)

    while #history > Config.History.limit do
        table.remove(history)
    end

    exports.qbx_core:SetMetadata(src, 'gig_goober_history', json.encode(history))
end

--- The Driver Profile avatar: a URL (lb-phone's own components.uploadMedia
--- result, or a gallery item's .src), stored on player metadata the same way
--- as gig_goober_history. This is a link into lb-phone's own media storage,
--- not image data itself, so the length cap here is just to stop a tampered
--- NUI call from writing something absurd rather than sizing for a photo.
---@param src number
---@return string?
local function loadAvatar(src)
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return nil end

    local raw = player.PlayerData.metadata.gig_goober_avatar
    return (raw and raw ~= '') and raw or nil
end

local MAX_AVATAR_LEN = 2048

---@param src number
---@param dataUrl unknown
---@return boolean
local function saveAvatar(src, dataUrl)
    if not exports.qbx_core:GetPlayer(src) then return false end

    if dataUrl == nil or dataUrl == false then
        exports.qbx_core:SetMetadata(src, 'gig_goober_avatar', nil)
        return true
    end

    if type(dataUrl) ~= 'string' or #dataUrl == 0 or #dataUrl > MAX_AVATAR_LEN
        or not (dataUrl:match('^https?://') or dataUrl:match('^data:image/')) then
        return false
    end

    exports.qbx_core:SetMetadata(src, 'gig_goober_avatar', dataUrl)
    return true
end

lib.callback.register('um_gigs:server:setAvatar', function(src, dataUrl)
    return saveAvatar(src, dataUrl)
end)

-- -----------------------------------------------------------------------------
-- What the rider actually writes
-- -----------------------------------------------------------------------------

--- Turns "how the ride went" into "what this particular person put on the app".
---
--- The two are not the same thing and never were. `clean` is the objective
--- score -- five, minus a star for every way you made the trip worse. What
--- lands on the profile is that number pushed around by who was in the car:
--- some people mark everything down, some people give five stars for showing
--- up, and the roll in the middle stops the same drive scoring identically
--- twice. Your STANDING is still computed from what you did (see complete);
--- this only decides what the review says.
---@param clean number stars before the rider's own temperament
---@return number stars, string? comment
local function reviewFor(clean)
    local reviewer = pickWeighted(Config.Feedback.reviewers)

    -- The bias is a lean, not a guarantee: a harsh reviewer usually knocks one
    -- off, sometimes cannot be bothered. Otherwise every 'harsh' roll is
    -- exactly -1 and the noise has a shape you can see.
    local stars = clean
    if reviewer.bias ~= 0 and math.random() < 0.75 then
        stars = stars + reviewer.bias
    end

    stars = math.max(1, math.min(5, math.floor(stars + 0.5)))

    local silence = Config.Feedback.silence[stars] or 0.3
    if math.random() < silence then return stars, nil end

    local pool
    if stars >= 5 then pool = Config.Feedback.great
    elseif stars == 4 then pool = Config.Feedback.good
    elseif stars == 3 then pool = Config.Feedback.mixed
    else pool = Config.Feedback.bad end

    return stars, pool and pick(pool) or nil
end

-- -----------------------------------------------------------------------------
-- Vehicle class pricing
-- -----------------------------------------------------------------------------

--- The multiplier and label for a GTA vehicle class id. The client reports the
--- class of the car the passenger actually got into; the rate itself is looked
--- up here so a modified client cannot name its own price.
---@param class number?
---@return table
local function classInfo(class)
    local c = tonumber(class)
    if not c then return Config.VehicleClassDefault end

    return Config.VehicleClasses[c] or Config.VehicleClassDefault
end

---@param mult number
---@return string
local function tierFor(mult)
    for _, t in ipairs(Config.VehicleTiers) do
        if mult >= t.atLeast then return t.label end
    end

    return Config.VehicleTiers[#Config.VehicleTiers].label
end

-- -----------------------------------------------------------------------------
-- Building fares
-- -----------------------------------------------------------------------------

--- Prices a distance inside a fare band. Linear across the band with a little
--- wobble, then rounded to something that reads as a price rather than as
--- arithmetic.
---@param band table
---@param metres number
---@return number
local function priceFare(band, metres)
    local km = metres / 1000.0
    local span = band.maxKm - band.minKm
    local t = span > 0 and ((km - band.minKm) / span) or 0
    t = math.max(0, math.min(1, t))

    local pay = band.minPay + (band.maxPay - band.minPay) * t
    pay = pay * (1.0 + (math.random() * 2 - 1) * Config.Fares.jitter)
    pay = math.floor(pay / Config.Fares.roundTo + 0.5) * Config.Fares.roundTo

    return math.max(band.minPay, math.min(band.maxPay, pay))
end

--- Which length of fare to roll. Below the good-rating threshold the app leans
--- hard on the short, cheap end -- the dispatch-only equivalent of trimming a
--- board down to its worst two entries, and just as quiet about it.
---@param rating number
---@return table
local function pickBand(rating)
    if rating < Config.Rating.goodThreshold and math.random() < Config.Rating.lowShortBias then
        return Config.Fares.short
    end

    return pickWeighted({ Config.Fares.short, Config.Fares.long })
end

--- Picks a pickup/dropoff pair whose straight-line distance lands inside the
--- band, preferring a pickup near the driver. Short fares are only ever
--- offered within one region, because "2 km" between two Blaine County
--- addresses does not exist on this map and the search would just churn.
---@param band table
---@param near vector3? where the driver is, if we know
---@return table pickup, table dropoff, number metres
local function pickRoute(band, near)
    local best, bestMiss

    for _ = 1, Config.Fares.attempts do
        local a = pick(Config.Addresses)

        -- Bias the pickup towards the driver: reject far ones most of the time
        -- rather than always, so a quiet corner of the map still gets work.
        if near and dist(a.coords, near) > Config.Fares.nearDriverMetres and math.random() < 0.8 then
            goto continue
        end

        do
            local b = pick(Config.Addresses)
            if b.label == a.label then goto continue end
            if band.id == 'short' and a.region ~= b.region then goto continue end

            local d = dist(a.coords, b.coords)
            local km = d / 1000.0

            if km >= band.minKm and km <= band.maxKm then
                return a, b, d
            end

            -- Keep the nearest miss, so a band that cannot be satisfied on this
            -- map still produces a fare rather than nothing at all.
            local miss = (km < band.minKm) and (band.minKm - km) or (km - band.maxKm)
            if not bestMiss or miss < bestMiss then
                best, bestMiss = { a, b, d }, miss
            end
        end

        ::continue::
    end

    if best then return best[1], best[2], best[3] end

    -- Nothing survived the filters at all (a tiny Config.Addresses, say).
    local a = pick(Config.Addresses)
    local b = pick(Config.Addresses)
    while b.label == a.label do b = pick(Config.Addresses) end

    return a, b, dist(a.coords, b.coords)
end

--- Builds one Ryde Me request for one driver. Dispatch-only work is made at
--- the moment it is offered and belongs to nobody else, which is why this does
--- not touch `boards`.
---@param src number
---@return table
local function makeFare(src)
    nextId = nextId + 1

    local band = pickBand(getRating(src))
    local pickup, dropoff, d = pickRoute(band, playerCoords(src))
    local mood = pick(Config.Passengers.moods)

    return {
        id = nextId,
        app = 'goober',
        kind = band.id,
        kindLabel = band.label,
        pickup = { x = pickup.coords.x, y = pickup.coords.y, z = pickup.coords.z },
        pickupHeading = pickup.heading or 0.0,
        pickupLabel = pickup.label,
        dropoff = { x = dropoff.coords.x, y = dropoff.coords.y, z = dropoff.coords.z },
        dropoffLabel = dropoff.label,
        distance = d,
        pay = priceFare(band, d),
        mood = mood,
        passengerName = pick(Config.Passengers.names),
        expires = os.time() + Config.OfferLifetime,
    }
end

--- Builds one Snarf board offer. Snarf keeps the old flat pricing: it is a
--- delivery, not a fare, and the short/long bands are a rideshare idea.
---@return table
local function makeDelivery()
    nextId = nextId + 1

    local r = pick(Config.Restaurants)
    local dropoff = pick(Config.Addresses)
    local d = dist(r.coords, dropoff.coords)
    local pay = math.max(
        Config.Pay.minPay,
        math.floor(Config.Pay.base + (d / 1000.0) * Config.Pay.perKm)
    )

    local note = pick(Config.CustomerNotes)

    return {
        id = nextId,
        app = 'snarf',
        pickup = { x = r.coords.x, y = r.coords.y, z = r.coords.z },
        pickupLabel = r.label,
        restaurantId = r.id,
        dropoff = { x = dropoff.coords.x, y = dropoff.coords.y, z = dropoff.coords.z },
        dropoffLabel = dropoff.label,
        distance = d,
        pay = pay,
        order = pick(Config.Orders),
        note = note.text,
        noteEffect = note.effect,
        expires = os.time() + Config.OfferLifetime,
    }
end

--- Refills a BOARD app and drops anything expired.
---@param app string
---@return number added
local function refresh(app)
    if not boards[app] then return 0 end

    local now = os.time()
    local kept = {}

    for _, o in ipairs(boards[app]) do
        if o.expires > now then kept[#kept + 1] = o end
    end

    local added = 0
    while #kept < Config.OfferCount do
        kept[#kept + 1] = makeDelivery()
        added = added + 1
    end

    boards[app] = kept

    return added
end

-- -----------------------------------------------------------------------------
-- Dispatch
-- -----------------------------------------------------------------------------

---@param src number
---@param app string
local function rollGap(src, app, first)
    local lo = first and Config.Dispatch.firstGapMin or Config.Dispatch.minGap
    local hi = first and Config.Dispatch.firstGapMax or Config.Dispatch.maxGap

    nextDispatch[src .. app] = os.time() + math.random(lo, hi)
end

--- Puts one request in front of one driver and starts their clock.
---@param src number
---@param app string
---@param offer table
local function pushFare(src, app, offer)
    local key = src .. app

    pendingFare[key] = offer
    pendingUntil[key] = os.time() + Config.Dispatch.responseWindow

    TriggerClientEvent('um_gigs:client:incomingFare', src, offer, Config.Dispatch.responseWindow)
end

---@param src number
---@param app string
local function clearPending(src, app)
    local key = src .. app
    pendingFare[key], pendingUntil[key] = nil, nil
end

--- True if this driver is in a state to be offered anything at all.
---@param src number
---@param app string
---@return boolean
local function dispatchable(src, app)
    if active[src] then return false end
    if riderRide[src] then return false end -- you cannot drive yourself
    if not (duty[src] and duty[src][app]) then return false end
    if pendingFare[src .. app] then return false end

    return true
end

--- The steady drip of NPC work for on-duty drivers.
---@param app string
local function dispatchFares(app)
    local now = os.time()

    for src, apps in pairs(duty) do
        if apps[app] and dispatchable(src, app) then
            local due = nextDispatch[src .. app]

            if due and now >= due then
                local offer = (app == 'goober') and makeFare(src) or nil

                if not offer then
                    -- Board apps push whatever is already on the board.
                    for _, o in ipairs(boards[app] or {}) do
                        if o.expires > now then offer = o break end
                    end
                end

                if offer then
                    -- The gap is rolled NOW, not on the answer, so a driver who
                    -- ignores their phone is not rewarded with a faster queue.
                    rollGap(src, app)
                    pushFare(src, app, offer)
                end
            end
        end
    end
end

--- Pulls back any request whose clock has run out server-side. The client runs
--- the same countdown for display, but the server owns the deadline -- a client
--- that never answers must not leave a fare parked forever.
local function expirePending()
    local now = os.time()

    for key, until_ in pairs(pendingUntil) do
        if now >= until_ then
            pendingFare[key], pendingUntil[key] = nil, nil
        end
    end
end

--- Tells everyone clocked on for a BOARD app that work turned up.
---@param app string
---@param added number
local function pingDuty(app, added)
    if added <= 0 or Config.DispatchOnly[app] then return end

    local now = os.time()

    for src, apps in pairs(duty) do
        -- Nobody mid-gig wants to hear about the next one.
        if apps[app] and not active[src] then
            local key = src .. app

            if not lastPing[key] or (now - lastPing[key]) >= Config.Duty.notifyCooldown then
                lastPing[key] = now
                TriggerClientEvent('um_gigs:client:workAvailable', src, app, added)
            end
        end
    end
end

-- -----------------------------------------------------------------------------
-- Rider mode
-- -----------------------------------------------------------------------------

---@return number
local function onlineDrivers()
    local n = 0
    for src, apps in pairs(duty) do
        if apps.goober and not riderRide[src] then n = n + 1 end
    end
    return n
end

--- Turns a live ride request into the offer card a driver is shown. Built
--- fresh each time it is offered because the pickup is wherever the rider is
--- standing right now, not where they were when they asked.
---@param req table
---@return table?
local function riderOffer(req)
    local at = playerCoords(req.rider)
    if not at then return nil end

    return {
        id = req.id,
        app = 'goober',
        playerRide = true,
        riderSrc = req.rider,
        kind = req.kind,
        kindLabel = req.kindLabel,
        pickup = { x = at.x, y = at.y, z = at.z },
        pickupLabel = req.pickupLabel,
        dropoff = { x = req.dropoff.x, y = req.dropoff.y, z = req.dropoff.z },
        dropoffLabel = req.dropoffLabel,
        distance = req.distance,
        -- The driver is shown their NET take, the rider is shown the gross.
        -- Both numbers are true and they are not the same number, which is the
        -- entire business model.
        pay = req.driverPay,
        grossFare = req.fare,
        passengerName = req.riderName,
        mood = { id = 'player', label = 'Real passenger', line = '' },
        expires = req.expires,
    }
end

--- Refunds the hold and closes a request out.
---@param req table
---@param state string
---@param reason string?
local function closeRide(req, state, reason, refund)
    req.state = state
    req.reason = reason
    req.closedAt = os.time()

    if refund and req.held and req.held > 0 then
        local player = exports.qbx_core:GetPlayer(req.rider)
        if player then
            player.Functions.AddMoney(Config.Account, req.held, 'rydeme-refund')
        end
        req.held = 0
    end

    -- Anyone still holding a card for this ride loses it.
    for key, offer in pairs(pendingFare) do
        if offer.playerRide and offer.id == req.id then
            pendingFare[key], pendingUntil[key] = nil, nil
        end
    end

    TriggerClientEvent('um_gigs:client:rideUpdate', req.rider, state, reason)
end

--- Offers a live player request to every idle on-duty driver who has not
--- already got a card up. First one to accept takes it; the rest find it gone.
---@param req table
local function broadcastRide(req)
    local offer = riderOffer(req)
    if not offer then return end

    for src, apps in pairs(duty) do
        if apps.goober and src ~= req.rider and not (req.declined and req.declined[src])
            and dispatchable(src, 'goober')
        then
            -- A real person waiting at the kerb jumps the pacing queue: the gap
            -- exists to stop the NPC drip feeling like a conveyor belt, and
            -- that reasoning does not apply here.
            if Config.Dispatch.playerRideIgnoresGap
                or (nextDispatch[src .. 'goober'] or 0) <= os.time()
            then
                pushFare(src, 'goober', offer)
            end
        end
    end
end

-- -----------------------------------------------------------------------------
-- Duty
-- -----------------------------------------------------------------------------

RegisterNetEvent('um_gigs:server:setDuty', function(app, on)
    local src = source
    if app ~= 'snarf' and app ~= 'goober' then return end

    duty[src] = duty[src] or {}
    duty[src][app] = on and true or nil

    if not next(duty[src]) then duty[src] = nil end

    if on then
        rollGap(src, app, true)
    else
        clearPending(src, app)
        nextDispatch[src .. app] = nil
    end

    dbg('%s is now %s duty for %s', src, on and 'ON' or 'OFF', app)
end)

--- The driver dismissed an incoming request, or their clock ran out. For NPC
--- work the request simply ceases to exist -- it was built for them and nobody
--- else. For a player ride it stays alive for whoever else is out there.
RegisterNetEvent('um_gigs:server:declineFare', function(app, id)
    local src = source
    if app ~= 'snarf' and app ~= 'goober' then return end

    local key = src .. app
    local offer = pendingFare[key]
    if not offer or offer.id ~= id then return end

    -- A player request survives a decline -- it belongs to the rider, not to
    -- the driver who waved it away -- so remember who said no. Without this
    -- the re-broadcast eight seconds later puts the same card straight back up
    -- in front of the same person, which is the opposite of declining it.
    if offer.playerRide then
        local req = rideRequests[offer.id]
        if req then
            req.declined = req.declined or {}
            req.declined[src] = true
        end
    end

    clearPending(src, app)
end)

-- -----------------------------------------------------------------------------
-- App state
-- -----------------------------------------------------------------------------

--- Everything one app screen needs, in one round trip. Replaces the old
--- getOffers: a dispatch app has no offers to get, and the phone still has to
--- be able to show the request that is currently in front of you, whether you
--- are looking at the screen or at the road.
lib.callback.register('um_gigs:server:getState', function(src, app)
    if app ~= 'snarf' and app ~= 'goober' then
        return { offers = {}, rating = 0 }
    end

    local rating = getRating(src)
    local dispatchOnly = Config.DispatchOnly[app] == true

    local state = {
        app = app,
        rating = rating,
        hasJob = active[src] ~= nil,
        onDuty = (duty[src] and duty[src][app]) == true,
        dispatchOnly = dispatchOnly,
        warnThreshold = Config.Rating.warnThreshold,
        offers = {},
    }

    if state.hasJob then
        local gig = active[src]
        state.job = {
            pay = gig.pay,
            kindLabel = gig.kindLabel,
            pickupLabel = gig.pickupLabel,
            dropoffLabel = gig.dropoffLabel,
            passengerName = gig.passengerName,
            playerRide = gig.playerRide or false,
        }
    end

    -- The request currently on the card, with whatever is left of its clock.
    local pending = pendingFare[src .. app]
    if pending then
        state.incoming = pending
        state.incomingSeconds = math.max(0, (pendingUntil[src .. app] or 0) - os.time())
    end

    if not dispatchOnly then
        local ok, err = pcall(refresh, app)
        if not ok then
            print(('^1[um_gigs]^7 refresh(%s) failed: %s'):format(app, err))
            state.refillFailed = true
            return state
        end

        local offers = boards[app]

        -- Below the good-rating threshold you only see the cheapest work, which
        -- is the joke and the progression in one: the app punishes you quietly.
        if rating < Config.Rating.goodThreshold then
            local sorted = {}
            for i = 1, #offers do sorted[i] = offers[i] end
            table.sort(sorted, function(a, b) return a.pay < b.pay end)

            local trimmed = {}
            for i = 1, math.min(Config.Rating.lowOfferCount, #sorted) do
                trimmed[i] = sorted[i]
            end
            offers = trimmed
        end

        state.offers = offers
    end

    -- ---- rider side -------------------------------------------------------
    if app == 'goober' and Config.RiderMode.enabled then
        state.riderMode = true
        state.driversOnline = onlineDrivers()

        local req = riderRide[src] and rideRequests[riderRide[src]]
        if req then
            state.ride = {
                id = req.id,
                state = req.state,
                reason = req.reason,
                destLabel = req.dropoffLabel,
                fare = req.fare,
                distance = req.distance,
                driverName = req.driverName,
                driverRating = req.driverRating,
                vehicle = req.vehicleLabel,
                tier = req.tier,
                secondsLeft = (req.state == 'searching')
                    and math.max(0, req.expires - os.time()) or nil,
            }
        end

        local pendingRate = awaitingRating[src]
        if pendingRate then
            state.rateDriver = pendingRate
        end

        -- Where a rider can ask to go, nearest first. Sent with the state so
        -- the app never has to hold a second copy of Config.Addresses.
        local at = playerCoords(src)
        local dests = {}
        for i, a in ipairs(Config.Addresses) do
            local d = at and dist(a.coords, at) or 0
            dests[#dests + 1] = {
                index = i,
                label = a.label,
                region = a.region,
                distance = d,
                fare = math.max(
                    Config.RiderMode.minFare,
                    math.min(
                        Config.RiderMode.maxFare,
                        math.floor(Config.RiderMode.base + (d / 1000.0) * Config.RiderMode.perKm)
                    )
                ),
            }
        end
        table.sort(dests, function(a, b) return a.distance < b.distance end)
        state.destinations = dests
    end

    dbg('state %s for %s: duty %s, job %s, incoming %s',
        app, src, tostring(state.onDuty), tostring(state.hasJob), tostring(state.incoming ~= nil))

    return state
end)

-- -----------------------------------------------------------------------------
-- Taking work
-- -----------------------------------------------------------------------------

lib.callback.register('um_gigs:server:accept', function(src, app, id)
    if app ~= 'snarf' and app ~= 'goober' then
        return { ok = false, message = 'Unknown app.' }
    end

    if active[src] then
        return { ok = false, message = 'Finish the one you have first.' }
    end
    if riderRide[src] then
        return { ok = false, message = 'You have a ride of your own booked.' }
    end

    local pending = pendingFare[src .. app]
    local chosen

    -- A dispatched request only ever exists on the card in front of you.
    if pending and pending.id == id then
        chosen = pending
        clearPending(src, app)
    elseif not Config.DispatchOnly[app] then
        for i, o in ipairs(boards[app] or {}) do
            if o.id == id then
                chosen = o
                table.remove(boards[app], i)
                break
            end
        end
    end

    if not chosen then return { ok = false, message = 'That fare is gone.' } end
    if chosen.expires and chosen.expires <= os.time() then
        return { ok = false, message = 'That fare expired.' }
    end

    -- ---- a real person asked for this one ---------------------------------
    if chosen.playerRide then
        local req = rideRequests[chosen.id]
        if not req or req.state ~= 'searching' then
            return { ok = false, message = 'Someone else got there first.' }
        end

        local at = playerCoords(req.rider)
        if not at then
            return { ok = false, message = 'That rider is no longer around.' }
        end

        req.state = 'assigned'
        req.driver = src
        req.driverName = playerName(src)
        req.driverRating = getRating(src)
        req.assignedAt = os.time()

        -- Every other driver's card for this ride goes dead.
        for key, offer in pairs(pendingFare) do
            if offer.playerRide and offer.id == req.id then
                pendingFare[key], pendingUntil[key] = nil, nil
            end
        end

        chosen.pickup = { x = at.x, y = at.y, z = at.z }
        TriggerClientEvent('um_gigs:client:rideUpdate', req.rider, 'assigned')
    end

    active[src] = chosen
    rollGap(src, app)

    TriggerClientEvent('um_gigs:client:startJob', src, chosen)

    return { ok = true, message = 'On your way.' }
end)

-- -----------------------------------------------------------------------------
-- Finishing
-- -----------------------------------------------------------------------------

--- Everything both endings need: clear the gig, close out a player ride, and
--- hand the numbers back.
---@param src number
---@return table? gig
local function takeActive(src)
    local gig = active[src]
    active[src] = nil
    return gig
end

--- The ride ended before the drop-off: dead engine, dry tank. No pay, and the
--- rider leaves the review of somebody stood at the roadside.
RegisterNetEvent('um_gigs:server:abort', function(data)
    local src = source
    local gig = active[src]

    if not gig or type(data) ~= 'table' or data.offerId ~= gig.id then return end
    if gig.app ~= 'goober' then return end

    takeActive(src)

    local reason = data.reason == 'fuel' and 'ran out of fuel' or 'the car died'
    local newRating = moveRating(src, -Config.Abort.ratingPenalty)

    pushHistory(src, {
        name = gig.passengerName or 'Rider',
        stars = Config.Abort.stars,
        comment = pick(Config.Abort.comments),
        pay = 0,
        tip = 0,
        ts = os.time(),
        aborted = true,
    })

    if gig.playerRide then
        local req = rideRequests[gig.id]
        if req then closeRide(req, 'cancelled', 'The driver broke down.', true) end
    end

    exports.qbx_core:Notify(src,
        ('Fare ended -- %s. No payment. %.2f stars.'):format(reason, newRating), 'error')
end)

RegisterNetEvent('um_gigs:server:complete', function(data)
    local src = source
    local gig = active[src]

    -- Only pay for a gig this server actually handed out.
    if not gig or type(data) ~= 'table' or data.offerId ~= gig.id then return end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end

    takeActive(src)

    local pay = gig.pay
    local ratingDelta = Config.Rating.step
    local reasons = {}
    -- Stars for THIS ride, before the rider's own temperament gets a say.
    local clean = 5
    local wanted = false

    -- ---- what you were driving --------------------------------------------
    -- Applied to the FARE, not to Snarf: a delivery does not care what the bag
    -- arrived in. The class comes off the car the passenger actually got into.
    local info = Config.VehicleClassDefault
    if gig.app == 'goober' then
        info = classInfo(data.vehicleClass)
        pay = math.floor(pay * info.mult)
        if info.mult ~= 1.0 then
            reasons[#reasons + 1] = ('%s rate'):format(info.label)
        end
    end

    -- ---- late --------------------------------------------------------------
    if data.late then
        pay = math.floor(pay * (1.0 - Config.Pay.latePenalty))
        ratingDelta = -Config.Rating.step
        clean = clean - 1
        reasons[#reasons + 1] = 'late'
    end

    if gig.app == 'goober' then
        -- ---- police --------------------------------------------------------
        -- Not a matter of degree. From the back seat there is no difference
        -- between one star and five, so neither is there here.
        if Config.Wanted.enabled and data.wanted then
            wanted = true
            clean = Config.Wanted.stars
            ratingDelta = -Config.Wanted.ratingPenalty
            reasons[#reasons + 1] = 'brought the police along'
        end

        -- ---- how you drove -------------------------------------------------
        local crashes = math.max(0, math.min(20, tonumber(data.crashes) or 0))
        if crashes > 0 then
            ratingDelta = ratingDelta - (Config.Driving.crashPenalty * math.min(crashes, 3))
            clean = clean - math.min(2, crashes)
            reasons[#reasons + 1] = crashes == 1 and 'one bump' or (crashes .. ' bumps')
        end

        local fast = math.max(0, math.min(1, tonumber(data.speedFraction) or 0))
        -- A rider who told you to hurry has forfeited the right to complain
        -- about it, so the nervous-passenger check only applies if they never
        -- asked.
        if gig.mood and gig.mood.hatesSpeed and not data.speedFreed and fast > 0.35 then
            ratingDelta = ratingDelta - Config.Driving.speedPenalty
            clean = clean - 1
            reasons[#reasons + 1] = 'drove too fast for them'
        end

        -- Time spent over the posted limit. Clamped at both ends: the cap keeps
        -- one long motorway blast from being ride-ending, and the sanity
        -- ceiling on the raw number stops a bad client claiming an absurd
        -- figure. Skipped entirely if the rider waived it.
        if Config.SpeedLimit.enabled and not data.speedFreed then
            local speeding = math.max(0, math.min(3600, tonumber(data.speedingSeconds) or 0))
            if speeding > 0 then
                local penalty = math.min(
                    Config.SpeedLimit.maxPenalty,
                    speeding * Config.SpeedLimit.penaltyPerSecond
                )
                ratingDelta = ratingDelta - penalty

                -- Only worth mentioning once it is a real chunk, otherwise
                -- every ride ends with a nag about three seconds of coasting.
                if penalty >= 0.05 then
                    clean = clean - 1
                    reasons[#reasons + 1] = ('%ds over the limit'):format(math.floor(speeding))
                end
            end
        end

        if gig.mood and gig.mood.rush and not data.late then
            ratingDelta = ratingDelta + Config.Rating.step
            reasons[#reasons + 1] = 'got them there in time'
        end

        -- ---- "I will cover the ticket" --------------------------------------
        if data.speedFreed and data.hurried then
            local bonus = math.floor(pay * Config.SpeedRequest.bonusMultiplier)
            if bonus > 0 then
                pay = pay + bonus
                reasons[#reasons + 1] = ('$%d for the hurry'):format(bonus)
            end
        end
    end

    -- Snarf: the note on the order changes what they wanted.
    if gig.app == 'snarf' and gig.noteEffect == 'rush' and data.late then
        ratingDelta = ratingDelta - Config.Rating.step
    end

    clean = math.max(0, math.min(5, clean))
    pay = math.max(0, pay)

    -- ---- tip ---------------------------------------------------------------
    local tip = 0
    if not data.late and not wanted and ratingDelta > 0 then
        tip = math.floor(pay * Config.Pay.maxTipMultiplier * math.random())
    end

    local newRating = moveRating(src, ratingDelta)

    -- ---- a player ride pays out of somebody's pocket ------------------------
    if gig.playerRide then
        local req = rideRequests[gig.id]
        if req then
            -- The rider's money was taken when they asked; the driver is paid
            -- the platform's leavings, and the rider is asked to rate rather
            -- than a pool of canned lines deciding for them.
            pay = req.driverPay
            tip = 0
            req.state = 'done'
            req.finishedAt = os.time()

            awaitingRating[req.rider] = {
                rideId = req.id,
                driver = src,
                driverName = req.driverName,
                fare = req.fare,
                destLabel = req.dropoffLabel,
            }

            TriggerClientEvent('um_gigs:client:rideUpdate', req.rider, 'done')
        end
    end

    player.Functions.AddMoney(Config.Account, pay + tip, 'gig-' .. gig.app)

    -- ---- the review --------------------------------------------------------
    -- Ryde Me only -- Snarf customers do not leave the equivalent of a star
    -- review in this resource today. A player ride is rated by the player, so
    -- nothing is written here; it lands when they submit.
    if gig.app == 'goober' and not gig.playerRide then
        local stars, comment

        if wanted then
            -- Nobody shrugs this one off, so it skips the temperament roll.
            stars, comment = Config.Wanted.stars, pick(Config.Wanted.comments)
        else
            stars, comment = reviewFor(clean)
        end

        pushHistory(src, {
            name = gig.passengerName or 'Rider',
            stars = stars,
            comment = comment,
            pay = pay,
            tip = tip,
            ts = os.time(),
            tier = (gig.app == 'goober') and tierFor(info.mult) or nil,
        })
    end

    local summary = ('$%d'):format(pay)
    if tip > 0 then summary = summary .. (' plus $%d tip'):format(tip) end
    summary = summary .. (' | %.2f stars'):format(newRating)
    if #reasons > 0 then summary = summary .. ' (' .. table.concat(reasons, ', ') .. ')' end

    exports.qbx_core:Notify(src, summary, (data.late or wanted) and 'error' or 'success')
end)

RegisterNetEvent('um_gigs:server:cancel', function()
    local src = source
    local gig = active[src]
    if not gig then return end

    takeActive(src)

    if gig.playerRide then
        local req = rideRequests[gig.id]
        if req and req.state ~= 'done' then
            -- The rider gets their money back and goes to the back of the
            -- queue; they did nothing wrong.
            closeRide(req, 'cancelled', 'Your driver cancelled.', true)
        end
    end

    -- Cancelling costs standing. Otherwise the right play is to reroll until a
    -- short job appears, and the offer means nothing.
    local r = moveRating(src, -Config.Rating.step * 2)

    TriggerClientEvent('um_gigs:client:cancelJob', src)
    exports.qbx_core:Notify(src, ('Job cancelled. %.2f stars.'):format(r), 'inform')
end)

lib.callback.register('um_gigs:server:getProfile', function(src, app)
    if app ~= 'goober' then return { rating = 0, history = {} } end

    return {
        rating = getRating(src),
        history = loadHistory(src),
        warnThreshold = Config.Rating.warnThreshold,
        avatar = loadAvatar(src),
    }
end)

-- -----------------------------------------------------------------------------
-- Rider mode callbacks
-- -----------------------------------------------------------------------------

--- A price for a custom (waypoint) destination without booking anything --
--- what the named Config.Addresses list already gets for free by having its
--- fares computed once in getState. A waypoint's fare cannot be precomputed
--- the same way because it does not exist until the player sets one, so the
--- map preview asks for a quote here before the player commits to it.
lib.callback.register('um_gigs:server:quoteRide', function(src, opts)
    opts = type(opts) == 'table' and opts or {}
    if type(opts.custom) ~= 'table' or not opts.custom.x then
        return { ok = false }
    end

    local at = playerCoords(src)
    if not at then return { ok = false } end

    local d = dist(vec3(opts.custom.x, opts.custom.y, opts.custom.z), at)
    local pricing = (opts.npc == true and Config.RiderMode.npc.enabled)
        and Config.RiderMode.npc or Config.RiderMode

    local fare = math.max(
        pricing.minFare,
        math.min(pricing.maxFare, math.floor(pricing.base + (d / 1000.0) * pricing.perKm))
    )

    return { ok = true, fare = fare, distance = d }
end)

--- opts: { index = Config.Addresses index } or { custom = {x,y,z} } for a spot
--- picked on the Ride tab's map, plus optional { npc = true } for the bought
--- -outright budget option instead of dispatching to a real driver.
lib.callback.register('um_gigs:server:requestRide', function(src, opts)
    opts = type(opts) == 'table' and opts or {}

    if not Config.RiderMode.enabled then
        return { ok = false, message = 'Rider mode is off.' }
    end
    if active[src] then
        return { ok = false, message = 'You are driving a fare right now.' }
    end
    if riderRide[src] then
        return { ok = false, message = 'You already have a ride booked.' }
    end

    local destCoords, destLabel
    if type(opts.custom) == 'table' and opts.custom.x then
        -- A waypoint the player set themselves, not one of Config.Addresses --
        -- distance and pricing work exactly the same either way. The label is
        -- whatever street name the client resolved at that point; a bare
        -- coordinate with no name at all falls back to the generic one.
        destCoords = vec3(opts.custom.x, opts.custom.y, opts.custom.z)
        destLabel = (type(opts.custom.label) == 'string' and opts.custom.label ~= '')
            and opts.custom.label or Config.RiderMode.customDestLabel
    else
        local a = Config.Addresses[tonumber(opts.index) or 0]
        if not a then return { ok = false, message = 'Pick a destination.' } end
        destCoords = a.coords
        destLabel = a.label
    end

    local at = playerCoords(src)
    if not at then return { ok = false, message = 'Cannot find where you are.' } end

    local d = dist(destCoords, at)
    if d < 60.0 then
        return { ok = false, message = 'You are already there. Walk.' }
    end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return { ok = false, message = 'Not loaded.' } end

    -- ---- the budget option: bought outright, nobody actually dispatched ---
    -- No hold/refund cycle and no rideRequests entry, because there is no
    -- driver to accept or cancel on you -- the client spawns the car itself
    -- the moment payment clears, the same illusion a Ryde Me NPC passenger
    -- already is for everyone who is not that driver.
    if opts.npc == true and Config.RiderMode.npc.enabled then
        local pricing = Config.RiderMode.npc
        local fare = math.max(
            pricing.minFare,
            math.min(pricing.maxFare, math.floor(pricing.base + (d / 1000.0) * pricing.perKm))
        )

        if not player.Functions.RemoveMoney(Config.Account, fare, 'rydeme-npc-fare') then
            return { ok = false, message = ('You need $%d for that ride.'):format(fare) }
        end

        TriggerClientEvent('um_gigs:client:npcRideStart', src,
            { x = destCoords.x, y = destCoords.y, z = destCoords.z }, destLabel, fare)

        dbg('%s bought an NPC ride to %s for $%d', src, destLabel, fare)

        return { ok = true, npc = true, fare = fare }
    end

    -- ---- a real driver: the existing dispatch/hold/refund path ------------
    local fare = math.max(
        Config.RiderMode.minFare,
        math.min(
            Config.RiderMode.maxFare,
            math.floor(Config.RiderMode.base + (d / 1000.0) * Config.RiderMode.perKm)
        )
    )

    -- The hold. Same as a real app putting the fare on your card before a
    -- driver has even accepted -- and refunded the same way if nothing comes
    -- of it.
    local held = 0
    if Config.RiderMode.holdFunds then
        if not player.Functions.RemoveMoney(Config.Account, fare, 'rydeme-fare') then
            return { ok = false, message = ('You need $%d for that ride.'):format(fare) }
        end
        held = fare
    end

    nextRideId = nextRideId + 1
    local id = 'r' .. nextRideId

    local band = (d / 1000.0) <= Config.Fares.short.maxKm and Config.Fares.short or Config.Fares.long

    local req = {
        id = id,
        rider = src,
        riderName = playerName(src),
        state = 'searching',
        pickupLabel = 'Rider pickup',
        dropoff = { x = destCoords.x, y = destCoords.y, z = destCoords.z },
        dropoffLabel = destLabel,
        distance = d,
        fare = fare,
        held = held,
        driverPay = math.max(1, math.floor(fare * (1.0 - Config.RiderMode.platformCut))),
        kind = band.id,
        kindLabel = band.label,
        expires = os.time() + Config.RiderMode.requestLifetime,
    }

    rideRequests[id] = req
    riderRide[src] = id

    broadcastRide(req)

    dbg('%s requested a ride to %s for $%d (%d drivers online)',
        src, destLabel, fare, onlineDrivers())

    return { ok = true, fare = fare, drivers = onlineDrivers() }
end)

--- The only refund path on the NPC side: the client could not even spawn a
--- car (a bad model, streaming failure, whatever). That is the app's fault,
--- not the player declining to get in once one showed up, which is why this
--- is the one NPC failure that pays the fare back.
RegisterNetEvent('um_gigs:server:npcRideFailed', function(fare)
    local src = source
    local amount = math.max(0, math.min(Config.RiderMode.npc.maxFare, tonumber(fare) or 0))
    if amount <= 0 then return end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end

    player.Functions.AddMoney(Config.Account, amount, 'rydeme-npc-refund')
    exports.qbx_core:Notify(src, ('Refunded $%d -- no driver available.'):format(amount), 'inform')
end)

lib.callback.register('um_gigs:server:cancelRide', function(src)
    local id = riderRide[src]
    local req = id and rideRequests[id]
    if not req then return { ok = false, message = 'No ride to cancel.' } end

    if req.state == 'searching' then
        closeRide(req, 'cancelled', 'You cancelled.', true)
    elseif req.state == 'assigned' or req.state == 'onboard' then
        -- A driver already set off. They keep the cancellation fee; the rider
        -- gets the rest back.
        local fee = math.floor((req.held or 0) * Config.RiderMode.cancelFee)
        local driver = exports.qbx_core:GetPlayer(req.driver)
        if driver and fee > 0 then
            driver.Functions.AddMoney(Config.Account, fee, 'rydeme-cancelfee')
            exports.qbx_core:Notify(req.driver,
                ('Rider cancelled. $%d cancellation fee.'):format(fee), 'inform')
        end

        req.held = math.max(0, (req.held or 0) - fee)

        if req.driver and active[req.driver] and active[req.driver].id == req.id then
            active[req.driver] = nil
            TriggerClientEvent('um_gigs:client:cancelJob', req.driver)
        end

        closeRide(req, 'cancelled', 'You cancelled.', true)
    else
        return { ok = false, message = 'Too late to cancel.' }
    end

    riderRide[src] = nil
    rideRequests[req.id] = nil

    return { ok = true }
end)

--- The rider rates their driver. This is the only place a Ryde Me rating comes
--- from a human rather than from Config.Feedback, which is why it goes straight
--- onto the driver's profile without passing through the temperament roll.
lib.callback.register('um_gigs:server:rateDriver', function(src, stars, comment)
    local pendingRate = awaitingRating[src]
    if not pendingRate then return { ok = false } end

    awaitingRating[src] = nil

    local s = math.max(1, math.min(5, math.floor(tonumber(stars) or 5)))
    local text = nil
    if type(comment) == 'string' and comment ~= '' then
        text = comment:sub(1, 90)
    end

    -- A five is worth about a step up; a one is worth a good deal more than a
    -- step down, because being rated one star by an actual person should hurt
    -- more than being rated one star by a table of adjectives.
    local delta = (s - 3.5) * Config.Rating.step * 0.8
    if s <= 2 then delta = delta * 1.5 end

    local driver = pendingRate.driver
    if exports.qbx_core:GetPlayer(driver) then
        local newRating = moveRating(driver, delta)

        pushHistory(driver, {
            name = playerName(src),
            stars = s,
            comment = text,
            pay = math.max(1, math.floor(pendingRate.fare * (1.0 - Config.RiderMode.platformCut))),
            tip = 0,
            ts = os.time(),
            player = true,
        })

        exports.qbx_core:Notify(driver,
            ('%s rated you %d/5. %.2f stars.'):format(playerName(src), s, newRating),
            s >= 4 and 'success' or 'inform')
    end

    -- The ride is finished with now.
    local req = rideRequests[pendingRate.rideId]
    if req then
        rideRequests[req.id] = nil
        if riderRide[req.rider] == req.id then riderRide[req.rider] = nil end
    end

    return { ok = true }
end)

--- The driver's client tells us the rider is aboard, so the rider's own screen
--- can stop saying "your driver is on the way".
RegisterNetEvent('um_gigs:server:riderAboard', function()
    local src = source
    local gig = active[src]
    if not gig or not gig.playerRide then return end

    local req = rideRequests[gig.id]
    if not req or req.state ~= 'assigned' then return end

    req.state = 'onboard'
    TriggerClientEvent('um_gigs:client:rideUpdate', req.rider, 'onboard')
end)

--- The driver's position, relayed to their rider so the rider's map can show
--- the car coming. Rate-limited by the client, not trusted for anything.
RegisterNetEvent('um_gigs:server:driverPing', function(x, y, z, vehicleLabel, class)
    local src = source
    local gig = active[src]
    if not gig or not gig.playerRide then return end

    local req = rideRequests[gig.id]
    if not req or (req.state ~= 'assigned' and req.state ~= 'onboard') then return end

    if vehicleLabel and not req.vehicleLabel then
        req.vehicleLabel = vehicleLabel
        req.tier = tierFor(classInfo(class).mult)
    end

    TriggerClientEvent('um_gigs:client:driverAt', req.rider, x, y, z)
end)

-- -----------------------------------------------------------------------------
-- Housekeeping
-- -----------------------------------------------------------------------------

AddEventHandler('playerDropped', function()
    local src = source

    -- A driver who drops mid-player-ride leaves somebody standing there.
    local gig = active[src]
    if gig and gig.playerRide then
        local req = rideRequests[gig.id]
        if req and req.state ~= 'done' then
            closeRide(req, 'cancelled', 'Your driver disconnected.', true)
        end
    end

    -- ...and a rider who drops mid-ride owes their driver the cancellation fee.
    local id = riderRide[src]
    local req = id and rideRequests[id]
    if req then
        if (req.state == 'assigned' or req.state == 'onboard') and req.driver then
            local fee = math.floor((req.held or 0) * Config.RiderMode.cancelFee)
            local driver = exports.qbx_core:GetPlayer(req.driver)
            if driver and fee > 0 then
                driver.Functions.AddMoney(Config.Account, fee, 'rydeme-cancelfee')
            end

            if active[req.driver] and active[req.driver].id == req.id then
                active[req.driver] = nil
                TriggerClientEvent('um_gigs:client:cancelJob', req.driver)
                exports.qbx_core:Notify(req.driver, 'Your rider disconnected.', 'error')
            end
        end

        rideRequests[id] = nil
    end

    active[src] = nil
    duty[src] = nil
    riderRide[src] = nil
    awaitingRating[src] = nil

    for _, app in ipairs({ 'snarf', 'goober' }) do
        lastPing[src .. app] = nil
        pendingFare[src .. app] = nil
        pendingUntil[src .. app] = nil
        nextDispatch[src .. app] = nil
    end
end)

-- The board refill. Snarf only -- Ryde Me has no board to refill.
CreateThread(function()
    while true do
        Wait(Config.RefreshSeconds * 1000)

        for app in pairs(boards) do
            local ok, added = pcall(refresh, app)

            if ok then
                pingDuty(app, added)
            else
                print(('^1[um_gigs]^7 background refresh(%s) failed: %s'):format(app, added))
            end
        end
    end
end)

-- The push. This is what makes work feel like it arrives at you rather than
-- like a list you happened to look at -- and, just as importantly, what makes
-- it arrive with GAPS in it (see Config.Dispatch).
CreateThread(function()
    while true do
        Wait(Config.Dispatch.checkInterval * 1000)

        expirePending()

        for _, app in ipairs({ 'snarf', 'goober' }) do
            local ok, err = pcall(dispatchFares, app)
            if not ok then
                print(('^1[um_gigs]^7 dispatchFares(%s) failed: %s'):format(app, err))
            end
        end
    end
end)

-- Player ride requests: re-offered while they wait, refunded if nobody bites.
CreateThread(function()
    while true do
        Wait(8000)

        local now = os.time()

        for id, req in pairs(rideRequests) do
            if req.state == 'searching' then
                if now >= req.expires then
                    closeRide(req, 'expired', 'No drivers available. You have been refunded.', true)
                    riderRide[req.rider] = nil
                    rideRequests[id] = nil
                else
                    local ok, err = pcall(broadcastRide, req)
                    if not ok then
                        print(('^1[um_gigs]^7 broadcastRide failed: %s'):format(err))
                    end
                end
            elseif req.closedAt and (now - req.closedAt) > 120 then
                -- Closed rides hang around briefly so the rider's screen can
                -- show what happened, then go.
                if riderRide[req.rider] == id then riderRide[req.rider] = nil end
                rideRequests[id] = nil
            end
        end
    end
end)
