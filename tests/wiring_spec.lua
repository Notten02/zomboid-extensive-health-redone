-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The adapter wiring in single-player mode, end to end against tests/support/fake_game.lua: transport, presence,
-- the scheduler, the simulation pipeline, the stat writer, sync to the client mirror, the importer on first load,
-- and the debug command gates. In-game testing is still needed; this catches wiring mistakes early.

insulate("single-player wiring", function()
    local FakeGame = require("support/fake_game")
    local Fixtures = require("fixtures/legacy_ehr")
    local game = FakeGame.install()

    -- Same order as the game: shared and client files first; the player appears; server files load at game start.
    local Client = require("ExtensiveHealthRedone/Client/Client")
    local veteran = Fixtures.veteran()
    local player = game.addPlayer({ modData = veteran })
    game.events.OnCreatePlayer.trigger(0, player)
    require("ExtensiveHealthRedone/Server/Main")
    local Runtime = require("ExtensiveHealthRedone/Server/Runtime")
    game.events.OnGameStart.trigger()

    -- A stand-in feature: drains immunity and adds pain every simulated minute. The real immune system is off, so
    -- only the stand-in moves the score.
    game.sandbox.ImmunitySystemEnabled = false
    Runtime.sim:add({
        name = "test",
        update = function(p, dt)
            p.state.immunity.score = p.state.immunity.score - 0.1 * dt
            p.dirty("immunity")
            p.stats:add("PAIN", "test", 1 * dt)
        end,
    })

    local rejected = {}
    Client.on("rejected", function(args) rejected[#rejected + 1] = args.code end)

    it("answers the queued hello with a snapshot of the imported state", function()
        local identity = Client.section(player, "identity")
        assert.is_not_nil(identity)
        assert.equal("A+", identity.bloodType)
        assert.equal("imported", Client.section(player, "meta").createdAs)
        assert.is_nil(veteran.EHR_Blood)
        assert.equal("table", type(veteran.ExtensiveHealthRedone))
        assert.truthy(game.logged("imported from Extensive Health Rework"))
    end)

    it("simulates on game time and syncs the changed section", function()
        local before = Client.section(player, "immunity").score
        game.advance(10)
        local after = Client.section(player, "immunity").score
        -- The first tick only sets the baseline, so 10 minutes give 9 or 10 steps.
        assert.truthy(before - after > 0.85 and before - after < 1.05, "drained " .. (before - after))
        assert.truthy(player.stats.PAIN >= 9 and player.stats.PAIN <= 10)
    end)

    it("pauses everything while the player is offline", function()
        local score = veteran.ExtensiveHealthRedone.immunity.score
        local pain = player.stats.PAIN
        game.removePlayer(player)
        game.advance(30)
        assert.equal(score, veteran.ExtensiveHealthRedone.immunity.score)
        assert.equal(pain, player.stats.PAIN)
        game.players[1] = player
        game.advance(5)
        assert.truthy(veteran.ExtensiveHealthRedone.immunity.score < score)
    end)

    it("refuses debug commands without DebugMode, then allows them", function()
        local score = veteran.ExtensiveHealthRedone.immunity.score
        Client.send(player, "debug.skipTime", { minutes = 60 })
        assert.same({ "debug_only" }, rejected)
        game.sandbox.DebugMode = true
        Client.send(player, "debug.skipTime", { minutes = 60 })
        assert.equal(1, #rejected)
        assert.near(score - 6, veteran.ExtensiveHealthRedone.immunity.score, 1e-6)
        assert.near(veteran.ExtensiveHealthRedone.immunity.score, Client.section(player, "immunity").score, 1e-6)
    end)

    it("rejects unknown commands and bad arguments without touching state", function()
        Client.send(player, "blood.setVolume", { ml = 9999 })
        Client.send(player, "debug.skipTime", { minutes = -5 })
        assert.same({ "debug_only", "unknown_command", "bad_args" }, rejected)
    end)

    it("logs rejections at most once per 10 s per sender, with long command names cut (SA-11 to SA-13)", function()
        game.realMs = game.realMs + 11000
        local before = #game.printed
        local long = string.rep("x", 300)
        for _ = 1, 5 do
            Client.send(player, long, {})
        end
        local lines = 0
        for i = before + 1, #game.printed do
            if game.printed[i]:find("rejected", 1, true) then
                lines = lines + 1
                assert.is_nil(game.printed[i]:find(string.rep("x", 65), 1, true))
            end
        end
        assert.equal(1, lines)
        game.realMs = game.realMs + 11000
        Client.send(player, "nope", {})
        assert.is_true(game.logged("(and 4 more rejections not logged)"))
        -- skipTime: at most 24 h per call; sync.hello: 2 per 10 s.
        Client.send(player, "debug.skipTime", { minutes = 24 * 60 + 1 })
        assert.equal("bad_args", rejected[#rejected])
        game.realMs = game.realMs + 11000
        for _ = 1, 3 do
            Client.send(player, "sync.hello", { v = require("ExtensiveHealthRedone/Core/Sync").PROTOCOL })
        end
        assert.equal("rate_limited", rejected[#rejected])
    end)

    it("dumps server state to the client", function()
        local dumped
        Client.on("debugDump", function(args) dumped = args.text end)
        Client.send(player, "debug.dump", {})
        assert.truthy(dumped and dumped:find('bloodType = "A+"', 1, true))
    end)

    it("gives a new character after death a fresh state that inherits nothing", function()
        player.dead = true
        game.advance(2)
        assert.is_false(Runtime.store:has("sp:0"))
        local reborn = game.addPlayer({})
        game.removePlayer(player)
        game.events.OnCreatePlayer.trigger(0, reborn)
        local meta = Client.section(reborn, "meta")
        assert.equal("new", meta.createdAs)
        assert.same({}, Client.section(reborn, "knowledge").diseases)
        assert.equal(75, Client.section(reborn, "immunity").score)
    end)

    it("writes vanilla stats through the stat writer only", function()
        local reborn = game.players[1]
        game.advance(3)
        assert.truthy((reborn.stats.PAIN or 0) > 0)
    end)
end)
