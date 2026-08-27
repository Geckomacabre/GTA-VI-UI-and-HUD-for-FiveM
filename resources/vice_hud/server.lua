--[[ =========================================================================
     vice_hud — server-wide layout
     -------------------------------------------------------------------------
     Everything /movehud tunes is stored per player, which is the right home for
     a preference and the wrong home for a mistake: when the shipped placement
     is off, it is off for every player on the server and each of them has to
     fix it themselves.

     /hudpublish (client) sends the running player's tuned layout here. If they
     hold the ACE in Config.PublishAce it is written to layout.json inside this
     resource and mirrored into GlobalState, from where:

       · every connected client re-runs its merge immediately, and
       · every client that connects later picks it up on join, and
       · the ox_lib notification hook reads the popup placement, in EVERY
         resource, without any of them knowing vice_hud exists.

     Nothing stored here is measured in pixels. Offsets are percentages of the
     screen, so one published layout is correct on 1080p, 1440p and ultrawide
     alike, and no element is ever resized to fit a display.
     ====================================================================== --]]

local STORE = 'layout.json'

-- Bumped if the shape of the stored file ever changes. A file from a different
-- version is ignored rather than half-applied.
local STORE_VERSION = 1

local published = nil

--- The eight anchors ox_lib accepts. An unrecognised one makes ox_lib drop the
--- notification silently, so a bad value must never reach GlobalState.
local NOTIFY_ANCHORS = {
    ['top-left'] = true, ['top'] = true, ['top-right'] = true,
    ['center-left'] = true, ['center-right'] = true,
    ['bottom-left'] = true, ['bottom'] = true, ['bottom-right'] = true,
}

--- Clamp a nudge to something a screen can plausibly hold. A published layout
--- reaches everyone, so a typo here is everyone's problem.
---
--- Kept in step with POS_PROPS in html/app.js: a value the editor lets you set
--- must not be quietly narrowed on the way through the server, or publishing
--- would move an element that looked right on the tuner's screen.
local function pct(v)
    v = tonumber(v) or 0.0
    if v ~= v then return 0.0 end            -- NaN
    return math.max(-500.0, math.min(500.0, v))
end

local function sanitiseNotify(n)
    if type(n) ~= 'table' then return nil end
    local anchor = NOTIFY_ANCHORS[n.anchor] and n.anchor or 'top-right'
    return { anchor = anchor, x = pct(n.x), y = pct(n.y) }
end

--- Copy only the fields a layout entry is allowed to carry.
---
--- The payload comes from a client, so it is untrusted input even when the
--- sender is an admin: without this, anything at all could be dropped into a
--- table that every other player then applies to their HUD.
local NUMERIC_KEYS = { 'x', 'y', 'sx', 'sy', 's', 'fs', 'ic', 'fw', 'ls', 'op', 'rad', 'sp' }
local STRING_KEYS = { 'ff', 'al', 'sm', 'anchor' }

local function sanitiseEntry(o)
    if type(o) ~= 'table' then return nil end
    local e = {}
    for _, k in ipairs(NUMERIC_KEYS) do
        if o[k] ~= nil then
            local n = tonumber(o[k])
            -- x/y are placements and get clamped; the rest are scales and
            -- typography, which have their own ranges enforced in the editor.
            if n and n == n then e[k] = (k == 'x' or k == 'y') and pct(n) or n end
        end
    end
    for _, k in ipairs(STRING_KEYS) do
        if type(o[k]) == 'string' and #o[k] <= 96 then e[k] = o[k] end
    end
    if e.anchor and not NOTIFY_ANCHORS[e.anchor] then e.anchor = nil end
    return e
end

