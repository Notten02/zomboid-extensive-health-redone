-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- How a fever feels (Body/FeverFeel): the felt temperature and "Check for Fever"'s answer, chills when the body doesn't
-- show the fever (Real Room Temperature's cold model owns it), the character's remarks while a fever lasts, the
-- Monitor's feverish mark, and the check through the action's server command (Server/Temperature).
local FeverFeel = require("ExtensiveHealthRedone/Body/FeverFeel")
local Sim = require("support/sim")

local function context(opts)
    local p = Sim.context(opts)
    p.facts.stats.TEMPERATURE = 37
    return p
end

local function temp(fever)
    return { fever = fever or false }
end

describe("Check for Fever (FeverFeel.check)", function()
    it("goes by the body without a fever", function()
        assert.equal("UI_EHR_Fever_Check_Normal", FeverFeel.check(temp(), 37))
        assert.equal("UI_EHR_Fever_Check_Cold", FeverFeel.check(temp(), 35.5))
        assert.equal("UI_EHR_Fever_Check_Warm", FeverFeel.check(temp(), 37.6))
    end)

    it("goes by our fever when there is one, in bands", function()
        assert.equal("UI_EHR_Fever_Check_Warm", FeverFeel.check(temp(37.7), 37.7))
        assert.equal("UI_EHR_Fever_Check_Fever", FeverFeel.check(temp(38.4), 38.4))
        assert.equal("UI_EHR_Fever_Check_High", FeverFeel.check(temp(39.2), 39.2))
        assert.equal("UI_EHR_Fever_Check_Burning", FeverFeel.check(temp(40.3), 40.3))
    end)

    it("feels like chills when the body doesn't show the fever", function()
        assert.equal(FeverFeel.CHILLS, FeverFeel.check(temp(38.6), 36.1))
        assert.equal(FeverFeel.CHILLS, FeverFeel.check(temp(38.6), 38.1))   -- just at the gap
        assert.equal("UI_EHR_Fever_Check_Fever", FeverFeel.check(temp(38.6), 38.2))
    end)

    it("never reports less than the body when the body is hotter than the fever", function()
        assert.equal(39.5, FeverFeel.felt(temp(38), 39.5))
        assert.is_false(FeverFeel.hidden(temp(38), 39.5))
    end)
end)

describe("fever remarks (FeverFeel.update)", function()
    local function update(p, fever, dt)
        p.state.temperature.fever = fever
        Sim.step(p)
        FeverFeel.update(p, dt or 1)
    end

    it("says when a fever comes on and when it ends, once each", function()
        local p = context()
        update(p, 37.2)
        assert.same({ FeverFeel.START }, p.said)
        update(p, 37.4)
        assert.equal(1, #p.said)                              -- no remark under REMARK_FROM, no roll anyway
        update(p, false)
        assert.same({ FeverFeel.START, FeverFeel.END }, p.said)
        update(p, false)
        assert.equal(2, #p.said)
    end)

    it("remarks now and then while the fever lasts, by how bad it is", function()
        local p = context({ float = 0, sandbox = { DialogueFrequency = 3 } })
        update(p, 38.4)                                      -- comes on
        p.facts.stats.TEMPERATURE = 38.4
        update(p, 38.4)
        assert.equal("UI_EHR_Text_IFeelFeverish", p.said[2])
        p.facts.stats.TEMPERATURE = 39.8
        update(p, 39.8)
        assert.equal("UI_EHR_Text_ImBurningUp", p.said[3])
    end)

    it("remarks on chills while the body doesn't show the fever", function()
        local p = context({ float = 0, sandbox = { DialogueFrequency = 3 } })
        update(p, 38.6)
        p.facts.stats.TEMPERATURE = 36.0
        update(p, 38.6)
        assert.equal(FeverFeel.CHILLS, p.said[2])
    end)

    it("stays quiet asleep and with dialogue off, and still tracks the fever", function()
        local p = context({ float = 0 })
        p.facts.asleep = true
        update(p, 38.6)
        update(p, 38.6)
        assert.equal(0, #p.said)
        assert.is_true(p.state.temperature.feverOn)
        local q = context({ float = 0, sandbox = { DialogueFrequency = 1 } })
        update(q, 38.6)
        update(q, 38.6)
        update(q, false)
        assert.equal(0, #q.said)
    end)

    it("takes an older save without the field as no fever", function()
        local p = context()
        p.state.temperature.feverOn = nil
        update(p, false)
        assert.equal(0, #p.said)
    end)
end)

describe("the Monitor's body temperature", function()
    local Monitor = require("ExtensiveHealthRedone/UI/Monitor")
    local Schema = require("ExtensiveHealthRedone/Core/Schema")
    local defs = require("ExtensiveHealthRedone/Conditions/Registry")

    local function body(fever, bodyC)
        local s = Schema.defaults()
        s.temperature.fever = fever
        local model = Monitor.build({ state = s, firstAid = 0, defs = defs,
            sandbox = function(_, default) return default end, bodyC = bodyC })
        return model.temperature.body
    end

    it("is marked feverish while we keep a fever, the reading staying the body's", function()
        local marked = body(38.6, 36.1)
        assert.equal("UI_EHR_Monitor_BodyTempFever", marked.key)
        assert.equal("UI_EHR_Monitor_BodyTemp", body(false, 36.1).key)
    end)
end)

insulate("single-player wiring: Check for Fever", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    local player = game.addPlayer({})
    game.events.OnCreatePlayer.trigger(0, player)
    require("ExtensiveHealthRedone/Server/Main")
    local Authority = require("ExtensiveHealthRedone/Actions/Authority")
    local Client = require("ExtensiveHealthRedone/Client/Client")
    game.events.OnGameBoot.trigger()
    game.events.OnGameStart.trigger()
    game.advance(2)

    local said = {}
    Client.on("say", function(args) said[#said + 1] = args.key end)

    local function state()
        return player.modData.ExtensiveHealthRedone
    end

    it("answers from our fever, even when the body doesn't show it", function()
        assert.is_true(Authority.run(player, "temperature.checkFever", {}))
        assert.equal("UI_EHR_Fever_Check_Normal", said[#said])
        state().temperature.fever = 38.6
        player.stats.TEMPERATURE = 36.0
        Authority.run(player, "temperature.checkFever", {})
        assert.equal(FeverFeel.CHILLS, said[#said])
    end)

    it("can't be sent by a client: only the action runs it", function()
        local before = #said
        Client.send(player, "temperature.checkFever", {})
        assert.equal(before, #said)
    end)
end)
