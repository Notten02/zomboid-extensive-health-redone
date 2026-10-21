---@diagnostic disable: need-check-nil
-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The fake game objects are deliberately partial.
---@diagnostic disable: missing-fields, duplicate-set-field
-- Lifestyle: Hobbies (Phase 10): the pure recovery pace, how the engine and the heat meters use it, the bladder pressure
-- of dysentery and furosemide, the reader on the server (SP and MP report), and the client's two jobs.
local Pace = require("ExtensiveHealthRedone/Lifestyle/Pace")
local Engine = require("ExtensiveHealthRedone/Conditions/Engine")
local Meters = require("ExtensiveHealthRedone/Diseases/Weather/Meters")
local Dysentery = require("ExtensiveHealthRedone/Diseases/Food/Dysentery")
local SideEffects = require("ExtensiveHealthRedone/Medication/SideEffects")
local ClientEffects = require("ExtensiveHealthRedone/Core/ClientEffects")
local Sim = require("support/sim")

describe("Lifestyle recovery pace", function()
    local function pace(raw)
        return Pace.read(raw).pace
    end

    it("is 1 with nothing to say, and cleans a raw reading into its ranges", function()
        assert.equal(1, pace({}))
        assert.equal(1, pace(nil))
        local l = Pace.clean({ hygiene = 500, comfort = 9, yoga = 99.7, bathLeft = -4, showering = "yes" })
        assert.same({ hygiene = 100, showering = false, bathLeft = 0, sitting = false, comfort = 1, yoga = 10 }, l)
        assert.is_nil(Pace.clean({ hygiene = 0 / 0 }).hygiene)
    end)

    it("gives the v0.9 hygiene tiers, and the penalties v0.9 never applied", function()
        assert.near(1.25, pace({ hygiene = 5 }), 1e-9)
        assert.near(1.15, pace({ hygiene = 20 }), 1e-9)
        assert.equal(1, pace({ hygiene = 50 }))
        assert.near(0.90, pace({ hygiene = 70 }), 1e-9)
        assert.near(0.75, pace({ hygiene = 95 }), 1e-9)
    end)

    it("adds a shower, its fading glow, sitting by comfort, and yoga", function()
        assert.near(1.05, pace({ showering = true }), 1e-9)
        assert.near(1.025, pace({ bathLeft = 60 }), 1e-9)
        assert.near(1.10, pace({ sitting = true, comfort = 0.7 }), 1e-9)
        assert.near(1.05, pace({ sitting = true, comfort = 0.2 }), 1e-9)
        assert.near(1.07, pace({ yoga = 7 }), 1e-9)
        assert.near(1.25 + 0.05 + 0.10 + 0.10, pace({ hygiene = 0, showering = true, sitting = true, comfort = 0.9,
            yoga = 10 }), 1e-9)
    end)

    it("lists its parts for debugging", function()
        local l = Pace.read({ hygiene = 0, showering = true, yoga = 2 })
        assert.same({ "hygiene", "bath", "yoga" }, { l.parts[1].name, l.parts[2].name, l.parts[3].name })
    end)

    it("adjusts cellulitis and the lungs, and leaves Knox alone", function()
        local dirty = Pace.read({ hygiene = 90 })
        assert.near(0.65, Pace.forCondition(dirty, "cellulitis"), 1e-9)
        assert.near(0.75, Pace.forCondition(dirty, "gastroenteritis"), 1e-9)
        local bathed = Pace.read({ hygiene = 50, showering = true })
        assert.near(1.10, Pace.forCondition(bathed, "cellulitis"), 1e-9)
        local sitting = Pace.read({ sitting = true, comfort = 0.7 })
        assert.near(1.05, Pace.forCondition(sitting, "pneumonia"), 1e-9)
        assert.near(1.05, Pace.forCondition(sitting, "common_cold"), 1e-9)
        assert.equal(1, Pace.forCondition(Pace.read({ hygiene = 0 }), "knox_infection"))
        assert.equal(1, Pace.forCondition(nil, "cellulitis"))
    end)
end)

