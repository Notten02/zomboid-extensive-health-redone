-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Corpse exposure illness and cadaveric aspergillosis: the two exposure meters, contraction, W15 (independent meters,
-- fresh air speeds recovery, bands 30/60/100) and the stage effects.
local Engine = require("ExtensiveHealthRedone/Conditions/Engine")
local defs = require("ExtensiveHealthRedone/Conditions/Registry")
local Exposure = require("ExtensiveHealthRedone/Diseases/Corpse/Exposure")
local Sim = require("support/sim")

local function corpses(p, t)
    p.facts.corpses = { fresh = t.fresh or 0, decomposing = t.decomposing or 0, rotten = t.rotten or 0,
        env = t.env or 1, protection = t.protection or 0, sealed = t.sealed or false }
end

local function meters(p, minutes, step)
    step = step or 10
    local done = 0
    while done < minutes do
        Exposure.update(Sim.step(p), step, defs)
        done = done + step
    end
end

local function run(p, minutes, step)
    step = step or 60
    local done = 0
    while done < minutes do
        Engine.step(Sim.step(p), defs, step)
        done = done + step
    end
end

---@return table
local function contract(p, id, opts)
    return Engine.contract(p, defs, id, opts) --[[@as table]]
end

describe("corpse exposure meter", function()
    it("builds from corpse emission, indoors faster, and decays 30 an hour in fresh air", function()
        local p = Sim.context()
        corpses(p, { rotten = 5, env = 1.5 })
        meters(p, 60)
        assert.near(37.5, p.state.exposure.corpse, 1e-6)    -- 5 rotten x 5/h x 1.5
        corpses(p, {})
        meters(p, 30)
        assert.near(22.5, p.state.exposure.corpse, 1e-6)
    end)

    it("counts fresh, decomposing and rotten corpses differently and scales with CorpseDiseaseSpeed", function()
        local p = Sim.context({ sandbox = { CorpseDiseaseSpeed = 2 } })
        corpses(p, { fresh = 1, decomposing = 1, rotten = 1 })
        meters(p, 60)
        assert.near(16, p.state.exposure.corpse, 1e-6)      -- (1 + 2 + 5) x 2
    end)

    it("halves gain behind a mask, and decays behind a filtered mask or in a sealed vehicle", function()
        local p = Sim.context()
        corpses(p, { rotten = 2, protection = 0.5 })
        meters(p, 60)
        assert.near(5, p.state.exposure.corpse, 1e-6)
        corpses(p, { rotten = 2, protection = 1 })
        meters(p, 10)
        assert.near(0, p.state.exposure.corpse, 1e-6)
        p.state.exposure.corpse = 50
        corpses(p, { rotten = 2, sealed = true })
        meters(p, 60)
        assert.near(20, p.state.exposure.corpse, 1e-6)
    end)

    it("makes the illness certain at 100 and resets the meter", function()
        local p = Sim.context()
        p.state.exposure.corpse = 99
        corpses(p, { rotten = 5 })
        meters(p, 10)
        local c = p.state.conditions.active.corpse_sickness
        assert.truthy(c)
        assert.equal(1, c.stage)
        assert.equal(0, p.state.exposure.corpse)
        assert.is_true(Sim.said(p, "UI_EHR_Text_IDontFeelSoGoodMustBeTheCorpses"))
    end)

    it("rolls hourly between 85 and 100 after an hour in the area", function()
        local p = Sim.context({ floats = { 0.29 } })
        p.state.exposure.corpse = 86
        corpses(p, { fresh = 1 })               -- 1/h: stays in the risk band
        meters(p, 50)
        assert.is_nil(p.state.conditions.active.corpse_sickness)  -- under an hour in the area
        meters(p, 10)
        assert.truthy(p.state.conditions.active.corpse_sickness)  -- 0.29 < 0.30 + a little
    end)

    it("does nothing when corpse illness is off, and stays at 0 for 2 h after recovering", function()
        local off = Sim.context({ sandbox = { CorpseSicknessEnabled = false } })
        corpses(off, { rotten = 5 })
        meters(off, 60)
        assert.equal(0, off.state.exposure.corpse)

        local p = Sim.context()
        contract(p, "corpse_sickness")
        Engine.cure(p, defs, "corpse_sickness")
        corpses(p, { rotten = 5 })
        local function both(minutes)
            for _ = 1, minutes / 10 do
                Engine.step(Sim.step(p), defs, 10)
                Exposure.update(p, 10, defs)
            end
        end
        both(110)
        assert.equal(0, p.state.exposure.corpse)
        both(20)
        assert.is_true(p.state.exposure.corpse > 0)
    end)

    it("reads the display bands 30/60/100 (W15)", function()
        assert.equal("none", Exposure.band(29))
        assert.equal("low", Exposure.band(30))
        assert.equal("medium", Exposure.band(60))
        assert.equal("high", Exposure.band(100))
    end)
end)

