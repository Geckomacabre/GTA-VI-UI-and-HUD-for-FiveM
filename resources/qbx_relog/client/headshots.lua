-- Face pictures for the switcher.
--
-- THE ONE SLOT PROBLEM
--
-- REGISTER_PEDHEADSHOT_TRANSPARENT is hardcoded to render into a single texture,
-- pedmugshot_01.ytd. Not "a small pool" -- exactly one. So while any headshot is
-- still registered, every further call fails, which is why an earlier version of
-- this file produced a portrait for the first character and nothing for the
-- rest: it kept every handle registered so the strip could draw the txds
-- directly, and after the first one the slot was gone.
-- (citizenfx/fivem#2611, from a CFX contributor: "RegisterPedheadshotTransparent
-- only has 1 available texture slot to draw to".)
--
-- So the slot is borrowed, never held. Per character: build a ped, photograph
-- it, hand the pixels to the NUI page, unregister immediately, delete the ped.
-- The page copies the texture into a blob it owns and keys it by citizenid, so
-- the portrait outlives the registration and the strip never needs the engine
-- slot again. That is the same shape the CFX contributor's own example uses,
-- and the same reason MugShotBase64 and loaf_lib both convert-then-unregister.
--
-- The alternative would be REGISTER_PEDHEADSHOT_HIRES, which has seven slots
-- but writes BC1 textures with one bit of alpha -- transparency only works
-- there if you stream replacement BC3 ytds over pedmugshot_02..08. Not worth
-- shipping map files for something that runs once per character at warm-up.
--
-- The ped is spawned unnetworked and out of sight below the player rather than
-- made invisible: the renderer photographs the ped as it is drawn, and a ped
-- hidden with SET_ENTITY_VISIBLE photographs as an empty frame. It lives for
-- well under a second either way.
--
-- EVERY character gets a portrait, including ones with no saved appearance --
-- a brand new character, or one made before illenium-appearance was installed,
-- has no row in `playerskins` and qbx_core's getPreviewPedData returns nothing.
-- Those get a default freemode ped of the right gender. A generic face is still
-- a face, and the strip reads as a set of characters instead of a set of holes.

Relog = Relog or {}

-- Which characters the NUI page is holding a portrait for. The image itself
-- lives in the page; this side only needs to know whether to build again.
---@type table<string, boolean>
local captured = {}

-- Set by the page's callback when it has finished copying the texture.
---@type table<string, boolean>
local confirmed = {}

-- Attempts so far per character. A failure is NOT permanent: the single slot
-- may be momentarily taken by another resource, and a character stuck without a
-- face for the rest of the session because of one bad moment is exactly the bug
-- this file is supposed to not have.
---@type table<string, number>
local attempts = {}
local MAX_ATTEMPTS = 3

-- Guards against two prepare() passes running at once (the background warm-up
-- and a strip opened before it finished). That guard is load-bearing here
-- rather than merely tidy: two passes would race for the one texture slot.
local building = false
local activePed

local PED_DROP = 200.0

local GENDER_MODEL = {
    [0] = `mp_m_freemode_01`,
    [1] = `mp_f_freemode_01`,
}

---The page confirming it has its own copy of the pixels. Until this arrives the
---headshot must stay registered, or the texture is recycled out from under the
---fetch.
RegisterNUICallback('captured', function(data, cb)
    if data and data.id then confirmed[data.id] = data.ok == true end
    cb({})
end)

---Somewhere the ped can stand for a moment without anyone seeing it, while
---staying close enough to the player to be streamed in and therefore rendered.
---Straight down usually means underground; when the player is high above the
---ground (aircraft, Chiliad) it means 200m below them instead, which is far
---enough to be a speck if anyone happens to be looking straight down.
---@return number x, number y, number z
local function hiddenSpawn()
    local coords = GetEntityCoords(cache.ped)
    local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z, false, false)
    local underground = (found and groundZ or coords.z) - 50.0

    return coords.x, coords.y, math.min(coords.z - PED_DROP, underground)
end

