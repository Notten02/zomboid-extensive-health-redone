-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The fake vanilla actions and items are deliberately partial.
---@diagnostic disable: missing-fields
-- Zombie Virus Vaccine beside us (Phase 10, docs/porting/phase10/zombie-virus-vaccine.md): the pure rules first, then the
-- server wiring against the fake game with stand-ins for the two vaccine modules it wraps.
local Knox = require("ExtensiveHealthRedone/Diseases/Knox/Knox")
local Transfusion = require("ExtensiveHealthRedone/Blood/Transfusion")
local BloodData = require("ExtensiveHealthRedone/Data/Blood")
local Blood = require("ExtensiveHealthRedone/Blood/Blood")

describe("Knox progress with Zombie Virus Vaccine", function()
    it("takes the larger of the stat and the timers by default", function()
        assert.equal(0.9, Knox.progress({ level = 0.9, timerProgress = 0.5 }))
        assert.equal(0.5, Knox.progress({ level = 0, timerProgress = 0.5 }))
    end)

    it("follows the timers alone while the mod is on, so a delay shows", function()
        assert.equal(0.5, Knox.progress({ level = 0.9, timerProgress = 0.5, followTimer = true }))
    end)

    it("still reads the stat when there is no timer", function()
        assert.equal(0.9, Knox.progress({ level = 0.9, followTimer = true }))
    end)
end)

