-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The fake game objects below are deliberately partial.
---@diagnostic disable: missing-fields
-- Server/Extremities against the fake game: the worn socks, shoes and gloves and the hands' and feet's skin end up in
-- facts.extremities.

insulate("single-player wiring: extremities facts", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    local player = game.addPlayer({})
    local Facts = require("ExtensiveHealthRedone/Server/Facts")
    require("ExtensiveHealthRedone/Server/Extremities")
    local Sim = require("support/sim")

    local function read()
        return Facts.read(player, Sim.RANGES).extremities
    end

    it("reads nothing worn on a bare character", function()
        local e = read()
        assert.is_nil(e.socks)
        assert.is_nil(e.shoes)
        assert.is_nil(e.gloves)
        assert.are.equal(20, e.windChillC)
        assert.are.same({ "Foot_L", "Foot_R", "Hand_L", "Hand_R" }, (function()
            local names = {}
            for name in pairs(e.parts) do names[#names + 1] = name end
            table.sort(names)
            return names
        end)())
    end)

    it("reads socks, shoes and gloves by location, wetness as a share", function()
        player.worn = {
            FakeGame.newClothing({ location = "Base:Socks", wet = 60, holes = 1 }),
            FakeGame.newClothing({ location = "Shoes", wet = 100, condition = 6, conditionMax = 24, waterRes = 0.25 }),
            FakeGame.newClothing({ location = "Hands", wet = 10 }),
            FakeGame.newClothing({ location = "Hat", wet = 100 }),
        }
        local e = read()
        assert.are.same({ wet = 0.6, holes = 1 }, e.socks)
        assert.are.same({ wet = 1, holes = 0, wear = 0.25, waterRes = 0.25 }, e.shoes)
        assert.are.same({ wet = 0.1, holes = 0 }, e.gloves)
    end)

    it("reads one-handed gloves as gloves", function()
        player.worn = { FakeGame.newClothing({ location = "Hands_Left", wet = 30 }) }
        assert.are.same({ wet = 0.3, holes = 0 }, read().gloves)
    end)

    it("reads skin temperature, insulation and wind chill", function()
        local parts = player:getBodyDamage().parts
        for _, part in ipairs(parts) do
            if part.name == "Foot_L" then
                part.skinC, part.insulation = 12.5, 0.8
            end
        end
        game.climate.windChillC = -7
        local e = read()
        assert.are.same({ skinC = 12.5, insulation = 0.8 }, e.parts.Foot_L)
        assert.are.equal(-7, e.windChillC)
    end)
end)
