--[[ =========================================================================
     vice_hud — skills persistence
     -------------------------------------------------------------------------
     Stores each player's XP in qbx_core's player metadata, which already has a
     database behind it and already survives relogs and character switches. A
     second table for eight integers would be a migration, a schema and a backup
     concern in exchange for nothing.

     THE CLIENT IS NOT TRUSTED
     XP is tracked client-side because that is where the activity is observable —
     only the client can see that the player is sprinting. That means the save
     payload is a client-authored number, and a client-authored number that
     drives a gameplay stat is exactly the thing to be careful with.

     Rather than pretend otherwise, the server enforces the one property that
     actually matters: XP may only go UP, and only by a plausible amount for the
     time that has passed. A modified client cannot hand itself level 100; it
     can only earn at the rate an honest client could. That is a rate limit, not
     a proof, and it is worth being clear about which of the two this is.
     ====================================================================== --]]

local META_KEY = 'vice_skills'

--- The most a single skill may gain per second of connected time.
---
--- Derived from the fastest anything can legitimately be earned: sprinting at
--- roughly 7 m/s at 0.5 XP/m is 3.5 XP/s, and shots on target can spike higher
--- for short bursts. 25 leaves generous headroom for a burst of activity while
--- still making "level 100 in a minute" impossible.
local MAX_XP_PER_SECOND = 25

--- Last accepted save per player: { xp = {...}, at = os.time() }.
--- Cleared on drop, so a reconnect starts from what the database says.
local session = {}

local function metaGet(src)
    local ok, data = pcall(function()
        return exports.qbx_core:GetMetadata(src, META_KEY)
    end)
    if ok and type(data) == 'table' then return data end
    return nil
end

local function metaSet(src, data)
    local ok = pcall(function()
        exports.qbx_core:SetMetadata(src, META_KEY, data)
    end)
    return ok
end

local function sendTo(src, xp)
    TriggerClientEvent('vice_hud:skills:load', src, xp)
end

--- Seed a character that has never been seen before.
---
--- Distinguishing "no stored data" from "stored data that is all zeroes"
--- matters here: the first should be given the starting level, the second is
--- someone who has been reset on purpose and must not be silently handed levels
--- back. metaGet returning nil is the only reliable signal for the first.
local function seedFor(src)
    local raw = metaGet(src)
    if raw ~= nil then return Skills.normalise(raw), false end

    local level = math.max(0, math.min(Skills.MAX_LEVEL,
        math.floor(tonumber(Config.Skills and Config.Skills.startingLevel or 0) or 0)))
    if level <= 0 then return Skills.normalise(nil), false end

    local seeded = Skills.normalise(nil)
    local at = Skills.xpForLevel(level)
    for i = 1, #Skills.List do seeded[Skills.List[i].id] = at end
    return seeded, true
end

RegisterNetEvent('vice_hud:skills:request', function()
    local src = source
    local stored, wasSeeded = seedFor(src)
    if wasSeeded then
        -- Written immediately, so the starting level is a one-time gift rather
        -- than something handed out again on every reconnect.
        metaSet(src, stored)
        print(('^2[vice_hud]^7 seeded %s (%s) at skill level %d')
            :format(GetPlayerName(src) or '?', src,
                    (Skills.resolve(stored[Skills.List[1].id]))))
    end
    session[src] = { xp = stored, at = os.time() }
    sendTo(src, stored)
end)

RegisterNetEvent('vice_hud:skills:save', function(payload)
    local src = source
    local incoming = Skills.normalise(payload)

    -- No session means the client saved before it ever loaded. Trusting that
    -- would let a fresh connection overwrite stored progress with zeroes, which
    -- is the one way this system could destroy something.
    local prev = session[src]
    if not prev then
        local stored = seedFor(src)
        session[src] = { xp = stored, at = os.time() }
        sendTo(src, stored)
        return
    end

    local now = os.time()
    local elapsed = math.max(1, now - prev.at)
    local ceiling = elapsed * MAX_XP_PER_SECOND

    local accepted = {}
    local clamped = false
    for i = 1, #Skills.List do
        local id = Skills.List[i].id
        local was, want = prev.xp[id], incoming[id]

        if want < was then
            -- XP never goes down. A lower number is a stale client, a rollback,
            -- or someone trying something; in every case the stored value is
            -- the one worth keeping.
            accepted[id] = was
        elseif want - was > ceiling then
            accepted[id] = was + ceiling
            clamped = true
        else
            accepted[id] = want
        end
    end

    session[src] = { xp = accepted, at = now }
    metaSet(src, accepted)

    -- Tell the client what was actually stored, but only when it differs —
    -- otherwise every save round-trips a payload nobody needed.
    if clamped then
        sendTo(src, accepted)
        print(('^3[vice_hud]^7 clamped a skill save from %s (%s): gained more in %ds than is possible')
            :format(GetPlayerName(src) or '?', src, elapsed))
    end
end)

AddEventHandler('playerDropped', function()
    session[source] = nil
end)

--- Read another player's skills from server code.
exports('GetPlayerSkills', function(src)
    local s = session[src]
    if s then return s.xp end
    return Skills.normalise(metaGet(src))
end)

--- Grant XP authoritatively. For other server-side resources that want to
--- reward something the client cannot be trusted to claim for itself — a job
--- completed, a heist finished.
exports('AddPlayerSkillXp', function(src, id, amount)
    if not Skills.ById[id] then return false end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end

    local current = session[src] and session[src].xp or Skills.normalise(metaGet(src))
    current[id] = (current[id] or 0) + amount
    session[src] = { xp = current, at = os.time() }
    metaSet(src, current)
    sendTo(src, current)
    return true
end)

--- Admin: set or clear a player's skills. Gated on the same ace as /hudpublish,
--- because both write something every player then lives with.
local function mayAdmin(src)
    if src == 0 then return true end
    return IsPlayerAceAllowed(src, Config.PublishAce or 'vice_hud.publish')
        or IsPlayerAceAllowed(src, 'command')
end

RegisterCommand('setskill', function(src, args)
    if not mayAdmin(src) then return end
    local target, id, level = tonumber(args[1]), args[2], tonumber(args[3])
    if not target or not id or not level then
        print('^3[vice_hud]^7 usage: setskill <playerId> <skill|all> <level 0-100>')
        return
    end
    level = math.max(0, math.min(Skills.MAX_LEVEL, math.floor(level)))
    local current = session[target] and session[target].xp or Skills.normalise(metaGet(target))

    if id == 'all' then
        for i = 1, #Skills.List do current[Skills.List[i].id] = Skills.xpForLevel(level) end
    elseif Skills.ById[id] then
        current[id] = Skills.xpForLevel(level)
    else
        print(('^1[vice_hud]^7 unknown skill "%s"'):format(id))
        return
    end

    session[target] = { xp = current, at = os.time() }
    metaSet(target, current)
    sendTo(target, current)
    print(('^2[vice_hud]^7 %s set to level %d for %s'):format(id, level, GetPlayerName(target) or target))
end, true)
