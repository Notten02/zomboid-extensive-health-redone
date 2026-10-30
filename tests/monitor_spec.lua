-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter, missing-fields, need-check-nil
-- The EHR Monitor and Immune System view models (UI/Monitor, UI/BodyStatus, UI/Immune) and the display refresh
-- (Conditions/Refresh): what the tabs show for a given mirrored state and reader. Knowledge gates names, stages and
-- progress; the watch gates blood; the Knox infection stays "Unknown Infection" without the Kentucky Herald; and every
-- key the models can produce exists in the English translations.
local LuaSource = require("LuaSource")
local Schema = require("ExtensiveHealthRedone/Core/Schema")
local Text = require("ExtensiveHealthRedone/UI/Text")
local Monitor = require("ExtensiveHealthRedone/UI/Monitor")
local BodyStatus = require("ExtensiveHealthRedone/UI/BodyStatus")
local Immune = require("ExtensiveHealthRedone/UI/Immune")
local Refresh = require("ExtensiveHealthRedone/Conditions/Refresh")
local DiseaseInfo = require("ExtensiveHealthRedone/Data/DiseaseInfo")
local MedData = require("ExtensiveHealthRedone/Medication/Data")
local defs = require("ExtensiveHealthRedone/Conditions/Registry")

local UI_JSON = "Contents/mods/ExtensiveHealthRedone/42/media/lua/shared/Translate/EN/UI.json"

local function sandbox(values)
    return function(name, default)
        local v = values and values[name]
        if v == nil then
            return default
        end
        return v
    end
end

-- Renders text as "key(args)" so tests compare whole lines.
local function render(t)
    return Text.render(t, function(key, ...)
        local args = { ... }
        if #args == 0 then
            return key
        end
        for i = 1, #args do
            args[i] = tostring(args[i])
        end
        return key .. "(" .. table.concat(args, ",") .. ")"
    end)
end

local function state()
    local s = Schema.defaults()
    s.identity.bloodType = "A+"
    return s
end

local function build(s, opts)
    opts = opts or {}
    return Monitor.build({
        state = s, firstAid = opts.firstAid or 0, defs = defs, sandbox = sandbox(opts.sandbox),
        watch = opts.watch, bodyC = opts.bodyC, airC = opts.airC, parts = opts.parts,
    })
end

local function row(model, id)
    for _, r in ipairs(model.conditions) do
        if r.id == id then
            return r
        end
    end
    return nil
end

local function start(s, id, stage, left, len)
    s.conditions.active[id] = { stage = stage, left = left, len = len or { 60, 60, 60, 60 }, duration = 180, extra = 0,
        severity = 1, data = {} }
end

describe("monitor: blood", function()
    it("needs a powered Medical Monitor Watch unless MedicalWatchRequired is off", function()
        local s = state()
        assert.is_false(build(s).blood.visible)
        assert.is_true(build(s, { watch = true }).blood.visible)
        assert.is_true(build(s, { sandbox = { MedicalWatchRequired = false } }).blood.visible)
    end)

    it("shows volume, the saline share and its status, and the bag of the reader's type", function()
        local s = state()
        s.blood.volume, s.blood.saline = 4000, 2000
        local b = build(s, { watch = true }).blood
        assert.equal(80, b.percent)
        assert.equal(0.5, b.salineShare)
        assert.equal("UI_EHR_SalineStatus_Danger", b.salineStatus.key)
        assert.equal("Item_BloodBagAPos", b.bag)
        assert.equal("UI_EHR_SalineLine(2000,50%)", render(b.salineText))
        s.blood.volume, s.blood.saline = 500, 0
        local low = build(s, { watch = true }).blood
        assert.equal("Item_BloodBagEmpty", low.bag)
        assert.equal("UI_EHR_SalineStatus_Safe", low.salineStatus.key)
    end)
end)

