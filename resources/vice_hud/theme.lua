-- -----------------------------------------------------------------------------
-- vice_hud popup theme
-- -----------------------------------------------------------------------------
-- The HUD itself is drawn by this resource, but every popup on the server --
-- notifications, progress bars, context menus, dialogs, TextUI -- is drawn by
-- ox_lib. This file describes what those should look like, and publishes that
-- description on a state bag so ox_lib can read it.
--
-- Same two-bag pattern the notification PLACEMENT already uses:
--   LocalPlayer.state['vice_hud:theme']   this player's own choice
--   GlobalState['vice_hud:theme']         the server-wide one (/themepublish)
-- Personal wins over server-wide.
--
-- The reason the values live here rather than in ox_lib's CSS is that CSS
-- cannot be changed at runtime from Lua. Publishing them as data means the
-- in-game menu can recolour every popup on the server without anything being
-- rebuilt or restarted.
-- -----------------------------------------------------------------------------

local KVP_THEME = 'vice_hud:theme'

-- The glass recipe, mirrored from html/style.css. These are the values the
-- popups need; the HUD's own palette is deliberately kept separate (see the
-- comment above --g-tint in style.css) and must not be merged into this.
--
-- There is no backdrop-filter here for the same reason there is none there: on
-- a transparent NUI page CEF has no backdrop to sample and rasterises the whole
-- region as opaque black.
-- The MAP PANEL plate, mirrored from html/style.css's --plate.
--
-- This is a different material from GLASS below and the two must not be merged.
-- .glass is what the HUD puts on top of ITSELF -- the editor, the skills screen,
-- the level-up card. --plate is what the zone bar and the vehicle panel are made
-- of, and it is a measured value: sampled across 113 frames of reference footage,
-- median #3c393d over typical scenery. That is why it is a warm purple-grey at
-- 0.88 rather than the near-black 0.82 of the glass tint.
--
-- Published for the resources that draw their own NUI page next to the map --
-- ox_target, qb-menu, qb-input -- because a target menu reads as part of the HUD
-- when it is made of the same plate as the panel above it, and reads as a
-- separate app when it is made of the popup glass instead.
local PLATE = {
    base    = { 57, 53, 59 },
    alpha   = 0.88,
    -- The plate's own hairline edge and top-lit inset, as fractions of the
    -- panel rather than colours -- see .slot in html/style.css. Consumers
    -- rebuild the box-shadow from these; sending the finished string would
    -- bake in cqh units that only mean something inside the HUD's container.
    edge    = 'rgba(255, 255, 255, 0.10)',
    topLit  = 'rgba(255, 255, 255, 0.055)',
    -- The lighter band #veh-foot uses to separate the pip strip from the name.
    band    = 'rgba(255, 255, 255, 0.052)',
    barrier = 'rgba(255, 255, 255, 0.16)',
}

local GLASS = {
    tint   = 'rgba(20, 20, 26, 0.82)',
    rim    = 'rgba(255, 255, 255, 0.20)',
    spec   = 'rgba(255, 255, 255, 0.42)',
    fill   = 'rgba(255, 255, 255, 0.07)',
    fillHi = 'rgba(255, 255, 255, 0.13)',
    line   = 'rgba(255, 255, 255, 0.10)',
    text   = '#f4f4f2',
    textDim = '#c2c2c6',
}

-- Accent presets. `success`/`error`/`inform` are the three notification types
-- ox_lib knows about; `accent` is everything else (progress bar fill, context
-- menu highlights, dialog buttons).
--
-- oxred is the ramp ox.cfg already sets as ox:primaryColor, matched to
-- ox_inventory. The vice presets use style.css's own --g-accent teal and the
-- --g-gold "something is EARNED" note.
local PRESETS = {
    oxred = {
        label = 'Ox Red (matches ox_inventory)',
        accent = '#c1272d',
        success = '#8fff35',
        error = '#ff4d4d',
        inform = '#46d8e6',
    },
    vice = {
        label = 'Vice Teal',
        accent = '#5fd8c8',
        success = '#5fd8c8',
        error = '#ff4d4d',
        inform = '#5fd8c8',
    },
    earned = {
        label = 'Vice Teal + Gold payouts',
        accent = '#5fd8c8',
        success = '#e8c56a',
        error = '#ff4d4d',
        inform = '#5fd8c8',
    },
    mono = {
        label = 'Monochrome (no accent)',
        accent = '#c2c2c6',
        success = '#f4f4f2',
        error = '#ff4d4d',
        inform = '#c2c2c6',
    },
}

