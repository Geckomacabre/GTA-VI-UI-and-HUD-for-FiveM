Config = {}

-- -----------------------------------------------------------------------------
-- um_gigs -- phone gig work
-- -----------------------------------------------------------------------------
-- Two SEPARATE phone apps, deliberately. Nobody has one app that does food and
-- rides, and a single "work" app would read as a game menu rather than a phone.
-- They share this resource because the underlying job loop is the same; they do
-- not share an icon, a name or a screen.
--
--   Snarf    -- food delivery. Collect from a restaurant, drive to an address.
--              Still a BOARD: a courier picks a run off a list, which is what
--              the real thing looks like.
--   Ryde Me  -- rideshare. Dispatch-only. There is no list of fares sitting
--              there waiting; a request arrives, a clock starts, you take it or
--              it goes to somebody else. Plus a rider side, so a fare can be
--              another player rather than a spawned ped.
--
-- Both are parodies, and the satire is GTA's own target: not the logos, the
-- BUSINESS. Snarf calls you a Partner, rates you out of five, and keeps most
-- of the money. Ryde Me borrows the neon-pink rideshare parody that already
-- exists in-universe rather than inventing a third one.
--
-- WHY THIS EXISTS
-- Everything else on this server requires you to drive to a fixed place to find
-- out whether there is work. This is work that arrives on your phone, which is
-- the thing a solo player actually wants: something to do, offered, wherever
-- they happen to be.
-- -----------------------------------------------------------------------------

Config.Account = 'cash'

-- App registration. Read by client.lua and handed to lb-phone.
Config.Apps = {
    snarf = {
        identifier = 'snarf',
        name = 'Snarf',
        description = 'Be your own boss. Hours not guaranteed.',
        developer = 'Snarf Global',
        icon = 'nui://um_gigs/ui/snarf.svg',
        ui = 'um_gigs/ui/snarf.html',
        size = 48,
    },
    rydeme = {
        identifier = 'rydeme',
        name = 'rydeme',
        description = 'Rides from strangers, priced dynamically.',
        developer = 'rydeme',
        icon = 'nui://um_gigs/ui/rydeme.svg',
        ui = 'um_gigs/ui/rydeme.html',
        size = 52,
    },
}

-- -----------------------------------------------------------------------------
-- Board vs dispatch.
-- -----------------------------------------------------------------------------
-- A browsable list of fares that never runs out is the single most game-like
-- thing this resource used to do: two or three rides permanently parked in the
-- app, pick whichever is closest, repeat. Nothing about that reads as a
-- rideshare. Ryde Me is dispatch-only now -- you go online, and requests are
-- pushed at you one at a time with a clock. The board machinery is still here
-- because Snarf genuinely is a board: a courier picking a run off a list is
-- what that job actually looks like.
Config.DispatchOnly = {
    snarf = false,
    rydeme = true,
}

-- How many offers sit in a BOARD app at once, and how often the list refreshes.
Config.OfferCount = 3
Config.RefreshSeconds = 90

-- Offers expire, so the list is never a stale queue you work through. Also the
-- lifetime of a dispatched request once it has been generated.
Config.OfferLifetime = 300

-- -----------------------------------------------------------------------------
-- Rating. Both apps rate you, because that is the joke and also the progression.
-- Rating gates the better-paying work.
-- -----------------------------------------------------------------------------
Config.Rating = {
    start = 4.2,
    min = 1.0,
    max = 5.0,
    -- How much a single job moves the rating. Small, so it is a trend not a coin
    -- flip, but large enough that a clean run out of the starting hole is short:
    -- start + 3 good gigs clears the threshold.
    step = 0.1,
    -- Below this, only the worst-paying work comes your way. This is the quiet
    -- punishment -- no banner, the good fares just stop showing up.
    goodThreshold = 4.5,
    -- How many offers you can see on a BOARD app while below the threshold.
    lowOfferCount = 2,
    -- Dispatch-only apps cannot trim a list, so they lean the fare-type roll
    -- towards the short, cheap end instead. Same punishment, same silence.
    lowShortBias = 0.85,
    -- The loud "you are getting deactivated" banner is a different, much lower
    -- bar than goodThreshold. A real app would not send that message at 4.4 --
    -- that is a full point above goodThreshold already. It is the empty threat
    -- gig apps make: it only shows up once you are actually at the floor.
    warnThreshold = 1.0,
}