---Photographs `ped` and gets the pixels into the page, borrowing the single
---headshot slot for as short a time as possible.
---@param ped number
---@param citizenId string
---@return boolean
local function capture(ped, citizenId)
    local handle = RegisterPedheadshotTransparent(ped)

    local deadline = GetGameTimer() + 5000
    while not IsPedheadshotReady(handle) and GetGameTimer() < deadline do Wait(0) end

    if not IsPedheadshotReady(handle) or not IsPedheadshotValid(handle) then
        UnregisterPedheadshot(handle)
        return false
    end

    confirmed[citizenId] = nil
    SendNUIMessage({
        action = 'capture',
        id = citizenId,
        txd = GetPedheadshotTxdString(handle),
    })

    deadline = GetGameTimer() + 5000
    while confirmed[citizenId] == nil and GetGameTimer() < deadline do Wait(0) end

    -- Unconditionally, and before returning: holding this is what broke every
    -- character after the first.
    UnregisterPedheadshot(handle)

    local ok = confirmed[citizenId] == true
    confirmed[citizenId] = nil
    return ok
end

---Builds the portrait for one character, if it doesn't already have one.
---@param citizenId string
---@param gender number? 0 male, 1 female -- only used for the stand-in
---@return boolean
local function build(citizenId, gender)
    if captured[citizenId] then return true end

    attempts[citizenId] = (attempts[citizenId] or 0) + 1
    if attempts[citizenId] > MAX_ATTEMPTS then return false end

    local clothing, model = lib.callback.await('qbx_core:server:getPreviewPedData', false, citizenId)

    -- No saved appearance: fall back to a plain freemode ped of the right
    -- gender so this character still gets a picture.
    if not (clothing and model) then
        clothing, model = nil, GENDER_MODEL[gender] or GENDER_MODEL[0]
    end

    -- lib.requestModel raises rather than returning false when the model never
    -- loads, and a portrait is not worth taking the caller down with it.
    if not pcall(lib.requestModel, model, 10000) then return false end

    local x, y, z = hiddenSpawn()
    local ped = CreatePed(4, model, x, y, z, 0.0, false, false)
    SetModelAsNoLongerNeeded(model)

    if not DoesEntityExist(ped) then return false end

    activePed = ped

    FreezeEntityPosition(ped, true)
    SetEntityCollision(ped, false, false)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)

    if clothing then
        pcall(function() exports['illenium-appearance']:setPedAppearance(ped, json.decode(clothing)) end)
    else
        -- Without this the stand-in wears the model's raw default, which for
        -- the freemode models is a placeholder body rather than clothes.
        SetPedDefaultComponentVariation(ped)
    end

    -- Several frames for the component, prop and head-blend changes to actually
    -- land on the ped before the renderer photographs it. One frame was not
    -- reliably enough -- a portrait would occasionally come back part-dressed.
    Wait(250)

    local ok = capture(ped, citizenId)

    DeletePed(ped)
    activePed = nil

    captured[citizenId] = ok or nil
    return ok
end

---Builds portraits for a whole character list. Strictly one at a time: they are
---queueing for a single engine texture slot, so overlapping them is the failure
---this file exists to avoid.
---@param characters { citizenid: string, gender: number? }[]
local function prepare(characters)
    if building then return end
    building = true

    for i = 1, #characters do
        local character = characters[i]
        character.hasPortrait = build(character.citizenid, character.gender)
    end

    building = false
end

---Drops one character's portrait so the next pass rebuilds it. Called after a
---switch, because the character just left behind may have changed clothes.
---@param citizenId string
local function invalidate(citizenId)
    captured[citizenId] = nil
    attempts[citizenId] = nil
    SendNUIMessage({ action = 'forget', id = citizenId })
end

local function releaseAll()
    for citizenId in pairs(captured) do
        captured[citizenId] = nil
    end
    attempts = {}
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    if activePed and DoesEntityExist(activePed) then DeletePed(activePed) end
    releaseAll()
end)

Relog.headshots = {
    prepare = prepare,
    invalidate = invalidate,
    releaseAll = releaseAll,
}