describe("Lifestyle in the engine and the meters", function()
    local defs = {
        flu = { incubation = { 1, 1 }, duration = { 10, 10 } },
        knox_infection = { incubation = { 1, 1 }, duration = { 10, 10 } },
    }

    local function contract(p, id)
        local c = Engine.contract(p, defs, id, { severity = 1 })
        c.stage, c.left = 2, c.len[2]
        return c
    end

    it("moves an illness along faster for a clean character and slower for a filthy one, never in the incubation", function()
        local p = Sim.context()
        local c = contract(p, "flu")
        local before = c.left
        p.facts.lifestyle = Pace.read({ hygiene = 0 })
        Engine.step(p, defs, 10)
        assert.near(before - 12.5, c.left, 1e-6)
        p.facts.lifestyle = Pace.read({ hygiene = 100 })
        local mid = c.left
        Engine.step(p, defs, 10)
        assert.near(mid - 7.5, c.left, 1e-6)
        local fresh = Engine.contract(Sim.context(), defs, "flu")
        assert.equal(1, fresh.stage)
        local q = Sim.context()
        local incubating = Engine.contract(q, defs, "flu", { severity = 1 })
        q.facts.lifestyle = Pace.read({ hygiene = 0 })
        local left = incubating.left
        Engine.step(q, defs, 0.5)
        assert.near(left - 0.5, incubating.left, 1e-6)
    end)

    it("does nothing without Lifestyle, and never speeds up Knox", function()
        local p = Sim.context()
        local c = contract(p, "flu")
        local before = c.left
        Engine.step(p, defs, 10)
        assert.near(before - 10, c.left, 1e-6)
        local k = contract(p, "knox_infection")
        p.facts.lifestyle = Pace.read({ hygiene = 0 })
        local left = k.left
        Engine.step(p, defs, 10)
        assert.near(left - 10, k.left, 1e-6)
    end)

    it("counts a Lifestyle shower as bathing for the heat meters", function()
        local p = Sim.context()
        assert.is_false(Meters.bathing(p))
        p.facts.lifestyle = Pace.read({ showering = true })
        assert.is_true(Meters.bathing(p))
        p.facts.lifestyle = Pace.read({ showering = false, bathLeft = 30 })
        assert.is_false(Meters.bathing(p))
    end)
end)

describe("bladder pressure", function()
    local function dysentery(stage, relief)
        local p = Sim.context({ treatment = { relief = relief or {} } })
        p.facts.stats.THIRST, p.facts.stats.HUNGER = 0, 0
        p.state.blood.volume = 5000
        Dysentery.effects(p, { stage = stage, data = {} }, 1)
        return p.fx.values.bladder
    end

    it("sums sources and is rounded when written to the section", function()
        local fx = ClientEffects.new()
        fx:bladder("a", 14)
        fx:bladder("b", 18.004)
        assert.near(32.004, fx.values.bladder, 1e-9)
        local section = ClientEffects.defaults()
        assert.equal(0, section.bladder)
        assert.is_true(fx:writeTo(section))
        assert.equal(32, section.bladder)
    end)

    it("grows with the dysentery stage (v0.9: 2, 14, 26, 2 points an hour)", function()
        assert.near(2, dysentery(1), 1e-9)
        assert.near(14, dysentery(2), 1e-9)
        assert.near(26, dysentery(3), 1e-9)
        assert.near(2, dysentery(4), 1e-9)
    end)

    it("eases with an anti-diarrheal, which also drains the need that is there", function()
        local rate = dysentery(3, { ["dysentery.diarrhea"] = 0.85, ["dysentery.bathroomNeed"] = 0.85 })
        assert.near(26 * 0.15 * 0.15 - 35 * 0.85, rate, 1e-9)
        assert.is_true(rate < 0)
    end)

    it("is raised by furosemide's side effect", function()
        local p = Sim.context()
        SideEffects.DEFS.diuretic_urination.update(p, {}, 1)
        assert.equal(18, p.fx.values.bladder)
    end)
end)

