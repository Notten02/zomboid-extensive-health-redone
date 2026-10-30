-- Common cold: caught from cold-and-wet exposure (Diseases/Weather/Exposure). Sneezing, the vanilla cold moodle, a
-- fatigue cap and fever; stage 4 is a real recovery stage, and entering it untreated rolls 35% (immunity-modified)
-- for pneumonia, which replaces the cold.
--
-- Treatment (through p.treatment): cure courses Cold & Flu Tablets (28 h, 8 doses), Antiviral Capsules
-- (48 h), Herbal Tea (8 doses); relief: cough medicine ("coughing", also slows sneezing), Antipyretic ("fever"),
-- "fatigue". A curing course holds the stage and skips the pneumonia roll.

local Data = require "ExtensiveHealthRedone/Diseases/Weather/Data"
local Episodes = require "ExtensiveHealthRedone/Diseases/Weather/Episodes"
local Symptoms = require "ExtensiveHealthRedone/Conditions/Symptoms"
local Speech = require "ExtensiveHealthRedone/Core/Speech"

local D = Data.commonCold
local K = Data.PER_MINUTE

local CommonCold = {
    enabledOption = "CommonColdEnabled", speedOption = "DiseaseSpeed",
    incubation = { 12, 24 }, duration = { 48, 96 }, baseSeverity = 0.3,
    effectsInStage1 = true,
    knowledge = "common_cold",
    name = "UI_EHR_Disease_common_cold",
    complications = {
        { stage = 4, id = "pneumonia", chance = D.PNEUMONIA_CHANCE, risk = true, untreated = true, replace = true },
    },
    lines = {
        stage = {
            [1] = "UI_EHR_Text_SniffIFeelABitRunDown",
            [2] = "UI_EHR_Text_GreatIThinkImCatchingACold",
            [3] = "UI_EHR_Text_ACHOOThisColdIsKickingMyAss",
            [4] = "UI_EHR_Text_SniffIThinkTheWorstIsOver",
        },
        random = {
            [1] = { "UI_EHR_Text_IFeelABitOff", "UI_EHR_Text_Sniff", "UI_EHR_Text_HopeImNotGettingSick" },
            [2] = { "UI_EHR_Text_Coughs", "UI_EHR_Text_MyThroatsGettingScratchy", "UI_EHR_Text_SniffUgh",
                "UI_EHR_Text_IShouldFindSomeMedicine" },
            [3] = { "UI_EHR_Text_ACHOO", "UI_EHR_Text_CoughsViolently", "UI_EHR_Text_CantStopSneezing",
                "UI_EHR_Text_BlowsNose", "UI_EHR_Text_IFeelTerrible" },
            [4] = { "UI_EHR_Text_StartingToFeelBetter", "UI_EHR_Text_SniffAlmostOverIt",
                "UI_EHR_Text_ShouldBeBackToNormalSoon" },
        },
        every = 168,    -- a 1-in-7 check every 24 game minutes
    },
}

function CommonCold.effects(p, c, dt)
    local row = D[c.stage]
    local t = p.treatment
    p.body:cold("common_cold", row.cold)
    p.stats:raiseF("SICKNESS", "common_cold", row.sickness, 0.01 * dt)
    Episodes.every(p, c, "sneezeIn", row.sneezeH, t:relief("common_cold", "coughing"), dt, Episodes.sneeze)
    if row.fatigue then
        local mult = 1 - t:relief("common_cold", "fatigue")
        p.stats:raiseF("FATIGUE", "common_cold", row.fatigue, row.fatigueStep * K * dt * mult)
    end
    if row.fever then
        local target, step = Symptoms.fever(row.fever, row.feverStep * K * dt * c.severity,
            t:relief("common_cold", "fever"))
        Symptoms.applyFever(p, "common_cold", target, step)
    end
end

-- The one cleanup path. The vanilla cold clears itself once nothing asks for it (Core/BodyAggregator).
function CommonCold.onEnd(p, c, reason)
    if reason == "complication" then
        Speech.stage(p, "UI_EHR_Text_CoughsViolentlyThisIsntJustAColdAnymore")
    elseif reason == "recovered" then
        Speech.stage(p, "UI_EHR_Text_SniffIThinkImFinallyGettingOverThisCold")
    end
end

return CommonCold
