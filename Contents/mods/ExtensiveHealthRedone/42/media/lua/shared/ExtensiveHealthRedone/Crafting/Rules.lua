-- Crafting rules, free of game objects: the fresh-herb test, which auto-learned recipes a character is missing, and
-- the clean bandage pack's counts. Game/RecipeCode and Server/Recipes read the game and call these.

local Data = require "ExtensiveHealthRedone/Crafting/Data"

local Rules = {}

-- Whether a candidate input item may be used in a medicine recipe. Only the listed herbs and berries are checked,
-- and only when they are food: those must be fresh (stale or rotten ones are refused). Everything else passes, so
-- the mortar, mug, honey, water container and so on are never refused here.
function Rules.acceptsIngredient(fullType, isFood, fresh, rotten)
    if not Data.freshOnly[fullType] or not isFood then
        return true
    end
    return fresh == true and rotten ~= true
end

-- levels: { [perk name] = level }. True when every auto-learn threshold is met.
function Rules.meetsAutoLearn(levels)
    for _, need in ipairs(Data.autoLearnLevels) do
        if (levels[need.perk] or 0) < need.level then
            return false
        end
    end
    return true
end

-- The auto-learned recipes this character should learn now, in Data order: none below the thresholds, otherwise the
-- ones isKnown(name) says are not known yet.
function Rules.missingAutoLearned(levels, isKnown)
    local missing = {}
    if not Rules.meetsAutoLearn(levels) then
        return missing
    end
    for _, name in ipairs(Data.autoLearned) do
        if not isKnown(name) then
            missing[#missing + 1] = name
        end
    end
    return missing
end

-- Uses of a pack after one bandage is put in (never above its size).
function Rules.usesAfterAdd(uses, maxUses)
    return math.min(maxUses or Data.pack.size, (uses or 0) + 1)
end

-- Uses of a pack just started from one loose bandage.
Rules.STARTED_PACK_USES = 1

return Rules
