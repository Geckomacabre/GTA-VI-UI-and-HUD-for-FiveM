local config = require 'config.client'
local isSearchLocked = false
local isSearchAllowed = false

local function setSearchLabelState(isAllowed)
    if isSearchLocked and isAllowed then return end
    if isAllowed and cache.vehicle and GetVehicleConfig(cache.vehicle).findKeysChance == 0.0 then
        isSearchAllowed = false
        return
    end
    local isOpen, text = lib.isTextUIOpen()
    local newText = locale('info.search_keys_dispatch')
    local isValidMessage = text and text == newText
    if isAllowed and not isValidMessage and cache.seat == -1 then
        lib.showTextUI(newText)
    elseif (not isAllowed or cache.seat ~= -1) and isOpen and isValidMessage then
        lib.hideTextUI()
    end

    isSearchAllowed = isAllowed and cache.seat == -1
end

local function findKeys(vehicleModel, vehicleClass, vehicle)
    local hotwireTime = math.random(config.minKeysSearchTime, config.maxKeysSearchTime)

    local anim = config.anims.searchKeys.model[vehicleModel]
        or config.anims.searchKeys.model[vehicleClass]
        or config.anims.searchKeys.default

    local searchingForKeys = true
    CreateThread(function()
        while searchingForKeys do
            if not IsEntityPlayingAnim(cache.ped, anim.dict, anim.clip, 49) then
                lib.playAnim(cache.ped, anim.dict, anim.clip, 3.0, 1.0, -1, 49)
            end
            Wait(100)
        end
    end)
    if lib.progressCircle({
        duration = hotwireTime,
        label = locale('progress.searching_keys'),
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        anim = anim,
        disable = {
            move = true,
            car = true,
            combat = true,
        }
    }) then
        searchingForKeys = false
        local success = lib.callback.await('qbx_vehiclekeys:server:findKeys', false, VehToNet(vehicle))
        if not success then
            TriggerServerEvent('hud:server:GainStress', math.random(1, 4))
            exports.qbx_core:Notify(locale("notify.failed_keys"), 'error')
        end
        return success
    end
    searchingForKeys = false
end

local searchKeysKeybind = lib.addKeybind({
    name = 'searchkeys',
    description = locale('info.search_keys'),
    defaultKey = 'H',
    secondaryMapper = 'PAD_DIGITALBUTTONANY',
    secondaryKey = 'LRIGHT_INDEX',
    disabled = true,
    onPressed = function()
        if isSearchAllowed and cache.vehicle then
            isSearchLocked = true
            setSearchLabelState(false)
            local vehicle = cache.vehicle
            local isFound
            if not GetIsVehicleAccessible(vehicle) then
                isFound = findKeys(GetEntityModel(vehicle), GetVehicleClass(vehicle), vehicle)
                SetTimeout(10000, function()
                    SendPoliceAlertAttempt('steal', vehicle)
                end)
            end
            Wait(config.timeBetweenHotwires)
            isSearchLocked = false
            setSearchLabelState(not isFound)
        end
    end
})

function GetKeySearchEnabled()
    return isSearchAllowed
end

function EnableKeySearch()
    setSearchLabelState(true)
    searchKeysKeybind:disable(false)
end

function DisableKeySearch()
    setSearchLabelState(false)
    searchKeysKeybind:disable(true)
end