describe("monitor: conditions", function()
    it("hides an unidentified disease behind its unknown name and hint", function()
        local s = state()
        start(s, "gastroenteritis", 2, 30)
        local r = row(build(s), "gastroenteritis")
        assert.is_false(r.known)
        assert.equal("UI_EHR_Unknown_Gastrointestinal", r.name.key)
        assert.equal("UI_EHR_Unknown_Gastrointestinal_Desc", r.description.key)
        assert.equal(DiseaseInfo.UNKNOWN_ICON, r.icon)
        assert.equal("UI_EHR_StageUnknown", r.detail.key)
        assert.equal("??%", r.progressText.raw)
        assert.is_nil(r.status)
    end)

    it("shows the stage from First Aid 4 and progress and treatment from 6, once the name is known", function()
        local s = state()
        s.knowledge.diseases.gastroenteritis = true
        start(s, "gastroenteritis", 2, 30)
        local r3 = row(build(s, { firstAid = 3 }), "gastroenteritis")
        assert.equal("UI_EHR_Disease_gastroenteritis", r3.name.key)
        assert.equal("UI_EHR_StageUnknown", r3.detail.key)
        local r4 = row(build(s, { firstAid = 4 }), "gastroenteritis")
        assert.equal("UI_EHR_StageSeverityLevel(2,UI_EHR_SeverityLevel_Severe)", render(r4.detail))
        assert.is_nil(r4.progress)
        local r6 = row(build(s, { firstAid = 6 }), "gastroenteritis")
        -- Stage 2 half way: (1 + 0.5) / 4.
        assert.equal(0.375, r6.progress)
        assert.equal("UI_EHR_Status_Untreated", r6.status.key)
    end)

    it("names the severity as a word beside the stage, never as a number", function()
        local s = state()
        s.knowledge.diseases.gastroenteritis = true
        start(s, "gastroenteritis", 2, 30)
        local function level(severity)
            s.conditions.active.gastroenteritis.severity = severity
            return render(row(build(s, { firstAid = 4 }), "gastroenteritis").detail)
        end
        assert.equal("UI_EHR_StageSeverityLevel(2,UI_EHR_SeverityLevel_Mild)", level(0.45))
        assert.equal("UI_EHR_StageSeverityLevel(2,UI_EHR_SeverityLevel_Moderate)", level(0.55))
        assert.equal("UI_EHR_StageSeverityLevel(2,UI_EHR_SeverityLevel_Moderate)", level(0.84))
        assert.equal("UI_EHR_StageSeverityLevel(2,UI_EHR_SeverityLevel_Severe)", level(0.85))
    end)

    it("shows only the stage for a condition whose symptoms don't scale with severity", function()
        local s = state()
        s.knowledge.diseases.sepsis = true
        start(s, "sepsis", 2, 30)
        assert.equal("UI_EHR_StageNumber(2)", render(row(build(s, { firstAid = 4 }), "sepsis").detail))
        start(s, "hypothermia", 2, 30)
        local r = row(build(s, { firstAid = 8 }), "hypothermia")
        assert.equal("UI_EHR_StageNumber(2)", render(r.detail))
    end)

    it("says TREATING while a course cures it", function()
        local s = state()
        s.knowledge.diseases.common_cold = true
        start(s, "common_cold", 2, 30)
        s.meds.courses.ColdFluTablets = { count = 2, elapsed = 240, cured = {} }
        s.meds.doses.ColdFluTablets = { since = 60 }
        local r = row(build(s, { firstAid = 6 }), "common_cold")
        assert.equal("UI_EHR_Status_Treating", r.status.key)
    end)

    it("gives sepsis, cellulitis, tetanus and AHTR flyer knowledge", function()
        for _, id in ipairs({ "sepsis", "cellulitis", "tetanus", "ahtr" }) do
            local s = state()
            start(s, id, 2, 30)
            assert.is_false(row(build(s), id).known, id)
            s.knowledge.diseases[id] = true
            assert.is_true(row(build(s), id).known, id)
        end
    end)

    it("keeps the Knox infection secret without the Herald, even at First Aid 10 or with a profession", function()
        local s = state()
        start(s, "knox_infection", 3, 0)
        s.conditions.active.knox_infection.data.progress = 0.6
        s.knowledge.professionGrant = "ehrdoctor"
        local r = row(build(s, { firstAid = 10 }), "knox_infection")
        assert.is_false(r.known)
        assert.equal("UI_EHR_Unknown_Infection", r.name.key)
        assert.is_nil(r.status)
    end)

    it("shows a known Knox infection like a disease: stage, progress and NO CURE, or TREATING while boosted", function()
        local s = state()
        start(s, "knox_infection", 4, 0)
        s.conditions.active.knox_infection.data.progress = 0.85
        s.knowledge.diseases.knox_infection = true
        s.knowledge.knoxHerald = true
        local r = row(build(s, { firstAid = 6 }), "knox_infection")
        assert.equal("UI_EHR_Disease_Knox_Infection", r.name.key)
        assert.equal("UI_EHR_StageNumber(4)", render(r.detail))
        assert.equal(0.85, r.progress)
        assert.equal("UI_EHR_Status_NoCure", r.status.key)
        assert.equal("UI_EHR_KnoxNoCureDetail", r.description.key)
        s.knox.effects.phalanxDebuff = 600
        assert.equal("UI_EHR_Status_Treating", row(build(s, { firstAid = 6 }), "knox_infection").status.key)
    end)

    it("counts a reverse condition down from its start stage", function()
        local s = state()
        start(s, "concussion", 2, 30)
        local r = row(build(s, { firstAid = 6 }), "concussion")
        -- Started at 3; stage 2 half way: (1 + 0.5) / 3.
        assert.equal(0.5, r.progress)
        assert.equal("UI_EHR_DiseaseDetail_StageTimeRest(2)", render(r.detail))
        assert.equal("UI_EHR_Status_Recovering", r.status.key)
    end)

    it("folds infected wounds into one row with the worst stage and the count", function()
        local s = state()
        s.knowledge.diseases.wound_infection = true
        s.wounds.parts.Hand_L = { phase = "infected", stage = 1, left = 100 }
        s.wounds.parts.Foot_R = { phase = "infected", stage = 2, left = 720 }
        s.wounds.parts.Head = { phase = "incubating", left = 60 }
        local r = row(build(s, { firstAid = 6 }), "wound_infection")
        assert.equal("UI_EHR_WoundInfectionCount(UI_EHR_WoundInfection,2)", render(r.name))
        assert.equal("UI_EHR_StageNumber(2)", render(r.detail))
        -- Stage 2 (24 h) half done: (1 + 0.5) / 3.
        assert.equal(0.5, r.progress)
    end)

    it("lists exposure meters at any First Aid level, hidden by the illness they lead to", function()
        local s = state()
        s.exposure.corpse, s.exposure.heat, s.exposure.cold, s.exposure.spores = 65, 90, 3, 80
        local model = build(s)
        assert.equal("UI_EHR_ExposureLevelLine(UI_EHR_ExposureLevel_Medium)", render(row(model, "corpse_exposure").detail))
        assert.equal("UI_EHR_ExposureLevelLine(UI_EHR_ExposureLevel_High)", render(row(model, "heat_exposure").detail))
        assert.equal("UI_EHR_ExposureLevelLine(UI_EHR_ExposureLevel_Medium)", render(row(model, "spores_exposure").detail))
        assert.is_nil(row(model, "cold_exposure"))
        start(s, "heat_stroke", 2, 30)
        assert.is_nil(row(build(s), "heat_exposure"))
    end)
end)

