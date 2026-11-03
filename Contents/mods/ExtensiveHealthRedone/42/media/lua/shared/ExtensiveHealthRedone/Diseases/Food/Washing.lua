-- Washing hands at a water source: which parts get cleaned, how much water and time it takes. Pure; the client
-- (Client/WashHands) uses it for the menu and the action length, the server (Server/Food) to validate and apply.
-- Clean hands lower the gastroenteritis risk because the risk reads the visible soil.

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

-- soil: { [part] = { blood = 0-1, dirt = 0-1 } }, for the parts there are. Returns { parts = { names }, bloody = bool,
-- water = units, ticks = action length }, or nil when they are already clean.
function Washing.plan(soil, soap)
    local parts, bloody = {}, false
    local function add(part)
        local s = soil[part]
        if s and (s.blood or 0) + (s.dirt or 0) > 0 then
            parts[#parts + 1] = part
            bloody = bloody or (s.blood or 0) > 0
        end
    end
    for _, part in ipairs(Washing.PARTS) do
        add(part)
    end
    for _, part in ipairs(Washing.EXTRA) do
        add(part)
    end
    if #parts == 0 then
        return nil
    end
    local water = math.max(Washing.MIN_WATER, #parts * (soap and Washing.WATER_PER_PART_SOAP or Washing.WATER_PER_PART))
    local ticks = math.max(Washing.MIN_TICKS, water * (soap and Washing.TICKS_PER_WATER_SOAP or Washing.TICKS_PER_WATER))
    return { parts = parts, bloody = bloody, water = water, ticks = ticks }
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
