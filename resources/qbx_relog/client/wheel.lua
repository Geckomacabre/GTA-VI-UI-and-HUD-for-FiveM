-- The character switcher: input and lifecycle. The strip itself is html/.
--
-- GTA VI's switcher is a row of portrait cards you cycle along, so cycling is
-- what this reads: horizontal mouse or stick travel steps the highlight one
-- card at a time, and so do the mouse wheel and the arrow keys. That is the
-- gesture the button prompt drawn on the left of the strip is promising.
--
-- Cards are laid out left to right and html/app.js appends them in the same
-- order, so index 1 is the leftmost card in both halves.
--
-- The page never takes NUI focus. The player is holding a key and cycling with
-- the mouse; SetNuiFocus would swallow the key-up and turn the mouse into a
-- cursor. So all input stays here and the page is told only when the highlight
-- moves.

Relog = Relog or {}

-- CURSOR_SCROLL_UP/DOWN and CELLPHONE_LEFT/RIGHT: the mouse wheel and the
-- arrow keys.
local SCROLL_UP, SCROLL_DOWN = 241, 242
local KEY_LEFT, KEY_RIGHT = 174, 175

local open = false

---@param characters table[]
---@return table[] payload
local function toPayload(characters)
    local payload = {}

    for i = 1, #characters do
        local character = characters[i]
        local emoji
        if character.honorTier == 'angel' then
            emoji = Config.honorAngelEmoji
        elseif character.honorTier == 'devil' then
            emoji = Config.honorDevilEmoji
        end

        payload[i] = {
            -- The page owns the portraits, keyed by citizenid -- see the note
            -- at the top of headshots.lua about the single texture slot. This
            -- side only says who each card is; the page looks up whether it
            -- has a face for them yet.
            id = character.citizenid,
            name = character.label,
            sub = character.job,
            initials = character.initials,
            current = character.isCurrent or false,
            honor = character.honor,
            honorTier = character.honorTier,
            honorEmoji = emoji,
            honorBroken = character.honorBroken or false,
        }
    end

    return payload
end

---Walks `step` cards from `from`, skipping the character already being played.
---The current character stays on the strip -- seeing who you are is half the
---point of the thing -- but the highlight never lands on it, so releasing can
---never mean "switch to myself".
---@param from number 0 when nothing is highlighted yet
---@param step number -1 or 1
---@param characters table[]
---@return number index 0 if every card is unselectable
local function nextSelectable(from, step, characters)
    local count = #characters
    local at = from

    -- At most one full lap: with a single character, or a list that is somehow
    -- all "current", there is nothing to land on and this returns 0 rather
    -- than spinning.
    for _ = 1, count do
        if at == 0 then
            at = step > 0 and 1 or count
        else
            at = ((at - 1 + step) % count + count) % count + 1
        end

        if not characters[at].isCurrent then return at end
    end

    return 0
end

---Runs the switcher until `stillHeld` goes false or the safety timeout expires.
---@param characters table[] ordered cards; each needs label, job, initials, isCurrent
---@param stillHeld fun(): boolean
---@return number? index the card the highlight was on at release
local function run(characters, stillHeld)
    if open then return end
    open = true

    local count = #characters

    SendNUIMessage({
        action = 'open',
        characters = toPayload(characters),
        margin = Config.wheelMargin,
        key = Config.wheelKey,
    })

    AnimpostfxStop('SwitchHUDOut')
    AnimpostfxPlay('SwitchHUDIn', 0, true)
    if Config.wheelSlowMotion then SetTimeScale(0.25) end

    -- Nothing is highlighted until the player actually cycles, so letting go
    -- without moving is a no-op rather than a switch.
    local selected, travel = 0, 0.0
    local deadline = GetGameTimer() + Config.wheelMaxOpenMs

    while stillHeld() and GetGameTimer() < deadline do
        -- 1/2 are LookLeftRight/LookUpDown, which is both the mouse and the
        -- gamepad right stick -- disabled so the camera holds still while the
        -- same input drives the highlight. 2 is disabled as well as 1 even
        -- though only 1 is read, or looking up and down would still work while
        -- the strip is open.
        DisableControlAction(0, 1, true)
        DisableControlAction(0, 2, true)
        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
        DisableControlAction(0, 68, true)
        DisableControlAction(0, 69, true)
        DisableControlAction(0, 70, true)
        DisableControlAction(0, 91, true)
        DisableControlAction(0, 92, true)

        local step = 0
        travel = travel + GetDisabledControlNormal(0, 1) * Config.wheelSensitivity

        -- One card per whole unit of travel, with the remainder carried, so a
        -- steady drag walks the strip at a steady rate instead of stalling.
        while travel >= 1.0 do
            step = step + 1
            travel = travel - 1.0
        end
        while travel <= -1.0 do
            step = step - 1
            travel = travel + 1.0
        end

        if IsDisabledControlJustPressed(0, SCROLL_DOWN) or IsDisabledControlJustPressed(0, KEY_RIGHT) then
            step = step + 1
        end
        if IsDisabledControlJustPressed(0, SCROLL_UP) or IsDisabledControlJustPressed(0, KEY_LEFT) then
            step = step - 1
        end

        if step ~= 0 then
            -- Wraps, because a strip you can fall off the end of makes the last
            -- card harder to reach than the rest for no reason.
            local target = nextSelectable(selected, step > 0 and 1 or -1, characters)

            if target ~= 0 and target ~= selected then
                selected = target
                SendNUIMessage({ action = 'select', index = selected })
            end
        end

        -- Portraits arriving mid-open need no message from here: the page
        -- stores them under the citizenid as each capture lands and repaints
        -- any card already showing that character.

        Wait(0)
    end

    SendNUIMessage({ action = 'close' })

    if Config.wheelSlowMotion then SetTimeScale(1.0) end
    AnimpostfxStop('SwitchHUDIn')

    open = false
    return selected > 0 and selected or nil
end

local function isOpen()
    return open
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    SetTimeScale(1.0)
    AnimpostfxStop('SwitchHUDIn')
    AnimpostfxStop('SwitchHUDOut')
end)

Relog.wheel = {
    run = run,
    isOpen = isOpen,
}
