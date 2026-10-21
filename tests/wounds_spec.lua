-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Wound infection per body part, the tetanus triggers and the stitch minigame outcomes (Wounds/).
local Infection = require("ExtensiveHealthRedone/Wounds/Infection")
local Tetanus = require("ExtensiveHealthRedone/Wounds/Tetanus")
local Stitch = require("ExtensiveHealthRedone/Wounds/Stitch")
local defs = require("ExtensiveHealthRedone/Conditions/Registry")
local Sim = require("support/sim")

local function infectedWound(p, name)
    local part = p.facts.parts[name]
    part.infected = true
    part.wound = true
    part.cut = true
    return part
end

local function step(p, dt)
    Infection.update(Sim.step(p), dt, defs)
end

describe("Wound infection", function()
    it("starts an incubation when vanilla infects an open wound", function()
        local p = Sim.context({ sandbox = { WoundInfectionSpeed = 2 } })
        infectedWound(p, "Hand_L")
        step(p, 1)
        local e = p.state.wounds.parts.Hand_L
        assert.equal("incubating", e.phase)
        assert.near(12 * 60 / 2, e.left, 1e-9)
    end)

    it("clears vanilla residue on a healed part, and anything new while antiseptic cream is active", function()
        local p = Sim.context()
        p.facts.parts.Hand_L.infected = true
        step(p, 1)
        assert.is_nil(p.state.wounds.parts.Hand_L)
        assert.is_false(p.body.infection.Hand_L)

        local q = Sim.context({ treatment = { active = { antiseptic = true } } })
        infectedWound(q, "Hand_R")
        step(q, 1)
        assert.is_nil(q.state.wounds.parts.Hand_R)
        assert.is_false(q.body.infection.Hand_R)
    end)

    it("becomes a stage-1 infection after the incubation, unless the immune system contains it", function()
        local p = Sim.context()
        infectedWound(p, "Hand_L")
        step(p, 1)
        step(p, 12 * 60)
        assert.equal("infected", p.state.wounds.parts.Hand_L.phase)
        assert.equal(1, p.state.wounds.parts.Hand_L.stage)
        assert.is_true(Sim.said(p, "UI_EHR_Text_ThisWoundLooksInfected"))

        assert.near(0.45, Infection.containChance(100), 1e-9)
        assert.equal(0, Infection.containChance(20))
        local q = Sim.context({ floats = { 0.1 } })
        q.state.immunity.score = 100
        infectedWound(q, "Hand_L")
        step(q, 1)
        step(q, 12 * 60)
        assert.is_nil(q.state.wounds.parts.Hand_L)
    end)

    it("goes through stages 1-3 (12/24/48 h) with pain, slower healing and fever, then hands off to sepsis", function()
        local p = Sim.context()
        Infection.start(p, "ForeArm_L", 1)
        step(p, 1)
        assert.equal(0.75, p.body.heal.ForeArm_L)
        step(p, 12 * 60)
        assert.equal(2, p.state.wounds.parts.ForeArm_L.stage)
        assert.equal(10, p.body.pains.ForeArm_L.woundInfection)
        assert.equal(0.5, p.body.heal.ForeArm_L)
        step(p, 24 * 60)
        assert.equal(3, p.state.wounds.parts.ForeArm_L.stage)
        assert.equal(0, p.body.heal.ForeArm_L)
        assert.is_true(Sim.resolve(p, "TEMPERATURE", 37) > 37)
        step(p, 48 * 60)
        assert.truthy(p.state.conditions.active.sepsis)
        assert.equal(3, p.state.wounds.parts.ForeArm_L.stage)
    end)

    it("holds while a curative course runs", function()
        local p = Sim.context({ treatment = { curing = { woundInfection = true } } })
        Infection.start(p, "ForeArm_L", 3)
        step(p, 100 * 60)
        assert.is_nil(p.state.conditions.active.sepsis)
        assert.equal(3, p.state.wounds.parts.ForeArm_L.stage)
    end)

    it("is prevented by disinfecting during the incubation, but not stopped once infected", function()
        local p = Sim.context()
        infectedWound(p, "Hand_L")
        step(p, 1)
        assert.equal("prevented", Infection.disinfected(p, "Hand_L"))
        assert.is_nil(p.state.wounds.parts.Hand_L)
        Infection.start(p, "Hand_R", 2)
        local left = p.state.wounds.parts.Hand_R.left
        assert.equal("stillInfected", Infection.disinfected(p, "Hand_R"))
        assert.equal(left, p.state.wounds.parts.Hand_R.left)
        assert.equal("none", Infection.disinfected(p, "Neck"))
    end)

    it("drops one stage per dose of vanilla antibiotics, and is cured below stage 1", function()
        local p = Sim.context()
        Infection.start(p, "Hand_L", 2)
        Infection.start(p, "Hand_R", 1)
        assert.equal(2, Infection.antibiotics(p))
        assert.equal(1, p.state.wounds.parts.Hand_L.stage)
        assert.is_nil(p.state.wounds.parts.Hand_R)
        assert.is_false(p.body.infection.Hand_R)
    end)
end)

