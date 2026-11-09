-- Frostnip and frostbite: frozen tissue on the hands and feet. Per part, a frost meter grows while the part's
-- effective temperature is below FrostbiteTemperature: the air (wind chill outdoors, the room's air indoors through
-- Indoor Climate Redone, the cabin in a vehicle), plus the clothing insulation over the part (vanilla's thermal
-- node, which already drops for wet clothing), less a wet part's extra loss and the core cold (a cold body pulls blood
-- from the hands and feet; more with hypothermia). The colder, the faster. A Warming Pack held in the hands halves the
-- gain there.
--
-- Stages: 1 frostnip (cold, white, painful; thaws fully within an hour of warmth), 2 superficial frostbite, 3 deep
-- frostbite (a blister: a scratch, halved healing, no sprinting on a foot), 4 necrosis (numb, dead tissue: the part
-- loses health and turns gangrenous, Diseases/Extremities/Gangrene). Hands lose aim, feet slow the walk.
--
-- Rewarming heals: warm surroundings (a heat source, indoors, a Warming Pack) or air at least 5 deg C. Frostnip thaws
-- in an hour (20 minutes by a fire or with a pack); deeper stages heal a stage per 2-3 days of warmth, faster by heat.
-- A gangrenous part stays at stage 4 until the gangrene is gone. The Only Cure: a cut hand is gone from here too.
--
-- A driven condition with one instance for all four parts (Diseases/Extremities/Parts). selfEvident, like hypothermia.

local Data = require "ExtensiveHealthRedone/Diseases/Extremities/Data"
local Inputs = require "ExtensiveHealthRedone/Diseases/Extremities/Inputs"
local Meters = require "ExtensiveHealthRedone/Diseases/Extremities/Meters"
local Parts = require "ExtensiveHealthRedone/Diseases/Extremities/Parts"
local Gangrene = require "ExtensiveHealthRedone/Diseases/Extremities/Gangrene"
local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Speech = require "ExtensiveHealthRedone/Core/Speech"

local D = Data.frostbite
local ID = "frostbite"
local METER = "frost"

local STAGE_LINES = {
    [1] = "UI_EHR_Extremities_FrostnipStings",
    [2] = "UI_EHR_Extremities_FrostbiteWhite",
    [3] = "UI_EHR_Extremities_FrostbiteBlisters",
    [4] = "UI_EHR_Extremities_FrostbiteDead",
}

local Frostbite = {
    enabledOption = "FrostbiteEnabled",
    driven = true,
    knowledge = ID,
    selfEvident = true,
    name = "UI_EHR_Disease_frostbite",
    xp = false,
    debugSource = "Hand_L",
    lines = {
        random = {
            [1] = { "UI_EHR_Extremities_FingersBurnWithCold", "UI_EHR_Extremities_NeedToWarmUp" },
            [2] = { "UI_EHR_Extremities_FingersBurnWithCold", "UI_EHR_Extremities_CantFeelMyFingers" },
            [3] = { "UI_EHR_Extremities_CantFeelMyFingers", "UI_EHR_Extremities_FrostbiteThrob" },
            [4] = { "UI_EHR_Extremities_FrostbiteThrob", "UI_EHR_Extremities_FrostbiteDead" },
        },
        every = 240,
        quiet = function(p) return Inputs.nearHeat(p) end,
    },
}

local function option(p, name, default, lo, hi)
    local v = tonumber(p.sandbox(name, default)) or default
    return math.max(lo, math.min(hi, v))
end

function Frostbite.threshold(p)
    return option(p, "FrostbiteTemperature", -10, -40, 5)
end

-- The air around the hands and feet.
function Frostbite.air(p)
    local env = p.facts.env
    if env.vehicleC then
        return env.vehicleC
    end
    if env.indoors then
        return env.airC
    end
    local e = p.facts.extremities
    return e and e.windChillC or env.airC
end

local function coreCold(p)
    local h = p.state.conditions.active.hypothermia
    if h and h.stage >= 2 then
        return D.HYPOTHERMIA_C
    end
    local body = p.facts.stats and p.facts.stats.TEMPERATURE
    if type(body) == "number" and body < D.CORE_COLD_BODY_C then
        return D.CORE_COLD_C
    end
    return 0
end

-- A part's effective temperature (deg C).
function Frostbite.effective(p, part)
    local t = Frostbite.air(p) + Inputs.insulation(p, part) * D.INSULATION_C - coreCold(p)
    if Inputs.wet(p, part) >= D.WET then
        t = t - D.WET_C
    end
    return t
end

-- Frost gained per hour on the part right now (0 when warm enough).
function Frostbite.gain(p, part)
    local below = Frostbite.threshold(p) - Frostbite.effective(p, part)
    if below <= 0 then
        return 0
    end
    local g = (below / 10) ^ D.POWER * option(p, "FrostbiteSpeed", 1, 0.1, 5)
    if not Inputs.isFoot(part) and Inputs.warmingPack(p) then
        g = g * D.PACK_HANDS
    end
    return g
