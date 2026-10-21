-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The fake vanilla actions and the fake ICL API are deliberately partial.
---@diagnostic disable: missing-fields, duplicate-set-field
-- Body temperature: the fever hold (contributions become one fever that rises by the disease's step and breaks at
-- 1 deg C per game hour), the Warming Pack, food temperature, the pre-disease stages, Indoor Climate Lite air, and
-- the server holding vanilla's TEMPERATURE between the floor and ceiling every tick (Body/Temperature,
-- Body/TemperatureStages, Server/Temperature, Server/IndoorClimate).
local Temperature = require("ExtensiveHealthRedone/Body/Temperature")
local Stages = require("ExtensiveHealthRedone/Body/TemperatureStages")
local Doses = require("ExtensiveHealthRedone/Medication/Doses")
local MedData = require("ExtensiveHealthRedone/Medication/Data")
local Exposure = require("ExtensiveHealthRedone/Diseases/Weather/Exposure")
local Meters = require("ExtensiveHealthRedone/Diseases/Weather/Meters")
local defs = require("ExtensiveHealthRedone/Conditions/Registry")
local Symptoms = require("ExtensiveHealthRedone/Conditions/Symptoms")
local Sim = require("support/sim")

local function context(opts)
    local p = Sim.context(opts)
    p.facts.stats.TEMPERATURE = 37
    return p
end

-- One simulation minute in which fn (optional) asks for a fever.
local function minute(p, fn)
    Sim.step(p)
    if fn then
        fn(p)
    end
    Temperature.update(p, 1)
end

local function fever(p)
    return p.state.temperature.fever
end

describe("fever hold", function()
    it("rises from the body's temperature by the asked step, then holds the target", function()
        local p = context()
        minute(p, function(q) Symptoms.applyFever(q, "sepsis", 38.6, 0.5) end)
        assert.near(37.5, fever(p), 1e-9)
        assert.equal("sepsis", p.state.temperature.source)
        for _ = 1, 10 do
            minute(p, function(q) Symptoms.applyFever(q, "sepsis", 38.6, 0.5) end)
        end
        assert.near(38.6, fever(p), 1e-9)
    end)

    it("owns TEMPERATURE: the stat writer gets no contribution", function()
        local p = context()
        minute(p, function(q) Symptoms.applyFever(q, "sepsis", 38.6, 0.5) end)
        assert.same({}, p.stats:touched())
    end)

    it("follows the highest target when several sources ask", function()
        local p = context()
        p.state.temperature.fever = 38
        minute(p, function(q)
            Symptoms.applyFever(q, "common_cold", 37.8, 0.1)
            Symptoms.applyFever(q, "pneumonia", 39.5, 0.1)
        end)
        assert.near(38.1, fever(p), 1e-9)
        assert.equal("pneumonia", p.state.temperature.source)
    end)

    it("breaks at 1 deg C per game hour once nothing asks, then lets vanilla take over", function()
        local p = context()
        p.state.temperature.fever = 39
        for _ = 1, 60 do
            minute(p)
        end
        assert.near(38, fever(p), 1e-6)
        for _ = 1, 61 do
            minute(p)
        end
        assert.is_false(fever(p))
        assert.is_false(p.state.temperature.source)
    end)

    it("breaks at the same pace toward a lower target (relief, a milder stage)", function()
        local p = context()
        p.state.temperature.fever = 39.4
        minute(p, function(q) Symptoms.applyFever(q, "sepsis", 38, 0.5) end)
        assert.near(39.4 - 1 / 60, fever(p), 1e-9)
    end)

    it("doesn't start a fever when the body is already that hot", function()
        local p = context()
        p.facts.stats.TEMPERATURE = 38.5
        minute(p, function(q) Symptoms.applyFever(q, "common_cold", 38, 0.1) end)
        assert.is_false(fever(p))
    end)

    it("cools faster when something cools the body (heat stroke in a cold bath)", function()
        local p = context()
        p.state.temperature.fever = 40.5
        minute(p, function(q) q.stats:lower("TEMPERATURE", "heat_stroke", 37.2, 0.05) end)
        assert.near(40.5 - 1 / 60 - 0.05, fever(p), 1e-9)
    end)

    it("scales rises and breaks with TemperatureChangeSpeed", function()
        local p = context({ sandbox = { TemperatureChangeSpeed = 2 } })
        minute(p, function(q) Symptoms.applyFever(q, "sepsis", 38.6, 0.5) end)
        assert.near(38, fever(p), 1e-9)
        minute(p)
        assert.near(38 - 2 / 60, fever(p), 1e-9)
    end)

    it("adds a spike on top of the held fever, which then breaks normally", function()
        local p = context()
        Temperature.spike(p, "staleBlood", 2)
        assert.near(39, fever(p), 1e-9)
        p.state.temperature.fever = 38
        Temperature.spike(p, "staleBlood", 2)
        assert.near(40, fever(p), 1e-9)
    end)

    it("syncs when the shown temperature changes by 0.1 deg C", function()
        local p = context()
        p.state.temperature.fever = 39
        minute(p)
        assert.equal(1, p.dirtied.temperature)
        minute(p)
        assert.equal(1, p.dirtied.temperature)
        for _ = 1, 5 do
            minute(p)
        end
        assert.equal(2, p.dirtied.temperature)
    end)
end)

