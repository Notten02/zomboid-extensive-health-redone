-- The Knox simulation: immunity enforcement, item side effects and timers, and the knox_infection display condition.
--
-- Immunity (permanent or immunobooster): every step a Knox-infected immune player is cured again: the infected flags
-- and timers through the body writer, ZOMBIE_INFECTION and ZOMBIE_FEVER through the stat writer. Bites still wound.
-- The bite's Knox roll happens in Java with no Lua event to stop it, so it is undone afterwards.
--
-- knox_infection mirrors vanilla's infection for the monitor and the dialogue: it is never contracted by a roll of
-- ours, can't be switched off (master = false), is named only with the Kentucky Herald (Conditions/Knowledge), and
-- its stage follows infection progress (bounds 0.2/0.5/0.8); c.data.progress is kept for the UI. Vanilla does every
-- effect of the infection itself.

local Data = require "ExtensiveHealthRedone/Diseases/Knox/Data"
local Knox = require "ExtensiveHealthRedone/Diseases/Knox/Knox"
local Items = require "ExtensiveHealthRedone/Diseases/Knox/Items"
local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Symptoms = require "ExtensiveHealthRedone/Conditions/Symptoms"
local Speech = require "ExtensiveHealthRedone/Core/Speech"
local Chance = require "ExtensiveHealthRedone/Core/Chance"

local Infection = {}

-- The display condition --------------------------------------------------------------------------------------------

local function progressStep(progress)
    return math.floor(progress / Data.PROGRESS_STEP + 0.5) * Data.PROGRESS_STEP
end

Infection.condition = {
    master = false,
    driven = true,
    xp = false,             -- it mirrors vanilla's infection; ending it is no medical achievement
    knowledge = Knox.ID,
    name = "UI_EHR_Disease_Knox_Infection",
    lines = {
        stage = {
            [1] = "UI_EHR_Knox_Stage1", [2] = "UI_EHR_Knox_Stage2",
            [3] = "UI_EHR_Knox_Stage3", [4] = "UI_EHR_Knox_Stage4",
        },
        random = {
            [1] = { "UI_EHR_Knox_Random1a", "UI_EHR_Knox_Random1b", "UI_EHR_Knox_Random1c" },
            [2] = { "UI_EHR_Knox_Random2a", "UI_EHR_Knox_Random2b", "UI_EHR_Knox_Random2c", "UI_EHR_Knox_Random2d" },
            [3] = { "UI_EHR_Knox_Random3a", "UI_EHR_Knox_Random3b", "UI_EHR_Knox_Random3c", "UI_EHR_Knox_Random3d" },
            [4] = { "UI_EHR_Knox_Random4a", "UI_EHR_Knox_Random4b", "UI_EHR_Knox_Random4c" },
        },
        every = 270,        -- a random line every 3-6 game hours
    },
}

-- Follows vanilla: the stage from progress, or recovered once vanilla (or immunity) no longer has an infection.
function Infection.condition.drive(p, c)
    local k = p.facts.knox
    if not k then
        return nil
    end
    if not Knox.infected(k) or Knox.immune(p.state) then
        return "recovered"
    end
    local progress = progressStep(Knox.progress(k))
    if c.data.progress ~= progress then
        c.data.progress = progress
        p.dirty("conditions")
    end
    return Knox.stageFor(progress)
end

-- Timers and side effects --------------------------------------------------------------------------------------------

-- Counts a timer field down. Returns true when it just ran out. Marks knox dirty when the shown hour changes.
local function countDown(p, t, field, dt)
    local left = t[field]
    if not left or left <= 0 then
        return false
    end
    local after = math.max(0, left - dt)
    t[field] = after
    if math.ceil(after / 60) ~= math.ceil(left / 60) then
        p.dirty("knox")
    end
    return after <= 0
end

