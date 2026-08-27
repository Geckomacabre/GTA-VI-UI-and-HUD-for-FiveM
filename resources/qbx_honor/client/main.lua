-- ============================================================================
-- qbx_honor / client
-- Reports rising wanted levels to the server (self-contained honor hook -
-- does not depend on vice_hud's own polling loop) and, whenever the server
-- confirms an honor change, grabs a fresh mugshot and hands it + the
-- devil/angel emoji to vice_hud so it can render a transient toast.
--
-- NUI is owned per-resource in FiveM, and the toast lives in vice_hud's own
-- NUI frame - so this resource never calls SendNUIMessage itself. Instead it
-- calls vice_hud's `ShowHonorToast` client export (see
-- [standalone]/vice_hud/client.lua), which is the only
-- thing allowed to touch vice_hud's NUI page.
-- ============================================================================

-- Printed before anything else can fail, so "did this file even load?" is
-- answerable at a glance in F8.
print('^2[qbx_honor]^7 client/main.lua loaded')

local function trace(fmt, ...)
    if not Config.Debug then return end
    print(('^5[qbx_honor]^7 ' .. fmt):format(...))
end

local currentHonor = Config.DefaultHonor
-- Permanently latches true once the server reports it; see Config's
-- "Unrepairable floor" section. Never manually reset to false in this file.
local currentHonorBroken = false

-- Forward declarations: defined in the vice_hud section at the bottom of this
-- file, but called from the sync handler above it.
local pushToHud, seedHud

-- ============================================================================
-- Client-side read API
-- Lets other client scripts branch on honor without a server round-trip.
-- `currentHonor` is seeded from the server on spawn / resource start and kept
-- current by the honorUpdated event below, so it never goes stale.
-- ============================================================================

---@return number
local function getHonor()
    return currentHonor
end
exports('GetHonor', getHonor)

---Whether this character's honor has permanently latched at the
---unrepairable floor. Never goes back to false once true.
---@return boolean
local function isHonorBroken()
    return currentHonorBroken
end
exports('IsHonorBroken', isHonorBroken)

---@param value number? defaults to the local player's current honor
---@return 'angel' | 'devil' | nil
local function getBadgeTier(value)
    value = tonumber(value) or currentHonor
    if value >= Config.AngelThreshold then return 'angel' end
    if value <= Config.DevilThreshold then return 'devil' end
    return nil
end
exports('GetBadgeTier', getBadgeTier)

-- Server-side trace lines, mirrored here so one console tells the whole story.
RegisterNetEvent('qbx_honor:client:trace', function(line)
    if Config.Debug then print('^5[qbx_honor/server]^7 ' .. tostring(line)) end
end)

RegisterNetEvent('qbx_honor:client:syncHonor', function(value, broken)
    if type(value) ~= 'number' then return end

    currentHonor = value
    if broken == true then currentHonorBroken = true end

    -- Tell vice_hud where honor stands WITHOUT drawing anything. It measures the
    -- delta that fires the +/- indicator against the last value it saw, so it
    -- needs the spawn value; but a player who has not done anything yet should
    -- not have a panel pop up at them for it.
    seedHud(value, currentHonorBroken)
end)

local function requestHonorSync()
    TriggerServerEvent('qbx_honor:server:requestHonor')
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', requestHonorSync)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if LocalPlayer.state.isLoggedIn then requestHonorSync() end
end)

-- ============================================================================
-- vice_hud
--
-- vice_hud draws two distinct things from one push (see its client.lua):
--   * the corner panel - mugshot, tier badge, and the value and reason. Shown
--     when honor moves and hidden again after Config.Honor.holdMs.
--   * the centre-screen +/- indicator - the CHANGE. Drawn only when vice_hud
--     works out a non-zero delta against the last value it saw.
--
-- Neither is permanent, on purpose: honor is a readout you get when something
-- happens, not furniture parked in the corner all session.
--
-- vice_hud derives that delta itself, and picks the tier face itself, as long
-- as we do not pass an emoji. Passing one - which this resource used to do,
-- with the face for the DIRECTION of the change - forced the tier badge to show
-- the wrong face, so the panel disagreed with the player's actual tier.
-- ============================================================================

---Grabs a fresh mugshot. Only ever called when we are about to push to the HUD,
---never polled, so it cannot become a per-tick screenshot cost.
---@return string?
local function getMugshot()
    local ok, mugshot = pcall(function()
        return exports['MugShotBase64']:GetMugShotBase64(PlayerPedId(), true)
    end)

    return ok and mugshot or nil
end

---Feedback that does not depend on the HUD drawing. An honor change the player
---cannot perceive is indistinguishable from a broken honor system, which is
---exactly the trap this resource fell into: the server side worked, nothing was
---visible, and there was no way to tell those apart from inside the game.
---@param honor number the new value
---@param reason string?
---@param delta number?
---Native GTA feed ticker. No NUI, no ox_lib, no vice_hud - if this does not
---show, the client never ran this code.
---@param message string
local function nativeNotify(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, true)
end

