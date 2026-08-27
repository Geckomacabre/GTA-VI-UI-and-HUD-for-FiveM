--[[ =========================================================================
     vice_hud — skills: tracking, stats, HUD
     -------------------------------------------------------------------------
     Watches what the player actually does, turns it into XP, and writes each
     skill's level into the GTA player stat it belongs to. The stat write is the
     whole point: without it this would be a number that goes up on a panel and
     changes nothing about the game.

     Kept out of client.lua deliberately. That file is already 3000 lines about
     drawing a HUD; this is a gameplay system that happens to have a HUD, and
     the two share nothing but the `ui()` helper.

     HOW ACTIVITY IS MEASURED
     Two mechanisms, chosen per skill by what is actually observable:

       · a sampling loop at Config.Skills.tick for anything that is distance or
         elapsed time — sprinting, swimming, crouching, driving, flying
       · gameEventTriggered / CEventNetworkEntityDamage for anything that is an
         EVENT — a melee hit landed, a shot on target

     Polling for hits would mean asking every nearby ped whether it had been
     damaged, every tick, and still missing the ones that died from it. The
     damage event carries attacker, victim and weapon, which is exactly the
     question being asked.
     ====================================================================== --]]

local CFG = Config.Skills or { enable = false }

if not CFG.enable then return end

--- Its own copy, deliberately.
---
--- client.lua declares `ui` as a LOCAL function, and a local does not cross a
--- file boundary — every .lua in a resource is its own chunk. Calling it from
--- here found a nil global and took the whole file down with
--- "attempt to call a nil value (global 'ui')". Four lines duplicated beats a
--- global shared between two files that have nothing else to do with each
--- other.
local function ui(action, data)
    data = data or {}
    data.action = action
    SendNUIMessage(data)
end

-- xp per skill id. Authoritative on the client between saves; the server owns
-- the persisted copy.
local xp = Skills.normalise(nil)

-- Levels as last applied to the engine, so an unchanged level is not re-written
-- to the stat sixty times a minute.
local appliedLevel = {}

-- XP banked since the last successful save.
local dirty = false

-- Set once the server has answered with the stored values. Until then nothing
-- is awarded, because XP earned against a zeroed table would be lost the moment
-- the real values arrived and overwrote it.
local loaded = false

-- =============================================================================
-- Stats
-- =============================================================================

--- Write one skill's level into its GTA stat.
---
--- The level IS the stat value (both are 0..100), so there is no conversion to
--- get wrong and nothing that can drift between the panel and the engine.
local function applyStat(id, level)
    local def = Skills.ById[id]
    if not def then return end
    if appliedLevel[id] == level then return end
    appliedLevel[id] = level

    local name = (CFG.statPrefix or 'MP0_') .. def.stat
    -- pcall'd: a stat name that does not exist on this build should cost one
    -- skill, not take every other stat down with it.
    pcall(function() StatSetInt(GetHashKey(name), level, true) end)
end

local function applyAllStats()
    for i = 1, #Skills.List do
        local id = Skills.List[i].id
        applyStat(id, (Skills.resolve(xp[id])))
    end
end

-- =============================================================================
-- HUD
-- =============================================================================

local function skillPayload()
    local list = {}
    for i = 1, #Skills.List do
        local def = Skills.List[i]
        local level, into, need, frac = Skills.resolve(xp[def.id])
        list[#list + 1] = {
            id = def.id, label = def.label, blurb = def.blurb, unit = def.unit,
            level = level, into = into, need = need, frac = frac,
            max = level >= Skills.MAX_LEVEL,
        }
    end
    return list
end

local function pushSkills(show)
    ui('skills', { show = show and true or false, skills = skillPayload() })
end

-- =============================================================================
-- Awarding
-- =============================================================================

