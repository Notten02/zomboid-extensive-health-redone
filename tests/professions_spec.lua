-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The fake vanilla screens and tokens are deliberately partial.
---@diagnostic disable: missing-fields
-- EHR Doctor and EHR Surgeon: the knowledge grant as a pure rule, then on the authority against the fake game; the
-- doctor outfit alias and the Patient Zero trait lists rebuilt after a custom sandbox is set.
local Professions = require("ExtensiveHealthRedone/Data/Professions")
local Legacy = require("ExtensiveHealthRedone/Data/LegacyEHR")
local Knowledge = require("ExtensiveHealthRedone/Conditions/Knowledge")
local Transfusion = require("ExtensiveHealthRedone/Blood/Transfusion")
local Schema = require("ExtensiveHealthRedone/Core/Schema")

local function newState()
    return Schema.new({ int = function(lo) return lo end })
end

describe("profession knowledge grant", function()
    it("grants the same professions the importer accepts from v0.9", function()
        assert.same(Legacy.PROFESSION_GRANTS, Professions.GRANTS)
        for _, id in ipairs(Professions.IDS) do
            assert.is_true(Professions.GRANTS[id])
        end
    end)

    it("grants an EHR Doctor and an EHR Surgeon once, with blood types", function()
        for _, id in ipairs({ "ehrdoctor", "ehrsurgeon" }) do
            local state = newState()
            assert.is_true(Professions.grantKnowledge(state, id))
            assert.equal(id, state.knowledge.professionGrant)
            assert.is_true(state.knowledge.diseases.blood_types)
            assert.is_false(Professions.grantKnowledge(state, id))
        end
    end)

    it("grants nothing to vanilla professions or none", function()
        for _, id in ipairs({ "doctor", "nurse", "unemployed", "", false }) do
            local state = newState()
            assert.is_false(Professions.grantKnowledge(state, id or nil))
            assert.is_nil(state.knowledge.professionGrant)
            assert.is_nil(state.knowledge.diseases.blood_types)
        end
    end)

    it("keeps an imported grant and never revokes", function()
        local state = newState()
        state.knowledge.professionGrant = "ehrsurgeon"
        assert.is_true(Professions.grantKnowledge(state, "ehrdoctor"))      -- only blood_types is added
        assert.equal("ehrsurgeon", state.knowledge.professionGrant)
        assert.is_false(Professions.grantKnowledge(state, nil))
        assert.equal("ehrsurgeon", state.knowledge.professionGrant)
        assert.is_true(state.knowledge.diseases.blood_types)
    end)

    it("names every condition but Knox, and lets a First Aid 6 doctor judge blood types", function()
        local state = newState()
        Professions.grantKnowledge(state, "ehrdoctor")
        local cold = Knowledge.of(state, { knowledge = "common_cold" }, 6)
        assert.is_true(cold.name)
        assert.is_true(cold.progress)
        assert.is_false(Knowledge.of(state, { knowledge = Knowledge.KNOX }, 10).name)
        assert.is_true(Transfusion.knowsTypes(state.knowledge, 6))
        assert.is_false(Transfusion.knowsTypes(newState().knowledge, 6))
    end)
end)

-- Fake profession tokens: tables with getName, compared by identity like the registry objects.
-- A profession token: getName(), and tostring() like a Java object's toString().
local function token(name)
    return setmetatable({ getName = function() return name end }, { __tostring = function() return name end })
end

insulate("single-player wiring: professions", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    game.sandbox.DebugMode = true
    local tokens = { ehrdoctor = token("ehrdoctor"), ehrsurgeon = token("ehrsurgeon") }
    _G.EHRCharacterProfessions = tokens
    local vanillaDoctor = token("doctor")

    local function hire(profession)
        local player = game.addPlayer({})
        ---@diagnostic disable-next-line: duplicate-set-field
        player.getDescriptor = function()
            return { isCharacterProfession = function(_, t) return t == profession end }
        end
        return player
    end

    local doctor = hire(tokens.ehrdoctor)
    local surgeon = hire(tokens.ehrsurgeon)
    local plain = hire(vanillaDoctor)
    require("ExtensiveHealthRedone/Server/Main")
    local Client = require("ExtensiveHealthRedone/Client/Client")
    game.events.OnGameStart.trigger()
    game.advance(2)

    local function knowledge(player)
        return player.modData.ExtensiveHealthRedone.knowledge
    end

    it("grants EHR Doctor and EHR Surgeon disease and blood type knowledge on the authority", function()
        assert.equal("ehrdoctor", knowledge(doctor).professionGrant)
        assert.equal("ehrsurgeon", knowledge(surgeon).professionGrant)
        assert.is_true(knowledge(doctor).diseases.blood_types)
        assert.is_nil(knowledge(plain).professionGrant)
        assert.is_nil(knowledge(plain).diseases.blood_types)
    end)

    it("syncs the grant to the owning client", function()
        assert.equal("ehrdoctor", Client.section(doctor, "knowledge").professionGrant)
    end)

    it("debug: resets the grant (given back next step) and grants doctor knowledge to anyone", function()
        Client.send(doctor, "debug.professionKnowledge", { action = "reset" })
        assert.is_nil(knowledge(doctor).professionGrant)
        game.advance(1)
        assert.equal("ehrdoctor", knowledge(doctor).professionGrant)
        Client.send(plain, "debug.professionKnowledge", { action = "doctor" })
        assert.equal("ehrdoctor", knowledge(plain).professionGrant)
    end)
end)