-- -----------------------------------------------------------------------------
-- What a fare pays.
-- -----------------------------------------------------------------------------
-- Two lengths, priced as two products, the way a rideshare actually is: a hop
-- across downtown and a run out to Sandy Shores are not the same job and should
-- not sit in the same price band. The bands OVERLAP on purpose -- a long fare
-- can pay less than a good short one, so "hold out for a long one" is not
-- automatically the right play.
--
-- Calibrated against the rest of the server: um_truckerjob pays ~100-120 a drop
-- before a 15% tax, um_taxijob runs 125 a mile (~78/km). Gig work sits at or
-- under that, because it is meant to read as the bottom of the ladder.
--
-- NOTE: distance here is straight-line between the two points, not road length.
-- Real driving is usually 30-40% further, so the effective rate per kilometre
-- actually driven is lower than these numbers suggest.
Config.Fares = {
    short = {
        id = 'short',
        label = 'Short hop',
        minKm = 0.4,
        maxKm = 2.6,
        minPay = 25,
        maxPay = 100,
        weight = 60,
    },
    long = {
        id = 'long',
        label = 'Long haul',
        minKm = 2.6,
        maxKm = 14.0,
        minPay = 50,
        maxPay = 200,
        weight = 40,
    },
    -- Random wobble either side of the straight distance-to-price line, so two
    -- fares over the same ground are not the same number twice.
    jitter = 0.08,
    -- Fares are quoted in fives. A $73 fare reads as arithmetic; $75 reads as
    -- a price.
    roundTo = 5,
    -- How many pairs of addresses to try before giving up on hitting the band
    -- exactly and taking the closest miss.
    attempts = 60,
    -- Dispatch tries to find you a pickup within this many metres before it
    -- widens out. A request from the other end of the map is the other thing
    -- that never happens in a real app.
    nearDriverMetres = 2200.0,
}

-- Snarf is still paid the old flat way -- it is a delivery, not a fare, and
-- the two bands above are a rideshare idea.
Config.Pay = {
    base = 70,
    perKm = 70,
    minPay = 120,
    -- Tip is scaled by how well you did: time taken and, for Ryde Me, how you
    -- drove. A good tip is a decent bonus, not a second fare.
    maxTipMultiplier = 0.25,
    -- Lose this fraction for arriving late.
    latePenalty = 0.35,
}

-- Time allowed, in seconds, per kilometre of route. Generous: this is a lift,
-- not a time trial, and a punishing clock makes people drive like maniacs.
Config.SecondsPerKm = 150

-- -----------------------------------------------------------------------------
-- What you are driving changes what the fare is worth.
-- -----------------------------------------------------------------------------
-- The multiplier is applied when the passenger gets in, off the car they
-- actually got into -- not off whatever you were sitting in when the request
-- came through. Pulling up in a Zentorno is worth more than pulling up in a
-- Rhapsody, and pulling up in a flatbed is worth almost nothing, because that
-- is what the rider is paying for.
--
-- Keys are GTA's own vehicle class ids (GET_VEHICLE_CLASS). The client reports
-- the class and the server looks the multiplier up here, so a modified client
-- cannot invent its own rate.
Config.VehicleClasses = {
    [0]  = { label = 'Compact',        mult = 0.85 },
    [1]  = { label = 'Sedan',          mult = 1.00 },
    [2]  = { label = 'SUV',            mult = 1.15 },
    [3]  = { label = 'Coupe',          mult = 1.00 },
    [4]  = { label = 'Muscle',         mult = 0.95 },
    [5]  = { label = 'Sports Classic', mult = 1.25 },
    [6]  = { label = 'Sports',         mult = 1.20 },
    [7]  = { label = 'Super',          mult = 1.50 },
    [8]  = { label = 'Motorcycle',     mult = 0.65 },
    [9]  = { label = 'Off-road',       mult = 0.90 },
    [10] = { label = 'Industrial',     mult = 0.50 },
    [11] = { label = 'Utility',        mult = 0.50 },
    [12] = { label = 'Van',            mult = 1.05 },
    [13] = { label = 'Bicycle',        mult = 0.40 },
    [14] = { label = 'Boat',           mult = 1.10 },
    [15] = { label = 'Helicopter',     mult = 1.60 },
    [16] = { label = 'Plane',          mult = 1.60 },
    [17] = { label = 'Service',        mult = 0.80 },
    [18] = { label = 'Emergency',      mult = 0.70 },
    [19] = { label = 'Military',       mult = 0.70 },
    [20] = { label = 'Commercial',     mult = 0.55 },
    [21] = { label = 'Train',          mult = 0.50 },
}
Config.VehicleClassDefault = { label = 'Vehicle', mult = 1.00 }

