-- Per-part stages inside one condition. The engine allows one instance per condition id, so a condition that can sit
-- on several hands or feet keeps them in its scratch: c.data.parts = { [part] = { stage, ... } }. The condition's own
-- stage is the worst part's, and c.source names that part (pain, the Monitor, debug).

local Text = require "ExtensiveHealthRedone/UI/Text"
local Tables = require "ExtensiveHealthRedone/Core/Tables"

local Parts = {}

-- Fixed order, so ties and labels don't depend on table order.
Parts.ORDER = { "Foot_L", "Foot_R", "Hand_L", "Hand_R" }

function Parts.all(c)
    c.data.parts = c.data.parts or {}
    return c.data.parts
end

function Parts.get(c, part)
    local parts = Parts.all(c)
    if not parts[part] then
        parts[part] = { stage = 0 }
    end
    return parts[part]
end

-- Sets a part's stage. Marks conditions dirty only when it changed. Returns true when it changed.
function Parts.setStage(p, c, part, stage)
    local entry = Parts.get(c, part)
    if entry.stage == stage then
        return false
    end
    entry.stage = stage
    if stage > (entry.maxStage or 0) then
        entry.maxStage = stage
    end
    c.data.maxStage = math.max(c.data.maxStage or 0, stage)
    p.dirty("conditions")
    return true
end

function Parts.stage(c, part)
    local entry = c.data.parts and c.data.parts[part]
    return entry and entry.stage or 0
end

-- Removes a part (healed, or amputated). Returns true when it was there.
function Parts.drop(p, c, part)
    local parts = Parts.all(c)
    if not parts[part] then
        return false
    end
    parts[part] = nil
    p.dirty("conditions")
    return true
end

-- The worst stage and the part that has it (0, nil when no part is affected).
function Parts.worst(c)
    local stage, worst = 0, nil
    local parts = c.data.parts or {}
    for _, part in ipairs(Parts.ORDER) do
        local entry = parts[part]
        if entry and entry.stage > stage then
            stage, worst = entry.stage, part
        end
    end
    return stage, worst
end

-- The affected parts in fixed order: { { part, stage } }.
function Parts.list(c)
    local out = {}
    local parts = c.data.parts or {}
    for _, part in ipairs(Parts.ORDER) do
        local entry = parts[part]
        if entry and entry.stage > 0 then
            out[#out + 1] = { part = part, stage = entry.stage }
        end
    end
    return out
end

local function isPart(name)
    return name == "Foot_L" or name == "Foot_R" or name == "Hand_L" or name == "Hand_R"
end

-- A condition started without parts (the debug menu, an admin) lands on its source part, or on fallback when the
-- source isn't a hand or foot. raise(p, c, part, stage) is the condition's own way of making a part worse.
function Parts.seed(p, c, fallback, raise)
    if not Tables.isEmpty(Parts.all(c)) then
        return
    end
    if not isPart(c.source) then
        c.source = fallback
    end
    raise(p, c, c.source, c.stage)
end

-- Stage entry. A natural change already gave the worst part that stage; a debug stage change moves the source part.
function Parts.follow(p, c, stage, raise)
    if not isPart(c.source) then
        return
    end
    local current = Parts.stage(c, c.source)
    if stage > current then
        raise(p, c, c.source, stage)
    elseif stage < current then
        Parts.setStage(p, c, c.source, stage)
    end
end

-- Vanilla's body part names (IG_UI), for the Monitor.
Parts.NAME_KEYS = { Foot_L = "IGUI_health_Left_Foot", Foot_R = "IGUI_health_Right_Foot",
    Hand_L = "IGUI_health_Left_Hand", Hand_R = "IGUI_health_Right_Hand" }

-- The affected parts as one text ("Left Foot, Right Foot"), or nil when none is.
function Parts.label(c)
    local label
    for _, e in ipairs(Parts.list(c)) do
        local name = Text.key(Parts.NAME_KEYS[e.part])
        label = label and Text.key("UI_EHR_Extremities_Join", label, name) or name
    end
    return label
end

-- Updates c.source to the worst part and returns the worst stage, or "recovered" when no part is affected (the
-- engine's drive result).
function Parts.result(p, c)
    local stage, worst = Parts.worst(c)
    if stage == 0 then
        return "recovered"
    end
    if c.source ~= worst then
        c.source = worst
        p.dirty("conditions")
    end
    return stage
end

return Parts
