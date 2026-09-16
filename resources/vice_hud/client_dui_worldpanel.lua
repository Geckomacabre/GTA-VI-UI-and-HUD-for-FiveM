-- ============================================================================
-- vice_hud / client_dui_worldpanel
--
-- "Bone-connected" world prompts (ShowWorldActions -- a car door, an item
-- with a resolved bone/offset point, see ox_target/client/main.lua's
-- driveUi) rendered with REAL 3D depth/perspective instead of the existing
-- screen-projected NUI overlay (GetScreenCoordFromWorldCoord + a flat HTML
-- element, see client_overlays.lua's own world-anchoring thread) -- a
-- browser (DUI) rendered onto an actual object's surface in the game world,
-- so it occludes behind geometry, scales with real depth, and has genuine
-- parallax as the player moves, the way the screen-projected version never
-- can.
--
-- ***************************************************************************
-- CARRIER PROP -- UNVERIFIED, OFF BY DEFAULT. READ BEFORE CHANGING THE CONVAR.
-- ***************************************************************************
-- ADD_REPLACE_TEXTURE is GLOBAL: it swaps a texture dictionary/name for
-- EVERY instance of it currently streamed in, not just the one object this
-- file spawns. prop_fridge_01, confirmed via _tools/gtav_reference (not
-- guessed) as a real, freestanding, freely-spawnable Rockstar fridge prop --
-- chosen per the user's own direction (2026-09-11) to use a fridge directly
-- rather than a generic screen carrier, since the whole point of this panel
-- IS the fridge-scene look. Deliberately still just the MODEL, not a
-- verified texture dictionary/name inside it -- prop_fridge_01.ytd likely
-- has several material slots (body paint, handle, glass, ...) and CARRIER_TXN
-- ('prop_fridge_01', same-name-as-model is only a common FiveM convention,
-- not a guarantee) has NOT been confirmed against the real .ytd. Wrong slot
-- name = AddReplaceTexture silently does nothing (no error), so the safe-
-- fallback path below only guards against a bad MODEL name, not a bad
-- texture name -- check in-game that the fridge prop's actual door/front
-- panel shows the DUI content, not some other part of the model, or a
-- default fridge texture with nothing replaced at all. duiWorldActions
-- defaults to OFF (0) regardless, so this file stays fully inert until
-- someone flips it on.
local ENABLED = GetConvarInt('vice_hud:duiWorldActions', 0) == 1
local CARRIER_MODEL = GetConvar('vice_hud:duiCarrierModel', 'prop_fridge_01')
local CARRIER_TXD = GetConvar('vice_hud:duiCarrierTxd', 'prop_fridge_01')
local CARRIER_TXN = GetConvar('vice_hud:duiCarrierTxn', 'prop_fridge_01')

-- The carrier is fridge-shaped (see above), so the DUI panel only makes
-- sense for a target that IS a fridge -- a car door or hood option (the
-- other ShowWorldActions callers, ox_target/client/defaults.lua and qbx_
-- vehiclekeys/client/slimjim.lua) would otherwise spawn a floating fridge
-- next to the vehicle. ShowWorldActions passes the interacted entity's
-- model along specifically so this file can gate on it -- see
-- client_overlays.lua's own comment on that param. Both confirmed real via
-- _tools/gtav_reference (not guessed); prop_fridge_03 is the other common
-- freestanding residential fridge alongside prop_fridge_01.
local ELIGIBLE_MODELS = {
    [joaat('prop_fridge_01')] = true,
    [joaat('prop_fridge_03')] = true,
}

-- Sized to the panel's own on-screen footprint, not a full NUI frame --
-- see dui_worldpanel.html's own comment. 4:3-ish, generous enough for a
-- 2-3 row option list at readable font sizes on a texture this small.
local DUI_WIDTH, DUI_HEIGHT = 512, 384

local duiObject, runtimeTxd, duiHandle
local carrierObject
local setupFailed = false
local visible = false

---One-time setup, deferred to first actual use (see showPanel) rather than
---resource start -- with the feature off by default, this keeps the whole
---file a no-op unless a server operator has actually opted in.
---@return boolean ok
local function ensureSetup()
    if not ENABLED then return false end
    if carrierObject and DoesEntityExist(carrierObject) then return true end
    if setupFailed then return false end

    local modelHash = joaat(CARRIER_MODEL)

    if not IsModelValid(modelHash) then
        setupFailed = true
        lib.print.error(('vice_hud: DUI carrier model "%s" (vice_hud:duiCarrierModel) does not exist -- falling back to the flat NUI world-actions prompt. Verify a real carrier model/texture in-game before enabling vice_hud:duiWorldActions.'):format(CARRIER_MODEL))
        return false
    end

    if not duiObject then
        duiObject = CreateDui(('https://cfx-nui-%s/html/dui_worldpanel.html'):format(GetCurrentResourceName()), DUI_WIDTH, DUI_HEIGHT)
        duiHandle = GetDuiHandle(duiObject)
        runtimeTxd = CreateRuntimeTxd('vice_hud_dui_worldpanel')
        CreateRuntimeTextureFromDuiHandle(runtimeTxd, 'worldpanel', duiHandle)

        -- Global for as long as this resource runs -- see this file's own
        -- header comment on the blast radius that carries.
        AddReplaceTexture(CARRIER_TXD, CARRIER_TXN, 'vice_hud_dui_worldpanel', 'worldpanel')
    end

    lib.requestModel(modelHash)

    carrierObject = CreateObject(modelHash, 0.0, 0.0, -1000.0, false, false, false)

    if not carrierObject or carrierObject == 0 then
        setupFailed = true
        SetModelAsNoLongerNeeded(modelHash)
        lib.print.error('vice_hud: failed to spawn the DUI carrier object -- falling back to the flat NUI world-actions prompt.')
        return false
    end

    SetEntityCollision(carrierObject, false, false)
    SetEntityInvincible(carrierObject, true)
    SetEntityVisible(carrierObject, false, false)
    FreezeEntityPosition(carrierObject, true)
    SetModelAsNoLongerNeeded(modelHash)

    return true
end

---@param message table
local function sendPanelMessage(message)
    if not duiObject then return end
    SendDuiMessage(duiObject, json.encode(message))
end

---Faces the carrier toward the camera every frame while visible (a
---billboard, not a fixed surface normal -- ox_target's option data only
---ever gives this file a point, never a normal vector to align to). Still
---a real 3D object: distance-scaled and occluded by world geometry exactly
---like anything else in the scene, which a screen-projected NUI element
---never was -- a fixed-orientation version could follow later if bone
---normal data ever becomes available.
local function trackCamera(point)
    if not carrierObject or not DoesEntityExist(carrierObject) then return end

    local camCoords = GetFinalRenderedCamCoord()
    local toCam = camCoords - point
    local flatLen = #vec2(toCam.x, toCam.y)
    local heading = flatLen > 0.001 and (math.deg(math.atan(toCam.x, toCam.y)) * -1) or 0.0

    SetEntityCoords(carrierObject, point.x, point.y, point.z, false, false, false, false)
    SetEntityRotation(carrierObject, 0.0, 0.0, heading, 2, false)
end

local trackThread
-- Shared with the tracking thread below, NOT captured as a closure param --
-- a re-render can call showPanel again with an updated point (shouldHide
-- re-resolving a bone/offset position each tick, see ox_target/client/
-- main.lua) while the panel is already up and the thread already running.
-- A captured param would freeze the thread on whatever point the FIRST
-- showPanel call had, forever, silently drifting from the real target the
-- instant it moves.
local currentPoint

---@param options { label: string, glyph: string?, device: string? }[]
---@param point vector3
---@param model number? the target entity's model hash -- see ELIGIBLE_MODELS' own comment
local function showPanel(options, point, model)
    if not model or not ELIGIBLE_MODELS[model] then return false end
    if not ensureSetup() then return false end

    visible = true
    currentPoint = point
    SetEntityVisible(carrierObject, true, false)
    trackCamera(currentPoint)
    sendPanelMessage({ type = 'worldPanel', show = true, options = options })

    if not trackThread then
        trackThread = true
        CreateThread(function()
            while visible do
                trackCamera(currentPoint)
                Wait(0)
            end
            trackThread = nil
        end)
    end

    return true
end

local function hidePanel()
    visible = false
    sendPanelMessage({ type = 'worldPanel', show = false })
    if carrierObject and DoesEntityExist(carrierObject) then
        SetEntityVisible(carrierObject, false, false)
    end
end

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if duiObject then DestroyDui(duiObject) end
    if carrierObject and DoesEntityExist(carrierObject) then DeleteEntity(carrierObject) end
end)

return {
    show = showPanel,
    hide = hidePanel,
}