-- The tier name the app shows the rider, picked off the multiplier. Purely
-- cosmetic, and deliberately written the way a rideshare writes it.
Config.VehicleTiers = {
    { atLeast = 1.35, label = 'rydeme LUX' },
    { atLeast = 1.15, label = 'rydeme COMFORT' },
    { atLeast = 0.90, label = 'rydeme STANDARD' },
    { atLeast = 0.00, label = 'rydeme ECONOMY' },
}

-- -----------------------------------------------------------------------------
-- Snarf: where food comes from. These match real shop locations already on
-- the server, so a delivery starts somewhere that actually exists.
-- -----------------------------------------------------------------------------
-- `shopPed = true` means ox_inventory already stands a targetable shop ped on
-- this exact coordinate, so we hang our option on a zone over them instead of
-- spawning a second person inside the first. Everywhere else we bring our own.
-- Checked against ox_inventory/data/shops.lua: only Burger Shot qualifies today
-- -- Taco Farmer's shop is a zone with no ped, and the rest have nothing.
--
-- NOTE: Diner and Pops Diner are 4 metres apart and both unsurveyed. They are
-- almost certainly the same building entered twice; "Pops" in ox_inventory is
-- Pops Pills, a pharmacy, which is not this.
Config.Restaurants = {
    {
        id = 'burgershot', label = 'Burger Shot',
        coords = vec3(-1193.57, -894.39, 12.89), verified = true,
        shopPed = true, heading = 346.8,
    },
    {
        id = 'tacofarmer', label = 'Taco Farmer',
        coords = vec3(11.21, -1605.49, 28.98), verified = true,
        ped = `s_m_m_linecook`, heading = 0.0,
    },
    {
        id = 'chihuahua', label = 'Chihuahua Hotdogs',
        coords = vec3(29.4, -1598.5, 29.6), verified = false,
        ped = `s_m_m_linecook`, heading = 0.0,
    },
    {
        id = 'diner', label = 'Diner',
        coords = vec3(1587.6, 6455.3, 25.0), verified = false,
        ped = `s_m_y_dealer_01`, heading = 0.0,
    },
    {
        id = 'popsdiner', label = 'Pops Diner',
        coords = vec3(1591.0, 6453.0, 25.0), verified = false,
        ped = `s_m_y_dealer_01`, heading = 0.0,
    },
}

-- The person who takes the delivery at the far end. Spawned at the drop-off, so
-- there is someone to hand the bag to rather than a circle on the pavement --
-- and a ped lands on the ground even where the address coordinate is a little
-- off, which most of them are.
Config.Customers = {
    peds = {
        `a_f_y_hipster_02`, `a_m_y_business_03`, `a_f_m_business_02`,
        `a_m_m_eastsa_02`, `a_f_y_soucent_02`, `a_m_y_stwhi_01`,
    },
    -- How far ox_target will let you reach them from.
    targetDistance = 2.5,
}

