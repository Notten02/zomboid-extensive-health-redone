-- Corpse exposure illness: from breathing corpse air (Diseases/Corpse/Exposure). Stage 1 is the incubation; stage 2
-- nausea and weakness; stage 3 cough, headache, dizziness, slower walking and collapse risk; stage 4 recovery. It never
-- kills. W15: once the incubation is over, fresh air (the corpse meter back at 0) makes the rest pass twice as fast.
-- Recovery or a cure gives 2 h of immunity (the meter stays at 0).
-- Effects from v0.9 EHR_Disease.lua:3452-3539 (docs/porting/phase4/corpse-scabies-concussion.md, section 1.11).
--
-- Treatment (Phase 5): cure - Respiratory Support Kit, Corticosteroid Injection. Relief - Anti-Nausea ("nausea"),
-- Bronchodilator ("breathingDifficulty"); also read: "dizziness", "weakness".

local Speech = require "ExtensiveHealthRedone/Core/Speech"
local Episodes = require "ExtensiveHealthRedone/Diseases/Corpse/Episodes"
local Symptoms = require "ExtensiveHealthRedone/Conditions/Symptoms"

local ID = "corpse_sickness"

-- Per v0.9 disease tick unless noted. head = headache pain on the head (ours: v0.9 nudged the general PAIN stat,
-- which B42 derives from body parts).
local ROWS = {
    [2] = { sickness = 0.36, discomfort = 0.32, drain = 0.006, floor = 0.58, mult = 0.45, dizzy = 0.007,
            cough = 0.0025, eyes = 0.006, head = 10 },
    [3] = { sickness = 0.58, discomfort = 0.55, drain = 0.011, floor = 0.42, mult = 1.00, dizzy = 0.018,
            cough = 0.007, eyes = 0.008, head = 20, collapse = 0.004, speed = 0.85, severe = true },
    [4] = { sickness = 0.20, discomfort = 0.18, drain = 0.002, floor = 0.78, mult = 0.25, dizzy = 0.0012,
            cough = 0.0005, head = 4 },
}

local EYE_LINES = { "UI_EHR_Corpse_EyesBurning", "UI_EHR_Corpse_EyesSting", "UI_EHR_Corpse_NeedFreshAir" }

local def = {
    enabledOption = "CorpseSicknessEnabled", speedOption = "DiseaseSpeed",
    incubation = { 6, 18 }, duration = { 24, 72 }, baseSeverity = 0.6,
    blockAfterCureHours = 2,        -- v0.9 GrantImmunity: 2 h without corpse exposure after it ends
    effectsInStage1 = true,         -- for the stage-1 lines; stage 1 has no symptoms
    knowledge = "corpse_sickness",
    name = "UI_EHR_Disease_corpse_sickness",
    lines = {
        stage = {
            [1] = "UI_EHR_Text_ThatSmellIsGettingToMe", [2] = "UI_EHR_Text_IFeelNauseousAndWeak",
            [3] = "UI_EHR_Text_CoughsINeedFreshAirNow", [4] = "UI_EHR_Text_IThinkImFinallyRecovering",
        },
        random = {
            [1] = { "UI_EHR_Text_UghTheStench", "UI_EHR_Text_SomethingsRottingNearby_2" },
            [2] = { "UI_EHR_Text_Gagging", "UI_EHR_Text_MyStomachIsTurning", "UI_EHR_Text_IFeelSick" },
            [3] = { "UI_EHR_Text_Coughs", "UI_EHR_Text_HeadIsPounding", "UI_EHR_Text_INeedToGetAwayFromTheseBodies" },
            [4] = { "UI_EHR_Text_BreathingEasierNow", "UI_EHR_Text_NeverStayingNearCorpsesAgain" },
        },
        every = 168,                -- v0.9: 1 in 7 every 1800 frames (about 24 game minutes)
    },
}

-- W15: fresh air after the incubation doubles the pace of the rest of the illness.
function def.rate(p, c)
    if c.stage > 1 and p.state.exposure.corpse <= 0 then
        return 2
    end
    return 1
end

function def.effects(p, c, dt, curing)
    Episodes.tick(c, dt)
    local row = ROWS[c.stage]
    if not row then
        return
    end
    local t = p.treatment
    local sev = c.severity
    local k = Symptoms.TICK * dt
    local nausea = math.max(0.12, 1 - t:relief(ID, "nausea"))
    local dizziness = math.max(0.12, 1 - t:relief(ID, "dizziness"))
    local breathing = math.max(0.15, 1 - t:relief(ID, "breathingDifficulty"))
    local weakness = math.max(0.18, 1 - t:relief(ID, "weakness"))

    p.stats:raiseF("SICKNESS", ID, row.sickness * nausea, 0.0035 * sev * k)
    p.stats:raiseF("DISCOMFORT", ID, row.discomfort * breathing, 0.003 * sev * k)
    p.stats:lowerF("ENDURANCE", ID, row.floor, row.drain * sev * weakness * k)
    p.stats:addF("PANIC", ID, 0.0008 * sev * row.mult * dizziness * k)
    p.stats:addF("THIRST", ID, 0.00018 * sev * row.mult * k)
    p.body:pain("Head", ID, row.head * breathing * math.max(0.65, sev))
    if row.speed then
        p.fx:speed(ID, row.speed)
    end
    if Episodes.try(p, c, "dizzy", row.dizzy * sev * dizziness, 0.18, dt) then
        Episodes.dizzy(p, c)
    end
    Episodes.blur(p, c, ID, dt)
    if Episodes.try(p, c, "cough", row.cough * sev * breathing, 0.16, dt) then
        Episodes.cough(p, row.severe)
    end
    if row.eyes and Episodes.try(p, c, "eyes", row.eyes * sev * breathing, 0.22, dt) then
        Speech.stage(p, Speech.pick(p, EYE_LINES))
    end
    if row.collapse and Episodes.try(p, c, "collapse", row.collapse * sev * weakness, 0.5, dt) then
        Episodes.collapse(p, ID)
    end
end

return def
