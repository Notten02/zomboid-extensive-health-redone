-- The immune system's numbers (v0.9 EHR_Immunity.lua; docs/porting/phase6/immunity.md). The score (0-100) moves
-- every 15 game minutes toward a target made of six weighted factors, minus a hygiene penalty; systemic antibiotics,
-- immunosuppression and the Phalanx debuff push it down. Diseases read it through Conditions/Risk.

return {
    NEUTRAL = 50,                   -- the score at which immunity changes no chance
    START = 75,                     -- a new character's score (maintainer, Phase 6); it then drifts to its target

    -- How strongly the score changes the chance of catching each supported disease (v0.9 :21-31, tuberculosis
    -- dropped). Diseases not listed are not affected by immunity.
    -- Multiplier at full strength: 1 - 0.35 at score 100, 1 + 0.50 at score 0, linear from the neutral score.
    BEST = 0.35,
    WORST = 0.50,
    SENSITIVITY = {
        common_cold = 0.85,
        pneumonia = 0.80,
        dysentery = 0.65,
        gastroenteritis = 0.75,
        cadaveric_aspergillosis = 1.00,
        hyperkeratotic_scabies = 0.85,
        cellulitis = 0.90,
    },

    -- Cadence and movement (v0.9 :13-16): one update every 15 game minutes, rising 1.5 and falling 3 points per game
    -- hour, times ImmunityRecoveryRate / ImmunityDeclineRate.
    TICK_MINUTES = 15,
    RISE_PER_HOUR = 1.5,
    FALL_PER_HOUR = 3.0,
    SETTLE = 0.05,                  -- closer than this to the target counts as there

    -- The target: sum of factor x weight (the weights add up to 1), minus the hygiene penalty (v0.9 :37-44).
    WEIGHTS = {
        nutrition = 0.22,           -- (1 - hunger) x 100
        hydration = 0.18,           -- (1 - thirst) x 100
        rest = 0.22,                -- 100 up to REST_FROM fatigue, then falling to 0 at full fatigue
        stressControl = 0.10,       -- (1 - stress) x 100
        bloodCondition = 0.13,      -- 0 at BLOOD_FLOOR % blood, 100 at full blood
        healthReserve = 0.15,       -- overall health minus disease pressure
    },
    FACTOR_ORDER = { "nutrition", "hydration", "rest", "stressControl", "bloodCondition", "healthReserve" },
    REST_FROM = 0.5,
    BLOOD_FLOOR = 40,

    -- Disease pressure, subtracted from health in healthReserve (v0.9 :155-188): each active condition 8 + 2 x stage,
    -- each infected wound 6 + 2 x stage (incubations don't count), sepsis a flat 25; at most 70.
    PRESSURE = {
        CONDITION_BASE = 8, CONDITION_PER_STAGE = 2,
        WOUND_BASE = 6, WOUND_PER_STAGE = 2,
        SEPSIS = 25,
        MAX = 70,
        IGNORE = { knox_infection = true },     -- display-only mirror of vanilla's Knox infection
        -- Mental conditions count half (maintainer, Phase 6).
        HALF = { painkiller_addiction = true, insomnia = true, delirium = true },
    },

    -- Hygiene penalty from average dirt and blood in percent (v0.9 :190-278): piecewise linear through these
    -- { percent, penalty } points, the two penalties together at most HYGIENE_MAX.
    DIRT_CURVE = { { 5, 0 }, { 20, 12 }, { 50, 25 }, { 100, 35 } },
    BLOOD_CURVE = { { 2, 0 }, { 20, 16 }, { 50, 30 }, { 100, 40 } },
    HYGIENE_MAX = 55,

    -- Suppression (guide "Antibiotic Suppression"): while a systemic antibiotic (the "antibiotic" medication flag;
    -- ointments don't carry it) or the immunosuppression side effect is active, the target is capped at 35 and a
    -- score above 35 falls 4 points per update (x ImmunityDeclineRate), instead of the normal movement.
    SUPPRESSED_CAP = 35,
    SUPPRESSED_STEP = 4,

    -- Status bands (guide "Immune Status"): the lowest score of each band, best first.
    BANDS = {
        { from = 80, id = "Strong" },
        { from = 60, id = "Stable" },
        { from = 40, id = "Strained" },
        { from = 20, id = "Compromised" },
        { from = 0, id = "Suppressed" },
    },
}