-- -----------------------------------------------------------------------------
-- Pickup and drop-off addresses, shared by both apps.
-- -----------------------------------------------------------------------------
-- SURVEYED. Every coordinate below is a real vehicle node out of the game's own
-- road graph, looked up with `_tools/gtav_reference` (`python query.py road x y
-- z`) rather than eyeballed off the map -- so a passenger always waits at the
-- kerb of a street a car can actually get to, and a drop-off circle is never in
-- the middle of a building. `heading` is the node's own road heading, which is
-- what a ped standing there should be facing along.
--
-- `region` is what makes short fares possible at all: a short hop is only ever
-- offered between two addresses in the same region, so the app never proposes
-- a "2 km" fare from Paleto Bay to Sandy Shores by accident of the map's
-- geography. The city list is deliberately dense for the same reason.
Config.Addresses = {
    -- ---- Los Santos ---------------------------------------------------------
    { label = 'Legion Square',    region = 'city',   coords = vec3(233.00, -848.75, 29.03),   heading = 69.6 },
    { label = 'Pillbox Hill',     region = 'city',   coords = vec3(-2.25, -635.00, 34.72),    heading = 342.2 },
    { label = 'Textile City',     region = 'city',   coords = vec3(405.75, -724.00, 28.31),   heading = 180.0 },
    { label = 'Downtown',         region = 'city',   coords = vec3(114.00, -545.50, 42.22),   heading = 342.6 },
    { label = 'Alta',             region = 'city',   coords = vec3(167.00, -407.75, 40.22),   heading = 336.4 },
    { label = 'Burton',           region = 'city',   coords = vec3(-421.75, -211.25, 35.25),  heading = 31.0 },
    { label = 'Hawick',           region = 'city',   coords = vec3(293.00, -49.50, 70.00),    heading = 339.0 },
    { label = 'Mirror Park',      region = 'city',   coords = vec3(1123.50, -513.75, 63.06),  heading = 95.9 },
    { label = 'Murrieta Heights', region = 'city',   coords = vec3(971.00, -927.25, 41.69),   heading = 21.0 },
    { label = 'Strawberry',       region = 'city',   coords = vec3(54.25, -1221.25, 28.31),   heading = 358.8 },
    { label = 'Davis',            region = 'city',   coords = vec3(238.50, -1522.00, 28.03),  heading = 159.8 },
    { label = 'Rancho',           region = 'city',   coords = vec3(432.50, -1637.00, 28.19),  heading = 4.8 },
    { label = 'La Mesa',          region = 'city',   coords = vec3(827.75, -1272.50, 25.25),  heading = 0.0 },
    { label = 'Grove Street',     region = 'city',   coords = vec3(-25.00, -1438.50, 29.94),  heading = 180.0 },
    { label = 'Little Seoul',     region = 'city',   coords = vec3(-645.75, -855.75, 23.62),  heading = 180.0 },
    { label = 'Cypress Flats',    region = 'city',   coords = vec3(750.00, -2216.00, 28.31),  heading = 355.1 },
    { label = 'Vespucci Beach',   region = 'city',   coords = vec3(-1227.25, -1507.00, 3.28), heading = 34.4 },
    { label = 'Del Perro Pier',   region = 'city',   coords = vec3(-1665.50, -1032.25, 12.09), heading = 319.4 },
    { label = 'Morningwood',      region = 'city',   coords = vec3(-1431.75, -332.75, 43.41), heading = 39.5 },
    { label = 'Rockford Hills',   region = 'city',   coords = vec3(-971.00, 146.25, 59.34),   heading = 40.9 },
    { label = 'Richman',          region = 'city',   coords = vec3(-1548.25, -33.50, 56.81),  heading = 95.2 },
    { label = 'Vinewood Hills',   region = 'city',   coords = vec3(-171.50, 511.75, 136.31),  heading = 103.2 },
    { label = 'Banning',          region = 'city',   coords = vec3(106.50, -2231.50, 4.94),   heading = 270.0 },
    { label = 'LS International', region = 'city',   coords = vec3(-682.50, -2377.50, 12.97), heading = 138.9 },
    -- ---- Blaine County ------------------------------------------------------
    { label = 'Sandy Shores',     region = 'county', coords = vec3(1716.75, 3732.75, 32.78),  heading = 299.7 },
    { label = 'Grapeseed',        region = 'county', coords = vec3(1991.50, 4933.50, 41.47),  heading = 131.0 },
    { label = 'Harmony',          region = 'county', coords = vec3(428.25, 2636.50, 42.94),   heading = 10.0 },
    { label = 'Chumash',          region = 'county', coords = vec3(-3105.50, 1195.00, 19.31), heading = 355.2 },
    { label = 'Paleto Bay',       region = 'county', coords = vec3(-116.75, 6453.25, 30.38),  heading = 43.0 },
}

-- -----------------------------------------------------------------------------
-- Snarf order flavour. Picked at random so two deliveries to the same street
-- still read differently.
-- -----------------------------------------------------------------------------
Config.Orders = {
    'a double cheeseburger, no pickles',
    'three slushies and one straw',
    'the whole left side of the menu',
    'one taco. Just one.',
    'a milkshake, extra thick',
    'cheese fries and a lot of napkins',
    'something called "the bleeder"',
    'six coffees for the office',
}

-- Customer notes. Flavour, but a couple of them change the job -- see client.lua.
Config.CustomerNotes = {
    { text = 'Leave it at the door. Do not knock.', effect = false },
    { text = 'Please hurry, I am starving.', effect = 'rush' },
    { text = 'Ring twice. The dog is friendly.', effect = false },
    { text = 'I am on the balcony, just shout.', effect = false },
    { text = 'If it is cold I am rating you one star.', effect = 'rush' },
    { text = 'No rush at all, take your time.', effect = 'relaxed' },
}

