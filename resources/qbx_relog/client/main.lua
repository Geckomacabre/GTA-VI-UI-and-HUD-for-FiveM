Relog = Relog or {}

local busy = false
local wheelHeld = false

---@type {citizenId: string, previousCitizenId: string?, airborne: boolean}?
local switching

--#region Helpers

---@return string?
local function ownCitizenId()
    return exports.qbx_core:GetPlayerData()?.citizenid
end

---qbx_core pops its multicharacter screen from its own playerLoggedOut handler,
---which fires before this resource gets a chance to log the target character
---in. The export patched into qbx_core's client/character.lua suppresses that
---once. Without it the picker would open on top of the switch, so refuse rather
---than leave the player in a half-broken state.
---@return boolean available
local function skipCharacterSelect()
    local ok = pcall(function() exports.qbx_core:SkipNextCharacterSelect() end)

    if not ok then
        lib.print.error("qbx_core has no SkipNextCharacterSelect export. The patch is in qbx_core's client/character.lua but the running copy predates it -- restart qbx_core (or the server) to pick it up.")
        exports.qbx_core:Notify('Character switching is unavailable until the server is restarted.', 'error')
    end

    return ok
end

---Confirms intent for the full relog back to the character picker.
---@return boolean confirmed
local function confirmRelog()
    local stayStill = Config.delay > 0 and ('\n\nYou must stay still for %d seconds.'):format(Config.delay) or ''

    return lib.alertDialog({
        header = 'Relog',
        content = 'Return to character selection?' .. stayStill,
        centered = true,
        cancel = true,
    }) == 'confirm'
end

---@param seconds number
---@param label string
---@return boolean completed
local function waitOutDelay(seconds, label)
    if seconds <= 0 then return true end

    return lib.progressBar({
        duration = seconds * 1000,
        label = label,
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, combat = true, car = true },
    })
end

--#endregion

--#region Character list

---Mirrors qbx_honor's getBadgeTier. The thresholds live in this resource's
---config for the same reason vice_hud keeps its own copy: a client cannot read
---another resource's Lua state, and one callback per character per open to ask
---the server for a comparison against two constants is not worth it.
---@param honor number
---@return 'angel'|'devil'|nil
local function honorTierOf(honor)
    if honor >= Config.honorAngelAt then return 'angel' end
    if honor <= Config.honorDevilAt then return 'devil' end
    return nil
end

---@param character table
---@return string
local function initialsOf(character)
    local first = character.charinfo?.firstname or '?'
    local last = character.charinfo?.lastname or '?'
    return (first:sub(1, 1) .. last:sub(1, 1)):upper()
end

---@type table[]?
local characterCache

---Every character on this license, current one included -- singleplayer shows
---the character you are already playing in the wheel too, just not selectable.
---@return table[]
local function fetchCharacters()
    local characters, amount = lib.callback.await('qbx_core:server:getCharacters', false)
    local own = ownCitizenId()
    local list = {}

    for i = 1, amount do
        local character = characters[i]
        if character then
            local honor = character.metadata?.honor or Config.honorDefault

            list[#list + 1] = {
                citizenid = character.citizenid,
                label = ('%s %s'):format(character.charinfo?.firstname or '?', character.charinfo?.lastname or '?'),
                initials = initialsOf(character),
                job = character.job?.label,
                isCurrent = character.citizenid == own,
                -- 0 male / 1 female, as qbx_core's character creator writes it.
                -- Only used to pick a stand-in model for the portrait when a
                -- character has never saved an appearance.
                gender = character.charinfo?.gender or 0,
                honor = honor,
                honorTier = honorTierOf(honor),
                -- Latches at Config.honorMin and never clears; vice_hud draws
                -- the badge grey and cracked from then on, so this does too.
                honorBroken = character.metadata?.honorBroken == true,
            }
        end
    end

    -- Stable slot order between opens, so muscle memory works.
    table.sort(list, function(a, b) return a.citizenid < b.citizenid end)

    -- Nothing about portraits is carried across a refresh any more: the NUI
    -- page owns them, keyed by citizenid, so a re-fetch cannot blank the strip
    -- back to initials the way it could when the txd handle lived out here.

    characterCache = list
    return list
end

--#endregion

--#region Wheel

local function openWheel()
    if busy or Relog.wheel.isOpen() then return end

    -- The strip has to be up on the same frame the hold threshold passes, so it
    -- opens on the last known list and refreshes behind itself. A round trip to
    -- the server here would cost the whole opening beat on a short hold.
    local characters = characterCache
    if not characters then
        -- Cold cache (warm-up hasn't finished, or this is a fresh restart under
        -- a player already in the world). Blocking here is the only option, but
        -- the key may well be back up by the time it returns -- so treat a hold
        -- that survives the round trip as still wanting the strip, and one that
        -- doesn't as a tap that primed the cache for next time.
        characters = fetchCharacters()
        if not wheelHeld then return end
    else
        CreateThread(fetchCharacters)
    end

    if #characters < 2 then
        exports.qbx_core:Notify('You have no other characters to switch to.', 'error')
        return
    end

    -- Portraits build in the background too; slots draw initials until their
    -- face is ready, and stay cached after that.
    CreateThread(function() Relog.headshots.prepare(characters) end)

    local index = Relog.wheel.run(characters, function() return wheelHeld end)
    local choice = index and characters[index]

    if not choice or choice.isCurrent then return end

    TriggerServerEvent('qbx_relog:server:requestSwitch', choice.citizenid)
end