local function sanitise(payload)
    if type(payload) ~= 'table' then return nil end
    local out = { v = STORE_VERSION, offsets = {}, map = nil, notify = nil }

    if type(payload.offsets) == 'table' then
        local n = 0
        for name, o in pairs(payload.offsets) do
            -- Element names are keys in a table every client reads, so they are
            -- held to the same shape the editor uses.
            if type(name) == 'string' and #name <= 32 and name:match('^[%a][%w_]*$') and n < 64 then
                local e = sanitiseEntry(o)
                if e then out.offsets[name] = e; n = n + 1 end
            end
        end
    end

    -- The map state is passed through as-is apart from its type check: the
    -- client validates every field against MAP_STATE_VERSION on the way in,
    -- and re-listing a dozen minimap keys here would just be a second place to
    -- forget to update.
    if type(payload.map) == 'table' then out.map = payload.map end

    -- Per-aspect map profiles.
    --
    -- MERGED with what is already published rather than replacing it, which is
    -- the only behaviour that lets an admin tune 16:9 on Monday and ultrawide
    -- on Friday and end up with both. A publish only ever overwrites the bucket
    -- it was measured on.
    --
    -- The bucket NAME is recomputed here from the reported aspect rather than
    -- trusted from the payload: a client could otherwise file its map under any
    -- string it liked, including one every other player then matches against.
    out.maps = {}
    if published and type(published.maps) == 'table' then
        for name, m in pairs(published.maps) do
            if type(name) == 'string' and type(m) == 'table' and Config.AspectNominal(name) then
                out.maps[name] = m
            end
        end
    end
    if out.map then
        out.maps[Config.AspectBucket(tonumber(payload.aspect))] = out.map
    end

    out.notify = sanitiseNotify(payload.notify) or sanitiseNotify(out.offsets.notify)

    return out
end

local function broadcast()
    if not published then return end
    GlobalState:set('vice_hud:layout', published, true)
    -- Published separately as well as inside the layout, because the ox_lib
    -- notification hook runs in every resource on the server and should not
    -- have to know the shape of a HUD layout to find one field in it.
    if published.notify then
        GlobalState:set('vice_hud:notify', published.notify, true)
    end
end

local function load()
    local raw = LoadResourceFile(GetCurrentResourceName(), STORE)
    if not raw or raw == '' then return end
    local ok, dec = pcall(json.decode, raw)
    if not ok or type(dec) ~= 'table' then
        print('^1[vice_hud]^7 ' .. STORE .. ' is not valid JSON — ignoring it')
        return
    end
    if tonumber(dec.v) ~= STORE_VERSION then
        print('^3[vice_hud]^7 ' .. STORE .. ' was written by an older version — ignoring it')
        return
    end
    published = dec
    broadcast()
    print('^2[vice_hud]^7 server-wide layout loaded from ' .. STORE)
end

local function save()
    local ok, enc = pcall(json.encode, published)
    if not ok then return false end
    return SaveResourceFile(GetCurrentResourceName(), STORE, enc, -1)
end

local function mayPublish(src)
    local ace = Config.PublishAce or 'vice_hud.publish'
    -- `command` is accepted too: anyone holding it can already run anything on
    -- the box, so refusing them here would be theatre.
    return IsPlayerAceAllowed(src, ace) or IsPlayerAceAllowed(src, 'command')
end

RegisterNetEvent('vice_hud:publish', function(payload)
    local src = source

    if not mayPublish(src) then
        print(('^3[vice_hud]^7 %s (%s) tried to publish a layout without the "%s" ace')
            :format(GetPlayerName(src) or '?', src, Config.PublishAce or 'vice_hud.publish'))
        TriggerClientEvent('vice_hud:published', src, false,
            'You need the vice_hud.publish permission')
        return
    end

    local clean = sanitise(payload)
    if not clean then
        TriggerClientEvent('vice_hud:published', src, false, 'That layout made no sense')
        return
    end

    published = clean
    if not save() then
        -- The layout still reaches everyone who is connected; it just will not
        -- survive a restart. Saying so is better than reporting success.
        TriggerClientEvent('vice_hud:published', src, false,
            'Applied to everyone, but ' .. STORE .. ' could not be written')
        broadcast()
        return
    end

    broadcast()
    print(('^2[vice_hud]^7 %s (%s) published the server-wide HUD layout')
        :format(GetPlayerName(src) or '?', src))
    TriggerClientEvent('vice_hud:published', src, true)
end)

--- Drop the published layout. Everyone falls back to Config.DefaultLayout at
--- their next connect; anyone already on keeps what they have until then,
--- because un-applying a layout in place would move the HUD under them with no
--- warning.
RegisterCommand('hudunpublish', function(src)
    if src ~= 0 and not mayPublish(src) then return end
    published = nil
    SaveResourceFile(GetCurrentResourceName(), STORE, '', -1)
    GlobalState:set('vice_hud:layout', nil, true)
    GlobalState:set('vice_hud:notify', nil, true)
    print('^2[vice_hud]^7 server-wide layout cleared')
end, true)

-- Called outright rather than off onResourceStart: a restart re-runs this
-- script from the top anyway, so the event adds a second path that has to be
-- kept in step with this one for no benefit.
load()
