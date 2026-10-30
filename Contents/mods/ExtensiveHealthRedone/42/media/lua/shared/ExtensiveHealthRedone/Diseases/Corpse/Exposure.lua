-- The two corpse meters: corpse exposure (corpse illness) and spore exposure (cadaveric aspergillosis). Pure: the
-- server's corpse reader (Server/Corpse) puts what is around the player into p.facts.corpses:
--   { fresh, decomposing, rotten = corpse counts sharing the player's air, env = 1 outdoors / 1.5 indoors / 2 small
--     room, protection = 0-1 (worn mask), sealed = in a closed vehicle }
-- Both meters build independently, the corpse meter keeps building while the player is ill (so fresh air can shorten
-- the illness), and the display bands are 30/60/100.

local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Risk = require "ExtensiveHealthRedone/Conditions/Risk"
local Chance = require "ExtensiveHealthRedone/Core/Chance"
local Speech = require "ExtensiveHealthRedone/Core/Speech"
local Episodes = require "ExtensiveHealthRedone/Diseases/Corpse/Episodes"

local Exposure = {}

Exposure.CORPSE = {
    EMISSION = { fresh = 1, decomposing = 2, rotten = 5 },  -- points per game hour per corpse
    DECAY = 30,                 -- points per hour without exposure
    GUARANTEED = 100,           -- contraction is certain at this exposure
    RISK = 85,                  -- hourly rolls from here (30% rising to 100%)
    RISK_CHANCE = { 0.30, 0.70 },
    MIN_MINUTES = 60,           -- exposure before the first roll; then a roll every hour
    SMELL_AT = 15,              -- smell lines from this exposure,
    SMELL_AFTER = 15,           -- after this many minutes in the area,
    SMELL_EVERY = 30,           -- at most this often (minutes)
    NAUSEA_MAX = 0.6,           -- sickness raised toward exposure/100 x this before the illness starts
    BANDS = { low = 30, medium = 60, high = 100 },
}

Exposure.SPORES = {
    LOAD = { decomposing = 1, rotten = 2 },                 -- fresh corpses carry no spores
    GAIN = 1.8,
    DAMP = 1.6, COLD = 1.25, INDOORS = 1.15,                -- weather multipliers (damp or cold needed at all)
    DAMP_WETNESS = 0.30, COLD_AIR = 10,
    DECAY = 25,
    GUARANTEED = 120,
    RISK = 0.85,                -- share of GUARANTEED from which hourly rolls start (35% rising to 85%)
    RISK_CHANCE = { 0.35, 0.50 },
    MIN_MINUTES = 90,
}

Exposure.SMELL_LINES = {
    "UI_EHR_Text_UghThatSmell", "UI_EHR_Text_SomethingsRottingNearby", "UI_EHR_Text_TheStenchOfDeath",
    "UI_EHR_Text_ICanSmellDecomposition", "UI_EHR_Text_ThatsTheSmellOfDecay",
}

-- "none", "low", "medium" or "high" for the monitor.
function Exposure.band(value)
    local b = Exposure.CORPSE.BANDS
    if value >= b.high then
        return "high"
    elseif value >= b.medium then
        return "medium"
    elseif value >= b.low then
        return "low"
    end
    return "none"
end

local function data(p)
    local d = p.state.exposure.data
    -- Minutes: time in the area, since the last roll, since the last smell line; the same for spores.
    d.corpse = d.corpse or { minutes = 0, sinceRoll = 0, sinceSmell = 999, sporeMinutes = 0, sporeSinceRoll = 0 }
    return d.corpse
end

-- Marks the section dirty only when a meter moves by a whole point, so the meters don't sync every minute.
local function set(p, field, value)
    local exposure = p.state.exposure
    value = math.max(0, value)
    if math.floor(value) ~= math.floor(exposure[field]) then
        p.dirty("exposure")
    end
    exposure[field] = value
end

local function enabled(p, def)
    return def ~= nil and Engine.enabled(p, def)
end

local function speed(p)
    local s = tonumber(p.sandbox("CorpseDiseaseSpeed", 1)) or 1
    return s > 0 and s or 1
end

