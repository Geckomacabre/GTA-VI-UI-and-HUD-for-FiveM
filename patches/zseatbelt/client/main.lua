-- zSeatbelt client — ported from zfbx/zSeatbelt (MIT), see NOTICE.md.
--
-- Two things other resources on this server rely on, neither of which upstream
-- provided:
--   * seatbelt:client:ToggleSeatbelt(state) -> um_hud's BELT bar
--   * LocalPlayer.state.seatbelt            -> qbx_noshuff's shuffle block
-- Both are pushed from setSeatbelt() so they can never drift out of sync with
-- the actual belt state.

local seatbeltOn = false
local uiActive   = false

local function isExemptVehicle(vehicle)
    return vehicle and Config.exemptClasses[GetVehicleClass(vehicle)] or false
end

-- Upstream looped -1 .. GetVehicleMaxNumberOfPassengers() - 2, which drops the
-- last seat (the native excludes the driver, so the last passenger index is
-- already max - 1). It also fed NPC passengers into the list: for a non-player
-- ped NetworkGetPlayerIndexFromPed returns -1 and GetPlayerServerId(-1) is 0,
-- so the server ended up firing at "player 0" once per NPC.
local function getPassengerServerIds(vehicle)
    local ids = {}
    for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if ped ~= 0 and IsPedAPlayer(ped) then
            local player = NetworkGetPlayerIndexFromPed(ped)
            if player ~= -1 then
                ids[#ids + 1] = GetPlayerServerId(player)
            end
        end
    end
    return ids
end

local function playSound(action)
    if not Config.playSound then return end

    if Config.playSoundForPassengers and cache.vehicle then
        TriggerServerEvent('seatbelt:server:PlaySound', action, getPassengerServerIds(cache.vehicle))
    else
        SendNUIMessage({ type = action, volume = Config.volume })
    end
end

local function toggleUI(status)
    if not Config.showUnbuckledIndicator then return end
    if uiActive == status then return end
    uiActive = status
    SendNUIMessage({ type = status and 'showindicator' or 'hideindicator' })
end

---Set the belt to an absolute state and fan that state out to everything.
---@param state boolean
---@param silent? boolean skip the buckle/unbuckle sound (used on forced exit)
local function setSeatbelt(state, silent)
    if seatbeltOn == state then return end
    seatbeltOn = state

    if state then
        -- Buckled: the ejection thresholds are pushed far out of reach rather
        -- than toggling ped config flag 32, because SetFlyThroughWindscreenParams
        -- is global state and the flag alone does not stop the eject.
        SetFlyThroughWindscreenParams(10000.0, 10000.0, Config.unknownModifier, 500.0)
    else
        SetFlyThroughWindscreenParams(Config.ejectVelocity, Config.unknownEjectVelocity, Config.unknownModifier, Config.minDamage)
    end

    -- Not replicated: qbx_noshuff is the only reader and it runs client-side.
    LocalPlayer.state:set('seatbelt', state, false)

    -- Explicit state, not a bare toggle - see NOTICE.md.
    TriggerEvent('seatbelt:client:ToggleSeatbelt', state)

    -- Truthiness, not a nil test: ox_lib parks cache.vehicle at `false` on foot.
    toggleUI(not state and cache.vehicle and not isExemptVehicle(cache.vehicle) or false)

    if not silent then
        playSound(state and 'buckle' or 'unbuckle')
    end
end

-- Hold the exit-vehicle control down only while it actually matters, instead of
-- upstream's unconditional 10ms loop that ran even on foot.
local function fixedWhileBuckledLoop()
    CreateThread(function()
        while seatbeltOn and cache.vehicle do
            DisableControlAction(0, 75, true)   -- exit vehicle, stopped
            DisableControlAction(27, 75, true)  -- exit vehicle, driving
            Wait(0)
        end
    end)
end

local function toggleSeatbelt()
    if not cache.vehicle or not cache.seat then return end
    if isExemptVehicle(cache.vehicle) then return end

    setSeatbelt(not seatbeltOn)

    if seatbeltOn and Config.fixedWhileBuckled then
        fixedWhileBuckledLoop()
    end
end

lib.onCache('vehicle', function(vehicle)
    if vehicle then
        -- um_hud clears its own beltOn in the same cache hook, so both sides land
        -- on "unbuckled" on entry regardless of which resource's hook runs first.
        toggleUI(not seatbeltOn and not isExemptVehicle(vehicle))
    else
        -- Left the vehicle (or was ragdolled/killed out of it): drop the belt
        -- silently, otherwise every exit plays an unbuckle click.
        setSeatbelt(false, true)
        toggleUI(false)
    end
end)

RegisterCommand('toggleseatbelt', toggleSeatbelt, false)
RegisterKeyMapping('toggleseatbelt', 'Toggle Seatbelt', 'keyboard', Config.key)

RegisterNetEvent('seatbelt:client:PlaySound', function(action, volume)
    SendNUIMessage({ type = action, volume = volume })
end)

exports('status', function() return seatbeltOn end)

-- Baseline so a player who never buckles still gets the configured eject values.
SetFlyThroughWindscreenParams(Config.ejectVelocity, Config.unknownEjectVelocity, Config.unknownModifier, Config.minDamage)

-- Position pushed from vice_hud's HUD editor (/movehud). zseatbelt owns its own
-- NUI page, so the offset is broadcast by vice_hud and applied here.
AddEventHandler('vice_hud:layout', function(layout)
    local o = layout and layout.seatbelt
    SendNUIMessage({
        type = 'offset',
        x = o and o.x or 0.0,
        y = o and o.y or 0.0,
        s = o and o.s or 1.0,
    })
end)

CreateThread(function()
    Wait(2500)
    if GetResourceState('vice_hud') == 'started' then
        local ok, x, y = pcall(function() return exports.vice_hud:GetHudOffset('seatbelt') end)
        if ok then SendNUIMessage({ type = 'offset', x = x or 0.0, y = y or 0.0 }) end
    end
end)
