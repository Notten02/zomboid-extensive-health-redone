-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The medicine recipes, recipe learning and the clean bandage pack, against our recipe scripts:
--   * the fresh-herb OnTest is our own global, every OnTest/OnCreate a script names exists, and the herbs it checks
--     are exactly the perishable ones the herb recipes take (vanilla DaysFresh, when the game is found);
--   * the auto-learned, supply and taught recipe sets match Crafting/Data, the Ultimate guide and the professions;
--   * the v0.9 semantic fixes (empty mugs, Permethrin's alcohol, whole honeycomb) stay in;
--   * the pack recipes' counts match the pack item, and the Lua callbacks and the authority's auto-learn safety net.
local LuaSource = require("LuaSource")
local Data = require("ExtensiveHealthRedone/Crafting/Data")
local Rules = require("ExtensiveHealthRedone/Crafting/Rules")

local SCRIPTS = "Contents/mods/ExtensiveHealthRedone/42/media/scripts/"
local LUA = "Contents/mods/ExtensiveHealthRedone/42/media/lua/"
local VANILLA = (os.getenv("PZ_MEDIA") or "/mnt/games/Steam/steamapps/common/ProjectZomboid/projectzomboid/media")
    .. "/scripts"

local function list(cmd)
    local out = {}
    local p = io.popen(cmd)
    if not p then
        return out
    end
    for line in p:lines() do
        out[#out + 1] = line
    end
    p:close()
    return out
end

local function uncomment(text)
    return (text:gsub("/%*.-%*/", ""))
end

local function readScripts(dir)
    local parts = {}
    for _, path in ipairs(list('find "' .. dir .. '" -name "*.txt" 2>/dev/null | sort')) do
        parts[#parts + 1] = uncomment(LuaSource.read(path))
    end
    return table.concat(parts, "\n")
end

local function script(name)
    return uncomment(LuaSource.read(SCRIPTS .. name))
end

-- name -> { props = { key = value }, inputs = { line, ... }, outputs = { line, ... } }, plus the names in file order.
local function recipes(text)
    local byName, names = {}, {}
    for name, body in text:gmatch("craftRecipe%s+([%w_]+)%s*(%b{})") do
        local props = {}
        for key, value in ("\n" .. body):gmatch("\n%s*([%w_]+)%s*=%s*([^,\n]*)") do
            props[key] = value
        end
        local function lines(section)
            local out = {}
            for line in (body:match(section .. "%s*(%b{})") or ""):gmatch("[^\n]+") do
                local trimmed = line:match("^%s*(.-),?%s*$")
                if trimmed ~= "" and trimmed ~= "{" and trimmed ~= "}" then
                    out[#out + 1] = trimmed
                end
            end
            return out
        end
        byName[name] = { props = props, inputs = lines("inputs"), outputs = lines("outputs") }
        names[#names + 1] = name
    end
    return byName, names
end

local function setOf(items)
    local s = {}
    for _, v in ipairs(items) do
        s[v] = true
    end
    return s
end

local function split(value)
    local out = {}
    for part in (value or ""):gmatch("[^;%s]+") do
        out[#out + 1] = part
    end
    return out
end

local function sameSet(expected, actual, what)
    local e, a = setOf(expected), setOf(actual)
    for name in pairs(e) do
        assert.is_true(a[name] == true, what .. " is missing " .. name)
    end
    for name in pairs(a) do
        assert.is_true(e[name] == true, what .. " has unexpected " .. name)
    end
end

local function itemBlock(text, name)
    return text:match("item%s+" .. name .. "%s*(%b{})")
end

local ours = readScripts(SCRIPTS)
local vanilla = readScripts(VANILLA)
local medicine = recipes(script("EHR_Recipes.txt"))
local supply = recipes(script("EHR_SupplyRecipes.txt"))
local all = recipes(ours)
-- The recipes of this feature (other scripts may add their own).
local mine = {}
for name, r in pairs(medicine) do
    mine[name] = r
end
for name, r in pairs(supply) do
    mine[name] = r
end

describe("medicine recipe scripts", function()
    local herbRecipes = {}
    for name, r in pairs(medicine) do
        if r.props.OnTest then
            herbRecipes[#herbRecipes + 1] = name
        end
    end

    -- The crafting window shows getText("IGUI_CraftingCategories_" .. category with its first letter upper-cased)
    -- (vanilla ISWidgetRecipeCategories); a category without the key shows the raw key.
    it("name every crafting category in every language (or use one of vanilla's)", function()
        local vanillaCategories = { Assembly = true, Carving = true, Cooking = true, Medical = true, Packing = true,
            Tools = true, Miscellaneous = true, Outdoors = true }
        local categories = {}
        for _, file in ipairs({ "EHR_Recipes.txt", "EHR_SupplyRecipes.txt", "EHR_HomemadeSupplies.txt" }) do
            for _, r in pairs(recipes(script(file))) do
                local category = r.props.category
                if category and category ~= "" then
                    categories[category:sub(1, 1):upper() .. category:sub(2)] = true
                end
            end
        end
        assert.is_true(categories.EHRMedicine)
        for _, lang in ipairs({ "CH", "CN", "EN", "ES", "FR", "IT", "JP", "PTBR", "RU", "UA" }) do
            local text = LuaSource.read(LUA .. "shared/Translate/" .. lang .. "/IG_UI.json")
            for category in pairs(categories) do
                assert.is_true(vanillaCategories[category] or text:find('"IGUI_CraftingCategories_' .. category .. '"%s*:') ~= nil,
                    lang .. " has no name for the crafting category " .. category)
            end
        end
    end)

    it("define the 17 auto-learned recipes and the 5 pack recipes", function()
        local names = {}
        for name in pairs(medicine) do
            names[#names + 1] = name
        end
        local expected = {}
        for _, name in ipairs(Data.autoLearned) do
            expected[#expected + 1] = name
        end
        for _, name in ipairs(Data.pack.recipes) do
            expected[#expected + 1] = name
        end
        sameSet(expected, names, "EHR_Recipes.txt")
        assert.equal(17, #Data.autoLearned)
    end)

    it("use our fresh-herb OnTest on the 11 herb recipes, never v0.9's RecipeCodeOnTest key", function()
        assert.equal(11, #herbRecipes)
        for _, name in ipairs(herbRecipes) do
            assert.equal("EHRRecipeCode.FreshMedicinalIngredients", medicine[name].props.OnTest, name)
        end
        assert.is_nil(ours:find("RecipeCodeOnTest.EHR", 1, true))
    end)

    it("name only OnTest and OnCreate functions our Lua defines", function()
        local code = {}
        for _, path in ipairs(list('find "' .. LUA .. '" -name "*.lua" | sort')) do
            code[#code + 1] = LuaSource.strip(LuaSource.read(path))
        end
        local source = table.concat(code, "\n")
        local checked = 0
        for _, r in pairs(all) do
            for _, key in ipairs({ "OnTest", "OnCreate" }) do
                local ref = r.props[key]
                if ref then
                    checked = checked + 1
                    local escaped = ref:gsub("%p", "%%%0")
                    local defined = source:find("function%s+" .. escaped .. "%s*%(")
                        or source:find(escaped .. "%s*=%s*function")
                    assert.truthy(defined, key .. " = " .. ref .. " is not defined in our Lua")
                end
            end
        end
        assert.is_true(checked >= 13)
    end)

    it("check freshness of exactly the perishable herbs and berries the herb recipes take", function()
        if vanilla == "" then
            ---@diagnostic disable-next-line: missing-parameter
            pending("game scripts not found; set PZ_MEDIA")
            return
        end
        local named = {}
        for _, name in ipairs(herbRecipes) do
            for _, line in ipairs(medicine[name].inputs) do
                for fullType in line:gmatch("(Base%.[%w_]+)") do
                    local body = itemBlock(vanilla, fullType:sub(6))
                    if body and body:find("DaysFresh") then
                        named[#named + 1] = fullType
                    end
                end
            end
        end
        local listed = {}
        for fullType in pairs(Data.freshOnly) do
            listed[#listed + 1] = fullType
        end
        sameSet(listed, named, "perishable herb inputs")
    end)

    it("refuse dried herbs (only the fresh types are listed)", function()
        for _, r in pairs(medicine) do
            for _, line in ipairs(r.inputs) do
                assert.is_nil(line:find("Dried", 1, true), line)
            end
        end
    end)

    it("take an empty mug for every tea", function()
        for _, name in ipairs({ "MakeCommonColdTea", "MakeAntipyreticTea", "MakeRelaxantTea" }) do
            local found = false
            for _, line in ipairs(medicine[name].inputs) do
                if line:find("Base.MugWhite", 1, true) then
                    found = true
                    assert.truthy(line:find("flags%[[^%]]*IsEmpty"), name .. ": mug must be empty")
                end
            end
            assert.is_true(found, name .. " has no mug")
        end
    end)

    it("take 0.1 L of alcohol for Permethrin, not wipes or a Disinfectant bottle", function()
        local inputs = table.concat(medicine.MakeHomemadeTopicalPermethrin.inputs, "\n")
        assert.is_nil(inputs:find("AlcoholWipes", 1, true))
        assert.is_nil(inputs:find("Disinfectant", 1, true))
        assert.truthy(inputs:find("item 1 [*]\n-fluid 0.1 [RubbingAlcohol;Vodka;Whiskey]", 1, true))
    end)

    it("make honey only from a whole honeycomb", function()
        local line = medicine.MakeHoneyFromHoneycomb.inputs[2]
        assert.truthy(line:find("ExtensiveHealth.Honeycomb", 1, true))
        assert.truthy(line:find("IsWholeFoodItem", 1, true))
    end)
end)

describe("recipe learning", function()
    local parts = {}
    for i, need in ipairs(Data.autoLearnLevels) do
        parts[i] = need.perk .. ":" .. need.level
    end
    local thresholds = table.concat(parts, ";")

    it("auto-learns exactly the 17 medicine recipes, at Crafting/Data's levels", function()
        local auto = {}
        for name, r in pairs(mine) do
            if r.props.AutoLearnAll or r.props.AutoLearnAny then
                auto[#auto + 1] = name
                assert.equal(thresholds, r.props.AutoLearnAll, name)
            end
        end
        sameSet(Data.autoLearned, auto, "auto-learned recipes")
        assert.equal("Doctor:6;PlantScavenging:4", thresholds)
    end)

    it("needs the guide or a profession for the 7 supply recipes", function()
        local names = {}
        for name, r in pairs(supply) do
            names[#names + 1] = name
            assert.equal("true", r.props.NeedToBeLearn, name)
            assert.is_nil(r.props.AutoLearnAll, name)
            assert.is_nil(r.props.AutoLearnAny, name)
        end
        sameSet(Data.supply, names, "EHR_SupplyRecipes.txt")
    end)

    it("makes every learned recipe one of the 24 the guide and professions teach", function()
        local learned = {}
        for name, r in pairs(mine) do
            if r.props.NeedToBeLearn == "true" then
                learned[#learned + 1] = name
            end
        end
        sameSet(Data.all, learned, "recipes that need to be learned")
        assert.equal(24, #Data.all)
    end)

    it("teaches all 24 from the Ultimate guide and one from the Plant-Based Antibiotics recipe", function()
        local flyers = script("EHR_Flyers.txt")
        local guide = assert(itemBlock(flyers, "EhrRecipeUltimateCraftGuide"))
        sameSet(Data.all, split(guide:match("LearnedRecipes%s*=%s*([^,\n]*)")), "Ultimate guide")
        local single = assert(itemBlock(flyers, "EhrRecipePlantBasedAntibiotics"))
        sameSet({ "MakePlantBasedAntibiotics" }, split(single:match("LearnedRecipes%s*=%s*([^,\n]*)")),
            "Plant-Based Antibiotics recipe")
    end)

    it("grants all 24 to both EHR professions", function()
        local professions = script("EHR_Professions.txt")
        local count = 0
        for value in professions:gmatch("GrantedRecipes%s*=%s*([^,\n]*)") do
            count = count + 1
            sameSet(Data.all, split(value), "profession GrantedRecipes")
        end
        assert.equal(2, count)
    end)

    it("learns nothing below the thresholds and only the missing ones at them", function()
        local none = function() return false end
        assert.same({}, Rules.missingAutoLearned({ Doctor = 5, PlantScavenging = 10 }, none))
        assert.same({}, Rules.missingAutoLearned({ Doctor = 10, PlantScavenging = 3 }, none))
        assert.same({}, Rules.missingAutoLearned({}, none))
        assert.equal(17, #Rules.missingAutoLearned({ Doctor = 6, PlantScavenging = 4 }, none))
        local missing = Rules.missingAutoLearned({ Doctor = 6, PlantScavenging = 4 }, function(name)
            return name ~= "MakeRelaxantTea"
        end)
        assert.same({ "MakeRelaxantTea" }, missing)
    end)
end)

describe("clean bandage pack", function()
    local packBody = assert(itemBlock(ours, "SterilizedBandages"))
    local useDelta = tonumber(packBody:match("UseDelta%s*=%s*([%d.]+)"))

    it("has 1 / UseDelta bandages", function()
        assert.equal(Data.pack.size, math.floor(1 / useDelta + 0.5))
    end)

    it("recipes are not learned and are hand crafts", function()
        for _, name in ipairs(Data.pack.recipes) do
            local r = assert(medicine[name], name)
            assert.equal("false", r.props.NeedToBeLearn, name)
            assert.is_nil(r.props.AutoLearnAll, name)
            assert.truthy(r.props.Tags:find("InHandCraft", 1, true), name)
        end
    end)

    it("unpacks and packs a full pack's worth", function()
        local unpack = medicine.EHRUnpackBandagePack
        assert.truthy(unpack.inputs[1]:find("mode:destroy", 1, true))
        assert.truthy(unpack.inputs[1]:find("IsFull", 1, true))
        assert.equal("item " .. Data.pack.size .. " " .. Data.pack.bandage, unpack.outputs[1])
        local pack = medicine.EHRPackBandages
        assert.truthy(pack.inputs[1]:find("item " .. Data.pack.size .. " [" .. Data.pack.bandage .. "]", 1, true))
        assert.equal("item 1 " .. Data.pack.item, pack.outputs[1])
    end)

    it("takes one bandage by using one use of the pack, also on double-click", function()
        local take = medicine.EHRTakeBandageFromPack
        assert.is_nil(take.inputs[1]:find("mode:", 1, true))
        assert.equal("item 1 " .. Data.pack.bandage, take.outputs[1])
        assert.equal("ExtensiveHealth.EHRTakeBandageFromPack", packBody:match("DoubleClickRecipe%s*=%s*([^,\n]*)"))
    end)

    it("adds a bandage to a pack with room, which it keeps", function()
        local add = medicine.EHRAddBandageToPack
        assert.truthy(add.inputs[2]:find("[" .. Data.pack.item .. "] mode:keep", 1, true))
        assert.truthy(add.inputs[2]:find("NotFull", 1, true))
        assert.same({}, add.outputs)
        assert.equal("EHRRecipeCode.AddBandageToPack", add.props.OnCreate)
        assert.equal("EHRRecipeCode.StartBandagePack", medicine.EHRStartBandagePack.props.OnCreate)
    end)

    it("is not taught by the guide or the professions", function()
        local taught = setOf(Data.all)
        for _, name in ipairs(Data.pack.recipes) do
            assert.is_nil(taught[name], name)
        end
    end)

    it("has a display name for every new recipe in every language", function()
        for _, lang in ipairs({ "CH", "CN", "EN", "ES", "FR", "IT", "JP", "PTBR", "RU", "UA" }) do
            local text = LuaSource.read(LUA .. "shared/Translate/" .. lang .. "/Recipes.json")
            for name in pairs(mine) do
                assert.truthy(text:find('"' .. name .. '"%s*:'), lang .. " has no name for " .. name)
            end
        end
    end)
end)

insulate("recipe callbacks", function()
    rawset(_G, "isServer", function() return false end)
    rawset(_G, "isClient", function() return false end)
    rawset(_G, "instanceof", function(obj, class) return class == "Food" and obj.food == true end)
    local synced = {}
    rawset(_G, "syncItemFields", function(_, item) synced[#synced + 1] = item end)
    package.loaded["ExtensiveHealthRedone/Game/RecipeCode"] = nil
    require("ExtensiveHealthRedone/Game/RecipeCode")
    local Code = _G.EHRRecipeCode

    local function item(fullType, opts)
        opts = opts or {}
        return {
            food = opts.food,
            uses = opts.uses,
            getFullType = function() return fullType end,
            isFresh = function() return opts.fresh == true end,
            isRotten = function() return opts.rotten == true end,
            getCurrentUses = function(self) return self.uses end,
            getMaxUses = function() return 5 end,
            setCurrentUses = function(self, n) self.uses = n end,
        }
    end

    local function javaList(items)
        return { size = function() return #items end, get = function(_, i) return items[i + 1] end }
    end

    it("pass anything that is not a listed herb", function()
        assert.is_true(Code.FreshMedicinalIngredients(item("Base.MortarPestle")))
        assert.is_true(Code.FreshMedicinalIngredients(item("Base.Honey", { food = true })))
        assert.is_true(Code.FreshMedicinalIngredients(nil))
    end)

    it("pass a fresh herb and refuse a stale or rotten one", function()
        assert.is_true(Code.FreshMedicinalIngredients(item("Base.Chamomile", { food = true, fresh = true }), nil))
        assert.is_false(Code.FreshMedicinalIngredients(item("Base.Chamomile", { food = true, fresh = false })))
        assert.is_false(Code.FreshMedicinalIngredients(item("Base.BerryBlue",
            { food = true, fresh = true, rotten = true })))
    end)

    it("pass a listed type that is not food", function()
        assert.is_true(Code.FreshMedicinalIngredients(item("Base.Garlic", { food = false })))
    end)

    it("add one use to the kept pack, never past full", function()
        local pack = item(Data.pack.item, { uses = 3 })
        local data = { getAllKeepInputItems = function() return javaList({ item("Base.Bandage"), pack }) end }
        Code.AddBandageToPack(data, {})
        assert.equal(4, pack.uses)
        pack.uses = 5
        Code.AddBandageToPack(data, {})
        assert.equal(5, pack.uses)
        assert.equal(0, #synced)
    end)

    it("start a pack with one bandage and sync it on a dedicated server", function()
        _G.isServer = function() return true end
        local pack = item(Data.pack.item, { uses = 5 })
        Code.StartBandagePack({ getAllCreatedItems = function() return javaList({ pack }) end }, {})
        _G.isServer = function() return false end
        assert.equal(1, pack.uses)
        assert.equal(pack, synced[1])
    end)
end)

insulate("auto-learn safety net on the authority", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    _G.Perks.PlantScavenging = { name = "PlantScavenging" }

    local function addPlayer(doctor, foraging)
        local player = game.addPlayer({})
        player.levels = { Doctor = doctor, PlantScavenging = foraging }
        player.known = {}
        player.learned = 0
        rawset(player, "getPerkLevel", function(self, perk) return self.levels[perk.name] end)
        function player:isRecipeActuallyKnown(name) return self.known[name] == true end
        function player:learnRecipe(name)
            self.known[name] = true
            self.learned = self.learned + 1
        end
        return player
    end

    local low = addPlayer(6, 3)
    local high = addPlayer(7, 4)
    high.known.MakeRelaxantTea = true
    require("ExtensiveHealthRedone/Server/Main")
    local ServerRecipes = require("ExtensiveHealthRedone/Server/Recipes")
    game.events.OnGameStart.trigger()

    it("teaches the missing recipes when a qualifying player attaches, once", function()
        game.advance(3)
        assert.equal(16, high.learned)
        assert.equal(0, low.learned)
        game.advance(10)
        assert.equal(16, high.learned)
    end)

    it("teaches on a level-up past the threshold", function()
        low.levels.PlantScavenging = 4
        game.advance(2)
        assert.equal(17, low.learned)
    end)

    it("syncs the known recipes on a dedicated server only when something was learned", function()
        local syncs = {}
        rawset(_G, "sendSyncPlayerFields", function(_, fields) syncs[#syncs + 1] = fields end)
        _G.isServer = function() return true end
        local fresh = addPlayer(6, 4)
        assert.equal(17, #ServerRecipes.grantAutoLearned(fresh))
        assert.equal(0, #ServerRecipes.grantAutoLearned(fresh))
        _G.isServer = function() return false end
        assert.same({ 1 }, syncs)
    end)
end)
