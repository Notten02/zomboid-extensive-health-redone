-- Rolling and checking blood types. Compatibility between types is Blood/Transfusion's.

local data = require "ExtensiveHealthRedone/Data/BloodTypes"

local BloodTypes = {}

local valid = {}
for _, t in ipairs(data.types) do
    valid[t] = true
end

function BloodTypes.isValid(value)
    return type(value) == "string" and valid[value] == true
end

-- rng.int(lo, hi) inclusive. A new character always rolls.
function BloodTypes.roll(rng)
    local total = 0
    for _, w in ipairs(data.weights) do
        total = total + w
    end
    local pick = rng.int(1, total)
    for i, w in ipairs(data.weights) do
        pick = pick - w
        if pick <= 0 then
            return data.types[i]
        end
    end
    return data.types[#data.types]
end

return BloodTypes
