-- ============================================================================
-- qbx_honor / server
-- Persistent per-character honor stat stored in qbx_core's player metadata
-- (metadata.honor). See README.md for the full export API.
-- ============================================================================

print('^2[qbx_honor]^7 server/main.lua loaded')

---Traces to the server console, and - when a player is named - mirrors the line
---into that player's F8 console. The server console and the client console are
---two different places, and needing to watch both at once to follow one action
---is what made this chain so hard to diagnose.
---@param src number? player to mirror to, or nil for server-console only
---@param fmt string
local function trace(src, fmt, ...)
    if not Config.Debug then return end

    local line = fmt:format(...)
    print('^5[qbx_honor]^7 ' .. line)

    if src then
        TriggerClientEvent('qbx_honor:client:trace', src, line)
    end
end

local honorCache = {}   -- [src] = last known honor value (avoids redundant GetPlayer calls on read-heavy callers)
local brokenCache = {}  -- [src] = last known metadata.honorBroken (same reasoning)
local hookState = {}    -- [src][hookName] = {last = GetGameTimer(), moved = total absolute honor moved this session}

local function clamp(value)
    if value < Config.MinHonor then return Config.MinHonor end
    if value > Config.MaxHonor then return Config.MaxHonor end
    return value
end

--- Returns the badge tier for a given honor value, or nil if it's in the neutral band.
---@param value number
---@return 'angel' | 'devil' | nil
local function getBadgeTier(value)
    if value >= Config.AngelThreshold then return 'angel' end
    if value <= Config.DevilThreshold then return 'devil' end
    return nil
end
exports('GetBadgeTier', getBadgeTier)

-- ============================================================================
-- Core API
-- ============================================================================

---Adjusts a player's honor by `delta` (positive to raise it, negative to lower it),
---clamps the result to [Config.MinHonor, Config.MaxHonor], persists it through
---qbx_core's metadata system, and notifies that player's client so the HUD can
---show the devil/angel toast.
---@param src number the player's server id
---@param delta number amount to add (may be negative)
---@param reason? string short human-readable cause, forwarded to the HUD
---@return number|nil newHonor the honor value after the adjustment, or nil if the player wasn't found
local function AdjustHonor(src, delta, reason)
    src = tonumber(src)
    delta = tonumber(delta)
    if not src or not delta or delta == 0 then return nil end

    local ok, player = pcall(function() return exports.qbx_core:GetPlayer(src) end)
    if not ok or not player then
        trace(src, 'AdjustHonor: NO qbx_core player for src %s (ok=%s)', tostring(src), tostring(ok))
        return nil
    end

    local current = player.PlayerData.metadata.honor or Config.DefaultHonor
    local newValue = clamp(current + delta)

    local wrote, err = pcall(function()
        exports.qbx_core:SetMetadata(src, 'honor', newValue)
    end)

    if not wrote then
        print(('^1[qbx_honor] SetMetadata failed for %s: %s^7'):format(tostring(src), tostring(err)))
        return nil
    end

    trace(src, 'AdjustHonor %s -> %s (%s)', tostring(current), tostring(newValue), tostring(reason))
    honorCache[src] = newValue

    -- The unrepairable floor. Latches once and is never unset by anything in
    -- this file — see Config's "Unrepairable floor" section for why. Checked
    -- against the ALREADY-cached flag so a character that hit the floor last
    -- session, then logged back in, doesn't re-trigger the write (and the
    -- trace line) on every subsequent honor change for no reason.
    local wasBroken = brokenCache[src]
    if wasBroken == nil then
        wasBroken = player.PlayerData.metadata.honorBroken == true
    end

    local nowBroken = wasBroken
    if not wasBroken and newValue <= Config.MinHonor then
        nowBroken = true
        brokenCache[src] = true

        local brokeWrote, brokeErr = pcall(function()
            exports.qbx_core:SetMetadata(src, 'honorBroken', true)
        end)
        if not brokeWrote then
            print(('^1[qbx_honor] SetMetadata(honorBroken) failed for %s: %s^7'):format(tostring(src), tostring(brokeErr)))
        else
            trace(src, 'honor hit the floor (%s) - permanently broken from here', tostring(Config.MinHonor))
        end
    end

    -- Always tell the client a hook fired, even when clamping left the value
    -- unchanged (e.g. already at the floor/ceiling) - the player still did the
    -- thing, and staying silent about that is what made "honor already at -100"
    -- indistinguishable from "the hook never fired" in the first place.
    TriggerClientEvent('qbx_honor:client:honorUpdated', src, newValue, current, reason, nowBroken)

    return newValue
