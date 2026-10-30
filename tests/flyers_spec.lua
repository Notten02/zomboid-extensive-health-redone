-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The fake vanilla actions and items are deliberately partial.
---@diagnostic disable: missing-fields
-- Disease flyers, the Wild Plants guide and the recipe guides: the item table, the pure learning rules on a test
-- context, then the server wiring against the fake game.
local FlyerData = require("ExtensiveHealthRedone/Data/Flyers")
local Learn = require("ExtensiveHealthRedone/Knowledge/Learn")
local Knowledge = require("ExtensiveHealthRedone/Conditions/Knowledge")
local Tables = require("ExtensiveHealthRedone/Core/Tables")
local LuaSource = require("LuaSource")
local Sim = require("support/sim")

local MEDIA = "Contents/mods/ExtensiveHealthRedone/42/media/"
local UI_JSON = MEDIA .. "lua/shared/Translate/EN/UI.json"

local function uiKeys()
    local keys = {}
    for key in LuaSource.read(UI_JSON):gmatch('"([%w_]+)"%s*:') do
        keys[key] = true
    end
    return keys
end

-- item name -> { field = value } from a script file (only the fields this spec reads).
local function scriptItems(path)
    local items = {}
    local text = LuaSource.read(path)
    for name, body in text:gmatch("item%s+([%w_]+)%s*(%b{})") do
        items[name] = {
            learned = body:match("LearnedRecipes%s*=%s*([^,\n]+)"),
            literature = body:find("ItemType%s*=%s*base:literature") ~= nil,
        }
    end
    return items
end

local function context()
    return Sim.context({})
end