local function notifyChange(honor, reason, delta)
    local isLoss = (delta or 0) < 0
    local sign = isLoss and '' or '+'

    if Config.NativeNotify then
        -- ~r~ red for a loss, ~g~ green for a gain: GTA's own text colour codes.
        nativeNotify(('%s%s%s HONOR~s~  %s (now %d)'):format(
            isLoss and '~r~' or '~g~',
            sign,
            tostring(delta or '?'),
            reason or 'Honor changed',
            honor
        ))
    end

    local ok, err = pcall(function()
        exports.qbx_core:Notify(
            ('%s %s%s honor (now %d) - %s'):format(
                isLoss and Config.DevilEmoji or Config.AngelEmoji,
                sign,
                tostring(delta or '?'),
                honor,
                reason or 'Honor changed'
            ),
            isLoss and 'error' or 'success'
        )
    end)

    if not ok then
        -- Never silent: if even the notification cannot be raised, say so.
        print(('^1[qbx_honor] qbx_core:Notify failed: %s^7'):format(tostring(err)))
    end
end

---Draws the panel. Assigns the forward-declared local at the top of this file.
---@param honor number
---@param reason string? the hook label behind the change
---@param delta number? how far honor just moved, for the fallback notification
function pushToHud(honor, reason, delta)
    if type(honor) ~= 'number' then return end

    local drew = false

    if GetResourceState('vice_hud') == 'started' then
        -- No emoji argument on purpose: vice_hud picks the tier face from its
        -- own thresholds, and the direction face for the indicator separately.
        -- currentHonorBroken IS passed explicitly -- unlike the tier, that is
        -- not something vice_hud can derive from the honor number alone (see
        -- Config's "Unrepairable floor" section).
        local ok, err = pcall(function()
            exports['vice_hud']:ShowHonorToast(getMugshot(), honor, nil, reason, currentHonorBroken)
        end)

        drew = ok
        if not ok then trace('^1vice_hud ShowHonorToast failed: %s^7', tostring(err)) end
    else
        trace('^3vice_hud is not started (%s)^7', GetResourceState('vice_hud'))
    end

    -- Notify when asked to, and always when the HUD could not be reached, so a
    -- change is never silent.
    if Config.NotifyOnChange or not drew then
        notifyChange(honor, reason, delta)
    end

    trace('pushToHud done (hud drew: %s)', tostring(drew))
end

---Tells vice_hud where honor stands without drawing anything, so the next real
---change reports a correct delta. Assigns the forward-declared local above.
---@param honor number
---@param broken? boolean
function seedHud(honor, broken)
    if type(honor) ~= 'number' then return end
    if GetResourceState('vice_hud') ~= 'started' then return end

    pcall(function()
        exports['vice_hud']:SetHonorStanding(honor, broken)
    end)
end

RegisterNetEvent('qbx_honor:client:honorUpdated', function(newHonor, previousHonor, reason, broken)
    trace('honorUpdated received: %s -> %s (%s)', tostring(previousHonor), tostring(newHonor), tostring(reason))

    if type(newHonor) ~= 'number' then
        trace('^1ignored: newHonor is not a number^7')
        return
    end

    currentHonor = newHonor
    if broken == true then
        if not currentHonorBroken then trace('honor just hit the floor - permanently broken from here') end
        currentHonorBroken = true
    end

    -- A hook can fire and still leave honor numerically unchanged (already at
    -- Config.MinHonor/MaxHonor). That still deserves a panel - just with no
    -- centre +/- indicator, since there is genuinely no delta to show.
    local delta = type(previousHonor) == 'number' and (newHonor - previousHonor) or 0

    pushToHud(newHonor, reason, delta)
end)

-- vice_hud restarting forgets the standing it was measuring deltas against, so
-- re-seed it. Silently: a resource restart is not an honor event and should not
-- put a panel on screen.
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= 'vice_hud' then return end

    -- Give vice_hud a moment to wire up before talking to it.
    SetTimeout(2000, function()
        if LocalPlayer.state.isLoggedIn then seedHud(currentHonor, currentHonorBroken) end
    end)
end)

-- ============================================================================
-- Wanted-level watcher
-- Polls GetPlayerWantedLevel() (same native vice_hud's cl_hud.lua already polls
-- for its own "cops are searching for you" notification) and reports rising
-- stars to the server. The server, not this client, decides whether the
-- report is plausible and applies the honor penalty.
-- ============================================================================

local lastWanted = 0

CreateThread(function()
    while true do
        Wait(1000)
        local level = GetPlayerWantedLevel(PlayerId())
        if level > lastWanted then
            trace('wanted level rose %d -> %d, reporting', lastWanted, level)
            TriggerServerEvent('qbx_honor:server:wantedIncreased', level, lastWanted)
        end
        lastWanted = level
    end
end)
