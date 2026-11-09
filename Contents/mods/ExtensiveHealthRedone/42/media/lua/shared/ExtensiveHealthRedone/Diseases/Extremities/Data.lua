-- Every number of the extremities group in one place. Hours are game hours.

local Data = {}

-- Foot blisters (Diseases/Extremities/Blisters): friction hours per foot, built by walking in shoes.
Data.blisters = {
    -- Friction gained per hour on the move, by gait. In good footwear a hot spot takes about 12 h of walking (a long
    -- hike), 3 h of running or 1.5 h of sprinting.
    GAIT = { walk = 0.25, run = 1, sprint = 2 },
    -- Multipliers on that gain.
    NO_SOCKS = 2.0,         -- shoes on bare feet
    WET_SOCKS = 1.75,       -- socks at least WET
    WET = 0.35,
    WORN = 0.5,             -- shoes with less than this share of their condition left
    WORN_MULT = 1.25,
    WORN_OUT = 0.25,        -- and less than this
    WORN_OUT_MULT = 1.5,
    SHOE_HOLES = 1.15,
    SOCK_HOLES = 1.25,
    PATCH = 0.15,           -- a blister patch on (flag blisterPatch)
    BANDAGE = 0.4,          -- a clean bandage on that foot
    -- Friction falls at rest (per hour), faster asleep.
    DECAY_REST = 1,
    DECAY_SLEEP = 2,
    -- Friction hours for stages 1 (hot spot), 2 (blister), 3 (burst); the meter stops at MAX_H.
    STAGE_H = { 3, 5, 7 },
    MAX_H = 8,
    -- Healing: hours of healing that take a foot down one stage from stage 1, 2, 3, and the healing speed by what the
    -- foot is doing. Bad going (running, wet or no socks, worn or holed shoes) pauses healing; careful walking in good
    -- footwear heals slowly and rubs no further.
    HEAL_H = { 4, 24, 36 },
    HEAL_REST = 1,
    HEAL_SLEEP = 1.5,
    HEAL_WALK = 0.5,
    HEAL_PATCH = 2,
    -- Per stage: pain on the foot, movement speed (the worst foot).
    PAIN = { 6, 14, 24 },
    SPEED = { 0.98, 0.94, 0.88 },
    -- The Medical Alert counts blisters from this stage (a hot spot alone doesn't light it).
    ALERT_FROM = 2,
}

-- Trench foot (Diseases/Extremities/TrenchFoot): hours of cold, wet feet per foot (wetColdH). A non-freezing cold
-- injury: wet socks at or below MaxTemperature (sandbox TrenchFootMaxTemperature) for days.
Data.trenchFoot = {
    WET = 0.35,             -- feet at least this wet count
    SOAKED = 0.7,           -- and this wet count faster
    SOAKED_MULT = 1.5,
    DRY = 0.15,             -- below this the feet are dry: the meter falls and the feet recover
    POWDER = 0.5,           -- foot powder on damp feet (flag footPowder)
    POWDER_SOAKED = 0.85,   -- powder can't dry soaked socks
    DECAY = 1,              -- meter fall per hour while dry
    DECAY_WARM_REST = 3,    -- while dry, warm and resting
    -- Stage thresholds in multiples of TrenchFootHours (default 12 h: stage 1 after half a day of cold, wet feet).
    STAGE_X = { 1, 2, 4, 6 },
    -- Hours of dry feet that take a foot down one stage from stage 1-4, and the speed-ups.
    DRY_H = { 4, 12, 24, 48 },
    REST = 1.5,             -- resting or asleep
    WARM = 1.5,             -- near heat, indoors or a Warming Pack
    POWDER_HEAL = 1.25,
    -- Per stage: pain on the foot, movement speed (worst foot); stage 3+ no sprint and halved healing; the skin breaks
    -- (a scratch) every MACERATION_H at stage 3+; stage 4 slowly damages the foot.
    PAIN = { 8, 18, 30, 40 },
    SPEED = { 0.97, 0.92, 0.85, 0.75 },
    NO_SPRINT_FROM = 3,
    HEAL_FACTOR = 0.5,
    MACERATION_H = 8,
    NECROSIS_DAMAGE_H = 0.5,    -- foot health per hour at stage 4
    -- XP for getting over it only from this stage (a damp afternoon isn't First Aid practice).
    XP_FROM = 2,
}

-- Frostbite (Diseases/Extremities/Frostbite): frozen tissue on hands and feet. The frost meter grows while a part's
-- effective temperature is below FrostbiteTemperature (sandbox, default -10 deg C).
Data.frostbite = {
    -- Effective temperature = air (wind chill outdoors) + clothing insulation over the part (vanilla's thermal node,
    -- which already drops when the clothing is wet) x INSULATION_C, - WET_C on a wet part, - core cold.
    INSULATION_C = 15,
    WET = 0.35,
    WET_C = 8,
    CORE_COLD_C = 3,        -- body temperature below CORE_COLD_BODY_C: the body pulls blood from the hands and feet
    CORE_COLD_BODY_C = 36,
    HYPOTHERMIA_C = 6,      -- hypothermia stage 2+
    -- Frost gained per hour: ((threshold - effective) / 10) ^ POWER.
    POWER = 1.5,
    PACK_HANDS = 0.5,       -- an active Warming Pack (held in the hands) halves the gain on the hands
    -- Frost for stages 1 (frostnip), 2 (superficial), 3 (deep), 4 (necrosis); the meter stops at MAX.
    STAGE = { 1, 3, 6, 10 },
    MAX = 12,
    -- Rewarming: effective temperature at or above WARM_C, or warm surroundings (Inputs.warm). The meter falls by
    -- DECAY per hour, and a part steps down one stage after THAW_H[stage] hours of rewarming (stage 4 never while it
    -- is gangrenous); near heat or with a Warming Pack frostnip thaws THAW_HEAT_NIP times faster and deeper stages
    -- THAW_HEAT times.
    WARM_C = 5,
    DECAY = 1,
    THAW_H = { 1, 48, 72, 72 },
    THAW_HEAT_NIP = 3,
    THAW_HEAT = 1.5,
    -- Per stage: pain (stage 4 is numb), aim on the worst hand, speed on the worst foot; stage 3+ on a foot stops
    -- sprinting; stage 3 halves healing on the part, stage 4 stops it and damages the part.
    PAIN = { 6, 16, 28, 12 },
    AIM = { 0.95, 0.85, 0.7, 0.6 },
    SPEED = { 0.97, 0.9, 0.82, 0.75 },
    NO_SPRINT_FROM = 3,
    HEAL_FACTOR = { [3] = 0.5, [4] = 0 },
    NECROSIS_DAMAGE_H = 0.3,
    XP_FROM = 2,
}

-- Gangrene (Diseases/Extremities/Gangrene): dead tissue that rots. Starts on a hand or foot held at stage 4
-- (necrosis) of trench foot or frostbite for GangreneOnsetHours; untreated stage 4 turns into sepsis.
Data.gangrene = {
    -- Stage lengths (hours, divided by DiseaseSpeed).
    STAGES = { [1] = { 12, 24 }, [2] = { 24, 36 }, [3] = { 24, 48 }, [4] = { 6, 12 } },
    BLOCK_AFTER_CURE_H = 48,
    -- Per stage: pain on each gangrenous part, part damage per hour, and from stage 2 fever, sickness and fatigue.
    ROWS = {
        [1] = { pain = 25, damage = 0.2 },
        [2] = { pain = 35, damage = 0.4, sickness = 0.2, fatigue = 0.2, fever = 38.0, feverStep = 0.03 },
        [3] = { pain = 45, damage = 0.6, sickness = 0.4, fatigue = 0.35, fever = 38.8, feverStep = 0.045 },
        [4] = { pain = 45, damage = 0.6, sickness = 0.45, fatigue = 0.4, fever = 39.2, feverStep = 0.05 },
    },
}

return Data
