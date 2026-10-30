-- Blood numbers.
--
-- Time base: amounts "per update" follow the original mod, which ran blood once per real second. We run per game
-- minute. With the default 1-hour day, one real second is 0.4 game minutes, so a per-update amount is
-- UPDATES_PER_MINUTE times that per game minute.
-- Sandbox options are read at run time; their defaults live in sandbox-options.txt.

return {
    UPDATES_PER_MINUTE = 2.5,

    MAX_ML = 5000,

    -- Bleeding: per bleeding, unbandaged part and update,
    --   min(PART_CAP, (100 - partHP) * wound * part * LOSS_SCALE) * BloodLossMultiplier
    LOSS_SCALE = 0.5,
    PART_CAP = 5.0,
    -- The neck bleeds harder from anything worse than a scratch: part rate and cap x NECK_BOOST.
    NECK_BOOST = 1.4,
    -- Wound types, highest match wins. "other" is a bleeding part with none of these.
    WOUND = { deep = 0.40, bullet = 0.25, glass = 0.25, cut = 0.12, bite = 0.08, scratch = 0.02, other = 0.15 },
    WOUND_ORDER = { "deep", "bullet", "glass", "cut", "bite", "scratch" },
    PART = {
        Neck = 2.5, Groin = 2.0, Torso_Upper = 1.5, Head = 1.4, Torso_Lower = 1.3,
        UpperLeg_L = 1.2, UpperLeg_R = 1.2, UpperArm_L = 1.0, UpperArm_R = 1.0,
        ForeArm_L = 0.7, ForeArm_R = 0.7, LowerLeg_L = 0.6, LowerLeg_R = 0.6,
        Hand_L = 0.4, Hand_R = 0.4, Foot_L = 0.3, Foot_R = 0.3,
    },
    PART_DEFAULT = 0.8,

    -- Stages: 4 healthy, 3 mild, 2 moderate, 1 critical. Thresholds are sandbox options (85/80/70 %).
    -- Endurance ceiling per stage: growing penalties, no endurance at Critical.
    ENDURANCE_CEILING = { [3] = 0.75, [2] = 0.5, [1] = 0 },
    -- Movement speed multiplier per stage, applied by the owning client.
    SPEED = { [4] = 1.0, [3] = 1.0, [2] = 0.8, [1] = 0.5 },
    -- Random lines: "1 in N" per update, scaled by DialogueFrequency.
    LIGHTHEADED_ONE_IN = 400,
    UNCONSCIOUS_ONE_IN = 100,

    -- Beta blocker: below this share of blood, effects behave as if blood were SHIFT lower.
    BETA_BELOW = 0.90,
    BETA_SHIFT = 0.05,

    -- Blackout at Critical: forced sleep, rolled 1 in BlackoutChance per update.
    BLACKOUT_HOURS = 1,
    BLACKOUT_GATE = 0.5,        -- panic or stress above this share of the range prevents it (unless beta blocker)
    BLACKOUT_GRACE = 3,         -- game minutes before "not asleep" counts as waking (MP latency)

    -- Death.
    DEATH_INSTANT = 0.05,
    DEATH_CHANCE_BELOW = 0.20,
    DEATH_ONE_IN = 50,

    -- Regeneration bonus while the healing conditions hold.
    REGEN_BONUS = 1.5,

    -- Saline and hemodilution (saline mL / blood mL).
    SALINE_ML = 250,
    SALINE_DECAY = 0.5,         -- mL per update
    DILUTION_WARNING = 0.40,
    DILUTION_LETHAL = 0.60,
    WARNING_FATIGUE = { target = 0.8, step = 0.02 },     -- per update, fraction of range
    WARNING_ENDURANCE = { target = 0.3, step = 0.05 },
    LETHAL_DAMAGE = 2,          -- overall health per update
    WARNING_LINE_ONE_IN = 200,
    LETHAL_LINE_ONE_IN = 30,
    WARNING_LINES = {
        "UI_EHR_Hemodilution_Warning_1", "UI_EHR_Hemodilution_Warning_2",
        "UI_EHR_Hemodilution_Warning_3", "UI_EHR_Hemodilution_Warning_4",
    },
    LETHAL_LINES = {
        "UI_EHR_Hemodilution_Lethal_1", "UI_EHR_Hemodilution_Lethal_2",
        "UI_EHR_Hemodilution_Lethal_3", "UI_EHR_Hemodilution_Lethal_4",
    },

    -- Conditional healing thresholds (fractions of each stat's range; pain 5 of 100).
    HEALING = { hunger = 0.3, thirst = 0.3, stress = 0.5, fatigue = 0.5, pain = 0.05, fatigueBypassHealth = 10 },

    -- Transfusion and draw.
    BAG_ML = 500,
    DRAW_ML = 500,
    DRAW_MINIMUM = 0.80,
    DRAW_FATIGUE = 0.15,
    DRAW_ENDURANCE = 0.2,
    -- A lab blood sample (Zombie Virus Vaccine's syringe draw, Server/ZVirusVaccine): a few mL of 5000.
    SAMPLE_ML = 50,
    SAMPLE_MINIMUM = 0.5,
    SALINE_THIRST = 0.1,
    -- Incompatible blood: immediate reaction (fractions of range).
    INCOMPATIBLE = { SICKNESS = 0.18, FOOD_SICKNESS = 0.12, PANIC = 0.35, PAIN = 0.12, lossMl = 150 },
    -- Stale bag: spoiled-blood reaction on top of the transfusion.
    STALE = {
        SICKNESS = 0.6, FOOD_SICKNESS = 0.7, PANIC = 0.4, PAIN = 0.5, lossMl = 150,
        feverC = 2, parts = 4, partDamage = { 10, 24 },
    },
    -- AHTR on incompatible blood: start at least this severity; worsen by STEP up to MAX and keep 72 h left.
    AHTR_SEVERITY = 0.95,
    AHTR_WORSEN_STEP = 0.25,
    AHTR_WORSEN_MAX = 1.25,
    AHTR_MIN_LEFT_HOURS = 72,

    -- Spoilage, in warm game hours (frozen time doesn't count).
    STALE_HOURS = 1.0,
    ROTTEN_HOURS = 2.0,
    SPOILAGE_KEY = "EHR_BloodSpoilage",     -- item modData, the original mod's format (save compatible)
    DONOR_KEY = "EHR_DonorBloodType",       -- item modData, as the original mod wrote it

    -- Blood type knowledge for compatibility hints: the flyer's knowledge ID, or First Aid at least this level.
    KNOWLEDGE_ID = "blood_types",
    KNOWLEDGE_FIRST_AID = 8,
}