local function sent(p, command)
    local found = {}
    for _, m in ipairs(p.sent) do
        if m[1] == command then
            found[#found + 1] = m[2]
        end
    end
    return found
end

describe("flyer items", function()
    local items = scriptItems(MEDIA .. "scripts/EHR_Flyers.txt")

    it("map every disease flyer in the script, and nothing else", function()
        local scripted = {}
        for name in pairs(items) do
            if name:find("^DiseaseFlyer_") then
                scripted[#scripted + 1] = name
            end
        end
        table.sort(scripted)
        assert.same(scripted, Tables.sortedKeys(FlyerData.DISEASES))
        assert.equal(19, #scripted)
    end)

    it("never teach Knox, tuberculosis or influenza", function()
        for name, id in pairs(FlyerData.DISEASES) do
            assert.is_true(id ~= Knowledge.KNOX, name)
            assert.is_nil(id:find("tuberculosis") or id:find("flu"), name)
        end
        assert.is_nil(items.DiseaseFlyer_Tuberculosis)
        assert.is_nil(items.DiseaseFlyer_Flu)
        assert.is_nil(items.DiseaseFlyer_KnoxInfection)
    end)

    it("are literature read with vanilla's ISReadABook", function()
        for name in pairs(FlyerData.DISEASES) do
            assert.is_true(items[name].literature, name)
        end
        assert.is_true(items[FlyerData.WILD_PLANTS].literature)
    end)

    it("have a translated name for every id", function()
        local keys = uiKeys()
        for _, id in pairs(FlyerData.DISEASES) do
            assert.truthy(keys[FlyerData.nameKey(id)], id)
        end
    end)

    it("look up full types", function()
        assert.same({ kind = "disease", id = "tetanus", name = "UI_EHR_Disease_tetanus" },
            FlyerData.entry("ExtensiveHealth.DiseaseFlyer_Tetanus"))
        assert.same({ kind = "disease", id = "blood_types", name = "UI_EHR_Disease_BloodTypes" },
            FlyerData.entry("ExtensiveHealth.DiseaseFlyer_BloodType"))
        assert.same({ kind = "wildPlants" }, FlyerData.entry("ExtensiveHealth.MedicalWildPlants"))
        assert.is_nil(FlyerData.entry("Base.DiseaseFlyer_Tetanus"))
        assert.is_nil(FlyerData.entry("ExtensiveHealth.EhrRecipeUltimateCraftGuide"))
        assert.is_nil(FlyerData.entry("Base.Newspaper"))
        assert.is_nil(FlyerData.entry(nil))
    end)

    it("teach recipe guides' recipes through vanilla's LearnedRecipes, all of them learnable EHR recipes", function()
        local recipes = {}
        for _, file in ipairs({ "EHR_Recipes.txt", "EHR_SupplyRecipes.txt" }) do
            local text = LuaSource.read(MEDIA .. "scripts/" .. file)
            for name, body in text:gmatch("craftRecipe%s+([%w_]+)%s*(%b{})") do
                recipes[name] = body:find("NeedToBeLearn%s*=%s*true") ~= nil
            end
        end
        local counts = {}
        for _, guide in ipairs(FlyerData.RECIPE_GUIDES) do
            local list = assert(items[guide].learned, guide .. " teaches nothing")
            counts[#counts + 1] = 0
            for name in list:gmatch("[^;%s]+") do
                counts[#counts] = counts[#counts] + 1
                assert.is_true(recipes[name], guide .. " teaches " .. name .. ", which is not a learnable EHR recipe")
            end
        end
        assert.same({ 1, 24 }, counts)
    end)
end)

describe("learning from flyers", function()
    local tetanus = FlyerData.entry("ExtensiveHealth.DiseaseFlyer_Tetanus")

    it("teaches a new id once, with 50 XP and the learned line", function()
        local p = context()
        assert.equal("learned", Learn.read(p, tetanus))
        assert.is_true(p.state.knowledge.diseases.tetanus)
        assert.same({ { "flyer", "tetanus" } }, p.xps)
        assert.same({ { name = "UI_EHR_Disease_tetanus" } }, sent(p, "knowledgeLearned"))
        assert.truthy(p.dirtied.knowledge)

        assert.equal("known", Learn.read(p, tetanus))
        assert.equal(1, #p.xps)
        assert.same({ "UI_EHR_FlyerAlreadyKnown" }, p.said)
    end)

    it("gives no XP for an id the radio already taught", function()
        local p = context()
        p.state.knowledge.diseases.tetanus = true
        assert.equal("known", Learn.read(p, tetanus))
        assert.same({}, p.xps)
    end)

    it("records a self-evident condition and still gives the XP (v0.9)", function()
        local p = context()
        assert.equal("learned", Learn.read(p, FlyerData.entry("ExtensiveHealth.DiseaseFlyer_Hypothermia")))
        assert.is_true(p.state.knowledge.diseases.hypothermia)
        assert.equal(1, #p.xps)
    end)

    it("teaches blood types for transfusion compatibility", function()
        local p = context()
        Learn.read(p, FlyerData.entry("ExtensiveHealth.DiseaseFlyer_BloodType"))
        assert.is_true(p.state.knowledge.diseases.blood_types)
    end)

    it("never teaches Knox", function()
        local p = context()
        assert.equal("refused", Learn.disease(p, Knowledge.KNOX))
        assert.is_nil(p.state.knowledge.diseases[Knowledge.KNOX])
        assert.equal("refused", Learn.disease(p, nil))
    end)

    it("opens the medicinal plant search with the Wild Plants guide, 50 XP the first time", function()
        local p = context()
        local guide = FlyerData.entry("ExtensiveHealth.MedicalWildPlants")
        assert.equal("learned", Learn.read(p, guide))
        assert.is_true(p.state.knowledge.wildPlants)
        assert.same({ { "wildPlants" } }, p.xps)
        assert.same({ "UI_EHR_HerbalSearch_KnowledgeLearned" }, p.said)
        assert.equal("known", Learn.read(p, guide))
        assert.equal(1, #p.xps)
        assert.equal("UI_EHR_HerbalSearch_KnowledgeAlreadyKnown", p.said[2])
    end)
end)

insulate("single-player wiring: flyers", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    game.sandbox.DebugMode = true
    _G.ISReadABook = { complete = function() return true end }

    local Client = require("ExtensiveHealthRedone/Client/Client")
    local player = game.addPlayer({ capabilities = { CanMedicalCheat = true } })
    game.events.OnCreatePlayer.trigger(0, player)
    require("ExtensiveHealthRedone/Server/Main")
    require("ExtensiveHealthRedone/Client/RadioKnowledge")
    game.events.OnGameStart.trigger()
    game.advance(2)

    local function knowledge()
        return player.modData.ExtensiveHealthRedone.knowledge
    end

    local function flyer(name)
        return { getFullType = function() return "ExtensiveHealth." .. name end }
    end

    local function read(name, extra)
        local action = { character = player, item = flyer(name) }
        for k, v in pairs(extra or {}) do
            action[k] = v
        end
        return ISReadABook.complete(action)
    end

    it("teaches the flyer's disease when vanilla finishes reading it, with XP once", function()
        local realGetText = _G.getText
        rawset(_G, "getText", function(key, arg)
            return arg and (key .. "(" .. arg .. ")") or key
        end)
        read("DiseaseFlyer_Sepsis")
        _G.getText = realGetText
        assert.is_true(knowledge().diseases.sepsis)
        assert.equal(50, game.xp[player:getUsername()])
        assert.equal("UI_EHR_FlyerLearned(UI_EHR_Disease_sepsis)", player.said[#player.said])
        read("DiseaseFlyer_Sepsis")
        assert.equal(50, game.xp[player:getUsername()])
    end)

    it("teaches nothing for an interrupted read or another book", function()
        read("DiseaseFlyer_Tetanus", { forceStopped = true })
        assert.is_nil(knowledge().diseases.tetanus)
        local before = Tables.deepCopy(knowledge())
        ISReadABook.complete({ character = player, item = { getFullType = function() return "Base.BookFirstAid1" end } })
        assert.same(before, knowledge())
    end)

    it("opens the plant search with the Wild Plants guide", function()
        read("MedicalWildPlants")
        assert.is_true(knowledge().wildPlants)
        assert.equal(100, game.xp[player:getUsername()])
    end)

    it("forgets flyer and radio knowledge with the debug command, but keeps the Herald's", function()
        knowledge().knoxHerald = true
        knowledge().diseases.knox_infection = true
        knowledge().radioHeard["3:9:XP:4"] = true
        Client.send(player, "debug.knowledge", { action = "forget" })
        assert.same({ knox_infection = true }, knowledge().diseases)
        assert.is_false(knowledge().wildPlants)
        assert.same({}, knowledge().radioHeard)
    end)
end)
