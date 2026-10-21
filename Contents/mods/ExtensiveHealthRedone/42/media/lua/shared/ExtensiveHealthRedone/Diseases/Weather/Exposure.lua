-- The cold and heat exposure meters and the triggers they drive: common cold, hypothermia, heat exhaustion and heat
-- stroke. Two simulation systems, before the condition engine. From v0.9 EHR_EnvironmentalDiseases.lua:1196-1550,
-- :1642-1731 (docs/porting/phase4/environmental.md, sections 1.1-1.2 and 4.1-4.2). Differences from v0.9:
--   * W13: the cold-and-wet route starts at 5 deg C (v0.9: 0).
--   * The meters are saved (v0.9 lost them on every reload).
--   * A cold roll blocked by another illness doesn't use up the hourly roll.
--   * The cold bath also cools the heat meter, and drives the bath cure (Server/Weather starts and keeps it alive).

local Data = require "ExtensiveHealthRedone/Diseases/Weather/Data"
local Meters = require "ExtensiveHealthRedone/Diseases/Weather/Meters"
local Hypothermia = require "ExtensiveHealthRedone/Diseases/Weather/Hypothermia"
local HeatExhaustion = require "ExtensiveHealthRedone/Diseases/Weather/HeatExhaustion"
local HeatStroke = require "ExtensiveHealthRedone/Diseases/Weather/HeatStroke"
local CommonCold = require "ExtensiveHealthRedone/Diseases/Weather/CommonCold"
local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Risk = require "ExtensiveHealthRedone/Conditions/Risk"
local Chance = require "ExtensiveHealthRedone/Core/Chance"
local Speech = require "ExtensiveHealthRedone/Core/Speech"
local Timers = require "ExtensiveHealthRedone/Core/Timers"
local Temperature = require "ExtensiveHealthRedone/Body/Temperature"

local Exposure = {}

local C = Data.cold
local H = Data.heat

local function option(p, name, default, lo, hi)
    local v = tonumber(p.sandbox(name, default)) or default
    return math.max(lo, math.min(hi, v))
end

local function anyActive(p, ids)
    local active = p.state.conditions.active
    for _, id in ipairs(ids) do
        if active[id] then
            return true
        end
    end
    return false
end

-- Writes a display percentage and marks the section only when the whole number changes.
local function display(p, field, value)
    value = math.floor(value + 0.5)
    if p.state.exposure[field] ~= value then
        p.state.exposure[field] = value
        p.dirty("exposure")
    end
end

local function nearHeat(p)
    return p.facts.weather ~= nil and p.facts.weather.nearHeat == true
end

-- An active Warming Pack counts as a heat source against the cold, but not against being soaked (maintainer, Phase 6).
local function warmingPack(p)
    return Temperature.enabled(p) and Temperature.warmingActive(p.state)
end

-- Cold ---------------------------------------------------------------------------------------------------------------

local COLD_BLOCKERS = { "common_cold", "pneumonia", "hypothermia", "heat_stroke" }

