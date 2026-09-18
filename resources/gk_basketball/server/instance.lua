--[[
    Match instancing.

    A match runs in its own routing bucket: an isolated copy of the world containing only
    the people playing. No traffic crossing the court, no pedestrians walking through a
    drive to the rim.

    Buckets are allocated per court rather than per match, and derived from the court id
    rather than counted upward, so a court keeps the same bucket across a restart and
    nothing accumulates over uptime.

    BUCKET RANGE — 41000-41499

    Chosen against everything else on this server that allocates buckets, because two
    resources sharing an id means two unrelated instances sharing a world:

        em_toolkit       500-900
        shell_creator    5000 + server id
        sk_streetkings   20000 upward, one per race lobby, never reset
        gk_tennis        40000-40499
        gk_basketball    41000-41499   <- here
        gk_soccer        42000-42499
        um_nightclubs    61000-64999

    LEAKS

    A player left in a bucket is invisible to everyone forever. Unlike tennis, a finished
    match here drops back to a lobby with its players still on the court, so the only ways
    out are leaving, wandering off, being dropped, and this resource stopping. All four
    are covered.
]]

local BUCKET_BASE  = 41000
local BUCKET_RANGE = 500

local buckets = {}    -- [courtId] = bucket id
local inside  = {}    -- [src] = bucket id, for anyone we have moved

--- Applies the instance's world settings. Idempotent, so it is simply reapplied whenever
--- a bucket is handed out rather than tracked.
local function configure(bucket)
    -- The reason to instance a court at all: no ambient population inside it. Server
    -- side and permanent, rather than every client calling the ...ThisFrame density
    -- natives every frame.
    SetRoutingBucketPopulationEnabled(bucket, Config.Instance.population)

    --[[
        Entity lockdown stays off by default, and it is worth saying why, because §14 of
        the notes recommends 'strict' and it cannot be used here yet.

            strict    no entities can be created by clients at all
            relaxed   script-owned entities created by clients are blocked
            inactive  clients can create anything

        The AI's ped is a script-owned networked entity created by its driver's client,
        so 'strict' and 'relaxed' both block it and the NPC simply never appears. The
        ball is no longer in that category — it is a local object on each client now, and
        local objects are not networked entities, so lockdown cannot see them.

        With Config.AI.enabled = false, 'strict' is safe and worth setting. With the AI
        on, leave this alone.
    ]]
    SetRoutingBucketEntityLockdownMode(bucket, Config.Instance.lockdown)
end

--- The bucket for a court, allocating one on first use.
---
--- Derived from the court id so it is stable, with linear probing so two courts whose
--- ids happen to hash to the same slot still get a bucket each.
function BB.bucketFor(courtId)
    if buckets[courtId] then return buckets[courtId] end

    local slot = joaat(courtId) % BUCKET_RANGE
    local taken = {}

    for _, bucket in pairs(buckets) do taken[bucket] = true end

    local guard = 0

    while taken[BUCKET_BASE + slot] and guard < BUCKET_RANGE do
        slot = (slot + 1) % BUCKET_RANGE
        guard = guard + 1
    end

    buckets[courtId] = BUCKET_BASE + slot
    configure(buckets[courtId])

    return buckets[courtId]
end

--- Moves a player into a court's instance.
function BB.enterInstance(src, courtId)
    if not Config.Instance.enabled then return end

    local bucket = BB.bucketFor(courtId)

    inside[src] = bucket
    SetPlayerRoutingBucket(src, bucket)
end

--- Puts a player back in the main world. Safe to call for someone who was never moved,
--- which is what makes it safe to call from every exit path without checking first.
function BB.leaveInstance(src)
    if not inside[src] then return end

    inside[src] = nil
    SetPlayerRoutingBucket(src, 0)
end

--[[
    Stopping this resource must not strand anyone.

    Without this, a restart mid-match leaves everyone in a bucket that nothing is left to
    move them out of: they see each other and nobody else, and rejoining does not fix it
    because the resource that knew about the bucket is gone.
]]
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    for src in pairs(inside) do
        SetPlayerRoutingBucket(src, 0)
    end

    inside = {}
end)
