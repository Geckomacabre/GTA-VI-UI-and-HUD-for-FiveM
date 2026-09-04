--[[
    Takes over the NATIVE pause menu instead of binding our own open key.

    ESC (INPUT_FRONTEND_PAUSE_ALTERNATE, 199), P (INPUT_FRONTEND_PAUSE, 200)
    and a controller Start button all funnel through these two control IDs,
    so watching IsControlJustPressed(0, 200)/(0, 199) instead of
    RegisterKeyMapping-ing one specific key means we don't have to chase
    every possible binding of "open pause menu" (including whatever a player
    rebinds it to).

    NOT watching IsPauseMenuActive() to detect the press (an earlier version
    of this file did): this file also runs SetPauseMenuActive(false)
    unconditionally every frame (see below), and that thread and a
    flag-watching detection loop are two scripts fighting over the exact
    same flag every single frame -- whichever one's Wait(0) happens to run
    first each tick wins, which in practice meant the suppression thread won
    essentially always and IsPauseMenuActive() never read true long enough
    for the detection loop to catch it: ESC/P stopped opening the menu at
    all. Watching the raw control press instead sidesteps that race
    entirely.

    HOW THE NATIVE MENU IS SUPPRESSED -- checked against five independent
    public FiveM pause-menu resources (ns-pausemenuv2, nxPausemenu,
    P42.PauseMenu, Nevylish/custom_pausemenu, Official-X3R0/pausemenu) that
    all use SetPauseMenuActive(false) unconditionally, every frame, forever
    (see the thread near the bottom of this file) for this same job -- this
    is what stops the real native menu from rendering itself once the engine
    notices the same ESC/P press the detection loop below also sees. No
    TakeControlOfFrontend/ReleaseControlOfFrontend anywhere in this file --
    an earlier version used that instead, which is a DIFFERENT and
    incompatible mechanism (see native_pages.lua's header comment for the
    history of why that combination caused a lockup).

    Map is entirely custom NUI (see html/app.js), not a native-frontend
    takeover -- ActivateFrontendMenu(FE_MENU_VERSION_MP_PAUSE) was tried at
    length: it genuinely worked without locking up (a real, safe technique),
    but renders as stock, unthemeable Rockstar UI with no scripting hook to
    restyle it -- visibly inconsistent with this resource's own theme, which
    isn't acceptable for the Map. Settings uses that exact same proven-safe
    technique deliberately (see openNativeSettings below) -- unlike Map,
    there's no way to reimplement the REAL Settings screens ourselves at all
    (most of Graphics/Audio/Controls have no scriptable SET_ native, per
    shared/config.lua's Settings-tab comment), so unthemed-but-real beats
    themed-but-fake there.
]]

local menuOpen = false
local currentPanel = Config.DefaultPanel
local enabled = true
local players = {}
local nativeSettingsOpen = false

local function loadEnabledSetting()
    if not Config.AllowPlayerToDisable then return end
    local kvp = GetResourceKvpString(Config.ToggleKvp)
    if kvp ~= nil then
        enabled = kvp == 'true'
    end
end

--[[
    Same gender resolution as vice_hud's own characterAccentKey() (see
    Config.Accent's comment) -- deliberately not cached across the whole
    session in a way that survives a character switch: mirrors vice_hud's
    own QBCore:Client:OnPlayerLoaded reset below, for the same "switched to
    my other character and it's still my first character's colour" bug that
    fix was written for there.
]]
local accentKey = nil

local function resolveAccentKey()
    if accentKey then return accentKey end
    if GetResourceState('qbx_core') ~= 'started' then return 'teal' end

    local ok, pd = pcall(function() return exports.qbx_core:GetPlayerData() end)
    if not ok or type(pd) ~= 'table' or type(pd.charinfo) ~= 'table' or pd.charinfo.gender == nil then
        return 'teal' -- not loaded yet -- try again next call, do not cache a guess
    end

    accentKey = pd.charinfo.gender == 0 and 'teal' or 'pink'
    return accentKey
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    accentKey = nil
end)

