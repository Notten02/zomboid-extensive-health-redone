-- Scalpel Master as pure rules on plain values.
-- Game/Scalpel reads the item and its script and writes what plan() returns.
--
-- Derive, don't store: a scalpel's stats are always the script's values, multiplied while (and only while) a living
-- Scalpel Master holds it in the main hand. Nothing is kept in item modData, so there are no saved originals to
-- restore or migrate; a scalpel saved, dropped or looted while boosted is put right the next time it is normalized.
-- Primary hand only: only the main hand attacks, so a secondary-hand boost would only change a tooltip.

local Data = require "ExtensiveHealthRedone/Data/Professions"

local Scalpel = {}

-- Floats come back from Java as single precision; a difference below this is no difference.
Scalpel.EPSILON = 0.0001

function Scalpel.isScalpel(fullType)
    return fullType == Data.SCALPEL_TYPE
end

-- who: { alive, hasTrait, inPrimaryHand } as plain booleans.
function Scalpel.boosted(who)
    return who ~= nil and who.alive == true and who.hasTrait == true and who.inPrimaryHand == true
end

-- base: the script's { minDamage, maxDamage, conditionLowerChance }. Returns the values the item should have.
function Scalpel.targets(base, boosted)
    local damage = boosted and Data.SCALPEL_DAMAGE or 1
    local durability = boosted and Data.SCALPEL_DURABILITY or 1
    return {
        minDamage = base.minDamage * damage,
        maxDamage = base.maxDamage * damage,
        -- an integer field in Java (HandWeapon:setConditionLowerChance(int))
        conditionLowerChance = math.floor(base.conditionLowerChance * durability + 0.5),
    }
end

local function differs(current, target)
    if type(current) ~= "number" then
        return true
    end
    return math.abs(current - target) > Scalpel.EPSILON * math.max(1, math.abs(target))
end

local FIELDS = { "minDamage", "maxDamage", "conditionLowerChance" }

-- current: the item's present { minDamage, maxDamage, conditionLowerChance }. Returns { field = value } for each field
-- that has to change (empty when the item is already right), and whether anything changes.
function Scalpel.plan(current, base, boosted)
    local target = Scalpel.targets(base, boosted)
    local writes, any = {}, false
    for _, field in ipairs(FIELDS) do
        if differs(current[field], target[field]) then
            writes[field] = target[field]
            any = true
        end
    end
    return writes, any
end

return Scalpel