describe("a lab blood sample", function()
    local function state(volume)
        return { blood = { volume = volume, max = BloodData.MAX_ML }, identity = { bloodType = "A+" } }
    end

    it("needs half the blood, not the four fifths a bag does", function()
        assert.is_nil(Transfusion.sampleRefusal(state(BloodData.MAX_ML * 0.6)))
        assert.equal("UI_EHR_Transfusion_NotEnoughBloodSafe", Transfusion.sampleRefusal(state(BloodData.MAX_ML * 0.4)))
        assert.equal("UI_EHR_Transfusion_NotEnoughBloodSafe", Transfusion.drawRefusal(state(BloodData.MAX_ML * 0.6)))
    end)

    it("costs the sample volume", function()
        local s = state(4000)
        local dirty = {}
        Transfusion.sample({ state = s, dirty = function(section) dirty[#dirty + 1] = section end })
        assert.equal(4000 - BloodData.SAMPLE_ML, s.blood.volume)
        assert.same({ "blood" }, dirty)
        assert.is_true(Blood.percent(s.blood) > 0.7)
    end)
end)

describe("Knox knowledge from a blood test", function()
    it("unlocks what the Herald unlocks, once", function()
        local dirty = {}
        local p = {
            state = { knowledge = { knoxHerald = false, diseases = {} } },
            dirty = function(section) dirty[#dirty + 1] = section end,
        }
        assert.is_true(Knox.learnFromBloodTest(p))
        assert.is_true(p.state.knowledge.knoxHerald)
        assert.is_true(p.state.knowledge.diseases.knox_infection)
        assert.is_false(Knox.learnFromBloodTest(p))
        assert.is_false(Knox.learnFromHerald(p))
        assert.same({ "knowledge" }, dirty)
    end)
end)

-- Stand-ins for the vaccine mod's two server modules (HealthSystem/LabCollectBloodLogic_Server and BloodTestLogic_Server).
local function installFakeVaccine()
    local calls = { collect = 0, test = 0 }
    local collect = {
        ProcessCollection = function(who, itemType)
            calls.collect = calls.collect + 1
            who.inventory:add(itemType == "LabSyringeReusable" and "LabItems.CmpSyringeReusableWithBlood"
                or "LabItems.CmpSyringeWithBlood")
            return "collected"
        end,
    }
    local test = {
        outcome = "Positive",
        ProcessTest = function()
            calls.test = calls.test + 1
            return package.loaded["HealthSystem/BloodTestLogic_Server"].outcome
        end,
    }
    package.loaded["HealthSystem/LabCollectBloodLogic_Server"] = collect
    package.loaded["HealthSystem/BloodTestLogic_Server"] = test
    return calls, collect, test
end

insulate("single-player wiring: Zombie Virus Vaccine on", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    game.mods.ZVirusVaccine42BETA = true
    local player = game.addPlayer({})
    game.events.OnCreatePlayer.trigger(0, player)
    local calls, collect, test = installFakeVaccine()
    local Client = require("ExtensiveHealthRedone/Client/Client")
    require("ExtensiveHealthRedone/Server/Main")
    require("ExtensiveHealthRedone/Server/Knox")
    local ServerVaccine = require("ExtensiveHealthRedone/Server/ZVirusVaccine")
    game.events.OnGameStart.trigger()
    game.advance(2)

    local notices = {}
    Client.on("notice", function(args) notices[#notices + 1] = args end)

    local function state()
        return player.modData.ExtensiveHealthRedone
    end

    it("wraps the two vaccine functions once, even when both start events fire", function()
        local wrapped = collect.ProcessCollection
        game.events.OnGameStart.trigger()
        assert.equal(wrapped, collect.ProcessCollection)
    end)

    it("takes blood for a sample and stamps the drawer's blood type on it", function()
        state().identity.bloodType = "B-"
        local before = state().blood.volume
        assert.equal("collected", collect.ProcessCollection(player, "LabSyringe"))
        assert.equal(1, calls.collect)
        assert.equal(before - BloodData.SAMPLE_ML, state().blood.volume)
        local sample = player.inventory:getFirstEvalRecurse(function(item)
            return item:getFullType() == "LabItems.CmpSyringeWithBlood"
        end)
        assert.equal("B-", sample:getModData()[BloodData.DONOR_KEY])
    end)

    it("stamps only the new sample, never one drawn earlier", function()
        state().identity.bloodType = "O+"
        local old = player.inventory:add("LabItems.CmpSyringeWithBlood")
        collect.ProcessCollection(player, "LabSyringe")
        assert.is_nil(old:getModData()[BloodData.DONOR_KEY])
    end)

    it("handles the reusable syringe too", function()
        local before = state().blood.volume
        collect.ProcessCollection(player, "LabSyringeReusable")
        assert.equal(before - BloodData.SAMPLE_ML, state().blood.volume)
    end)

    it("refuses a draw from someone with too little blood and leaves the vaccine mod's code alone", function()
        state().blood.volume = BloodData.MAX_ML * 0.3
        local ran, volume = calls.collect, state().blood.volume
        assert.is_nil(collect.ProcessCollection(player, "LabSyringe"))
        assert.equal(ran, calls.collect)
        assert.equal(volume, state().blood.volume)
        assert.equal("UI_EHR_Transfusion_NotEnoughBloodSafe", notices[#notices].key)
        state().blood.volume = BloodData.MAX_ML
    end)

    it("teaches Knox knowledge from a positive or negative test, but not from a spoiled sample", function()
        test.outcome = "InvalidSample"
        assert.equal("InvalidSample", test.ProcessTest(player, "CmpSyringeWithBlood"))
        assert.is_false(state().knowledge.knoxHerald)
        test.outcome = "Negative"
        assert.equal("Negative", test.ProcessTest(player, "CmpSyringeWithBlood"))
        assert.is_true(state().knowledge.knoxHerald)
        assert.is_true(state().knowledge.diseases.knox_infection)
    end)

    it("shows a delayed infection at the timer's progress, not the stat's", function()
        state().knowledge.knoxHerald = false
        -- 30 of 60 hours gone on the timer, but the stat still says 90 %.
        player.body.knox = { infected = true, time = game.minutes / 60 - 30, duration = 60 }
        player.body:part("Hand_L").knox = true
        player.stats.ZOMBIE_INFECTION = 90
        game.advance(2)
        assert.equal(3, state().conditions.active.knox_infection.stage)
    end)

    it("is not reinstalled after a reset when the mod is off", function()
        ServerVaccine.reset()
        game.mods.ZVirusVaccine42BETA = nil
        assert.is_false(ServerVaccine.install())
    end)
end)

insulate("single-player wiring: Zombie Virus Vaccine off", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    local player = game.addPlayer({})
    game.events.OnCreatePlayer.trigger(0, player)
    local calls, collect, test = installFakeVaccine()
    local original = collect.ProcessCollection
    require("ExtensiveHealthRedone/Server/Main")
    require("ExtensiveHealthRedone/Server/Knox")
    game.events.OnGameStart.trigger()
    game.advance(2)

    it("leaves the vaccine functions and the blood alone", function()
        assert.equal(original, collect.ProcessCollection)
        local before = player.modData.ExtensiveHealthRedone.blood.volume
        collect.ProcessCollection(player, "LabSyringe")
        assert.equal(before, player.modData.ExtensiveHealthRedone.blood.volume)
        test.ProcessTest(player, "CmpSyringeWithBlood")
        assert.is_false(player.modData.ExtensiveHealthRedone.knowledge.knoxHerald)
        assert.equal(1, calls.collect)
    end)

    it("keeps the larger of stat and timers for the Knox display", function()
        player.body.knox = { infected = true, time = game.minutes / 60 - 30, duration = 60 }
        player.body:part("Hand_L").knox = true
        player.stats.ZOMBIE_INFECTION = 90
        game.advance(2)
        assert.equal(4, player.modData.ExtensiveHealthRedone.conditions.active.knox_infection.stage)
    end)
end)

insulate("single-player wiring: Zombie Virus Vaccine's modules changed", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    game.mods.ZVirusVaccine42BETA = true
    local player = game.addPlayer({})
    game.events.OnCreatePlayer.trigger(0, player)
    package.loaded["HealthSystem/LabCollectBloodLogic_Server"] = { Renamed = function() end }
    package.preload["HealthSystem/BloodTestLogic_Server"] = function() error("module gone") end
    require("ExtensiveHealthRedone/Server/Main")
    game.events.OnGameStart.trigger()
    game.advance(2)

    it("logs a warning for each and carries on", function()
        assert.is_true(game.logged("not found; its ProcessCollection is left alone"))
        assert.is_true(game.logged("not found; its ProcessTest is left alone"))
    end)
end)
