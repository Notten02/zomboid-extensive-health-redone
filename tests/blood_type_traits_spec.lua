-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Blood type traits: picking a blood type at character creation instead of rolling it (Core/BloodTypes chosen,
-- Server/PlayerState), the trait scripts and texts, and hiding the traits with BloodTypeTraitsDisabled
-- (Client/BloodTypeTraits).
local LuaSource = require("LuaSource")
local BloodTypes = require("ExtensiveHealthRedone/Core/BloodTypes")
local Data = require("ExtensiveHealthRedone/Data/BloodTypes")
local KnoxData = require("ExtensiveHealthRedone/Diseases/Knox/Data")

local MEDIA = "Contents/mods/ExtensiveHealthRedone/42/media/"

local function tokens()
    local t = {}
    for _, traitKey in pairs(Data.traits) do
        t[traitKey] = "ExtensiveHealth:" .. traitKey
    end
    return t
end

describe("BloodTypes.chosen", function()
    it("gives the type whose trait the character has, or nil", function()
        for _, t in ipairs(Data.types) do
            assert.equal(t, BloodTypes.chosen(function(key) return key == Data.traits[t] end))
        end
        assert.is_nil(BloodTypes.chosen(function() return false end))
    end)

    it("takes the first in type order when a character carries several", function()
        local has = { [Data.traits["AB+"]] = true, [Data.traits["O+"]] = true }
        assert.equal("O+", BloodTypes.chosen(function(key) return has[key] == true end))
    end)
end)

describe("blood type trait definitions", function()
    local traits = LuaSource.read(MEDIA .. "scripts/EHR_Traits.txt")
    local registries = LuaSource.read(MEDIA .. "registries.lua")
    local ui = LuaSource.read(MEDIA .. "lua/shared/Translate/EN/UI.json")

    local function block(traitKey)
        return traits:match("character_trait_definition ExtensiveHealth:" .. traitKey .. "%s*(%b{})")
    end

    it("define, register and name one positive-cost trait per type, each excluding all the others", function()
        local count = 0
        for _, t in ipairs(Data.types) do
            local key = Data.traits[t]
            count = count + 1
            local def = block(key)
            assert.truthy(def, "no trait for " .. t)
            assert.truthy(registries:find('EHRCharacterTraits.' .. key .. ' = CharacterTrait.register("ExtensiveHealth:'
                .. key .. '")', 1, true), key .. " is not registered")
            local cost = tonumber(def:match("Cost = (%-?%d+)"))
            assert.truthy(cost and cost > 0, key .. " costs " .. tostring(cost))
            local name = def:match("UIName = ([%w_]+)")
            local desc = def:match("UIDescription = ([%w_]+)")
            assert.truthy(ui:find('"' .. name .. '"%s*:%s*"[^"]*' .. t:gsub("%p", "%%%0")), name .. " lacks " .. t)
            assert.truthy(ui:find('"' .. desc .. '"%s*:'), desc .. " is missing")
            local exclusive = {}
            for other in (def:match("MutuallyExclusiveTraits = ([^,\n]+)") or ""):gmatch("ExtensiveHealth:(%w+)") do
                exclusive[other] = true
            end
            for _, o in ipairs(Data.types) do
                assert.equal(o ~= t, exclusive[Data.traits[o]] == true, key .. " and " .. Data.traits[o])
            end
        end
        assert.equal(8, count)
    end)

    it("vary in cost, so the better types cost more", function()
        local costs = {}
        for _, t in ipairs(Data.types) do
            costs[tonumber(block(Data.traits[t]):match("Cost = (%-?%d+)"))] = true
        end
        local distinct = 0
        for _ in pairs(costs) do distinct = distinct + 1 end
        assert.truthy(distinct > 1)
    end)

    it("describe the gene therapy chance the Knox rules use", function()
        for _, t in ipairs(Data.types) do
            local desc = block(Data.traits[t]):match("UIDescription = ([%w_]+)")
            local text = ui:match('"' .. desc .. '"%s*:%s*"([^"]*)"')
            assert.truthy(text:find(KnoxData.GENE_THERAPY_CHANCE[t] .. "%%", 1, true), desc .. ": " .. text)
        end
    end)
end)

