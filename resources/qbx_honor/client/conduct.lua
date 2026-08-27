-- ============================================================================
-- qbx_honor / client / conduct
--
-- The RDR2-shaped half of the honor system: honor reacts to how you treat the
-- people and animals around you, with no dependency on any other resource.
--
--   * Killing an innocent bystander or a harmless animal costs honor.
--   * A ped that shot at you first, or that dies holding a weapon, is free.
--   * `/greet` waves at a passing stranger and earns a little honor back.
--   * Optionally, pointing a gun at a civilian costs honor (off by default).
--
-- This file never decides how much honor anything is worth, and never applies
-- it. It names what happened and hands that to the server, which owns the
-- amounts, cooldowns and caps (Config.Hooks). See server/main.lua.
-- ============================================================================

print('^2[qbx_honor]^7 client/conduct.lua loaded')

local watcher = Config.ConductWatcher

local function trace(fmt, ...)
    if not Config.Debug then return end
    print(('^5[qbx_honor/conduct]^7 ' .. fmt):format(...))
end

if not watcher.enabled then
    print('^3[qbx_honor]^7 conduct watcher is DISABLED in config - no kill detection.')
    return
end

---Peds that have damaged the local player recently. Killing one of these is
---self-defence and costs nothing - this is what stops honor from punishing the
---player for surviving a mugging they did not start.
---@type table<number, number> [ped] = GetGameTimer() of the last hit taken
local aggressors = {}

---@param hookName string a key of Config.Hooks the server is willing to accept
local function report(hookName)
    TriggerServerEvent('qbx_honor:server:reportConduct', hookName)
end

---@param ped number
---@return boolean
local function getIsAggressor(ped)
    local hitAt = aggressors[ped]
    if not hitAt then return false end

    return (GetGameTimer() - hitAt) < watcher.selfDefenceGraceMs
end

---@param ped number
---@return boolean
local function getIsArmed(ped)
    if not watcher.armedPedsAreFairGame then return false end

    -- IsPedArmed goes false the moment a dead ped drops its weapon, so read the
    -- selected weapon instead - it survives death long enough to be useful.
    -- This is a heuristic; selfDefenceGraceMs is the reliable half of the check.
    return GetSelectedPedWeapon(ped) ~= `WEAPON_UNARMED`
end

---Classifies a ped the local player just killed.
---@param ped number
---@return 'kill_civilian' | 'kill_animal' | nil nil when the kill costs nothing
local function classifyKill(ped)
    if not DoesEntityExist(ped) then return end
    if not IsEntityAPed(ped) or IsPedAPlayer(ped) then return end

    local pedType = GetPedType(ped)

    if watcher.animalPedTypes[pedType] then
        -- A cougar mid-lunge is not an innocent animal.
        return not getIsAggressor(ped) and 'kill_animal' or nil
    end

    if not watcher.civilianPedTypes[pedType] then return end -- gangs, criminals: free
    if getIsAggressor(ped) or getIsArmed(ped) then return end

    return 'kill_civilian'
end

-- ============================================================================
-- Damage watcher
-- One handler covers both jobs: remembering who shot at us, and noticing who we
-- killed.
--
-- CEventNetworkEntityDamage argument layout:
--   args[1]  victim
--   args[2]  attacker
--   args[4]  victimDied (1 when this damage was the killing blow)
--   args[5]  weaponHash
--   args[10] isMelee
--
-- The death flag is args[4], NOT args[6]. This is worth stating plainly because
-- getting it wrong fails silently and invisibly: no error, no log line, honor
-- simply never moves when you kill anyone. The layout is corroborated by
-- [Scripts]/PolyZone/EntityZone.lua, [Scripts]/stevo_lib's framework bridges,
-- and CitizenFX's own ped-money-drops example, all shipped in this server.
-- ============================================================================

local VICTIM, ATTACKER, VICTIM_DIED = 1, 2, 4

