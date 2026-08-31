local overlayID = -1
RegisterNetEvent("ScUI:AddMinimapOverlay")
AddEventHandler("ScUI:AddMinimapOverlay", function(cb)
    if overlayID == -1 then
        overlayID = AddMinimapOverlay("files/MINIMAP_LOADER.gfx")
        print(overlayID)
    end
    cb(overlayID)
end)

exports('AddMinimapOverlay', function()
    if overlayID == -1 then
        overlayID = AddMinimapOverlay("files/MINIMAP_LOADER.gfx")
    end
    cb(overlayID)
end)