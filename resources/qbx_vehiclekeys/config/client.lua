---@alias Difficulty 'easy' | 'medium' | 'hard' | {areaSize: number, speedMultiplier: number}

---Arguments of https://overextended.dev/ox_lib/Modules/Interface/Client/skillcheck
---@class SkillCheckConfig
---@field difficulty Difficulty[]
---@field inputs? string[]

---@type SkillCheckConfig
local easyLockpickSkillCheck = {
    difficulty = { 'easy', 'easy', { areaSize = 60, speedMultiplier = 1 }, 'easy' },
    inputs = { '1' }
}

---@type SkillCheckConfig
local normalLockpickSkillCheck = {
    difficulty = { 'easy', 'easy', { areaSize = 60, speedMultiplier = 1 }, 'easy' },
    inputs = { '1' }
}

---@type SkillCheckConfig
local hardLockpickSkillCheck = {
    difficulty = { 'easy', 'easy', { areaSize = 60, speedMultiplier = 1 }, 'medium' },
    inputs = { '1' }
}

return {
    vehicleMaximumLockingDistance = 5.0, -- Minimum distance for vehicle locking
    getKeysWhenEngineIsRunning = true, -- when enabled, gives keys to a player who doesn't have them if they enter the driver seat when the engine is running
    keepEngineOnWhenAbandoned = true, -- when enabled, keeps a vehicle's engine running after exiting

    -- Carjack Settings
    carjackEnable = true,                -- Enables the ability to carjack pedestrian vehicles, stealing them by pointing a weapon at them
    carjackingTimeInMs = 7500,           -- Time it takes to successfully carjack in miliseconds
    delayBetweenCarjackingsInMs = 10000, -- Time before you can attempt another carjack in miliseconds

    -- Hotwire Settings
    timeBetweenHotwires = 5000, -- Time in milliseconds between hotwire attempts
    minKeysSearchTime = 10000,  -- Minimum hotwire time in milliseconds
    maxKeysSearchTime = 20000,  -- Maximum hotwire time in milliseconds

    -- ------------------------------------------------------------------
    -- Window Smash Settings (Upstate Mafia addition, see client/smashwindow.lua)
    -- Third-eye the driver door of a locked vehicle you have no keys for to get
    -- a "Smash Window" option. Succeeding unlocks the doors, so the normal
    -- hotwire path (search for keys with [H], or a lockpick) takes over from
    -- there. No item is required - the cost is noise, stress, honor and a
    -- police alert.
    -- ------------------------------------------------------------------
    smashWindow = {
        enable = true,
        maxDistance = 2.5,            -- ox_target interaction distance

        -- Which bones the option appears on. Driver side only: you should have
        -- to go to the door you intend to climb through.
        targetBones = { 'door_dside_f', 'window_lf' },

        baseDurationMs = 4500,        -- progress duration at neutral honor, before the tier multiplier
        alarmDurationMs = 15000,      -- how long the vehicle alarm wails after a smash
        stressGain = { 2, 6 },        -- min/max stress applied on a successful smash

        ---Honor tuning. Tier comes from qbx_honor (angel / devil / nil for neutral);
        ---if qbx_honor isn't running, every player is treated as neutral and the
        ---honor loss below is simply never applied.
        ---`durationMultiplier` scales baseDurationMs - a career criminal is quicker
        ---about it, a clean-handed character fumbles.
        ---`alertChanceMultiplier` is rolled before the resource's normal police-alert
        ---roll, so it only ever reduces the odds relative to that baseline.
        honor = {
            angel = { durationMultiplier = 1.4, alertChanceMultiplier = 1.0 },
            neutral = { durationMultiplier = 1.0, alertChanceMultiplier = 0.85 },
            devil = { durationMultiplier = 0.65, alertChanceMultiplier = 0.6 },
        },

        ---Note: the honor *cost* of a smash is not set here. server/main.lua calls
        ---qbx_honor's ApplyHook, so the amount lives in qbx_honor/config.lua
        ---(Config.Hooks.window_smash) along with every other hook amount.
    },

    -- ------------------------------------------------------------------
    -- Slim Jim Settings (see client/slimjim.lua)
    -- Third-eye the driver door of a locked vehicle for a "Slim Jim" option
    -- alongside Smash Window, playing out on vice_hud's own GTA6-styled
    -- lockpick ring rather than LockpickDoor's ox_lib lib.skillCheck
    -- (client/functions.lua) -- that function, and the item-use event
    -- (lockpicks:UseLockpick) that triggers it, are untouched and still
    -- exist as a separate, unconnected path (no item currently fires it —
    -- see items.lua's 'lockpick' entry). This is a second, parallel front
    -- end for the same kind of theft, not a replacement.
    --
    -- Needs a lockpick or advancedlockpick item. Quieter than smashing (no
    -- alarm, lower alert chance) but costs the tool on a failed attempt,
    -- same as LockpickDoor's own breakLockpick. Succeeding unlocks the
    -- doors, same hand-off to the normal hotwire path smashWindow uses.
    -- ------------------------------------------------------------------
    slimJim = {
        enable = true,
        maxDistance = 2.5,             -- ox_target interaction distance
        targetBones = { 'door_dside_f' },

        -- The vice_hud lockpick ring: hold, release inside the highlighted
        -- zone. zoneLen is the win window's width as a percentage of the
        -- ring (0-100) -- wider is easier. advancedlockpick gets the wider
        -- zone; a plain lockpick gets the baseline one.
        ringDurationMs = 3000,
        zoneLenBase = 10,
        zoneLenAdvanced = 16,

        -- Break chance on a FAILED attempt reuses vehicleConfig's own
        -- removeNormalLockpickChance / removeAdvancedLockpickChance
        -- (shared/vehicle-config.lua) rather than a second, separately-
        -- tuned pair here -- those already exist for exactly this, and
        -- LockpickDoor (client/functions.lua) already reads them the same
        -- way, so a vehicle tuned harder to lockpick is harder for BOTH
        -- flows to walk away from, not just one of them.

        stressGain = { 2, 5 },         -- min/max stress on a successful pick

        -- Same honor-tuning shape as smashWindow, scaling the ring's fill
        -- duration -- a career criminal works the lock faster.
        honor = {
            angel = { durationMultiplier = 1.3, alertChanceMultiplier = 1.0 },
            neutral = { durationMultiplier = 1.0, alertChanceMultiplier = 0.6 },
            devil = { durationMultiplier = 0.75, alertChanceMultiplier = 0.35 },
        },

        ---Honor cost lives in qbx_honor/config.lua like window_smash's does --
        ---see Config.Hooks.window_smash; slim_jim reuses that same hook rather
        ---than needing its own entry, since both represent the same act
        ---(illegally entering someone else's vehicle).
    },

    -- Police Alert Settings
    alertCooldown = 10000,         -- Cooldown period in milliseconds (10 seconds)
    policeAlertChance = 0.75,      -- Chance of alerting the police during the day
    policeNightAlertChance = 0.50, -- Chance of alerting the police at night (times: 01-06)
    policeAlertNightStartHour = 1,
    policeAlertNightDuration = 5,

    ---Sends an alert to police
    ---@param crime string
    ---@param vehicle number entity
    alertPolice = function(crime, vehicle)
        TriggerServerEvent('police:server:policeAlert', locale("info.vehicle_theft") .. crime)
    end,

    vehicleAlarmDuration = 10000,
    lockpickCooldown = 1000,
    hotwireCooldown = 1000,

    -- Job Settings
    ---@class SharedKeysConfig
    ---@field enableAutolock? boolean auto-lock door on driver exit
    ---@field requireOnDuty? boolean requires player to be on duty to access the vehicle
    ---@field classes? table<VehicleClass, boolean> vehicle classes to enable shared keys on
    ---@field vehicles? table<number, boolean> vehicle hashes to enable shared keys on

    ---@alias JobName string
    ---@type table<JobName, SharedKeysConfig>
    sharedKeys = { -- Share keys amongst employees. Employees can lock/unlock any job-listed vehicle
        police = { -- Job name
            enableAutolock = true,
            requireOnduty = true,
            classes = {},
            vehicles = {
                [`police`] = true,  -- Vehicle model
                [`police2`] = true, -- Vehicle model
            }
        },
        ambulance = {
            enableAutolock = true,
            requireOnduty = true,
            classes = {},
            vehicles = {
                [`ambulance`] = true,
            },
        },
        mechanic = {
            requireOnduty = false,
            vehicles = {
                [`towtruck`] = true,
            }
        }
    },

    ---@class SkillCheckConfigEntry
    ---@field default SkillCheckConfig
    ---@field class table<VehicleClass, SkillCheckConfig | {}>
    ---@field model table<number, SkillCheckConfig>

    ---@class SkillCheckEntities
    ---@field lockpick SkillCheckConfigEntry
    ---@field advancedLockpick SkillCheckConfigEntry
    ---@field hotwire SkillCheckConfigEntry
    ---@field advancedHotwire SkillCheckConfigEntry

    ---@type SkillCheckEntities
    skillCheck = {
        lockpick = {
            default = normalLockpickSkillCheck,
            class = {
                [VehicleClass.PLANES] = hardLockpickSkillCheck,
                [VehicleClass.HELICOPTERS] = hardLockpickSkillCheck,
                [VehicleClass.EMERGENCY] = hardLockpickSkillCheck,
                [VehicleClass.MILITARY] = {}, -- cannot be lockpicked
                [VehicleClass.TRAINS] = {}, -- cannot be lockpicked
                [VehicleClass.OPEN_WHEEL] = easyLockpickSkillCheck,
            },
            model = {}
        },
        advancedLockpick = {
            default = easyLockpickSkillCheck,
            class = {
                [VehicleClass.PLANES] = hardLockpickSkillCheck,
                [VehicleClass.HELICOPTERS] = hardLockpickSkillCheck,
                [VehicleClass.EMERGENCY] = hardLockpickSkillCheck,
                [VehicleClass.MILITARY] = {}, -- cannot be lockpicked
                [VehicleClass.TRAINS] = {}, -- cannot be lockpicked
            },
            model = {}
        },
        hotwire = {
            default = normalLockpickSkillCheck,
            class = {
                [VehicleClass.PLANES] = hardLockpickSkillCheck,
                [VehicleClass.HELICOPTERS] = hardLockpickSkillCheck,
                [VehicleClass.EMERGENCY] = hardLockpickSkillCheck,
                [VehicleClass.MILITARY] = {}, -- cannot be hotwired
                [VehicleClass.TRAINS] = {}, -- cannot be hotwired
                [VehicleClass.OPEN_WHEEL] = easyLockpickSkillCheck,
            },
            model = {}
        },
        advancedHotwire = {
            default = easyLockpickSkillCheck,
            class = {
                [VehicleClass.PLANES] = hardLockpickSkillCheck,
                [VehicleClass.HELICOPTERS] = hardLockpickSkillCheck,
                [VehicleClass.EMERGENCY] = hardLockpickSkillCheck,
                [VehicleClass.MILITARY] = {}, -- cannot be hotwired
                [VehicleClass.TRAINS] = {}, -- cannot be hotwired
            },
            model = {}
        }
    },

    ---@class AnimConfigEntry
    ---@field default Anim
    ---@field class table<VehicleClass, Anim | {}>
    ---@field model table<number, Anim>

    ---@class AnimConfigEntities
    ---@field hotwire AnimConfigEntry
    ---@field smashWindow AnimConfigEntry
    ---@field searchKeys AnimConfigEntry
    ---@field lockpick AnimConfigEntry
    ---@field holdup AnimConfigEntry
    ---@field toggleEngine AnimConfigEntry

    ---@type AnimConfigEntities
    anims = {
        hotwire = {
            default = {
                dict = 'anim@veh@plane@howard@front@ds@base',
                clip = 'hotwire'
            },
            class = {},
            model = {}
        },
        searchKeys = {
            default = {
                dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',
                clip = 'machinic_loop_mechandplayer',
            },
            class = {},
            model = {}
        },
        lockpick = {
            default = {
                dict = 'veh@break_in@0h@p_m_one@',
                clip = 'low_force_entry_ds'
            },
            class = {},
            model = {}
        },
        smashWindow = {
            default = {
                -- 'high_force_entry_ds' does not exist in this dict (verified
                -- against the real clip list: only low_force_entry_ds and
                -- std_force_entry_ds, plus their _locked_ variants). An
                -- invalid clip makes TaskPlayAnim silently no-op, so nothing
                -- ever played, which is why the window smash had no
                -- animation. std_force_entry_ds is the forceful break-in
                -- clip in this dict, distinct from lockpick's gentler
                -- low_force_entry_ds above.
                dict = 'veh@break_in@0h@p_m_one@',
                clip = 'std_force_entry_ds'
            },
            class = {},
            model = {}
        },
        holdup = {
            default = {
                dict = 'mp_am_hold_up',
                clip = 'holdup_victim_20s'
            },
            class = {},
            model = {}
        },
        toggleEngine = {
            default = {
                dict = 'oddjobs@towing',
                clip = 'start_engine',
                delay = 400, -- how long it takes to start the engine
            },
            class = {
                [VehicleClass.MOTORCYCLES] = {
                    dict = 'veh@bike@quad@front@base',
                    clip = 'start_engine',
                    delay = 1000,
                },
                [VehicleClass.CYCLES] = {}, -- does not have an engine
            },
            model = {},
        },
    },
    -- Weapons that cannot be used for carjacking
    noCarjackWeapons = {
        `WEAPON_UNARMED`,
        `WEAPON_KNIFE`,
        `WEAPON_NIGHTSTICK`,
        `WEAPON_HAMMER`,
        `WEAPON_BAT`,
        `WEAPON_CROWBAR`,
        `WEAPON_GOLFCLUB`,
        `WEAPON_BOTTLE`,
        `WEAPON_DAGGER`,
        `WEAPON_HATCHET`,
        `WEAPON_KNUCKLE`,
        `WEAPON_MACHETE`,
        `WEAPON_FLASHLIGHT`,
        `WEAPON_SWITCHBLADE`,
        `WEAPON_POOLCUE`,
        `WEAPON_WRENCH`,
        `WEAPON_BATTLEAXE`,
        `WEAPON_GRENADE`,
        `WEAPON_STOCKYBOMB`,
        `WEAPON_PROXIMITYMINE`,
        `WEAPON_BZGAS`,
        `WEAPON_MOLOTOV`,
        `WEAPON_FIREEXTINGUISHER`,
        `WEAPON_PETROLCAN`,
        `WEAPON_FLARE`,
        `WEAPON_BALL`,
        `WEAPON_SNOWBALL`,
        `WEAPON_SMOKEGRENADE`,
        -- Add more weapon names as needed
    },
}
