-- Cellulitis: a skin infection from a rough stitch. Stage 4 turns into sepsis unless a curative course is running.

local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Symptoms = require "ExtensiveHealthRedone/Conditions/Symptoms"
local Speech = require "ExtensiveHealthRedone/Core/Speech"

local Cellulitis = {}

local ROWS = {
    [2] = { pain = 16, endurance = 0.82, drain = 0.0025, sickness = 0.18, fatigue = 0.18, fever = 37.8, feverStep = 0.026 },
    [3] = { pain = 32, endurance = 0.68, drain = 0.006, sickness = 0.34, fatigue = 0.34, fever = 38.6, feverStep = 0.042 },
    [4] = { pain = 38, endurance = 0.62, drain = 0.007, sickness = 0.42, fatigue = 0.44, fever = 39.2, feverStep = 0.050 },
}

local LINES = {
    [2] = "UI_EHR_Text_TheRednessIsSpreading",
    [3] = "UI_EHR_Text_HotToTouchTheCellulitisIsGettingSevere",
}

-- Untreated stage 4: hand off to sepsis. Cellulitis ends only when sepsis actually starts; while sepsis is already
-- running or blocked after a cure, it stays and tries again.
local function handOff(p, c, defs)
    if Engine.contract(p, defs, "sepsis", { source = c.source }) then
        Engine.finish(p, defs, "cellulitis", "complication")
        Speech.stage(p, "UI_EHR_Cellulitis_SpreadsToBlood")
        return true
    end
    return false
end

function Cellulitis.onStage(p, c, stage)
    Speech.stage(p, LINES[stage])
end

function Cellulitis.effects(p, c, dt, curing, defs)
    if c.stage == 4 and not curing and handOff(p, c, defs) then
        return
    end
    local row = ROWS[c.stage]
    if not row then
        return
    end
    local sev = c.severity
    local t = p.treatment
    local treat = curing and 0.38 or 1
    local painRelief = math.max(t:relief("cellulitis", "pain"), 0.85 * t:relief("cellulitis", "inflammation"))
    local painMult = math.max(curing and 0.16 or 0.35, treat * (1 - 1.45 * painRelief))
    local weakMult = math.max(curing and 0.20 or 0.38, treat * (1 - 1.2 * t:relief("cellulitis", "weakness")))
    local k = Symptoms.TICK * dt

    if c.source then
        p.body:pain(c.source, "cellulitis", row.pain * painMult * math.max(0.65, sev))
    end
    p.stats:lowerF("ENDURANCE", "cellulitis", row.endurance, row.drain * sev * weakMult * k)
    p.stats:raiseF("SICKNESS", "cellulitis", row.sickness, 0.0028 * sev * k)
    p.stats:raiseF("FATIGUE", "cellulitis", row.fatigue * weakMult, 0.0014 * sev * k)

    local target = row.fever
    local step = row.feverStep * sev * k
    if curing then
        target = math.min(target, c.stage == 3 and 38.1 or 37.6)
        step = step * 1.5
    end
    target, step = Symptoms.fever(target, step, t:relief("cellulitis", "fever"))
    Symptoms.applyFever(p, "cellulitis", target, step)
end

return Cellulitis