-- -----------------------------------------------------------------------------
-- Ryde Me passengers. `mood` changes what they say and how they rate you.
-- -----------------------------------------------------------------------------
Config.Passengers = {
    peds = {
        `a_f_y_business_02`, `a_m_y_business_01`, `a_f_y_hipster_01`,
        `a_m_y_hipster_02`, `a_f_m_business_02`, `a_m_m_tourist_01`,
        `a_f_y_tourist_02`, `a_m_y_latino_01`,
    },
    names = {
        'Marcus', 'Dana', 'Teddy', 'Priya', 'Wes', 'Nina', 'Karl', 'Rosa',
        'Yusuf', 'Bree', 'Otto', 'Simone', 'Hal', 'Marguerite', 'Dre', 'Constance',
        'Vic', 'Elena', 'Ruben', 'Joss',
    },
    moods = {
        { id = 'chatty',   label = 'Chatty',   line = 'So what do you do when you are not driving?' },
        { id = 'quiet',    label = 'Quiet',    line = '...' },
        { id = 'late',     label = 'In a hurry', line = 'I am so late. Please tell me you know a shortcut.', rush = true },
        { id = 'nervous',  label = 'Nervous',  line = 'Could you slow down a bit? Please?', hatesSpeed = true },
        { id = 'drunk',    label = 'Worse for wear', line = 'You are my best friend. Did you know that?' },
        { id = 'business', label = 'On a call', line = 'Do not mind me, I have to take this.' },
        { id = 'tourist',  label = 'Sightseeing', line = 'Is this the bit that is in all the films?' },
    },
}

-- Driving quality, for Ryde Me. A passenger notices.
Config.Driving = {
    -- Above this speed (m/s) counts as fast. ~28 m/s is about 100 km/h.
    fastSpeed = 28.0,
    -- Rating hit per collision while carrying someone, counted at most 3 times.
    -- Kept near one step so a scrappy ride is worth less, not ruinous.
    crashPenalty = 0.1,
    -- Rating hit for a nervous passenger if you spend a lot of the trip fast.
    speedPenalty = 0.08,
    -- A collision only counts as one if you were actually moving and actually
    -- lost speed (m/s). Curbs, kerb-scrapes and resting against a wall are not
    -- crashes, and the old check counted all of them.
    crashMinSpeed = 9.0,
    crashSpeedDrop = 6.0,
    -- The line the passenger comes out with when you clout something. Said at
    -- most once a ride, because a running commentary is worse than silence.
    crashLines = {
        'What was that?!', 'Careful!', 'Oh my God.', 'Watch it!',
        'You are going to get us both killed.',
    },
}

-- -----------------------------------------------------------------------------
-- Posted speed limits, Ryde Me only. The point is that the fastest route is not
-- automatically the best-paid one: the clock still rewards getting there, but
-- flooring it past every sign quietly costs you stars, so the optimal play is
-- brisk-but-legal rather than a straight sprint.
--
-- The limit itself is read from the standalone `speedlimits` resource via its
-- getSpeedLimitAtCoords export, so the numbers are never copied into this
-- resource and cannot drift out of sync with the signs the player can see.
-- Streets with no posted limit are treated as unposted, not as no-limit.
-- -----------------------------------------------------------------------------
Config.SpeedLimit = {
    enabled = true,
    -- Draw the speedometer while a passenger is aboard.
    showMeter = true,
    -- MPH over the posted limit before it starts counting against you. Wide
    -- enough that ordinary traffic-flow driving and brief overtakes are free.
    graceMph = 8,
    -- Rating lost per second spent over the limit, and the most a single ride
    -- can lose this way. Deliberately small per second: this should feel like
    -- a slow drip for sustained speeding, not a cliff for one burst.
    penaltyPerSecond = 0.004,
    maxPenalty = 0.25,
}

-- -----------------------------------------------------------------------------
-- "Just go, I will cover the ticket."
-- -----------------------------------------------------------------------------
-- Part-way through a ride the passenger can tell you to stop worrying about the
-- limit. When they do, the speedometer comes OFF the screen and the speeding
-- rule switches off for the rest of that ride -- the meter is only there to
-- make a penalty legible, and once there is no penalty there is nothing to
-- make legible. It is also the one moment in the loop that gives you explicit
-- permission to drive the way the game wants you to, which is the whole reason
-- it exists.
Config.SpeedRequest = {
    enabled = true,
    -- Earliest and latest, in seconds into the ride, that they might say it.
    minDelay = 20,
    maxDelay = 80,
    -- Base odds any given rider asks, and the much better odds a rider who is
    -- already late asks. A nervous rider never does.
    chance = 0.30,
    rushChance = 0.85,
    -- Get them there inside this fraction of the time allowance after being
    -- told to hurry, and they pay for it.
    bonusUnderFraction = 0.6,
    bonusMultiplier = 0.20,
    lines = {
        'Forget the limit, I will cover the ticket.',
        'Can you step on it? I will make it worth your while.',
        'Nobody is watching. Put your foot down.',
        'Speed limits are a suggestion. Go.',
        'I am paying by the minute here. Move.',
    },
}

