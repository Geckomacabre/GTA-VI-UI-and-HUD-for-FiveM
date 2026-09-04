--[[ DISABLED — infinite stamina.

     This ran ResetPlayerStamina(PlayerId()) every 500ms, which pins sprint
     stamina at full permanently. That is why vice_hud's stamina bar never
     moved: GetPlayerSprintStaminaRemaining was being reset faster than it
     could ever drain, so no HUD could read a changing value.

     Original file kept as client.lua.bak — restore it if you actually want
     infinite stamina, but then remove the stamina bar from vice_hud since it
     can only ever read "full".
]]

-- Citizen.CreateThread( function()
-- 	while true do
-- 		Citizen.Wait(500)
-- 		ResetPlayerStamina(PlayerId())
-- 	end
-- end)