insulate("Lifestyle: Hobbies wiring", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    _G.SandboxVars.Text = { DividerHygiene = true }

    local Client = require("ExtensiveHealthRedone/Client/Client")
    local PlayerKey = require("ExtensiveHealthRedone/Game/PlayerKey")
    local Lifestyle = require("ExtensiveHealthRedone/Game/Lifestyle")
    local player = game.addPlayer({})
    game.events.OnCreatePlayer.trigger(0, player)
    require("ExtensiveHealthRedone/Server/Main")
    local ServerLifestyle = require("ExtensiveHealthRedone/Server/Lifestyle")
    local ClientLifestyle = require("ExtensiveHealthRedone/Client/Lifestyle")
    game.events.OnGameStart.trigger()
    game.advance(2)

    local function lifestyleData(extra)
        player.modData.hygieneNeed = 10
        player.modData.IsDoingShower = false
        player.modData.IsSittingOnSeat = false
        player.modData.ComfortVal = 0
        player.modData.bathroomNeed = 20
        player.modData.IsDoingToilet = false
        player.modData.LSMoodles = { BladderNeed = { Value = 0 }, BathCold = { Value = 0 } }
        player.modData.LSHiddenSkills = { Yoga = { 4, 0, 1000 } }
        for k, v in pairs(extra or {}) do
            player.modData[k] = v
        end
    end
    local facts = { inVehicle = false, env = { moving = false } }

    before_each(function()
        game.mods.LifestyleHobbies = true
        Lifestyle.reset()
        lifestyleData()
        player.state.sitOnGround, player.state.sittingOnFurniture = false, false
    end)

    it("reads Lifestyle's real keys in single player", function()
        player.modData.IsDoingShower = true
        player.modData.IsSittingOnSeat, player.modData.ComfortVal = true, 0.75
        local s = Lifestyle.sample(player)
        assert.same({ hygiene = 10, showering = true, sitting = true, comfort = 0.75, yoga = 4 }, s)
        local l = ServerLifestyle.read(player, facts)
        assert.is_true(l.showering)
        assert.is_true(l.pace > 1.25)
    end)

    it("counts sitting on the ground or on furniture and ignores hygiene when Lifestyle's module is off", function()
        player.state.sitOnGround = true
        assert.same({ true, 0.2 }, { Lifestyle.sample(player).sitting, Lifestyle.sample(player).comfort })
        player.state.sitOnGround, player.state.sittingOnFurniture = false, true
        assert.is_true(Lifestyle.sample(player).sitting)
        _G.SandboxVars.Text.DividerHygiene = false
        assert.is_nil(Lifestyle.sample(player).hygiene)
        assert.is_false(Lifestyle.hasToilet(player))
        _G.SandboxVars.Text.DividerHygiene = true
    end)

    it("says nothing without Lifestyle", function()
        game.mods.LifestyleHobbies = nil
        Lifestyle.reset()
        assert.is_nil(Lifestyle.sample(player))
        assert.is_nil(ServerLifestyle.read(player, facts))
        assert.is_nil(Lifestyle.addBathroomNeed(player, 5))
        Lifestyle.markColdBath(player)
        assert.equal(0, player.modData.LSMoodles.BathCold.Value)
    end)

    it("only believes a shower to a character standing still outside a vehicle, then keeps a 2 hour glow", function()
        player.modData.IsDoingShower = true
        assert.is_true(ServerLifestyle.read(player, { inVehicle = true, env = { moving = false } }).showering ~= true)
        assert.is_true(ServerLifestyle.read(player, { inVehicle = false, env = { moving = true } }).showering ~= true)
        assert.is_true(ServerLifestyle.read(player, facts).showering)
        player.modData.IsDoingShower = false
        game.advance(60)
        local glow = ServerLifestyle.read(player, facts)
        assert.is_false(glow.showering)
        assert.near(60, glow.bathLeft, 1)
        game.advance(70)
        assert.equal(0, ServerLifestyle.read(player, facts).bathLeft)
    end)

    it("speeds up a real condition through the simulation", function()
        local Runtime = require("ExtensiveHealthRedone/Server/Runtime")
        local defs = require("ExtensiveHealthRedone/Conditions/Registry")
        local key = Runtime.attach(player)
        local c
        Runtime.applyNow(key, function(p)
            c = Engine.contract(p, defs, "common_cold", { severity = 1 })
            c.stage, c.left = 2, 300
        end)
        game.advance(5)
        local clean = 300 - c.left
        lifestyleData({ hygieneNeed = 95 })
        c.left = 300
        game.advance(5)
        local dirty = 300 - c.left
        assert.is_true(clean > dirty)
        assert.is_true(dirty > 0)
    end)

    describe("on a dedicated server", function()
        local isServer = _G.isServer
        before_each(function()
            _G.isServer = function() return true end
        end)
        after_each(function()
            _G.isServer = isServer
        end)

        -- The test's own sends go through the single-player transport.
        local function send(command, args)
            local now = _G.isServer
            _G.isServer = isServer
            Client.send(player, command, args)
            _G.isServer = now
        end

        it("uses only a fresh report, clamps it and refuses what is out of range", function()
            local key = PlayerKey.of(player)
            player.modData.hygieneNeed = 99   -- the server never looks at this
            assert.is_nil(ServerLifestyle.read(player, facts))
            send("lifestyle.report", { hygiene = 5, showering = false, sitting = true, comfort = 0.8, yoga = 10 })
            assert.is_false(game.logged("rejected"))
            ServerLifestyle.report(key, { hygiene = 5, sitting = true, comfort = 0.8, yoga = 10 })
            local l = ServerLifestyle.read(player, facts)
            assert.near(1.25 + 0.10 + 0.10, l.pace, 1e-9)
            ServerLifestyle.report(key, { hygiene = -400, yoga = 60, comfort = 7 })
            l = ServerLifestyle.read(player, facts)
            assert.equal(0, l.hygiene)
            assert.equal(10, l.yoga)
            send("lifestyle.report", { hygiene = 400 })
            assert.is_true(game.logged("rejected"))
            game.realMs = game.realMs + ServerLifestyle.FRESH_S * 1000 + 1000
            assert.is_nil(ServerLifestyle.read(player, facts))
            ServerLifestyle.report(key, { hygiene = 5 })
            ServerLifestyle.report(key, nil)
            assert.is_nil(ServerLifestyle.read(player, facts))
        end)
    end)

    describe("the client", function()
        local sent
        before_each(function()
            sent = {}
            local send = Client.send
            Client.send = function(_, command, args) sent[#sent + 1] = { command, args } end
            Client.__send = send
        end)
        after_each(function()
            Client.send = Client.__send
        end)

        it("reports on change, on the heartbeat and when Lifestyle goes away", function()
            game.realMs = game.realMs + 100000
            ClientLifestyle.tick()
            assert.equal(1, #sent)
            assert.equal("lifestyle.report", sent[1][1])
            assert.equal(10, sent[1][2].hygiene)
            game.realMs = game.realMs + 6000
            ClientLifestyle.tick()
            assert.equal(1, #sent)                       -- nothing changed
            player.modData.hygieneNeed = 40
            game.realMs = game.realMs + 6000
            ClientLifestyle.tick()
            assert.equal(2, #sent)
            game.realMs = game.realMs + 31000
            ClientLifestyle.tick()
            assert.equal(3, #sent)                       -- the heartbeat
            game.mods.LifestyleHobbies = nil
            Lifestyle.reset()
            game.realMs = game.realMs + 6000
            ClientLifestyle.tick()
            assert.is_true(sent[#sent][2].clear)
        end)

        it("adds the server's bladder pressure to Lifestyle's need, not on the toilet", function()
            local effects = Client.section(player, "effects")
            effects.bladder = 30
            player.modData.bathroomNeed = 20
            ClientLifestyle.minute()
            assert.near(20.5, player.modData.bathroomNeed, 1e-9)
            player.modData.IsDoingToilet = true
            ClientLifestyle.minute()
            assert.near(20.5, player.modData.bathroomNeed, 1e-9)
            player.modData.IsDoingToilet = false
            effects.bladder = -3000
            ClientLifestyle.minute()
            assert.equal(0, player.modData.bathroomNeed)
            effects.bladder = 3000
            player.modData.bathroomNeed = 99
            ClientLifestyle.minute()
            assert.equal(100, player.modData.bathroomNeed)
            effects.bladder = 0
        end)

        it("leaves Lifestyle's need alone without its toilet system", function()
            player.modData.LSMoodles = nil
            local effects = Client.section(player, "effects")
            effects.bladder = 60
            ClientLifestyle.minute()
            assert.equal(20, player.modData.bathroomNeed)
            effects.bladder = 0
        end)
    end)
end)