RegisterCommand('+qbx_relog_wheel', function()
    if wheelHeld or busy then return end
    wheelHeld = true

    CreateThread(function()
        local opensAt = GetGameTimer() + Config.wheelHoldMs

        -- A tap does nothing; only a hold opens the wheel.
        while wheelHeld and GetGameTimer() < opensAt do Wait(0) end
        if not wheelHeld then return end

        openWheel()
    end)
end, false)

RegisterCommand('-qbx_relog_wheel', function()
    wheelHeld = false
end, false)

RegisterKeyMapping('+qbx_relog_wheel', 'Switch character (hold)', 'keyboard', Config.wheelKey)

--#endregion

--#region Relog / switch flow

RegisterNetEvent('qbx_relog:client:begin', function(citizenId, targetName)
    if GetInvokingResource() then return end
    if busy then return end

    busy = true

    -- Checked here rather than server side: vehicle state natives are client only.
    if Config.blockInVehicle and IsPedInAnyVehicle(cache.ped, false) then
        exports.qbx_core:Notify('You cannot relog while in a vehicle.', 'error')
        TriggerServerEvent('qbx_relog:server:cancel')
        busy = false
        return
    end

    local confirmed
    if citizenId then
        -- No confirmation prompt on the wheel path: you already committed by
        -- pointing at a face and letting go. The delay is the anti-combat-log
        -- check, and cancelling it backs out.
        confirmed = waitOutDelay(Config.switchDelay, ('Switching to %s...'):format(targetName or 'character'))
    else
        confirmed = confirmRelog() and waitOutDelay(Config.delay, 'Logging out...')
    end

    if not confirmed then
        TriggerServerEvent('qbx_relog:server:cancel')
        busy = false
        return
    end

    if citizenId then
        if not skipCharacterSelect() then
            TriggerServerEvent('qbx_relog:server:cancel')
            busy = false
            return
        end

        switching = {
            citizenId = citizenId,
            previousCitizenId = ownCitizenId(),
            airborne = Relog.switch.ascend(),
        }
    end

    TriggerServerEvent('qbx_relog:server:confirm')

    -- The switch path stays busy until the server comes back with a spawn or a
    -- failure; the plain relog is done here and qbx_core takes over.
    if not citizenId then
        busy = false
        return
    end

    -- If neither reply ever lands the player would be stuck in the clouds with
    -- the wheel locked out for the rest of the session. Come back down and hand
    -- them the picker instead.
    local stranded = switching
    CreateThread(function()
        Wait(Config.switchTimeoutMs * 3)
        if switching ~= stranded then return end

        switching = nil
        lib.print.error('character switch never came back from the server; falling back to the character picker')
        Relog.switch.abort(stranded.airborne)
        pcall(function() exports.qbx_core:OpenCharacterSelect() end)
        busy = false
    end)
end)

---@param position {x: number, y: number, z: number, w: number}
RegisterNetEvent('qbx_relog:client:quickSwitchSpawn', function(position)
    if GetInvokingResource() then return end

    local pending = switching
    switching = nil
    if not pending then return end

    -- Still parked in the clouds for all of this.
    Relog.switch.applyAppearance(pending.citizenId)
    Relog.switch.placeAt(position)

    TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
    TriggerEvent('QBCore:Client:OnPlayerLoaded')

    -- illenium-appearance reloads the outfit asynchronously off OnPlayerLoaded
    -- and swaps the player model to do it, which replaces the ped again. Hold
    -- up here until that has settled, then re-place the ped that came out of it.
    Wait(Config.switchSkyHoldMs)
    Relog.switch.placeAt(position)

    Relog.switch.descend(pending.airborne)

    -- Both characters may look different next time -- the one just parked could
    -- have changed clothes since its portrait was taken, and the one now in
    -- play is about to.
    Relog.headshots.invalidate(pending.citizenId)
    if pending.previousCitizenId then
        Relog.headshots.invalidate(pending.previousCitizenId)
    end
    characterCache = nil

    busy = false
end)

RegisterNetEvent('qbx_relog:client:switchFailed', function()
    if GetInvokingResource() then return end

    local pending = switching
    switching = nil

    Relog.switch.abort(pending and pending.airborne)

    -- The old character is logged out server side and the picker was told to
    -- skip itself once, so nothing else will bring it up. Ask for it directly.
    pcall(function() exports.qbx_core:OpenCharacterSelect() end)

    busy = false
end)

--#endregion

--#region Warm-up

-- The first hold of the key has to open on something. Without a warmed cache
-- openWheel() has to make a blocking round trip to the server, and if the key
-- comes up during it the strip never appears at all -- which reads exactly like
-- the feature being broken.
--
-- Two triggers, because either one alone leaves a hole: OnPlayerLoaded doesn't
-- fire when the resource is restarted under a player who is already in, and a
-- resource-start warm-up doesn't fire for someone who connects later.
local function warmUp()
    CreateThread(function()
        -- Wait for a character to actually be loaded before asking the server
        -- about its siblings; on a fresh connect this file runs long before the
        -- player picks anyone.
        local deadline = GetGameTimer() + 120000
        while not ownCitizenId() and GetGameTimer() < deadline do Wait(1000) end
        if not ownCitizenId() then return end

        -- Long enough after the spawn rush that a handful of ped creations and
        -- model loads aren't competing with everything else streaming in.
        Wait(10000)
        if busy or Relog.wheel.isOpen() then return end

        local characters = fetchCharacters()
        if #characters >= 2 then Relog.headshots.prepare(characters) end
    end)
end

AddEventHandler('QBCore:Client:OnPlayerLoaded', warmUp)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= cache.resource then return end
    warmUp()
end)

--#endregion