-- -----------------------------------------------------------------------------
-- Heat. A rider did not order a getaway car.
-- -----------------------------------------------------------------------------
-- Pick up a wanted level with somebody in the back and the ride is over as far
-- as they are concerned: zero stars, no tip, and a real dent in your standing.
-- This is the one rating outcome that is not a matter of degree -- it does not
-- scale with how many stars the police gave you, because from the back seat
-- there is no difference between one and five.
Config.Wanted = {
    enabled = true,
    stars = 0,
    ratingPenalty = 0.5,
    lines = {
        'Are those sirens for us? Are they for US?',
        'What did you DO?',
        'Oh no. No no no. Let me out.',
        'I am not going to prison for a $40 ride.',
    },
    -- What they write on the profile afterwards. Its own pool, because none of
    -- the ordinary bad-ride comments cover this.
    comments = {
        'Police chase. Zero stars. Reported.',
        'Driver was wanted by the LSPD. With me in the car.',
        'I have contacted the app about this.',
        'Do not let this person drive.',
    },
}

-- -----------------------------------------------------------------------------
-- The ride can just end.
-- -----------------------------------------------------------------------------
-- Run the tank dry or write the car off with a passenger aboard and the fare
-- stops there: no pay, no tip, and a one-star ride for the trouble of being
-- left at the roadside. Not a punishment so much as a consequence -- it is the
-- reason to look at the fuel gauge before accepting a run to Paleto.
Config.Abort = {
    enabled = true,
    -- Tank percentage at or below which the car counts as dry. LegacyFuel and
    -- the engine both store this as 0-100 on the vehicle itself, so this reads
    -- the same number whichever one is driving it.
    fuelBelow = 0.8,
    -- Engine health at or below which the car counts as dead. GTA's scale is
    -- -4000..1000 and the engine cuts out around zero.
    engineHealthBelow = 1.0,
    -- Rating lost, and the stars the stranded rider leaves.
    ratingPenalty = 0.15,
    stars = 1,
    comments = {
        'Car died halfway. Left me on the hard shoulder.',
        'Ran out of fuel. With me in it.',
        'Broke down. Had to walk the rest.',
        'Never made it. Do not know what to say.',
    },
}

-- -----------------------------------------------------------------------------
-- Driver Profile. Every finished ride writes one entry here: who, how many
-- stars they left THIS ride, what they said, what it paid. That is what the
-- profile screen is actually showing -- not the running average by itself,
-- but where it came from.
-- -----------------------------------------------------------------------------
Config.History = {
    -- Rides kept per player. This is a phone screen, not a ledger -- old rides
    -- roll off rather than growing the metadata forever.
    limit = 15,
}

-- -----------------------------------------------------------------------------
-- Feedback.
-- -----------------------------------------------------------------------------
-- A rating that is a pure function of your driving is a score, not a review.
-- Real ones are noisy: the same ride gets five stars from one person and three
-- from the next, and most people do not write anything at all. So the star
-- count starts from how the ride actually went, then gets pushed around by who
-- happened to be in the car, and the comment is a coin flip on top of that.
--
-- None of this touches your standing -- `ratingDelta` on the server is still
-- computed straight off what you did. This is what shows up on the profile.
Config.Feedback = {
    -- Who the rider is, as a reviewer. Rolled per ride.
    reviewers = {
        { id = 'harsh',    bias = -1, weight = 15 },
        { id = 'fair',     bias = 0,  weight = 55 },
        { id = 'generous', bias = 1,  weight = 30 },
    },
    -- Odds this rider says nothing at all, by the stars they left. Most people
    -- who had a perfectly fine time do not write a review, which is why the
    -- middle of this table is the quietest part of it.
    silence = {
        [5] = 0.35,
        [4] = 0.55,
        [3] = 0.45,
        [2] = 0.20,
        [1] = 0.10,
        [0] = 0.05,
    },
    great = {
        'Smooth ride, thanks!', 'Great music taste.', 'Would ride with you again.',
        'Fastest driver I have had all week.', 'Genuinely pleasant trip.',
        'Knew exactly where they were going.', 'Clean car, good driver, no notes.',
        'Actually made my morning better.', 'Five stars, obviously.',
        'Did not say a word the whole way. Perfect.',
        'Took the back roads and saved me ten minutes.',
        'If I could give six I would.',
    },
    good = {
        'No complaints.', 'Got me there, no fuss.', 'Solid ride.',
        'Pleasant enough.', 'Fine. Would ride again.', 'Did the job.',
        'Nothing to report.', 'Bit of a long way round but fine.',
        'Good driver. Terrible radio station.',
    },
    mixed = {
        'A little rough getting here.', 'Ride was fine, I guess.',
        'Took a couple of odd turns.', 'Got there eventually.',
        'Not the smoothest.', 'Car smelled of something.',
        'Missed the turning twice.', 'I have had worse. Not many.',
    },
    bad = {
        'Way too aggressive.', 'I feared for my life.', 'Never again.',
        'Worst ride I have had on this app.', 'Drove like the car was stolen.',
        'Hit something. Twice.', 'I am still shaking.',
        'Genuinely dangerous.', 'Please do not let this person drive.',
    },
}

