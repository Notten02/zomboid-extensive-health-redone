-- Washing hands at a water source or from a carried container: which parts get cleaned, how much water and time it
-- takes. Pure; the client (Client/WashHands) uses it for the menu and the action length, the server (Server/Food) to
-- validate and apply. Clean hands lower the gastroenteritis risk because the risk reads the visible soil.

local Washing = {}

-- BloodBodyPartType names: the hands and arms.
Washing.PARTS = { "Hand_L", "Hand_R", "ForeArm_L", "ForeArm_R", "UpperArm_L", "UpperArm_R" }
-- With The Only Cure (Game/BodySoil): worn prostheses beside the arms, or the face alone for a character with no hand
-- or prosthesis left. Without the mod the soil never has them.
Washing.EXTRA = { "Prosthesis_L", "Prosthesis_R", "Head" }

Washing.WATER_PER_PART = 0.25
Washing.WATER_PER_PART_SOAP = 0.15
Washing.MIN_WATER = 0.1
Washing.TICKS_PER_WATER = 145
Washing.TICKS_PER_WATER_SOAP = 90
Washing.MIN_TICKS = 80
Washing.UNHAPPINESS_WITH_SOAP = 1   -- points off the 0-100 unhappiness scale
-- When the water doesn't cover every dirty part, what touches the food goes first (Game/BodySoil), then up the arms.
Washing.FIRST = { "Hand_L", "Hand_R", "Prosthesis_L", "Prosthesis_R", "Head", "ForeArm_L", "ForeArm_R", "UpperArm_L",
    "UpperArm_R" }
-- Slack when comparing water amounts: the game keeps them as 32-bit floats (a 0.9 canteen holds 0.89999998).
Washing.WATER_SLACK = 0.001

-- soil: { [part] = { blood = 0-1, dirt = 0-1 } }, for the parts there are. Returns { parts = { names }, bloody = bool,
-- water = units, ticks = action length }, or nil when they are already clean.
-- available (a carried container, which rarely holds a full wash): the water there is. With less than every dirty
-- part needs, the plan keeps the parts that fit, in Washing.FIRST order, and is marked partial; when not even one
-- part fits, parts is empty and water is what one part needs, so Washing.enough fails.
function Washing.plan(soil, soap, available)
    local function dirty(part)
        local s = soil[part]
        return s ~= nil and (s.blood or 0) + (s.dirt or 0) > 0
    end
    local parts = {}
    for _, list in ipairs({ Washing.PARTS, Washing.EXTRA }) do
        for _, part in ipairs(list) do
            if dirty(part) then
                parts[#parts + 1] = part
            end
        end
    end
    if #parts == 0 then
        return nil
    end
    local perPart = soap and Washing.WATER_PER_PART_SOAP or Washing.WATER_PER_PART
    local partial = false
    local count = #parts
    if available and available + Washing.WATER_SLACK < count * perPart then
        partial = true
        count = math.floor((available + Washing.WATER_SLACK) / perPart)
        parts = {}
        for _, part in ipairs(Washing.FIRST) do
            if #parts < count and dirty(part) then
                parts[#parts + 1] = part
            end
        end
    end
    local bloody = false
    for _, part in ipairs(parts) do
        bloody = bloody or (soil[part].blood or 0) > 0
    end
    local water = math.max(Washing.MIN_WATER, math.max(1, count) * perPart)
    local ticks = math.max(Washing.MIN_TICKS, water * (soap and Washing.TICKS_PER_WATER_SOAP or Washing.TICKS_PER_WATER))
    return { parts = parts, bloody = bloody, water = water, ticks = ticks, partial = partial }
end

-- Whether a source holding `available` water covers the plan.
function Washing.enough(plan, available)
    return #plan.parts > 0 and available + Washing.WATER_SLACK >= plan.water
end

-- The average blood and dirt of a list of surfaces ({ blood, dirt } each): what touches the food (Game/BodySoil).
function Washing.average(surfaces)
    local blood, dirt = 0, 0
    for _, s in ipairs(surfaces) do
        blood, dirt = blood + (s.blood or 0), dirt + (s.dirt or 0)
    end
    local n = math.max(1, #surfaces)
    return { blood = blood / n, dirt = dirt / n }
end

return Washing
