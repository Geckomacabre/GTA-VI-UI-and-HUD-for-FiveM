--[[
    Equipment frames and item rarity for the redesigned inventory UI.

    This file is intentionally separate from data/items.lua so that item
    definitions stay untouched and survive ox_inventory updates. Everything
    here is safe to edit.
]]

return {
    --[[
        Reserved player-inventory slots rendered as labelled frames around the
        character outline.

        The slot numbers sit at the TOP of the range on purpose. ox_inventory
        allocates new pickups from slot 1 upwards, so keeping equipment at the
        end means everyday loot never competes for these slots in practice.
        They must all be <= the `inventory:slots` convar (currently 50).

        `accepts` lists equipment categories (see `categories` below). An empty
        list means the frame is ungated — used for the hotkeys, which are just
        the normal ox_inventory hotbar slots 1-3 shown in the character panel.

        `hotkey` gives the frame its own keybind, registered exactly like the
        hotbar hotkeys: pressing it uses whatever sits in that slot, so for a
        weapon frame it draws/holsters the gun. Only set it on frames the
        hotbar doesn't already cover -- hotkey1-3 are slots 1-3 and ox_inventory
        binds 1-5 to slots 1-5 on its own, so binding those here would collide.
        Players can rebind these in FiveM's own keybind settings.
    ]]
    slots = {
        { id = 'backpack',  slot = 45, label = 'Backpack',      glyph = 'backpack',  column = 'left',   accepts = { 'backpack' } },
        { id = 'armour',    slot = 46, label = 'Body Armour',   glyph = 'armour',    column = 'left',   accepts = { 'armour' } },
        { id = 'phone',     slot = 47, label = 'Phone',         glyph = 'phone',     column = 'left',   accepts = { 'phone' } },
        { id = 'parachute', slot = 48, label = 'Parachute',     glyph = 'parachute', column = 'right',  accepts = { 'parachute' } },
        { id = 'weapon1',   slot = 49, label = 'Weapon Slot 1', glyph = 'pistol',    column = 'right',  accepts = { 'weapon' }, hotkey = '6' },
        { id = 'weapon2',   slot = 50, label = 'Weapon Slot 2', glyph = 'rifle',     column = 'right',  accepts = { 'weapon' }, hotkey = '7' },
        { id = 'hotkey1',   slot = 1,  label = 'Hotkey Slot 1', glyph = 'hotkey',    column = 'hotkey', accepts = {} },
        { id = 'hotkey2',   slot = 2,  label = 'Hotkey Slot 2', glyph = 'hotkey',    column = 'hotkey', accepts = {} },
        { id = 'hotkey3',   slot = 3,  label = 'Hotkey Slot 3', glyph = 'hotkey',    column = 'hotkey', accepts = {} },
    },

    --[[
        Which items may occupy each equipment category. Anything flagged
        `weapon = true` by data/weapons.lua is treated as the `weapon`
        category automatically, so only non-weapon gear needs listing here.
    ]]
    categories = {
        backpack = {
            'dufflebag', 'bag', 'expensive_bag', 'stolen_bag',
            'debonairepack', 'redwoodpack', 'yukonpack', 'sixtyninepack',
        },
        armour = { 'heavypc', 'lightpc' },
        phone = { 'phone', 'tablet', 'sn_tablet' },
        parachute = { 'parachute' },
    },

    --[[
        Rarity drives the slot border colour and the corner label. Unlisted
        items fall back to `defaultRarity`. Per-item metadata still wins over
        this table, so a script can mint a one-off `rarity = 'legendary'` drop.

        Valid tiers: common, uncommon, rare, epic, legendary.
    ]]
    defaultRarity = 'common',

    -- Applied to every item data/weapons.lua marks as a weapon.
    weaponRarity = 'rare',

    rarity = {
        uncommon = {
            'lockpick', 'advancedlockpick', 'screwdriverset', 'repairitem',
            'toolkit', 'carokit', 'carotool', 'weaponfixkit', 'drill', 'drill2',
            'medikit', 'defib', 'suturekit', 'bandage', 'burncream', 'morphine15',
            'morphine30', 'ice', 'copper', 'aluminum', 'steel', 'iron', 'metal',
            'radio', 'bodycam', 'gas_mask', 'laptop', 'fishingrod', 'pickaxe',
        },
        rare = {
            'dufflebag', 'bag', 'expensive_bag', 'stolen_bag', 'debonairepack',
            'redwoodpack', 'yukonpack', 'sixtyninepack', 'parachute', 'phone',
            'tablet', 'sn_tablet', 'black_money', 'moneywash', 'heavypc',
            'lightpc', 'heavyplate', 'lightplate', 'thermite', 'thermal_charge',
            'hacking_device', 'hacking_computer', 'cryptostick', 'spikestrip',
            'jackhammer', 'miningdrill', 'mininglaser', 'stolen_weapon_case',
        },
        epic = {
            'gold', 'gold_ingot', 'ls_gold_ingot', 'ls_platinum_ingot',
            'ls_titanium_ingot', 'emerald', 'uncut_emerald', 'uncut_ruby',
            'uncut_sapphire', 'rolex', 'painting', 'coke_brick', 'weed_brick',
            'kq_meth_high', 'vehicle_blueprints', 'diamonds_box',
        },
        legendary = {
            'diamond', 'uncut_diamond', 'the_bleeder',
        },
    },
}