---Was this damage ours?
---
---Running a ped over reports the VEHICLE as the attacker, not the ped driving
---it - so a plain `attacker == playerPed` test silently ignores every vehicular
---death, which is one of the most common ways a player kills a bystander.
---@param attacker number
---@param playerPed number
---@return boolean
local function getIsOurs(attacker, playerPed)
    if not attacker or attacker == 0 then return false end
    if attacker == playerPed then return true end

    -- A vehicle we are sitting in, or one we were the last driver of (the ped
    -- can already be out of the car by the time the victim dies).
    if IsEntityAVehicle(attacker) then
        if GetVehiclePedIsIn(playerPed, false) == attacker then return true end
        if GetPedInVehicleSeat(attacker, -1) == playerPed then return true end
    end

    return false
end

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end

    local victim = args[VICTIM]
    local attacker = args[ATTACKER]
    local playerPed = PlayerPedId()

    if not victim or victim == 0 then return end

    -- Someone hit us: remember them, fatal or not.
    if victim == playerPed and attacker and attacker ~= 0 and attacker ~= playerPed then
        aggressors[attacker] = GetGameTimer()
        return
    end

    if victim == playerPed or not getIsOurs(attacker, playerPed) then return end

    -- Trust the flag, but confirm against the ped itself. If the argument
    -- layout ever shifts under us this keeps working off observable state
    -- rather than going quiet again.
    local isFatal = args[VICTIM_DIED] == 1
        or (DoesEntityExist(victim) and IsPedDeadOrDying(victim, true))

    if not isFatal then return end

    local hookName = classifyKill(victim)

    trace('fatal hit by us on ped %s (type %s) -> %s',
        tostring(victim), tostring(GetPedType(victim)), hookName or 'no honor cost')

    if hookName then
        report(hookName)
    end

    aggressors[victim] = nil
end)

-- Entity handles are recycled, so a stale entry could excuse a later kill.
-- Expiring them on a slow timer keeps both the table and the grace window honest.
CreateThread(function()
    while true do
        Wait(30000)

        local now = GetGameTimer()
        for ped, hitAt in pairs(aggressors) do
            if (now - hitAt) >= watcher.selfDefenceGraceMs then
                aggressors[ped] = nil
            end
        end
    end
end)

-- ============================================================================
-- Greeting / Antagonizing
--
-- Both are exports.ox_target:addGlobalPed options rather than a command, so
-- ox_target owns targeting/range/prompt UI (same "Pickpocket" pattern
-- [UM]/um_beg/client/pickpocket.lua uses). canInteract is intentionally
-- omitted for the same reason that file's comment gives - ox_target calls it
-- from its own Lua state where this resource's globals don't exist - so the
-- civilian-type check happens inside onSelect instead. Selecting either
-- option on a non-civilian ped (cop, gang member, ...) is a silent no-op.
--
-- The reaction to either one reads the player's OWN qbx_reputation standing
-- (client-cached, so this never blocks on a round-trip): a well-known
-- criminal gets flinched away from on a Greet and bolted from twice as hard
-- on an Antagonize; a well-known trader gets a warmer Greet. Best-effort -
-- if qbx_reputation isn't running, everything falls back to tier 1 (baseline
-- behaviour, unchanged from before this existed).
-- ============================================================================

local GREET_ANIM = { dict = 'gestures@m@standing@casual', clip = 'gesture_hello' }

---@param track string 'criminal' | 'trade' | 'exploration'
---@return number tier 1 (baseline) if qbx_reputation has no data or isn't running
local function safeGetTier(track)
    if GetResourceState('um_livingworld') ~= 'started' then return 1 end
    local ok, tier = pcall(function() return exports.um_livingworld:GetTier(track) end)
    return (ok and tier) or 1
end

---@param ped number
---@return boolean
local function isGreetable(ped)
    return DoesEntityExist(ped) and not IsPedAPlayer(ped) and not IsPedDeadOrDying(ped, true)
        and watcher.civilianPedTypes[GetPedType(ped)]