local PRESET_ORDER = { 'earned', 'vice', 'oxred', 'mono' }

local DEFAULT = {
    preset = 'earned',
    glass = true,
    font = true,
    radius = 6,     -- px, popup corner rounding
    opacity = 82,   -- percent, the tint's alpha
}

local theme = nil

--- Builds the full payload ox_lib consumes from the player's choices.
--- Sent as finished values rather than a preset name so ox_lib never needs to
--- know what a preset is.
---@param t table
---@return table
local function buildPayload(t)
    local preset = PRESETS[t.preset] or PRESETS[DEFAULT.preset]

    -- Rebuild the tint at the chosen opacity rather than shipping a fixed
    -- string, so the slider actually does something.
    local alpha = math.max(0, math.min(100, tonumber(t.opacity) or DEFAULT.opacity)) / 100
    local tint = ('rgba(20, 20, 26, %.2f)'):format(alpha)

    -- The plate's alpha is scaled RELATIVE to its own default rather than being
    -- set to the slider outright. At the default the result is exactly the
    -- 0.88 measured off the reference, so a target menu matches the vehicle
    -- panel by construction; moving the slider still fades both together.
    -- Written this way round because the plate and the glass tint have
    -- different natural alphas and pointing both at one slider value would
    -- have quietly retuned the plate to the glass's.
    local plateAlpha = math.min(1, PLATE.alpha * (alpha / (DEFAULT.opacity / 100)))
    local plate = ('rgba(%d, %d, %d, %.3f)'):format(
        PLATE.base[1], PLATE.base[2], PLATE.base[3], plateAlpha)

    return {
        glass = t.glass ~= false,
        -- The HUD's Art Deco display face. Loaded by ox_lib straight out of
        -- this resource over nui://, so nothing is duplicated.
        font = t.font ~= false,
        radius = math.max(0, math.min(24, tonumber(t.radius) or DEFAULT.radius)),
        tint = tint,
        -- Map panel material. Only the own-ui_page resources read these; ox_lib
        -- ignores them, so its popups stay glass.
        plate = plate,
        plateEdge = PLATE.edge,
        plateTopLit = PLATE.topLit,
        plateBand = PLATE.band,
        plateBarrier = PLATE.barrier,
        rim = GLASS.rim,
        spec = GLASS.spec,
        fill = GLASS.fill,
        fillHi = GLASS.fillHi,
        line = GLASS.line,
        text = GLASS.text,
        textDim = GLASS.textDim,
        accent = preset.accent,
        success = preset.success,
        error = preset.error,
        inform = preset.inform,
    }
end

--- Publishes the current theme to every other resource.
local function apply()
    LocalPlayer.state:set('vice_hud:theme', buildPayload(theme), false)
end

--- Persists the player's own choice.
local function save()
    local ok, enc = pcall(json.encode, theme)
    if ok then SetResourceKvp(KVP_THEME, enc) end
end

--- Loads the saved personal theme, falling back to the default.
local function load()
    theme = {}
    for k, v in pairs(DEFAULT) do theme[k] = v end

    local raw = GetResourceKvpString(KVP_THEME)
    if not raw or raw == '' then return end

    local ok, dec = pcall(json.decode, raw)
    if not ok or type(dec) ~= 'table' then return end

    -- Field by field, so a saved file from an older version cannot introduce
    -- keys the payload builder does not expect.
    if PRESETS[dec.preset] then theme.preset = dec.preset end
    if type(dec.glass) == 'boolean' then theme.glass = dec.glass end
    if type(dec.font) == 'boolean' then theme.font = dec.font end
    if tonumber(dec.radius) then theme.radius = tonumber(dec.radius) end
    if tonumber(dec.opacity) then theme.opacity = tonumber(dec.opacity) end
end

