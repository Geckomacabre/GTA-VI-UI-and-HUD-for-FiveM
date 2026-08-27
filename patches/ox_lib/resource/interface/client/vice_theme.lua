--[[ ---------------------------------------------------------------------------
     vice_hud theme hook  --  BEGIN  (added by vice_hud; safe to delete)
     ---------------------------------------------------------------------------
     Styles ox_lib's popup layer -- progress bars, context menus, dialogs,
     TextUI, notifications -- to match vice_hud's glass surface.

     Placement is handled separately in notify.lua; this file is only about how
     things LOOK. The two are kept apart because placement is per-notification
     and styling is page-wide.

     How it works: the theme is published as data on a state bag by vice_hud,
     read here, and pushed into ox_lib's own NUI page as CSS custom properties.
     Doing it as variables rather than fixed CSS is what lets /hudtheme recolour
     every popup on the server at runtime with nothing rebuilt or restarted.

     Read from two bags, personal first:
       LocalPlayer.state['vice_hud:theme']   set by /hudtheme on this client
       GlobalState['vice_hud:theme']         set by /themepublish, server-wide

     This file only runs inside ox_lib itself -- SendNUIMessage reaches the
     calling resource's own page, so no other resource could push to it. It is
     picked up by the existing `resource/**/client/*.lua` glob in fxmanifest;
     nothing there needed changing.

     If vice_hud is not running, neither bag exists, nothing is ever sent, and
     web/build/vice-glass.css falls back to ox_lib's stock appearance.

     NOTE: an ox_lib update deletes this file. It also overwrites index.html and
     removes the two lines that load vice-glass.css. Restore both, or popups go
     back to the stock look on their own.
     ------------------------------------------------------------------------ ]]

local function currentTheme()
    local ok, s = pcall(function() return LocalPlayer.state['vice_hud:theme'] end)
    if not ok or type(s) ~= 'table' then s = GlobalState['vice_hud:theme'] end
    if type(s) ~= 'table' then return nil end
    return s
end

--- Pushes the theme into the NUI page. Cheap, and safe to call repeatedly.
local function push()
    local t = currentTheme()
    if not t then return end

    SendNUIMessage({
        action = 'viceTheme',
        data = {
            glass = t.glass ~= false,
            font = t.font ~= false,
            radius = t.radius,
            -- The MAP PANEL plate. web/build/vice-glass.css paints popups with
            -- the .slot recipe now, so without these three a themed popup falls
            -- back to the measured defaults in that file and stops following
            -- /hudtheme's opacity slider.
            plate = t.plate,
            plateEdge = t.plateEdge,
            plateTopLit = t.plateTopLit,
            tint = t.tint,
            rim = t.rim,
            spec = t.spec,
            fill = t.fill,
            fillHi = t.fillHi,
            line = t.line,
            text = t.text,
            textDim = t.textDim,
            accent = t.accent,
            success = t.success,
            error = t.error,
            inform = t.inform,
        }
    })
end

--- Re-push whenever either bag changes, so /hudtheme is live without a reload.
AddStateBagChangeHandler('vice_hud:theme', nil, function()
    push()
end)

CreateThread(function()
    -- The NUI page is not necessarily up the instant this file runs, and a
    -- message sent before it is listening is simply lost. A few early retries
    -- cost nothing and save a "why is it unstyled until I open a menu".
    for _ = 1, 10 do
        Wait(500)
        if currentTheme() then
            push()
            break
        end
    end
end)

-- No explicit refresh event: vice_hud re-sets its local bag on start, which
-- fires the handler above. A second path would be one more thing to keep in
-- step for no benefit.

-- vice_hud theme hook -- END -------------------------------------------------
