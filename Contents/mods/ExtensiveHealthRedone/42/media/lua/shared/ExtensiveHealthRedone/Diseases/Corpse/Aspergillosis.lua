-- Cadaveric aspergillosis: a fungal lung infection from spores of decomposing corpses in damp or cold air
-- (Diseases/Corpse/Exposure). Stage 1 is the incubation; stage 2 cough, feverish feeling and stamina loss; stage 3
-- severe breathing trouble, a 39.4 C fever, no sprinting, slower walking, and untreated a health drain with no floor
-- (lethal); stage 4 recovery. A curative course softens everything and stops the drain.
--
-- Treatment: cure - Antifungal Tablets, IV Amphotericin B. Relief - cough syrups and Cough Suppressant
-- ("coughing"), Bronchodilator ("breathingDifficulty"), Antipyretic ("fever"); also read: "weakness".

local Speech = require "ExtensiveHealthRedone/Core/Speech"
local Episodes = require "ExtensiveHealthRedone/Diseases/Corpse/Episodes"
local Symptoms = require "ExtensiveHealthRedone/Conditions/Symptoms"

local ID = "cadaveric_aspergillosis"

local ROWS = {
    [2] = { sickness = 0.34, discomfort = 0.32, fatigue = 0.20, fatigueStep = 0.0010, drain = 0.0035, floor = 0.74,
            fever = 38.2, feverStep = 0.035, mult = 0.45, cough = 0.006, breath = 0.003, hot = 0.0015 },
    [3] = { sickness = 0.58, discomfort = 0.58, fatigue = 0.62, fatigueStep = 0.0025, drain = 0.012, floor = 0.42,
            fever = 39.4, feverStep = 0.055, mult = 1.00, cough = 0.018, breath = 0.006, hot = 0.004,
            severe = true, thirst = true, speed = 0.75, noSprint = true, lethal = true },
    [4] = { sickness = 0.20, discomfort = 0.20, fatigue = 0.22, fatigueStep = 0.0025, drain = 0.003, floor = 0.82,
            fever = 37.6, feverStep = 0.030, mult = 0.25, cough = 0.0018 },
}

-- Stage-3 drain: 0.55 + 1.30 x severity HP every 0.45 game hours, no floor.
local DRAIN = { base = 0.55, perSeverity = 1.30, everyMinutes = 27 }

local BREATH_LINES = { "UI_EHR_Asperg_LungsTight", "UI_EHR_Asperg_HurtsToBreathe", "UI_EHR_Asperg_NoFullBreath" }
local FEVER_LINES = { "UI_EHR_Text_ImBurningUp", "UI_EHR_Asperg_ChestOnFire", "UI_EHR_Asperg_FeverWorse" }

local def = {
    enabledOption = "CadavericAspergillosisEnabled", speedOption = "DiseaseSpeed",
    incubation = { 24, 72 }, duration = { 168, 336 }, baseSeverity = 0.75,
    effectsInStage1 = true,         -- for the stage-1 lines; stage 1 has no symptoms
    knowledge = "cadaveric_aspergillosis",
    name = "UI_EHR_Disease_cadaveric_aspergillosis",
    lines = {
        stage = {
            [1] = "UI_EHR_Text_MyThroatFeelsDustyAfterBreathingThatAir",
            [2] = "UI_EHR_Text_CoughsSomethingIsWrongWithMyLungs",
            [3] = "UI_EHR_Text_WheezesINeedAntifungalsNow", [4] = "UI_EHR_Text_TheCoughIsFinallyEasing",
        },
        random = {
            [1] = { "UI_EHR_Text_MyChestFeelsScratchy", "UI_EHR_Text_ThatDampCorpseAirGotIntoMyLungs" },
            [2] = { "UI_EHR_Text_Coughs", "UI_EHR_Text_MyChestFeelsTight", "UI_EHR_Text_IFeelFeverish" },
            [3] = { "UI_EHR_Text_WheezingCough", "UI_EHR_Text_ICanBarelyBreathe",
                    "UI_EHR_Text_ThisFeelsLikeALungInfection" },
            [4] = { "UI_EHR_Text_BreathingALittleEasier", "UI_EHR_Text_TheFeverIsBreaking" },
        },
        every = 168,
    },
}

function def.effects(p, c, dt, curing)
    Episodes.tick(c, dt)
    local row = ROWS[c.stage]
    if not row then
        return
    end
    local t = p.treatment
    local sev = c.severity
    local k = Symptoms.TICK * dt
    local cough = math.max(0.12, 1 - t:relief(ID, "coughing"))
    local breathing = math.max(0.15, 1 - t:relief(ID, "breathingDifficulty"))
    local weakness = math.max(0.18, 1 - t:relief(ID, "weakness"))
    local treat = curing and { sickness = 0.65, discomfort = 0.70, fatigue = 0.70, drain = 0.65 }
        or { sickness = 1, discomfort = 1, fatigue = 1, drain = 1 }
    local floor = curing and math.min(0.90, row.floor + 0.12) or row.floor

    p.stats:raiseF("SICKNESS", ID, row.sickness * sev * treat.sickness, 0.0035 * sev * k)
    p.stats:raiseF("DISCOMFORT", ID, row.discomfort * breathing * treat.discomfort, 0.003 * sev * k)
    p.stats:raiseF("FATIGUE", ID, row.fatigue * weakness * treat.fatigue, row.fatigueStep * sev * k)
    p.stats:lowerF("ENDURANCE", ID, floor, row.drain * sev * weakness * treat.drain * k)
    p.stats:addF("PANIC", ID, 0.0008 * sev * row.mult * breathing * k)
    if row.thirst and not curing then
        p.stats:raiseF("THIRST", ID, 0.5, 0.000018 * sev * k)
    end

    local target, step = row.fever, row.feverStep * sev * k
    if curing then
        target, step = c.stage == 3 and 38.2 or 37.6, step * 1.8
    end
    target, step = Symptoms.fever(target, step, t:relief(ID, "fever"))
    Symptoms.applyFever(p, ID, target, step)

    if row.speed then
        p.fx:speed(ID, row.speed)
    end
    if row.noSprint then
        p.fx:noSprint(ID)
    end
    if row.lethal and not curing then
        Episodes.healthCap(p, c, ID, nil, (DRAIN.base + DRAIN.perSeverity * sev) / DRAIN.everyMinutes, dt)
    else
        c.data.cap = nil
    end
    if Episodes.try(p, c, "cough", row.cough * sev * cough, 0.14, dt) then
        Episodes.cough(p, row.severe)
    end
    if Episodes.try(p, c, "breath", (row.breath or 0) * sev * breathing, 0.22, dt) then
        Speech.stage(p, Speech.pick(p, BREATH_LINES))
    end
    if Episodes.try(p, c, "hot", (row.hot or 0) * sev, 0.28, dt) then
        Speech.stage(p, Speech.pick(p, FEVER_LINES))
    end
end

return def