describe("warming pack", function()
    local pack = MedData.byType["ExtensiveHealth.WarmingPack"]

    local function packed(opts)
        local p = context(opts)
        p.state.meds.effects.warming = { id = "warming", left = 120, data = {} }
        return p
    end

    it("warms toward 37 deg C at 3.2 deg C per hour, never above", function()
        local p = packed()
        p.facts.stats.TEMPERATURE = 35
        minute(p)
        assert.near(35 + 3.2 / 60, p.state.temperature.floor, 1e-9)
        p.state.temperature.warm = 36.99
        minute(p)
        assert.equal(37, p.state.temperature.floor)
        p.facts.stats.TEMPERATURE = 37.5            -- warmer than the pack: a floor never cools
        minute(p)
        assert.equal(37, p.state.temperature.floor)
    end)

    it("stops when the pack runs out, and a fever above it wins", function()
        local p = packed()
        p.facts.stats.TEMPERATURE = 36
        p.state.temperature.fever = 38
        minute(p)
        assert.equal(38 - 1 / 60, p.state.temperature.floor)
        p.state.meds.effects.warming = nil
        p.state.temperature.fever = false
        minute(p)
        assert.is_false(p.state.temperature.warm)
        assert.is_false(p.state.temperature.floor)
    end)

    it("does nothing, and is refused, while BodyTemperatureEnabled is off", function()
        local p = packed({ sandbox = { BodyTemperatureEnabled = false } })
        p.facts.stats.TEMPERATURE = 35
        minute(p)
        assert.is_false(p.state.temperature.floor)
        local off = function(name, default) if name == "BodyTemperatureEnabled" then return false end return default end
        assert.equal("UI_EHR_MedReason_TemperatureDisabled", Doses.refusal(p.state, pack, { sandbox = off }))
    end)

    it("is one at a time", function()
        local p = context()
        assert.is_nil(Doses.refusal(p.state, pack, {}))
        Doses.take(p, defs, pack, {})
        assert.equal("UI_EHR_MedReason_WarmingPackActive", Doses.refusal(p.state, pack, {}))
        assert.near(120, p.state.meds.effects.warming.left, 1e-9)
    end)

    it("keeps the cold meter from building, but not being soaked", function()
        local function cold(p)
            for _ = 1, 60 do
                Sim.step(p)
                Exposure.updateCold(p, 1, defs)
            end
            return Meters.weather(p)
        end
        local p = packed()
        p.facts.env.wetness, p.facts.env.airC = 0.5, 0
        assert.equal(0, cold(p).coldH)
        local q = packed()
        q.facts.env.wetness, q.facts.env.airC = 1, 20
        assert.is_true(cold(q).soakedH > 0)
    end)
end)

