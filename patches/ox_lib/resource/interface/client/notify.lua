--[[
    https://github.com/overextended/ox_lib

    This file is licensed under LGPL-3.0 or higher <https://www.gnu.org/licenses/lgpl-3.0.en.html>

    Copyright © 2025 Linden <https://github.com/thelindat>
]]

---@alias NotificationPosition 'top' | 'top-right' | 'top-left' | 'bottom' | 'bottom-right' | 'bottom-left' | 'center-right' | 'center-left'
---@alias NotificationType 'info' | 'warning' | 'success' | 'error'
---@alias IconAnimationType 'spin' | 'spinPulse' | 'spinReverse' | 'pulse' | 'beat' | 'fade' | 'beatFade' | 'bounce' | 'shake'

---@class NotifyProps
---@field id? string
---@field title? string
---@field description? string
---@field duration? number
---@field showDuration? boolean
---@field position? NotificationPosition
---@field type? NotificationType
---@field style? { [string]: any }
---@field icon? string | { [1]: IconProp, [2]: string }
---@field iconAnimation? IconAnimationType
---@field iconColor? string
---@field alignIcon? 'top' | 'center'
---@field sound? { bank?: string, set: string, name: string }

local settings = require 'resource.settings'

--[[ ---------------------------------------------------------------------------
     vice_hud hook  --  BEGIN  (added by vice_hud; safe to delete)
     ---------------------------------------------------------------------------
     Lets one HUD editor place the notifications of EVERY resource on the
     server. This file is loaded into each resource that imports ox_lib, so a
     hook here reaches every lib.notify call anywhere without any of those
     resources being touched.

     Placement is read from two state bags, personal first:
       LocalPlayer.state['vice_hud:notify']   set by /movehud on this client
       GlobalState['vice_hud:notify']         set by /hudpublish, server-wide
     Both are plain { anchor = <one of ox_lib's eight>, x = %, y = % }.

     x and y are PERCENTAGES OF THE SCREEN, applied as margins, so the same
     placement lands in the same relative spot at any resolution or aspect
     ratio, and the notification itself is never resized.

     If vice_hud is not running, neither bag exists and every line below is a
     no-op -- notifications behave exactly as they did before.

     NOTE: an ox_lib update overwrites this file and takes the hook with it.
     Re-add it (or restore notify.lua.pre-vice_hud, which is the original) if
     notifications go back to the top-right corner on their own.
     ------------------------------------------------------------------------ ]]
local function viceHudPlacement()
    local ok, s = pcall(function() return LocalPlayer.state['vice_hud:notify'] end)
    if not ok or type(s) ~= 'table' then s = GlobalState['vice_hud:notify'] end
    if type(s) ~= 'table' then return nil end
    return s
end

local function viceHudApply(data)
    local s = viceHudPlacement()
    if not s then return end

    local anchor = type(s.anchor) == 'string' and s.anchor or data.position
    data.position = anchor or data.position

    local dx = tonumber(s.x) or 0.0
    local dy = tonumber(s.y) or 0.0
    if dx == 0.0 and dy == 0.0 then return end

    -- Margins, not a transform: ox_lib animates the notification IN with a
    -- transform of its own, and an inline one would fight it and land the popup
    -- somewhere different at rest than in flight.
    --
    -- The doubling on a centred axis is not a fudge. A centred item sits in the
    -- middle of its free space, so flex splits any margin you add across both
    -- sides and the item only moves half as far -- doubling makes "+2 means two
    -- percent of the screen to the right" true on every anchor.
    local style = {}
    for k, v in pairs(type(data.style) == 'table' and data.style or {}) do style[k] = v end

    -- Each axis is written only when it is actually being moved. A margin of
    -- zero is not the same as no margin: it would replace whatever spacing
    -- ox_lib gives the stack on that side, so nudging only sideways would
    -- quietly change the vertical gaps too.
    if dx ~= 0.0 then
        if anchor and anchor:find('right') then
            style.marginRight = (-dx) .. 'vw'
        elseif anchor and anchor:find('left') then
            style.marginLeft = dx .. 'vw'
        else
            style.marginLeft = (dx * 2) .. 'vw'
        end
    end

    if dy ~= 0.0 then
        if anchor and anchor:find('bottom') then
            style.marginBottom = (-dy) .. 'vh'
        elseif anchor and anchor:find('center') then
            style.marginTop = (dy * 2) .. 'vh'
        else
            style.marginTop = dy .. 'vh'
        end
    end

    data.style = style
end
-- vice_hud hook -- END ------------------------------------------------------


---`client`
---@param data NotifyProps
---@diagnostic disable-next-line: duplicate-set-field
function lib.notify(data)
    local sound = settings.notification_audio and data.sound
    data.sound = nil
    data.position = data.position or settings.notification_position

    -- vice_hud: place this notification wherever the HUD editor put them.
    viceHudApply(data)

    SendNUIMessage({
        action = 'notify',
        data = data
    })

    if not sound then return end

    if sound.bank then lib.requestAudioBank(sound.bank) end

    local soundId = GetSoundId()
    PlaySoundFrontend(soundId, sound.name, sound.set, true)
    ReleaseSoundId(soundId)

    if sound.bank then ReleaseNamedScriptAudioBank(sound.bank) end
end

---@class DefaultNotifyProps
---@field title? string
---@field description? string
---@field duration? number
---@field position? NotificationPosition
---@field status? 'info' | 'warning' | 'success' | 'error'
---@field id? number

---@param data DefaultNotifyProps
function lib.defaultNotify(data)
    -- Backwards compat for v3
    data.type = data.status
    if data.type == 'inform' then data.type = 'info' end
    return lib.notify(data --[[@as NotifyProps]])
end

RegisterNetEvent('ox_lib:notify', lib.notify)
RegisterNetEvent('ox_lib:defaultNotify', lib.defaultNotify)
