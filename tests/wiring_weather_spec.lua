-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The fake game objects below are deliberately partial.
---@diagnostic disable: missing-fields
-- The test replaces a few fake globals and methods for this file only.
---@diagnostic disable: duplicate-set-field
-- The heat-stroke cold bath end to end in single-player mode: the server checks the tub, its water and the distance,
-- uses the water, keeps the bath alive on heartbeats, and cures heat stroke after 3 game hours.

insulate("single-player wiring: cold bath", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()

    -- Server/Weather's facts reader looks at worn items and nearby squares; give the fakes what it needs.
    local squares = {}
    local function key(x, y, z) return x .. "," .. y .. "," .. z end
    local snowCell = _G.getCell
    _G.getCell = function()
        local cell = snowCell()
        cell.getGridSquare = function(_, x, y, z) return squares[key(x, y, z)] end
        return cell
    end
    _G.SCampfireSystem = nil

    local Client = require("ExtensiveHealthRedone/Client/Client")
    local player = game.addPlayer({})

    game.events.OnCreatePlayer.trigger(0, player)
    require("ExtensiveHealthRedone/Server/Main")
    require("ExtensiveHealthRedone/Server/Weather")
    local Runtime = require("ExtensiveHealthRedone/Server/Runtime")
    local Engine = require("ExtensiveHealthRedone/Conditions/Engine")
    local defs = require("ExtensiveHealthRedone/Conditions/Registry")
    game.events.OnGameStart.trigger()
    game.advance(2)

    local received = { notice = {}, coldBathDone = {} }
    for command in pairs(received) do
        Client.on(command, function(args) table.insert(received[command], args) end)
    end

    local function tubAt(x, y, z, water)
        local square = FakeGame.newSquare(x, y, z)
        local tub = { water = water, used = 0 }
        function tub:getSprite() return { getName = function() return "fixtures_bathroom_01_25" end } end
        function tub:hasWater() return self.water > 0 end
        function tub:getFluidAmount() return self.water end
        function tub:useFluid(amount) self.water, self.used = self.water - amount, self.used + amount end
        square.objects = { tub }
        squares[key(x, y, z)] = square
        return tub
    end

    local function state()
        return player.modData.ExtensiveHealthRedone
    end

    local key0 = Runtime.attach(player)
    Runtime.applyNow(key0, function(p)
        Engine.contract(p, defs, "heat_stroke")
    end)

    it("refuses a tub that is too far away or holds too little water", function()
        tubAt(110, 100, 0, 20)
        Client.send(player, "weather.bathStart", { x = 110, y = 100, z = 0 })
        local dry = tubAt(101, 100, 0, 5)
        Client.send(player, "weather.bathStart", { x = 101, y = 100, z = 0 })
        assert.equal(2, #received.notice)
        assert.equal("UI_EHR_Weather_BathNotHere", received.notice[1].key)
        assert.equal(0, dry.used)
        assert.is_nil(state().exposure.data.weather and state().exposure.data.weather.bath)
    end)

    it("uses the water, keeps going on heartbeats and cures heat stroke after 3 hours", function()
        local tub = tubAt(101, 101, 0, 20)
        Client.send(player, "weather.bathStart", { x = 101, y = 101, z = 0 })
        assert.equal(8, tub.used)
        assert.truthy(state().exposure.data.weather.bath)
        for _ = 1, 19 do
            game.advance(10)
            Client.send(player, "weather.bathBeat", {})
        end
        assert.is_nil(state().conditions.active.heat_stroke)
        assert.is_true(received.coldBathDone[1].cured)
    end)
end)
