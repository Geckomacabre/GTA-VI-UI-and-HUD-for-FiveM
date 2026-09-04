--[[ ---------------------------------------------------------------------------
     vice_hud theme hook
     ---------------------------------------------------------------------------
     qbx_relog draws its own NUI page, and SendNUIMessage only ever reaches the
     CALLING resource's page -- the patch inside ox_lib does not reach here. So
     this is the same hook ox_target, qb-menu and qb-input each carry, copied
     idiom for idiom so one /hudtheme push lands identically on every page.

     Read from two bags, personal first:
       LocalPlayer.state['vice_hud:theme']   set by /hudtheme on this client
       GlobalState['vice_hud:theme']         set by /themepublish, server-wide

     If vice_hud is not running neither bag exists, nothing is ever sent, and
     html/style.css falls back to vice_hud's own measured values, which are
     baked in as the custom-property defaults.
     ------------------------------------------------------------------------ ]]

Relog = Relog or {}

local function currentTheme()
    local ok, state = pcall(function() return LocalPlayer.state['vice_hud:theme'] end)
    if not ok or type(state) ~= 'table' then state = GlobalState['vice_hud:theme'] end
    if type(state) ~= 'table' then return end
    return state
end

---Pushes the theme into this resource's page. Cheap, and safe to call
---repeatedly.
---
---Only the keys this page uses are forwarded. The notification type colours
---ox_lib gets (success/error/inform) have no counterpart here -- a character
---row is not a notification -- and tint/rim/spec are the popup glass, which
---this page deliberately is not made of.
local function push()
    local theme = currentTheme()
    if not theme then return end

    SendNUIMessage({
        action = 'viceTheme',
        data = {
            glass = theme.glass ~= false,
            font = theme.font ~= false,
            radius = theme.radius,
            plate = theme.plate,
            plateEdge = theme.plateEdge,
            plateTopLit = theme.plateTopLit,
            plateBand = theme.plateBand,
            plateBarrier = theme.plateBarrier,
            line = theme.line,
            text = theme.text,
            textDim = theme.textDim,
            accent = theme.accent,
        }
    })
end

---Re-push whenever either bag changes, so /hudtheme is live without a reload.
AddStateBagChangeHandler('vice_hud:theme', nil, function()
    push()
end)

CreateThread(function()
    -- The page is not necessarily up the instant this file runs, and a message
    -- sent before it is listening is simply lost. A few early retries cost
    -- nothing and save a "why is the switcher unstyled until I retheme".
    for _ = 1, 10 do
        Wait(500)
        if currentTheme() then
            push()
            break
        end
    end
end)

Relog.theme = { push = push }
