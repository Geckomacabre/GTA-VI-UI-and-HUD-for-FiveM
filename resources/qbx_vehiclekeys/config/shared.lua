return {
    ---For a given vehicle, the config used is based on precendence of:
    ---1. model
    ---2. category from qbx_core shared/vehicles.lua
    ---3. class
    ---4. type
    ---5. default
    ---Each field falls back to its parent value if not specified.
    ---Example: model's shared value is nil, so the type's shared value is used.
    vehicles = {
        ---@type VehicleConfig
        default = {
            noLock = false,
            -- Upstate Mafia: stock was 0.75/0.75, which made practically every car
            -- on the street locked. These are the fallback odds for anything that
            -- isn't overridden by a class/category entry below.
            spawnLockedIfParked = 0.3,
            spawnLockedIfDriven = 0.4,
            carjackingImmune = false,
            lockpickImmune = false,
            -- Set true on a vehicle/class/category that should never be openable by
            -- smashing the driver window. Falls back to lockpickImmune when nil.
            windowSmashImmune = nil,
            shared = false,
            removeNormalLockpickChance = 0.4,
            removeAdvancedLockpickChance = 0.2,
            findKeysChance = 0.55,
        },
        ---@type table<VehicleClass, VehicleConfig>
        classes = {
            -- Cheap/utility metal: mostly left open, which is what makes the
            -- occasional locked car feel like a real obstacle again.
            [VehicleClass.COMPACTS] = {
                spawnLockedIfParked = 0.2,
                spawnLockedIfDriven = 0.3,
            },
            [VehicleClass.SEDANS] = {
                spawnLockedIfParked = 0.25,
                spawnLockedIfDriven = 0.35,
            },
            [VehicleClass.OFF_ROAD] = {
                spawnLockedIfParked = 0.2,
                spawnLockedIfDriven = 0.3,
            },
            [VehicleClass.INDUSTRIAL] = {
                spawnLockedIfParked = 0.2,
                spawnLockedIfDriven = 0.3,
            },
            [VehicleClass.UTILITY] = {
                spawnLockedIfParked = 0.2,
                spawnLockedIfDriven = 0.3,
            },
            [VehicleClass.COMMERCIAL] = {
                spawnLockedIfParked = 0.25,
                spawnLockedIfDriven = 0.35,
            },

            -- Money on wheels: still a hard target, and worth the alarm.
            [VehicleClass.SPORTS] = {
                spawnLockedIfParked = 0.7,
                spawnLockedIfDriven = 0.75,
            },
            [VehicleClass.SPORTS_CLASSICS] = {
                spawnLockedIfParked = 0.7,
                spawnLockedIfDriven = 0.75,
            },
            [VehicleClass.SUPER] = {
                spawnLockedIfParked = 0.9,
                spawnLockedIfDriven = 0.9,
            },

            -- Never openable by smashing glass.
            [VehicleClass.EMERGENCY] = {
                windowSmashImmune = true,
            },
            [VehicleClass.MILITARY] = {
                windowSmashImmune = true,
            },
            [VehicleClass.TRAINS] = {
                windowSmashImmune = true,
            },
        },
        ---@type table<string, VehicleConfig>
        categories = { -- known categories: super, service, utility, helicopters, motorcycles, suvs, planes, sports, emergency, military, sportsclassics, compacts, sedans
            -- super = {
            --     noLock = false,
            --     spawnLockedIfParked = 1.0,
            --     carjackingImmune = false,
            --     lockpickImmune = false,
            --     shared = false,
            --     removeNormalLockpickChance = 1.0,
            --     removeAdvancedLockpickChance = 1.0,
            --     findKeysChance = 0.5,
            -- }
        },
        ---@type table<VehicleType, VehicleConfig>
        types = { -- known types: automobile, bike, boat, heli, plane, submarine, trailer, train
            bike = {
                noLock = true
            },
            -- automobile = {
            --     noLock = false,
            --     spawnLockedIfParked = 1.0,
            --     carjackingImmune = false,
            --     lockpickImmune = false,
            --     shared = false,
            --     removeNormalLockpickChance = 1.0,
            --     removeAdvancedLockpickChance = 1.0,
            --     findKeysChance = 0.5,
            -- }
        },
        ---@type table<Hash, VehicleConfig>
        models = {
            -- [`stockade`] = {
            --     spawnLockedIfParked = 0.5
            -- }
        }
    },
}
