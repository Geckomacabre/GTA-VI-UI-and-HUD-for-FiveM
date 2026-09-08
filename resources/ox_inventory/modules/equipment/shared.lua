--[[
    Resolves item rarity and equipment eligibility from data/equipment.lua.

    Loaded on both sides: the client uses it to decorate the item table sent to
    the NUI, the server uses it to enforce the equipment gate. Keeping the
    lookup in one place means the UI affordance and the authoritative check can
    never drift apart.
]]

local config = lib.load('data.equipment') or {}

local Equipment = {}

local VALID_RARITY = {
    common = true,
    uncommon = true,
    rare = true,
    epic = true,
    legendary = true,
}

Equipment.defaultRarity = VALID_RARITY[config.defaultRarity] and config.defaultRarity or 'common'
Equipment.weaponRarity = VALID_RARITY[config.weaponRarity] and config.weaponRarity or nil
Equipment.slots = config.slots or {}

-- itemName -> rarity
local rarityByItem = {}

for tier, items in pairs(config.rarity or {}) do
    if not VALID_RARITY[tier] then
        warn(('data/equipment.lua declares unknown rarity tier "%s"; ignoring it.'):format(tier))
    else
        for i = 1, #items do
            rarityByItem[items[i]] = tier
        end
    end
end

-- itemName -> equipment category
local categoryByItem = {}

for category, items in pairs(config.categories or {}) do
    for i = 1, #items do
        categoryByItem[items[i]] = category
    end
end

-- slot number -> set of accepted categories. Frames with an empty `accepts`
-- list are deliberately omitted so they behave like ordinary slots.
local gatedSlots = {}

for i = 1, #Equipment.slots do
    local frame = Equipment.slots[i]

    if frame.accepts and #frame.accepts > 0 then
        local accepts = {}

        for j = 1, #frame.accepts do
            accepts[frame.accepts[j]] = true
        end

        gatedSlots[frame.slot] = accepts
    end
end

Equipment.gatedSlots = gatedSlots

---Equipment category for an item, or nil if it is not wearable gear.
---@param item table|string An OxItem or an item name.
---@return string?
function Equipment.getCategory(item)
    if type(item) == 'string' then
        -- Weapons can only be identified from the resolved item table, so a
        -- bare name falls back to the explicit category list.
        return categoryByItem[item]
    end

    if not item or not item.name then return end
    if item.weapon then return 'weapon' end

    return categoryByItem[item.name]
end

---@param item table|string An OxItem or an item name.
---@return string rarity
function Equipment.getRarity(item)
    local name = type(item) == 'string' and item or item and item.name

    if not name then return Equipment.defaultRarity end

    local explicit = rarityByItem[name]

    if explicit then return explicit end

    if Equipment.weaponRarity and type(item) == 'table' and item.weapon then
        return Equipment.weaponRarity
    end

    return Equipment.defaultRarity
end

---Whether an item may occupy a given player-inventory slot.
---Ungated slots always return true, so this is safe to call for every move.
---@param slot number
---@param item table|string|nil
---@return boolean
function Equipment.canHold(slot, item)
    local accepts = gatedSlots[slot]

    if not accepts then return true end
    if not item then return true end

    local category = Equipment.getCategory(item)

    return category ~= nil and accepts[category] == true
end

---True if the slot is one of the gated equipment frames.
---@param slot number
---@return boolean
function Equipment.isGated(slot)
    return gatedSlots[slot] ~= nil
end

return Equipment
