--[[ =========================================================================
     vice_hud — skills and XP
     -------------------------------------------------------------------------
     Shared definitions and the level maths. Loaded on BOTH sides: the client
     awards XP and applies the stats, the server persists them, and neither may
     disagree about what a level means.

     WHY LEVELS ARE 0..100
     GTA's player stats are 0..100 and they are the only thing here that changes
     the game: MP0_STAMINA lengthens your sprint, MP0_STRENGTH raises melee
     damage, MP0_LUNG_CAPACITY holds your breath longer, MP0_SHOOTING_ABILITY
     tightens recoil. Making a skill level the stat value directly means there is
     no second scale to convert between and no way for the number on screen to
     drift from the number the engine is using. A level IS the stat.

     WHAT XP IS NOT
     There is no global "player level" here, on purpose. A single number that
     rises whatever you do says nothing about what you are good at, and the
     stats it would have to drive are per-discipline anyway. Each skill carries
     its own XP and its own level.
     ====================================================================== --]]

Skills = {}

--- Every skill, in display order.
---
--- `stat` is the GTA stat this level is written to. `prefix` is applied in
--- client.lua (MP0_ / SP0_) because which character slot is live is a runtime
--- question, not a definition.
---
--- `rate` is how much XP one unit of the tracked activity is worth. The units
--- differ per skill and are named in `unit` so nobody has to reverse-engineer
--- them from the tracking code.
Skills.List = {
    {
        id = 'stamina', label = 'Stamina', stat = 'STAMINA',
        unit = 'metres sprinted',
        -- Tuned against tools/skills.test.js, which prints how much of each
        -- activity a level actually costs. At 0.5: ~200 m for the first level,
        -- ~196 km for the whole 0..100. Sprinting at ~7 m/s that is about eight
        -- hours of PURE sprinting, so a maxed stat is a long-term goal rather
        -- than an afternoon or an impossibility.
        rate = 0.5,
        blurb = 'Sprint further before you redline.',
    },
    {
        id = 'strength', label = 'Strength', stat = 'STRENGTH',
        unit = 'melee hits landed',
        rate = 12.0,
        blurb = 'Hit harder, and take a little less from a beating.',
    },
    {
        id = 'lung', label = 'Lung capacity', stat = 'LUNG_CAPACITY',
        unit = 'seconds underwater',
        rate = 12.0,
        blurb = 'Hold your breath longer.',
    },
    {
        id = 'shooting', label = 'Shooting', stat = 'SHOOTING_ABILITY',
        unit = 'shots on target',
        rate = 6.0,
        blurb = 'Less recoil and a tighter spread.',
    },
    {
        id = 'stealth', label = 'Stealth', stat = 'STEALTH_ABILITY',
        unit = 'metres moved crouched',
        rate = 2.0,
        blurb = 'Move quietly, and stay unseen for longer.',
    },
    {
        id = 'driving', label = 'Driving', stat = 'DRIVING_ABILITY',
        unit = 'metres driven without a crash',
        rate = 0.1,
        blurb = 'Better grip and less chance of losing it.',
    },
    {
        id = 'flying', label = 'Flying', stat = 'FLYING_ABILITY',
        unit = 'seconds airborne',
        rate = 4.0,
        blurb = 'Steadier in the air.',
    },
    {
        id = 'wheelie', label = 'Wheelie', stat = 'WHEELIE_ABILITY',
        unit = 'seconds on one wheel',
        rate = 9.0,
        blurb = 'Hold a wheelie without binning it.',
    },
}

--- id -> definition, built once.
Skills.ById = {}
for i = 1, #Skills.List do
    Skills.List[i].order = i
    Skills.ById[Skills.List[i].id] = Skills.List[i]
end

Skills.MAX_LEVEL = 100

--- XP needed to go from `level` to `level + 1`.
---
--- Linear growth on the per-level cost, which makes the TOTAL cost quadratic.
--- Chosen over the usual exponential curve deliberately: exponential means the
--- last ten levels cost more than the first ninety, which reads as a wall
--- rather than as progress. Quadratic keeps late levels expensive without
--- making them hopeless, and it is the difference between a stat that a normal
--- player eventually maxes and one that only a bot does.
---
--- At base 100 / growth 18: level 1 costs 100, level 50 costs 982, level 99
--- costs 1864, and a full 0 -> 100 run is about 98,200 XP.
Skills.XP_BASE = 100
Skills.XP_GROWTH = 18

function Skills.xpToNext(level)
    if level >= Skills.MAX_LEVEL then return 0 end
    if level < 0 then level = 0 end
    return math.floor(Skills.XP_BASE + (Skills.XP_GROWTH * level) + 0.5)
end

--- Total XP required to REACH `level` from zero.
function Skills.xpForLevel(level)
    if level <= 0 then return 0 end
    if level > Skills.MAX_LEVEL then level = Skills.MAX_LEVEL end
    local total = 0
    for n = 0, level - 1 do total = total + Skills.xpToNext(n) end
    return total
end

--- Resolve a raw XP total into level and progress.
---
--- Returns: level, xpIntoLevel, xpNeededForNext, fraction 0..1
---
--- Deriving the level from total XP rather than storing it separately means the
--- two can never disagree — a stored level that drifted from its XP would show
--- one number and grant the stat for another.
function Skills.resolve(xp)
    xp = math.max(0, math.floor(tonumber(xp) or 0))
    local level = 0
    local remaining = xp

    while level < Skills.MAX_LEVEL do
        local need = Skills.xpToNext(level)
        if remaining < need then break end
        remaining = remaining - need
        level = level + 1
    end

    if level >= Skills.MAX_LEVEL then
        return Skills.MAX_LEVEL, 0, 0, 1.0
    end

    local need = Skills.xpToNext(level)
    return level, remaining, need, need > 0 and (remaining / need) or 0.0
end

--- Normalise a stored skill table into { id = xp } with every skill present.
---
--- Storage comes back from a database, an export, or a KVP written by an older
--- version, so it may be missing keys, carry keys that no longer exist, or be
--- the wrong type entirely. Everything downstream is allowed to assume the
--- shape this returns.
function Skills.normalise(stored)
    local out = {}
    if type(stored) ~= 'table' then stored = {} end
    for i = 1, #Skills.List do
        local id = Skills.List[i].id
        local v = tonumber(stored[id])
        -- NaN fails both comparisons, which is what rejects it here.
        if not v or v ~= v or v < 0 then v = 0 end
        out[id] = math.floor(v)
    end
    return out
end

return Skills