describe("Tetanus triggers", function()
    local function deepGlass(p, name)
        local part = p.facts.parts[name]
        part.deep, part.glass = true, true
        return part
    end

    it("roll for a deep wound with glass at once, then every 12 h at 40/55/70 %", function()
        assert.near(0.40, Tetanus.glassChance(0), 1e-9)
        assert.near(0.55, Tetanus.glassChance(1), 1e-9)
        assert.near(0.70, Tetanus.glassChance(5), 1e-9)
        local p = Sim.context({ floats = { 0.45, 0.5, 0.5, 0.5, 0.54 } })
        deepGlass(p, "UpperLeg_L")
        Tetanus.update(p, 1, defs, true)
        assert.is_nil(p.state.conditions.active.tetanus)        -- 0.45 misses 40 %
        Tetanus.update(p, 12 * 60, defs, true)
        assert.truthy(p.state.conditions.active.tetanus)        -- 0.54 hits 55 %
        assert.equal("glass", p.state.conditions.active.tetanus.source)
    end)

    it("scale with TetanusChanceMultiplier", function()
        local p = Sim.context({ floats = { 0.0 }, sandbox = { TetanusChanceMultiplier = 0 } })
        deepGlass(p, "Hand_L")
        Tetanus.update(p, 1, defs, true)
        assert.is_nil(p.state.conditions.active.tetanus)
    end)

    it("roll for a new deep wound in a vehicle (a crash), but not on the first look after login", function()
        local p = Sim.context({ floats = { 0.3, 0.3 } })
        p.facts.inVehicle = true
        p.facts.parts.Head.deep = true
        Tetanus.update(p, 1, defs, false)
        assert.is_nil(p.state.conditions.active.tetanus)
        local q = Sim.context({ floats = { 0.3 } })
        Tetanus.update(q, 1, defs, true)
        q.facts.inVehicle = true
        q.facts.parts.Head.deep = true
        Tetanus.update(q, 1, defs, true)
        assert.equal("crash", q.state.conditions.active.tetanus.source)
    end)

    it("roll for glass appearing in a foot outside a vehicle (walking on glass)", function()
        local p = Sim.context({ floats = { 0.15 } })
        Tetanus.update(p, 1, defs, true)
        p.facts.parts.Foot_R.glass = true
        Tetanus.update(p, 1, defs, true)
        assert.equal("glass", p.state.conditions.active.tetanus.source)
    end)

    it("roll every 12 h for a deep wound left unbandaged or under a dirty bandage", function()
        local p = Sim.context({ floats = { 0.1 } })
        p.facts.parts.Torso_Lower.deep = true
        p.facts.parts.Torso_Lower.bandaged = true
        Tetanus.update(p, 1, defs, true)
        Tetanus.update(p, 13 * 60, defs, true)
        assert.is_nil(p.state.conditions.active.tetanus)        -- clean bandage: no roll
        p.facts.parts.Torso_Lower.bandageDirty = true
        Tetanus.update(p, 11 * 60, defs, true)
        assert.is_nil(p.state.conditions.active.tetanus)
        Tetanus.update(p, 60, defs, true)
        assert.equal("dirtyWound", p.state.conditions.active.tetanus.source)
    end)
end)

describe("Stitch minigame outcomes", function()
    it("allows 4/5/6 misses by First Aid and maps misses to quality bands", function()
        assert.equal(4, Stitch.maxMisses(0))
        assert.equal(5, Stitch.maxMisses(4))
        assert.equal(6, Stitch.maxMisses(8))
        assert.equal(6, Stitch.maxMisses(10))
        assert.equal("excellent", Stitch.band(Stitch.quality(0)))
        assert.equal("stable", Stitch.band(Stitch.quality(2)))
        assert.equal("rough", Stitch.band(Stitch.quality(3)))
        assert.equal("poor", Stitch.band(Stitch.quality(4)))
        assert.equal(0.35, Stitch.quality(9))
    end)

    it("rolls 40 % cellulitis on a rough stitch, on the stitched part", function()
        local p = Sim.context({ floats = { 0.39 } })
        local r = Stitch.applySuccess(p, defs, "ForeArm_R", 3, false)
        assert.is_true(r.cellulitis)
        assert.equal("ForeArm_R", p.state.conditions.active.cellulitis.source)
        assert.equal(5, p.body.oneOff.ForeArm_R)
        local q = Sim.context({ floats = { 0.41 } })
        assert.is_false(Stitch.applySuccess(q, defs, "ForeArm_R", 3, false).cellulitis)
    end)

    it("can infect the wound on a poor stitch, and eases pain on an excellent one", function()
        local p = Sim.context({ floats = { 0.2, 0.9 } })
        local r = Stitch.applySuccess(p, defs, "Hand_L", 4, false)
        assert.is_true(r.infected)
        assert.is_true(p.body.infection.Hand_L)
        assert.equal(12, p.body.oneOff.Hand_L)
        local q = Sim.context({ floats = { 0.0, 0.9 } })
        assert.is_false(Stitch.applySuccess(q, defs, "Hand_L", 4, true).infected)
        local e = Sim.context()
        Stitch.applySuccess(e, defs, "Hand_L", 0, false)
        assert.equal(-5, e.body.oneOff.Hand_L)
    end)

    it("hurts on a failure, and rolls cellulitis for a started attempt below stable", function()
        local p = Sim.context({ floats = { 0.1 } })
        local r = Stitch.applyAbort(p, defs, "Hand_L", 4, true, true)
        assert.is_true(r.cellulitis)
        assert.equal(10, p.body.oneOff.Hand_L)
        local q = Sim.context({ floats = { 0.1 } })
        assert.is_false(Stitch.applyAbort(q, defs, "Hand_L", 0, false, false).cellulitis)
        assert.is_nil(q.body.oneOff.Hand_L)
    end)
end)
