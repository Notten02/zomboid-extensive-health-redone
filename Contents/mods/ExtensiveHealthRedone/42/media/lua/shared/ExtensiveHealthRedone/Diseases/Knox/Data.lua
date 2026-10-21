-- Knox numbers. From v0.9 EHR_KnoxCure.lua (docs/porting/phase4/mental-knox-sounds.md, section 4) unless marked
-- "ours". W33 (decided 2026-10-07): the side effects the tooltips promise are applied.

return {
    -- Gene therapy success chance (%) by blood type; 50 when the type is unknown.
    GENE_THERAPY_CHANCE = {
        ["O-"] = 95, ["O+"] = 85, ["A-"] = 75, ["B-"] = 75, ["A+"] = 65, ["B+"] = 65, ["AB-"] = 50, ["AB+"] = 40,
    },
    GENE_THERAPY_DEFAULT_CHANCE = 50,
    GENE_THERAPY_HEALTH_COST = 10,      -- W33: 10% of health on success (one-off damage)

    -- Antibody test bands: the first band whose minimum the chance reaches.
    RATINGS = {
        { min = 75, key = "UI_EHR_KnoxCure_Rating_High" },
        { min = 50, key = "UI_EHR_KnoxCure_Rating_Moderate" },
        { min = 25, key = "UI_EHR_KnoxCure_Rating_Low" },
        { min = 0, key = "UI_EHR_KnoxCure_Rating_Critical" },
    },

    -- Immunobooster
    BOOSTER_MINUTES = 24 * 60,
    BOOSTER_COOLDOWN_MINUTES = 7 * 24 * 60,
    BOOSTER_NAUSEA = 0.2,               -- food sickness floor while active, share of the range
    BOOSTER_ENDURANCE_FLOOR = 0.3,      -- "slower stamina regeneration": endurance drains toward this
    BOOSTER_ENDURANCE_DRAIN = 0.00125,  -- per game minute (v0.9: 0.001 per 60 ticks)
    TREMOR_EVERY = { 60, 120 },         -- ours: game minutes between tremors (W33)
    TREMOR_ENDURANCE = 0.05,            -- ours: endurance lost to a tremor

    -- Phalanx: progress (share of the infection's range) each dose resets to, by dose number. Later doses do nothing.
    PHALANX_RESET = { 0, 0.25, 0.50, 0.75 },
    PHALANX_NAUSEA_MINUTES = 6 * 60,
    PHALANX_NAUSEA = 0.6,               -- food sickness target, share of the range
    PHALANX_NAUSEA_STEP = 0.02,         -- ours: per game minute
    PHALANX_FEVER_MINUTES = 12 * 60,
    PHALANX_FEVER = 38.5,               -- deg C
    PHALANX_FEVER_STEP = 0.01,          -- ours: deg C per game minute
    PHALANX_DEBUFF_MINUTES = 48 * 60,   -- immune debuff; Immunity/Immunity reads state.knox.effects.phalanxDebuff
    PHALANX_DEBUFF_POINTS = 20,         -- immunity target penalty while the debuff runs

    -- Gene therapy survivors get the odd migraine: v0.9 rolled 0.001 per 60 ticks (1.25 rolls per game minute).
    MIGRAINE_CHANCE = 0.001,
    MIGRAINE_ROLLS_PER_MINUTE = 1.25,
    MIGRAINE_PAIN = 20,                 -- one-off head pain
    MIGRAINE_LINE_ONE_IN = 20,

    -- The display condition's stages: progress at or above these bounds (v0.9 0.2/0.5/0.8).
    STAGE_FROM = { 0, 0.2, 0.5, 0.8 },
    -- Synced progress steps (share of the range), so the condition section isn't sent every minute.
    PROGRESS_STEP = 0.01,

    -- The Kentucky Herald, July 16 1993 (vanilla print media id KentuckyHerald_July16, inferred from its
    -- translation keys). Ids and titles are matched after removing everything but letters and digits.
    HERALD_MATCH = "kentuckyheraldjuly16",
    HERALD_IDS = { "KentuckyHerald_July16", "Print_Media_KentuckyHerald_July16_title" },
}
