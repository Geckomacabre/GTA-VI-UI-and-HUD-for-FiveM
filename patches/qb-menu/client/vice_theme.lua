--[[ ---------------------------------------------------------------------------
     vice_hud theme hook  --  BEGIN  (added by vice_hud; safe to delete)
     ---------------------------------------------------------------------------
     qb-menu draws its own NUI page. The theme patch in ox_lib only reaches
     ox_lib's page -- SendNUIMessage delivers to the CALLING resource's page and
     nothing else -- so this menu needs its own copy of the hook, living inside
     qb-menu. That is the whole reason this file exists rather than being folded
     into ox_lib's vice_theme.lua.

     Read from two bags, personal first:
       LocalPlayer.state['vice_hud:theme']   set by /hudtheme on this client
       GlobalState['vice_hud:theme']         set by /themepublish, server-wide

     If vice_hud is not running, neither bag exists, nothing is ever sent, and
     html/vice-theme.css falls back to qb-menu's stock appearance.

     NOTE: a qb-menu update deletes this file, drops its line from
     fxmanifest.lua, and overwrites html/index.html (removing the two lines that
     load html/vice-theme.css and html/vice-theme.js). Restore all of it, or the
     menu goes back to the stock Material red on its own.
     ------------------------------------------------------------------------ ]]

local function currentTheme()
    local ok, s = pcall(function() return LocalPlayer.state['vice_hud:theme'] end)
    if not ok or type(s) ~= 'table' then s = GlobalState['vice_hud:theme'] end
    if type(s) ~= 'table' then return nil end
    return s
end

--- Pushes the theme into this resource's NUI page. Cheap, and safe to call
--- repeatedly.
---
--- Only the keys this page uses are forwarded. The notification type colours
--- ox_lib gets (success/error/inform) have no counterpart here -- a menu row is
--- not a notification -- and sending them would suggest vice-theme.css does
--- something with them.
local function push()
    local t = currentTheme()
    if not t then return end

    SendNUIMessage({
        action = 'viceTheme',
        data = {
            glass = t.glass ~= false,
            font = t.font ~= false,
            radius = t.radius,
            -- The MAP PANEL plate, not the popup glass -- see
            -- html/vice-theme.css for why these two materials are different
            -- and must not be unified. tint/rim/spec are ox_lib's and are
            -- deliberately not forwarded.
            plate = t.plate,
            plateEdge = t.plateEdge,
            plateTopLit = t.plateTopLit,
            plateBand = t.plateBand,
            plateBarrier = t.plateBarrier,
            line = t.line,
            text = t.text,
            textDim = t.textDim,
            accent = t.accent,
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
    -- cost nothing and save a "why is this menu unstyled until I retheme".
    for _ = 1, 10 do
        Wait(500)
        if currentTheme() then
            push()
            break
        end
    end
end)

-- vice_hud theme hook -- END -------------------------------------------------