insulate("PlayerState: the blood type trait sets the blood type", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    _G.EHRCharacterTraits = tokens()
    local Schema = require("ExtensiveHealthRedone/Core/Schema")
    local PlayerState = require("ExtensiveHealthRedone/Server/PlayerState")

    local function withTrait(t)
        local player = game.addPlayer({})
        if t then
            player.traits[EHRCharacterTraits[Data.traits[t]]] = true
        end
        return player
    end

    after_each(function()
        game.sandbox.BloodTypeTraitsDisabled = nil
    end)

    it("gives a new character the type it picked", function()
        for _, t in ipairs(Data.types) do
            assert.equal(t, PlayerState.load(withTrait(t), "new" .. t).identity.bloodType)
        end
    end)

    it("rolls for a new character without the trait", function()
        assert.is_true(BloodTypes.isValid(PlayerState.load(withTrait(nil), "rolled").identity.bloodType))
    end)

    it("sets it on an existing state too (a trait added later)", function()
        local player = withTrait(nil)
        local state = PlayerState.load(player, "later")
        state.identity.bloodType = "AB-"
        player.traits[EHRCharacterTraits[Data.traits["O+"]]] = true
        assert.equal("O+", PlayerState.load(player, "later").identity.bloodType)
        assert.equal("O+", player:getModData()[Schema.ROOT_KEY].identity.bloodType)
    end)

    it("ignores the trait while BloodTypeTraitsDisabled is on, and keeps a type it already set", function()
        game.sandbox.BloodTypeTraitsDisabled = true
        local player = withTrait("O-")
        local state = PlayerState.load(player, "disabled")
        state.identity.bloodType = "B+"
        assert.equal("B+", PlayerState.load(player, "disabled").identity.bloodType)

        game.sandbox.BloodTypeTraitsDisabled = false
        local picked = withTrait("A-")
        assert.equal("A-", PlayerState.load(picked, "kept").identity.bloodType)
        game.sandbox.BloodTypeTraitsDisabled = true
        assert.equal("A-", PlayerState.load(picked, "kept").identity.bloodType)
    end)
end)

insulate("character creation: blood type traits with BloodTypeTraitsDisabled", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    _G.EHRCharacterTraits = tokens()
    _G.EHRCharacterTraits.patientzero = "ExtensiveHealth:patientzero"
    -- The options being set up on the new-game screens (CreationTraits reads these, not SandboxVars).
    _G.getSandboxOptions = function()
        return {
            getOptionByName = function(_, name)
                local option = name:match("^ExtensiveHealthRework%.(.+)$")
                return { getValue = function() return game.sandbox[option] == true end }
            end,
        }
    end
    _G.SandboxOptionsScreen = { setSandboxVars = function() end }
    _G.CharacterCreationProfession = { populateTraitList = function() end }
    local BloodTypeTraits = require("ExtensiveHealthRedone/Client/BloodTypeTraits")
    require("ExtensiveHealthRedone/Client/PatientZero")
    game.events.OnGameBoot.trigger()

    local function definition(token, cost)
        return { getType = function() return token end, getCost = function() return cost end }
    end

    local function listbox(entries)
        local list = { items = {} }
        for _, e in ipairs(entries) do
            list.items[#list.items + 1] = { text = e[1], item = definition(e[2], e[3]) }
        end
        function list:removeMatchingItems(text)
            for i = #self.items, 1, -1 do
                if self.items[i].text == text then
                    table.remove(self.items, i)
                end
            end
        end
        return list
    end

    local function texts(list)
        local out = {}
        for _, e in ipairs(list.items) do
            out[#out + 1] = e.text
        end
        return out
    end

    local function populate()
        local list = listbox({
            { "Blood Type: O-", EHRCharacterTraits.bloodtypeoneg, 3 },
            { "Blood Type: AB+", EHRCharacterTraits.bloodtypeabpos, 3 },
            { "Patient Zero", EHRCharacterTraits.patientzero, 20 },
            { "Athletic", "base:athletic", 6 },
        })
        local screen = {
            pointToSpend = 0,
            listboxTraitSelected = listbox({
                { "Blood Type: O+", EHRCharacterTraits.bloodtypeopos, 4 },
                { "Strong", "base:strong", 10 },
            }),
        }
        _G.CharacterCreationProfession.populateTraitList(screen, list)
        return screen, list
    end

    after_each(function()
        game.sandbox.BloodTypeTraitsDisabled = nil
    end)

    it("recognises every blood type trait and nothing else", function()
        for _, traitKey in pairs(Data.traits) do
            assert.is_true(BloodTypeTraits.is(definition(EHRCharacterTraits[traitKey], 1)), traitKey)
        end
        assert.is_false(BloodTypeTraits.is(definition(EHRCharacterTraits.patientzero, 20)))
        assert.is_false(BloodTypeTraits.is(definition("base:athletic", 6)))
    end)

    it("offers them while the option is off", function()
        local screen, list = populate()
        assert.same({ "Blood Type: O-", "Blood Type: AB+", "Patient Zero", "Athletic" }, texts(list))
        assert.same({ "Blood Type: O+", "Strong" }, texts(screen.listboxTraitSelected))
        assert.equal(0, screen.pointToSpend)
    end)

    it("hides them and refunds a chosen one while the option is on", function()
        game.sandbox.BloodTypeTraitsDisabled = true
        local screen, list = populate()
        assert.same({ "Patient Zero", "Athletic" }, texts(list))
        assert.same({ "Strong" }, texts(screen.listboxTraitSelected))
        assert.equal(4, screen.pointToSpend)
    end)
end)
