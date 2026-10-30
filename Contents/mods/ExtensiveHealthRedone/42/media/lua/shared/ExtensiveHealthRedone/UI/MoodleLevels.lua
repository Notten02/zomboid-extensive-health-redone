-- The levels (0 hidden, 1-4) of EHR's five moodles, from the client's mirrored state. Pure; Client/Moodles shows them
-- through MoodleFramework:
--   Medical Alert  the worst of: each active condition's stage (sepsis one higher), the worst infected wound's
--                  stage, side effects (1 for one, 2 for several). Knox counts only once symptomatic (stage 2+) and at
--                  its stage, so the alert never reveals a fresh bite.
--                  Conditions defined with alert = false never count (add-on conditions, Conditions/Registration).
--   Corpse         the corpse meter: 1 low, 2 medium (Exposure bands), 3 from the hourly risk, 4 when certain
--   Cadaveric      the spore meter: 1 from 1, 2 from 72, 3 from 102, 4 at 120 (certain); hidden once the disease runs
--   Heat           the heat meter share: 1 from 5 %, 2 from 50 %, 3 from 85 %; 4 while heat stroke runs
--   Cold           the cold meter: 1 from 5, 2 from 50, 3 from 85; hidden while a cold or pneumonia runs
--
--   MoodleLevels.compute(sections) -> { [moodle id] = { level, title = key, desc = Text } } for every id in ORDER
--   sections: the mirrored conditions, wounds, meds and exposure sections (any may be nil before the first sync)

local Text = require "ExtensiveHealthRedone/UI/Text"
local Exposure = require "ExtensiveHealthRedone/Diseases/Corpse/Exposure"
local defs = require "ExtensiveHealthRedone/Conditions/Registry"

local MoodleLevels = {}

MoodleLevels.ORDER = { "medical", "corpse", "cadaveric", "heat", "cold" }

MoodleLevels.TITLES = {
    medical = "UI_EHR_Moodle_MedicalAlert_Title",
    corpse = "UI_EHR_CorpseExposure",
    cadaveric = "UI_EHR_CadavericAspergillosisExposure",
    heat = "UI_EHR_Moodle_HeatExposure_Title",
    cold = "UI_EHR_Moodle_ColdRisk_Title",
}

MoodleLevels.KNOX = "knox_infection"
MoodleLevels.KNOX_FROM_STAGE = 2
MoodleLevels.SPORES = { 1, 72, 102, Exposure.SPORES.GUARANTEED }
MoodleLevels.SHARE = { 5, 50, 85 }      -- heat (share of a full meter, %) and cold (share of "ready", %)

local EXPOSURE_WORDS = { "UI_EHR_ExposureLevel_Low", "UI_EHR_ExposureLevel_Medium", "UI_EHR_ExposureLevel_High",
    "UI_EHR_ExposureLevel_High" }

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do
        n = n + 1
    end
    return n
end

-- The highest step index whose threshold value reaches.
local function steps(value, thresholds)
    local level = 0
    for i, from in ipairs(thresholds) do
        if value >= from then
            level = i
        end
    end
    return level
end

function MoodleLevels.medical(conditions, wounds, meds)
    local level, diseases = 0, 0
    for id, c in pairs(conditions and conditions.active or {}) do
        local stage = tonumber(c.stage) or 1
        local silent = defs[id] ~= nil and defs[id].alert == false
        if not silent and (id ~= MoodleLevels.KNOX or stage >= MoodleLevels.KNOX_FROM_STAGE) then
            diseases = diseases + 1
            level = math.max(level, id == "sepsis" and stage + 1 or stage)
        end
    end
    for _, e in pairs(wounds and wounds.parts or {}) do
        if e.phase == "infected" then
            diseases = diseases + 1
            level = math.max(level, tonumber(e.stage) or 1)
        end
    end
    local side = count(meds and meds.side)
    local sideLevel = side > 1 and 2 or side
    level = math.max(1, math.min(4, math.max(level, sideLevel)))
    if diseases == 0 and side == 0 then
        return 0, nil
    end
    local desc = "UI_EHR_Moodle_MedicalAlert_Desc"
    if diseases > 1 then
        desc = "UI_EHR_Moodle_MedicalAlert_Multiple"
    elseif diseases == 0 then
        desc = "UI_EHR_Moodle_MedicalAlert_SideEffects"
    end
    return level, Text.key(desc)
end

local function active(conditions, id)
    return conditions ~= nil and conditions.active ~= nil and conditions.active[id] ~= nil
end

function MoodleLevels.corpse(value)
    local C = Exposure.CORPSE
    if value >= C.GUARANTEED then
        return 4
    elseif value >= C.RISK then
        return 3
    end
    local band = Exposure.band(value)
    return band == "medium" and 2 or band == "low" and 1 or 0
end

function MoodleLevels.compute(sections)
    sections = sections or {}
    local conditions, exposure = sections.conditions, sections.exposure or {}
    local out = {}
    local level, desc = MoodleLevels.medical(conditions, sections.wounds, sections.meds)
    out.medical = { level = level, desc = desc }

    local levels = {
        corpse = MoodleLevels.corpse(tonumber(exposure.corpse) or 0),
        cadaveric = 0,
        heat = steps(tonumber(exposure.heat) or 0, MoodleLevels.SHARE),
        cold = 0,
    }
    if not active(conditions, "cadaveric_aspergillosis") then
        levels.cadaveric = steps(tonumber(exposure.spores) or 0, MoodleLevels.SPORES)
    end
    if active(conditions, "heat_stroke") then
        levels.heat = 4
    end
    if not (active(conditions, "common_cold") or active(conditions, "pneumonia")) then
        levels.cold = steps(tonumber(exposure.cold) or 0, MoodleLevels.SHARE)
    end
    for id, l in pairs(levels) do
        out[id] = { level = l,
            desc = l > 0 and Text.key("UI_EHR_Moodle_ExposureLevel_Desc", Text.key(EXPOSURE_WORDS[l])) or nil }
    end
    for _, id in ipairs(MoodleLevels.ORDER) do
        out[id].title = MoodleLevels.TITLES[id]
    end
    return out
end

return MoodleLevels