--- Add XP to a skill, apply any level change, and announce it.
---
--- Every award goes through here so there is exactly one place that can level a
--- skill up — and therefore exactly one place that can be wrong about it.
local function award(id, amount)
    if not loaded then return end
    local def = Skills.ById[id]
    if not def or not amount or amount <= 0 then return end

    local before = (Skills.resolve(xp[id]))
    xp[id] = xp[id] + amount
    dirty = true

    local after = (Skills.resolve(xp[id]))
    if after == before then return end

    applyStat(id, after)
    pushSkills(false)          -- refresh the panel's numbers without opening it

    if CFG.announce then
        ui('skillUp', { id = id, label = def.label, level = after, blurb = def.blurb })
        lib.notify({
            id = 'vice_hud:skill:' .. id,
            title = def.label .. ' ' .. after,
            description = def.blurb,
            type = 'success',
            duration = 4000,
        })
    end

    -- A level is worth writing down immediately; losing one to a crash is much
    -- more annoying than losing thirty seconds of progress toward it.
    TriggerServerEvent('vice_hud:skills:save', xp)
    dirty = false
end

--- Award for an activity measured in its own units (metres, seconds, hits).
local function awardUnits(id, units)
    local def = Skills.ById[id]
    if not def or units <= 0 then return end
    award(id, units * def.rate)
end

-- Other resources can grant XP too. A skills system nothing else can feed is
-- one that only rewards the handful of activities this file happens to watch.
exports('AddSkillXp', function(id, amount)
    award(id, tonumber(amount) or 0)
    return true
end)

exports('GetSkill', function(id)
    if not Skills.ById[id] then return nil end
    local level, into, need, frac = Skills.resolve(xp[id])
    return { id = id, xp = xp[id], level = level, into = into, need = need, frac = frac }
end)

exports('GetSkills', function()
    local out = {}
    for i = 1, #Skills.List do
        local id = Skills.List[i].id
        out[id] = { xp = xp[id], level = (Skills.resolve(xp[id])) }
    end
    return out
end)

--- Read by the exhaustion model, so being fit is worth something beyond the
--- native stat. 0 at level 0, 1 at max.
function SkillFitness()
    if not CFG.fitnessAffectsFatigue then return 0.0 end
    return (Skills.resolve(xp.stamina)) / Skills.MAX_LEVEL
end

-- =============================================================================
-- Persistence
-- =============================================================================

RegisterNetEvent('vice_hud:skills:load', function(stored)
    xp = Skills.normalise(stored)
    loaded = true
    applyAllStats()
    pushSkills(false)
end)

CreateThread(function()
    -- Ask on start AND after a short wait: the resource can come up before the
    -- player is fully loaded server-side, and a request that arrives too early
    -- gets no answer at all.
    for _ = 1, 3 do
        if loaded then break end
        TriggerServerEvent('vice_hud:skills:request')
        Wait(3000)
    end
end)

CreateThread(function()
    while true do
        Wait(CFG.saveMs or 30000)
        if dirty and loaded then
            TriggerServerEvent('vice_hud:skills:save', xp)
            dirty = false
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if dirty and loaded then TriggerServerEvent('vice_hud:skills:save', xp) end
end)

-- =============================================================================
-- Activity: events
-- =============================================================================

-- Melee hits and shots on target. Both come from the same damage event, told
-- apart by whether the weapon is a melee weapon.
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    if not loaded then return end

    local victim, attacker = args[1], args[2]
    local ped = cache.ped or PlayerPedId()
    if not ped or ped == 0 then return end
    -- Only damage WE dealt, and never to ourselves — falling down the stairs is
    -- not strength training.
    if attacker ~= ped or victim == ped then return end
    if not DoesEntityExist(victim) then return end

    -- Classify by what the player is HOLDING, not by the weapon hash in the
    -- event payload. The argument layout of CEventNetworkEntityDamage is not
    -- stable enough across builds to index by position with any confidence, and
    -- guessing wrong here means silently crediting the wrong skill forever.
    -- IsPedArmed answers the only question being asked.
    if IsPedArmed(ped, 1) or not IsPedArmed(ped, 7) then
        -- Melee, or bare hands (armed with nothing at all).
        awardUnits('strength', 1)
    elseif IsPedArmed(ped, 2) then
        awardUnits('shooting', 1)
    end
end)