-- -----------------------------------------------------------------------------
-- Rider mode. The other side of the app.
-- -----------------------------------------------------------------------------
-- Ryde Me has two halves and only one of them was ever built: you could drive,
-- but nobody could be driven. This is the half that makes the app a service
-- rather than a job board -- a player opens it, picks a destination, and the
-- request goes out to whoever is online and driving. It is also the only fare
-- in this resource where the money comes out of somebody's pocket rather than
-- out of the air.
Config.RiderMode = {
    enabled = true,
    -- What a player-requested ride costs the RIDER. Priced clearly above the
    -- NPC bands below (see Config.RiderMode.npc) -- a real driver is a real
    -- person's time, and the price has to say so, not just the description.
    base = 38,
    perKm = 72,
    minFare = 25,
    maxFare = 250,
    -- The platform's cut of a player ride. The driver is paid the rest. This
    -- is the joke the whole app is built on, so it is visible in both UIs:
    -- the rider sees what they pay, the driver sees what they get.
    platformCut = 0.25,
    -- Seconds a request waits for a driver before it gives up and refunds.
    requestLifetime = 180,
    -- The rider's fare is taken when they request and refunded if nothing
    -- comes of it, the same hold a real app puts on your card.
    holdFunds = true,
    -- If the ride falls apart after a driver accepted -- rider cancels, rider
    -- disconnects -- the driver keeps this share as a cancellation fee.
    cancelFee = 0.5,
    -- How often the driver's route is re-pointed at the rider while they are
    -- still walking around waiting. Seconds.
    trackInterval = 4,
    -- How close the driver has to be before the rider can climb in.
    pickupRadius = 25.0,
    -- Custom destinations dropped on the Ride tab's map (see the Leaflet
    -- picker in ui/app.js) skip Config.Addresses entirely and price off the
    -- straight-line distance to wherever was tapped, same formula either way.
    customDestLabel = 'Custom pin',
}

-- -----------------------------------------------------------------------------
-- NPC drivers.
-- -----------------------------------------------------------------------------
-- The budget option next to a real player: cheaper, because nobody's actual
-- time is being spent, and instant, because there is no dispatch clock to run
-- against a driver who is not there. Bought, not booked -- accepting spawns
-- the car immediately rather than waiting on anyone to answer a phone.
--
-- Entirely client-side theatre: the car and its driver exist only on the
-- requesting player's machine, the same way a Ryde Me NPC passenger already
-- does not exist for anyone else. Nothing here touches `active`/`rideRequests`
-- -- the server takes the fare and fires one event; the client does the rest
-- and never reports back, so there is nothing to keep in sync.
Config.RiderMode.npc = {
    enabled = true,
    -- Independent bands, not a multiplier of the real-driver ones above --
    -- easier to tune on its own and the numbers should not accidentally track
    -- each other if one gets rebalanced later.
    base = 18,
    perKm = 40,
    minFare = 15,
    maxFare = 150,
    -- Ordinary street cars. Nothing branded, nothing rare -- this is meant to
    -- read as "whoever was free", not as a fleet vehicle.
    vehicles = {
        `asea`, `premier`, `stanier`, `tailgater`, `washington`, `intruder`,
    },
    -- How far out the car spawns and starts driving in. Far enough that it is
    -- not conjured out of thin air in front of you, close enough it does not
    -- take a full minute to arrive.
    spawnDistance = 60.0,
    approachSpeed = 14.0,   -- m/s driving to collect you
    dropoffSpeed = 18.0,    -- m/s driving to your destination
    driveStyle = 786603,    -- normal traffic-obeying driving style
    -- What the driver switches to once told to speed up. Avoids vehicles,
    -- peds, and objects but drives through speed zones and red lights --
    -- verified against https://vespura.com/fivem/drivingstyle/ (the same
    -- source [night]/night_ers's npcbackup-config.lua cites for its own
    -- "runs red lights" style) rather than guessed, since driveStyle is an
    -- opaque bitmask and a wrong value silently does nothing.
    rushedDriveStyle = 2900796,
    pickupRadius = 6.0,     -- how close it has to get before you are told to get in
    arriveRadius = 8.0,     -- how close to the destination counts as arrived
    -- Give up waiting on the pathing at this point either way -- GTA's vehicle
    -- AI occasionally gets a car stuck on scenery, and a fare that can never
    -- end is worse than one that ends early having still gotten you most of
    -- the way there.
    timeoutSeconds = 100,
    -- How long one drive-to-you attempt gets before it is re-issued. A car
    -- that reports its task "finished" (or just times out) without actually
    -- reaching pickupRadius gets re-routed within the overall timeoutSeconds
    -- budget, rather than the ride quietly boarding you into a car that is
    -- still blocks away.
    attemptSeconds = 35,
}

