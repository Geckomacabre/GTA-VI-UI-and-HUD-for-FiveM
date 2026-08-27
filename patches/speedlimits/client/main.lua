local enabled = true
local UIOpen = false
local currentStreet = nil
local frequency = Config.updateFrequency * 1000

CreateThread(function()
    local savedState = GetResourceKvpString("speedLimit")
    if savedState then
        enabled = savedState == "true"
    else
        SetResourceKvp("speedLimit", "true")
    end
end)

RegisterCommand(Config.toggleCommand, function(source, args)
    local toggle = not enabled
    if toggle then
        SendNUIMessage({action = "show"})
        UIOpen = true
    else
        SendNUIMessage({action = "hide"})
        UIOpen = false
        currentStreet = nil
    end
    enabled = toggle
    SetResourceKvp("speedLimit", tostring(enabled))
end)

-- Exports ---------------------------------------------------------------------
-- fenix-police's ambient officers enforce the posted limit through these, so the
-- limits stay defined here in Config.SpeedLimits rather than being copied into
-- another resource and drifting out of sync.
--
-- Both return nil where a street has no posted limit, which the caller treats as
-- "unposted" rather than "no limit".

--- @param street string street name, as GetStreetNameFromHashKey returns it
--- @return number|nil mph
local function limitForStreet(street)
    if type(street) ~= 'string' then return nil end
    return Config.SpeedLimits[street]
end

exports('getSpeedLimitForStreet', limitForStreet)

--- @return number|nil mph, string|nil street
exports('getSpeedLimitAtCoords', function(x, y, z)
    local street = GetStreetNameFromHashKey(GetStreetNameAtCoord(x + 0.0, y + 0.0, z + 0.0))
    return limitForStreet(street), street
end)

Citizen.CreateThread(function()
    while true do
        Wait(frequency)
        if IsPedInAnyVehicle(PlayerPedId()) and enabled then
            if not UIOpen then
                SendNUIMessage({action = "show"})
                UIOpen = true
            end
            
            local newStreet = GetStreetNameFromHashKey(GetStreetNameAtCoord(table.unpack(GetEntityCoords(PlayerPedId()))))
                
            if newStreet ~= currentStreet then
                currentStreet = newStreet
                local speed = Config.SpeedLimits[currentStreet]
                if speed then
                    SendNUIMessage({action = "setlimit", speed = speed})
                end
            end
        elseif UIOpen then
            SendNUIMessage({action = "hide"})
            UIOpen = false
        end
    end
end)

-- Position pushed from vice_hud's HUD editor (/movehud). This sign has its own
-- NUI page, so CSS cannot reach it from vice_hud — the offset is broadcast and
-- applied here instead.
-- The page's message handler switches on `action`, not `type` — sending `type`
-- here meant the offset message matched no case at all and was dropped, so the
-- sign never moved from /movehud. Both keys are sent now: `action` is the one
-- this page reads, `type` keeps any other listener working.
AddEventHandler('vice_hud:layout', function(layout)
    local o = layout and layout.speedlimit
    SendNUIMessage({
        action = 'offset', type = 'offset',
        x = o and o.x or 0.0,
        y = o and o.y or 0.0,
        s = o and o.s or 1.0,
    })
end)

CreateThread(function()
    Wait(2500)
    if GetResourceState('vice_hud') == 'started' then
        local ok, x, y, s = pcall(function() return exports.vice_hud:GetHudOffset('speedlimit') end)
        if ok then
            SendNUIMessage({ action = 'offset', type = 'offset', x = x or 0.0, y = y or 0.0, s = s or 1.0 })
        end
    end
end)
