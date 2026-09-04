---@type table<string, number> license -> os.time() of last relog
local lastRelog = {}

---@type table<number, boolean> source -> awaiting client confirmation
local pending = {}

---@type table<number, string> source -> citizenid approved by requestSwitch, awaiting confirmation
local pendingSwitch = {}

---@type table<number, string> source -> citizenid to log into once Logout finishes
local quickSwitch = {}

---@param source Source
---@return string?
local function getLicense(source)
    local player = exports.qbx_core:GetPlayer(source)
    return player and player.PlayerData.license
end

---Validates that the player is allowed to relog right now.
---@param source Source
---@return boolean allowed
---@return string? reason
local function canRelog(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return false, 'You are not logged in.' end

    local metadata = player.PlayerData.metadata

    if Config.blockWhenDead and (metadata.isdead or metadata.inlaststand) then
        return false, 'You cannot relog while down.'
    end

    if Config.blockWhenCuffed and metadata.ishandcuffed then
        return false, 'You cannot relog while cuffed.'
    end

    if Config.cooldown > 0 then
        local last = lastRelog[player.PlayerData.license]
        if last then
            local remaining = Config.cooldown - (os.time() - last)
            if remaining > 0 then
                return false, ('You must wait %d more seconds to relog.'):format(remaining)
            end
        end
    end

    return true
end

lib.addCommand(Config.commandName, {
    help = 'Return to the character selection screen',
}, function(source)
    if pending[source] then return end

    local allowed, reason = canRelog(source)
    if not allowed then
        exports.qbx_core:Notify(source, reason, 'error')
        return
    end

    pending[source] = true
    TriggerClientEvent('qbx_relog:client:begin', source)
end)

---Approves a quick-switch to one of the player's own other characters,
---requested from the client's hold-key wheel.
---@param citizenId string
RegisterNetEvent('qbx_relog:server:requestSwitch', function(citizenId)
    local src = source --[[@as Source]]
    if pending[src] then return end

    local allowed, reason = canRelog(src)
    if not allowed then
        exports.qbx_core:Notify(src, reason, 'error')
        return
    end

    local player = exports.qbx_core:GetPlayer(src)
    if player.PlayerData.citizenid == citizenId then
        exports.qbx_core:Notify(src, 'You are already playing as that character.', 'error')
        return
    end

    -- Never trust a client-supplied citizenid without checking it actually
    -- belongs to the same license -- otherwise this is a free character hijack.
    local target = exports.qbx_core:GetOfflinePlayer(citizenId)
    if not target or target.PlayerData.license ~= player.PlayerData.license then
        exports.qbx_core:Notify(src, 'Invalid character.', 'error')
        return
    end

    pending[src] = true
    pendingSwitch[src] = citizenId
    TriggerClientEvent('qbx_relog:client:begin', src, citizenId, ('%s %s'):format(target.PlayerData.charinfo.firstname, target.PlayerData.charinfo.lastname))
end)

RegisterNetEvent('qbx_relog:server:cancel', function()
    local src = source --[[@as Source]]
    pending[src] = nil
    pendingSwitch[src] = nil
end)

RegisterNetEvent('qbx_relog:server:confirm', function()
    local src = source
    if not pending[src] then return end
    pending[src] = nil

    local switchTo = pendingSwitch[src]
    pendingSwitch[src] = nil

    -- Re-check: state can change during the confirmation and delay.
    local allowed, reason = canRelog(src)
    if not allowed then
        exports.qbx_core:Notify(src, reason, 'error')
        return
    end

    local license = getLicense(src)
    if license then
        lastRelog[license] = os.time()
    end

    if switchTo then
        quickSwitch[src] = switchTo
    end

    exports.qbx_core:Logout(src)
end)

-- Fired by qbx_core after Logout finishes tearing down the old character.
-- If this source is mid quick-switch, log straight into the target
-- character and drop the player at its last position instead of letting
-- qbx_core show the multicharacter screen (client.lua already told it to
-- skip that once, via SkipNextCharacterSelect).
AddEventHandler('qbx_core:server:playerLoggedOut', function(src)
    local citizenId = quickSwitch[src]
    if not citizenId then return end
    quickSwitch[src] = nil

    local success = exports.qbx_core:Login(src, citizenId)
    if not success then
        exports.qbx_core:Notify(src, 'Failed to switch character.', 'error')
        TriggerClientEvent('qbx_relog:client:switchFailed', src)
        return
    end

    local player = exports.qbx_core:GetPlayer(src)
    TriggerClientEvent('qbx_relog:client:quickSwitchSpawn', src, player.PlayerData.position)
end)

AddEventHandler('playerDropped', function()
    local src = source --[[@as Source]]
    pending[src] = nil
    pendingSwitch[src] = nil
    quickSwitch[src] = nil
end)
