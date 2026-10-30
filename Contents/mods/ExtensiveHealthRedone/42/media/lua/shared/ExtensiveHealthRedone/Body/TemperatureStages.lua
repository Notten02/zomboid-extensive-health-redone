-- Pre-disease effects (order 795, after Body/Temperature so it knows about a fever): four cold and four hot stages
-- from body temperature, before hypothermia (35 deg C) or heat illness set in.
--
-- A stage moves at most one step per update, with 0.3 deg C of hysteresis. While a stage lasts the character says one
-- of its two lines every 30 game minutes (not asleep). Effects: very cold slows movement 5/15/25 % at stages 2-4, very
-- hot drains thirst x1.25/1.5/2.
-- A fever alone is illness, not heat: while one is held, the hot stages fall back as at normal temperature.
-- Off with PreDiseaseEffectsEnabled=false or BodyTemperatureEnabled=false.
--
-- State, in state.temperature: cold, hot (0-4), lineIn (game minutes to the next line), lastThirst (THIRST expected
-- after our last write, or false).

local Speech = require "ExtensiveHealthRedone/Core/Speech"
local Temperature = require "ExtensiveHealthRedone/Body/Temperature"

local Stages = {}

Stages.COLD = { 35.8, 35.5, 35.0, 34.0 }    -- enter a stage below this (Chilly, Cold, Very cold, Freezing)
Stages.HOT = { 37.5, 38.5, 39.5, 40.5 }     -- enter a stage above this (Warm, Hot, Very hot, Overheating)
Stages.HYSTERESIS = 0.3
Stages.LINE_MINUTES = 30
Stages.SLOW = { [2] = 0.95, [3] = 0.85, [4] = 0.75 }
Stages.THIRST = { [2] = 1.25, [3] = 1.5, [4] = 2.0 }

local T = "UI_EHR_Temp_"
Stages.LINES = {
    cold = {
        { T .. "Chilly1", T .. "Chilly2" }, { T .. "Cold1", T .. "Cold2" },
        { T .. "VeryCold1", T .. "VeryCold2" }, { T .. "Freezing1", T .. "Freezing2" },
    },
    hot = {
        { T .. "Warm1", T .. "Warm2" }, { T .. "Hot1", T .. "Hot2" },
        { T .. "VeryHot1", T .. "VeryHot2" }, { T .. "Overheating1", T .. "Overheating2" },
    },
}

function Stages.enabled(p)
    return Temperature.enabled(p) and p.sandbox("PreDiseaseEffectsEnabled", true) ~= false
end

-- The next stage from the current one: one step deeper past the next threshold, one step back past the current
-- threshold plus the hysteresis.
function Stages.next(stage, body, thresholds, cold)
    local deeper, current = thresholds[stage + 1], thresholds[stage]
    if cold then
        if deeper and body < deeper then
            return stage + 1
        elseif current and body > current + Stages.HYSTERESIS then
            return stage - 1
        end
    else
        if deeper and body > deeper then
            return stage + 1
        elseif current and body < current - Stages.HYSTERESIS then
            return stage - 1
        end
    end
    return stage
end

local function speak(p, t, dt)
    t.lineIn = (t.lineIn or 0) - dt
    if t.lineIn > 0 or p.facts.asleep then
        return
    end
    local kind, stage = "cold", t.cold
    if stage == 0 then
        kind, stage = "hot", t.hot
    end
    if stage > 0 then
        Speech.stage(p, Speech.pick(p, Stages.LINES[kind][stage]))
        t.lineIn = Stages.LINE_MINUTES
    end
end

-- Very hot: thirst rises faster. The extra is a share of how much thirst rose since our last write.
local function thirst(p, t)
    local now = p.facts.stats and p.facts.stats.THIRST
    local mult = Stages.THIRST[t.hot]
    local add = 0
    if mult and now and t.lastThirst and now > t.lastThirst and not p.fresh then
        add = (now - t.lastThirst) * (mult - 1)
        p.stats:add("THIRST", "heatStage", add)
    end
    t.lastThirst = now and (now + add) or false
end

function Stages.update(p, dt)
    local t = p.state.temperature
    if not Stages.enabled(p) then
        if t.cold ~= 0 or t.hot ~= 0 then
            t.cold, t.hot = 0, 0
            p.dirty("temperature")
        end
        t.lastThirst = false
        return
    end
    local body = p.facts.stats and p.facts.stats.TEMPERATURE or Temperature.NORMAL
    local cold = Stages.next(t.cold, body, Stages.COLD, true)
    local hot = Stages.next(t.hot, t.fever and Temperature.NORMAL or body, Stages.HOT, false)
    if cold ~= t.cold or hot ~= t.hot then
        t.cold, t.hot = cold, hot
        p.dirty("temperature")
    end
    speak(p, t, dt)
    if Stages.SLOW[t.cold] then
        p.fx:speed("coldStage", Stages.SLOW[t.cold])
    end
    thirst(p, t)
end

Stages.system = { name = "temperatureStages", order = 795, update = function(p, dt) Stages.update(p, dt) end }

return Stages
