-- What the EHR Monitor's body diagram shows per body part: every status, highest priority first, the colour value
-- for the diagram (0 healthy ... 1 red), and the W21 "what's needed" hint for wound infection.
-- From v0.9 EHR_HealthPanelUI.lua:4443-4615 (docs/porting/phase7/monitor-panel.md 2.3), translated (most labels were
-- hard-coded English), with garlic poultices shown too.
--
-- Input per part: plain facts read from vanilla's BodyPart by the client (Client/MonitorView):
--   { bleeding, infected (vanilla), fracture, bullet, glass, burn, burnWash, bandaged, bandageDirty, deep, bitten, cut,
--     scratched, injury, pain (0-100), stiffness (0-100), stitched, splinted, plantain, comfrey, garlic, health (0-100) }
-- and our wound infection, state.wounds.parts[part] = { phase = "incubating" | "infected", stage }.
-- hints: true when the reader knows wound infection and has First Aid 6 (Conditions/Knowledge progress gate).

local Text = require "ExtensiveHealthRedone/UI/Text"

local BodyStatus = {}

-- Diagram colour values (ISBodyPartPanel colour scheme in Client/MonitorView).
BodyStatus.VALUE = { green = 0.2, yellow = 0.4, orange = 0.6, purple = 0.8, red = 1.0 }

-- The legend under the diagram: colour and label.
BodyStatus.LEGEND = {
    { color = "green", label = "UI_EHR_BodyLegend_Bandaged" },
    { color = "yellow", label = "UI_EHR_BodyLegend_DirtyBandage" },
    { color = "orange", label = "UI_EHR_BodyLegend_PainWound" },
    { color = "purple", label = "UI_EHR_BodyLegend_Infected" },
    { color = "red", label = "UI_EHR_BodyLegend_Bleeding" },
}

local S = "UI_EHR_BodyStatus_"

-- Ordered by priority (v0.9's numbers). test(part, wound, hints) -> the label key (or nil) and a colour.
---@type { id: string, prio: integer, color: string?, test: fun(f: table, w: table?, hints: boolean?): string|false|nil, string? }[]
local RULES = {
    { id = "bleeding", prio = 110, color = "red", test = function(f) return f.bleeding and "UI_EHR_BodyLegend_Bleeding" end },
    { id = "infected", prio = 100, color = "purple", test = function(f, w)
        return (f.infected or (w and w.phase == "infected")) and "UI_EHR_BodyLegend_Infected"
    end },
    { id = "incubating", prio = 99, color = "yellow", test = function(_, w, hints)
        return hints and w and w.phase == "incubating" and S .. "InfectionRisk"
    end },
    { id = "fracture", prio = 95, color = "red", test = function(f) return f.fracture and S .. "Fracture" end },
    { id = "bullet", prio = 94, color = "red", test = function(f) return f.bullet and S .. "Bullet" end },
    { id = "glass", prio = 92, color = "red", test = function(f) return f.glass and S .. "Glass" end },
    { id = "bandage", prio = 89, test = function(f)
        if not f.bandaged then
            return nil
        end
        return f.bandageDirty and "UI_EHR_BodyLegend_DirtyBandage" or "UI_EHR_BodyLegend_Bandaged",
            f.bandageDirty and "yellow" or "green"
    end },
    { id = "burn", prio = 88, color = "orange", test = function(f)
        return f.burn and (f.burnWash and S .. "BurnWash" or S .. "Burn")
    end },
    { id = "damaged", prio = 86, test = function(f)
        local health = f.health or 100
        if health < 45 then
            return S .. "SevereDamage", "red"
        elseif health < 85 then
            return S .. "Damaged", "orange"
        end
    end },
    { id = "deep", prio = 84, color = "orange", test = function(f) return f.deep and S .. "DeepWound" end },
    { id = "bite", prio = 82, color = "red", test = function(f) return f.bitten and S .. "Bite" end },
    { id = "cut", prio = 78, color = "orange", test = function(f) return f.cut and S .. "Cut" end },
    { id = "scratch", prio = 74, color = "orange", test = function(f) return f.scratched and S .. "Scratch" end },
    { id = "pain", prio = 72, color = "orange", test = function(f)
        local pain = f.pain or 0
        if pain > 50 then
            return S .. "HeavyPain"
        elseif pain > 10 then
            return "UI_EHR_Symptom_Pain"
        elseif pain >= 1 then
            return S .. "MinorPain"
        end
    end },
    { id = "stiffness", prio = 70, test = function(f)
        local stiffness = f.stiffness or 0
        if stiffness >= 20 then
            return S .. "MuscleStrain", "orange"
        elseif stiffness >= 5 then
            return S .. "MinorStiffness", "yellow"
        elseif stiffness >= 1 then
            return S .. "SlightStiffness", "yellow"
        end
    end },
    { id = "stitched", prio = 32, color = "green", test = function(f) return f.stitched and S .. "Stitched" end },
    { id = "splinted", prio = 30, color = "green", test = function(f) return f.splinted and S .. "Splinted" end },
    { id = "plantain", prio = 26, color = "green", test = function(f) return f.plantain and S .. "Plantain" end },
    { id = "comfrey", prio = 26, color = "green", test = function(f) return f.comfrey and S .. "Comfrey" end },
    { id = "garlic", prio = 26, color = "green", test = function(f) return f.garlic and S .. "Garlic" end },
}

-- A wound with nothing else matched.
local INJURY = { id = "injury", prio = 46, color = "orange", label = S .. "Injury" }

-- The W21 hint for our wound infection (maintainer, Phase 7).
function BodyStatus.hint(wound)
    if not wound then
        return nil
    end
    if wound.phase == "incubating" then
        return Text.key("UI_EHR_WoundHint_Disinfect")
    elseif wound.phase == "infected" then
        return Text.key((wound.stage or 1) >= 3 and "UI_EHR_WoundHint_Urgent" or "UI_EHR_WoundHint_Antibiotics")
    end
    return nil
end

-- One part: { statuses = { { id, label = Text, color } }, color, value, hint = Text or nil }.
function BodyStatus.part(facts, wound, hints)
    facts = facts or {}
    local statuses = {}
    local wounded = false
    for _, rule in ipairs(RULES) do
        local label, color = rule.test(facts, wound, hints)
        if label then
            statuses[#statuses + 1] = { id = rule.id, label = Text.key(label), color = color or rule.color }
            wounded = wounded or (rule.id ~= "pain" and rule.id ~= "stiffness")
        end
    end
    -- Only pain and stiffness can be listed then, and both rank above an unnamed injury.
    if facts.injury and not wounded then
        statuses[#statuses + 1] = { id = INJURY.id, label = Text.key(INJURY.label), color = INJURY.color }
    end
    local top = statuses[1]
    return {
        statuses = statuses,
        color = top and top.color or nil,
        value = top and BodyStatus.VALUE[top.color] or 0,
        hint = hints and BodyStatus.hint(wound) or nil,
    }
end

-- Every part by name: parts = { [name] = facts }, wounds = state.wounds.parts.
function BodyStatus.all(names, parts, wounds, hints)
    local out = {}
    for _, name in ipairs(names) do
        out[name] = BodyStatus.part(parts and parts[name], wounds and wounds[name], hints)
    end
    return out
end

return BodyStatus