describe("spore meter", function()
    it("needs damp or cold air and decomposing or rotten corpses", function()
        assert.equal(0, Exposure.fungal({ wetness = 0, raining = false, indoors = false, airC = 20 }))
        assert.near(1.6 * 1.25 * 1.15, Exposure.fungal({ wetness = 0.5, raining = false, indoors = true, airC = 5 }),
            1e-9)
        assert.near(1.6, Exposure.fungal({ wetness = 0, raining = true, indoors = false, airC = 20 }), 1e-9)
        assert.equal(0, Exposure.fungal({ wetness = 0, raining = true, indoors = true, airC = 20 }))

        local p = Sim.context()
        p.facts.env.airC = 5
        corpses(p, { fresh = 10 })
        meters(p, 60)
        assert.equal(0, p.state.exposure.spores)
        corpses(p, { rotten = 5 })
        meters(p, 60)
        assert.near(10 * 1.8 * 1.25, p.state.exposure.spores, 1e-6)
    end)

    it("builds alongside the corpse meter in damp weather (W15)", function()
        local p = Sim.context()
        p.facts.env.wetness = 0.5
        corpses(p, { rotten = 2 })
        meters(p, 60)
        assert.near(10, p.state.exposure.corpse, 1e-6)
        assert.near(4 * 1.8 * 1.6, p.state.exposure.spores, 1e-6)
    end)

    it("starts aspergillosis for certain at 120", function()
        local p = Sim.context()
        p.facts.env.airC = 0
        p.state.exposure.spores = 119
        corpses(p, { rotten = 5 })
        meters(p, 10)
        assert.truthy(p.state.conditions.active.cadaveric_aspergillosis)
        assert.equal(0, p.state.exposure.spores)
    end)
end)

describe("corpse illness", function()
    it("runs twice as fast in fresh air once the incubation is over (W15)", function()
        local p = Sim.context()
        local c = contract(p, "corpse_sickness", { stage = 2 })
        local left = c.left
        p.state.exposure.corpse = 10
        run(p, 60)
        assert.near(left - 60, c.left, 1e-6)
        p.state.exposure.corpse = 0
        run(p, 60)
        assert.near(left - 180, c.left, 1e-6)
    end)

    it("brings nausea, headache and slower walking at stage 3, and never kills", function()
        local p = Sim.context()
        contract(p, "corpse_sickness", { stage = 3 })
        run(p, 1, 1)
        assert.equal(0.85, p.fx.values.speed)
        assert.is_true(Sim.resolve(p, "SICKNESS", 0) > 0)
        assert.is_true(p.body:painTargets().Head > 0)
        assert.same({}, p.body.damages)
    end)

    it("coughs with sound and world noise", function()
        local p = Sim.context({ float = 0 })
        contract(p, "corpse_sickness", { stage = 3 })
        run(p, 1, 1)
        assert.equal("coughSevere", p.noises[1][1])
    end)
end)

describe("cadaveric aspergillosis", function()
    it("takes away sprinting and drains health without a floor at stage 3 untreated", function()
        local p = Sim.context()
        contract(p, "cadaveric_aspergillosis", { stage = 3, severity = 1 })
        run(p, 27, 27)
        assert.is_true(p.fx.values.noSprint)
        assert.equal(0.75, p.fx.values.speed)
        assert.near(0.55 + 1.30, p.body.damages[1].hp, 1e-9)
        assert.equal(0, p.body.damages[1].floor)
        assert.equal(0, p.body.heal.Head)
    end)

    it("stops the drain while a curative course runs", function()
        local p = Sim.context({ treatment = { curing = { cadaveric_aspergillosis = true } } })
        contract(p, "cadaveric_aspergillosis", { stage = 3 })
        run(p, 60)
        assert.same({}, p.body.damages)
    end)
end)

