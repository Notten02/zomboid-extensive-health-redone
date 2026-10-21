-- The lines EHR adds under an item's vanilla tooltip (Client/ItemTooltip), and the medication facts the context menu
-- shares (Client/MedicationMenu). docs/porting/phase7/tooltips-moodles-watch.md, Part A.
--
-- Mechanical facts come from the data the simulation uses, so a tooltip can't drift from the mechanics again (v0.9's
-- did, section 6.3): tier, cures and their times, the course, the syringe or IV kit, side effects (Medication/Data),
-- blood bag compatibility (Blood/Transfusion) and freshness (Blood/Spoilage). The authored text stays translated
-- keys, read by the item's name: Tooltip_EHR_<Item>_Category, _Description, _Effect_<i>, _Relief_<i>, _Warning, and
-- for items outside the medication data (supplies, bags, Knox items) also _Requirement_<i>, _Cure_<i>,
-- _TreatmentTime and _SideEffect_<i>.
--
--   ItemInfo.lines(fullType, ctx) -> { { label = Text, value = Text?, color = Draw colour, progress = 0-1?,
--                                        wrap = bool? }, ... } or nil for items we don't annotate
--   ctx: has(key) -> bool (the key is translated), knowledge (mirror section), firstAid, bloodType,
--        spoilage = { state, hoursLeft, frozen } (blood bags), preparation = 0-1 (a bag being prepared),
--        sandbox(name, default)

local Text = require "ExtensiveHealthRedone/UI/Text"
local Data = require "ExtensiveHealthRedone/Medication/Data"
local SideEffects = require "ExtensiveHealthRedone/Medication/SideEffects"
local Supplies = require "ExtensiveHealthRedone/Data/MedicalSupplies"
local BloodData = require "ExtensiveHealthRedone/Data/Blood"
local Transfusion = require "ExtensiveHealthRedone/Blood/Transfusion"
local Spoilage = require "ExtensiveHealthRedone/Blood/Spoilage"
local defs = require "ExtensiveHealthRedone/Conditions/Registry"

local ItemInfo = {}

-- Tier name and colour: 0 basic ... 4 experimental (the Knox items).
ItemInfo.TIERS = {
    [0] = { key = "Tooltip_EHR_Tier_Basic", color = "dim" },
    [1] = { key = "Tooltip_EHR_Tier_OTC", color = "green" },
    [2] = { key = "Tooltip_EHR_Tier_Prescription", color = "blue" },
    [3] = { key = "Tooltip_EHR_Tier_Clinical", color = "purple" },
    [4] = { key = "Tooltip_EHR_Tier_Experimental", color = "red" },
}

-- Our items outside the medication data, with authored text. kind: "supply", "bag" (also freshness and
-- compatibility), "knox" (tier 4, all authored), "prepared" (a bag being prepared: preparation progress).
ItemInfo.OTHER = {
    ["ExtensiveHealth.EmptyBloodBag"] = "supply",
    ["ExtensiveHealth.HomemadeEmptyBloodBag"] = "supply",
    ["ExtensiveHealth.PreparedHomemadeBloodBag"] = "prepared",
    ["ExtensiveHealth.SalineBag"] = "supply",
    ["ExtensiveHealth.IVKit"] = "supply",
    ["ExtensiveHealth.HomemadeIVKit"] = "supply",
    ["ExtensiveHealth.Syringe"] = "supply",
    ["ExtensiveHealth.HomemadeSyringe"] = "supply",
    ["ExtensiveHealth.SterilizedBandages"] = "supply",
    ["ExtensiveHealth.AlchoholicBandage"] = "supply",
    ["ExtensiveHealth.PlasticStrips"] = "supply",
    ["ExtensiveHealth.GeneTherapyKit"] = "knox",
    ["ExtensiveHealth.PhalanxPills"] = "knox",
    ["ExtensiveHealth.AntibodyTestKit"] = "knox",
    ["ExtensiveHealth.ImmunoboosterShot"] = "knox",
}
for fullType in pairs(Supplies.bloodTypeOf) do
    ItemInfo.OTHER[fullType] = "bag"
end

-- Condition names that the registry doesn't hold (wound infection is per body part).
local EXTRA_NAMES = { woundInfection = "UI_EHR_Disease_WoundInfection" }

