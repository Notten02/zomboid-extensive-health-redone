-- Heat exhaustion (W9): the guide's 4 stages, driven by the heat exposure meter (a driven condition, no timers).
-- Stage 1 hot and thirsty, stage 2 leg cramps and a slowdown, stage 3 dizziness, nausea and no sprint (heat stroke
-- rolls run alongside, Diseases/Weather/Exposure), stage 4 recovery while the meter falls; it ends when the meter is
-- below 10%. v0.9 had only the meter; the stage thresholds and effects are ours (Data.heat, Data.heatExhaustion).
--
-- Treatment (Phase 5, through p.treatment): relief only: water, Electrolyte Powder and Oral Rehydration Kit
-- ("dehydration"). Cooling down is the cure.

local Data = require "ExtensiveHealthRedone/Diseases/Weather/Data"
local Meters = require "ExtensiveHealthRedone/Diseases/Weather/Meters"
local Episodes = require "ExtensiveHealthRedone/Diseases/Weather/Episodes"
local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Speech = require "ExtensiveHealthRedone/Core/Speech"

local D = Data.heatExhaustion
local H = Data.heat

local HeatExhaustion = {
    enabledOption = "HeatExhaustionEnabled", speedOption = "DiseaseSpeed",
    driven = true,
    knowledge = "heat_exhaustion",
    selfEvident = true,
    name = "UI_EHR_Disease_heat_exhaustion",
    lines = {
        stage = {
            [1] = "UI_EHR_Text_GettingReallyHotSweatingBuckets",
            [2] = "UI_EHR_Text_CrampsOwMyLeg",
            [3] = "UI_EHR_Text_DizzyEverythingsSpinningCantTakeThisHeat",
            [4] = "UI_EHR_Text_FeelingCooler",
        },
        random = {
            [1] = { "UI_EHR_Text_ItsSoHot", "UI_EHR_Text_HeavySweating", "UI_EHR_Text_SoThirsty",
                "UI_EHR_Text_SweatingThroughMyClothes" },
            [2] = { "UI_EHR_Text_CrampsOwMyLeg", "UI_EHR_Text_PantingImOverheatingNeedWaterAndShade",
                "UI_EHR_Text_HeavySweating" },
            [3] = { "UI_EHR_Text_GettingLightheadedFromTheHeat", "UI_EHR_Text_ThisIsBadHeatStrokeComing",
                "UI_EHR_Text_ImGettingDizzy" },
            [4] = { "UI_EHR_Text_CoolingDownNow", "UI_EHR_Text_StopsSweating" },
        },
        every = 168,
    },
}

-- The stage for a meter share (0 = below stage 1) while the meter is not falling.
function HeatExhaustion.band(ratio)
    for stage = 3, 1, -1 do
        if ratio >= H.EXHAUSTION[stage] then
            return stage
        end
    end
    return 0
end

function HeatExhaustion.drive(p, c)
    local ratio = Meters.heatRatio(p)
    if not Engine.enabled(p, HeatExhaustion) or ratio < H.EXHAUSTION_END then
        return "recovered"
    end
    if Meters.weather(p).heatFalling >= H.FALLING_MINUTES then
        return 4
    end
    local band = HeatExhaustion.band(ratio)
    if band == 0 then
        return c.stage == 4 and 4 or 1
    end
    return band
end

-- Trigger: called by the exposure system after the heat meter moved.
function HeatExhaustion.check(p, defs)
    if p.state.conditions.active.heat_exhaustion then
        return
    end
    local band = HeatExhaustion.band(Meters.heatRatio(p))
    if band > 0 and Engine.contract(p, defs, "heat_exhaustion", { stage = band, source = "heat" }) then
        Speech.stage(p, HeatExhaustion.lines.stage[band])
    end
end

local DIZZY = { "UI_EHR_Text_ImGettingDizzy", "UI_EHR_Text_GettingLightheadedFromTheHeat" }

function HeatExhaustion.effects(p, c, dt)
    local row = D[c.stage]
    local hydrated = 1 - p.treatment:relief("heat_exhaustion", "dehydration")
    p.stats:addF("THIRST", "heat_exhaustion", row.thirst * dt * hydrated)
    if row.cramps then
        for _, part in ipairs(D.CRAMP_PARTS) do
            p.body:pain(part, "heat_exhaustion", row.cramps)
        end
    end
    if row.speed then
        p.fx:speed("heat_exhaustion", row.speed)
    end
    if row.noSprint then
        p.fx:noSprint("heat_exhaustion")
    end
    if row.nausea then
        p.stats:raiseF("SICKNESS", "heat_exhaustion", row.nausea, 0.01 * dt)
    end
    if row.dizzy then
        Episodes.dizzy(p, c, 0.05, dt, DIZZY, 15)
    end
    Episodes.blur(p, c, "heat_exhaustion", dt)
end

return HeatExhaustion
