-- -----------------------------------------------------------------------------
-- Server-wide popup theme
-- -----------------------------------------------------------------------------
-- Mirrors what server.lua does for the HUD layout, for the popup theme that
-- theme.lua builds. Kept in its own file because the two share nothing except
-- the ace check, and folding it into server.lua's sanitise() would mean one
-- more shape for that function to know about.
--
-- A player's own /hudtheme choice always wins over this; the published theme is
-- only the default for anyone who has not set one.
-- -----------------------------------------------------------------------------

local STORE = 'theme.json'
local published = nil

--- Only permits colour strings this file recognises as safe.
--- These values are written straight into CSS custom properties, so an
--- unchecked string here would let a publisher inject arbitrary CSS into every
--- player's popup layer.
---@param value any
---@return string?
local function colour(value)
    if type(value) ~= 'string' then return nil end
    if #value > 32 then return nil end

    -- #rgb, #rrggbb, #rrggbbaa
    if value:match('^#%x%x%x$') or value:match('^#%x%x%x%x%x%x$') or value:match('^#%x%x%x%x%x%x%x%x$') then
        return value
    end

    -- rgb(...) / rgba(...) with numeric components only.
    local body = value:match('^rgba?%(([%d%s%.,]+)%)$')
    if body then return value end

    return nil
end

--- Rebuilds the payload from scratch, keeping only fields of the right shape.
---@param payload any
---@return table?
local function sanitise(payload)
    if type(payload) ~= 'table' then return nil end

    local out = {
        glass = payload.glass ~= false,
        font = payload.font ~= false,
        radius = math.max(0, math.min(24, tonumber(payload.radius) or 6)),
    }

    for _, key in ipairs({ 'tint', 'rim', 'spec', 'fill', 'fillHi', 'line', 'text', 'textDim', 'accent', 'success', 'error', 'inform' }) do
        local c = colour(payload[key])
        if not c then return nil end
        out[key] = c
    end

    return out
end

local function broadcast()
    GlobalState:set('vice_hud:theme', published, true)
end

local function save()
    local ok, enc = pcall(json.encode, published)
    if not ok then return false end
    return SaveResourceFile(GetCurrentResourceName(), STORE, enc, -1)
end

local function mayPublish(src)
    local ace = Config.PublishAce or 'vice_hud.publish'
    return IsPlayerAceAllowed(src, ace) or IsPlayerAceAllowed(src, 'command')
end

RegisterNetEvent('vice_hud:publishTheme', function(payload)
    local src = source

    if not mayPublish(src) then
        print(('^3[vice_hud]^7 %s (%s) tried to publish a popup theme without the "%s" ace')
            :format(GetPlayerName(src) or '?', src, Config.PublishAce or 'vice_hud.publish'))
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Popup Theme',
            description = 'You need the vice_hud.publish permission.',
            type = 'error'
        })
        return
    end

    local clean = sanitise(payload)
    if not clean then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Popup Theme',
            description = 'That theme made no sense.',
            type = 'error'
        })
        return
    end

    published = clean
    local saved = save()
    broadcast()

    print(('^2[vice_hud]^7 %s (%s) published the server-wide popup theme')
        :format(GetPlayerName(src) or '?', src))

    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Popup Theme',
        description = saved and 'Published to everyone.'
            or ('Applied to everyone, but ' .. STORE .. ' could not be written.'),
        type = saved and 'success' or 'error'
    })
end)

RegisterCommand('themeunpublish', function(src)
    if src ~= 0 and not mayPublish(src) then return end

    published = nil
    SaveResourceFile(GetCurrentResourceName(), STORE, '', -1)
    GlobalState:set('vice_hud:theme', nil, true)
    print('^2[vice_hud]^7 server-wide popup theme cleared')
end, true)

--- Called outright rather than off onResourceStart, matching server.lua.
local function load()
    local raw = LoadResourceFile(GetCurrentResourceName(), STORE)
    if not raw or raw == '' then return end

    local ok, dec = pcall(json.decode, raw)
    if not ok then
        print('^1[vice_hud]^7 ' .. STORE .. ' is not valid JSON -- ignoring it')
        return
    end

    published = sanitise(dec)
    if published then broadcast() end
end

load()
