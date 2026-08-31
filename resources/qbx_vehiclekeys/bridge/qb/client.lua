if GetConvar('qbx_vehiclekeys:enableBridge', 'true') ~= 'true' then return end

RegisterNetEvent('qb-vehiclekeys:client:AddKeys', function(plate)
    TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate)
end)

RegisterNetEvent('qb-vehiclekeys:client:RemoveKeys', function(plate)
    TriggerServerEvent('qb-vehiclekeys:server:removeKeys', plate)
end)

RegisterNetEvent('vehiclekeys:client:SetOwner', function(plate)
    TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate)
end)

CreateQbExport('HasKeys', function(plate)
    if not plate then return HasKeys(cache.vehicle) end
    local vehicles = GetVehiclesFromPlate(plate)
    local success = false
    for i = 1, #vehicles do
        success = success or HasKeys(vehicles[i])
    end
    return success
end)