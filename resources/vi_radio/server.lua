--[[
    VI Radio - server

    Owns On Demand playback. The client is never trusted with what is playing:
    it asks for a link to be queued, and the server decides what the track is,
    when it started and who hears about it. Everything is keyed by the
    vehicle's network id, so passengers and late joiners land on the same track
    at the same point in it.
]]

if not Config.OnDemand.enabled then return end

if GetResourceState('xsound') ~= 'started' then
    Config.OnDemand.enabled = false
    print('[vi_radio] xsound is not started, On Demand is disabled')
    return
end

local OD = Config.OnDemand

-- state ----------------------------------------------------------------------
-- A session existing at all means the vehicle's On Demand switch is ON. It
-- outlives the queue: switching on with nothing queued is a valid state, and so
-- is playing the last track in the queue and running out.
--
-- sessions[netId] = {
--   queue    = { { url, kind, title, artist, duration }, ... },
--   index    = current track, 0 when nothing is playing,
--   previousStation = the radio station to put back when the switch goes off,
--   token    = bumped on every track change, so a late duration report for the
--              previous track can be thrown away,
--   startedAt/pausedAt = the playback clock, see elapsed(),
-- }
local sessions = {}
local lastCommand = {}   -- [src] = GetGameTimer() of their last command

-- helpers --------------------------------------------------------------------

local function elapsed(s)
    if s.index == 0 or not s.startedAt then return 0.0 end
    if s.paused then return s.pausedAt end
    return (GetGameTimer() - s.startedAt) / 1000.0
end

