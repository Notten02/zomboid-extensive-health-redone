-- Skill loss wished for this step, by perk: the passive skills (Strength, Fitness) wasting away while the body lacks
-- what it needs. Systems state an XP drain per game hour; the highest drain per perk wins (the worst cause sets it).
-- Server/PerkWriter, the only code that takes XP away, applies it the way vanilla's own passive-skill decay does.
--
--   p.perks:drain("Strength", "myaddon:protein", 6)    -- lose 6 Strength XP per game hour
--
-- Perk names are vanilla Perks field names. dt scales the drain in the writer.

local PerkAggregator = {}
PerkAggregator.__index = PerkAggregator

PerkAggregator.PERKS = { Strength = true, Fitness = true }

function PerkAggregator.new()
    return setmetatable({ drains = {} }, PerkAggregator)
end

function PerkAggregator:drain(perk, source, xpPerHour)
    if type(source) ~= "string" then
        error("perk drains need a source name", 2)
    end
    if not PerkAggregator.PERKS[perk] then
        error("perk drains are for Strength and Fitness: " .. tostring(perk), 2)
    end
    if type(xpPerHour) == "number" and xpPerHour > 0 and xpPerHour > (self.drains[perk] or 0) then
        self.drains[perk] = xpPerHour
    end
end

-- XP per game hour for perk (0 when none).
function PerkAggregator:get(perk)
    return self.drains[perk] or 0
end

return PerkAggregator
