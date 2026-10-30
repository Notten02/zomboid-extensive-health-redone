-- Toxin poisoning: from eating anything with a poison value (poisonous mushrooms, berries, other toxic food). Always
-- contracted, no roll. Bitter taste (incubation), nausea and dizziness, then dangerous vomiting, weakness, vision blur
-- and (mushrooms) lethal health loss at stage 3, then recovery. Incubation 1-4 h, then 1-4 days, scaled by
-- DiseaseSpeed whatever the source; the severity depends on the source.
--
-- Treatment: cure Activated Charcoal / Homemade (about 12 h), Chelation Kit.
-- Relief: Anti-Nausea, Electrolyte Powder.

local Data = require "ExtensiveHealthRedone/Diseases/Food/Data"
local Common = require "ExtensiveHealthRedone/Diseases/Food/Common"
local Speech = require "ExtensiveHealthRedone/Core/Speech"

local ID = "toxin_poisoning"

local TOXIN_MULT = { mushroom = 1.20, berry = 0.75, toxin = 0.95 }

-- Per engine check (Data TICK).
local ROWS = {
    [2] = { drain = 0.007, floor = 0.70, curedFloor = 0.86, thirst = 0.0009, fatigue = 0.22, fatigueStep = 0.0025,
            vomit = 0.0025, dizzy = 0.002 },
    [3] = { drain = 0.017, floor = 0.50, mushroomFloor = 0.35, curedFloor = 0.72, mushroomCuredFloor = 0.62,
            thirst = 0.0018, hunger = 0.0006, fatigue = 0.38, mushroomFatigue = 0.55, fatigueStep = 0.004,
            pain = 12, mushroomPain = 22, vomit = 0.007, dizzy = 0.005 },
    [4] = { drain = 0.003, floor = 0.82, curedFloor = 0.90, thirst = 0.00035, vomit = 0.0007, dizzy = 0.0005 },
}
local VOMIT_COOLDOWN = 9.6      -- game minutes
local DIZZY_COOLDOWN = 12       -- game minutes
-- Vision: a dizzy spell blurs for 5-10 minutes; at stage 3 recurring episodes of 10-20 minutes, 25-45 minutes apart,
-- the first at once.
local BLUR_TOXIN = 1.0
local BLUR_DIZZY = 0.6

local def = {
    enabledOption = "ToxinPoisoningEnabled", speedOption = "DiseaseSpeed",
    incubation = { 1, 4 }, duration = { 24, 96 }, baseSeverity = 0.65,
    effectsInStage1 = true,     -- for the bitter-taste lines; stage 1 has no effects
    name = "UI_EHR_Disease_toxin_poisoning", knowledge = ID,
    lines = {
        stage = {
            [1] = "UI_EHR_Text_ThatTastedWrong",
            [2] = "UI_EHR_Text_MyStomachIsTurningIThinkThatWasPoisonous",
            [3] = "UI_EHR_Text_RetchesSomethingIsBadlyWrong",
            [4] = "UI_EHR_Text_ThePoisonIsFinallyPassing",
        },
        random = {
            [1] = { "UI_EHR_Text_MyMouthFeelsBitter", "UI_EHR_Text_ThatWasAMistake" },
            [2] = { "UI_EHR_Text_IFeelPoisoned", "UI_EHR_Text_MyStomachIsBurning", "UI_EHR_Text_ImGettingDizzy" },
            [3] = { "UI_EHR_Text_Vomits", "UI_EHR_Text_INeedHelp", "UI_EHR_Text_MyBodyFeelsLikeItsShuttingDown" },
            [4] = { "UI_EHR_Text_StillShaky", "UI_EHR_Text_IThinkImRecovering" },
        },
        every = Data.LINE_EVERY,
    },
    onEnd = Common.onEnd,
}

-- Severity by source and poison power.
function def.poisonSeverity(toxinType, power)
    local sev
    if toxinType == "mushroom" then
        sev = 0.72 + math.min(0.28, 0.08 * power)
    elseif toxinType == "berry" then
        sev = 0.38 + math.min(0.22, 0.06 * power)
    else
        sev = 0.55 + math.min(0.30, 0.08 * power)
    end
    return math.max(0.25, math.min(1, sev))
