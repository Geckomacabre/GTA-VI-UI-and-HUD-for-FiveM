--[[ ---------------------------------------------------------------------------
     vice_hud theme hook  --  BEGIN  (added by vice_hud; safe to delete)
     ---------------------------------------------------------------------------
     ox_target draws its own NUI page. The theme patch in ox_lib only reaches
     ox_lib's page -- SendNUIMessage delivers to the CALLING resource's page and
     nothing else -- so the eye and the option list need their own copy of this
     hook, living inside ox_target. That is the whole reason this file exists
     rather than being folded into ox_lib's vice_theme.lua.

     It is the same shape as that file: read the theme off a state bag published
     by vice_hud, push it into this resource's page as CSS custom properties.
     web/vice-theme.css does the rest.

     Read from two bags, personal first:
       LocalPlayer.state['vice_hud:theme']   set by /hudtheme on this client
       GlobalState['vice_hud:theme']         set by /themepublish, server-wide

     If vice_hud is not running, neither bag exists, nothing is ever sent, and
     web/vice-theme.css falls back to ox_target's stock appearance.

     NOTE: an ox_target update deletes this file, drops its line from
     fxmanifest.lua, and overwrites web/index.html (removing the two lines that
     load web/vice-theme.css and web/js/vice-theme.js). Restore all of it, or
     the target menu goes back to the stock look on its own.
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
--- Only the keys this page actually uses are forwarded. The notification type
--- colours ox_lib gets (success/error/inform) have no counterpart here -- a
--- target option is not a notification -- and sending them would suggest
--- vice-theme.css does something with them.
local function push()
    local t = currentTheme()
    if not t then return end

    SendNUIMessage({
        action = 'viceTheme',
        data = {
            glass = t.glass ~= false,
            font = t.font ~= false,
            radius = t.radius,
            -- The MAP PANEL plate, not the popup glass. ox_target sits a few
            -- hundred pixels from the zone bar and is read alongside it, so it
            -- is built out of .slot's material rather than .glass's -- which is
            -- why tint/rim/spec are not forwarded. See web/vice-theme.css.
            plate = t.plate,
            plateEdge = t.plateEdge,
            plateTopLit = t.plateTopLit,
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
    -- cost nothing and save a "why is the target menu unstyled until I retheme".
    for _ = 1, 10 do
        Wait(500)
        if currentTheme() then
            push()
            break
        end
    end
end)

-- vice_hud theme hook -- END -------------------------------------------------
