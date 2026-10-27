-- The EHR Monitor's view model: what the tab shows, from the mirrored state and what the reader knows. Pure, so the
-- tests check it and the Phase 9 exam can build the same view of another player with the doctor's knowledge.
-- Spec: docs/porting/phase7/monitor-panel.md section 2; maintainer decisions in docs/parity-checklist.md section 14
-- ("Decided in Phase 7").
--
--   Monitor.build({
--       state = { identity, knowledge, blood, body, wounds, conditions, exposure, meds, knox },   -- mirror sections
--       firstAid = 0-10, defs = Conditions/Registry, sandbox = function(name, default),
--       watch = true when a powered Medical Monitor Watch is worn,
--       bodyC = deg C, airC = deg C or nil (Indoor Climate Lite's room air), parts = { [part] = facts },
--   })
--
-- Text is UI/Text; colours are Client/Draw colour names.

local Text = require "ExtensiveHealthRedone/UI/Text"
local BodyStatus = require "ExtensiveHealthRedone/UI/BodyStatus"
local DiseaseInfo = require "ExtensiveHealthRedone/Data/DiseaseInfo"
local BodyParts = require "ExtensiveHealthRedone/Data/BodyParts"
local BloodData = require "ExtensiveHealthRedone/Data/Blood"
local WoundData = require("ExtensiveHealthRedone/Data/Wounds").infection
local Knowledge = require "ExtensiveHealthRedone/Conditions/Knowledge"
local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Exposure = require "ExtensiveHealthRedone/Diseases/Corpse/Exposure"
local MedData = require "ExtensiveHealthRedone/Medication/Data"
local Doses = require "ExtensiveHealthRedone/Medication/Doses"
local SideEffects = require "ExtensiveHealthRedone/Medication/SideEffects"
local Interactions = require "ExtensiveHealthRedone/Medication/Interactions"
local Tables = require "ExtensiveHealthRedone/Core/Tables"

local Monitor = {}

Monitor.TIERS = {
    [0] = "UI_EHR_MedAction_Tier_Basic",
    [1] = "UI_EHR_MedAction_Tier_OTC",
    [2] = "UI_EHR_MedAction_Tier_Prescription",
    [3] = "UI_EHR_MedAction_Tier_Clinical",
}

-- Saline share of the circulating blood (legacy monitor, W23): the lethal and warning shares are Data/Blood's, with
-- "danger" half way between.
Monitor.SALINE = {
    { from = BloodData.DILUTION_LETHAL, key = "UI_EHR_SalineStatus_Lethal", color = "red" },
    { from = (BloodData.DILUTION_WARNING + BloodData.DILUTION_LETHAL) / 2, key = "UI_EHR_SalineStatus_Danger",
        color = "orange" },
    { from = BloodData.DILUTION_WARNING, key = "UI_EHR_SalineStatus_Warning", color = "yellow" },
    { from = 0, key = "UI_EHR_SalineStatus_Safe", color = "blue" },
}

-- The blood bag drawn beside the bar: empty at or below this share.
Monitor.EMPTY_BAG = 12

-- Exposure meters shown as rows (any First Aid level). value(state) -> current, max; hiddenBy: an active condition
-- that replaces the row. Bands are the meter values for low, medium and high.
Monitor.EXPOSURE = {
    { id = "corpse", name = "UI_EHR_CorpseExposure", icon = "EHR_Disease_CorpseSickness", max = 100,
        band = function(v) return Exposure.band(v) end },
    { id = "spores", name = "UI_EHR_CadavericAspergillosisExposure", icon = "EHR_Disease_CadavericAspergillosis",
        max = Exposure.SPORES.GUARANTEED, low = 1, medium = 72, high = 102, hiddenBy = { "cadaveric_aspergillosis" } },
    { id = "heat", name = "UI_EHR_Moodle_HeatExposure_Title", icon = "EHR_Disease_HeatExhaustion", max = 100,
        low = 5, medium = 50, high = 85, hiddenBy = { "heat_stroke" } },
    { id = "cold", name = "UI_EHR_Moodle_ColdRisk_Title", icon = "EHR_Disease_CommonCold", max = 100,
        low = 5, medium = 50, high = 85, hiddenBy = { "common_cold", "pneumonia" } },
}

-- How hard a case hits, as a word beside the stage: severity (baseSeverity +- 0.15, Conditions/Engine) scales the
-- symptoms. No number, so the reader gets a hint rather than the scale. Bands from the highest.
Monitor.SEVERITY = {
    { from = 0.85, key = "UI_EHR_SeverityLevel_Severe" },
    { from = 0.55, key = "UI_EHR_SeverityLevel_Moderate" },
    { from = 0, key = "UI_EHR_SeverityLevel_Mild" },
}

-- The severity word, or nil for a condition whose symptoms don't scale with it (no baseSeverity, or severityHidden).
function Monitor.severityLevel(c, def)
    local sev = tonumber(c.severity)
    if not sev or def.baseSeverity == nil or def.severityHidden then
        return nil
    end
    for _, band in ipairs(Monitor.SEVERITY) do
        if sev >= band.from then
            return band.key
        end
    end
end

local LEVEL_COLOR = { low = "yellow", medium = "orange", high = "red" }
local LEVEL_KEY = { low = "UI_EHR_ExposureLevel_Low", medium = "UI_EHR_ExposureLevel_Medium",
    high = "UI_EHR_ExposureLevel_High" }

-- Knox side effects shown with the medication side effects (W33): effect -> label key.
Monitor.KNOX_EFFECTS = {
    phalanxNausea = "UI_EHR_KnoxEffect_PhalanxNausea",
    phalanxFever = "UI_EHR_KnoxEffect_PhalanxFever",
    phalanxDebuff = "UI_EHR_KnoxEffect_PhalanxDebuff",
}
Monitor.BOOSTER_EFFECTS = { "UI_EHR_KnoxEffect_BoosterNausea", "UI_EHR_KnoxEffect_BoosterStamina",
    "UI_EHR_KnoxEffect_BoosterTremors" }

local function clamp01(v)
    return math.max(0, math.min(1, v))
end

-- Blood ---------------------------------------------------------------------------------------------------------------

local function bagIcon(bloodType, percent)
    if percent <= Monitor.EMPTY_BAG then
        return "Item_BloodBagEmpty"
    end
    if not bloodType then
        return "Item_BloodBag"
    end
    return "Item_BloodBag" .. bloodType:gsub("%+", "Pos"):gsub("%-", "Neg")
end

local function blood(input)
    local b = input.state.blood or {}
    local max = tonumber(b.max) or BloodData.MAX_ML
    local volume = math.max(0, math.min(max, tonumber(b.volume) or max))
    local percent = max > 0 and volume / max * 100 or 0
    local saline = tonumber(b.saline) or 0
    local share = volume > 0 and saline / volume or 0
    local status
    for _, s in ipairs(Monitor.SALINE) do
        if share >= s.from then
            status = s
            break
        end
    end
    local visible = input.watch == true or input.sandbox("MedicalWatchRequired", true) == false
    return {
        visible = visible,
        percent = percent,
        ml = math.floor(volume + 0.5),
        max = math.floor(max + 0.5),
        saline = math.floor(saline + 0.5),
        salineShare = clamp01(share),
        salineText = Text.key("UI_EHR_SalineLine", math.floor(saline + 0.5), Text.percent(share * 100)),
        salineStatus = Text.key(status.key),
        salineColor = status.color,
        bag = bagIcon(input.state.identity and input.state.identity.bloodType, percent),
    }
end

-- Conditions ------------------------------------------------------------------------------------------------------------

-- Share of the whole illness done, from the stage and the time left in it; nil when there are no timers.
function Monitor.progress(c, def)
    if def.driven then
        return nil
    end
    local len = Engine.stageMinutes(c, c.stage)
    local within = len > 0 and clamp01(1 - (c.left or 0) / len) or 1
    if def.reverse then
        local start = def.startStage or 4
        return clamp01(((start - c.stage) + within) / start)
    end
    return clamp01(((c.stage - 1) + within) / 4)
end

-- A row the reader may or may not recognise. known = Conditions/Knowledge.of(...).
local function conditionRow(id, def, known)
    local row = { id = id, known = known.name, icon = known.name and DiseaseInfo.icon(id) or DiseaseInfo.UNKNOWN_ICON }
    if known.name then
        row.name = Text.key(def.name)
    else
        local name, desc = DiseaseInfo.unknownKeys(id)
        row.name = Text.key(name)
        row.description = Text.key(desc)
        row.descriptionColor = "dim"
    end
    return row
end

local function stageDetail(row, id, c, known, def)
    if not known.stage then
        row.detail = Text.key("UI_EHR_StageUnknown")
        row.detailColor = "dim"
        return
    end
    row.detailColor = "green"
    local level = def and Monitor.severityLevel(c, def)
    if id == "concussion" then
        row.detail = Text.key("UI_EHR_DiseaseDetail_StageTimeRest", c.stage)
    elseif level then
        row.detail = Text.key("UI_EHR_StageSeverityLevel", c.stage, Text.key(level))
    else
        row.detail = Text.key("UI_EHR_StageNumber", c.stage)
    end
end

local function knoxTreated(state)
    local knox = state.knox or {}
    if (knox.boosterLeft or 0) > 0 then
        return true
    end
    for _, minutes in pairs(knox.effects or {}) do
        if type(minutes) == "number" and minutes > 0 then
            return true
        end
    end
    return false
end

local function conditionRows(input, curing)
    local rows = {}
    local active = input.state.conditions and input.state.conditions.active or {}
    for _, id in ipairs(Tables.sortedKeys(active)) do
        local c, def = active[id], input.defs[id]
        if def then
            local known = Knowledge.of(input.state, def, input.firstAid)
            local row = conditionRow(id, def, known)
            stageDetail(row, id, c, known, def)
            if id == "delirium" and known.name then
                row.description = Text.key("UI_EHR_DeliriumCourseRequired")
                row.descriptionColor = "yellow"
            end
            local share
            if id == "knox_infection" then
                share = c.data and c.data.progress or nil
            else
                share = Monitor.progress(c, def)
            end
            if known.progress then
                row.progress = share
                row.progressText = share and Text.percent(share * 100) or nil
                if id == "knox_infection" then
                    if knoxTreated(input.state) then
                        row.status, row.statusColor = Text.key("UI_EHR_Status_Treating"), "green"
                    else
                        row.status, row.statusColor = Text.key("UI_EHR_Status_NoCure"), "red"
                    end
                elseif curing[id] then
                    row.status, row.statusColor = Text.key("UI_EHR_Status_Treating"), "green"
                elseif id == "concussion" then
                    row.status, row.statusColor = Text.key("UI_EHR_Status_Recovering"), "green"
                else
                    row.status, row.statusColor = Text.key("UI_EHR_Status_Untreated"), "orange"
                end
            else
                row.progressText = Text.raw("??%")
            end
            if id == "knox_infection" and known.name and c.stage >= 4 then
                row.description = Text.key("UI_EHR_KnoxNoCureDetail")
                row.descriptionColor = "red"
            end
            rows[#rows + 1] = row
        end
    end
    return rows
end

local function woundSpeed(sandbox)
    local s = tonumber(sandbox("WoundInfectionSpeed", 1.0)) or 1
    return math.max(0.1, math.min(10, s))
end

-- All infected parts as one row: the worst stage, and the count when more than one.
local function woundRow(input, curing)
    local parts = input.state.wounds and input.state.wounds.parts or {}
    local worst, count
    count = 0
    for _, name in ipairs(Tables.sortedKeys(parts)) do
        local e = parts[name]
        if e.phase == "infected" then
            count = count + 1
            if not worst or e.stage > worst.stage or (e.stage == worst.stage and e.left < worst.left) then
                worst = e
            end
        end
    end
    if not worst then
        return nil
    end
    local known = Knowledge.of(input.state, DiseaseInfo.WOUND_INFECTION, input.firstAid)
    local row = conditionRow("wound_infection", DiseaseInfo.WOUND_INFECTION, known)
    if known.name and count > 1 then
        row.name = Text.key("UI_EHR_WoundInfectionCount", Text.key(DiseaseInfo.WOUND_INFECTION.name), count)
    end
    stageDetail(row, "wound_infection", worst, known)
    if known.progress then
        local len = WoundData.STAGE_HOURS[worst.stage] * 60 / woundSpeed(input.sandbox)
        local share = clamp01(((worst.stage - 1) + clamp01(1 - worst.left / len)) / #WoundData.STAGE_HOURS)
        row.progress = share
        row.progressText = Text.percent(share * 100)
        if curing.woundInfection then
            row.status, row.statusColor = Text.key("UI_EHR_Status_Treating"), "green"
        else
            row.status, row.statusColor = Text.key("UI_EHR_Status_Untreated"), "orange"
        end
    else
        row.progressText = Text.raw("??%")
    end
    return row
end

local function exposureLevel(meter, value)
    if meter.band then
        local band = meter.band(value)
        return band ~= "none" and band or nil
    end
    if value >= meter.high then
        return "high"
    elseif value >= meter.medium then
        return "medium"
    elseif value >= meter.low then
        return "low"
    end
    return nil
end

local function exposureRows(input)
    local rows = {}
    local exposure = input.state.exposure or {}
    local active = input.state.conditions and input.state.conditions.active or {}
    for _, meter in ipairs(Monitor.EXPOSURE) do
        local hidden = false
        for _, id in ipairs(meter.hiddenBy or {}) do
            hidden = hidden or active[id] ~= nil
        end
        local value = tonumber(exposure[meter.id]) or 0
        local level = not hidden and exposureLevel(meter, value)
        if level then
            local share = clamp01(value / meter.max)
            rows[#rows + 1] = {
                id = meter.id .. "_exposure", exposure = true, known = true, icon = meter.icon,
                name = Text.key(meter.name),
                detail = Text.key("UI_EHR_ExposureLevelLine", Text.key(LEVEL_KEY[level])),
                detailColor = LEVEL_COLOR[level],
                progress = share, progressText = Text.percent(share * 100),
            }
        end
    end
    return rows
end

-- Medication ------------------------------------------------------------------------------------------------------------

local function minutes(hours)
    return (hours or 0) * 60
end

-- Minutes until a fully dosed course cures (the slowest of its uncured conditions), or nil.
local function cureLeft(med, course)
    local left
    for cond, hours in pairs(med.cures or {}) do
        if not course.cured[cond] then
            local m = math.max(0, minutes(hours) - course.elapsed)
            left = left and math.max(left, m) or m
        end
    end
    return left
end

local function medicationRow(state, med)
    local meds = state.meds
    local dose, course = meds.doses[med.id], meds.courses[med.id]
    local row = {
        id = med.id, item = med.fullType, name = Text.key(med.name),
        tier = Text.key(Monitor.TIERS[med.tier] or Monitor.TIERS[0]),
    }
    local fullyDosed = course and course.count >= med.doses
    local cure = course and fullyDosed and cureLeft(med, course)
    if cure then
        row.top = Text.key("UI_EHR_TimeToCureLine", Text.duration(cure))
        row.topColor = "dim"
        local total = 0
        for cond, hours in pairs(med.cures) do
            if not course.cured[cond] then
                total = math.max(total, minutes(hours))
            end
        end
        row.progress = total > 0 and clamp01(course.elapsed / total) or 1
    elseif Doses.isActive(state, med) then
        row.top = Text.key("UI_EHR_ActiveLine", Text.duration(minutes(med.active) - dose.since))
        row.topColor = "green"
        row.progress = clamp01(1 - dose.since / minutes(med.active))
    else
        row.top = Text.key("UI_EHR_GeneralEffect")
        row.topColor = "dim"
    end
    if course and MedData.isCourse(med) then
        row.doses = Text.key("UI_EHR_DoseCount", course.count, med.doses)
        if fullyDosed then
            row.schedule, row.scheduleColor = Text.key("UI_EHR_CourseComplete"), "green"
        else
            local late = dose and dose.since - minutes(med.interval) or 0
            if late > 0 then
                row.schedule = Text.key("UI_EHR_OverdueLine", Text.duration(late))
                row.scheduleColor = "red"
            else
                local wait = Doses.nextDoseIn(state, med) or 0
                row.schedule = Text.key("UI_EHR_NextDoseLine", Text.duration(wait))
                row.scheduleColor = wait <= 30 and "yellow" or "dim"
            end
            row.progress = clamp01(course.count / med.doses)
        end
    end
    return row
end

local function medicationRows(state)
    local rows = {}
    local meds = state.meds
    if not meds then
        return rows
    end
    local ids = {}
    for id in pairs(meds.courses) do
        ids[id] = true
    end
    for id in pairs(meds.doses) do
        local med = MedData.byId[id]
        if med and not med.silent and Doses.isActive(state, med) then
            ids[id] = true
        end
    end
    for _, id in ipairs(Tables.sortedKeys(ids)) do
        local med = MedData.byId[id]
        if med and med.name then
            rows[#rows + 1] = medicationRow(state, med)
        end
    end
    local knox = state.knox or {}
    if (knox.boosterLeft or 0) > 0 then
        rows[#rows + 1] = {
            id = "Immunobooster", item = "ExtensiveHealth.ImmunoboosterShot",
            name = Text.key("UI_EHR_KnoxCure_ImmunoboosterTitle"), tier = Text.key("Tooltip_EHR_Tier_Experimental"),
            top = Text.key("UI_EHR_ProtectionLine", Text.duration(knox.boosterLeft)), topColor = "green",
            progress = clamp01(knox.boosterLeft / (24 * 60)),
        }
    end
    return rows
end

local function sideEffectRows(state)
    local rows = {}
    local side = state.meds and state.meds.side or {}
    for _, id in ipairs(Tables.sortedKeys(side)) do
        local def = SideEffects.DEFS[id]
        if def then
            rows[#rows + 1] = { name = Text.key(def.name), left = Text.duration(side[id].left) }
        end
    end
    local knox = state.knox or {}
    for _, id in ipairs(Tables.sortedKeys(Monitor.KNOX_EFFECTS)) do
        local left = knox.effects and knox.effects[id]
        if type(left) == "number" and left > 0 then
            rows[#rows + 1] = { name = Text.key(Monitor.KNOX_EFFECTS[id]), left = Text.duration(left) }
        end
    end
    if (knox.boosterLeft or 0) > 0 then
        for _, key in ipairs(Monitor.BOOSTER_EFFECTS) do
            rows[#rows + 1] = { name = Text.key(key), left = Text.duration(knox.boosterLeft) }
        end
    end
    return rows
end

local function interactionRows(state)
    local rows = {}
    local pairsActive = state.meds and state.meds.pairs or {}
    for _, id in ipairs(Tables.sortedKeys(pairsActive)) do
        local pair = Interactions.PAIRS[id]
        if pair then
            rows[#rows + 1] = Text.key(pair.line)
        end
    end
    return rows
end

local function overdoseRow(state)
    local od = state.meds and state.meds.overdose
    if not od then
        return nil
    end
    return { name = Text.key("UI_EHR_OverdoseLine", od.level), left = Text.duration(od.left) }
end

-- Overview --------------------------------------------------------------------------------------------------------------

local function healing(state)
    local h = state.body and state.body.healing or {}
    if h.blocked then
        return {
            blocked = true,
            text = Text.key("UI_EHR_HealingSlowedShort"),
            reason = h.reason and Text.key("UI_EHR_HealReason_" .. h.reason) or nil,
        }
    end
    return { blocked = false, text = Text.key("UI_EHR_HealingActiveShort") }
end

local function oneDecimal(c)
    return string.format("%.1f", c)
end

local function temperature(input)
    local out = {}
    if input.bodyC then
        out.body = Text.key("UI_EHR_Monitor_BodyTemp", oneDecimal(input.bodyC))
    end
    if input.airC then
        out.air = Text.key("UI_EHR_Monitor_IndoorAir", oneDecimal(input.airC))
    end
    return out
end

-- The model -------------------------------------------------------------------------------------------------------------

function Monitor.build(input)
    local state = input.state
    local curing = (state.meds and state.conditions) and Doses.curing(state) or {}
    local conditions = conditionRows(input, curing)
    local wound = woundRow(input, curing)
    if wound then
        conditions[#conditions + 1] = wound
    end
    for _, row in ipairs(exposureRows(input)) do
        conditions[#conditions + 1] = row
    end
    local woundKnown = Knowledge.of(state, DiseaseInfo.WOUND_INFECTION, input.firstAid).progress
    return {
        bloodType = state.identity and state.identity.bloodType or nil,
        blood = blood(input),
        healing = healing(state),
        temperature = temperature(input),
        conditions = conditions,
        medications = medicationRows(state),
        sideEffects = sideEffectRows(state),
        interactions = interactionRows(state),
        overdose = overdoseRow(state),
        parts = BodyStatus.all(BodyParts.names, input.parts, state.wounds and state.wounds.parts, woundKnown),
    }
end

return Monitor