end

exports('AdjustHonor', AdjustHonor)

---Raises a player's honor. `amount` is always treated as positive.
---@param src number
---@param amount number
---@return number|nil newHonor
local function AddHonor(src, amount, reason)
    amount = math.abs(tonumber(amount) or 0)
    return AdjustHonor(src, amount, reason)
end
exports('AddHonor', AddHonor)

---Lowers a player's honor. `amount` is always treated as positive (it is subtracted).
---@param src number
---@param amount number
---@return number|nil newHonor
local function RemoveHonor(src, amount, reason)
    amount = math.abs(tonumber(amount) or 0)
    return AdjustHonor(src, -amount, reason)
end
exports('RemoveHonor', RemoveHonor)

-- ============================================================================
-- Hook API
-- The only thing other resources should call. Everything about a hook - how
-- much it moves honor, how often it may fire, how much it may move in total -
-- lives in Config.Hooks, so a call site is a one-liner with no numbers in it.
-- ============================================================================

---Applies the named hook from Config.Hooks to a player, honouring that hook's
---cooldown and session cap.
---@param src number the player's server id
---@param hookName string a key of Config.Hooks
---@return number|nil newHonor honor after the change, or nil if nothing was applied
local function ApplyHook(src, hookName)
    src = tonumber(src)
    if not src then return nil end

    local hook = Config.Hooks[hookName]
    if not hook then
        print(('[qbx_honor] unknown hook "%s" - check Config.Hooks'):format(tostring(hookName)))
        return nil
    end

    local state = hookState[src]
    if not state then
        state = {}
        hookState[src] = state
    end

    local entry = state[hookName]
    if not entry then
        entry = { last = nil, moved = 0 }
        state[hookName] = entry
    end

    local now = GetGameTimer()

    if hook.cooldownMs and entry.last and (now - entry.last) < hook.cooldownMs then
        trace(src, 'hook "%s" ON COOLDOWN (%dms left)', hookName, hook.cooldownMs - (now - entry.last))
        return nil
    end

    local delta = hook.delta

    if hook.sessionCap then
        local remaining = hook.sessionCap - entry.moved
        if remaining <= 0 then
            trace(src, 'hook "%s" HIT ITS SESSION CAP', hookName)
            return nil
        end

        -- Clamp the last application so the cap lands exactly rather than overshooting.
        if math.abs(delta) > remaining then
            delta = delta > 0 and remaining or -remaining
        end
    end

    local newValue = AdjustHonor(src, delta, hook.label)
    if newValue == nil then return nil end

    entry.last = now
    entry.moved = entry.moved + math.abs(delta)

    -- Server-side only (both resources run server-side) - lets qbx_reputation
    -- and anything else piggyback on these 18 call sites without touching
    -- them. Not a dependency: this fires whether or not a listener exists.
    TriggerEvent('qbx_honor:server:hookApplied', src, hookName)

    return newValue
end
exports('ApplyHook', ApplyHook)

---Returns a player's current honor value (from cache if available, else qbx_core metadata).
---@param src number
---@return number|nil
local function GetHonor(src)
    src = tonumber(src)
    if not src then return nil end
    if honorCache[src] ~= nil then return honorCache[src] end

    local ok, player = pcall(function() return exports.qbx_core:GetPlayer(src) end)
    if not ok or not player then return nil end

    return player.PlayerData.metadata.honor or Config.DefaultHonor
end
exports('GetHonor', GetHonor)

---Whether this player's honor has permanently latched at the unrepairable
---floor. See Config's "Unrepairable floor" section — this never goes back to
---false once true, regardless of what GetHonor()/the raw value do afterward.
---@param src number
---@return boolean
local function IsHonorBroken(src)
    src = tonumber(src)
    if not src then return false end
    if brokenCache[src] ~= nil then return brokenCache[src] end

    local ok, player = pcall(function() return exports.qbx_core:GetPlayer(src) end)
    if not ok or not player then return false end

    return player.PlayerData.metadata.honorBroken == true