function Exposure.updateCold(p, dt, defs)
    local w = Meters.weather(p)
    local env = p.facts.env
    local h = dt / 60
    if not Engine.enabled(p, defs.common_cold) then
        w.coldH, w.soakedH = 0, 0
        display(p, "cold", 0)
        return
    end
    local wet, air = env.wetness, env.airC
    local body = p.facts.stats and p.facts.stats.TEMPERATURE or 37
    local heat = nearHeat(p)
    local pack = warmingPack(p)
    local freezingRisk = air <= C.FREEZING_C and wet > C.WET and not env.indoors and not heat and not pack
    local soakedRisk = wet >= C.HEAVILY_SOAKED and not heat
    local warm = heat or pack or (env.indoors and body > C.WARM_INDOORS_BODY_C) or body > C.WARM_BODY_C
        or (not env.indoors and air > C.FREEZING_C)
    local mult = option(p, "CommonColdExposureMultiplier", 1, 0, 5)

    if Meters.bathing(p) then
        w.coldH = math.max(0, w.coldH - C.DECAY_BATHING * h)
        w.soakedH = math.max(0, w.soakedH - C.DECAY_BATHING * h)
        freezingRisk, soakedRisk = false, false
    elseif warm and not freezingRisk and not soakedRisk then
        w.coldH = math.max(0, w.coldH - C.DECAY_WARM * h)
        w.soakedH = math.max(0, w.soakedH - C.DECAY_WARM * h)
    else
        if freezingRisk then
            w.coldH = w.coldH + h * (wet > C.SOAKED and C.GAIN_SOAKED or C.GAIN) * mult
        else
            w.coldH = math.max(0, w.coldH - C.DECAY * h)
        end
        if soakedRisk then
            w.soakedH = w.soakedH + h * mult
        else
            w.soakedH = math.max(0, w.soakedH - C.DECAY * h)
        end
    end
    display(p, "cold", math.min(100, 100 * math.max(w.coldH / C.READY_FREEZING_H, w.soakedH / C.READY_SOAKED_H)))

    local ready = (freezingRisk and w.coldH >= C.READY_FREEZING_H) or (soakedRisk and w.soakedH >= C.READY_SOAKED_H)
    if not ready or Timers.running(w.timers, "coldRoll") or anyActive(p, COLD_BLOCKERS) then
        return
    end
    Timers.start(w.timers, "coldRoll", C.ROLL_EVERY)
    local freezing = math.min(C.FREEZING_CAP, C.FREEZING_BASE * w.coldH / C.READY_FREEZING_H)
    local soaked = math.min(C.SOAKED_CAP, C.SOAKED_BASE * w.soakedH / C.READY_SOAKED_H)
    local chance = math.min(1, math.max(freezing, soaked) * option(p, "CommonColdChanceMultiplier", 1, 0, 5))
    chance = Risk.chance(p, "common_cold", chance)
    if Chance.roll(p.rng, chance) and Engine.contract(p, defs, "common_cold", { source = "cold" }) then
        w.coldH, w.soakedH = 0, 0
        display(p, "cold", 0)
        Speech.stage(p, CommonCold.lines.stage[1])
    end
end

-- Heat ---------------------------------------------------------------------------------------------------------------

local STROKE_BLOCKERS = { "heat_stroke", "common_cold", "pneumonia", "hypothermia" }

local function inWindow(hour, startHour, endHour)
    if startHour == endHour then
        return true
    elseif startHour < endHour then
        return hour >= startHour and hour < endHour
    end
    return hour >= startHour or hour < endHour
end

-- Meter change per game hour (negative: recovering).
function Exposure.heatRate(p)
    local env = p.facts.env
    local air = Meters.heatAir(p)
    local threshold = Meters.threshold(p)
    local recover = option(p, "HeatExposureRecoveryMultiplier", 1, 0, 5)
    local hour = env.hour
    if Meters.bathing(p) or env.indoors then
        return -H.RECOVER_INDOORS * recover
    elseif not inWindow(hour, option(p, "HeatExposureStartHour", 9, 0, 23), option(p, "HeatExposureEndHour", 20, 0, 23)) then
        return -H.RECOVER_OFF_HOURS * recover
    elseif air < threshold then
        return -H.RECOVER_COOL * recover
    elseif env.shade and air < H.SHADE_MAX_C then
        return -H.RECOVER_SHADE * recover
    end
    local m = math.min(H.MAX_HEAT_MULT, 1 + H.PER_DEGREE * (air - threshold))
    if env.exerting then
        m = m * H.EXERTING
    end
    local thirst = p.facts.norm and p.facts.norm.THIRST or 0
    if thirst > H.THIRSTY_AT then
        m = m * H.THIRSTY
        if thirst > H.VERY_THIRSTY_AT then
            m = m * H.VERY_THIRSTY
        end
    end
    if env.shade then
        m = m * H.SHADE
    end
    if p.facts.weather and p.facts.weather.headwear then
        m = m * option(p, "HeatHeadwearExposureMultiplier", 0.30, 0, 1)
    end
    return m * option(p, "HeatExposureGainMultiplier", 1, 0, 5)
