-- Washing hands at a water source: which parts get cleaned, how much water and time it takes. Pure; the client
-- (Client/WashHands) uses it for the menu and the action length, the server (Server/Food) to validate and apply.
-- Clean hands lower the gastroenteritis risk because the risk reads the visible soil.

local Washing = {}

-- BloodBodyPartType names: the hands and arms.
Washing.PARTS = { "Hand_L", "Hand_R", "ForeArm_L", "ForeArm_R", "UpperArm_L", "UpperArm_R" }

Washing.WATER_PER_PART = 0.25
Washing.WATER_PER_PART_SOAP = 0.15
Washing.MIN_WATER = 0.1
Washing.TICKS_PER_WATER = 145
Washing.TICKS_PER_WATER_SOAP = 90
Washing.MIN_TICKS = 80
Washing.UNHAPPINESS_WITH_SOAP = 1   -- points off the 0-100 unhappiness scale

-- soil: { [part] = { blood = 0-1, dirt = 0-1 } }. Returns { parts = { names }, bloody = bool, water = units,
-- ticks = action length }, or nil when the hands and arms are already clean.
function Washing.plan(soil, soap)
    local parts, bloody = {}, false
    for _, part in ipairs(Washing.PARTS) do
        local s = soil[part]
        if s and (s.blood or 0) + (s.dirt or 0) > 0 then
            parts[#parts + 1] = part
            bloody = bloody or (s.blood or 0) > 0
        end
    end
    if #parts == 0 then
        return nil
    end
    local water = math.max(Washing.MIN_WATER, #parts * (soap and Washing.WATER_PER_PART_SOAP or Washing.WATER_PER_PART))
    local ticks = math.max(Washing.MIN_TICKS, water * (soap and Washing.TICKS_PER_WATER_SOAP or Washing.TICKS_PER_WATER))
    return { parts = parts, bloody = bloody, water = water, ticks = ticks }
end

return Washing