describe("food temperature", function()
    it("classifies by vanilla's heat value: hot from 1.3, cold when frozen, else nothing", function()
        assert.is_nil(Temperature.foodEffect({ heat = 1.0, portion = 1 }))
        assert.is_nil(Temperature.foodEffect({ heat = 1.29, portion = 1 }))
        local warm = Temperature.foodEffect({ heat = 1.3, portion = 1 }) --[[@as table]]
        assert.equal("hot", warm.kind)
        assert.near(0.4 * 0.3 * 1.5, warm.add, 1e-9)
        assert.near(30 + 30 * warm.add / 0.4, warm.minutes, 1e-9)
        assert.equal(0.4, Temperature.foodEffect({ heat = 3, portion = 1 }).add)
        local liquid = Temperature.foodEffect({ heat = 3, portion = 1, liquid = true }) --[[@as table]]
        assert.equal(30, liquid.minutes)
        local ice = Temperature.foodEffect({ heat = 1, frozen = true, portion = 0.5 }) --[[@as table]]
        assert.equal("cold", ice.kind)
        assert.near(0.3, ice.add, 1e-9)
    end)

    it("warms a cold body by up to 0.4 deg C, never above 37, fading over its time", function()
        local p = context()
        p.facts.stats.TEMPERATURE = 36
        Temperature.eat(p, { heat = 3, portion = 1 })
        assert.is_true(Sim.said(p, "UI_EHR_Food_Warming"))
        minute(p)
        local first = p.state.temperature.floor --[[@as number]]
        assert.near(36 + 0.4 * 59 / 60, first, 1e-9)
        for _ = 1, 29 do
            minute(p)
        end
        assert.near(36 + 0.4 * 30 / 60, p.state.temperature.floor, 1e-9)
        local q = context()
        q.facts.stats.TEMPERATURE = 36.9
        Temperature.eat(q, { heat = 3, portion = 1 })
        minute(q)
        assert.equal(37, q.state.temperature.floor)
    end)

    it("cools a hot body by up to 0.4 deg C, never below 37, unless a fever is held", function()
        local p = context()
        p.facts.stats.TEMPERATURE = 38
        Temperature.eat(p, { heat = 1, frozen = true, portion = 1 })
        assert.is_true(Sim.said(p, "UI_EHR_Food_Cooling"))
        minute(p)
        assert.near(38 - 0.4 * 59 / 60, p.state.temperature.ceiling, 1e-9)
        p.state.temperature.fever = 39
        minute(p)
        assert.is_false(p.state.temperature.ceiling)
        local q = context()
        q.facts.stats.TEMPERATURE = 37.2
        Temperature.eat(q, { heat = 1, frozen = true, portion = 1 })
        minute(q)
        assert.equal(37, q.state.temperature.ceiling)
    end)

    it("stacks a second item at 70 %, up to 0.6 deg C in all", function()
        local p = context()
        p.facts.stats.TEMPERATURE = 35
        Temperature.eat(p, { heat = 3, portion = 1 })
        Temperature.eat(p, { heat = 3, portion = 1 })
        assert.near(0.6, (p.state.temperature.food.hot --[[@as table]]).add, 1e-9)     -- 0.4 + 0.7 x 0.4, capped
    end)

    it("does nothing while BodyTemperatureEnabled is off", function()
        local p = context({ sandbox = { BodyTemperatureEnabled = false } })
        assert.is_nil(Temperature.eat(p, { heat = 3, portion = 1 }))
        assert.is_false(p.state.temperature.food.hot)
    end)
end)

