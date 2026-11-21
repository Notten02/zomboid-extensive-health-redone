-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The stand-ins for Real Room Temperature's globals are deliberately partial.
---@diagnostic disable: missing-fields, duplicate-set-field
-- Real Room Temperature 2.0 beside us, with its Body Temperature Rework on: the cold retention the Warming Pack and
-- hot food ask for (Body/Temperature.coldRetention), when RRT's cold model owns a body (Game/RealRoomTemperature,
-- against stand-ins for RealRoomHeat2.BodyCold, BodyServer and BodyServerInput as read in RRT's code), and the
-- server's temperature hold yielding to it (Server/RealRoomTemperature, Server/Temperature).
local Temperature = require("ExtensiveHealthRedone/Body/Temperature")
local Sim = require("support/sim")

local function context()
    local p = Sim.context()
    p.facts.stats.TEMPERATURE = 37
    return p
end

local function minute(p)
    Sim.step(p)
    Temperature.update(p, 1)
end

-- A stand-in for RRT's cold retention registry (shared/RRH2/RRH2ColdRetention.lua): providers by id, the highest
-- answer wins, errors and bad values count as nothing.
local function fakeRegistry()
    local registry = { providers = {} }
    function registry.registerColdRetentionProvider(id, callback)
        if type(id) ~= "string" or id == "" or type(callback) ~= "function" then
            return false
        end
        registry.providers[id] = callback
        return true
    end
    function registry.unregisterColdRetentionProvider(id)
        local had = registry.providers[id] ~= nil
        registry.providers[id] = nil
        return had
    end
    function registry.resolve(actor)
        local strongest = 0
        for _, callback in pairs(registry.providers) do
            local ok, value = pcall(callback, actor)
            if ok and type(value) == "number" and value > strongest and value < math.huge then
                strongest = math.min(value, 1)
            end
        end
        return strongest > 0 and strongest or nil
    end
    return registry
end

describe("cold retention (Temperature.coldRetention)", function()
    it("is nothing without the pack or hot food", function()
        local p = context()
        minute(p)
        assert.equal(0, Temperature.coldRetention(p.state.temperature))
        assert.equal(0, Temperature.coldRetention(nil))
    end)

    it("keeps heat in while the Warming Pack is active", function()
        local p = context()
        p.state.meds.effects.warming = { id = "warming", left = 120, data = {} }
        p.facts.stats.TEMPERATURE = 35
        minute(p)
        assert.equal(Temperature.RETENTION.WARMING, Temperature.coldRetention(p.state.temperature))
        p.state.meds.effects.warming = nil
        minute(p)
        assert.equal(0, Temperature.coldRetention(p.state.temperature))
    end)

    it("follows hot food, fading with it, and is the larger of the two", function()
        local p = context()
        p.facts.stats.TEMPERATURE = 36
        Temperature.eat(p, { heat = 3, portion = 1 })       -- 0.4 deg C for 60 minutes
        local R, F = Temperature.RETENTION, Temperature.FOOD
        assert.near(R.HOT_FOOD * 0.4 / F.MAX_TOTAL, Temperature.coldRetention(p.state.temperature), 1e-9)
        for _ = 1, 30 do
            minute(p)
        end
        assert.near(R.HOT_FOOD * 0.2 / F.MAX_TOTAL, Temperature.coldRetention(p.state.temperature), 1e-9)
        p.state.meds.effects.warming = { id = "warming", left = 120, data = {} }
        minute(p)
        assert.equal(R.WARMING, Temperature.coldRetention(p.state.temperature))
    end)

    it("asks nothing for a fever or frozen food", function()
        local p = context()
        p.state.temperature.fever = 39
        Temperature.eat(p, { heat = 1, frozen = true, portion = 1 })
        minute(p)
        assert.equal(0, Temperature.coldRetention(p.state.temperature))
    end)
end)

