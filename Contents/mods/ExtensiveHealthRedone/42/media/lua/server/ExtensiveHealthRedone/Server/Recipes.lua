-- Recipe learning on the authority: a safety net for the 17 auto-learned medicine recipes, and a debug command.
-- The scripts' AutoLearnAll (First Aid 6 plus Foraging 4) only fires on a level-up, so a character who already has
-- the levels (an existing save, a profession's starting skills) would wait for the next level-up, and where that
-- learning happens in MP is unverified. Here the authority checks each attached player when they attach and whenever
-- either level changes, learns what is missing and syncs the known recipes to the client. Literature and professions
-- teach through the scripts (LearnedRecipes, GrantedRecipes) and need nothing here.
-- An MP client loads this file too and stops at the first line.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Data = require "ExtensiveHealthRedone/Crafting/Data"
local Rules = require "ExtensiveHealthRedone/Crafting/Rules"

local log = Env.logger("Recipes")

local ServerRecipes = {}

-- vanilla's PF_Recipes (ISResearchRecipe:complete)
local SYNC_RECIPES = 0x00000001

-- { [perk name] = level } for the auto-learn perks, and the same as a string to notice a change.
local function levels(player)
    local out, parts = {}, {}
    for i, need in ipairs(Data.autoLearnLevels) do
        local level = player:getPerkLevel(Perks[need.perk])
        out[need.perk] = level
        parts[i] = tostring(level)
    end
    return out, table.concat(parts, "/")
end

-- Learns the auto-learned recipes this player qualifies for but doesn't know, and syncs them on a dedicated server.
-- Returns the names learned.
function ServerRecipes.grantAutoLearned(player)
    local missing = Rules.missingAutoLearned((levels(player)), function(name)
        return player:isRecipeActuallyKnown(name)
    end)
    for _, name in ipairs(missing) do
        player:learnRecipe(name)
    end
    if #missing > 0 and isServer() then
        sendSyncPlayerFields(player, SYNC_RECIPES)
    end
    return missing
end

-- key -> { player = IsoPlayer, levels = "6/4" } as last checked. A new player object (attach, reconnect, new
-- character) or a changed level triggers a check.
local checked = {}

local function check(key, player)
    local _, signature = levels(player)
    local last = checked[key]
    if last and last.player == player and last.levels == signature then
        return
    end
    checked[key] = { player = player, levels = signature }
    local learned = ServerRecipes.grantAutoLearned(player)
    if #learned > 0 then
        log:info(key, "learned", #learned, "EHR recipes at First Aid and Foraging", signature)
    end
end

Runtime.scheduler:every("recipes.autoLearn", 1, function()
    for key in pairs(checked) do
        if not Runtime.playerFor(key) then
            checked[key] = nil
        end
    end
    Runtime.eachAttached(function(key, player)
        check(key, player)
    end)
end, { coalesce = true })

-- Debug --------------------------------------------------------------------------------------------------------------

-- forget: drops the 17 auto-learned recipes (to test the safety net: it teaches them again within a game minute when
-- the levels qualify). autoLearn: runs the check now.
Runtime.registry:register("debug.recipes", {
    args = { action = { type = "string", oneOf = { forget = true, autoLearn = true } } },
    access = "medicalAdmin",
    debugOnly = true,
    handler = function(ctx, args)
        local player = ctx.actor.player
        if args.action == "forget" then
            local known = player:getKnownRecipes()
            for _, name in ipairs(Data.autoLearned) do
                known:remove(name)
            end
            if isServer() then
                sendSyncPlayerFields(player, SYNC_RECIPES)
            end
            checked[ctx.actor.key] = nil
        else
            checked[ctx.actor.key] = nil
            check(ctx.actor.key, player)
        end
        log:info(ctx.actor.key, "debug: recipes", args.action)
    end,
})

log:info("recipes loaded")

return ServerRecipes
