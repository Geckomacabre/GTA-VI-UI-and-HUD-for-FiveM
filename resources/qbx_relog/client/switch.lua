-- The switch cinematic: up into the clouds, swap the character, come back down.
--
-- This is the engine's own singleplayer switch, not an imitation of it.
-- SWITCH_TO_MULTI_FIRSTPART pulls the camera off the current ped and climbs; the
-- engine then parks in state 5 ("in the air") indefinitely until
-- SWITCH_TO_MULTI_SECONDPART tells it which ped to come back down onto. Every
-- ped-churning step of the character swap -- model change, appearance apply,
-- teleport across the map -- happens inside that window, so none of it is ever
-- on camera. That's the same trick singleplayer uses to stream in a character
-- who is standing on the other side of Los Santos.

Relog = Relog or {}

local IN_THE_AIR = 5

---STREAMING::IS_SAFE_TO_START_PLAYER_SWITCH. FiveM carries this one by hash
---only -- it has no generated Lua name, so `IsSafeToStartPlayerSwitch` is a nil
---global -- hence the direct invoke.
---
---It is a courtesy check, not a gate: if it cannot be asked, say yes and let
---ascend()'s own timeout catch a switch that never gets off the ground. All it
---buys is failing over to the fade immediately instead of after ten seconds.
---@return boolean
local function safeToSwitch()
    local ok, result = pcall(Citizen.InvokeNative, 0x71E7B2E657449AAD, Citizen.ResultAsInteger())
    if not ok or type(result) ~= 'number' then return true end
    return result ~= 0
end

---@return boolean airborne false if the engine refused; the caller must fall back to a fade
local function ascend()
    if IsPlayerSwitchInProgress() then return false end

    AnimpostfxStop('SwitchHUDIn')
    AnimpostfxPlay('SwitchHUDOut', 0, false)

    if not safeToSwitch() then
        DoScreenFadeOut(500)
        while not IsScreenFadedOut() do Wait(0) end
        return false
    end

    SwitchToMultiFirstpart(PlayerPedId(), 0, Config.switchType)

    local deadline = GetGameTimer() + Config.switchTimeoutMs
    while GetPlayerSwitchState() ~= IN_THE_AIR and GetGameTimer() < deadline do
        if not IsPlayerSwitchInProgress() then break end
        Wait(0)
    end

    if GetPlayerSwitchState() == IN_THE_AIR then return true end

    -- Engine wouldn't take it (mid-cutscene, ragdolling, Mount Chiliad, ...).
    -- Hide the swap behind a plain fade rather than doing it in plain sight.
    if IsPlayerSwitchInProgress() then StopPlayerSwitch() end
    AnimpostfxStop('SwitchHUDOut')
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(0) end
    return false
end

---Puts the player ped down at `position` and waits for the ground to exist
---under it, so the descent doesn't land on an unstreamed hole.
---@param position {x: number, y: number, z: number, w: number?}
local function placeAt(position)
    -- Not cache.ped: the model swap above replaced the ped and the cache may
    -- not have caught up yet.
    local ped = PlayerPedId()

    SetEntityCoords(ped, position.x, position.y, position.z, false, false, false, false)
    SetEntityHeading(ped, position.w or 0.0)

    local deadline = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do
        RequestCollisionAtCoord(position.x, position.y, position.z)
        Wait(0)
    end
end

---Swaps the ped to the target character's saved model and outfit. Mirrors
---qbx_core's own previewPed(), which reads the same callback and calls the same
---illenium-appearance export.
---@param citizenId string
local function applyAppearance(citizenId)
    local clothing, model = lib.callback.await('qbx_core:server:getPreviewPedData', false, citizenId)

    -- lib.requestModel raises rather than returning false when the model never
    -- loads; swallowing it here leaves the player as whoever they were, which
    -- illenium-appearance then corrects on its own OnPlayerLoaded pass.
    if not (clothing and model) or not pcall(lib.requestModel, model, 10000) then return end

    SetPlayerModel(cache.playerId, model)
    SetModelAsNoLongerNeeded(model)
    pcall(function() exports['illenium-appearance']:setPedAppearance(PlayerPedId(), json.decode(clothing)) end)
end

---@param airborne boolean whether ascend() actually got the camera up
local function descend(airborne)
    if airborne and IsPlayerSwitchInProgress() then
        SwitchToMultiSecondpart(PlayerPedId())

        local deadline = GetGameTimer() + Config.switchTimeoutMs
        while IsPlayerSwitchInProgress() and GetGameTimer() < deadline do Wait(0) end
        if IsPlayerSwitchInProgress() then StopPlayerSwitch() end
    end

    AnimpostfxStop('SwitchHUDOut')
    if not IsScreenFadedIn() then DoScreenFadeIn(500) end
end

---Comes back down onto whoever the player still is, for when the switch fell
---over partway through.
---@param airborne boolean?
local function abort(airborne)
    descend(airborne or false)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    if IsPlayerSwitchInProgress() then StopPlayerSwitch() end
end)

Relog.switch = {
    ascend = ascend,
    descend = descend,
    abort = abort,
    placeAt = placeAt,
    applyAppearance = applyAppearance,
}