insulate("who owns the body (Game/RealRoomTemperature.owns)", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    local RRT = require("ExtensiveHealthRedone/Game/RealRoomTemperature")
    local player = game.addPlayer({})

    before_each(function()
        RRT.reset()
        game.mods.RealRoomHeat = true
        game.sandboxFor("RRH2").BodyTempRework = true
        _G.isServer = function() return false end
        _G.RealRoomHeat2 = { BodyCold = { blocks = function(actor) return actor == player end } }
    end)
    after_each(function()
        _G.RealRoomHeat2 = nil
        _G.isServer = function() return false end
    end)

    it("is never without the mod, or with its Body Temperature Rework off", function()
        game.mods.RealRoomHeat = nil
        assert.is_false(RRT.owns(player))
        RRT.reset()
        game.mods.RealRoomHeat = true
        game.sandboxFor("RRH2").BodyTempRework = false
        assert.is_false(RRT.owns(player))
        game.sandboxFor("RRH2").BodyTempRework = nil       -- off by default
        assert.is_false(RRT.owns(player))
    end)

    it("follows the single-player cold model's lease", function()
        assert.is_true(RRT.owns(player))
        _G.RealRoomHeat2.BodyCold.blocks = function() return false end
        assert.is_false(RRT.owns(player))
    end)

    it("takes the body as owned when RRT's API fails or is missing", function()
        _G.RealRoomHeat2.BodyCold.blocks = function() error("boom") end
        assert.is_true(RRT.owns(player))
        _G.RealRoomHeat2.BodyCold.blocks = nil
        assert.is_true(RRT.owns(player))
        _G.RealRoomHeat2 = {}                               -- no body model loaded: nothing of RRT writes
        assert.is_false(RRT.owns(player))
    end)

    describe("on a dedicated server", function()
        local route, snapshot
        before_each(function()
            _G.isServer = function() return true end
            route, snapshot = "native_delivery", { owner = "native_and_production" }
            _G.RealRoomHeat2 = {
                BodyServerInput = { resolve = function() return { route = route } end },
                BodyServer = { snapshot = function() return snapshot end },
            }
        end)

        it("owns while its route is the cold model, before admission too", function()
            assert.is_false(RRT.owns(player))
            route = RRT.COLD_ROUTE
            assert.is_true(RRT.owns(player))
        end)

        it("owns while a generation is still held or being cleaned up", function()
            snapshot = { owner = RRT.SERVER_OWNER }
            assert.is_true(RRT.owns(player))
            snapshot = { owner = "native_and_production", cleanupPending = true }
            assert.is_true(RRT.owns(player))
        end)

        it("owns when the resolver errors", function()
            _G.RealRoomHeat2.BodyServerInput.resolve = function() error("boom") end
            assert.is_true(RRT.owns(player))
        end)
    end)
end)

insulate("single-player wiring: Real Room Temperature with its rework on", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    game.mods.RealRoomHeat = true
    game.sandboxFor("RRH2").BodyTempRework = true
    local lease = { held = false }
    local registry = fakeRegistry()
    -- RRT's shared files load before any server file.
    _G.RealRoomHeat2 = {
        ColdRetention = registry,
        BodyCold = { blocks = function() return lease.held end },
    }
    local player = game.addPlayer({})
    game.events.OnCreatePlayer.trigger(0, player)
    require("ExtensiveHealthRedone/Server/Main")
    local ServerRRT = require("ExtensiveHealthRedone/Server/RealRoomTemperature")
    game.events.OnGameBoot.trigger()
    game.events.OnGameStart.trigger()
    game.advance(2)

    local function state()
        return player.modData.ExtensiveHealthRedone
    end

    after_each(function()
        lease.held = false
        state().temperature.fever, state().temperature.floor = false, false
        state().temperature.food.hot = false
        state().meds.effects.warming = nil
    end)

    it("registers our cold retention provider", function()
        assert.equal(ServerRRT.retentionFor, registry.providers[ServerRRT.PROVIDER_ID])
        assert.is_true(game.logged("Real Room Temperature found"))
    end)

    it("holds a fever while RRT's cold model doesn't own the body", function()
        state().temperature.fever = 39
        game.advance(1)
        assert.near(state().temperature.fever, player.stats.TEMPERATURE, 0.02)
    end)

    it("never writes TEMPERATURE while the cold model owns the body", function()
        lease.held = true
        state().temperature.fever = 39
        player.stats.TEMPERATURE = 36.2
        game.advance(1)
        assert.equal(36.2, player.stats.TEMPERATURE)
        assert.truthy(state().temperature.fever)            -- the fever itself keeps running
        lease.held = false
        game.advance(0.1)
        assert.near(state().temperature.fever, player.stats.TEMPERATURE, 0.02)
    end)

    it("gives the cold model the Warming Pack and hot food as retention", function()
        lease.held = true
        assert.is_nil(registry.resolve(player))
        state().meds.effects.warming = { id = "warming", left = 120, data = {} }
        player.stats.TEMPERATURE = 35
        game.advance(1)
        assert.equal(35, player.stats.TEMPERATURE)
        assert.equal(Temperature.RETENTION.WARMING, registry.resolve(player))
        state().meds.effects.warming = nil
        game.advance(1)
        assert.is_nil(registry.resolve(player))
        local soup = player.inventory:add("Base.Soup", { food = true, heat = 2.5 })
        ISEatFoodAction.complete({ character = player, item = soup, percentage = 1 })
        assert.is_true(registry.resolve(player) > 0)
    end)

    it("asks for no retention with the rework switched off", function()
        state().meds.effects.warming = { id = "warming", left = 120, data = {} }
        game.advance(1)
        game.sandboxFor("RRH2").BodyTempRework = false
        assert.equal(0, ServerRRT.retentionFor(player))
        game.sandboxFor("RRH2").BodyTempRework = true
    end)
end)

insulate("single-player wiring: without Real Room Temperature", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    local player = game.addPlayer({})
    game.events.OnCreatePlayer.trigger(0, player)
    require("ExtensiveHealthRedone/Server/Main")
    game.events.OnGameBoot.trigger()
    game.events.OnGameStart.trigger()
    game.advance(2)

    it("registers nothing and holds as before", function()
        assert.is_false(game.logged("Real Room Temperature found"))
        player.modData.ExtensiveHealthRedone.temperature.fever = 39
        game.advance(1)
        assert.near(39, player.stats.TEMPERATURE, 0.05)
    end)
end)
