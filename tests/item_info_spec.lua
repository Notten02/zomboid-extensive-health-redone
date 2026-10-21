-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Item tooltip lines (UI/ItemInfo): mechanical facts come from the medication and blood data, authored text from the
-- Tooltip_EHR_<Item>_* keys, and every key a line names exists in the English translations.
local LuaSource = require("LuaSource")
local ItemInfo = require("ExtensiveHealthRedone/UI/ItemInfo")
local Text = require("ExtensiveHealthRedone/UI/Text")
local Data = require("ExtensiveHealthRedone/Medication/Data")
local Supplies = require("ExtensiveHealthRedone/Data/MedicalSupplies")

local TRANSLATE = "Contents/mods/ExtensiveHealthRedone/42/media/lua/shared/Translate/EN/"

local keys = {}
for _, file in ipairs({ "Tooltip.json", "UI.json" }) do
    for key in LuaSource.read(TRANSLATE .. file):gmatch('"([%w_]+)"%s*:') do
        keys[key] = true
    end
end

local function ctx(extra)
    local c = { has = function(key) return keys[key] == true end, knowledge = { diseases = {} }, firstAid = 0 }
    for k, v in pairs(extra or {}) do
        c[k] = v
    end
    return c
end

-- "key(arg,arg)" for each line, label then value.
local function show(t)
    return Text.render(t, function(key, ...)
        local args = { ... }
        for i = 1, #args do args[i] = tostring(args[i]) end
        return #args > 0 and (key .. "(" .. table.concat(args, ",") .. ")") or key
    end)
end