local function showNui(panel)
    SendNUIMessage({
        type = 'open',
        panel = panel,
        -- Only scanned for the Map tab -- GK.ScanBlips() is a few thousand
        -- native calls (see its own header comment for why there's no
        -- cheaper way to enumerate every active blip), cheap enough for an
        -- on-demand scan but still pointless work when opening straight to
        -- Quick Menu or Players, which never use it.
        blips = panel == 'map' and GK.ScanBlips() or nil,
        players = players,
        mapConfig = Config.Map,
        accent = Config.Accent[resolveAccentKey()],
    })
end

local function openMenu()
    if menuOpen then return end -- ignore reentrant opens (e.g. a stray double-fire of the key-press detection)

    -- No TakeControlOfFrontend/SetFrontendActive(false) needed here -- the
    -- unconditional SetPauseMenuActive(false) thread near the bottom of this
    -- file already means there's nothing native rendering underneath to
    -- fight or hide. Just take NUI focus.
    local ok, err = pcall(function()
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false)

        -- Matches the blurred-background look in the reference screenshots --
        -- also what CritteRo/crit_PauseMenu uses for the same effect. (The
        -- animpostfx vignette crit_PauseMenu also uses was pulled after it
        -- coincided with the pause menu locking up across repeated open/close
        -- cycles in testing -- not confirmed as the cause, but not worth the
        -- risk for a purely cosmetic effect.)
        TriggerScreenblurFadeIn(500)
    end)

    if not ok then
        print(('[gk_pausemenu] openMenu native sequence failed, aborting open: %s'):format(err))
        SetNuiFocus(false, false)
        return
    end

    menuOpen = true
    currentPanel = Config.DefaultPanel
    -- vice_hud's own minimap frame/corner-badge are NUI elements that only
    -- react to vice_hud's OWN belief about radar state (see its client.lua
    -- around its `setRadar` function) -- they follow real IsPauseMenuActive()
    -- changes, but this resource's whole approach is to force that flag
    -- false every frame (see this file's header comment) so the real native
    -- menu never renders, which means vice_hud never sees a pause to react
    -- to either. Without this, its frame/badge (and the engine minimap
    -- behind them) stay drawn on top of/behind this NUI whenever the player
    -- would otherwise have a map showing (in a vehicle, or "on foot" map
    -- enabled). LocalPlayer.state is the same mechanism vice_hud already
    -- uses for ox_inventory's invOpen flag, so this follows an established
    -- pattern rather than inventing a new cross-resource channel.
    LocalPlayer.state:set('pauseMenuOpen', true, false)
    TriggerServerEvent('gk_pausemenu:server:requestPlayers')
    showNui(currentPanel)
end

local function closeMenu()
    if not menuOpen then return end
    menuOpen = false

    SetNuiFocus(false, false)
    TriggerScreenblurFadeOut(500)
    LocalPlayer.state:set('pauseMenuOpen', false, false)

    SendNUIMessage({ type = 'close' })
end

--[[
    Hands off to FiveM's own real Settings screen instead of a custom NUI
    panel -- see shared/config.lua's Settings-tab comment for why. Sequence:

    1. Drop this resource's own NUI focus FIRST. Leaving SetNuiFocus(true,
       ...) on while a frontend menu is also active is exactly the kind of
       native/NUI mixing that caused the historical pause-menu lockup (see
       this file's top header comment) -- hand off cleanly, don't layer them.
    2. ActivateFrontendMenu(GetHashKey('FE_MENU_VERSION_LANDING_MENU'), false,
       -1) -- FiveM's own reimplemented Settings screen (General/Gamepad/
       Audio/Display/Graphics/Rockstar Editor/Voice Chat/Keyboard-Mouse/
       Camera/Key Bindings -- matches the reference screenshots this was
       built from exactly), deliberately NOT FE_MENU_VERSION_MP_PAUSE (that's
       the WHOLE native pause tree with its own Resume/Map/etc, which would
       duplicate this resource's own Quick Menu underneath it).
       component=-1 opens that standalone LANDING page directly -- confirmed
       via a community-verified working example for its sibling
       FE_MENU_VERSION_LANDING_KEYMAPPING_MENU (jumps straight to Key
       Bindings the same way: forum.cfx.re/t/open-fivem-keybinds-in-pause-
       menu/4833882). -1 meaning "open the map" is documented behaviour for
       FE_MENU_VERSION_MP_PAUSE/SP_PAUSE specifically, not for a LANDING_*
       hash.
    3. Poll IsFrontendReadyForControl() for the close edge (true -> false) to
       detect the player backing out of it, then PauseMenuceptionTheKick() +
       SetFrontendActive(false) to fully tear it down (both documented native
       names, matching this file's original header-comment research), and
       restore this resource's own Quick Menu NUI.

    No component-ID list for jumping straight to one specific SUB-tab (e.g.
    straight to Graphics, skipping General) is documented anywhere reachable
    offline -- checked _tools/nativedb (native signature + old single-player
    doc blurb only), _tools/fivem_docs (nothing on ActivateFrontendMenu at
    all), and _tools/decompiled_scripts' pausemenu_multiplayer.c (the actual
    GTA Online pause menu script, 150k lines -- but this decompile has no
    native names or symbols resolved at all, every call site is opaque
    numbered locals, so it's unsearchable for this). Landing on the General
    tab and letting the player click across the real tab bar themselves is
    the community-verified-safe option, not a guessed shortcut.
]]
local function openNativeSettings()
    if nativeSettingsOpen then return end
    nativeSettingsOpen = true

    SendNUIMessage({ type = 'close' })
    SetNuiFocus(false, false)

    -- Passing togglePause=false to ActivateFrontendMenu below means WE own
    -- IsPauseMenuActive for this, not the native call itself -- the
    -- unconditional suppression thread near the bottom of this file already
    -- stops FIGHTING it false while nativeSettingsOpen is true, but nothing
    -- was ever setting it true. Normally ESC's own engine-level handling
    -- does that; this resource intercepts ESC itself (IsControlJustPressed,
    -- see this file's header comment) and never dispatches through that
    -- path, so the flag likely never saw a real false->true transition at
    -- all -- suspected cause of Settings loading fine once (whatever state
    -- the flag happened to already be in from before this resource started)
    -- and then getting stuck on a permanent loading screen every time after
    -- (no fresh transition for its second-load logic to key off of).
    SetPauseMenuActive(true)

    local ok, err = pcall(ActivateFrontendMenu, GetHashKey('FE_MENU_VERSION_LANDING_MENU'), false, -1)
    if not ok then
        print(('[gk_pausemenu] ActivateFrontendMenu failed, returning to Quick Menu: %s'):format(err))
        nativeSettingsOpen = false
        SetPauseMenuActive(false)
        if menuOpen then
            SetNuiFocus(true, true)
            SetNuiFocusKeepInput(false)
            showNui(currentPanel)
        end
        return
    end

    CreateThread(function()
        -- Wait for it to actually come up before watching for it to go back
        -- down again -- without this, the very next check would still read
        -- "not ready" from before it opened and immediately think it closed.
        local start = GetGameTimer()
        while not IsFrontendReadyForControl() and GetGameTimer() - start < 5000 do
            Wait(0)
        end

        while IsFrontendReadyForControl() do
            Wait(0)
        end

        pcall(PauseMenuceptionTheKick)
        pcall(SetFrontendActive, false)
        -- Explicit false here, not just leaving it to the suppression
        -- thread's next tick -- gives the true->false transition a clean,
        -- immediate edge right at teardown instead of however many frames
        -- later that thread happens to run first.
        SetPauseMenuActive(false)

        nativeSettingsOpen = false
        if menuOpen then
            SetNuiFocus(true, true)
            SetNuiFocusKeepInput(false)
            showNui(currentPanel)
        end
    end)
end

RegisterNUICallback('resume', function(_, cb)
    closeMenu()
    cb(1)
end)

RegisterNUICallback('setPanel', function(data, cb)
    currentPanel = data.panel
    -- The initial showNui() on open only scans blips if Config.DefaultPanel
    -- itself is 'map' (it isn't -- 'quickmenu' is) -- switching to Map from
    -- the Quick Menu is the actual normal path there, so it needs its own
    -- fresh scan rather than relying on stale (empty) data from open time.
    if data.panel == 'map' then
        SendNUIMessage({ type = 'blips', blips = GK.ScanBlips() })
    end
    cb(1)
end)

RegisterNUICallback('openSettings', function(_, cb)
    openNativeSettings()
    cb(1)
end)

RegisterNUICallback('setWaypoint', function(data, cb)
    if data.x and data.y then
        SetNewWaypoint(data.x + 0.0, data.y + 0.0)
        closeMenu()
    end
    cb(1)
end)

RegisterNetEvent('gk_pausemenu:client:setPlayers', function(list)
    players = list
    if menuOpen and currentPanel == 'players' then
        SendNUIMessage({ type = 'players', players = players })
    end
end)

if Config.AllowPlayerToDisable then
    RegisterCommand(Config.ToggleCommand, function()
        enabled = not enabled
        SetResourceKvp(Config.ToggleKvp, tostring(enabled))
        lib.notify({
            description = enabled and 'Custom pause menu enabled' or 'Custom pause menu disabled',
            type = 'inform',
        })
    end, false)
end

-- Defensive: an older version of this resource played AnimpostfxPlay(
-- 'MP_OrbitalCannon', ...) on open, which turned out not to reliably stop
-- (see the removed code's history) and could be left looping forever from a
-- previous broken session -- a plain resource restart does NOT undo it,
-- since it's game state, not script state. Stopping it here is a harmless
-- no-op if it wasn't playing, and cleans up anyone still stuck from before
-- this was removed.
AnimpostfxStop('MP_OrbitalCannon')

-- Unconditional, every frame, forever -- see this file's header comment.
-- This is what stops the real native pause menu from rendering itself once
-- the engine notices the same ESC/P press the detection loop below also
-- sees (via IsControlJustPressed, not this flag -- see the header comment
-- for why watching this flag directly doesn't work here).
--
-- SetPauseMenuActive is marked deprecated in FiveM's own native docs, which
-- suggest DisableFrontendThisFrame for "disable toggling the pause menu"
-- instead. Deliberately NOT switched to that: this exact deprecated call is
-- what all five researched working examples use for this, and there's no
-- confirmation DisableFrontendThisFrame behaves identically for this
-- specific "let ESC through to script but suppress the native render" use
-- case. If revisiting, test any substitution as carefully as this one was
-- researched -- don't swap it on the assumption "not deprecated" means
-- "equivalent behavior here."
--
-- `and not nativeSettingsOpen`: while the REAL native Settings screen
-- (openNativeSettings, FE_MENU_VERSION_LANDING_MENU) is up, this must NOT
-- keep forcing the flag false -- that menu's own loading sequence needs
-- IsPauseMenuActive to actually go true to finish initializing, and this
-- thread fighting it every single frame is what showed up as Settings
-- getting stuck on a permanent loading screen: the frontend was requested,
-- but never allowed to finish coming up.
CreateThread(function()
    while true do
        Wait(0)
        if not nativeSettingsOpen then
            SetPauseMenuActive(false)
        end
    end
end)

CreateThread(function()
    loadEnabledSetting()

    while true do
        Wait(0)

        if IsControlJustPressed(0, 200) or IsControlJustPressed(0, 199) then
            if enabled and not menuOpen then
                openMenu()
            end
        end

        -- Skipped while the real native Settings screen has taken over --
        -- INPUT_FRONTEND_ACCEPT (202) is in Config.DisableWhileOpen, and the
        -- player needs that to actually select things in the native menu.
        -- Suppressing it there wouldn't just be redundant, it would break
        -- using Settings at all.
        if menuOpen and not nativeSettingsOpen then
            for _, control in ipairs(Config.DisableWhileOpen) do
                DisableControlAction(0, control, true)
            end
        end
    end
end)

-- Low-frequency (not Wait(0)) -- only feeds the NUI-drawn Map tab, and only
-- while it's actually the visible panel, so this costs nothing the rest of
-- the time.
CreateThread(function()
    while true do
        Wait(150)

        if menuOpen and currentPanel == 'map' then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            SendNUIMessage({
                type = 'playerPos',
                x = coords.x,
                y = coords.y,
                heading = GetEntityHeading(ped),
            })
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    if menuOpen then closeMenu() end
end)
