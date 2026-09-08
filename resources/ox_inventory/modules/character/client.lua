if not lib then return end

--[[
    Feeds the character panel: limb injuries and vitals.

    Injuries come from wasabi_ambulance, which broadcasts its whole
    `PlayerInjury` table on `wasabi_ambulance:syncInjury`. We cache the last
    payload so the panel is correct the moment the inventory opens rather than
    only after the next injury event.

    If wasabi_ambulance is not running the event simply never fires and the
    outline stays healthy — nothing here hard-depends on it.
]]

local BODY_PARTS = {
    head = true,
    neck = true,
    spine = true,
    upper_body = true,
    lower_body = true,
    left_arm = true,
    right_arm = true,
    left_leg = true,
    right_leg = true,
}

local INJURY_TYPES = {
    shot = true,
    stabbed = true,
    beat = true,
    burned = true,
}

local injuries = {}

---Flattens wasabi's `{ [part] = { type = ..., data = { level, bleed } } }`
---into the shape the UI expects. Anything unrecognised is dropped rather than
---forwarded, so a change in wasabi's payload degrades to "no injury" instead
---of throwing in the NUI.
---@param payload any
---@return table
local function normalise(payload)
    local result = {}

    if type(payload) ~= 'table' then return result end

    for part, entry in pairs(payload) do
        if BODY_PARTS[part] and type(entry) == 'table' then
            local data = type(entry.data) == 'table' and entry.data or entry
            local level = tonumber(data.level) or 0

            if level > 0 then
                result[part] = {
                    level = math.min(4, math.floor(level)),
                    bleed = tonumber(data.bleed) or 0,
                    type = INJURY_TYPES[entry.type] and entry.type or 'unknown',
                    label = type(data.label) == 'string' and data.label or nil,
                }
            end
        end
    end

    return result
end

local function pushInjuries()
    SendNUIMessage({ action = 'setInjuries', data = injuries })
end

-- Server -> client. wasabi only sends this on treatment and on initial load,
-- so it cannot be the only source: a freshly sustained injury never triggers it.
RegisterNetEvent('wasabi_ambulance:syncInjury', function(data)
    injuries = normalise(data)
    pushInjuries()
end)

--[[
    Client-side broadcast covering the gap above.

    New injuries are applied inside wasabi's escrowed ChanceInjury(), which only
    mutates its own `PlayerInjury` global and reports upward to the server.
    Because each resource runs its own Lua state, that global is unreachable
    from here, so a watcher appended to wasabi_ambulance's own client.lua polls
    it and re-broadcasts changes as this event.

    That watcher lives in a file wasabi marks `escrow_ignore`, and a
    wasabi_ambulance update will wipe it — see the bridge comment at the bottom
    of `wasabi_ambulance/game/client/client.lua`. If limb injuries ever stop
    appearing in the panel after updating that resource, the watcher is the
    first thing to check.
]]
AddEventHandler('wasabi_ambulance:injuryChanged', function(data)
    injuries = normalise(data)
    pushInjuries()
end)

local function clamp(value)
    return math.max(0, math.min(100, math.floor(value)))
end

--[[
    Read-only probes into wasabi_ambulance.

    The exports we want live in `game/client/functions.lua`, which ships
    escrowed, so there is no way to confirm they exist by reading the resource —
    only by calling them. Every call is therefore wrapped, and a call that
    throws marks that export dead for the rest of the session instead of
    spamming errors twice a second.

    Deliberately not used: `diagnosePlayer`, which opens a context menu as a
    side effect and would pop a UI every refresh tick.
]]
local wasabiExport = {}

local function wasabiRead(name, ...)
    if wasabiExport[name] == false then return nil end
    if GetResourceState('wasabi_ambulance') ~= 'started' then return nil end

    local resource = exports['wasabi_ambulance']
    local args = table.pack(...)

    local ok, result = pcall(function()
        return resource[name](resource, table.unpack(args, 1, args.n))
    end)

    if not ok then
        wasabiExport[name] = false
        return nil
    end

    return result
end

--[[
    Every figure here is derived exactly the way um_hud derives it, so the
    inventory panel and the HUD can never disagree by a point. Hunger, thirst
    and stress are read straight off the QBX statebags the HUD also reads, so
    no dependency on um_hud is introduced.
]]
local function pushVitals()
    local ped = cache.ped or PlayerPedId()
    local maxHealth = GetEntityMaxHealth(ped)

    -- Ped health has a floor of 100, and max health is not always 200 (armour
    -- perks and some peds raise it), so the range is normalised rather than
    -- assuming a 100–200 scale.
    local health = maxHealth > 100 and ((GetEntityHealth(ped) - 100) / (maxHealth - 100)) * 100 or 0

    -- wasabi's check also covers the last-stand/unconscious window that the
    -- native dead check misses, so the player counts as down if either says so.
    local down = IsEntityDead(ped) or wasabiRead('isPlayerDead') == true

    if down then health = 0 end

    SendNUIMessage({
        action = 'setVitals',
        data = {
            health = clamp(health),
            armour = clamp(GetPedArmour(ped)),
            hunger = clamp(LocalPlayer.state.hunger or 100),
            thirst = clamp(LocalPlayer.state.thirst or 100),
            stress = clamp(LocalPlayer.state.stress or 0),
            -- Seconds of breath remaining, scaled to a percentage the same way
            -- the HUD does it. Reads 100 whenever the player is not underwater.
            oxygen = clamp(GetPlayerUnderwaterTimeRemaining(cache.playerId or PlayerId()) * 10),
            down = down and true or false,
            stretcher = wasabiRead('isPlayerUsingStretcher', cache.playerId or PlayerId()) and true or false,
        }
    })
end

-- Only tick while the inventory is actually on screen; ox_inventory publishes
-- that as a statebag, so no polling of its internals is needed.
CreateThread(function()
    while true do
        if LocalPlayer.state.invOpen then
            pushVitals()
            Wait(500)
        else
            Wait(1000)
        end
    end
end)

AddStateBagChangeHandler('invOpen', ('player:%s'):format(cache.serverId), function(_, _, value)
    if not value then return end

    pushInjuries()
    pushVitals()
end)
