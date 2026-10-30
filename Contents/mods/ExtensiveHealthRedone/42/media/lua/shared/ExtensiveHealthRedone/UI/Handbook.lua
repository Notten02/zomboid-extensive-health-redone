-- The disease handbook (J): every in-scope disease in the original mod's order, known or locked, with its Cause,
-- Symptoms, Timing, Prevention and Treatment. Pure: the window (Client/Handbook) only draws what this returns.
--   * a disease is known by the monitor's own rule (Conditions/Knowledge, name level): flyer or radio, a medical
--     profession, First Aid 8, or self-evident; Knox only from the Kentucky Herald. The handbook has no stage or
--     progress tiers: known shows everything.
--   * Timing: the authored _Incubation/_Duration texts where they exist, else computed from the definition's hours
--     (divided by its speed option), else left out (driven, staged and per-part conditions).
--   * "LETHAL RISK" only on known entries, Knox included.
--   * Knox has its own locked text: a flyer or First Aid never unlocks it.
--   * Every disease is listed, even when switched off in the sandbox: it is a reference book.
--
--   Handbook.build(knowledge, firstAid, defs, sandbox) -> { known, total, entries = { ... } }
-- knowledge: the state's knowledge section; defs: the condition registry; sandbox(name, default).

local Text = require "ExtensiveHealthRedone/UI/Text"
local Knowledge = require "ExtensiveHealthRedone/Conditions/Knowledge"
local DiseaseInfo = require "ExtensiveHealthRedone/Data/DiseaseInfo"

local Handbook = {}

Handbook.SECTIONS = { "Cause", "Symptoms", "Timing", "Prevention", "Treatment" }

-- Diseases whose timing is authored text (UI_EHR_Codex_<id>_Incubation / _Duration).
Handbook.AUTHORED_TIMING = { heat_stroke = true, insomnia = true, painkiller_addiction = true, ahtr = true,
    knox_infection = true }

local function codex(id, field)
    return "UI_EHR_Codex_" .. id .. "_" .. field
end

local function definition(id, defs)
    if id == "wound_infection" then
        return DiseaseInfo.WOUND_INFECTION
    end
    return defs[id]
end

-- "12", "1.5": one decimal at most.
local function number(v)
    local rounded = math.floor(v * 10 + 0.5) / 10
    if rounded == math.floor(rounded) then
        return string.format("%d", rounded)
    end
    return string.format("%.1f", rounded)
end

local function amount(hours)
    if hours < 24 then
        return Text.key("UI_EHR_Codex_Hours", number(hours))
    end
    return Text.key("UI_EHR_Codex_Days", number(hours / 24))
end

local function range(minH, maxH, speed)
    minH, maxH = minH / speed, maxH / speed
    if minH == maxH then
        return amount(minH)
    end
    return Text.key("UI_EHR_Codex_Range", amount(minH), amount(maxH))
end

-- The Timing text, or nil when there is none to show.
function Handbook.timing(id, def, sandbox)
    if Handbook.AUTHORED_TIMING[id] then
        return Text.key("UI_EHR_Codex_TimingNotes", Text.key(codex(id, "Incubation")), Text.key(codex(id, "Duration")))
    end
    if not (def and def.incubation and def.duration) or def.driven or def.reverse or def.stages then
        return nil
    end
    local speed = def.speedOption and tonumber(sandbox(def.speedOption, 1)) or 1
    if not speed or speed <= 0 then
        speed = 1
    end
    return Text.key("UI_EHR_Codex_TimingText", range(def.incubation[1], def.incubation[2], speed),
        range(def.duration[1], def.duration[2], speed))
end

local function entry(id, knowledge, firstAid, defs, sandbox)
    local info = DiseaseInfo.BY_ID[id]
    local def = definition(id, defs)
    local known = def ~= nil and Knowledge.of({ knowledge = knowledge }, def, firstAid).name
    local e = {
        id = id,
        known = known,
        category = Text.key("UI_EHR_Codex_Category_" .. info.category),
    }
    if not known then
        e.icon = DiseaseInfo.UNKNOWN_ICON
        e.name = Text.key("UI_EHR_Codex_UnknownCategory_" .. info.category)
        e.lethal = false
        e.locked = Text.key(id == Knowledge.KNOX and "UI_EHR_Codex_LockedDescKnox" or info.lockedDesc
            or "UI_EHR_Codex_LockedDesc")
        return e
    end
    e.icon = info.icon
    e.name = Text.key(codex(id, "Name"))
    e.lethal = info.lethal == true
    e.sections = {}
    for _, field in ipairs(Handbook.SECTIONS) do
        local body
        if field == "Timing" then
            body = Handbook.timing(id, def, sandbox)
        else
            body = Text.key(codex(id, field))
        end
        if body then
            e.sections[#e.sections + 1] = { label = Text.key("UI_EHR_Codex_" .. field), body = body }
        end
    end
    return e
end

function Handbook.build(knowledge, firstAid, defs, sandbox)
    knowledge = knowledge or {}
    if not knowledge.diseases then
        knowledge = { diseases = {}, knoxHerald = knowledge.knoxHerald, professionGrant = knowledge.professionGrant }
    end
    sandbox = sandbox or function(_, default) return default end
    local model = { known = 0, total = #DiseaseInfo.ORDER, entries = {} }
    for _, id in ipairs(DiseaseInfo.ORDER) do
        local e = entry(id, knowledge, firstAid or 0, defs, sandbox)
        model.entries[#model.entries + 1] = e
        if e.known then
            model.known = model.known + 1
        end
    end
    return model
end

return Handbook
