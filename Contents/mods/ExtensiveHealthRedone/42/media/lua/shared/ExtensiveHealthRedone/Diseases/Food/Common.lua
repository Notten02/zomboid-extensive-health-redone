-- Helpers shared by the food-borne diseases: relief multipliers, symptom cooldowns, vomiting, nausea, health drain.
--
-- Relief (p.treatment:relief(id, symptom)) uses these symptom names:
--   general     the tier relief of any active medicine for this disease (symptom multiplier: t0 .15, t1 .40, t2 .60,
--               t3 .80)
--   nausea, vomiting, dehydration, weakness, pain, fever, muscleSpasms, inflammation, diarrhea

local Data = require "ExtensiveHealthRedone/Diseases/Food/Data"
local Chance = require "ExtensiveHealthRedone/Core/Chance"
local Speech = require "ExtensiveHealthRedone/Core/Speech"

local Common = {}

-- The symptom multiplier from general relief: 1 untreated, at least 0.20.
function Common.symptomMult(p, id)
    return math.max(0.20, 1 - p.treatment:relief(id, "general"))
end

-- Per-disease multipliers.
function Common.mults(p, id)
    local t = p.treatment
    local sm = Common.symptomMult(p, id)
    return {
        symptom = sm,
        vomit = math.max(0.08, sm * (1 - math.max(t:relief(id, "vomiting"), 0.5 * t:relief(id, "nausea")))),
        hydration = math.max(0.15, sm * (1 - t:relief(id, "dehydration"))),
        weakness = math.max(0.20, sm * (1 - t:relief(id, "weakness"))),
        nausea = math.max(0.45, 1 - math.max(0.75 * t:relief(id, "nausea"), t:relief(id, "sickness"))),
    }
end

-- A symptom with a chance per engine check (Data TICK) and a cooldown in game minutes, tracked in c.data. Returns
-- true when it fires.
function Common.symptom(p, c, key, chancePerTick, cooldown, dt, ticksPerMinute)
    local left = (c.data[key] or 0) - dt
    if left > 0 then
        c.data[key] = left
        return false
    end
    c.data[key] = nil
    if Chance.roll(p.rng, Chance.over(chancePerTick, ticksPerMinute or Data.TICK, dt)) then
        c.data[key] = cooldown
        return true
    end
    return false
end

-- Vomiting: a line, hungrier and thirstier (fractions of the range; 0 skips one), and the retching noise.
function Common.vomit(p, id, hunger, thirst)
    Speech.stage(p, Speech.pick(p, Data.VOMIT_LINES))
    if hunger > 0 then
        p.stats:addF("HUNGER", id, hunger)
    end
    if thirst > 0 then
        p.stats:addF("THIRST", id, thirst)
    end
    p.noise("vomit")
end

-- Nausea through vanilla's SICKNESS (the Queasy/Nauseous moodles): a per-stage level, times (0.5 + severity),
-- the symptom multiplier and nausea relief, at most 0.65 (below vanilla's lethal range). floor: a minimum level
-- (gastroenteritis), already lowered by relief.
Common.SICKNESS = { [1] = 0.10, [2] = 0.35, [3] = 0.60, [4] = 0.20 }
Common.SICKNESS_CAP = 0.65
Common.SICKNESS_STEP = 0.01     -- per game minute

function Common.nausea(p, id, c, dt, m, floor)
    local target = (Common.SICKNESS[c.stage] or 0) * (0.5 + c.severity) * m.symptom * m.nausea
    if floor then
        target = math.max(target, floor)
    end
    target = math.min(Common.SICKNESS_CAP, target)
    if target > 0 then
        p.stats:raiseF("SICKNESS", id, target, Common.SICKNESS_STEP * dt)
    end
end

-- Endurance drained toward a floor by `amount` per engine check (Data TICK).
function Common.drainEndurance(p, id, amount, floor, dt)
    if amount > 0 then
        p.stats:lowerF("ENDURANCE", id, floor, amount * Data.TICK * dt)
    end
end

-- Untreated lethal stage: health falls by hp every `everyMinutes` and never regenerates; at or below killBelow, each
-- damage event rolls killChance (trichinosis and mushroom stage 3).
function Common.drain(p, id, c, dt, hp, everyMinutes, killBelow, killChance)
    p.body:damage(id, hp / everyMinutes * dt, 0)
    p.body:healFactorAll(require("ExtensiveHealthRedone/Data/BodyParts").names, id, 0)
    if p.facts.health <= killBelow and Chance.roll(p.rng, Chance.over(killChance, 1 / everyMinutes, dt)) then
        Speech.stage(p, "UI_EHR_Text_Collapses")
        p.body:kill(id, id)
    end
end

-- The shared end of every food disease: "I think I'm finally over it..." on natural recovery. Tracked pain, nausea
-- and fever are per-step contributions, so nothing else is left behind on either path.
function Common.onEnd(p, c, reason)
    if reason == "recovered" then
        Speech.stage(p, Data.RECOVERED_LINE)
    end
end

return Common
