--[[
    History, kept for whoever next touches Map or Settings:

    Map went through several iterations: SetRadarBigmapEnabled (black screen
    that never recovered) -> a self-drawn NUI map (this resource's current
    approach) -> ActivateFrontendMenu (genuinely worked, no lockup, but
    renders as stock unthemeable Rockstar UI, reverted for that reason) ->
    back to the self-drawn NUI map, refined. See client/main.lua's header
    comment for the ActivateFrontendMenu sequence if it's worth revisiting
    again (SetPauseMenuActive(false) suppression + IsControlJustPressed open
    detection + ActivateFrontendMenu(hash, false, -1) +
    PauseMenuceptionTheKick/SetFrontendActive(false) on exit -- proven safe
    against five independent public FiveM pause-menu resources).

    The self-drawn map's own real bugs, now fixed, for whoever touches
    html/app.js's renderMapBlips next:
      - Transparency in the source map art (real alpha in the DXT5 minimap
        tiles) got flattened to black by the JPEG encoder during
        stitching (JPEG has no alpha channel) -- fixed by compositing onto a
        sky-blue background before flattening. See _tools/map_extract.
      - An early version had a hand-typed Config.Locations list (grepped out
        of um_cityhall/um_dmv/every um_*job/qbx_garages, each's own
        AddBlipForCoord call copied by hand) with an `ownBlip` field to avoid
        drawing a double pin over each of those resources' own real blips.
        Replaced entirely by client/blips.lua's GK.ScanBlips(), which reads
        every currently active native blip server-wide directly (see that
        file's own header comment) -- there's nothing left to double up on
        or keep in sync by hand, since the Locations panel's own pins now
        ARE the real blips, not a lookalike copy of them.
      - A full downloaded-icon-per-blip-sprite pipeline (~900 images from
        docs.fivem.net) was built, then a CSS mask-image was added to tint
        icons to their real in-game colour -- and BOTH were torn out, twice,
        for two different reasons: masking assumes a plain white silhouette,
        which is only true for some sprites (many are detailed multi-colour
        art: shop logos, letter markers), so masking flattened those into
        solid-coloured blobs; separately, mask-image itself turned out to be
        unreliable in FiveM's embedded CEF build -- a mask that fails to
        apply renders the whole element invisible rather than falling back
        to unmasked, which made every icon blip vanish outright the one time
        it was tried anyway. The current version (see renderMapBlips) uses a
        plain <img> (the same tag #map-image already relies on, so it can't
        fail that way) shown at each sprite's own native colour -- not
        tinted/inverted -- inside a coloured-border badge, with a plain
        coloured dot as the fallback for a sprite with no known icon or
        whose hotlinked one fails to load.

    Settings does not reimplement GTA's real Settings pages (Audio/Video/
    Controls/Graphics/...) as NUI at all any more -- most of them have no
    working SET_ native for a script to call in the first place (confirmed
    via _tools/nativedb: GET_PROFILE_SETTING exists, SET_PROFILE_SETTING
    does not), so a from-scratch NUI reimplementation could only ever be a
    differently-shaped SUBSET of the real thing, not a themed version of it.
    It now hands off to the real native Settings screen instead
    (ActivateFrontendMenu('FE_MENU_VERSION_LANDING_MENU', ...), unthemed but
    fully real -- see client/main.lua's openNativeSettings for the full
    sequence and why that specific menu hash was picked).
]]

GK = GK or {}
