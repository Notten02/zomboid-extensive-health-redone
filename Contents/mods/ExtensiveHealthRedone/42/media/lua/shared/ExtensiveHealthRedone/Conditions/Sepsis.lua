-- Sepsis: the infection reaches the blood. Started by an untreated stage-3 wound infection running out, or by
-- untreated stage-4 cellulitis. Stage 1 (the incubation) already shows mild symptoms; untreated, stage 4 never ends
-- and drains health to death. A curative course holds it and stops the damage; completing the course cures it.

local Symptoms = require "ExtensiveHealthRedone/Conditions/Symptoms"
local Speech = require "ExtensiveHealthRedone/Core/Speech"
local Chance = require "ExtensiveHealthRedone/Core/Chance"

local Sepsis = {}

-- health: damage per game hour, never below floor. confusion: chance per check (every 4 game minutes).
local ROWS = {
    [1] = { fever = 38.0, feverStep = 0.030, fatigue = 0.30, fatigueStep = 0.010, health = 0.25, floor = 85, confusion = 0 },
    [2] = { fever = 38.6, feverStep = 0.040, fatigue = 0.50, fatigueStep = 0.015, health = 1.0, floor = 65, confusion = 0.10 },
    [3] = { fever = 39.4, feverStep = 0.060, fatigue = 0.70, fatigueStep = 0.020, health = 4.0, floor = 30, confusion = 0.30 },
    [4] = { fever = 40.0, feverStep = 0.075, fatigue = 0.80, fatigueStep = 0.025, health = 10.0, floor = 0, confusion = 0.50 },
}

Sepsis.LINES = {
    [1] = "UI_EHR_Text_SomethingsVeryWrongTheInfectionIsInMyBlood",
    [2] = "UI_EHR_Text_ImShakingCantThinkStraight",
    [3] = "UI_EHR_Text_ShiveringUncontrollablyINeedIVAntibioticsNOW",
    [4] = "UI_EHR_Text_ImDyingThisIsIt",
}

local CONFUSED = { "UI_EHR_Text_WhereAmI", "UI_EHR_Text_WhatsHappening", "UI_EHR_Text_ICantThink" }

function Sepsis.onStage(p, c, stage)
    Speech.stage(p, Sepsis.LINES[stage])
end

function Sepsis.effects(p, c, dt, curing)
    local row = ROWS[c.stage]
    local k = Symptoms.SLOW_TICK * dt
    local target, step = Symptoms.fever(row.fever, row.feverStep * k, p.treatment:relief("sepsis", "fever"))
    Symptoms.applyFever(p, "sepsis", target, step)
    p.stats:raiseF("FATIGUE", "sepsis", row.fatigue, row.fatigueStep * k)
    if not curing then
        p.body:damage("sepsis", row.health / 60 * dt, row.floor)
        p.body:healFactorAll(Symptoms.ALL_PARTS, "sepsis", 0)
    end
    if Chance.roll(p.rng, Chance.over(row.confusion, Symptoms.SLOW_TICK, dt)) then
        p.stats:addF("STRESS", "sepsis", 0.2)
        if Chance.roll(p.rng, 0.3) then
            Speech.stage(p, Speech.pick(p, CONFUSED))
        end
    end
end

return Sepsis
