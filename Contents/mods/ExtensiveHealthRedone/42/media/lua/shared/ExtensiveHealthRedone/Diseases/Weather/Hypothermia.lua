-- Hypothermia: follows body temperature, with no roll and no timer (a driven condition). Stage 1-4 at or below the
-- HypothermiaStage1..4Temp options; warming steps back one stage at a time with 0.25 deg C of slack, and it clears
-- above HypothermiaClearTemp. Slowdown, no sprint from stage 2, an endurance cap, fatigue, a health drain from stage 2,
-- confusion, dizziness and (stage 4) collapse. Warmth is the only treatment (no medicine).
--
-- Body temperature is vanilla's CharacterStat.TEMPERATURE (deg C), bounded by Body/Temperature;
-- BodyTemperatureEnabled=false turns hypothermia off.

local Data = require "ExtensiveHealthRedone/Diseases/Weather/Data"
local Episodes = require "ExtensiveHealthRedone/Diseases/Weather/Episodes"
local Speech = require "ExtensiveHealthRedone/Core/Speech"
local Chance = require "ExtensiveHealthRedone/Core/Chance"
local Engine = require "ExtensiveHealthRedone/Conditions/Engine"

local D = Data.hypothermia
local K = Data.PER_MINUTE

local CONFUSED = { "UI_EHR_Weather_StumblesWhereAmI", "UI_EHR_Weather_ConfusedWhatWasIDoing",
    "UI_EHR_Weather_DisorientedCantThinkStraight" }
local DIZZY = { "UI_EHR_Text_DizzyWorldsSpinning", "UI_EHR_Weather_Stumbles", "UI_EHR_Weather_SwaysCantFocus" }
local COLLAPSE = { "UI_EHR_Weather_SlurredCantStayAwake", "UI_EHR_Weather_CollapsesSoCold",
    "UI_EHR_Weather_DazedEverythingIsFading", "UI_EHR_Weather_MumblesNeedWarmth" }

-- Spoken only when the stage gets worse; warming steps back quietly.
local STAGE_LINES = {
    [1] = "UI_EHR_Text_SSoColdCantStopShivering",
    [2] = "UI_EHR_Text_ICCantFeelMyFingersNeedWarmth",
    [3] = "UI_EHR_Text_EverythingsGettingFuzzySoTired",
    [4] = "EHR_Dialogue_Hypothermia_S4_Novice_1",
}

local Hypothermia = {
    enabledOption = "HypothermiaEnabled",
    driven = true,
    knowledge = "hypothermia",
    selfEvident = true,
    name = "UI_EHR_Disease_hypothermia",
    lines = {
        random = {
            [1] = { "UI_EHR_Text_Shivers", "UI_EHR_Text_SoCold", "UI_EHR_Text_NeedToFindShelter" },
            [2] = { "UI_EHR_Text_TeethChattering", "UI_EHR_Text_CantStopShaking", "UI_EHR_Text_ShiversViolently",
                "UI_EHR_Text_NeedFireWarmth" },
            [3] = { "UI_EHR_Text_SlurredSoSleepy", "UI_EHR_Text_ConfusedWhereAmI", "UI_EHR_Text_MumblesIncoherently",
                "UI_EHR_Text_JustWantToRest" },
            [4] = { "EHR_Dialogue_Hypothermia_S4_Novice_1", "EHR_Dialogue_Hypothermia_S3_Clueless_1",
                "EHR_Dialogue_Hypothermia_S4_Inter_1" },
        },
        every = 168,
        -- No shivering talk while warming up at a heat source
        quiet = function(p)
            return p.facts.weather ~= nil and p.facts.weather.nearHeat == true
        end,
    },
}