-- =============================================================================
-- Driving skill -> real handling
-- =============================================================================
-- MP0_DRIVING_ABILITY is written faithfully by applyStat, but Rockstar only
-- wires that stat's grip assist into the singleplayer protagonists' ability
-- scripts, which never run for a freemode ped -- so the level climbing did
-- nothing a player could feel. This applies an actual traction change to
-- whatever the player is driving instead, scaled off the skill level.
--
-- SetVehicleHandlingFloat mutates the handling data attached to that ONE
-- vehicle entity (FiveM clones it off the shared class data on first write),
-- so this never touches every car of that model, only the one being driven.

-- veh handle -> stock traction floats, read once per vehicle so repeated
-- ticks multiply off the ORIGINAL value rather than compounding onto an
-- already-boosted one.
local drivingBase = {}

-- The vehicle currently carrying a handling boost, so it can be put back to
-- stock the moment the skilled driver gets out — the boost must not become a
-- free permanent upgrade for whoever drives that car next.
local drivingVeh = nil

--- 1.0 at the midpoint (Config.Skills.startingLevel — "an average character"),
--- swinging by +/- half of drivingGripBonus at the ends of the skill range.
--- Also folds in vice_hud's Focus ability, when active for this driver: this
--- function's caller (applyDrivingHandling) is the ONLY writer of the
--- vehicle's traction fields while this skill owns them, reapplying every
--- tick straight from its own cached stock values -- a second writer (Focus,
--- from client.lua) would just get silently overwritten within one tick, so
--- Focus signals through the VicehudFocusActive global instead of writing
--- these fields itself. See client.lua's "Grip boost while driving in Focus".
local function drivingFactor(level)
    local mid = (Skills.MAX_LEVEL or 100) / 2.0
    local bonus = CFG.drivingGripBonus or 0.0
    local factor = 1.0 + ((level - mid) / mid) * bonus
    if _G.VicehudFocusActive and Config.Focus then
        factor = factor * (Config.Focus.drivingGripBonus or 1.0)
    end
    return factor
end

local function applyDrivingHandling(veh)
    if not CFG.drivingAffectsHandling then return end
    local base = drivingBase[veh]
    if not base then
        local okMax, curveMax = pcall(GetVehicleHandlingFloat, veh, 'CHandlingData', 'fTractionCurveMax')
        local okMin, curveMin = pcall(GetVehicleHandlingFloat, veh, 'CHandlingData', 'fTractionCurveMin')
        local okLoss, lossMult = pcall(GetVehicleHandlingFloat, veh, 'CHandlingData', 'fTractionLossMult')
        -- A read failure means this build's handling fields do not match —
        -- skip rather than write a value derived from a nil.
        if not (okMax and okMin and okLoss) then return end
        base = { curveMax = curveMax, curveMin = curveMin, lossMult = lossMult }
        drivingBase[veh] = base
    end

    local level = (Skills.resolve(xp.driving))
    local factor = drivingFactor(level)
    -- Higher curve = more lateral grip before the tyres let go; lower loss
    -- mult = grip comes back faster once it does. Both move the same
    -- direction with skill, so factor and its inverse, not two separate knobs.
    pcall(SetVehicleHandlingFloat, veh, 'CHandlingData', 'fTractionCurveMax', base.curveMax * factor)
    pcall(SetVehicleHandlingFloat, veh, 'CHandlingData', 'fTractionCurveMin', base.curveMin * factor)
    pcall(SetVehicleHandlingFloat, veh, 'CHandlingData', 'fTractionLossMult', base.lossMult / factor)
end

--- Put a vehicle's traction back exactly as found. Anyone else who drives it
--- afterwards — another player, an NPC, the skilled driver at a lower level
--- next session — gets stock handling, not a stranger's stat leaking in.
local function restoreDrivingHandling(veh)
    local base = drivingBase[veh]
    if not base then return end
    drivingBase[veh] = nil
    if not DoesEntityExist(veh) then return end
    pcall(SetVehicleHandlingFloat, veh, 'CHandlingData', 'fTractionCurveMax', base.curveMax)
    pcall(SetVehicleHandlingFloat, veh, 'CHandlingData', 'fTractionCurveMin', base.curveMin)
    pcall(SetVehicleHandlingFloat, veh, 'CHandlingData', 'fTractionLossMult', base.lossMult)
end

-- Both of these can fire mid-session (resource restart, disconnect) with a
-- boost still live on whatever the player was last driving.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if drivingVeh then restoreDrivingHandling(drivingVeh) end
end)