end

local function strokeChance(p, ratio)
    local t = (ratio - H.STROKE_RISK) / (1 - H.STROKE_RISK)
    local chance = H.STROKE_BASE + H.STROKE_SPAN * t
    local thirst = p.facts.norm and p.facts.norm.THIRST or 0
    if thirst > H.VERY_THIRSTY_AT then
        chance = chance * H.STROKE_VERY_THIRSTY
    elseif thirst > H.THIRSTY_AT then
        chance = chance * H.STROKE_THIRSTY
    end
    if p.facts.env.exerting then
        chance = chance * H.STROKE_EXERTING
    end
    chance = chance * option(p, "HeatStrokeChanceMultiplier", 1, 0, 5)
    return math.max(0, math.min(H.STROKE_MAX, chance))
end

function Exposure.updateHeat(p, dt, defs)
    local w = Meters.weather(p)
    if not Engine.enabled(p, defs.heat_exhaustion) then
        w.heatH, w.heatFalling = 0, 0
        display(p, "heat", 0)
        return
    end
    if p.state.conditions.active.heat_stroke then
        w.heatH, w.heatFalling = 0, 0
        display(p, "heat", 0)
        return
    end
    local before = w.heatH
    w.heatH = math.max(0, w.heatH + Exposure.heatRate(p) * dt / 60)
    if w.heatH < before then
        w.heatFalling = w.heatFalling + dt
    else
        w.heatFalling = 0
    end
    local ratio = Meters.heatRatio(p)
    display(p, "heat", 100 * math.min(H.DISPLAY_MAX, ratio))
    HeatExhaustion.check(p, defs)

    if ratio < H.STROKE_RISK or anyActive(p, STROKE_BLOCKERS) or not Engine.enabled(p, defs.heat_stroke) then
        return
    end
    if ratio >= 1 then
        HeatStroke.start(p, defs)
    elseif not Timers.running(w.timers, "strokeRoll") then
        Timers.start(w.timers, "strokeRoll", H.STROKE_ROLL_EVERY)
        if Chance.roll(p.rng, strokeChance(p, ratio)) then
            HeatStroke.start(p, defs)
        end
    end
end

-- Cold bath: Server/Weather opens it and keeps it alive with heartbeats; after 3 h it cures heat stroke.
function Exposure.updateBath(p, dt, defs)
    local w = Meters.weather(p)
    local bath = w.bath
    if not bath then
        return
    end
    if not p.state.conditions.active.heat_stroke then
        w.bath = nil
        p.client("coldBathDone", { cured = false })
        return
    end
    bath.left = bath.left - dt
    bath.elapsed = bath.elapsed + dt
    if bath.elapsed >= Data.heatStroke.BATH_MINUTES then
        w.bath = nil
        Engine.cure(p, defs, "heat_stroke")
        Speech.stage(p, "UI_EHR_ColdBath_Complete")
        p.client("coldBathDone", { cured = true })
    elseif bath.left <= 0 then
        w.bath = nil            -- no heartbeat: the client stopped bathing
    end
end

Exposure.systems = {
    {
        name = "weatherCold",
        order = 320,
        update = function(p, dt, defs)
            Timers.advance(Meters.weather(p).timers, dt)
            Exposure.updateCold(p, dt, defs)
            Hypothermia.check(p, defs)
        end,
    },
    {
        name = "weatherHeat",
        order = 330,
        update = function(p, dt, defs)
            Exposure.updateBath(p, dt, defs)
            Exposure.updateHeat(p, dt, defs)
        end,
    },
}

return Exposure