insulate("single-player wiring: corpses, scabies scratches and concussion reports", function()
    local FakeGame = require("support/fake_game")
    local game = FakeGame.install()
    _G.ItemTag = _G.ItemTag or { GAS_MASK = "GAS_MASK", IMPROVISED_GAS_MASK = "IMPROVISED_GAS_MASK",
        RESPIRATOR = "RESPIRATOR", MUFFLE_SNEEZE = "MUFFLE_SNEEZE" }
    local Client = require("ExtensiveHealthRedone/Client/Client")
    local player = game.addPlayer({})
    game.events.OnCreatePlayer.trigger(0, player)
    require("ExtensiveHealthRedone/Server/Main")
    require("ExtensiveHealthRedone/Server/Corpse")
    local Runtime = require("ExtensiveHealthRedone/Server/Runtime")
    game.events.OnGameStart.trigger()
    game.advance(2)

    local function state()
        return player.modData.ExtensiveHealthRedone
    end

    local function corpse(x, y, ageHours, props)
        local sq = FakeGame.newSquare(x, y, 0)
        game.squares[x .. "," .. y .. ",0"] = sq
        local body = { death = game.minutes / 60 - ageHours }
        for k, v in pairs(props or {}) do body[k] = v end
        function body:getDeathTime() return self.death end
        function body:isSkeleton() return self.skeleton == true end
        function body:isAnimal() return self.animal == true end
        sq.deadBodies[#sq.deadBodies + 1] = body
        return sq
    end

    it("finds rotten corpses sharing the air and builds the meter; skeletons and other rooms don't count", function()
        corpse(103, 100, 60)
        corpse(104, 100, 60, { skeleton = true })
        corpse(130, 100, 60)                         -- beyond 10 tiles
        local indoors = corpse(100, 105, 60)
        indoors.room = { getRoomDef = function() return nil end }
        game.advance(60)
        assert.near(5, state().exposure.corpse, 0.5)
    end)

    it("stops building behind a gas mask with a working filter", function()
        local mask = { clothing = true, filter = "Base.Hat_GasMask_nofilter", delta = 0.5 }
        function mask:hasTag(tag) return tag == ItemTag.GAS_MASK end
        function mask:getWithoutDrainable() return self.filter end
        function mask:getUsedDelta() return self.delta end
        function mask:getCorpseSicknessDefense() return 25 end
        function mask:getFullType() return "Base.Hat_GasMask" end
        player.worn = { mask }
        local before = state().exposure.corpse
        game.advance(30)
        assert.is_true(state().exposure.corpse < before)
        mask.delta = 0                               -- an empty filter only halves it
        local low = state().exposure.corpse
        game.advance(60)
        assert.near(low + 2.5, state().exposure.corpse, 0.5)
        player.worn = {}
    end)

    it("gives scabies' bite as a real vanilla scratch, with no Knox", function()
        local Engine = require("ExtensiveHealthRedone/Conditions/Engine")
        local defs = require("ExtensiveHealthRedone/Conditions/Registry")
        Runtime.applyNow("sp:0", function(p)
            Engine.contract(p, defs, "hyperkeratotic_scabies")
        end)
        game.advance(1)
        local bite = state().conditions.active.hyperkeratotic_scabies.data.bite
        local part = player.body:part(bite)
        assert.is_true(part.flags.scratch)
        assert.is_true(part.scratchTime >= 16)
        assert.is_true(part.additionalPain >= 8)
        assert.is_not_true(player.body:IsInfected())
    end)

    it("rolls for a concussion when a reported fall really hurt the head", function()
        game.float = 0.01
        Client.send(player, "concussion.trauma", { kind = "fall" })
        player.body:part("Head").health = 80
        game.advance(1)
        assert.truthy(state().conditions.active.concussion)
        game.float = nil
    end)
end)