-- Sandbox thresholds, each stage at least 0.1 deg C below the previous, the clear temperature at least stage 1's.
function Hypothermia.thresholds(p)
    local t = {
        tonumber(p.sandbox("HypothermiaStage1Temp", 35.0)) or 35.0,
        tonumber(p.sandbox("HypothermiaStage2Temp", 34.0)) or 34.0,
        tonumber(p.sandbox("HypothermiaStage3Temp", 32.0)) or 32.0,
        tonumber(p.sandbox("HypothermiaStage4Temp", 31.0)) or 31.0,
    }
    for i = 2, 4 do
        t[i] = math.min(t[i], t[i - 1] - D.MIN_GAP)
    end
    t.clear = math.max(tonumber(p.sandbox("HypothermiaClearTemp", 35.5)) or 35.5, t[1])
    return t
end

-- The stage for a body temperature (0 = none). current: the stage now (0 when not hypothermic), for the slack.
function Hypothermia.stageFor(p, temp, current)
    local t = Hypothermia.thresholds(p)
    local stage = 0
    for i = 4, 1, -1 do
        if temp <= t[i] then
            stage = i
            break
        end
    end
    -- Warming: hold the current stage within 0.25 deg C above its threshold, and stage 1 until the clear temperature.
    if current >= 2 and stage < current and temp <= t[current] + D.HYSTERESIS then
        stage = current
    end
    if current >= 1 and stage == 0 and temp <= t.clear then
        stage = 1
    end
    return stage
end

function Hypothermia.temperature(p)
    local temp = p.facts.stats and p.facts.stats.TEMPERATURE
    if type(temp) ~= "number" or temp < D.PLAUSIBLE_MIN_C then
        return nil
    end
    return temp
end

local function active(p)
    return p.sandbox("BodyTemperatureEnabled", true) ~= false and Engine.enabled(p, Hypothermia)
end

-- Engine drive: the stage from body temperature, or "recovered".
function Hypothermia.drive(p, c)
    local temp = Hypothermia.temperature(p)
    if not active(p) or not temp then
        return "recovered"
    end
    local stage = Hypothermia.stageFor(p, temp, c.stage)
    if stage == 0 then
        return "recovered"
    end
    return stage
end

function Hypothermia.onStage(p, c, stage)
    if stage > (c.data.prev or 0) then
        Speech.stage(p, STAGE_LINES[stage])
    end
    c.data.prev = stage
end

-- Trigger: called by the exposure system each step. Starts hypothermia at the stage the temperature is in.
function Hypothermia.check(p, defs)
    if p.state.conditions.active.hypothermia or not active(p) then
        return
    end
    local temp = Hypothermia.temperature(p)
    local stage = temp and Hypothermia.stageFor(p, temp, 0) or 0
    if stage > 0 then
        local c = Engine.contract(p, defs, "hypothermia", { stage = stage, source = "cold" })
        if c then
            Hypothermia.onStage(p, c, stage)
        end
    end
end

function Hypothermia.effects(p, c, dt)
    local row = D[c.stage]
    local weak = 1 - p.treatment:relief("hypothermia", "weakness")
    p.fx:speed("hypothermia", row.speed)
    if row.noSprint then
        p.fx:noSprint("hypothermia")
    end
    p.stats:ceilingF("ENDURANCE", "hypothermia", row.endurance + (1 - row.endurance) * (1 - weak))
    p.stats:raiseF("FATIGUE", "hypothermia", row.fatigue, row.fatigueStep * K * dt)
    if row.drain then
        p.body:damage("hypothermia", row.drain / 60 * dt * weak, 0)
    end
    Episodes.blur(p, c, "hypothermia", dt)
    if row.confusion then
        Episodes.confused(p, c, row.confusion, dt, CONFUSED, c.stage == 4 and 7 or 13)
    end
    if row.dizziness then
        Episodes.dizzy(p, c, row.dizziness, dt, DIZZY, 11)
    end
    Episodes.collapseCooldown(p, c, dt)
    if row.blackout then
        Episodes.collapse(p, c, Chance.over(row.blackout, K, dt), D.BLACKOUT_COOLDOWN, COLLAPSE)
    end
end

function Hypothermia.onEnd(p, c, reason)
    if reason == "recovered" then
        Speech.stage(p, "UI_EHR_Text_StopsShivering")
    end
end

return Hypothermia