local function boosterEffects(p, knox, dt)
    p.stats:floorF("FOOD_SICKNESS", "immunobooster", Data.BOOSTER_NAUSEA)
    p.stats:lowerF("ENDURANCE", "immunobooster", Data.BOOSTER_ENDURANCE_FLOOR, Data.BOOSTER_ENDURANCE_DRAIN * dt)
    local fx = knox.effects
    fx.tremorIn = (fx.tremorIn or Data.TREMOR_EVERY[1]) - dt
    if fx.tremorIn <= 0 then
        fx.tremorIn = p.rng.int(Data.TREMOR_EVERY[1], Data.TREMOR_EVERY[2])
        p.stats:addF("ENDURANCE", "immunoboosterTremor", -Data.TREMOR_ENDURANCE)
        p.client("knoxTremor", {})
        Speech.stage(p, "UI_EHR_Knox_Tremor")
    end
end

local function timers(p, knox, dt)
    if countDown(p, knox, "boosterLeft", dt) then
        knox.effects.tremorIn = nil
        Speech.stage(p, "UI_EHR_Knox_BoosterWearingOff")
    end
    countDown(p, knox, "boosterCooldown", dt)
    for _, effect in ipairs({ "phalanxNausea", "phalanxFever", "phalanxDebuff" }) do
        countDown(p, knox.effects, effect, dt)
    end
end

local function sideEffects(p, knox, dt)
    if (knox.boosterLeft or 0) > 0 then
        boosterEffects(p, knox, dt)
    end
    local fx = knox.effects
    if (fx.phalanxNausea or 0) > 0 then
        p.stats:raiseF("FOOD_SICKNESS", "phalanx", Data.PHALANX_NAUSEA, Data.PHALANX_NAUSEA_STEP * dt)
    end
    if (fx.phalanxFever or 0) > 0 then
        Symptoms.applyFever(p, "phalanx", Data.PHALANX_FEVER, Data.PHALANX_FEVER_STEP * dt)
    end
    if knox.survivor and Chance.roll(p.rng, Chance.over(Data.MIGRAINE_CHANCE, Data.MIGRAINE_ROLLS_PER_MINUTE, dt)) then
        p.body:addPain("Head", "geneTherapyMigraine", Data.MIGRAINE_PAIN)
        Speech.maybePick(p, { "UI_EHR_Knox_Migraine" }, Data.MIGRAINE_LINE_ONE_IN, 1)
    end
end

-- The Patient Zero trait (chosen at character creation) makes the character permanently immune. While
-- PatientZeroTraitDisabled is on, a trait that got past the creation screen anyway (a modified client, an admin) gives
-- nothing; immunity a character already has is never taken away.
local function traitImmunity(p, knox, k)
    if k.hasTrait and not knox.geneTherapyImmune and p.sandbox("PatientZeroTraitDisabled", false) ~= true then
        knox.geneTherapyImmune = true
        knox.immunityTraitGranted = true
        knox.patientZeroTraitSource = true
        p.dirty("knox")
    end
end

-- The system ------------------------------------------------------------------------------------------------------------

function Infection.update(p, dt, defs)
    local knox = p.state.knox
    knox.effects = knox.effects or {}
    timers(p, knox, dt)
    local k = p.facts.knox
    if k then
        traitImmunity(p, knox, k)
        if Knox.immune(p.state) then
            if Knox.infected(k) or (k.level or 0) > 0 or (k.fever or 0) > 0 then
                Items.clearInfection(p, "knoxImmunity")
            end
        elseif Knox.infected(k) and not p.state.conditions.active[Knox.ID] then
            local progress = Knox.progress(k)
            local c = Engine.contract(p, defs, Knox.ID, { stage = Knox.stageFor(progress), source = "vanilla" })
            if c then
                c.data.progress = progressStep(progress)
                Engine.enterStage(p, defs, Knox.ID, c, c.stage)
            end
        end
    end
    sideEffects(p, knox, dt)
end

Infection.system = { name = "knox", order = 380, update = Infection.update }

return Infection
