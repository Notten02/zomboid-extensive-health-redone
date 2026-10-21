-- Pneumonia: from an untreated common cold (W14: no other source). Coughs that draw zombies, chest pain, fever, an
-- endurance cap from stage 2, and a health drain from stage 3 (to 30 HP) that turns lethal in stage 4. An active cure
-- course holds the stage and pauses the drain. From v0.9 EHR_EnvironmentalDiseases.lua:2621-2682, :2950-3137 and
-- EHR_DiseaseDefinitions.lua:140-239 (docs/porting/phase4/environmental.md, section 2).
--
-- Treatment (Phase 5, through p.treatment): cure courses Prescription, Broad Spectrum or Plant-Based Antibiotics
-- (72 h), IV Ciprofloxacin (24 h); vanilla Antibiotics only minor help. Relief: Bronchodilator
-- ("breathingDifficulty", lifts the endurance cap), cough medicine ("coughing"), Antipyretic ("fever"), "pain".

local Data = require "ExtensiveHealthRedone/Diseases/Weather/Data"
local Episodes = require "ExtensiveHealthRedone/Diseases/Weather/Episodes"
local Symptoms = require "ExtensiveHealthRedone/Conditions/Symptoms"
local Speech = require "ExtensiveHealthRedone/Core/Speech"

local D = Data.pneumonia
local K = Data.PER_MINUTE

local Pneumonia = {
    enabledOption = "PneumoniaEnabled", speedOption = "DiseaseSpeed",
    incubation = { 12, 24 }, duration = { 120, 216 }, baseSeverity = 0.7,
    effectsInStage1 = true,
    knowledge = "pneumonia",
    name = "UI_EHR_Disease_pneumonia",
    lines = {
        stage = {
            [1] = "UI_EHR_Weather_PneumoniaStage1",
            [2] = "UI_EHR_Weather_PneumoniaStage2",
            [3] = "UI_EHR_Weather_PneumoniaStage3",
            [4] = "UI_EHR_Weather_PneumoniaStage4",
        },
        random = {
            [1] = { "UI_EHR_Weather_HardToCatchMyBreath", "UI_EHR_Weather_MyChestHurts" },
            [2] = { "UI_EHR_Weather_CoughsCantShakeThis", "UI_EHR_Weather_BreathingIsGettingHarder",
                "UI_EHR_Weather_Wheezes", "UI_EHR_Weather_INeedMedicine" },
            [3] = { "UI_EHR_Weather_CoughingFit", "UI_EHR_Weather_GaspsForAir", "EHR_Dialogue_HeatStroke_S4_Novice_1",
                "UI_EHR_Weather_ViolentCoughing", "UI_EHR_Weather_GoingToDieWithoutAntibiotics" },
            [4] = { "UI_EHR_Weather_GaspsForAir", "UI_EHR_Weather_ViolentCoughing",
                "UI_EHR_Weather_GoingToDieWithoutAntibiotics" },
        },
        every = 168,
    },
}

local function cough(severe)
    return function(p)
        Episodes.cough(p, severe)
    end
end

function Pneumonia.effects(p, c, dt, curing)
    local row = D[c.stage]
    local t = p.treatment
    p.stats:raiseF("SICKNESS", "pneumonia", row.sickness, 0.01 * dt)
    if p.facts.asleep then
        c.data.coughIn = nil        -- v0.9: the cough clock restarts on waking
    else
        Episodes.every(p, c, "coughIn", row.coughH, t:relief("pneumonia", "coughing"), dt, cough(row.severe))
    end
    local pain = math.min(D.CHEST_PAIN_MAX, row.chestPain * (1 - t:relief("pneumonia", "pain")))
    p.body:pain("Torso_Upper", "pneumonia", pain)
    if row.endurance then
        local cap = row.endurance + (1 - row.endurance) * t:relief("pneumonia", "breathingDifficulty")
        p.stats:ceilingF("ENDURANCE", "pneumonia", cap)
    end
    p.stats:raiseF("FATIGUE", "pneumonia", row.fatigue, row.fatigueStep * K * dt)
    local target, step = Symptoms.fever(row.fever, row.feverStep * K * dt * c.severity, t:relief("pneumonia", "fever"))
    Symptoms.applyFever(p, "pneumonia", target, step)
    if row.drain and not curing then
        -- v0.9 ratchet: natural healing can't outpace the drain.
        p.body:damage("pneumonia", row.drain / 60 * dt, row.floor)
        p.body:healFactorAll(Symptoms.ALL_PARTS, "pneumonia", 0)
    end
end

function Pneumonia.onEnd(p, c, reason)
    -- Chest pain and the drain stop on their own once nothing asks for them.
    if reason == "recovered" then
        Speech.stage(p, "UI_EHR_Text_BreathingEasierNow")
    end
end

return Pneumonia