-- -----------------------------------------------------------------------------
-- Marking the spot, and drawing the route.
-- -----------------------------------------------------------------------------
Config.RydeMe = {
    dropoffRadius = 9.0,
    markerScale = vec3(3.0, 3.0, 0.8),
    parkedSpeed = 0.5,
    parkedHold = 1200,
}

-- -----------------------------------------------------------------------------
-- Navigation.
-- -----------------------------------------------------------------------------
-- This resource does NOT draw its own route line any more, and it deliberately
-- does not grow an in-app map the way qbx_geocaching has one. A rideshare's
-- directions belong in the same place every other set of directions on this
-- server lives: vice_hud's turn-by-turn panel above the minimap.
--
-- vice_hud drives that panel off the player's own waypoint (blip type 8) and
-- the engine's own GPS route -- there is no export to point it somewhere, and
-- it does not need one. Setting the waypoint IS the integration: the game
-- pathfinds to it, the minimap draws the line, and vice_hud reads the next
-- manoeuvre off that same route and puts "Turn Left, 250 ft" on screen. So a
-- gig sets the waypoint and gets real turn-by-turn for free, identical to the
-- one the player gets when they drop a pin themselves.
Config.Nav = {
    -- Set the player's waypoint to the current stop. Turning this off falls
    -- back to a plain destination blip with no directions at all.
    setWaypoint = true,
    -- Put the waypoint back where the player had it when the gig ends. Off by
    -- default: silently restoring a pin they set an hour ago is more confusing
    -- than just clearing it.
    restorePrevious = false,
}

Config.Marker = {
    -- Start drawing this close, in metres. The gig loop already runs every
    -- frame inside this range, so it costs nothing extra.
    drawDistance = 25.0,
    type = 1,               -- thin cylinder
    scale = vec3(1.6, 1.6, 0.8),
    alpha = 110,
    -- A soft radius on the map, so the destination is findable before you can
    -- see the marker itself.
    radius = 22.0,
    snarf  = { r = 229, g = 57,  b = 127 },   -- matches --accent in snarf.html
    rydeme = { r = 255, g = 45,  b = 149 },   -- matches --accent-text in rydeme.html (Ryde Me neon pink)
}

-- -----------------------------------------------------------------------------
-- Going on duty.
-- -----------------------------------------------------------------------------
Config.Duty = {
    -- Seconds between "work available" pings to the same person for the same
    -- BOARD app. Dispatch apps do not use this -- their pacing is Config.Dispatch.
    notifyCooldown = 240,
    -- Duty is per app: clocking on for Snarf should not ping you about fares.
    -- Nobody on a job gets pinged, on duty or not.
}

-- -----------------------------------------------------------------------------
-- Dispatch pacing.
-- -----------------------------------------------------------------------------
-- The old numbers pushed a fare at an idle driver every 20 seconds with a 30
-- second cooldown, which meant that going online produced a more or less
-- continuous stream of offers -- a queue with extra steps, and the fastest way
-- to make a phone notification meaningless. Real dispatch is bursty and has
-- gaps in it: you go online, nothing happens for a bit, then a request lands.
--
-- So the gap between one driver's requests is RANDOM inside a range, rolled
-- fresh each time, rather than a fixed cooldown. The loop itself ticks often;
-- the per-driver gap is what does the pacing.
Config.Dispatch = {
    -- How often the server looks at who is due a request. Cheap; the gap below
    -- is what actually decides.
    checkInterval = 10,
    -- Seconds to accept or decline before the request is pulled back.
    responseWindow = 25,
    -- Quiet period after a request has been resolved, either way. Rolled
    -- randomly in this range each time, so the app never has a rhythm you can
    -- count on.
    minGap = 60,
    maxGap = 150,
    -- The first request after going online. Shorter than the steady-state gap
    -- -- clocking on and then waiting two minutes with a blank screen is not
    -- atmospheric, it is just a blank screen -- but never instant, because
    -- instant is what made this feel scripted.
    firstGapMin = 12,
    firstGapMax = 40,
    -- A player-requested ride ignores the gap entirely. Somebody is actually
    -- stood there waiting.
    playerRideIgnoresGap = true,
}

Config.Debug = true