local function vehicleNetId(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then return nil end
    -- Mirrors the client's Config.DriverOnly check, so a passenger can't
    -- drive the playlist by firing the events directly either.
    if Config.DriverOnly and GetPedInVehicleSeat(veh, -1) ~= ped then return nil end
    return NetworkGetNetworkIdFromEntity(veh)
end

local function vehicleExists(netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    return veh and veh ~= 0 and DoesEntityExist(veh)
end

-- Whoever vehicleNetId accepts (the driver, or anyone with Config.DriverOnly
-- off) may drive its playlist. That is scope, not permission:
-- there is deliberately no job or ace check anywhere in here.
local function sessionFor(src)
    local netId = vehicleNetId(src)
    if not netId then return nil, nil end
    return sessions[netId], netId
end

local function rateLimited(src)
    local now = GetGameTimer()
    if lastCommand[src] and now - lastCommand[src] < OD.commandCooldown then
        return true
    end
    lastCommand[src] = now
    return false
end

local function notify(src, message)
    if message then TriggerClientEvent('vi_radio:od:notify', src, message) end
end

-- broadcast ------------------------------------------------------------------

local function payload(netId, s)
    local queue = {}
    for i, t in ipairs(s.queue) do
        queue[i] = { title = t.title, artist = t.artist, duration = t.duration }
    end

    local track = s.queue[s.index]
    return {
        netId    = netId,
        engaged  = true,
        index    = s.index,
        token    = s.token,
        playing  = track ~= nil,
        paused   = s.paused or false,
        -- audioUrl (once resolveAudioStream fills it in) is a plain audio
        -- stream URL, playable -- and filterable -- as a direct file; url is
        -- the original youtube.com link, used until/unless that resolves.
        url      = track and (track.audioUrl or track.url) or nil,
        title    = track and track.title or nil,
        artist   = track and track.artist or nil,
        duration = track and track.duration or nil,
        position = elapsed(s),
        queue    = queue,
    }
end

-- Sent to everyone: any player may end up in earshot of any vehicle, and the
-- client only starts audio for vehicles that are actually near it.
local function broadcast(netId, target)
    local s = sessions[netId]
    if not s then
        TriggerClientEvent('vi_radio:od:state', target or -1, { netId = netId, playing = false, gone = true })
        return
    end
    TriggerClientEvent('vi_radio:od:state', target or -1, payload(netId, s))
end

-- playback -------------------------------------------------------------------

--[[
    Resolves a YouTube link to a raw playable audio-stream URL via a public
    Piped API instance (no API key, no yt-dlp binary/subprocess on this
    machine -- FXServer's Lua sandbox has no os.execute/io.popen for that
    anyway). Once a track plays through a resolved stream URL instead of the
    embedded YouTube iframe, xsound treats it as a plain audio file and the
    lowpass/muffle filter (SoundPlayer.js's initLowpass) can actually attach
    to it -- the embedded iframe's audio is a cross-origin video player, which
    a Web Audio filter node can never reach.

    Community-run instances, independent of anything in this codebase -- can
    go down or rate-limit on their own schedule. Tried in order; if every one
    fails, `callback(nil)` and the caller falls back to the plain youtube.com
    URL (the original iframe-embed behaviour, unfiltered but always works).
]]
local PIPED_INSTANCES = {
    'https://pipedapi.kavin.rocks',
    'https://pipedapi.adminforge.de',
    'https://api.piped.yt',
}

local function extractVideoId(url)
    return url and url:match('[?&]v=([%w_%-]+)')
end

local function resolveAudioStream(track, callback, instanceIndex)
    instanceIndex = instanceIndex or 1
    local instance = PIPED_INSTANCES[instanceIndex]
    local videoId = extractVideoId(track.url)
    if not instance or not videoId then
        callback(nil)
        return
    end

    PerformHttpRequest(('%s/streams/%s'):format(instance, videoId), function(status, body)
        if status ~= 200 or not body then
            resolveAudioStream(track, callback, instanceIndex + 1)
            return
        end

        local ok, data = pcall(json.decode, body)
        if not ok or type(data) ~= 'table' or type(data.audioStreams) ~= 'table' then
            resolveAudioStream(track, callback, instanceIndex + 1)
            return
        end

        -- Highest-bitrate audio-only stream on offer.
        local best = nil
        for _, stream in ipairs(data.audioStreams) do
            if type(stream.url) == 'string'
               and (not best or (tonumber(stream.bitrate) or 0) > (tonumber(best.bitrate) or 0)) then
                best = stream
            end
        end
        callback(best and best.url or nil)
    end, 'GET')
end

local function startTrack(netId, s, i)
    s.index     = i
    s.token     = (s.token or 0) + 1
    s.startedAt = GetGameTimer()
    s.paused    = false
    s.pausedAt  = 0.0

    local track = s.queue[i]
    -- Broadcast immediately with the plain YouTube URL (the pre-existing
    -- iframe-embed behaviour -- nobody waits in silence for the resolver),
    -- then swap to a resolved, filterable stream URL once/if one shows up.
    broadcast(netId)

    if track and track.kind == 'youtube' and not track.audioUrl and not track.audioResolveFailed then
        resolveAudioStream(track, function(streamUrl)
            -- The queue may have moved on (skipped, removed, session ended)
            -- by the time an HTTP callback lands -- only act if this track
            -- is still the one actually playing.
            if sessions[netId] ~= s or s.index ~= i then return end

            if streamUrl then
                track.audioUrl = streamUrl
            else
                track.audioResolveFailed = true
                return -- stays on the already-playing iframe embed, nothing to swap to
            end

            -- Bumping the token forces the client to treat this as a fresh
            -- track (see client.lua's `if not prev or prev.token ~= data.token
            -- then sess.restart = true end`) so it tears down the iframe
            -- embed and restarts on the resolved stream instead of just
            -- updating position on the sound that's already playing. This is
            -- a real, audible restart-from-zero, once, a second or two into
            -- a YouTube track -- the trade-off for the filter being able to
            -- attach at all.
            s.token     = (s.token or 0) + 1
            s.startedAt = GetGameTimer()
            broadcast(netId)
        end)
    end
end

-- `restore` is the station to hand the vehicle radio back to, and is only sent
-- when the switch was deliberately turned off. A vehicle that simply stopped
-- existing restores nothing.
local function stopSession(netId, restore)
    sessions[netId] = nil
    TriggerClientEvent('vi_radio:od:state', -1, {
        netId   = netId,
        gone    = true,
        playing = false,
        restore = restore,
    })
end

-- Nothing playing is a state, not the end of the session: the switch stays on
-- and the panel stays useful, there is just silence until something is queued.
local function idle(netId, s)
    s.index    = 0
    s.paused   = false
    s.pausedAt = 0.0
    s.token    = (s.token or 0) + 1
    broadcast(netId)
end

local function advance(netId, s, dir)
    local nextIndex = s.index + (dir or 1)
    if nextIndex < 1 then nextIndex = 1 end
    if nextIndex > #s.queue then
        idle(netId, s)
        return
    end
    startTrack(netId, s, nextIndex)
end

-- titles ---------------------------------------------------------------------
-- YouTube's oEmbed endpoint needs no key and returns the video title and the
-- channel name, which is as close to "title / artist" as this gets.

local function fetchTitle(netId, track)
    if not OD.fetchTitles or track.kind ~= 'youtube' then return end

    PerformHttpRequest('https://www.youtube.com/oembed?format=json&url=' .. track.url, function(status, body)
        if status ~= 200 or not body then return end

        local ok, data = pcall(json.decode, body)
        if not ok or type(data) ~= 'table' then return end

        if type(data.title) == 'string' then track.title = data.title end
        if type(data.author_name) == 'string' then track.artist = data.author_name end

        if sessions[netId] then broadcast(netId) end
    end, 'GET')
end

-- events ---------------------------------------------------------------------

-- The switch itself. Turning it on creates the session -- that is what "on"
-- means -- and remembers the station to put back when it goes off again.
RegisterNetEvent('vi_radio:od:engage', function(previousStation)
    local src = source
    if rateLimited(src) then return end

    local netId = vehicleNetId(src)
    if not netId then return notify(src, 'You have to be in a vehicle') end

    if sessions[netId] then
        broadcast(netId)
        return
    end

    if type(previousStation) ~= 'string' or #previousStation > 64
       or not previousStation:match('^[%w_]+$') then
        previousStation = 'OFF'
    end

    sessions[netId] = {
        queue = {}, index = 0, token = 0,
        paused = false, pausedAt = 0.0,
        previousStation = previousStation,
    }
    broadcast(netId)
end)

-- `restore` is false when the player switched off by picking a radio station:
-- they have already chosen what they want to hear, so putting the old station
-- back would undo it.
RegisterNetEvent('vi_radio:od:disengage', function(restore)
    local src = source
    if rateLimited(src) then return end

    local s, netId = sessionFor(src)
    if not s then return end

    stopSession(netId, restore ~= false and s.previousStation or nil)
end)

RegisterNetEvent('vi_radio:od:add', function(link, playNow)
    local src = source
    if rateLimited(src) then return end

    local netId = vehicleNetId(src)
    if not netId then return notify(src, 'You have to be in a vehicle') end

    local url, kind = Config.NormalizeUrl(link)
    if not url then return notify(src, kind) end

    -- /ondemand <url> can queue something without the switch having been
    -- flipped first, so this still creates the session when there is none.
    local s = sessions[netId]
    if not s then
        s = {
            queue = {}, index = 0, token = 0,
            paused = false, pausedAt = 0.0,
            previousStation = 'OFF',
        }
        sessions[netId] = s
    end

    if #s.queue >= OD.queueLimit then
        return notify(src, ('The queue is full (%d tracks)'):format(OD.queueLimit))
    end

    local track = {
        url   = url,
        kind  = kind,
        title = kind == 'youtube' and 'YouTube' or (url:match('([^/]+)$') or 'Track'),
    }
    s.queue[#s.queue + 1] = track

    if playNow or s.index == 0 then
        startTrack(netId, s, #s.queue)
    else
        broadcast(netId)
    end

    fetchTitle(netId, track)
end)

RegisterNetEvent('vi_radio:od:remove', function(i)
    local src = source
    if rateLimited(src) then return end
    if type(i) ~= 'number' then return end

    local s, netId = sessionFor(src)
    if not s then return end

    i = math.floor(i)
    if not s.queue[i] then return end

    table.remove(s.queue, i)

    if #s.queue == 0 then
        idle(netId, s)
    elseif i == s.index then
        -- The track that was playing is gone: play whatever slid into its place.
        startTrack(netId, s, math.min(i, #s.queue))
    else
        if i < s.index then s.index = s.index - 1 end
        broadcast(netId)
    end
end)

RegisterNetEvent('vi_radio:od:skip', function(dir)
    local src = source
    if rateLimited(src) then return end

    local s, netId = sessionFor(src)
    if not s or s.index == 0 then return end

    advance(netId, s, dir == -1 and -1 or 1)
end)

RegisterNetEvent('vi_radio:od:pause', function()
    local src = source
    if rateLimited(src) then return end

    local s, netId = sessionFor(src)
    if not s or s.index == 0 then return end

    if s.paused then
        s.startedAt = GetGameTimer() - math.floor(s.pausedAt * 1000)
        s.paused = false
    else
        s.pausedAt = elapsed(s)
        s.paused = true
    end
    broadcast(netId)
end)

-- Stop clears the queue but leaves the switch on. Turning the switch off is
-- vi_radio:od:disengage, which is a different thing to want.
RegisterNetEvent('vi_radio:od:stop', function()
    local src = source
    if rateLimited(src) then return end

    local s, netId = sessionFor(src)
    if not s then return end

    s.queue = {}
    idle(netId, s)
end)

-- A listener tells us how long the current track is. Nothing on the server can
-- know that, so it comes from whoever is actually playing it -- but only for
-- the track playing right now, and only if the number is plausible.
RegisterNetEvent('vi_radio:od:duration', function(netId, token, seconds)
    if type(netId) ~= 'number' or type(token) ~= 'number' or type(seconds) ~= 'number' then return end

    local s = sessions[netId]
    if not s or s.token ~= token or s.index == 0 then return end
    if seconds <= 0 or seconds > 21600 then return end

    local track = s.queue[s.index]
    if not track or track.duration then return end

    track.duration = seconds
    broadcast(netId)
end)

RegisterNetEvent('vi_radio:od:sync', function()
    local src = source
    for netId, s in pairs(sessions) do
        TriggerClientEvent('vi_radio:od:state', src, payload(netId, s))
    end
end)

-- upkeep ---------------------------------------------------------------------
-- Advance finished tracks, drop sessions whose vehicle no longer exists, and
-- rebroadcast the playback position so listeners cannot drift far.

CreateThread(function()
    local lastBroadcast = 0

    while true do
        Wait(1000)

        local now = GetGameTimer()
        local resend = now - lastBroadcast >= OD.broadcastInterval
        if resend then lastBroadcast = now end

        for netId, s in pairs(sessions) do
            if not vehicleExists(netId) then
                stopSession(netId)
            else
                local track = s.queue[s.index]
                if track and track.duration and not s.paused and elapsed(s) >= track.duration then
                    advance(netId, s, 1)
                elseif resend then
                    broadcast(netId)
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    lastCommand[source] = nil
end)

-- exports --------------------------------------------------------------------

exports('GetOnDemandSession', function(netId)
    local s = sessions[netId]
    return s and payload(netId, s) or nil
end)

exports('StopOnDemand', function(netId)
    if sessions[netId] then stopSession(netId) end
end)