-- Corpse meter: one step of dt minutes.
local function corpseMeter(p, defs, dt, seen)
    local C = Exposure.CORPSE
    local d = data(p)
    local h = dt / 60
    local id = "corpse_sickness"
    local exposure = p.state.exposure
    if not enabled(p, defs[id]) or Engine.isBlocked(p.state, id) then
        set(p, "corpse", 0)
        d.minutes = 0
        return
    end
    local emission = C.EMISSION.fresh * seen.fresh + C.EMISSION.decomposing * seen.decomposing
        + C.EMISSION.rotten * seen.rotten
    if seen.sealed or seen.protection >= 1 or emission <= 0 then
        set(p, "corpse", exposure.corpse - C.DECAY * h)
        d.minutes = 0
        return
    end
    set(p, "corpse", exposure.corpse + emission * h * seen.env * (1 - seen.protection) * speed(p))
    d.minutes = d.minutes + dt
    d.sinceRoll = d.sinceRoll + dt
    d.sinceSmell = d.sinceSmell + dt

    local value = exposure.corpse
    if value >= C.SMELL_AT and d.minutes >= C.SMELL_AFTER and d.sinceSmell >= C.SMELL_EVERY then
        d.sinceSmell = 0
        Speech.stage(p, Speech.pick(p, Exposure.SMELL_LINES))
    end
    if p.state.conditions.active[id] then
        return
    end
    p.stats:raiseF("SICKNESS", "corpseAir", math.min(C.NAUSEA_MAX, value / 100 * C.NAUSEA_MAX), 0.005 * dt)
    local catch = value >= C.GUARANTEED
    if not catch and value >= C.RISK and d.minutes >= C.MIN_MINUTES and d.sinceRoll >= 60 then
        d.sinceRoll = 0
        local chance = C.RISK_CHANCE[1] + C.RISK_CHANCE[2] * (value - C.RISK) / (C.GUARANTEED - C.RISK)
        catch = Chance.roll(p.rng, Risk.chance(p, id, chance))
    end
    if catch and Engine.contract(p, defs, id, { source = "corpses" }) then
        set(p, "corpse", 0)
        d.minutes, d.sinceRoll = 0, 0
        Speech.stage(p, "UI_EHR_Text_IDontFeelSoGoodMustBeTheCorpses")
    end
end

-- Weather multiplier for spores: 0 when neither damp nor cold.
function Exposure.fungal(env)
    local S = Exposure.SPORES
    local damp = env.wetness >= S.DAMP_WETNESS or (env.raining and not env.indoors)
    local cold = env.airC <= S.COLD_AIR
    if not damp and not cold then
        return 0
    end
    local m = 1
    if damp then m = m * S.DAMP end
    if cold then m = m * S.COLD end
    if env.indoors then m = m * S.INDOORS end
    return m
end

-- Spore meter: one step of dt minutes.
local function sporeMeter(p, defs, dt, seen)
    local S = Exposure.SPORES
    local d = data(p)
    local h = dt / 60
    local id = "cadaveric_aspergillosis"
    local exposure = p.state.exposure
    if not enabled(p, defs[id]) or p.state.conditions.active[id] then
        set(p, "spores", 0)
        d.sporeMinutes = 0
        return
    end
    local load = S.LOAD.decomposing * seen.decomposing + S.LOAD.rotten * seen.rotten
    local weather = Exposure.fungal(p.facts.env)
    if seen.sealed or seen.protection >= 1 or load <= 0 or weather <= 0 then
        set(p, "spores", exposure.spores - S.DECAY * h)
        d.sporeMinutes = math.max(0, d.sporeMinutes - dt)
        return
    end
    set(p, "spores", exposure.spores + load * S.GAIN * weather * (1 - seen.protection) * speed(p) * h)
    d.sporeMinutes = d.sporeMinutes + dt
    d.sporeSinceRoll = d.sporeSinceRoll + dt
    local ratio = exposure.spores / S.GUARANTEED
    local catch = ratio >= 1
    if not catch and ratio >= S.RISK and d.sporeMinutes >= S.MIN_MINUTES and d.sporeSinceRoll >= 60 then
        d.sporeSinceRoll = 0
        local chance = S.RISK_CHANCE[1] + S.RISK_CHANCE[2] * (ratio - S.RISK) / (1 - S.RISK)
        catch = Chance.roll(p.rng, Risk.chance(p, id, chance))
    end
    if catch and Engine.contract(p, defs, id, { source = "spores" }) then
        set(p, "spores", 0)
        d.sporeMinutes, d.sporeSinceRoll = 0, 0
        Speech.stage(p, "UI_EHR_Text_CoughsMyChestFeelsWrongAfterBreathingThatAir")
    end
end

local NOTHING = { fresh = 0, decomposing = 0, rotten = 0, env = 1, protection = 0, sealed = false }

function Exposure.update(p, dt, defs)
    local seen = p.facts.corpses or NOTHING
    sporeMeter(p, defs, dt, seen)
    corpseMeter(p, defs, dt, seen)
    data(p).corpses = seen.fresh + seen.decomposing + seen.rotten
end

Exposure.system = { name = "corpseExposure", order = 330, update = Exposure.update }

return Exposure
