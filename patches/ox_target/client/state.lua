local state = {}

local isActive = false

---@return boolean
function state.isActive()
    return isActive
end

---@param value boolean
function state.setActive(value)
    isActive = value

    -- vice_hud textui migration (added by vice_hud; see
    -- client/main.lua's header block, and state.lua.pre-vice_hud for the
    -- original): upstream sent '{"event": "visible", "state": true}' here,
    -- which sets body.style.visibility = "visible" on ox_target's own web
    -- page -- and that page's <body> contains a STATIC <div id="eye"> (a
    -- black eye SVG, see web/index.html), not just the option list. So
    -- making it visible draws that eye in the centre of the screen
    -- regardless of whether any options were ever pushed.
    --
    -- Upstream got away with it because the page was only made visible
    -- while Alt was held. Targeting is always-on now, so this pinned a
    -- permanent black eye to the middle of every player's screen. Nothing
    -- reads that page any more (all rendering goes through vice_hud), so
    -- the message is simply not sent -- the page stays hidden for good.
end

local nuiFocus = false

---@return boolean
function state.isNuiFocused()
    return nuiFocus
end

---@param value boolean
function state.setNuiFocus(value, cursor)
    if value then SetCursorLocation(0.5, 0.5) end

    nuiFocus = value
    SetNuiFocus(value, cursor or false)
    SetNuiFocusKeepInput(value)
end

local isDisabled = false

---@return boolean
function state.isDisabled()
    return isDisabled
end

---@param value boolean
function state.setDisabled(value)
    isDisabled = value
end

return state
