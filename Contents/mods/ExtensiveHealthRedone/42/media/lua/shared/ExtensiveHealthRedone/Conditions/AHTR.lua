-- AHTR, the acute hemolytic transfusion reaction: from incompatible blood (Blood/Transfusion). Effects start in stage
-- 1. Untreated, stage 2 drains health down to 50 and stages 3 and 4 drain it without a floor. A curative course (IV
-- fluids, furosemide; Phase 5) stops the damage and softens the symptoms.
-- Effects from v0.9 EHR_Disease.lua (docs/porting/phase3/transfusion-ahtr-supplies.md, part 10). Back pain goes on
-- the lower torso (v0.9 used stiffness and a general pain stat, which B42 derives from the body parts).

local Symptoms = require "ExtensiveHealthRedone/Conditions/Symptoms"
local Speech = require "ExtensiveHealthRedone/Core/Speech"

local AHTR = {}

-- health = { base, perSeverity, everyHours, floor }
local ROWS = {
    [1] = { endurance = 0.30, drain = 0.006, sickness = 0.10, pain = 18 },
    [2] = { endurance = 0.40, drain = 0.009, sickness = 0.46, pain = 28, fever = 40.0, feverStep = 0.060,
            health = { 0.55, 0.95, 0.42, 50 } },
    [3] = { endurance = 0.40, drain = 0.013, sickness = 0.62, pain = 38, fever = 40.1, feverStep = 0.065,
            health = { 1.15, 1.95, 0.30, 0 } },
    [4] = { endurance = 0.44, drain = 0.012, sickness = 0.52, pain = 34, fever = 39.7, feverStep = 0.055,
            health = { 0.95, 1.65, 0.34, 0 } },
}

AHTR.LINES = {
    [1] = "UI_EHR_Text_SomethingIsWrongWithThatTransfusion",
    [2] = "UI_EHR_Text_MyBackHurtsIFeelSick",
    [3] = "UI_EHR_Text_ImBurningUpMyBloodFeelsWrong",
    [4] = "UI_EHR_Text_IHaveToKeepFightingThisReaction",
}

function AHTR.onStage(p, c, stage)
    Speech.stage(p, AHTR.LINES[stage])
end

function AHTR.effects(p, c, dt, curing)
    local row = ROWS[c.stage]
    local sev = c.severity
    local t = p.treatment
    local k = Symptoms.TICK * dt
    local weak = math.max(0.20, 1 - t:relief("ahtr", "weakness"))
    local nausea = math.max(0.18, 1 - math.max(t:relief("ahtr", "nausea"), t:relief("ahtr", "sickness")))
    local pain = math.max(0.18, 1 - math.max(t:relief("ahtr", "pain"), 0.65 * t:relief("ahtr", "inflammation")))
    if curing then
        weak, nausea, pain = weak * 0.35, nausea * 0.45, pain * 0.40
    end

    p.stats:lowerF("ENDURANCE", "ahtr", row.endurance, row.drain * sev * weak * k)
    p.stats:raiseF("SICKNESS", "ahtr", math.min(0.65, row.sickness * nausea), 0.0045 * sev * k)
    p.body:pain("Torso_Lower", "ahtr", row.pain * pain)
    if row.fever then
        local target, step = row.fever, row.feverStep * sev * k
        if curing then
            target, step = math.min(37.7, target - 2.8), step * 1.45
        end
        target, step = Symptoms.fever(target, step, t:relief("ahtr", "fever"))
        Symptoms.applyFever(p, "ahtr", target, step)
    end
    if row.health and not curing then
        local h = row.health
        p.body:damage("ahtr", (h[1] + h[2] * sev) / h[3] / 60 * dt, h[4])
        p.body:healFactorAll(Symptoms.ALL_PARTS, "ahtr", 0)
    end
end

return AHTR
