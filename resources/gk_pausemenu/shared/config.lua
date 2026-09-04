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
Config.DefaultPanel = 'quickmenu' -- 'quickmenu' | 'map' | 'players'

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
    client/main.lua's openNativeSettings for the full native sequence and
    why that specific menu hash was picked over FE_MENU_VERSION_MP_PAUSE.
]]

--------------------------------------------------------------------------------
-- Points of interest (Map tab's Locations panel)
--------------------------------------------------------------------------------

--[[
    NOT a hand-typed list -- an earlier version of this file had one (city
    hall/DMV/hospital/police/jail/five job depots, each grepped out of the
    resource that placed it), and it kept drifting: a stale Trucking Depot
    coordinate that no longer matched um_truckerjob's own config, categories
    that stopped meaning anything once qbx_garages' dynamically-added
    garages were mixed in, a sprite (356) that turned out to render as a
    generic dock/anchor icon rather than anything jail-shaped because that's
    just what rcore_prison happened to pick. Every one of those was a
    real-world resource's blip already; keeping a second, hand-maintained
    copy of coordinates those resources already own was the actual bug.

    client/blips.lua's GK.ScanBlips() reads every currently active native
    blip server-wide directly instead (GET_FIRST_BLIP_INFO_ID/
    GET_NEXT_BLIP_INFO_ID walking every sprite id, filtered to
    GET_BLIP_INFO_ID_TYPE == Coord) -- see that file's header comment for
    the technique, the filtering, and what it genuinely cannot do (there is
    no native to read a blip's own custom name back, so a discovered blip's
    label is built from its sprite's generic name plus its zone, not
    whatever specific name the creating script gave it). Nothing here needs
    to be kept in sync by hand any more; a resource that adds, moves, or
    removes a blip is reflected immediately, automatically, for every
    resource on the server, not just the ones someone remembered to grep.
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
-- Map tab
--------------------------------------------------------------------------------

--[[
    Deliberately NOT using SetRadarBigmapEnabled/ActivateFrontendMenu to show
    GTA's real map -- see client/native_pages.lua's header comment for the
    full history (a black screen that never recovered; later, a genuinely
    working native handoff that still got reverted because it renders as
    stock, unthemeable Rockstar UI). Instead the Map tab is a plain NUI image
    panned/scaled under a fixed center marker -- ordinary DOM/CSS, no
    game-frontend natives involved, so it can't reproduce the native
    failure modes, and it can be themed to match the rest of this UI.

    html/images/map.jpg is the actual GTA V map, extracted from
    resources/[assets]/ls_map_lite's own stream/minimap_ROW_COL.ytd tiles via
    _tools/map_extract (a small CodeWalker.Core-based tool -- see that
    folder) and stitched into one 6144x9216 image (ROW 0-2 north->south,
    COL 0-1 west->east, confirmed by inspecting each tile's visible
    landmarks). ls_map_lite only re-textures this core 3x2 tile grid --
    that's the entire map region this image covers; areas further out use
    the base game's own unmodified minimap tiles, which weren't extracted.

    worldMinX/Y and worldMaxX/Y below were previously a "widely-cited
    community figure" (-4000/4000/-4000/8000) that turned out to be wrong --
    it was never actually verified against this specific stitched image, and
    doing so (see html/images/README.md's calibration procedure) showed
    Humane Labs and Los Santos International Airport both landing in open
    ocean, hundreds of pixels from the real coastline. Location pins across
    the whole Map tab were off by the same kind of margin, not just those two.

    Recalibrated by WEIGHTED least-squares, pixel-matching landmarks against
    their real world coordinates (_tools/gtav_reference `zone` bbox centers)
    and their measured icon/feature pixel position in html/images/map.jpg
    (see html/images/README.md for the method):
      - Humane Labs and Research: world (3530.4, 3708.2) -> pixel (5330, 3196), weight 5
      - Maze Bank Arena:          world (-300.3, -1966.0) -> pixel (2617, 7116), weight 5
      - Elysian Island docks:     world (597.7, -3064.5)  -> pixel (3525, 7845), weight 1
    Humane Labs and Maze Bank Arena are precise single-icon matches; Elysian
    Island's pixel position is an eyeballed industrial-cluster center, not a
    discrete icon, so it carries real uncertainty of its own. An UNWEIGHTED
    fit through all three (tried first) reproduced Elysian well but dragged
    Maze Bank Arena's own residual out to ~127px -- letting one noisy point
    degrade an otherwise-precise one just to accommodate it, which is worse
    for the whole populated central-LS cluster near Maze Bank (City Hall,
    DMV, Hospital, Police Department, Mechanic Shop, Taxi Depot) than
    leaving that outlier a bit off. Weighting Humane/Maze 5x pulls the fit
    back toward them (their residuals: ~11px and ~37px) while still fixing
    the actual reported bug -- a real, script-sourced coordinate
    (um_truckerjob's own Trucking Depot, on Elysian Island) that the
    original two-point-only fit placed several hundred pixels out in open
    ocean, since neither Humane Labs nor Maze Bank Arena is anywhere near
    that part of the map. With this weighting the Trucking Depot lands
    directly on the pier structure itself, not just near its edge.

    If another far-south (or otherwise poorly-covered) location still
    drifts, re-run html/images/README.md's procedure with a real discrete
    icon in that area rather than nudging these numbers by feel -- Elysian's
    own eyeballed point is the weak link here, not a limitation of the
    method itself. A third landmark, LSIA, was also tried and excluded from
    the X fit entirely -- its zone is a large multi-lobed polygon whose bbox
    center sits well away from where the actual airport icon is drawn (its Y
    still matched to ~1%, kept as a sanity check, not a fit input).
]]
Config.Map = {
    image = 'images/map.jpg',
    pixelWidth = 6144,
    pixelHeight = 9216,

    -- World-space bounds (GetEntityCoords units) the image's top-left and
    -- bottom-right corners correspond to. X = east(+)/west(-),
    -- Y = north(+)/south(-).
    worldMinX = -4083.8,
    worldMaxX = 4674.4,
    worldMinY = -5019.5,
    worldMaxY = 8344.6,

    -- How many map pixels one screen pixel covers at zoom level 1 (bigger =
    -- more zoomed out). Mouse wheel / +- buttons adjust from here in NUI.
    metersPerPixelAtZoom1 = 6.0,
    minZoom = 0.4,
    maxZoom = 4.0,
}
