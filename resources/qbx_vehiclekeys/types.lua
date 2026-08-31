---@meta

---@alias Anim {dict: string, clip: string, delay?: integer}

---@alias VehicleType 'automobile' | 'bike' | 'boat' | 'heli' | 'plane' | 'submarine' | 'trailer' | 'train'
---@alias Hash number|string actually a number but `model` is treated as a string by language server

---@class VehicleConfig
---@field spawnLockedIfParked? boolean | number ratio 0.0 - 1.0
---@field spawnLockedIfDriven? boolean | number ratio 0.0 - 1.0
---@field noLock? boolean
---@field carjackingImmune? boolean
---@field lockpickImmune? boolean
---@field windowSmashImmune? boolean defaults to lockpickImmune when unset
---@field shared? boolean
---@field removeNormalLockpickChance? number ratio
---@field removeAdvancedLockpickChance? number ratio
---@field findKeysChance? number ratio