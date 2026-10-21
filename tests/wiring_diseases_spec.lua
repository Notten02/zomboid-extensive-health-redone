-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Every condition, end to end in single-player mode with all feature files loaded (tests/support/fake_game.lua):
-- started, put through each stage and cured with the debug command, with game time running in between. Catches a
-- condition whose effects or cleanup break once every group's systems and fact readers run together.

insulate("single-player wiring: every condition", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    game.sandbox.DebugMode = true

    local player = game.addPlayer({ capabilities = { CanMedicalCheat = true } })
    game.events.OnCreatePlayer.trigger(0, player)
    require("ExtensiveHealthRedone/Server/Main")
    local Client = require("ExtensiveHealthRedone/Client/Client")
    local Tables = require("ExtensiveHealthRedone/Core/Tables")
    local defs = require("ExtensiveHealthRedone/Conditions/Registry")
    game.events.OnGameStart.trigger()
    game.advance(2)

    local rejected = {}
    Client.on("rejected", function(args) rejected[#rejected + 1] = args end)

    local function active(id)
        return player.modData.ExtensiveHealthRedone.conditions.active[id]
    end

    local function heal()
        player.dead = false
        player.body.health = 100
        for _, part in ipairs(player.body.parts) do
            part.health = 100
        end
    end

    for _, id in ipairs(Tables.sortedKeys(defs)) do
        it("runs " .. id .. " through every stage and cures it", function()
            heal()
            Client.send(player, "debug.condition", { id = id, action = "start" })
            assert.truthy(active(id), id .. " did not start")
            for stage = 1, 4 do
                if active(id) then
                    Client.send(player, "debug.condition", { id = id, action = "stage", stage = stage })
                    game.advance(30)
                    heal()
                end
            end
            Client.send(player, "debug.condition", { id = id, action = "cure" })
            game.advance(5)
            -- Driven conditions (hypothermia, heat exhaustion, Knox) may come straight back from their facts; the
            -- point here is that nothing errors and a cure removes the condition.
            if not defs[id].driven then
                assert.is_nil(active(id), id .. " is still active after the cure")
            end
            assert.same({}, rejected)
        end)
    end
end)
