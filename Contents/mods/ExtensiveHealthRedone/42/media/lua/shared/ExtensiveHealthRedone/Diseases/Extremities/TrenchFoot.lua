-- Trench foot: a non-freezing cold injury from feet kept cold and wet for a long time. Per foot, hours of cold, wet
-- feet build up (wetColdH) while the feet are at least damp (socks, else the inside of the shoes, else the body;
-- Diseases/Extremities/Inputs) and the air is at or below TrenchFootMaxTemperature. Soaked feet count faster; foot
-- powder slows it on damp feet. Dry feet let the meter fall, faster when warm and resting.
--
-- Stages at 1x, 2x, 4x and 6x TrenchFootHours: 1 cold, numb feet; 2 swollen and painful; 3 the skin breaks down
-- (a scratch every few hours, halved healing, no sprinting); 4 necrosis (the foot slowly loses health, and it leads
-- to gangrene, Diseases/Extremities/Gangrene).
--
-- The counterplay is dry feet: change into dry socks or dry off. While a foot is dry it recovers one stage after
-- 4/12/24/48 h (stage 1-4), faster resting, warm (a heat source, indoors or a Warming Pack) or under foot powder.
-- Getting wet again restarts the count. A stage 4 foot with gangrene stays until the gangrene is gone.
--
-- A driven condition with one instance for both feet (Diseases/Extremities/Parts), like foot blisters.

local Data = require "ExtensiveHealthRedone/Diseases/Extremities/Data"
local Inputs = require "ExtensiveHealthRedone/Diseases/Extremities/Inputs"
local Meters = require "ExtensiveHealthRedone/Diseases/Extremities/Meters"
local Parts = require "ExtensiveHealthRedone/Diseases/Extremities/Parts"
local Gangrene = require "ExtensiveHealthRedone/Diseases/Extremities/Gangrene"
local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Speech = require "ExtensiveHealthRedone/Core/Speech"

local D = Data.trenchFoot
local ID = "trench_foot"
local METER = "wetColdH"

local STAGE_LINES = {
    [1] = "UI_EHR_Extremities_FeetColdAndNumb",
    [2] = "UI_EHR_Extremities_FeetSwollen",
    [3] = "UI_EHR_Extremities_SkinOnMyFeetPeeling",
    [4] = "UI_EHR_Extremities_CantFeelMyToes",
}

local TrenchFoot = {
    enabledOption = "TrenchFootEnabled",
    driven = true,
    knowledge = ID,
    name = "UI_EHR_Disease_trench_foot",
    xp = false,
    debugSource = "Foot_L",
    lines = {
        random = {
            [1] = { "UI_EHR_Extremities_FeetFeelLikeIce", "UI_EHR_Extremities_NeedDrySocks" },
            [2] = { "UI_EHR_Extremities_FeetThrob", "UI_EHR_Extremities_NeedDrySocks" },
            [3] = { "UI_EHR_Extremities_FeetThrob", "UI_EHR_Extremities_FeetSmellRotten" },
            [4] = { "UI_EHR_Extremities_CantFeelMyToes", "UI_EHR_Extremities_FeetSmellRotten" },
        },
        every = 300,
    },
}

local function option(p, name, default, lo, hi)
    local v = tonumber(p.sandbox(name, default)) or default
    return math.max(lo, math.min(hi, v))
end

function TrenchFoot.hours(p)
    return option(p, "TrenchFootHours", 12, 2, 72)
end

function TrenchFoot.maxTemperature(p)
    return option(p, "TrenchFootMaxTemperature", 15, 0, 25)
end

local function powdered(p)
    return p.treatment:active("footPowder")
end

-- Hours of cold, wet feet gained per hour right now (0 when dry enough or warm enough).
function TrenchFoot.gain(p)
    local wet = Inputs.feetWet(p)
    if wet < D.WET or p.facts.env.airC > TrenchFoot.maxTemperature(p) then
        return 0
    end
    local soaked = wet >= D.SOAKED
    local m = soaked and D.SOAKED_MULT or 1
    if powdered(p) then
        m = m * (soaked and D.POWDER_SOAKED or D.POWDER)
    end
    return m * option(p, "TrenchFootExposureMultiplier", 1, 0, 5)
end

function TrenchFoot.dry(p)
    return Inputs.feetWet(p) < D.DRY
end

-- Recovery speed of a dry foot.
function TrenchFoot.recoveryRate(p)
    local rate = 1
    if Inputs.resting(p) then
        rate = rate * D.REST
    end
    if Inputs.warm(p) then
        rate = rate * D.WARM
    end
    if powdered(p) then
        rate = rate * D.POWDER_HEAL
    end
    return rate
end

-- The stage a meter reaches (0-4).
function TrenchFoot.stageFor(p, wetColdH)
    local hours = TrenchFoot.hours(p)
    for s = #D.STAGE_X, 1, -1 do
        if wetColdH >= D.STAGE_X[s] * hours then
            return s
        end
    end
    return 0
end