end

-- The part is being rewarmed.
function Frostbite.rewarming(p, part)
    return Inputs.warm(p) or Frostbite.effective(p, part) >= D.WARM_C
end

-- Thawing speed of a rewarming part at a stage.
function Frostbite.thawRate(p, stage)
    if Inputs.nearHeat(p) or Inputs.warmingPack(p) then
        return stage <= 1 and D.THAW_HEAT_NIP or D.THAW_HEAT
    end
    return 1
end

function Frostbite.stageFor(frost)
    for s = #D.STAGE, 1, -1 do
        if frost >= D.STAGE[s] then
            return s
        end
    end
    return 0
end

local function raise(p, c, part, stage)
    stage = math.min(stage, #D.STAGE)
    local before = Parts.stage(c, part)
    if stage <= before then
        return
    end
    Parts.setStage(p, c, part, stage)
    Parts.get(c, part).thaw = 0
    Speech.stage(p, STAGE_LINES[stage])
    if stage >= 3 and before < 3 then
        p.body:scratch(part, ID)
    end
end

local function lower(p, c, part)
    local stage = Parts.stage(c, part) - 1
    Parts.setStage(p, c, part, stage)
    local entry = Parts.get(c, part)
    entry.thaw = 0
    Gangrene.resetOnset(entry)
    local cap = stage > 0 and D.STAGE[stage] or 0
    Meters.set(p, part, METER, math.min(Meters.value(p, part, METER), cap))
end

function Frostbite.update(p, dt, defs)
    local def = defs[ID]
    if not Engine.enabled(p, def) or not Inputs.available(p) then
        return
    end
    local h = dt / 60
    local c = p.state.conditions.active[ID]
    for _, part in ipairs(Inputs.ALL) do
        if not Inputs.present(p, part) then
            if c then
                Parts.drop(p, c, part)
            end
        else
            local frost = Meters.value(p, part, METER)
            local gain = Frostbite.gain(p, part)
            local warming = gain == 0 and Frostbite.rewarming(p, part)
            if gain > 0 then
                frost = frost + gain * h
            elseif warming then
                frost = frost - D.DECAY * h
            end
            Meters.set(p, part, METER, frost, D.MAX)
            local target = Frostbite.stageFor(Meters.value(p, part, METER))
            local current = c and Parts.stage(c, part) or 0
            if target > current then
                if not c then
                    c = Engine.contract(p, defs, ID, { stage = target, source = part })
                end
                if c then
                    raise(p, c, part, target)
                end
            elseif c and current > 0 then
                local entry = Parts.get(c, part)
                if current >= 4 then
                    Gangrene.onset(p, defs, part, entry, h)
                end
                if warming and not (current >= 4 and Gangrene.has(p, part)) then
                    entry.thaw = (entry.thaw or 0) + Frostbite.thawRate(p, current) * h
                    if entry.thaw >= D.THAW_H[current] then
                        lower(p, c, part)
                    end
                end
            end
        end
    end
end

function Frostbite.drive(p, c)
    if not Engine.enabled(p, Frostbite) then
        return "recovered"
    end
    Parts.seed(p, c, Frostbite.debugSource, raise)
    return Parts.result(p, c)
end

function Frostbite.onStage(p, c, stage)
    Parts.follow(p, c, stage, raise)
end

function Frostbite.effects(p, c, dt)
    local relief = 1 - p.treatment:relief(ID, "pain")
    local h = dt / 60
    local hand, foot = 0, 0
    for _, e in ipairs(Parts.list(c)) do
        local part, stage = e.part, e.stage
        p.body:pain(part, ID, D.PAIN[stage] * relief)
        local heal = D.HEAL_FACTOR[stage]
        if heal then
            p.body:healFactor(part, ID, heal)
        end
        if stage >= 4 then
            p.body:partDamage(part, ID, D.NECROSIS_DAMAGE_H * h)
        end
        if Inputs.isFoot(part) then
            foot = math.max(foot, stage)
        else
            hand = math.max(hand, stage)
        end
    end
    if hand > 0 then
        p.fx:aim(ID, D.AIM[hand])
    end
    if foot > 0 then
        p.fx:speed(ID, D.SPEED[foot])
        if foot >= D.NO_SPRINT_FROM then
            p.fx:noSprint(ID)
        end
    end
end

function Frostbite.onEnd(p, c, reason)
    if reason == "recovered" or reason == "cured" then
        if (c.data.maxStage or 0) >= D.XP_FROM and p.xp then
            p.xp("cure", ID)
        end
        if reason == "recovered" then
            Speech.stage(p, "UI_EHR_Extremities_FeelingComesBack")
        end
    end
    if reason ~= "recovered" then
        Meters.clear(p, METER)
    end
end

function Frostbite.monitorRow(row, c, known)
    if not known.name then
        return
    end
    row.description = Parts.label(c)
    row.descriptionColor = "dim"
end

Frostbite.systems = {
    { name = "frostbite", order = 338, update = Frostbite.update },
}

return Frostbite