end

-- Per-ped, client-only spam guard so mashing the target option doesn't queue
-- anim tasks or fire the interaction faster than a person could plausibly
-- repeat it. Config.Hooks' server-side cooldown is the real anti-farm; this
-- is just so the ped doesn't visibly stutter.
local interactionCooldowns = {} -- [ped] = GetGameTimer() it's next available

local function onCooldown(ped)
    local expires = interactionCooldowns[ped]
    return expires ~= nil and GetGameTimer() < expires
end

local function setCooldown(ped, ms)
    interactionCooldowns[ped] = GetGameTimer() + ms
end

local function greet(target)
    if onCooldown(target) then return end
    setCooldown(target, 8000)

    local playerPed = PlayerPedId()

    RequestAnimDict(GREET_ANIM.dict)
    local timeout = GetGameTimer() + 2000
    while not HasAnimDictLoaded(GREET_ANIM.dict) and GetGameTimer() < timeout do
        Wait(0)
    end
    if not HasAnimDictLoaded(GREET_ANIM.dict) then return end

    TaskPlayAnim(playerPed, GREET_ANIM.dict, GREET_ANIM.clip, 3.0, 3.0, -1, 48, 0, false, false, false)

    -- Fear outranks warmth: a well-known criminal doesn't get the friendly
    -- reception a well-known trader would, even if both tiers are high.
    if safeGetTier('criminal') >= 3 then
        TaskTurnPedToFaceEntity(target, playerPed, 800)
        SetTimeout(900, function()
            if DoesEntityExist(target) then TaskWanderStandard(target, 10.0, 10) end
        end)
        exports.qbx_core:Notify('They eye you nervously and hurry past without waving back.', 'error')
    else
        TaskTurnPedToFaceEntity(target, playerPed, 1500)
        TaskPlayAnim(target, GREET_ANIM.dict, GREET_ANIM.clip, 3.0, 3.0, -1, 48, 0, false, false, false)

        if safeGetTier('trade') >= 3 then
            exports.qbx_core:Notify('They recognize you and greet you warmly.', 'success')
        end
    end

    report('greet_npc')
end

local function antagonize(target)
    if onCooldown(target) then return end
    setCooldown(target, 8000)

    local playerPed = PlayerPedId()

    -- Reuses the exact natives [UM]/um_beg/client/pickpocket.lua's failure
    -- branch already proves work on this server, rather than guessing at a
    -- new intimidation anim dict.
    TaskTurnPedToFaceEntity(playerPed, target, 500)
    PlayAmbientSpeech1(target, 'GENERIC_CURSE_HIGH', 'SPEECH_PARAMS_FORCE_SHOUTED_CRITICAL')
    TaskReactAndFleePed(target, playerPed)

    if safeGetTier('criminal') >= 3 then
        -- Already known for it - they don't just flinch, they bolt further and
        -- faster than TaskReactAndFleePed's default panic.
        SetTimeout(200, function()
            if DoesEntityExist(target) then TaskSmartFleeEntity(target, playerPed, 100.0, -1) end
        end)
        exports.qbx_core:Notify('Word travels fast - they bolt the second they recognize you.', 'error')
    else
        exports.qbx_core:Notify('They flinch and back away.', 'error')
    end

    report('antagonize_npc')
end

CreateThread(function()
    while GetResourceState('ox_target') ~= 'started' do
        Wait(1000)
    end

    exports.ox_target:addGlobalPed({
        {
            name = 'qbx_honor_greet',
            label = 'Greet',
            icon = 'fas fa-hand-paper',
            distance = watcher.interactionDistance,
            onSelect = function(data)
                local target = data.entity
                if not isGreetable(target) then return end
                CreateThread(function() greet(target) end)
            end,
        },
        {
            name = 'qbx_honor_antagonize',
            label = 'Antagonize',
            icon = 'fas fa-hand-fist',
            distance = watcher.interactionDistance,
            onSelect = function(data)
                local target = data.entity
                if not isGreetable(target) then return end
                CreateThread(function() antagonize(target) end)
            end,
        },
    })
end)

