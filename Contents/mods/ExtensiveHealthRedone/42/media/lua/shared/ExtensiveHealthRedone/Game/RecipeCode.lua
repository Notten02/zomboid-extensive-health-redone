-- The recipe callbacks the scripts name (OnTest / OnCreate = EHRRecipeCode.<name>). This is shared Lua because the
-- client's crafting window tests recipes and the authority (single player, or the MP server) tests and performs them.
-- The rules are in Crafting/Rules; these functions only read and write the game objects.
--
-- 42.21 calls an OnTest once per candidate input item as (item, character|nil) and drops the item when it returns
-- false. An OnCreate runs only on the authority, as (craftRecipeData, character), after the outputs were added and
-- before the consumed inputs are removed (ISHandcraftAction:performRecipe).

local Env = require "ExtensiveHealthRedone/Game/Env"
local Data = require "ExtensiveHealthRedone/Crafting/Data"
local Rules = require "ExtensiveHealthRedone/Crafting/Rules"

local log = Env.logger("Recipes")

-- The one global the recipe scripts name. 42.21's RecipeCodeOnTest is a Java class, so v0.9's key on it is not used.
EHRRecipeCode = EHRRecipeCode or {}

-- OnTest of the 11 herb recipes: listed herbs and berries must be fresh. Called often (every UI refresh): keep it cheap.
function EHRRecipeCode.FreshMedicinalIngredients(item, _character)
    if not item then
        return true
    end
    local fullType = item:getFullType()
    if not Data.freshOnly[fullType] then
        return true
    end
    local isFood = instanceof(item, "Food")
    return Rules.acceptsIngredient(fullType, isFood, isFood and item:isFresh(), isFood and item:isRotten())
end

local function sync(character, item)
    if isServer() then
        syncItemFields(character, item)
    end
end

-- OnCreate of EHRAddBandageToPack: the kept pack (NotFull in the script) gets the consumed bandage as one more use.
function EHRRecipeCode.AddBandageToPack(data, character)
    local kept = data:getAllKeepInputItems()
    for i = 0, kept:size() - 1 do
        local pack = kept:get(i)
        if pack:getFullType() == Data.pack.item then
            pack:setCurrentUses(Rules.usesAfterAdd(pack:getCurrentUses(), pack:getMaxUses()))
            sync(character, pack)
            return
        end
    end
    log:warn("add bandage to pack: no pack among the kept inputs")
end

-- OnCreate of EHRStartBandagePack: the new pack (created full) holds only the one bandage it was made from.
function EHRRecipeCode.StartBandagePack(data, character)
    local created = data:getAllCreatedItems()
    for i = 0, created:size() - 1 do
        local pack = created:get(i)
        if pack:getFullType() == Data.pack.item then
            pack:setCurrentUses(Rules.STARTED_PACK_USES)
            sync(character, pack)
        end
    end
end

return EHRRecipeCode