-- =============================================================================
-- Activity: sampling loop
-- =============================================================================

CreateThread(function()
    local lastPos = nil
    local wasInVehicle = false

    while true do
        Wait(CFG.tick or 200)

        if not loaded then goto continue end

        do
            local ped = cache.ped or PlayerPedId()
            if not DoesEntityExist(ped) or IsEntityDead(ped) then
                lastPos = nil
                goto continue
            end

            local pos = GetEntityCoords(ped)
            local step = 0.0
            if lastPos then step = #(pos - lastPos) end
            lastPos = pos

            -- A teleport, a respawn or being carried by a lift would otherwise
            -- bank hundreds of metres in a single sample. Distance is only
            -- credited when it is a distance a person could have covered.
            if step > (CFG.maxStep or 40.0) then step = 0.0 end

            local dtSec = (CFG.tick or 200) / 1000.0
            local veh = cache.vehicle
            local inVehicle = veh and veh ~= 0

            if inVehicle then
                -- ---- driving ------------------------------------------
                -- Only the driver, and only while the vehicle is not in the
                -- middle of hitting something. Crediting a passenger for the
                -- driver's mileage would make the fastest route to a maxed
                -- driving skill "sit in someone else's car".
                if GetPedInVehicleSeat(veh, -1) == ped then
                    if HasEntityCollidedWithAnything(veh) then
                        -- Nothing this sample. The skill is called "driven
                        -- without a crash" and it should mean it.
                    else
                        awardUnits('driving', step)
                    end

                    if veh ~= drivingVeh then
                        -- Switched cars (or just got in one): put the last
                        -- one back to stock before touching this one.
                        if drivingVeh then restoreDrivingHandling(drivingVeh) end
                        drivingVeh = veh
                    end
                    applyDrivingHandling(veh)
                elseif drivingVeh then
                    -- Moved to a different seat in the same tick the driver
                    -- swap happened — no longer the one earning the boost.
                    restoreDrivingHandling(drivingVeh)
                    drivingVeh = nil
                end

                -- ---- flying -------------------------------------------
                -- 15 = helicopters, 16 = planes.
                local class = GetVehicleClass(veh)
                if (class == 15 or class == 16) and IsEntityInAir(veh) then
                    awardUnits('flying', dtSec)
                end

                -- ---- wheelie ------------------------------------------
                -- Bikes only, moving, front wheel clearly up. Pitch alone is
                -- not enough: a bike on a hill is pitched too.
                if class == 8 and GetEntitySpeed(veh) > 4.0
                   and GetEntityPitch(veh) > 18.0 and not IsEntityInAir(veh) then
                    awardUnits('wheelie', dtSec)
                end
            else
                wasInVehicle = false

                if drivingVeh then
                    restoreDrivingHandling(drivingVeh)
                    drivingVeh = nil
                end

                -- ---- lung capacity ------------------------------------
                if IsPedSwimmingUnderWater(ped) then
                    awardUnits('lung', dtSec)
                end

                -- ---- stamina ------------------------------------------
                -- Sprinting only. Jogging everywhere would otherwise max the
                -- stat by accident, and the skill is supposed to be about
                -- pushing yourself.
                if IsPedSprinting(ped) and step > 0.0 then
                    awardUnits('stamina', step)
                end

                -- ---- stealth ------------------------------------------
                if GetPedStealthMovement(ped) == 1 and step > 0.0 then
                    awardUnits('stealth', step)
                end
            end

            if inVehicle ~= wasInVehicle then wasInVehicle = inVehicle end
        end

        ::continue::
    end
end)

-- =============================================================================
-- Commands
-- =============================================================================

-- Whether the panel has NUI focus. Tracked with our own flag rather than
-- IsNuiFocused(), for the same reason the editor does: another resource's
-- legitimately focused NUI must never be stolen out from under it.
local skillsFocused = false

local function closeSkillsPanel()
    if skillsFocused then
        skillsFocused = false
        SetNuiFocus(false, false)
    end
    ui('skills', { show = false })
end

RegisterCommand('skills', function()
    pushSkills(true)
    skillsFocused = true
    SetNuiFocus(true, true)
end, false)