--- Fires one of each notification type so the player can see the change.
local function preview()
    lib.notify({ title = 'Preview', description = 'This is an informational popup.', type = 'inform' })
    SetTimeout(400, function()
        lib.notify({ title = 'Preview', description = 'Payment received: $1,250.', type = 'success' })
    end)
    SetTimeout(800, function()
        lib.notify({ title = 'Preview', description = 'Something went wrong.', type = 'error' })
    end)
end

local function openMenu()
    local preset = PRESETS[theme.preset]

    local options = {
        {
            title = 'Accent',
            description = preset and preset.label or theme.preset,
            icon = 'palette',
            onSelect = function()
                local choices = {}
                for i = 1, #PRESET_ORDER do
                    local key = PRESET_ORDER[i]
                    choices[#choices + 1] = {
                        title = PRESETS[key].label,
                        icon = theme.preset == key and 'circle-check' or 'circle',
                        onSelect = function()
                            theme.preset = key
                            apply(); save(); preview()
                            openMenu()
                        end,
                    }
                end

                lib.registerContext({
                    id = 'vice_theme_accent',
                    title = 'Accent',
                    menu = 'vice_theme',
                    options = choices,
                })
                lib.showContext('vice_theme_accent')
            end,
        },
        {
            -- Named for what it does, not for the recipe behind it: the
            -- material is the map-panel PLATE now, not the old glass. The
            -- stored key and the data-vice-glass attribute keep their names so
            -- an existing saved theme and all five stylesheets still match.
            title = 'Panel surface',
            description = theme.glass and 'On -- map-panel plate' or 'Off -- ox_lib default',
            icon = theme.glass and 'toggle-on' or 'toggle-off',
            onSelect = function()
                theme.glass = not theme.glass
                apply(); save(); preview()
                openMenu()
            end,
        },
        {
            title = 'HUD font',
            description = theme.font and 'GTA Art Deco' or 'Off -- ox_lib default (Roboto)',
            icon = theme.font and 'toggle-on' or 'toggle-off',
            onSelect = function()
                theme.font = not theme.font
                apply(); save(); preview()
                openMenu()
            end,
        },
        {
            title = 'Opacity',
            description = theme.opacity .. '%',
            icon = 'droplet',
            onSelect = function()
                local input = lib.inputDialog('Popup opacity', {
                    { type = 'slider', label = 'Percent', default = theme.opacity, min = 30, max = 100 },
                })
                if not input then return openMenu() end

                theme.opacity = input[1]
                apply(); save(); preview()
                openMenu()
            end,
        },
        {
            title = 'Corner rounding',
            description = theme.radius .. 'px',
            icon = 'border-top-left',
            onSelect = function()
                local input = lib.inputDialog('Corner rounding', {
                    { type = 'slider', label = 'Pixels', default = theme.radius, min = 0, max = 24 },
                })
                if not input then return openMenu() end

                theme.radius = input[1]
                apply(); save(); preview()
                openMenu()
            end,
        },
        {
            title = 'Preview',
            description = 'Fire one of each notification type',
            icon = 'eye',
            onSelect = function()
                preview()
                openMenu()
            end,
        },
        {
            title = 'Reset to default',
            icon = 'rotate-left',
            onSelect = function()
                for k, v in pairs(DEFAULT) do theme[k] = v end
                apply(); save(); preview()
                openMenu()
            end,
        },
        {
            title = 'Publish server-wide',
            description = 'Make this everyone\'s default (needs permission)',
            icon = 'upload',
            onSelect = function()
                TriggerServerEvent('vice_hud:publishTheme', buildPayload(theme))
            end,
        },
    }

    lib.registerContext({ id = 'vice_theme', title = 'Popup Theme', options = options })
    lib.showContext('vice_theme')
end

RegisterCommand('hudtheme', function()
    openMenu()
end, false)

TriggerEvent('chat:addSuggestion', '/hudtheme', 'Style the notifications, progress bars and menus')

CreateThread(function()
    load()

    -- ox_lib's NUI has to be up before the first push lands, and the state bag
    -- is what other resources read on their own schedule anyway.
    Wait(1000)
    apply()
end)

--- Exposed so /hudreset and friends can re-push without duplicating the logic.
exports('RefreshTheme', apply)
