if GetConvar('qbx_vehiclekeys:enableBridge', 'true') ~= 'true' then return end

local function giveKeys(source, plate)
    local vehicles = plate and GetVehiclesFromPlate(plate) or {GetVehiclePedIsIn(GetPlayerPed(source), false)}
    local success = false
    for i = 1, #vehicles do
        local vehicle = vehicles[i]
        if DoesEntityExist(vehicle) then
            if GiveKeys(source, vehicles[i], true) then
                success = true
            end
            Wait(20)
        end
    end
    if success then
        exports.qbx_core:Notify(source, locale('notify.keys_taken'))
    end
    return success
end

CreateQbExport('GiveKeys', giveKeys)

local function removeKeys(source, plate)
    local vehicles = GetVehiclesFromPlate(plate)
    local success = false
    for i = 1, #vehicles do
        local vehicle = vehicles[i]
        if DoesEntityExist(vehicle) then
            if RemoveKeys(source, vehicle, true) then
                success = true
            end
            Wait(20)
        end
    end
    if success then
        exports.qbx_core:Notify(source, locale('notify.keys_removed'))
    end
    return success
end

CreateQbExport('RemoveKeys', removeKeys)

RegisterNetEvent('qb-vehiclekeys:server:AcquireVehicleKeys', function(plate)
    giveKeys(source, plate)
end)

RegisterNetEvent('qb-vehiclekeys:server:removeKeys', function(plate)
    removeKeys(source, plate)
end)

CreateQbExport('HasKeys', function(source, plate)
    local vehicles = GetVehiclesFromPlate(plate)
    local success = false
    for i = 1, #vehicles do
        success = success or HasKeys(source, vehicles[i])
    end
    return success
end)