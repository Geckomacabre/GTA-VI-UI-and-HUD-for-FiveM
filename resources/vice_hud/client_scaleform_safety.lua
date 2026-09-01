-- Defensive backfill for vendor/ScaleformUI_Lua/src/ScaleformUI/mainScaleform.lua.
--
-- That file snapshots about a dozen vendor globals (MinimapOverlays,
-- BigMessageInstance, RankbarHandler, ...) into ScaleformUI.Scaleforms /
-- ScaleformUI.Notifications the instant IT loads. If the file defining one
-- of those globals hasn't run yet at that exact moment, the snapshot
-- captures nil PERMANENTLY -- Lua does not retroactively update an
-- already-assigned table field once the class file does load a moment
-- later. Seen in practice as "attempt to index a nil value (field
-- 'MinimapOverlays')" from mainScaleform.lua, even with every vendor glob
-- in fxmanifest.lua ordered so ScaleformUI/mainScaleform.lua loads last --
-- if that happens again, the client most likely needs `refresh` before its
-- next `restart`/`ensure`: FXServer resolves glob-matched client_scripts at
-- refresh time and caches the result, so editing which globs exist (or
-- their order) does nothing until the next refresh, same as any other new
-- file (see this resource's own README, "Adding new files to a running
-- server needs refresh before ensure").
--
-- Patching mainScaleform.lua itself isn't the fix here: it's vendored
-- unmodified on purpose (vendor/ScaleformUI_Lua/VENDORED.md) so future
-- updates from upstream diff cleanly. This file re-checks every field it
-- snapshots one tick later instead, by which point every other vendor file
-- (all loaded earlier in client_scripts) has definitely finished its own
-- top-level code.
CreateThread(function()
    Wait(0)
    if not ScaleformUI or not ScaleformUI.Scaleforms then return end

    local backfill = {
        MidMessageInstance   = MidMessageInstance,
        PlayerListScoreboard = PlayerListScoreboard,
        InstructionalButtons = ButtonsHandler,
        BigMessageInstance   = BigMessageInstance,
        Warning              = WarningInstance,
        JobMissionSelector   = MissionSelectorHandler,
        RankbarHandler       = RankbarHandler,
        SplashText           = SplashTextInstance,
        BigFeed              = BigFeedInstance,
        MinimapOverlays      = MinimapOverlays,
    }
    for field, value in pairs(backfill) do
        if ScaleformUI.Scaleforms[field] == nil and value ~= nil then
            ScaleformUI.Scaleforms[field] = value
            print(('^3[vice_hud]^7 backfilled ScaleformUI.Scaleforms.%s (vendor load-order race, see client_scaleform_safety.lua)'):format(field))
        end
    end
    if ScaleformUI.Notifications == nil and Notifications ~= nil then
        ScaleformUI.Notifications = Notifications
        print('^3[vice_hud]^7 backfilled ScaleformUI.Notifications (vendor load-order race, see client_scaleform_safety.lua)')
    end
end)
