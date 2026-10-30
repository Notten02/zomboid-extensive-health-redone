-- The Immune System tab's view model, from the mirrored state.immunity and the sandbox options. Pure.
-- It shows "awaiting data" until the first update, pressure rows for immunosuppression and the Phalanx
-- debuff, as many pressure rows as fit (the view decides), and "Monitoring only" whenever no chance is changed.
--
--   Immune.build(state.immunity, sandbox) -> model, or nil while there is nothing to show yet

local Text = require "ExtensiveHealthRedone/UI/Text"
local Data = require "ExtensiveHealthRedone/Data/Immunity"
local Immunity = require "ExtensiveHealthRedone/Immunity/Immunity"
local Risk = require "ExtensiveHealthRedone/Conditions/Risk"

local Immune = {}

local FACTOR_KEYS = {
    nutrition = "UI_EHR_Immunity_Factor_Nutrition",
    hydration = "UI_EHR_Immunity_Factor_Hydration",
    rest = "UI_EHR_Immunity_Factor_Rest",
    stressControl = "UI_EHR_Immunity_Factor_StressControl",
    bloodCondition = "UI_EHR_Immunity_Factor_BloodCondition",
    healthReserve = "UI_EHR_Immunity_Factor_HealthReserve",
}

local TREND_KEYS = {
    recovering = "UI_EHR_Immunity_Trend_Recovering",
    declining = "UI_EHR_Immunity_Trend_Declining",
    stable = "UI_EHR_Immunity_Trend_Stable",
    disabled = "UI_EHR_Immunity_Disabled",
}

-- A factor below this counts as a pressure.
Immune.WEAK_FACTOR = 50

-- Band colour of a 0-100 value.
function Immune.color(value)
    value = tonumber(value) or 0
    if value >= 80 then
        return "green"
    elseif value >= 60 then
        return "blue"
    elseif value >= 40 then
        return "yellow"
    elseif value >= 20 then
        return "orange"
    end
    return "red"
end

-- The tab exists only while the system is on.
function Immune.visible(sandbox)
    return sandbox("ImmunitySystemEnabled", true) ~= false
end

local function round(v)
    return math.floor((tonumber(v) or 0) + 0.5)
end

-- "Label: value" (the immunity keys are bare labels).
local function labelled(key, value)
    return Text.key("UI_EHR_LabelValue", Text.key(key), value)
end

-- The infection-risk line: the sensitivity-1 curve at the current strength, or "not applied".
local function risk(score, strength)
    if strength <= 0 then
        return labelled("UI_EHR_Immunity_InfectionRisk", Text.key("UI_EHR_Immunity_NotApplied")), "dim"
    end
    local pct = math.floor(((Risk.multiplier(score, 1, strength) - 1) * 100) * 10 + 0.5) / 10
    local text = (pct > 0 and "+" or "") .. string.format("%.1f%%", pct)
    local color = pct > 0.05 and "orange" or (pct < -0.05 and "green" or "dim")
    return labelled("UI_EHR_Immunity_InfectionRisk", Text.raw(text)), color
end

-- Priority pressures first (suppression, Phalanx), then weak factors, lowest first.
local function pressures(im)
    local rows = {}
    local p = im.pressures or {}
    if p.antibiotic then
        rows[#rows + 1] = { label = Text.key("UI_EHR_Immunity_AntibioticPressure"), value = Text.percent(Data.SUPPRESSED_CAP),
            color = Immune.color(Data.SUPPRESSED_CAP) }
    end
    if p.immunosuppression then
        rows[#rows + 1] = { label = Text.key("UI_SideEffect_Immunosuppression"),
            value = Text.percent(Data.SUPPRESSED_CAP), color = Immune.color(Data.SUPPRESSED_CAP) }
    end
    if p.phalanx then
        rows[#rows + 1] = { label = Text.key("UI_EHR_Immunity_PhalanxPressure"),
            value = Text.raw("-" .. tostring(round(p.phalanx))), color = "red" }
    end
    local weak = {}
    for _, id in ipairs(Data.FACTOR_ORDER) do
        local v = im.factors and im.factors[id]
        if v and v < Immune.WEAK_FACTOR then
            weak[#weak + 1] = { id = id, v = v }
        end
    end
    table.sort(weak, function(a, b)
        if a.v ~= b.v then
            return a.v < b.v
        end
        return a.id < b.id
    end)
    for _, w in ipairs(weak) do
        rows[#rows + 1] = { label = Text.key(FACTOR_KEYS[w.id]), value = Text.percent(w.v), color = Immune.color(w.v) }
    end
    return rows
end

function Immune.build(im, sandbox)
    if type(im) ~= "table" or im.score == nil then
        return nil
    end
    local strength = Risk.strength({ sandbox = sandbox })
    local model = {
        awaiting = im.target == false or im.target == nil,
        score = im.score,
        scoreText = Text.percent(im.score),
        color = Immune.color(im.score),
        band = Text.key("UI_EHR_Immunity_Status_" .. Immunity.band(im.score)),
        active = strength > 0,
        state = Text.key(strength > 0 and "UI_EHR_Immunity_GameplayActive" or "UI_EHR_Immunity_MonitoringOnly"),
    }
    if model.awaiting then
        return model
    end
    model.target = im.target
    model.targetText = labelled("UI_EHR_Immunity_Target", Text.percent(im.target))
    model.trend = labelled("UI_EHR_Immunity_Trend", Text.key(TREND_KEYS[im.trend] or TREND_KEYS.stable))
    model.risk, model.riskColor = risk(im.score, strength)
    model.factors = {}
    for _, id in ipairs(Data.FACTOR_ORDER) do
        local v = im.factors and im.factors[id] or 0
        model.factors[#model.factors + 1] = { id = id, label = Text.key(FACTOR_KEYS[id]), value = v,
            valueText = Text.percent(v), color = Immune.color(v) }
    end
    local h = im.hygiene or {}
    model.dirtiness = { value = h.dirtiness or 0, text = Text.percent(h.dirtiness), color = Immune.color(100 - (h.dirtiness or 0)) }
    model.bloodiness = { value = h.bloodiness or 0, text = Text.percent(h.bloodiness),
        color = Immune.color(100 - (h.bloodiness or 0)) }
    local penalty = round(h.penalty)
    model.penalty = labelled("UI_EHR_Immunity_HygienePenalty", Text.raw("-" .. penalty))
    model.penaltyColor = penalty >= 25 and "red" or (penalty >= 10 and "orange" or (penalty > 0 and "yellow" or "green"))
    model.pressures = pressures(im)
    return model
end

return Immune