end
exports('IsHonorBroken', IsHonorBroken)

-- ============================================================================
-- First-load initialization
-- qbx_core's own player.lua does not know about `honor`, so this resource is
-- responsible for seeding the default the first time a character is loaded
-- (mirrors the pattern other addon resources in this codebase use for their
-- own custom metadata fields, e.g. an addiction script / qbx_smallresources).
-- ============================================================================

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    if not player or not player.PlayerData then return end
    local src = player.PlayerData.source

    if player.PlayerData.metadata.honor == nil then
        exports.qbx_core:SetMetadata(src, 'honor', Config.DefaultHonor)
        honorCache[src] = Config.DefaultHonor
    else
        honorCache[src] = player.PlayerData.metadata.honor
    end

    -- honorBroken defaults false, exactly like honor defaults to
    -- Config.DefaultHonor above — a brand new character has not hit the
    -- floor yet. Once qbx_core writes it the first time it is never absent
    -- again, so this branch only ever runs once per character.
    if player.PlayerData.metadata.honorBroken == nil then
        exports.qbx_core:SetMetadata(src, 'honorBroken', false)
        brokenCache[src] = false
    else
        brokenCache[src] = player.PlayerData.metadata.honorBroken == true
    end
end)

-- ============================================================================
-- Client sync
-- The client caches honor so other resources can read a tier without a
-- round-trip per call (qbx_vehiclekeys' window-smash flow does this). Honor
-- changes already push to the client via honorUpdated; this only covers the
-- initial value on spawn / resource restart.
-- ============================================================================

RegisterNetEvent('qbx_honor:server:requestHonor', function()
    local src = source
    local value = GetHonor(src)
    if value == nil then return end
    TriggerClientEvent('qbx_honor:client:syncHonor', src, value, IsHonorBroken(src))
end)

AddEventHandler('playerDropped', function()
    honorCache[source] = nil
    brokenCache[source] = nil
    hookState[source] = nil
end)

-- ============================================================================
-- Self-contained wanted-level hook
-- qbx_honor's own client watcher (client/main.lua) reports rising wanted
-- levels here. Kept server-authoritative: the client only reports the event,
-- this handler decides whether it's plausible and applies the penalty.
-- ============================================================================

RegisterNetEvent('qbx_honor:server:wantedIncreased', function(newLevel, oldLevel)
    local src = source
    if type(newLevel) ~= 'number' or type(oldLevel) ~= 'number' then return end
    trace(src, 'wantedIncreased: %s -> %s', tostring(oldLevel), tostring(newLevel))

    if newLevel <= oldLevel or newLevel < 1 then return end -- guard against a spoofed/non-increase report

    -- The anti-farm cooldown lives in Config.Hooks.wanted_level, so rapid star
    -- flicker right at a threshold can't be ground into repeated honor loss.
    ApplyHook(src, 'wanted_level')
end)


-- ============================================================================
-- Self-contained conduct hooks
-- client/conduct.lua watches how the player treats the peds around them and
-- reports one of a small, fixed set of outcomes. The client is not trusted with
-- the amount or the timing - it only names what happened, and this handler
-- decides whether that hook is allowed to fire right now.
--
-- There is no way to re-validate an NPC kill server-side (ambient peds are
-- client-owned and gone by the time we hear about them), so the defence is the
-- allowlist below plus the per-hook cooldowns and session caps in Config.Hooks.
-- ============================================================================

local reportableHooks = {
    kill_civilian = true,
    kill_animal = true,
    aim_at_civilian = true,
    greet_npc = true,
    antagonize_npc = true,
}

RegisterNetEvent('qbx_honor:server:reportConduct', function(hookName)
    local src = source
    trace(src, 'reportConduct received: %s', tostring(hookName))

    if type(hookName) ~= 'string' or not reportableHooks[hookName] then
        trace(src, 'REJECTED: "%s" is not a reportable hook', tostring(hookName))
        return
    end
    if hookName == 'aim_at_civilian' and not Config.ConductWatcher.penaliseAiming then return end

    ApplyHook(src, hookName)
end)
