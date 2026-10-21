-- Blood types, compatibility and what a transfusion or blood draw does to the patient.
-- From v0.9 EHR_Transfusion.lua and EHR_ServerCommands.lua (docs/porting/phase3/transfusion-ahtr-supplies.md).
-- Fixed: reactions use each stat's own scale (v0.9 clamped pain, panic and food sickness to 1); a bag given at full
-- blood is refused instead of wasted; saline only counts the volume it added.

local Data = require "ExtensiveHealthRedone/Data/Blood"
local Supplies = require "ExtensiveHealthRedone/Data/MedicalSupplies"
local BodyParts = require "ExtensiveHealthRedone/Data/BodyParts"
local Blood = require "ExtensiveHealthRedone/Blood/Blood"
local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Speech = require "ExtensiveHealthRedone/Core/Speech"
local Spoilage = require "ExtensiveHealthRedone/Blood/Spoilage"
local Temperature = require "ExtensiveHealthRedone/Body/Temperature"

local Transfusion = {}

-- Recipient -> donors it accepts (ABO/Rh; O- gives to all, AB+ takes from all).
Transfusion.ACCEPTS = {
    ["O-"] = { "O-" },
    ["O+"] = { "O-", "O+" },
    ["A-"] = { "O-", "A-" },
    ["A+"] = { "O-", "O+", "A-", "A+" },
    ["B-"] = { "O-", "B-" },
    ["B+"] = { "O-", "O+", "B-", "B+" },
    ["AB-"] = { "O-", "A-", "B-", "AB-" },
    ["AB+"] = { "O-", "O+", "A-", "A+", "B-", "B+", "AB-", "AB+" },
}

function Transfusion.compatible(donor, recipient)
    for _, t in ipairs(Transfusion.ACCEPTS[recipient] or {}) do
        if t == donor then
            return true
        end
    end
    return false
end

-- Can this character judge compatibility? Read the Blood Types flyer, or First Aid at least KNOWLEDGE_FIRST_AID.
function Transfusion.knowsTypes(knowledge, firstAid)
    return (knowledge and knowledge.diseases and knowledge.diseases[Data.KNOWLEDGE_ID] == true)
        or (firstAid or 0) >= Data.KNOWLEDGE_FIRST_AID
end

-- Why a bag can't be given right now, or nil. kind: a fullType from Supplies.transfusable.
function Transfusion.refusal(state, fullType, spoilage)
    if not Supplies.transfusable[fullType] then
        return "UI_EHR_Transfusion_Unusable"
    end
    if spoilage == Spoilage.ROTTEN then
        return "UI_EHR_Transfusion_BloodSpoiledDesc"
    end
    if state.blood.volume >= state.blood.max then
        return "UI_EHR_Transfusion_BloodFull"
    end
    return nil
end

local function reaction(p, values, source)
    for _, stat in ipairs({ "SICKNESS", "FOOD_SICKNESS", "PANIC", "PAIN" }) do
        if values[stat] then
            p.stats:addF(stat, source, values[stat])
        end
    end
    Blood.change(p.state.blood, -values.lossMl)
end

-- Spoiled-blood reaction (stale bag): sickness, fever, damage to a few random parts, and lost blood.
local function staleReaction(p)
    local s = Data.STALE
    reaction(p, s, "staleBlood")
    Temperature.spike(p, "staleBlood", s.feverC)
    for _ = 1, s.parts do
        local part = BodyParts.names[p.rng.int(1, #BodyParts.names)]
        p.body:partDamage(part, "staleBlood", p.rng.int(s.partDamage[1], s.partDamage[2]))
    end
    Speech.stage(p, "UI_EHR_Text_ThatBloodTastedOff")
end

-- Incompatible blood: immediate reaction, then AHTR starts, or worsens and lasts at least 72 h more.
local function incompatible(p, defs)
    reaction(p, Data.INCOMPATIBLE, "incompatibleBlood")
    Speech.stage(p, "UI_EHR_Text_SomethingsWrongIFeelTerrible")
    local active = p.state.conditions.active.ahtr
    if active then
        active.severity = math.min(Data.AHTR_WORSEN_MAX, active.severity + Data.AHTR_WORSEN_STEP)
        local short = Data.AHTR_MIN_LEFT_HOURS * 60 - Engine.minutesLeft(active)
        if short > 0 then
            if active.stage < 3 then
                active.extra = (active.extra or 0) + short
            else
                active.left = active.left + short
            end
        end
        p.dirty("conditions")
        return "worsened"
    end
    local c = Engine.contract(p, defs, "ahtr", { source = "transfusion" })
    if c then
        c.severity = math.max(c.severity, Data.AHTR_SEVERITY)
        return "ahtr"
    end
    return "reaction"
end

-- Applies a transfusion to the patient p. Returns a short outcome for logs and tests:
-- "saline", "compatible", "ahtr", "worsened" or "reaction".
function Transfusion.apply(p, defs, fullType, spoilage)
    local b = p.state.blood
    if fullType == Supplies.saline then
        local added = Blood.change(b, Data.SALINE_ML)
        b.saline = b.saline + added
        if b.volume > 0 and b.saline / b.volume >= Data.DILUTION_WARNING then
            Speech.stage(p, "UI_EHR_Dialogue_Saline_Warning")
        else
            Speech.stage(p, "UI_EHR_Dialogue_Saline_Good")
        end
        p.stats:addF("THIRST", "saline", -Data.SALINE_THIRST)
        p.dirty("blood")
        return "saline"
    end
    if spoilage == Spoilage.STALE then
        staleReaction(p)
    end
    local donor = Supplies.bloodTypeOf[fullType]
    local outcome
    if Transfusion.compatible(donor, p.state.identity.bloodType) then
        Blood.change(b, Data.BAG_ML)
        Speech.stage(p, "UI_EHR_Text_ThatShouldHelp")
        outcome = "compatible"
    else
        outcome = incompatible(p, defs)
    end
    p.dirty("blood")
    return outcome
end

-- Blood draw: needs DRAW_MINIMUM of max volume. Returns the filled bag type, or nil and a refusal key.
function Transfusion.drawRefusal(state)
    if Blood.percent(state.blood) < Data.DRAW_MINIMUM then
        return "UI_EHR_Transfusion_NotEnoughBloodSafe"
    end
    if not Supplies.bagFor[state.identity.bloodType] then
        return "UI_EHR_Transfusion_SomethingWentWrong"
    end
    return nil
end

function Transfusion.draw(p)
    local b = p.state.blood
    Blood.change(b, -Data.DRAW_ML)
    p.stats:addF("FATIGUE", "bloodDraw", Data.DRAW_FATIGUE)
    p.stats:addF("ENDURANCE", "bloodDraw", -Data.DRAW_ENDURANCE)
    Speech.stage(p, "UI_EHR_DrawBlood_Complete")
    p.dirty("blood")
    return Supplies.bagFor[p.state.identity.bloodType]
end

-- A lab blood sample (the syringe draw of Zombie Virus Vaccine) takes a few mL, so it only needs half the blood.
-- Returns a refusal key, or nil.
function Transfusion.sampleRefusal(state)
    if Blood.percent(state.blood) < Data.SAMPLE_MINIMUM then
        return "UI_EHR_Transfusion_NotEnoughBloodSafe"
    end
    return nil
end

function Transfusion.sample(p)
    Blood.change(p.state.blood, -Data.SAMPLE_ML)
    p.dirty("blood")
end

return Transfusion