local function raise(p, c, foot, stage)
    stage = math.min(stage, #D.STAGE_X)
    if stage <= Parts.stage(c, foot) then
        return
    end
    Parts.setStage(p, c, foot, stage)
    local entry = Parts.get(c, foot)
    entry.dry = 0
    entry.macerate = entry.macerate or 0
    Speech.stage(p, STAGE_LINES[stage])
end

local function lower(p, c, foot)
    local stage = Parts.stage(c, foot) - 1
    Parts.setStage(p, c, foot, stage)
    Parts.get(c, foot).dry = 0
    Gangrene.resetOnset(Parts.get(c, foot))
    local cap = stage > 0 and D.STAGE_X[stage] * TrenchFoot.hours(p) or 0
    Meters.set(p, foot, METER, math.min(Meters.value(p, foot, METER), cap))
end

function TrenchFoot.update(p, dt, defs)
    local def = defs[ID]
    if not Engine.enabled(p, def) or not Inputs.available(p) then
        return
    end
    local h = dt / 60
    local c = p.state.conditions.active[ID]
    local gain = TrenchFoot.gain(p)
    local dry = TrenchFoot.dry(p)
    for _, foot in ipairs(Inputs.FEET) do
        if not Inputs.present(p, foot) then
            if c then
                Parts.drop(p, c, foot)
            end
        else
            local meter = Meters.value(p, foot, METER)
            if gain > 0 then
                meter = meter + gain * h
            elseif dry then
                local decay = (Inputs.warm(p) and Inputs.resting(p)) and D.DECAY_WARM_REST or D.DECAY
                meter = meter - decay * h
            end
            Meters.set(p, foot, METER, meter, D.STAGE_X[#D.STAGE_X] * TrenchFoot.hours(p))
            local target = TrenchFoot.stageFor(p, Meters.value(p, foot, METER))
            local current = c and Parts.stage(c, foot) or 0
            if target > current then
                if not c then
                    c = Engine.contract(p, defs, ID, { stage = target, source = foot })
                end
                if c then
                    raise(p, c, foot, target)
                end
            elseif c and current > 0 then
                local entry = Parts.get(c, foot)
                if current >= 4 then
                    Gangrene.onset(p, defs, foot, entry, h)
                end
                if dry and not (current >= 4 and Gangrene.has(p, foot)) then
                    entry.dry = (entry.dry or 0) + TrenchFoot.recoveryRate(p) * h
                    if entry.dry >= D.DRY_H[current] then
                        lower(p, c, foot)
                    end
                elseif not dry then
                    entry.dry = 0
                end
            end
        end
    end
end

function TrenchFoot.drive(p, c)
    if not Engine.enabled(p, TrenchFoot) then
        return "recovered"
    end
    Parts.seed(p, c, TrenchFoot.debugSource, raise)
    return Parts.result(p, c)
end

function TrenchFoot.onStage(p, c, stage)
    Parts.follow(p, c, stage, raise)
end

function TrenchFoot.effects(p, c, dt)
    local relief = 1 - p.treatment:relief(ID, "pain")
    local h = dt / 60
    for _, e in ipairs(Parts.list(c)) do
        local foot, stage = e.part, e.stage
        p.body:pain(foot, ID, D.PAIN[stage] * relief)
        if stage >= D.NO_SPRINT_FROM then
            p.body:healFactor(foot, ID, D.HEAL_FACTOR)
            local entry = Parts.get(c, foot)
            entry.macerate = (entry.macerate or 0) + h
            if entry.macerate >= D.MACERATION_H then
                entry.macerate = 0
                p.body:scratch(foot, ID)
            end
        end
        if stage >= 4 then
            p.body:partDamage(foot, ID, D.NECROSIS_DAMAGE_H * h)
        end
    end
    local speed = D.SPEED[c.stage]
    if speed then
        p.fx:speed(ID, speed)
    end
    if c.stage >= D.NO_SPRINT_FROM then
        p.fx:noSprint(ID)
    end
end

function TrenchFoot.onEnd(p, c, reason)
    if reason == "recovered" or reason == "cured" then
        if (c.data.maxStage or 0) >= D.XP_FROM and p.xp then
            p.xp("cure", ID)
        end
        if reason == "recovered" then
            Speech.stage(p, "UI_EHR_Extremities_FeetWarmAgain")
        end
    end
    if reason ~= "recovered" then
        Meters.clear(p, METER)
    end
end

function TrenchFoot.monitorRow(row, c, known)
    if not known.name then
        return
    end
    row.description = Parts.label(c)
    row.descriptionColor = "dim"
end

-- The worst foot's share of stage 1 (0-100+), for the Monitor's wet feet row (exposure.feet).
function TrenchFoot.display(p)
    local worst = 0
    for _, foot in ipairs(Inputs.FEET) do
        worst = math.max(worst, Meters.value(p, foot, METER))
    end
    local value = math.floor(worst / TrenchFoot.hours(p) * 100 + 0.5)
    if p.state.exposure.feet ~= value then
        p.state.exposure.feet = value
        p.dirty("exposure")
    end
end

TrenchFoot.systems = {
    {
        name = "trenchFoot",
        order = 337,
        update = function(p, dt, defs)
            TrenchFoot.update(p, dt, defs)
            TrenchFoot.display(p)
        end,
    },
}

return TrenchFoot
