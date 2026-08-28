--[[
 GTA6-style pocket cap.

 The two wheels (WeaponWheel.tsx slots 1-7, ItemWheel.tsx slots 8-15 -- see
 web/src/components/inventory/) are meant to be all a player can carry on
 their person. The full shared.playerslots/shared.playerweight capacity is
 only unlocked while they have a bag equipped (wasabi_backpack) -- and even
 then it's the BAG's own separate stash inventory that gets browsed as a full
 grid, never this module raising the player's own inventory past the wheels.

 So this only ever toggles the PLAYER inventory's own ceiling between the
 15-slot pocket cap and the server's normal capacity, driven by whether they
 are currently carrying one of wasabi_backpack's bag items. SetSlotCount/
 SetMaxWeight only change the ceiling number -- they never touch inv.items --
 confirmed by reading modules/inventory/server.lua (SetSlotCount, GetEmptySlot
 loops `for i = 1, inventory.slots`), so lowering the cap on an unbagged
 player can never delete or hide anything already in slots 1-15.
]]

local Inventory = require 'modules.inventory.server'

local POCKET_SLOTS = GetConvarInt('inventory:pocketslots', 15)
local POCKET_WEIGHT = GetConvarInt('inventory:pocketweight', 8000)

-- wasabi_backpack/config.lua's Config.Bags keys -- that resource has no
-- export/convar surface for this list, so it's mirrored here by item name.
-- Add a name here (and give it a real client.export in wasabi_backpack) if a
-- new bag type is ever added.
local ok, decoded = pcall(json.decode, GetConvar('inventory:pocketbags', '["dufflebag","backpack","rucksack","cayoduffel"]'))
local BAG_ITEMS = (ok and type(decoded) == 'table' and decoded) or { 'dufflebag', 'backpack', 'rucksack', 'cayoduffel' }

-- Same list, but as a set -- the SetSlot hook below runs on every single item
-- add/remove in the whole server, so that check has to be O(1).
local BAG_SET = {}
for i = 1, #BAG_ITEMS do BAG_SET[BAG_ITEMS[i]] = true end

-- The poll is now just a safety net (catches anything that changes inv.items
-- without going through Inventory.SetSlot -- a direct DB-loaded inventory
-- edit, for instance). Real pickup/drop responsiveness comes from the hook
-- below, not this interval.
local POLL_INTERVAL = 5000

-- Per-player last-known bagged state, so a player who hasn't changed state
-- doesn't get a redundant SetSlotCount/SetMaxWeight call (each of those fires
-- a TriggerClientEvent to every viewer of the inventory).
local baggedState = {}

local function hasBag(inv)
	local found = Inventory.Search(inv, 'count', BAG_ITEMS)

	if type(found) == 'table' then
		for _, count in pairs(found) do
			if count and count > 0 then return true end
		end

		return false
	end

	return (found or 0) > 0
end

local function applyPocketCap(inv, bagged)
	if bagged then
		Inventory.SetSlotCount(inv, shared.playerslots)
		Inventory.SetMaxWeight(inv, shared.playerweight)
	else
		Inventory.SetSlotCount(inv, POCKET_SLOTS)
		Inventory.SetMaxWeight(inv, POCKET_WEIGHT)
	end
end

-- Shared by both the instant hook and the poll fallback below.
local function checkPlayer(source)
	local inv = Inventory(source)
	if not (inv and inv.player) then return end

	local bagged = hasBag(inv)

	if baggedState[source] ~= bagged then
		baggedState[source] = bagged
		applyPocketCap(inv, bagged)
	end
end

--[[
 Inventory.SetSlot is the one low-level function every add/remove path
 (AddItem, RemoveItem, swaps, buys, crafts, drops, gives...) funnels through
 to actually write into inv.items -- confirmed by reading
 modules/inventory/server.lua (AddItem calls it at line ~1168, RemoveItem at
 ~1193/1345/1358). Hooking it here, rather than every individual call site,
 is what makes "picked up/dropped a bag" apply the cap on the same tick
 instead of waiting for the next poll.
]]
local originalSetSlot = Inventory.SetSlot

function Inventory.SetSlot(inv, item, count, metadata, slot)
	local result = originalSetSlot(inv, item, count, metadata, slot)

	if item and BAG_SET[item.name] then
		local resolved = Inventory(inv)
		if resolved then checkPlayer(resolved.id) end
	end

	return result
end

AddEventHandler('playerDropped', function()
	baggedState[source] = nil
end)

CreateThread(function()
	while true do
		Wait(POLL_INTERVAL)

		local players = GetPlayers()

		for i = 1, #players do
			local source = tonumber(players[i])
			if source then checkPlayer(source) end
		end
	end
end)