local function dump(lines)
    local out = {}
    for _, line in ipairs(lines) do
        out[#out + 1] = show(line.label) .. (line.value and (" = " .. show(line.value)) or "")
    end
    return table.concat(out, "\n")
end

local function has(lines, needle)
    return dump(lines):find(needle, 1, true) ~= nil
end

-- Every key a line names (label, value and their arguments).
local function namedKeys(t, out)
    if type(t) == "table" then
        if t.key then out[#out + 1] = t.key end
        for _, a in ipairs(t.args or {}) do namedKeys(a, out) end
    end
    return out
end

describe("item tooltip lines", function()
    it("derive a clinical drug's cures, supply and side effects from the medication data", function()
        local lines = assert(ItemInfo.lines("ExtensiveHealth.IVVancomycin", ctx()))
        assert.truthy(has(lines, "Tooltip_EHR_IVVancomycin_Category = Tooltip_EHR_Tier_Clinical"))
        assert.truthy(has(lines, "Tooltip_EHR_Label_Cures = UI_EHR_MedAction_DiseaseHours(UI_EHR_Disease_cellulitis,48)"))
        assert.truthy(has(lines, "UI_EHR_MedAction_DiseaseHours(UI_EHR_Disease_sepsis,48)"))
        assert.truthy(has(lines, "UI_EHR_MedAction_RequiresIVKit"))
        assert.truthy(has(lines, "Tooltip_EHR_Label_SideEffects = UI_SideEffect_RedManSyndrome"))
        -- The authored cure list and time are not used for medication: the data decides.
        assert.is_false(has(lines, "Tooltip_EHR_IVVancomycin_Cure_1"))
        assert.is_false(has(lines, "Tooltip_EHR_IVVancomycin_TreatmentTime"))
    end)

    it("show a course and the authored relief", function()
        local lines = assert(ItemInfo.lines("ExtensiveHealth.ColdFluTablets", ctx()))
        assert.truthy(has(lines, "UI_EHR_ItemInfo_CourseLabel = UI_EHR_ItemInfo_Course(8,4)"))
        assert.truthy(has(lines, "Tooltip_EHR_Label_Relieves = Tooltip_EHR_ColdFluTablets_Relief_1"))
        assert.truthy(has(lines, "UI_EHR_ItemInfo_Warning(Tooltip_EHR_ColdFluTablets_Warning)"))
    end)

    it("describe vanilla antibiotics as one dose that treats, without a cure (drift fixed)", function()
        local lines = assert(ItemInfo.lines("Base.Antibiotics", ctx()))
        assert.is_false(has(lines, "Tooltip_EHR_Label_Cures"))
        assert.truthy(has(lines, "UI_EHR_ItemInfo_TreatsLabel = UI_EHR_Disease_cellulitis"))
        assert.truthy(has(lines, "Tooltip_EHR_Antibiotics_Category = Tooltip_EHR_Tier_Basic"))
    end)

    it("fall back to the authored crash text when a drug has no side effects in the data", function()
        local lines = assert(ItemInfo.lines("Base.PillsVitamins", ctx()))
        assert.truthy(has(lines, "Tooltip_EHR_Label_SideEffects = Tooltip_EHR_PillsVitamins_SideEffect_1"))
    end)

    it("show blood bag compatibility only with knowledge, and freshness always", function()
        local bag = Supplies.bagFor["A+"]
        local unknown = assert(ItemInfo.lines(bag, ctx({ bloodType = "O-",
            spoilage = { state = "fresh", hoursLeft = 0.5 } })))
        assert.truthy(has(unknown, "Tooltip_EHR_Label_CompatibilityUnknown"))
        assert.is_false(has(unknown, "UI_EHR_Transfusion_"))
        assert.truthy(has(unknown, "Tooltip_EHR_Label_FreshFor = UI_EHR_Med_Tooltip_Minutes(30)"))

        local known = assert(ItemInfo.lines(bag, ctx({ firstAid = 8, bloodType = "O-",
            spoilage = { state = "stale", hoursLeft = 0.25 } })))
        assert.truthy(has(known, "Tooltip_EHR_BloodBagAPos_BloodCompatibility"))
        assert.truthy(has(known, "UI_EHR_Transfusion_IncompatibleSuffix"))
        assert.truthy(has(known, "Tooltip_EHR_Label_StaleSpoilsIn"))

        local flyer = assert(ItemInfo.lines(Supplies.bagFor["O-"], ctx({ bloodType = "AB+",
            knowledge = { diseases = { blood_types = true } }, spoilage = { frozen = true } })))
        assert.truthy(has(flyer, "UI_EHR_Transfusion_CompatibleSuffix"))
        assert.truthy(has(flyer, "Tooltip_EHR_Label_FrozenSpoilage"))
        assert.truthy(has(assert(ItemInfo.lines(bag, ctx({ spoilage = { state = "rotten" } }))),
            "Tooltip_EHR_Label_Spoiled"))
    end)

    it("keep the Knox items' authored text at the experimental tier", function()
        local lines = assert(ItemInfo.lines("ExtensiveHealth.GeneTherapyKit", ctx()))
        assert.truthy(has(lines, "Tooltip_EHR_GeneTherapyKit_Category = Tooltip_EHR_Tier_Experimental"))
        assert.truthy(has(lines, "Tooltip_EHR_GeneTherapyKit_SuccessText)"))
        local off = assert(ItemInfo.lines("ExtensiveHealth.GeneTherapyKit",
            ctx({ sandbox = function(name) return name == "PatientZeroTraitDisabled" end })))
        assert.truthy(has(off, "Tooltip_EHR_GeneTherapyKit_SuccessText_PatientZeroDisabled"))
    end)

    it("annotate only EHR items, not everyday drinks or unrelated items", function()
        assert.is_nil(ItemInfo.lines("Base.HotDrinkTea", ctx()))
        assert.is_nil(ItemInfo.lines("Base.Apple", ctx()))
        assert.is_false(ItemInfo.covers("Fluid.Water"))
        assert.is_true(ItemInfo.covers("ExtensiveHealth.Syringe"))
    end)

    it("name only translated keys, and have authored text for every annotated item", function()
        local types = {}
        for fullType in pairs(Data.byType) do types[#types + 1] = fullType end
        for fullType in pairs(ItemInfo.OTHER) do types[#types + 1] = fullType end
        for _, fullType in ipairs(types) do
            local lines = ItemInfo.lines(fullType, ctx({ firstAid = 10, bloodType = "A+",
                spoilage = { state = "fresh", hoursLeft = 1 }, preparation = 0.5 }))
            if lines then
                assert.truthy(keys["Tooltip_EHR_" .. ItemInfo.textName(fullType) .. "_Category"],
                    fullType .. " has no authored category")
                for _, line in ipairs(lines) do
                    for _, key in ipairs(namedKeys(line.label, namedKeys(line.value, {}))) do
                        assert.truthy(keys[key], fullType .. " names a missing key " .. key)
                    end
                end
            end
        end
    end)
end)
