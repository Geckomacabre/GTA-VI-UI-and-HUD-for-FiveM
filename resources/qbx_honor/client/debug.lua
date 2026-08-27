-- ============================================================================
-- qbx_honor / client / debug
--
-- Diagnostics only - no gameplay logic lives here.
--
-- `/honorhud` proves the whole client -> vice_hud chain in one step, without
-- needing to find an NPC to shoot or a fish to catch. If the panel appears the
-- HUD side is fine and the problem is upstream (a hook not firing); if it does
-- not, the problem is the HUD side.
-- ============================================================================

local function state(resourceName)
    local s = GetResourceState(resourceName)
    return (s == 'started' and '^2' or '^1') .. s .. '^7'
end

RegisterCommand('honorhud', function()
    print('^5===== qbx_honor client diagnostics =====^7')
    print(('  qbx_honor:     %s'):format(state('qbx_honor')))
    print(('  vice_hud:      %s'):format(state('vice_hud')))
    print(('  MugShotBase64: %s  (blank mugshot only)'):format(state('MugShotBase64')))
    print(('  logged in:     %s'):format(tostring(LocalPlayer.state.isLoggedIn)))
    print(('  cached honor:  %s'):format(tostring(exports.qbx_honor:GetHonor())))
    print(('  conduct watcher: %s'):format(tostring(Config.ConductWatcher.enabled)))

    if GetResourceState('vice_hud') ~= 'started' then
        print('^1  vice_hud is not started - nothing can be drawn. That is the problem.^7')
        print('^5========================================^7')
        return
    end

    local hud = exports['vice_hud']

    if not hud or not hud.ShowHonorToast then
        print('^1  vice_hud is started but exposes no ShowHonorToast export.^7')
        print('^5========================================^7')
        return
    end

    -- Force a visible change: seed a value, then push a different one, so
    -- vice_hud computes a non-zero delta and draws BOTH the corner panel and
    -- the centre +/- indicator.
    local honor = exports.qbx_honor:GetHonor() or 0

    pcall(function() hud:SetHonorStanding(honor - 5) end)

    local ok, mugshot = pcall(function()
        return exports['MugShotBase64']:GetMugShotBase64(PlayerPedId(), true)
    end)

    pcall(function()
        hud:ShowHonorToast(ok and mugshot or nil, honor, nil, 'Diagnostic test')
    end)

    print('  pushed a test change to vice_hud.')
    print('  EXPECT: corner panel with your face + value, and a centre "+5".')
    print('  If you see neither, the break is in vice_hud, not qbx_honor.')
    print('^5========================================^7')
end, false)

---Fires a conduct report by hand, exercising the full client -> server ->
---honor -> client -> HUD round trip.
RegisterCommand('honorping', function()
    print('^5[qbx_honor]^7 reporting a greet_npc conduct event to the server...')
    TriggerServerEvent('qbx_honor:server:reportConduct', 'greet_npc')
    print('  if honor does not move, check the server console for qbx_honor lines,')
    print('  and remember greet_npc has a 3 minute cooldown and a session cap of 6.')
end, false)