describe("pre-disease stages", function()
    local function stage(p, minutes)
        for _ = 1, minutes or 1 do
            Sim.step(p)
            Temperature.update(p, 1)
            Stages.update(p, 1)
        end
        return p.state.temperature
    end

    it("moves one stage per update, with 0.3 deg C of hysteresis", function()
        assert.equal(1, Stages.next(0, 35.7, Stages.COLD, true))
        assert.equal(1, Stages.next(1, 35.7, Stages.COLD, true))
        assert.equal(1, Stages.next(1, 36.0, Stages.COLD, true))
        assert.equal(0, Stages.next(1, 36.2, Stages.COLD, true))
        assert.equal(1, Stages.next(0, 37.6, Stages.HOT, false))
        assert.equal(1, Stages.next(1, 37.3, Stages.HOT, false))
        assert.equal(0, Stages.next(1, 37.1, Stages.HOT, false))
        local p = context()
        p.facts.stats.TEMPERATURE = 34.5
        assert.equal(1, stage(p).cold)
        assert.equal(3, stage(p, 2).cold)
    end)

    it("speaks a stage line every 30 game minutes, not while asleep", function()
        local p = context({ sandbox = { DialogueFrequency = 3 } })
        p.facts.stats.TEMPERATURE = 35.6
        stage(p)
        assert.equal(1, #p.said)
        stage(p, 29)
        assert.equal(1, #p.said)
        stage(p)
        assert.equal(2, #p.said)
        p.facts.asleep = true
        stage(p, 40)
        assert.equal(2, #p.said)
    end)

    it("slows a very cold character and makes a very hot one thirstier", function()
        local p = context()
        p.facts.stats.TEMPERATURE = 34.5
        stage(p, 3)
        assert.equal(0.85, p.fx.values.speed)
        local q = context()
        q.facts.stats.TEMPERATURE, q.facts.stats.THIRST = 38.6, 0.2
        stage(q, 2)
        assert.equal(2, q.state.temperature.hot)
        q.facts.stats.THIRST = 0.3
        stage(q)
        assert.near(0.1 * 0.25, Sim.resolve(q, "THIRST", 0.3) - 0.3, 1e-9)
    end)

    it("doesn't count a fever as being hot", function()
        local p = context()
        p.facts.stats.TEMPERATURE = 39
        p.state.temperature.fever = 39
        assert.equal(0, stage(p, 3).hot)
    end)

    it("is off with PreDiseaseEffectsEnabled or BodyTemperatureEnabled off", function()
        for _, sandbox in ipairs({ { PreDiseaseEffectsEnabled = false }, { BodyTemperatureEnabled = false } }) do
            local p = context({ sandbox = sandbox })
            p.facts.stats.TEMPERATURE = 34
            assert.equal(0, stage(p, 5).cold)
            assert.equal(0, #p.said)
        end
    end)
end)

insulate("single-player wiring: body temperature", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    _G.ISDrinkFluidAction = {
        new = function(_, character, item, percentage)
            return { character = character, item = item, fluidContainer = item.fluid, percentage = percentage }
        end,
        complete = function() return true end,
    }
    local player = game.addPlayer({})
    game.events.OnCreatePlayer.trigger(0, player)
    require("ExtensiveHealthRedone/Server/Main")
    local Facts = require("ExtensiveHealthRedone/Server/Facts")
    local StatWriter = require("ExtensiveHealthRedone/Server/StatWriter")
    game.events.OnGameBoot.trigger()
    game.events.OnGameStart.trigger()
    game.advance(2)

    local function state()
        return player.modData.ExtensiveHealthRedone
    end

    it("holds vanilla's TEMPERATURE at the fever on every tick", function()
        state().temperature.fever = 39
        game.advance(1)
        assert.near(state().temperature.fever, player.stats.TEMPERATURE, 0.02)
        player.stats.TEMPERATURE = 37      -- vanilla pulls it back between ticks
        game.advance(0.1)
        assert.near(state().temperature.fever, player.stats.TEMPERATURE, 0.02)
    end)

    it("never lowers a hotter body, and lets go once the fever has broken", function()
        player.stats.TEMPERATURE = 40
        game.advance(0.1)
        assert.equal(40, player.stats.TEMPERATURE)
        state().temperature.fever, state().temperature.floor = false, false
        player.stats.TEMPERATURE = 37
        game.advance(1)
        assert.equal(37, player.stats.TEMPERATURE)
    end)

    it("warms the body from hot food and cools it from a frozen drink, through the vanilla actions", function()
        local soup = player.inventory:add("Base.Soup", { food = true, heat = 2.5 })
        ISEatFoodAction.complete({ character = player, item = soup, percentage = 1 })
        assert.truthy(state().temperature.food.hot)
        local slush = player.inventory:add("Base.Pop", { food = true, frozen = true, fluid = {} })
        ISDrinkFluidAction.complete(ISDrinkFluidAction:new(player, slush, 1))
        assert.truthy(state().temperature.food.cold)
        assert.is_false(game.logged("listener foodTemperature"))
    end)

    describe("Indoor Climate Lite", function()
        local sample
        before_each(function()
            sample = { source = "IndoorClimateLite", active = true, indoors = true, roomKey = "r1", airC = 21.5 }
            _G.IndoorClimateLite = {
                isActive = function() return true end,
                getTemperatureSample = function() return sample end,
                getRoomDescriptor = function() return { key = "r1" } end,
            }
        end)
        after_each(function()
            _G.IndoorClimateLite = nil
        end)

        local function env()
            return Facts.read(player, StatWriter.ranges()).env
        end

        it("uses ICL's room air for the meters in SP, keeping vanilla's reading beside it", function()
            local vanilla = env().nativeAirC
            local e = env()
            assert.equal(21.5, e.airC)
            assert.equal("icl", e.airSource)
            assert.equal(vanilla, e.nativeAirC)
        end)

        it("ignores samples outside a simulated room, insane values, and a switched-off ICL", function()
            sample.roomKey = nil
            assert.equal("vanilla", env().airSource)
            sample.roomKey, sample.airC = "r1", 90
            assert.equal("vanilla", env().airSource)
            sample.airC = 21.5
            _G.IndoorClimateLite.isActive = function() return false end
            assert.equal("vanilla", env().airSource)
        end)

        it("works without ICL at all", function()
            _G.IndoorClimateLite = nil
            assert.equal("vanilla", env().airSource)
        end)

        it("reads the server's own sample on a dedicated server", function()
            local isServer = _G.isServer
            _G.isServer = function() return true end
            local e = env()
            player.vehicle = {}
            local driving = require("ExtensiveHealthRedone/Server/IndoorClimate").air(player)
            player.vehicle = nil
            _G.isServer = isServer
            assert.equal(21.5, e.airC)
            assert.equal("icl", e.airSource)
            assert.is_nil(driving)
        end)
    end)
end)
