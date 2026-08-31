return {
    runClearCronMinutes = 5,
    distanceToHandKeys = 3,
    ---@type table<WeaponTypeGroup, number>
    carjackChance = {                    -- Probability of successful carjacking based on weapon used
        [WeaponTypeGroup.MELEE] = 0.0,
        [WeaponTypeGroup.HANDGUN] = 0.5,
        [WeaponTypeGroup.SMG] = 0.75,
        [WeaponTypeGroup.SHOTGUN] = 0.90,
        [WeaponTypeGroup.RIFLE] = 0.90,
        [WeaponTypeGroup.LMG] = 0.99,
        [WeaponTypeGroup.SNIPER] = 0.99,
        [WeaponTypeGroup.HEAVY] = 0.99,
        [WeaponTypeGroup.THROWABLE] = 0.0,
        [WeaponTypeGroup.MISC] = 0.0,
    },
}