-- The key name of an item: the part after the module, non-word characters as "_" (v0.9 TS:29-32).
function ItemInfo.textName(fullType)
    local name = tostring(fullType):match("^[^%.]*%.(.+)$") or tostring(fullType)
    return (name:gsub("[^%w]", "_"))
end

-- The medication entry an item has a tooltip for (everyday drinks have none).
local function medFor(fullType)
    local med = Data.byType[fullType]
    if med and not med.silent then
        return med
    end
    return nil
end

function ItemInfo.covers(fullType)
    return medFor(fullType) ~= nil or ItemInfo.OTHER[fullType] ~= nil
end

function ItemInfo.conditionName(id)
    local def = defs[id]
    return Text.key((def and def.name) or EXTRA_NAMES[id] or id)
end

-- "Sepsis: 24h" for each condition a medication cures, in target order.
function ItemInfo.cureTimes(med)
    local list = {}
    local cures = med.cures or {}
    for _, id in ipairs(med.targets) do
        if cures[id] then
            list[#list + 1] = Text.key("UI_EHR_MedAction_DiseaseHours", ItemInfo.conditionName(id), cures[id])
        end
    end
    return list
end

-- Building lines ---------------------------------------------------------------------------------------------------------

local function add(lines, label, value, color, extra)
    local line = { label = label, value = value, color = color or "text" }
    for k, v in pairs(extra or {}) do
        line[k] = v
    end
    lines[#lines + 1] = line
    return line
end

-- A labelled list: the label on the first row, one value per row.
local function list(lines, labelKey, values, color)
    for i, value in ipairs(values) do
        add(lines, i == 1 and Text.key(labelKey) or Text.raw(""), value, color)
    end
end

-- The authored keys prefix_1, prefix_2, ... that exist, as text.
local function numbered(ctx, prefix)
    local out = {}
    local i = 1
    while ctx.has(prefix .. i) do
        out[#out + 1] = Text.key(prefix .. i)
        i = i + 1
    end
    return out
end

local function header(lines, ctx, base, tier)
    local t = tier and ItemInfo.TIERS[tier]
    local category = base .. "Category"
    if ctx.has(category) then
        add(lines, Text.key(category), t and Text.key(t.key), t and t.color or "blue")
    elseif t then
        add(lines, Text.key(t.key), nil, t.color)
    end
end

local function description(lines, ctx, base)
    if ctx.has(base .. "Description") then
        add(lines, Text.key(base .. "Description"), nil, "text", { wrap = true })
    end
    for _, effect in ipairs(numbered(ctx, base .. "Effect_")) do
        add(lines, Text.key("UI_EHR_ItemInfo_Plus", effect), nil, "green", { wrap = true })
    end
end

local function warning(lines, ctx, base)
    if ctx.has(base .. "Warning") then
        add(lines, Text.key("UI_EHR_ItemInfo_Warning", Text.key(base .. "Warning")), nil, "red", { wrap = true })
    end
end

local function medicationLines(lines, ctx, base, med)
    header(lines, ctx, base, med.tier)
    description(lines, ctx, base)
    list(lines, "Tooltip_EHR_Label_Cures", ItemInfo.cureTimes(med), "blue")
    if Data.isCourse(med) then
        add(lines, Text.key("UI_EHR_ItemInfo_CourseLabel"),
            Text.key("UI_EHR_ItemInfo_Course", med.doses, med.interval), "dim")
    end
    local reliefs = numbered(ctx, base .. "Relief_")
    if #reliefs > 0 then
        list(lines, "Tooltip_EHR_Label_Relieves", reliefs, "yellow")
    else
        local treats = {}
        for _, id in ipairs(med.targets) do
            if not (med.cures and med.cures[id]) then
                treats[#treats + 1] = ItemInfo.conditionName(id)
            end
        end
        list(lines, "UI_EHR_ItemInfo_TreatsLabel", treats, "yellow")
    end
    if med.supply == "syringe" then
        add(lines, Text.key("UI_EHR_MedAction_RequiresSyringe"), nil, "orange")
    elseif med.supply == "ivKit" then
        add(lines, Text.key("UI_EHR_MedAction_RequiresIVKit"), nil, "orange")
    end
    local side = {}
    for _, id in ipairs(med.side or {}) do
        local def = SideEffects.DEFS[id]
        side[#side + 1] = Text.key(def and def.name or id)
    end
    if #side == 0 then
        -- Crashes (caffeine, stimulants) are timed effects, not side effects; the authored text describes them.
        side = numbered(ctx, base .. "SideEffect_")
    end
    list(lines, "Tooltip_EHR_Label_SideEffects", side, "orange")
    warning(lines, ctx, base)
end

local function authoredLines(lines, ctx, base, tier)
    header(lines, ctx, base, tier)
    description(lines, ctx, base)
    list(lines, "Tooltip_EHR_Label_Cures", numbered(ctx, base .. "Cure_"), "blue")
    if ctx.has(base .. "TreatmentTime") then
        add(lines, Text.key("Tooltip_EHR_Label_TreatmentTime"), Text.key(base .. "TreatmentTime"), "dim")
    end
    list(lines, "Tooltip_EHR_Label_Requires", numbered(ctx, base .. "Requirement_"), "orange")
    list(lines, "Tooltip_EHR_Label_SideEffects", numbered(ctx, base .. "SideEffect_"), "orange")
    warning(lines, ctx, base)
    if tier == 4 then
        local disabled = ctx.sandbox and ctx.sandbox("PatientZeroTraitDisabled", false) == true
        local success = base .. (disabled and "SuccessText_PatientZeroDisabled" or "SuccessText")
        if not ctx.has(success) then
            success = base .. "SuccessText"
        end
        if ctx.has(success) then
            add(lines, Text.key("UI_EHR_ItemInfo_Plus", Text.key(success)), nil, "green", { wrap = true })
        end
        if ctx.has(base .. "FailureText") then
            add(lines, Text.key("UI_EHR_ItemInfo_Minus", Text.key(base .. "FailureText")), nil, "red", { wrap = true })
        end
    end
end

-- Compatibility only with blood type knowledge (the flyer or First Aid 8); freshness always.
local function bagLines(lines, ctx, base, fullType)
    if Transfusion.knowsTypes(ctx.knowledge, ctx.firstAid) then
        if ctx.has(base .. "BloodCompatibility") then
            add(lines, Text.key(base .. "BloodCompatibility"), nil, "blue", { wrap = true })
        end
        if ctx.bloodType then
            local ok = Transfusion.compatible(Supplies.bloodTypeOf[fullType], ctx.bloodType)
            add(lines, Text.key(ok and "UI_EHR_Transfusion_CompatibleSuffix" or "UI_EHR_Transfusion_IncompatibleSuffix"),
                nil, ok and "green" or "red")
        end
    else
        add(lines, Text.key("Tooltip_EHR_Label_CompatibilityUnknown"), nil, "dim", { wrap = true })
    end
    local s = ctx.spoilage
    if not s then
        return
    end
    if s.frozen then
        add(lines, Text.key("Tooltip_EHR_Label_FrozenSpoilage"), nil, "blue")
    elseif s.state == Spoilage.ROTTEN then
        add(lines, Text.key("Tooltip_EHR_Label_Spoiled"), nil, "red")
    elseif s.state == Spoilage.STALE then
        local left = math.max(0, s.hoursLeft or 0)
        add(lines, Text.key("Tooltip_EHR_Label_StaleSpoilsIn"), Text.duration(left * 60), "orange",
            { progress = left / (BloodData.ROTTEN_HOURS - BloodData.STALE_HOURS) })
    else
        local left = math.max(0, s.hoursLeft or 0)
        add(lines, Text.key("Tooltip_EHR_Label_FreshFor"), Text.duration(left * 60), "green",
            { progress = left / BloodData.STALE_HOURS })
    end
end

function ItemInfo.lines(fullType, ctx)
    local base = "Tooltip_EHR_" .. ItemInfo.textName(fullType) .. "_"
    local lines = {}
    local med = medFor(fullType)
    if med then
        medicationLines(lines, ctx, base, med)
        return lines
    end
    local kind = ItemInfo.OTHER[fullType]
    if not kind then
        return nil
    end
    authoredLines(lines, ctx, base, kind == "knox" and 4 or nil)
    if kind == "bag" then
        bagLines(lines, ctx, base, fullType)
    elseif kind == "prepared" and ctx.preparation then
        local share = math.max(0, math.min(1, ctx.preparation))
        add(lines, Text.key("Tooltip_EHR_Label_PreparationProgress", Text.percent(share * 100)), nil, "blue",
            { progress = share })
    end
    return lines
end

return ItemInfo