describe("monitor: medication", function()
    it("shows a running course with its dose count and next dose, and the cure time once fully dosed", function()
        local s = state()
        s.meds.courses.ColdFluTablets = { count = 3, elapsed = 600, cured = {} }
        s.meds.doses.ColdFluTablets = { since = 60 }
        local r = build(s).medications[1]
        assert.equal("UI_EHR_Med_ColdFluTablets", r.name.key)
        assert.equal("UI_EHR_MedAction_Tier_OTC", r.tier.key)
        assert.equal("UI_EHR_DoseCount(3,8)", render(r.doses))
        assert.equal("UI_EHR_NextDoseLine", r.schedule.key)
        s.meds.courses.ColdFluTablets.count = 8
        local done = build(s).medications[1]
        assert.equal("UI_EHR_CourseComplete", done.schedule.key)
        -- 28 h cure, 10 h elapsed.
        assert.equal("UI_EHR_TimeToCureLine(UI_EHR_Med_Tooltip_HoursMinutes(18,0))", render(done.top))
    end)

    it("marks an overdue course dose", function()
        local s = state()
        s.meds.courses.ColdFluTablets = { count = 2, elapsed = 600, cured = {} }
        s.meds.doses.ColdFluTablets = { since = 300 }
        assert.equal("UI_EHR_OverdueLine(UI_EHR_Med_Tooltip_HoursMinutes(1,0))", render(build(s).medications[1].schedule))
    end)

    it("lists active single doses but not everyday drinks", function()
        local s = state()
        s.meds.doses.Painkillers = { since = 30 }
        s.meds.doses.Water = { since = 10 }
        local meds = build(s).medications
        assert.equal(1, #meds)
        assert.equal("Painkillers", meds[1].id)
        assert.equal("UI_EHR_ActiveLine(UI_EHR_Med_Tooltip_HoursMinutes(2,30))", render(meds[1].top))
    end)

    it("shows side effects, Knox effects, the immunobooster, interactions and an overdose", function()
        local s = state()
        s.meds.side.nausea = { left = 90, data = {} }
        s.knox.effects.phalanxFever = 120
        s.knox.boosterLeft = 600
        s.meds.pairs.coughCold = true
        s.meds.overdose = { level = 2, left = 300, early = 1 }
        local model = build(s)
        assert.equal("UI_SideEffect_Nausea", model.sideEffects[1].name.key)
        assert.equal("UI_EHR_KnoxEffect_PhalanxFever", model.sideEffects[2].name.key)
        assert.equal(5, #model.sideEffects)
        assert.equal("Immunobooster", model.medications[#model.medications].id)
        assert.equal("UI_EHR_Text_MultipleColdMedicationsWatchForDrowsiness", model.interactions[1].key)
        assert.equal("UI_EHR_OverdoseLine(2)", render(model.overdose.name))
    end)
end)

describe("monitor: overview and body", function()
    it("says why healing is slowed, and shows body and room temperature", function()
        local s = state()
        s.body.healing = { blocked = true, reason = "thirsty" }
        local model = build(s, { bodyC = 37.26, airC = 18.0 })
        assert.equal("UI_EHR_HealingSlowedShort", model.healing.text.key)
        assert.equal("UI_EHR_HealReason_thirsty", model.healing.reason.key)
        assert.equal("UI_EHR_Monitor_BodyTemp(37.3)", render(model.temperature.body))
        assert.equal("UI_EHR_Monitor_IndoorAir(18.0)", render(model.temperature.air))
    end)

    it("ranks part statuses and colours the diagram by the top one", function()
        local part = BodyStatus.part({ bandaged = true, deep = true, pain = 20, health = 70 })
        assert.equal("UI_EHR_BodyLegend_Bandaged", part.statuses[1].label.key)
        assert.equal("UI_EHR_BodyStatus_Damaged", part.statuses[2].label.key)
        assert.equal(BodyStatus.VALUE.green, part.value)
        local bleeding = BodyStatus.part({ bleeding = true, scratched = true })
        assert.equal(1.0, bleeding.value)
        local injury = BodyStatus.part({ injury = true, pain = 5 })
        assert.equal("UI_EHR_BodyStatus_MinorPain", injury.statuses[1].label.key)
        assert.equal("UI_EHR_BodyStatus_Injury", injury.statuses[2].label.key)
    end)

    it("gives the wound infection hint only to a reader who knows wound infection at First Aid 6", function()
        local s = state()
        s.wounds.parts.Hand_L = { phase = "infected", stage = 3, left = 100 }
        s.wounds.parts.Foot_L = { phase = "incubating", left = 100 }
        local blind = build(s, { firstAid = 5 }).parts
        assert.is_nil(blind.Hand_L.hint)
        assert.equal("UI_EHR_BodyLegend_Infected", blind.Hand_L.statuses[1].label.key)
        assert.equal(0, #blind.Foot_L.statuses)
        local doctor = build(s, { firstAid = 8 }).parts
        assert.equal("UI_EHR_WoundHint_Urgent", doctor.Hand_L.hint.key)
        assert.equal("UI_EHR_WoundHint_Disinfect", doctor.Foot_L.hint.key)
        assert.equal("UI_EHR_BodyStatus_InfectionRisk", doctor.Foot_L.statuses[1].label.key)
    end)
end)

describe("immune tab", function()
    local function immunity(fields)
        local im = Schema.defaults().immunity
        for k, v in pairs(fields) do
            im[k] = v
        end
        return im
    end

    it("waits for the first update, and is hidden while the system is off", function()
        assert.is_true(Immune.build(immunity({ target = false }), sandbox()).awaiting)
        assert.is_false(Immune.visible(sandbox({ ImmunitySystemEnabled = false })))
        assert.is_true(Immune.visible(sandbox()))
    end)

    it("shows the band, target, trend and the risk at the effect strength", function()
        local m = Immune.build(immunity({ score = 100, target = 90, trend = "declining",
            factors = { nutrition = 80, hydration = 70, rest = 30, stressControl = 90, bloodCondition = 100,
                healthReserve = 45 } }), sandbox())
        assert.equal("UI_EHR_Immunity_Status_Strong", m.band.key)
        assert.equal("UI_EHR_LabelValue(UI_EHR_Immunity_Target,90%)", render(m.targetText))
        assert.equal("UI_EHR_LabelValue(UI_EHR_Immunity_Trend,UI_EHR_Immunity_Trend_Declining)", render(m.trend))
        assert.equal("UI_EHR_LabelValue(UI_EHR_Immunity_InfectionRisk,-35.0%)", render(m.risk))
        assert.equal("green", m.riskColor)
        assert.is_true(m.active)
        -- Weak factors, lowest first.
        assert.equal("UI_EHR_Immunity_Factor_Rest", m.pressures[1].label.key)
        assert.equal("UI_EHR_Immunity_Factor_HealthReserve", m.pressures[2].label.key)
    end)

    it("is monitoring only when gameplay effects are off or the strength is 0", function()
        for _, values in ipairs({ { ImmunityGameplayEffects = false }, { ImmunityEffectStrength = 0 } }) do
            local m = Immune.build(immunity({ score = 20, target = 20 }), sandbox(values))
            assert.is_false(m.active)
            assert.equal("UI_EHR_Immunity_MonitoringOnly", m.state.key)
            assert.equal("UI_EHR_LabelValue(UI_EHR_Immunity_InfectionRisk,UI_EHR_Immunity_NotApplied)", render(m.risk))
        end
    end)

    it("lists suppression and the Phalanx debuff before weak factors", function()
        local m = Immune.build(immunity({ score = 50, target = 35, factors = { rest = 10 },
            pressures = { antibiotic = true, immunosuppression = true, phalanx = 20 } }), sandbox())
        assert.equal("UI_EHR_Immunity_AntibioticPressure", m.pressures[1].label.key)
        assert.equal("UI_SideEffect_Immunosuppression", m.pressures[2].label.key)
        assert.equal("-20", m.pressures[3].value.raw)
        assert.equal("UI_EHR_Immunity_Factor_Rest", m.pressures[4].label.key)
    end)
end)

describe("display refresh", function()
    it("re-sends running conditions and wounds every 10 game minutes", function()
        local s = state()
        local dirty = {}
        local p = { state = s, dirty = function(name) dirty[#dirty + 1] = name end }
        for _ = 1, 30 do
            Refresh.update(p, 1)
        end
        assert.equal(0, #dirty)
        start(s, "common_cold", 2, 30)
        s.wounds.parts.Hand_L = { phase = "infected", stage = 1, left = 100 }
        for _ = 1, 20 do
            Refresh.update(p, 1)
        end
        assert.same({ "conditions", "wounds", "conditions", "wounds" }, dirty)
    end)
end)

describe("monitor translations", function()
    local keys = {}
    for key in LuaSource.read(UI_JSON):gmatch('"([%w_]+)"%s*:') do
        keys[key] = true
    end

    it("have every unknown name and hint, heal reason, immune band and every medication name", function()
        local needed = { "UI_EHR_DiseaseUnknown", "UI_EHR_DiseaseUnknownDesc" }
        for id in pairs(DiseaseInfo.BY_ID) do
            local name, desc = DiseaseInfo.unknownKeys(id)
            needed[#needed + 1] = name
            needed[#needed + 1] = desc
        end
        for _, reason in ipairs({ "hungry", "thirsty", "stressed", "tired", "pain" }) do
            needed[#needed + 1] = "UI_EHR_HealReason_" .. reason
        end
        for _, band in ipairs({ "Strong", "Stable", "Strained", "Compromised", "Suppressed" }) do
            needed[#needed + 1] = "UI_EHR_Immunity_Status_" .. band
        end
        for _, med in pairs(MedData.byId) do
            if med.name then
                needed[#needed + 1] = med.name
            end
        end
        for _, key in ipairs(needed) do
            assert.truthy(keys[key], "missing " .. key)
        end
    end)
end)
