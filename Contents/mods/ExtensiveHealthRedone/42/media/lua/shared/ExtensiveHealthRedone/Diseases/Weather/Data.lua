-- Numbers for the environmental diseases: common cold, pneumonia, hypothermia, heat exhaustion, heat stroke, and the
-- cold and heat exposure meters.
--
-- Time base: "per update" numbers are per environmental update of the original mod, every 90 ticks = 3 real seconds
-- = 1.2 game minutes with the default 1-hour day. A "per update" amount is therefore PER_MINUTE times that per game
-- minute, and a "per update" chance uses Chance.over(p, PER_MINUTE, dt).

local Data = {}

Data.PER_MINUTE = 1 / 1.2

-- Cold exposure (meters in hours of exposure). The cold-and-wet route starts at 5 deg C.
Data.cold = {
    FREEZING_C = 5,
    WET = 0.30, SOAKED = 0.70, HEAVILY_SOAKED = 0.90,
    -- isWarm: indoors with body above 36.2 deg C, or body above 36.84 deg C
    WARM_INDOORS_BODY_C = 36.2, WARM_BODY_C = 36.84,
    GAIN = 1.5, GAIN_SOAKED = 2.25, DECAY = 1, DECAY_WARM = 2, DECAY_BATHING = 3,
    READY_FREEZING_H = 2.0, READY_SOAKED_H = 1.0,
    -- chance = min(cap, base x meter / ready), once per game hour while ready and at risk
    FREEZING_BASE = 0.10, FREEZING_CAP = 0.35, SOAKED_BASE = 0.08, SOAKED_CAP = 0.25,
    ROLL_EVERY = 60,
}

-- Heat exposure (meter in hours; full = HeatExposureHoursToFull).
Data.heat = {
    RECOVER_INDOORS = 2.25, RECOVER_OFF_HOURS = 1.25, RECOVER_COOL = 1.25, RECOVER_SHADE = 0.625,
    SHADE_MAX_C = 35,
    PER_DEGREE = 0.06, MAX_HEAT_MULT = 1.75,
    EXERTING = 1.25, THIRSTY = 1.15, VERY_THIRSTY = 1.25, SHADE = 0.35,
    THIRSTY_AT = 0.4, VERY_THIRSTY_AT = 0.7,
    -- heat stroke: guaranteed from a full meter; between 85% and 100% a roll every 5 game minutes
    STROKE_RISK = 0.85, STROKE_ROLL_EVERY = 5, STROKE_BASE = 0.35, STROKE_SPAN = 0.65, STROKE_MAX = 0.95,
    STROKE_THIRSTY = 1.15, STROKE_VERY_THIRSTY = 1.35, STROKE_EXERTING = 1.15,
    DISPLAY_MAX = 1.25,
    -- Heat exhaustion stages: stage 1/2/3 from these meter shares; stage 4 while the meter falls for
    -- FALLING_MINUTES; recovered below END.
    EXHAUSTION = { [1] = 0.35, [2] = 0.60, [3] = 0.85 }, EXHAUSTION_END = 0.10, FALLING_MINUTES = 5,
}

-- Common cold: per stage. sneezeH = game hours between sneezes; fatigue raised toward a cap by step per update;
-- fever target / step per update; vanilla cold strength; sickness shown (0-1).
Data.commonCold = {
    [1] = { cold = 0, sneezeH = 3, sickness = 0.10 },
    [2] = { cold = 35, sneezeH = 1, fatigue = 0.10, fatigueStep = 0.001, fever = 37.6, feverStep = 0.018,
            sickness = 0.35 },
    [3] = { cold = 65, sneezeH = 0.5, fatigue = 0.60, fatigueStep = 0.003, fever = 38.0, feverStep = 0.025,
            sickness = 0.60 },
    [4] = { cold = 0, sneezeH = 3, sickness = 0.20 },
    PNEUMONIA_CHANCE = 0.35,
}