for _, alias in ipairs({ 'skill', 'stats', 'xp' }) do
    RegisterCommand(alias, function() ExecuteCommand('skills') end, false)
end

RegisterNUICallback('closeSkills', function(_, cb)
    closeSkillsPanel()
    cb({ ok = true })
end)

-- NUI focus is GLOBAL and survives this resource restarting, so a panel that
-- died holding it takes the player's hotbar keys with it until they rejoin.
-- Same three safety nets the editor has, for the same reason.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if skillsFocused then SetNuiFocus(false, false) end
end)

-- /hudfocus is the manual release for stranded NUI focus and it lives in
-- client.lua, which cannot see this file's locals. It broadcasts instead, so
-- one command clears every panel in the resource rather than only the editor.
AddEventHandler('vice_hud:releaseFocus', function()
    skillsFocused = false
end)

--- Print every skill, with what the engine was actually told.
---
--- Reads the stat back rather than reporting the level we meant to write: a
--- stat that silently refused the write is exactly the failure this is for.
RegisterCommand('skillinfo', function()
    print('^3[vice_hud]^7 ============ skills ============')
    print(('  prefix %s   loaded %s'):format(CFG.statPrefix or 'MP0_', tostring(loaded)))
    for i = 1, #Skills.List do
        local def = Skills.List[i]
        local level, into, need = Skills.resolve(xp[def.id])
        local statName = (CFG.statPrefix or 'MP0_') .. def.stat
        local okRead, engine = pcall(function() return StatGetInt(GetHashKey(statName), -1) end)
        print(('  %-9s lvl %3d  xp %8d  (%d/%d to next)   %s = %s')
            :format(def.id, level, xp[def.id], into, need, statName,
                    okRead and tostring(engine) or 'unreadable'))
    end
    print('  A stat that does not match its level was refused by the engine —')
    print('  usually the wrong statPrefix for the ped model in use.')

    if CFG.drivingAffectsHandling then
        local level = (Skills.resolve(xp.driving))
        print(('  driving handling: factor %.3f (level %d, bonus +/-%.0f%%)')
            :format(drivingFactor(level), level, (CFG.drivingGripBonus or 0.0) * 50.0))
        if drivingVeh and DoesEntityExist(drivingVeh) then
            local okMax, curveMax = pcall(GetVehicleHandlingFloat, drivingVeh, 'CHandlingData', 'fTractionCurveMax')
            print(('    currently applied to veh %s — live fTractionCurveMax = %s (stock %.3f)')
                :format(tostring(drivingVeh), okMax and tostring(curveMax) or 'unreadable',
                        drivingBase[drivingVeh] and drivingBase[drivingVeh].curveMax or -1))
        else
            print('    not currently driving — nothing applied right now')
        end
    else
        print('  driving handling: disabled (Config.Skills.drivingAffectsHandling = false)')
    end
end, false)

--- Grant XP by hand, for testing the curve and the toast without playing for
--- an hour. Not gated: it is a client command, so it only ever affects the
--- person who runs it, and the server clamps what it will store.
RegisterCommand('skillxp', function(_, args)
    local id, amount = args[1], tonumber(args[2])
    if not id or not amount then
        print('^3[vice_hud]^7 usage: /skillxp <skill> <amount>       e.g. /skillxp stamina 500')
        print('                /skillxp reset                  clear everything')
        local names = {}
        for i = 1, #Skills.List do names[#names + 1] = Skills.List[i].id end
        print('  skills: ' .. table.concat(names, ', '))
        return
    end
    if id == 'reset' then
        xp = Skills.normalise(nil)
        appliedLevel = {}
        applyAllStats()
        pushSkills(false)
        TriggerServerEvent('vice_hud:skills:save', xp)
        print('^2[vice_hud]^7 skills reset')
        return
    end
    if not Skills.ById[id] then
        print(('^1[vice_hud]^7 unknown skill "%s" — run /skillxp for the list'):format(id))
        return
    end
    award(id, amount)
    ExecuteCommand('skillinfo')
end, false)

RegisterCommand('skillreset', function() ExecuteCommand('skillxp reset') end, false)
