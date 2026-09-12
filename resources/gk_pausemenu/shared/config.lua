Config = {}

--------------------------------------------------------------------------------
-- General
--------------------------------------------------------------------------------

-- KVP-backed opt-out, same pattern as CritteRo/crit_PauseMenu's
-- allowPlayerToDisableMenu: players who hate it can turn it off and get the
-- native ESC menu back, without a server restart.
Config.AllowPlayerToDisable = true
Config.ToggleCommand        = 'togglepausemenu'
Config.ToggleKvp            = 'gk_pausemenu:enabled'

-- Which panel the menu opens on the first time it's shown each session.
-- Map is not a value here -- it's a native frontend handoff (see
-- client/main.lua's openNativeFrontend), not an NUI panel to default into.
Config.DefaultPanel = 'dashboard' -- 'dashboard' | 'players'

--------------------------------------------------------------------------------
-- Theme
--------------------------------------------------------------------------------

--[[
    Gender-matched accent, same idea and same two colours as vice_hud's own
    waypoint marker / nav-turn tile (vice_hud/client.lua's NAV_ACCENT_HEX and
    characterAccentKey()) -- teal for a male character, pink for a female
    one, so this menu reads as part of the same HUD rather than a
    differently-branded overlay bolted on next to it.

    Duplicated here rather than read from vice_hud at runtime: vice_hud
    exports/publishes a state bag for its POPUP theme (accent/glass/etc, see
    its theme.lua) for other resources to read, but NOT this specific
    gender-pair table -- NAV_ACCENT_HEX is a local in client.lua with no
    export or state bag of its own. If vice_hud's own pink/teal hexes ever
    change, update both places.
]]
Config.Accent = {
    teal = { accent = '#47aba7', ink = '#0b1a19' },
    pink = { accent = '#fc74a4', ink = '#280d14' },
}

--------------------------------------------------------------------------------
-- Settings tab
--------------------------------------------------------------------------------

--[[
    Settings is NOT a custom NUI panel (an earlier version reimplemented a
    handful of options -- HUD/radar toggles, targeting mode, camera view --
    as its own arrow-selector rows, styled to match the rest of this UI).
    That was torn back out: it could only ever cover the small subset of
    vanilla's real Settings that happen to have a working FiveM SET_ native
    (most of Graphics/Audio/most of Controls have none at all -- confirmed
    via _tools/nativedb: GET_PROFILE_SETTING exists, SET_PROFILE_SETTING
    does not), so however it was styled it could never be the REAL Settings
    menu, just a differently-shaped subset of it.

    Instead, client/main.lua's Settings row hands off to FiveM's own
    ActivateFrontendMenu('FE_MENU_VERSION_LANDING_MENU', ...) -- the actual
    native Settings screen (General/Gamepad/Audio/Display/Graphics/Rockstar
    Editor/Voice Chat/Keyboard-Mouse/Camera/Key Bindings, every option real
    and working), at the cost of it rendering as unthemed stock Rockstar UI
    while open rather than matching this resource's own look -- see
    client/main.lua's openNativeFrontend for the full native sequence and
    why that specific menu hash was picked over FE_MENU_VERSION_MP_PAUSE
    (the Map footer icon's own target -- see that function's header comment).
]]

--------------------------------------------------------------------------------
-- Controls
--------------------------------------------------------------------------------

--[[
    We don't bind our own open key -- see client/main.lua. The whole point of
    watching IsControlJustPressed on these control IDs instead of
    RegisterKeyMapping('INPUT_FRONTEND_PAUSE', ...) is that ESC (and the
    controller Start button, and any user rebind of it) all funnel through
    the same control IDs, so we don't have to chase every possible binding
    of "open pause menu" ourselves.
]]
Config.DisableWhileOpen = { 200, 199, 202 } -- INPUT_FRONTEND_PAUSE, INPUT_FRONTEND_PAUSE_ALTERNATE, INPUT_FRONTEND_ACCEPT passthrough

--------------------------------------------------------------------------------
-- Dashboard (home panel) -- reskinned after SY_PauseMenu's dashboard layout
-- (sidebar/navbar/cards/footer), adapted onto qbx_core data instead of ESX's.
--------------------------------------------------------------------------------

-- Shown as their own card on the dashboard's home view.
Config.PatchNotes = {
    date = '08.09.2026',
    updates = {
        'Reskinned the pause menu into a dashboard layout.',
    },
}

--[[
    Bug/suggestion report form (the dashboard's Report card) -- posts straight
    to Discord via a plain incoming webhook, no bot token needed (unlike
    SY_PauseMenu's avatar-fetch feature, which does require one -- this
    resource doesn't fetch Discord avatars at all, so that's not needed here).
    Leave Config.Report.Webhook empty to disable the feature: server/main.lua
    just logs to console instead of posting when it's blank, same pattern as
    every other webhook-gated resource on this server.
]]
Config.Report = {
    Webhook = '',
    WebhookName = 'gk_pausemenu',
    WebhookAvatar = '',
}
