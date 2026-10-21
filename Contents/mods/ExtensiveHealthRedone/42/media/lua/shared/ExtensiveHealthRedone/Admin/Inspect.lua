-- /ehrinspect Name: a short, read-only summary of a player's health state as chat lines for the admin (decision Q6).
-- Pure: lines are UI/Text values (keys and arguments), translated on the admin's client. Server/Admin writes the full
-- state (Core/Dump) to the server log alongside.

local Text = require "ExtensiveHealthRedone/UI/Text"
local Tables = require "ExtensiveHealthRedone/Core/Tables"
local BodyParts = require "ExtensiveHealthRedone/Data/BodyParts"
local Blood = require "ExtensiveHealthRedone/Blood/Blood"
local Knox = require "ExtensiveHealthRedone/Diseases/Knox/Knox"
local MedData = require "ExtensiveHealthRedone/Medication/Data"

local Inspect = {}

-- Arguments are strings: over the network every number becomes a double, which Java's getText may print as "2.0".
local function round(value)
    return tostring(math.floor((tonumber(value) or 0) + 0.5))
end

local function knoxStatus(state)
    if Knox.permanentlyImmune(state) then
        return Text.key("UI_EHR_Admin_KnoxImmune")
    end
    local c = state.conditions.active[Knox.ID]
    if c then
        return Text.key("UI_EHR_Admin_KnoxInfected", round(c.stage or 1))
    end
    if (state.knox.boosterLeft or 0) > 0 then
        return Text.key("UI_EHR_Admin_KnoxBooster", round(math.ceil(state.knox.boosterLeft / 60)))
    end
    return Text.key("UI_EHR_Admin_KnoxNone")
end

local function conditionName(defs, id)
    local def = defs[id]
    if def and def.name then
        return Text.key(def.name)
    end
    return Text.raw(id)
end

-- state: the target's state; defs: the condition definitions; username: who it is. Returns a list of text values.
function Inspect.lines(state, defs, username)
    local lines = {}
    local function add(t)
        lines[#lines + 1] = t
    end
    add(Text.key("UI_EHR_Admin_InspectHeader", tostring(username)))
    add(Text.key("UI_EHR_Admin_InspectBlood", round(Blood.percent(state.blood) * 100),
        tostring(state.identity.bloodType or "?")))

    local ids = Tables.sortedKeys(state.conditions.active)
    if #ids == 0 then
        add(Text.key("UI_EHR_Admin_InspectNoConditions"))
    end
    for _, id in ipairs(ids) do
        add(Text.key("UI_EHR_Admin_InspectCondition", conditionName(defs, id),
            round(state.conditions.active[id].stage or 1)))
    end

    for _, part in ipairs(BodyParts.names) do
        local e = state.wounds.parts[part]
        if e and e.phase == "infected" then
            add(Text.key("UI_EHR_Admin_InspectWound", Text.raw(part), round(e.stage or 1)))
        elseif e then
            add(Text.key("UI_EHR_Admin_InspectWoundIncubating", Text.raw(part)))
        end
    end

    for _, medId in ipairs(Tables.sortedKeys(state.meds.courses)) do
        local course = state.meds.courses[medId]
        local med = MedData.byId[medId]
        add(Text.key("UI_EHR_Admin_InspectCourse", med and Text.key(med.name) or Text.raw(medId),
            round(course.count), med and round(med.doses) or "?"))
    end

    add(Text.key("UI_EHR_Admin_InspectImmunity", round(state.immunity.score)))
    add(Text.key("UI_EHR_Admin_InspectKnox", knoxStatus(state)))
    add(Text.key("UI_EHR_Admin_InspectLogged"))
    return lines
end

return Inspect