-- ============================================================================
-- Ambient reactions
-- World-state texture, not a hook: nearby civilians occasionally react to a
-- player whose qbx_reputation is high enough to be recognizable, with no
-- honor/reputation change and no dialogue - see Config.ConductWatcher.Ambient.
-- Deliberately animation-only. A notify popup every time a passerby glances
-- at you would turn "ambient" into "nagging" the moment a tier holds for a
-- whole session; the deliberate Greet/Antagonize interactions above are
-- where the flavour text belongs, because there the player asked for it.
-- ============================================================================

local ambientCooldowns = {} -- [ped] = GetGameTimer() it's next eligible

local function ambientOnCooldown(ped)
    local expires = ambientCooldowns[ped]
    return expires ~= nil and GetGameTimer() < expires
end

---Eligible civilians within Ambient.radius, any direction. Unlike Greet/
---Antagonize this is not something the player aimed at, so no facing cone.
---@param ambient table Config.ConductWatcher.Ambient
---@return number[]
local function nearbyReactableCivilians(ambient)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local peds = GetGamePool('CPed')
    local found = {}

    for i = 1, #peds do
        local ped = peds[i]
        if ped ~= playerPed and isGreetable(ped) and not ambientOnCooldown(ped) then
            local distance = #(GetEntityCoords(ped) - playerCoords)
            if distance <= ambient.radius then
                found[#found + 1] = ped
            end
        end
    end

    return found
end

---A head-turn only (not a task that derails whatever the ped is already
---doing), same for a wary glance or a nod of recognition - the two read the
---same from third person, and the difference is meant to be subliminal, not
---explained. Someone at high standing in BOTH tracks is more curiosity than
---threat, so this only fires for whichever gets there here.
---@param ped number
local function ambientReact(ped)
    ambientCooldowns[ped] = GetGameTimer() + Config.ConductWatcher.Ambient.cooldownMs
    TaskLookAtEntity(ped, PlayerPedId(), 1500, 0, 2)
end

CreateThread(function()
    local ambient = Config.ConductWatcher.Ambient
    if not ambient.enabled then return end

    while true do
        Wait(math.random(ambient.intervalMsMin, ambient.intervalMsMax))

        local playerPed = PlayerPedId()
        if IsPedDeadOrDying(playerPed, true) then goto continue end

        -- Cheapest possible early-out: don't touch the ped pool at all until
        -- a track has actually reached the reaction threshold.
        local criminalTier = safeGetTier('criminal')
        local tradeTier = safeGetTier('trade')
        if criminalTier < ambient.tierThreshold and tradeTier < ambient.tierThreshold then
            goto continue
        end

        do
            local candidates = nearbyReactableCivilians(ambient)
            local reactions = 0

            for i = 1, #candidates do
                if reactions >= ambient.maxReactionsPerScan then break end

                if math.random(100) <= ambient.chancePercent then
                    ambientReact(candidates[i])
                    reactions = reactions + 1
                end
            end
        end

        ::continue::
    end
end)

-- ============================================================================
-- Aiming at civilians (opt-in)
-- ============================================================================

if watcher.penaliseAiming then
    CreateThread(function()
        while true do
            Wait(500)

            local playerId = PlayerId()

            if IsPlayerFreeAiming(playerId) then
                local found, entity = GetEntityPlayerIsFreeAimingAt(playerId)

                if found and entity and entity ~= 0 and IsEntityAPed(entity)
                    and not IsPedAPlayer(entity)
                    and not IsPedDeadOrDying(entity, true)
                    and watcher.civilianPedTypes[GetPedType(entity)]
                    and not getIsAggressor(entity)
                then
                    report('aim_at_civilian')
                    -- The server's cooldown is authoritative; this just keeps the
                    -- client from firing the event several times a second.
                    Wait(5000)
                end
            end
        end
    end)
end
