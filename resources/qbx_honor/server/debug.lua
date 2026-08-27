-- ============================================================================
-- qbx_honor / server / debug
--
-- Diagnostics only - no gameplay logic lives here.
--
-- The honor system is deliberately quiet: hooks fire from other resources, the
-- amounts are throttled, and the only feedback is a HUD panel owned by a third
-- resource. That makes "nothing happened" ambiguous - it could be the resource
-- not running, a hook never firing, a cooldown swallowing it, or the HUD. This
-- file makes each of those distinguishable.
-- ============================================================================

-- A startup banner, so "is qbx_honor even running?" is answerable by scrolling
-- the server console instead of guessing.
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    local hookCount = 0
    for _ in pairs(Config.Hooks) do hookCount = hookCount + 1 end

    print(('^2[qbx_honor]^7 started - %d hooks configured, conduct watcher %s.')
        :format(hookCount, Config.ConductWatcher.enabled and '^2on^7' or '^3off^7'))
end)

---Formats one player's honor state.
---@param src number
---@return string
local function describePlayer(src)
    local ok, player = pcall(function() return exports.qbx_core:GetPlayer(src) end)

    if not ok or not player then
        return ('  [%s] not a loaded qbx_core player'):format(src)
    end

    local meta = player.PlayerData.metadata.honor
    local name = ('%s %s'):format(player.PlayerData.charinfo.firstname, player.PlayerData.charinfo.lastname)

    return ('  [%s] %s - metadata.honor = %s  (tier: %s)')
        :format(src, name, meta == nil and '^1nil - never seeded^7' or tostring(meta),
            tostring(exports.qbx_honor:GetBadgeTier(meta or Config.DefaultHonor)))
end

---`honordebug [id]` - report honor state. With no id, reports every online
---player. Console-only by default; see the ace check below.
RegisterCommand('honordebug', function(source, args)
    -- source 0 is the server console. In-game use needs the qbx_honor.debug ace.
    if source ~= 0 and not IsPlayerAceAllowed(source, 'qbx_honor.debug') then
        exports.qbx_core:Notify(source, 'You do not have permission to do that.', 'error')
        return
    end

    local function output(line)
        if source == 0 then print(line) else print(line) end
    end

    output('^5===== qbx_honor diagnostics =====^7')
    output(('  resource state: %s'):format(GetResourceState(GetCurrentResourceName())))
    output(('  vice_hud state: %s'):format(GetResourceState('vice_hud')))
    output(('  MugShotBase64 state: %s (only affects the mugshot image)'):format(GetResourceState('MugShotBase64')))

    local target = tonumber(args[1])

    if target then
        output(describePlayer(target))
    else
        local players = exports.qbx_core:GetQBPlayers()
        local any = false

        for playerSrc in pairs(players) do
            any = true
            output(describePlayer(playerSrc))
        end

        if not any then output('  no players online') end
    end

    output('^5=================================^7')
end, false)

---`honortest <id> <hookName>` - fire a hook by hand, bypassing whatever
---resource normally triggers it. This is the fastest way to tell "the honor
---system is broken" apart from "that one hook never fired".
RegisterCommand('honortest', function(source, args)
    if source ~= 0 and not IsPlayerAceAllowed(source, 'qbx_honor.debug') then
        exports.qbx_core:Notify(source, 'You do not have permission to do that.', 'error')
        return
    end

    local target = tonumber(args[1]) or (source ~= 0 and source or nil)
    local hookName = args[2] or 'greet_npc'

    if not target then
        print('^3[qbx_honor]^7 usage: honortest <playerId> <hookName>')
        return
    end

    if not Config.Hooks[hookName] then
        local names = {}
        for name in pairs(Config.Hooks) do names[#names + 1] = name end
        table.sort(names)
        print(('^1[qbx_honor]^7 unknown hook "%s". Known: %s'):format(hookName, table.concat(names, ', ')))
        return
    end

    local before = exports.qbx_honor:GetHonor(target)
    local after = exports.qbx_honor:ApplyHook(target, hookName)

    if after == nil then
        print(('^3[qbx_honor]^7 hook "%s" did not apply for %s - honor is %s. '
            .. 'Either the player is not loaded, or this hook is on cooldown / at its session cap.')
            :format(hookName, target, tostring(before)))
        return
    end

    print(('^2[qbx_honor]^7 hook "%s" applied to %s: %s -> %s')
        :format(hookName, target, tostring(before), tostring(after)))
end, false)