-- Pneumonia: per stage. coughH = game hours between coughs; chest pain on Torso_Upper; endurance cap; health drain
-- (HP per game hour) and floor; fatigue toward a cap.
Data.pneumonia = {
    [1] = { coughH = 2.0, severe = false, chestPain = 6, fever = 38.0, feverStep = 0.030,
            fatigue = 0.30, fatigueStep = 0.001, sickness = 0.10 },
    [2] = { coughH = 1.0, severe = true, chestPain = 20, endurance = 0.70, fever = 40.0, feverStep = 0.070,
            fatigue = 0.50, fatigueStep = 0.005, sickness = 0.35 },
    [3] = { coughH = 0.75, severe = true, chestPain = 30, endurance = 0.70, fever = 40.0, feverStep = 0.075,
            drain = 2.5, floor = 30, fatigue = 0.70, fatigueStep = 0.010, sickness = 0.60 },
    [4] = { coughH = 0.75, severe = true, chestPain = 35, endurance = 0.70, fever = 40.0, feverStep = 0.075,
            drain = 4.0, floor = 0, fatigue = 0.80, fatigueStep = 0.012, sickness = 0.20 },
    CHEST_PAIN_MAX = 70,
}

-- Hypothermia: per stage (stages come from body temperature, see the sandbox HypothermiaStage*Temp options).
-- Chances are per update.
Data.hypothermia = {
    [1] = { speed = 0.90, endurance = 0.86, fatigue = 0.40, fatigueStep = 0.00035 },
    [2] = { speed = 0.76, noSprint = true, endurance = 0.70, fatigue = 0.55, fatigueStep = 0.00075, drain = 2,
            confusion = 0.002 },
    [3] = { speed = 0.52, noSprint = true, endurance = 0.45, fatigue = 0.70, fatigueStep = 0.0012, drain = 8,
            confusion = 0.006, dizziness = 0.010 },
    [4] = { speed = 0.42, noSprint = true, endurance = 0.32, fatigue = 0.85, fatigueStep = 0.0018, drain = 18,
            confusion = 0.010, dizziness = 0.016, blackout = 0.008 },
    HYSTERESIS = 0.25,
    MIN_GAP = 0.1,
    BLACKOUT_COOLDOWN = 45,          -- game minutes (0.75 h)
    PLAUSIBLE_MIN_C = 20,            -- body temperatures below this are a sensor glitch, never hypothermia
}

-- Heat exhaustion: per stage.
Data.heatExhaustion = {
    [1] = { thirst = 0.0015 },
    [2] = { thirst = 0.0025, cramps = 12, speed = 0.9 },
    [3] = { thirst = 0.0035, cramps = 12, speed = 0.8, noSprint = true, nausea = 0.30, dizzy = 0.3 },
    [4] = { thirst = 0.001 },
    CRAMP_PARTS = { "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R" },
}

-- Heat stroke: per stage. The drain starts at stage 2. thirst per update; chances
-- per update except collapse (per 5 game minutes).
Data.heatStroke = {
    [1] = { fever = 40.5, feverStep = 0.110, thirst = 0.004, speed = 0.65, dizziness = 0.08, confusion = 0.08,
            collapse = 0.50 },
    [2] = { fever = 40.5, feverStep = 0.120, drain = 15, thirst = 0.010, speed = 0.50, dizziness = 0.12,
            confusion = 0.12, collapse = 0.60 },
    [3] = { fever = 40.5, feverStep = 0.130, drain = 36, thirst = 0.016, speed = 0.35, dizziness = 0.18,
            confusion = 0.18, collapse = 0.70 },
    [4] = { fever = 40.5, feverStep = 0.100, drain = 24, thirst = 0.008, speed = 0.50, dizziness = 0.12,
            confusion = 0.12, collapse = 0.50 },
    COLLAPSE_EVERY = 5,              -- game minutes
    COLLAPSE_COOLDOWN = 45,          -- game minutes after a collapse
    COOLING_FEVER = 37.2, COOLING_STEP = 0.22,
    AMBIENT_COOL_C = 10, AMBIENT_CURE_MINUTES = 180, AMBIENT_DECAY = 0.5,
    BATH_MINUTES = 180, BATH_HEARTBEAT_MINUTES = 15, BATH_WATER = 8,
}

-- Shared symptom episodes.
Data.episodes = {
    BLUR = 0.5, BLUR_MINUTES = { 5, 10 },           -- dizziness blur
    DIZZY_PANIC = 0.2, CONFUSION_PANIC = 0.15,      -- fractions of the panic range
}

return Data