end

-- Recurring stage-3 blur episodes and the short dizzy spells, as minutes left in c.data.
local function vision(p, c, dt)
    if c.stage == 3 then
        if c.data.blurLeft and c.data.blurLeft > 0 then
            c.data.blurLeft = c.data.blurLeft - dt
            if c.data.blurLeft <= 0 then
                c.data.blurLeft = nil
                c.data.blurNext = p.rng.int(25, 45)
            end
        else
            c.data.blurNext = (c.data.blurNext or 0) - dt
            if c.data.blurNext <= 0 then
                c.data.blurNext = nil
                c.data.blurLeft = p.rng.int(10, 20)
                Speech.stage(p, Speech.pick(p, Data.BLUR_LINES))
            end
        end
    else
        c.data.blurLeft, c.data.blurNext = nil, nil
    end
    if c.data.blurLeft then
        p.fx:blur(ID, BLUR_TOXIN)
    end
    if c.data.dizzyLeft then
        c.data.dizzyLeft = c.data.dizzyLeft - dt
        if c.data.dizzyLeft <= 0 then
            c.data.dizzyLeft = nil
        else
            p.fx:blur(ID, BLUR_DIZZY)
        end
    end
end

function def.effects(p, c, dt, curing)
    local row = ROWS[c.stage]
    if not row then
        return
    end
    local sev = c.severity
    local mushroom = c.data.toxinType == "mushroom"
    local tm = TOXIN_MULT[c.data.toxinType or "toxin"] or TOXIN_MULT.toxin
    local m = Common.mults(p, ID)
    local k = Data.TICK * dt
    local floor = mushroom and row.mushroomFloor or row.floor
    local painMult = 1
    if curing then
        tm = tm * 0.45
        m.vomit, m.hydration, m.weakness = math.max(0.03, m.vomit * 0.35), math.max(0.06, m.hydration * 0.45),
            math.max(0.08, m.weakness * 0.35)
        painMult = 0.35
        floor = mushroom and row.mushroomCuredFloor or row.curedFloor
        p.stats:lowerF("SICKNESS", ID, 0, 0.006 * sev * k)
    end

    Common.drainEndurance(p, ID, row.drain * sev * tm * m.weakness, floor, dt)
    p.stats:addF("THIRST", ID, row.thirst * sev * tm * m.hydration * k)
    if row.hunger then
        p.stats:addF("HUNGER", ID, row.hunger * sev * m.vomit * k)
    end
    if row.fatigue then
        local target = mushroom and row.mushroomFatigue or row.fatigue
        p.stats:raiseF("FATIGUE", ID, target * sev * tm, row.fatigueStep * sev * k)
    end
    if row.pain then
        p.body:pain("Torso_Lower", ID, (mushroom and row.mushroomPain or row.pain) * sev * painMult)
    end
    if Common.symptom(p, c, "vomitIn", row.vomit * sev * tm * m.vomit, VOMIT_COOLDOWN, dt) then
        Common.vomit(p, ID, 0.10, 0.15)
    end
    if Common.symptom(p, c, "dizzyIn", row.dizzy * sev * tm * m.weakness, DIZZY_COOLDOWN, dt) then
        Speech.stage(p, Speech.pick(p, Data.DIZZY_LINES))
        p.stats:addF("PANIC", ID, 0.2)
        c.data.dizzyLeft = p.rng.int(5, 10)
    end
    vision(p, c, dt)
    if not curing then
        Common.nausea(p, ID, c, dt, m)
    end
    -- Mushrooms do 0.45 + 1.10 x severity every 0.35 h at stage 3 with no regeneration; other toxins don't.
    if c.stage == 3 and mushroom and not curing then
        Common.drain(p, ID, c, dt, 0.45 + 1.10 * sev, 21, 15, 0.012 * sev)
    end
end

return def