insulate("character creation: profession outfits", function()
    local FakeGame = require("support/fake_game")
    FakeGame.install()
    local Data = require("ExtensiveHealthRedone/Data/Professions")
    local custom = { Female = {} }
    _G.ClothingSelectionDefinitions = { doctor = { Female = {} }, ehrsurgeon = custom }
    _G.EHRCharacterProfessions = { ehrdoctor = token("ExtensiveHealth:ehrdoctor"), ehrsurgeon = token("ehrsurgeon") }
    require("ExtensiveHealthRedone/Client/Professions")

    it("puts our outfits under every name the game may look up, keeping another mod's outfit", function()
        local defs = _G.ClothingSelectionDefinitions --[[@as table]]
        assert.equal(Data.OUTFITS.ehrdoctor, defs.ehrdoctor)
        assert.equal(Data.OUTFITS.ehrdoctor, defs["ExtensiveHealth:ehrdoctor"])
        assert.equal(Data.OUTFITS.ehrdoctor, defs["extensivehealth:ehrdoctor"])
        assert.equal(Data.OUTFITS.ehrsurgeon, defs["extensivehealth:ehrsurgeon"])
        assert.equal(custom, defs.ehrsurgeon)
    end)

    it("dresses both in a lab coat, the surgeon in scrubs", function()
        assert.same({ "Base.JacketLong_Doctor" }, Data.OUTFITS.ehrdoctor.Female.JacketSuit.items)
        assert.same({ "Base.JacketLong_Doctor" }, Data.OUTFITS.ehrsurgeon.Female.JacketSuit.items)
        assert.same({ "Base.Shirt_Scrubs" }, Data.OUTFITS.ehrsurgeon.Female.Shirt.items)
    end)

    -- Every item must exist in vanilla 42.21, or the creator silently skips it (instanceItem returns nil).
    it("names only clothing that exists in vanilla", function()
        local path = (os.getenv("PZ_MEDIA") or "/mnt/games/Steam/steamapps/common/ProjectZomboid/projectzomboid/media")
            .. "/scripts/generated/items/clothing.txt"
        local f = io.open(path, "rb")
        if not f then
            ---@diagnostic disable-next-line: missing-parameter
            pending("vanilla scripts not installed")
            return
        end
        local text = f:read("*a")
        f:close()
        for _, id in ipairs(Data.IDS) do
            for location, entry in pairs(Data.OUTFITS[id].Female) do
                for _, fullType in ipairs(entry.items) do
                    local name = fullType:match("^Base%.(.+)$")
                    assert.truthy(name and text:find("\n%s*item " .. name .. "%s*\n"), id .. " " .. location .. " " .. fullType)
                end
            end
        end
    end)
end)

insulate("character creation: Patient Zero after a custom sandbox", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    local order = {}
    local screen = { repopulateTraitLists = function() order[#order + 1] = "repopulate" end }
    _G.MainScreen = { instance = { charCreationProfession = screen } }
    _G.SandboxOptionsScreen = { setSandboxVars = function() order[#order + 1] = "set" end }
    _G.CharacterCreationProfession = { populateTraitList = function() end }
    require("ExtensiveHealthRedone/Client/PatientZero")
    game.events.OnGameBoot.trigger()

    it("rebuilds the trait lists right after the sandbox values are set", function()
        _G.SandboxOptionsScreen.setSandboxVars({})
        assert.same({ "set", "repopulate" }, order)
    end)
end)
