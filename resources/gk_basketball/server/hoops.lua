--[[
    Hoop storage. The list lives in data/hoops.json so admins can place rims in-game
    without editing config and without a database table.
]]

local FILE = 'data/hoops.json'

BB.hoops = {}

local function save()
    SaveResourceFile(GetCurrentResourceName(), FILE, json.encode(BB.hoops, { indent = true }), -1)
end

local function load()
    local raw = LoadResourceFile(GetCurrentResourceName(), FILE)

    if not raw or raw == '' then
        BB.hoops = {}
        return
    end

    local ok, decoded = pcall(json.decode, raw)

    if not ok or type(decoded) ~= 'table' then
        print('^1[gk_basketball]^7 data/hoops.json is not valid JSON — starting with no hoops')
        BB.hoops = {}
        return
    end

    BB.hoops = decoded
    print(('^2[gk_basketball]^7 loaded %s hoop(s)'):format(#BB.hoops))
end

--- @return table hoops with vector3 coords, ready for BB.buildCourts
function BB.hoopList()
    local list = {}

    for _, hoop in ipairs(BB.hoops) do
        list[#list + 1] = {
            id     = hoop.id,
            court  = hoop.court,
            team   = hoop.team,
            coords = BB.vec(hoop.coords),
        }
    end

    return list
end

function BB.findHoop(id)
    for _, hoop in ipairs(BB.hoops) do
        if hoop.id == id then return hoop end
    end
end

--[[
    Publishes the hoops to every client.

    Global state rather than a broadcast plus a callback. A state bag replicates on
    its own and a client reading it at start gets whatever is already there, which
    replaces both halves of the old arrangement: the -1 event on every change, and
    the fetch the client had to retry ten times because it could come up before the
    server had registered the callback. That whole failure mode is gone.

    Assigned whole, every time. State bags only re-serialize on a direct set, so
    mutating BB.hoops in place would update the server's copy and replicate
    nothing at all.
]]
local function publish()
    GlobalState[BB.STATE_HOOPS] = BB.hoops
end

local function broadcast()
    BB.courts = BB.buildCourts(BB.hoopList())
    publish()
end

local function canManage(source)
    if source == 0 then return true end

    if not IsPlayerAceAllowed(source, Config.ManageAce) then
        TriggerClientEvent('gk_basketball:notify', source, 'You do not have permission to manage hoops.', 'error')
        return false
    end

    return true
end

--[[
    Diagnostic for "I get told I have no permission".

    Getting a reply at all proves the resource is running. The output then shows
    whether the ace actually resolved for you, and which identifiers the server sees
    you as, which is what an add_principal line has to match.
]]
RegisterCommand('bball_perms', function(source)
    local ace = Config.ManageAce

    if source == 0 then
        print(('[gk_basketball] running. Manage ace is "%s". Run this in-game to test a player.'):format(ace))
        return
    end

    local allowed = IsPlayerAceAllowed(source, ace)

    print(('^2[gk_basketball]^7 perms check for %s (id %s): %s = %s')
        :format(GetPlayerName(source) or '?', source, ace, tostring(allowed)))

    for i = 0, GetNumPlayerIdentifiers(source) - 1 do
        print('    ' .. GetPlayerIdentifier(source, i))
    end

    TriggerClientEvent('gk_basketball:notify', source, ((allowed
        and 'Resource running. You DO hold %s.')
        or 'Resource running, but you do NOT hold %s. Identifiers printed to the server console.')
        :format(ace), allowed and 'success' or 'error')
end, false)

RegisterNetEvent('gk_basketball:saveHoop', function(courtId, coords, team)
    local source = source
    if not canManage(source) then return end

    if type(courtId) ~= 'string' or courtId == '' or type(coords) ~= 'table' then return end
    if not tonumber(coords.x) or not tonumber(coords.y) or not tonumber(coords.z) then return end

    -- Court ids end up in event names and file keys, so keep them tame.
    courtId = courtId:lower():gsub('[^%w_%-]', '')
    if courtId == '' then return end

    local id = ('%s_%s'):format(courtId, #BB.hoops + 1)
    while BB.findHoop(id) do
        id = ('%s_%s'):format(courtId, math.random(1000, 9999))
    end

    BB.hoops[#BB.hoops + 1] = {
        id     = id,
        court  = courtId,
        team   = (team == 'home' or team == 'away') and team or nil,
        coords = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 },
    }

    save()
    broadcast()

    TriggerClientEvent('gk_basketball:notify', source,
        ('Saved hoop %s on court "%s".'):format(id, courtId), 'success')
end)

RegisterNetEvent('gk_basketball:deleteHoop', function(id)
    local source = source
    if not canManage(source) then return end

    for index, hoop in ipairs(BB.hoops) do
        if hoop.id == id then
            table.remove(BB.hoops, index)
            save()
            broadcast()
            TriggerClientEvent('gk_basketball:notify', source, ('Removed hoop %s.'):format(id), 'success')
            return
        end
    end

    TriggerClientEvent('gk_basketball:notify', source, 'That hoop no longer exists.', 'error')
end)

load()
BB.courts = BB.buildCourts(BB.hoopList())
publish()
