-- Multipliers on rates EHR systems compute, collected per step like the stat aggregator: a system (often an add-on's)
-- states a factor for a key and a source, and the lowest factor per key wins, so the worst cause sets the rate and
-- the next-worst takes over when it ends. A key nobody scales reads 1.
--
--   p.mods:scale("bloodRegen", "myaddon:anemia", 0.5)   -- blood volume recovers at half the rate
--   p.mods:get("bloodRegen")                            -- 0.5
--
-- Keys EHR reads (a system that scales one must run before the reader's order, or the factor applies a step late):
--   bloodRegen     blood volume recovery (Blood/Blood, order 200)
--   immunityRise   how fast the immune score recovers toward its target (Immunity/Immunity, order 395)

local Modifiers = {}
Modifiers.__index = Modifiers

function Modifiers.new()
    return setmetatable({ factors = {}, sources = {} }, Modifiers)
end

function Modifiers:scale(key, source, factor)
    if type(source) ~= "string" then
        error("modifiers need a source name", 2)
    end
    if type(factor) ~= "number" or factor < 0 then
        error("modifier factors are numbers from 0", 2)
    end
    local current = self.factors[key]
    if current == nil or factor < current then
        self.factors[key] = factor
        self.sources[key] = source
    end
end

function Modifiers:get(key)
    return self.factors[key] or 1
end

-- The source of the factor in effect for key, or nil.
function Modifiers:source(key)
    return self.sources[key]
end

return Modifiers
