-- Trichinosis: from raw wild game or pork (Diseases/Food/Risk). Muscle aches, then peak muscle pain, fever, movement
-- and endurance penalties with lethal health loss at stage 3, then a weak recovery. Incubation 24-48 h, then 7-12
-- days. Muscle pain goes on the limb and torso parts on the 0-100 pain scale; muscle relief only eases this disease's
-- pain, not other sources' pain on the limbs.
--
-- Treatment: cure Antiparasitic Pills (long course), Albendazole Injection (fast).
-- Relief: Muscle Relaxants / Homemade (muscleSpasms .40, pain .30), Anti-Inflammatory (pain .55, fever .30),
-- Antipyretic (fever).

local Data = require "ExtensiveHealthRedone/Diseases/Food/Data"
local Common = require "ExtensiveHealthRedone/Diseases/Food/Common"
local Symptoms = require "ExtensiveHealthRedone/Conditions/Symptoms"
local Speech = require "ExtensiveHealthRedone/Core/Speech"
local BodyParts = require "ExtensiveHealthRedone/Data/BodyParts"

local ID = "trichinosis"

-- Per engine check (Data TICK). pain: AdditionalPain per muscle part at severity 1. speed: the movement penalty.
local ROWS = {
    [2] = { drain = 0.007, floor = 0.70, fatigue = 0.35, sickness = 0.35, pain = 18, fever = 38.0, feverStep = 0.028,
            cramp = 0.003, feverLine = 0.0015, thirst = 0.5, speed = 0.9 },
    [3] = { drain = 0.016, floor = 0.40, fatigue = 0.72, sickness = 0.70, pain = 40, fever = 38.9, feverStep = 0.045,
            cramp = 0.009, feverLine = 0.004, thirst = 1.0, speed = 0.8 },
    [4] = { drain = 0.003, floor = 0.82, fatigue = 0.22, sickness = 0.16, pain = 8, fever = 37.4, feverStep = 0.020,
            cramp = 0.0005, feverLine = 0, thirst = 0.25 },
}
local COOLDOWN = 15             -- game minutes between cramps and between fever lines
local CRAMP_PARTS = { "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R" }
local FEVER_LINES = { "UI_EHR_Text_ImBurningUp", "UI_EHR_Text_FeelingWeak" }

local def = {
    enabledOption = "TrichinosisEnabled", speedOption = "DiseaseSpeed",
    incubation = { 24, 48 }, duration = { 168, 288 }, baseSeverity = 0.75,
    name = "UI_EHR_Disease_trichinosis", knowledge = ID,
    lines = {
        stage = {
            [2] = "UI_EHR_Text_MyMusclesAreStartingToAcheBadly",
            [3] = "UI_EHR_Text_GaspsInPainEveryMuscleIsOnFire",
            [4] = "UI_EHR_Text_ThePainIsFinallySubsiding",
        },
        random = {
            [2] = { "UI_EHR_Text_MyMusclesHurtSoMuch", "UI_EHR_Text_ICanBarelyMove",
                "UI_EHR_Text_ShouldHaveCookedThatMeatLonger" },
            [3] = { "UI_EHR_Text_ScreamsInPain", "UI_EHR_Text_ItFeelsLikeParasitesAreInMyMuscles",
                "UI_EHR_Text_IMightDieFromThis" },
            [4] = { "UI_EHR_Text_SlowlyGettingBetter", "UI_EHR_Text_NeverEatingRawMeatAgain" },
        },
        every = Data.LINE_EVERY,
    },
    onEnd = Common.onEnd,
}

function def.effects(p, c, dt, curing)
    local row = ROWS[c.stage]
    if not row then
        return
    end
    local sev = c.severity
    local t = p.treatment
    local m = Common.mults(p, ID)
    local k = Data.TICK * dt
    local muscle = t:relief(ID, "muscleSpasms")
    local painRelief = math.max(t:relief(ID, "pain"), 0.6 * t:relief(ID, "inflammation"))
    local feverRelief = t:relief(ID, "fever")

    Common.drainEndurance(p, ID, row.drain * sev * m.weakness, row.floor, dt)
    p.stats:raiseF("FATIGUE", ID, row.fatigue * sev, 0.0035 * sev * k)
    p.stats:raiseF("SICKNESS", ID, math.min(Common.SICKNESS_CAP, row.sickness * sev * math.max(0.25, 1 - 1.4 * feverRelief)),
        0.004 * sev * k)
    p.stats:addF("THIRST", ID, 0.00055 * sev * row.thirst * k)

    local pain = row.pain * sev * m.symptom * math.max(0.25, 1 - 1.5 * painRelief) * math.max(0.12, 1 - 2 * muscle)
    for _, part in ipairs(BodyParts.muscles) do
        p.body:pain(part, ID, pain)
    end

    local target, step = row.fever, row.feverStep * sev * math.max(0.25, m.symptom) * k
    if curing then
        target, step = math.min(target, c.stage == 3 and 38.1 or 37.6), step * 1.5
    end
    target, step = Symptoms.fever(target, step, feverRelief)
    Symptoms.applyFever(p, ID, target, step)

    if Common.symptom(p, c, "crampIn", row.cramp * sev * math.max(0.1, 1 - 2 * muscle), COOLDOWN, dt) then
        Speech.stage(p, Speech.pick(p, Data.CRAMP_LINES))
        p.body:addPain(Speech.pick(p, CRAMP_PARTS), ID, 10)
    end
    if row.feverLine > 0 and Common.symptom(p, c, "feverLineIn", row.feverLine * sev, COOLDOWN, dt) then
        Speech.stage(p, Speech.pick(p, FEVER_LINES))
    end
    if row.speed then
        p.fx:speed(ID, row.speed)
    end
    -- About 1.1 + 2.2 x severity every 0.25 h with no regeneration; a kill roll below 20 health.
    if c.stage == 3 and not curing then
        Common.drain(p, ID, c, dt, 1.1 + 2.2 * sev, 15, 20, 0.02 * sev)
    end
end

return def
