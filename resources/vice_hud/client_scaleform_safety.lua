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

-- Re-entrancy guard for vendor/ScaleformUI_Lua/src/scaleforms/Minimap/MinimapOverlays.lua.
--
-- That file's own per-frame `while true do Wait(0) ... end` loop (its last
-- ~15 lines) calls MinimapOverlays:Load() again on EVERY frame that
-- isLoaded is still false -- not just once. Load() fires
-- TriggerEvent("ScUI:AddMinimapOverlay", callback) and the callback then
-- yields on `while not HasMinimapOverlayLoaded(...) do Wait(0) end`, so if
-- that round trip takes more than one frame (it does: it crosses into the
-- sibling ScaleformUI_Assets resource and back), every frame in that window
-- re-fires the event and starts a NEW overlapping wait-chain on top of the
-- one(s) already in flight, rather than just waiting for the first one to
-- resolve. Confirmed in practice: disabling vice_hud + ScaleformUI_Assets
-- together fixed unrelated scaleform requests (um_spawn's spawn-selection
-- map) timing out -- this compounding retry storm was starving the
-- engine's scaleform pool for the whole client session, not just briefly
-- on connect, since it runs for as long as isLoaded never becomes true.
--
-- Patching MinimapOverlays.lua itself isn't the fix: it's vendored
-- unmodified on purpose (vendor/ScaleformUI_Lua/VENDORED.md). Instead this
-- wraps the published :Load method so only one call is ever in flight at a
-- time -- later calls made while one is still pending are just skipped
-- until it resolves (isLoaded flips true) or fails (falls back to being
-- retried on a later frame, same as before, just not every single frame).
-- Also don't let it even START trying to load before the player has
-- actually spawned in: the character-select/spawn-location screens run
-- their own scaleform requests (um_spawn's HEISTMAP_MP map among them)
-- during exactly the window this vendor thread is already spinning in,
-- well before QBCore:Client:OnPlayerLoaded fires.
local playerLoaded = false

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    playerLoaded = true
end)

CreateThread(function()
    Wait(0)
    if not MinimapOverlays or MinimapOverlays.__loadGuarded then return end

    local originalLoad = MinimapOverlays.Load
    local loading = false

    MinimapOverlays.Load = function(self)
        if not playerLoaded or loading then return end

        loading = true
        originalLoad(self)

        -- originalLoad's TriggerEvent returns immediately -- the actual load
        -- happens later, in the callback it passed across to
        -- ScaleformUI_Assets, running in ITS OWN coroutine (that gap between
        -- "returned" and "actually loaded" is exactly what let the vendor's
        -- per-frame loop pile up overlapping attempts). So the guard has to
        -- stay held by a separate watcher, not dropped the instant
        -- originalLoad's synchronous portion returns, or it protects
        -- nothing. Bounded by a timeout so a load that genuinely never
        -- resolves doesn't wedge every future attempt shut forever.
        CreateThread(function()
            local start = GetGameTimer()

            while not self.isLoaded and GetGameTimer() - start < 15000 do
                Wait(0)
            end

            loading = false
        end)
    end

    MinimapOverlays.__loadGuarded = true
    print('^3[vice_hud]^7 guarded MinimapOverlays:Load against re-entrant per-frame calls (vendor retry-storm bug, see client_scaleform_safety.lua)')
end)
