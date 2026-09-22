--[[ =========================================================================
     vice_hud — gym stations (server)
     -------------------------------------------------------------------------
     Owns data/gym.json: the places a player can lift free weights. Stations are
     authored in game from em_toolkit > Content builders > Gym stations, which
     reaches this file only through the exports below (em_toolkit does the
     developer check; this re-validates every station it is handed, so a bad
     request cannot write junk into the file every player then loads).

     A station is one target the client draws with ox_target: an exercise, where
     the ped stands and which way it faces, and how close you must be.
     ====================================================================== --]]

local FILE = 'data/gym.json'

local T = Config.Training or {}
local stations = {}

--- Exercises a station may run: the ones flagged for stations, plus the prop
--- ones (bench, chin-ups) so a gym without stock props can still place them.
local function allowed(exercise)
    local ex = T.exercises and T.exercises[exercise]
    return ex ~= nil and (ex.station == true or ex.atProp == true)
end

local function finite(n)
    return type(n) == 'number' and n == n and n > -1e9 and n < 1e9
end

--- Clean a station or reject it. Returns station, nil  or  nil, reason.
local function clean(raw)
    if type(raw) ~= 'table' then return nil, 'bad request' end
    if not allowed(raw.exercise) then return nil, 'unknown exercise' end
    local x, y, z, h = tonumber(raw.x), tonumber(raw.y), tonumber(raw.z), tonumber(raw.h) or 0.0
    if not (finite(x) and finite(y) and finite(z) and finite(h)) then return nil, 'bad position' end
    -- The map is roughly +/-8000; anything wildly outside is a typo, not a place.
    if math.abs(x) > 10000 or math.abs(y) > 10000 or z < -500 or z > 3000 then return nil, 'out of the map' end

    local radius = tonumber(raw.radius) or (T.stationRadius or 1.2)
    if not finite(radius) then radius = T.stationRadius or 1.2 end
    radius = math.max(0.5, math.min(4.0, radius))

    local label = raw.label
    if type(label) ~= 'string' or label == '' then label = nil else label = label:sub(1, 40) end

    return {
        id = type(raw.id) == 'string' and raw.id:match('^gym_%d+$') or nil,
        exercise = raw.exercise,
        x = x, y = y, z = z, h = h % 360.0,
        radius = radius,
        label = label,
    }
end

local function persist()
    return SaveResourceFile(GetCurrentResourceName(), FILE, json.encode(stations), -1)
end

local function broadcast(target)
    TriggerClientEvent('vice_hud:gym:sync', target or -1, stations)
end

local function load()
    local raw = LoadResourceFile(GetCurrentResourceName(), FILE)
    local ok, data = pcall(json.decode, raw or '[]')
    stations = {}
    if ok and type(data) == 'table' then
        for _, s in ipairs(data) do
            local c = clean(s)
            if c and c.id then stations[#stations + 1] = c end
        end
    end
end

local function nextId()
    local highest = 0
    for _, s in ipairs(stations) do highest = math.max(highest, tonumber(s.id:match('%d+')) or 0) end
    return 'gym_' .. (highest + 1)
end

exports('GetGymStations', function() return stations end)

--- Add a station, or replace the one whose id matches.
exports('SaveGymStation', function(raw)
    local c, why = clean(raw)
    if not c then return { ok = false, msg = why } end

    if c.id then
        local found = false
        for i, s in ipairs(stations) do
            if s.id == c.id then stations[i] = c found = true break end
        end
        if not found then return { ok = false, msg = 'no such station' } end
    else
        c.id = nextId()
        stations[#stations + 1] = c
    end

    if not persist() then return { ok = false, msg = 'could not write ' .. FILE } end
    broadcast()
    return { ok = true, id = c.id, station = c }
end)

exports('RemoveGymStation', function(id)
    for i, s in ipairs(stations) do
        if s.id == id then
            table.remove(stations, i)
            if not persist() then return { ok = false, msg = 'could not write ' .. FILE } end
            broadcast()
            return { ok = true }
        end
    end
    return { ok = false, msg = 'no such station' }
end)

RegisterNetEvent('vice_hud:gym:request', function() broadcast(source) end)

load()
