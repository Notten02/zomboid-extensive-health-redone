-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The extremities group's shared pieces (Diseases/Extremities): the readings from facts.extremities, the saved meters
-- and the per-part stages inside one condition.
local Inputs = require("ExtensiveHealthRedone/Diseases/Extremities/Inputs")
local Meters = require("ExtensiveHealthRedone/Diseases/Extremities/Meters")
local Parts = require("ExtensiveHealthRedone/Diseases/Extremities/Parts")
local Sim = require("support/sim")

local function extremities(t)
    t = t or {}
    t.parts = t.parts or { Hand_L = { skinC = 30, insulation = 0.5 }, Hand_R = { skinC = 31, insulation = 0 },
        Foot_L = { skinC = 28, insulation = 1 }, Foot_R = { skinC = 29, insulation = 1 } }
    t.windChillC = t.windChillC or 20
    return t
end

describe("extremities inputs", function()
    it("has nothing without facts.extremities", function()
        local p = Sim.context()
        assert.is_false(Inputs.available(p))
        assert.is_false(Inputs.present(p, "Foot_L"))
        assert.are.equal(0, Inputs.feetWet(p))
        assert.is_nil(Inputs.skinC(p, "Hand_L"))
        assert.are.equal(0, Inputs.insulation(p, "Hand_L"))
    end)

    it("skips amputated parts", function()
        local p = Sim.context()
        p.facts.extremities = extremities()
        p.facts.missing = { Hand_L = true }
        assert.is_false(Inputs.present(p, "Hand_L"))
        assert.is_true(Inputs.present(p, "Hand_R"))
    end)

    it("takes the feet's wetness from the socks first", function()
        local p = Sim.context()
        p.facts.env.wetness = 0.9
        p.facts.extremities = extremities({ socks = { wet = 0.4, holes = 0 },
            shoes = { wet = 1, holes = 0, wear = 1, waterRes = 0 } })
        assert.are.equal(0.4, Inputs.feetWet(p))
    end)

    it("takes the inside of the shoes without socks, less their water resistance", function()
        local p = Sim.context()
        p.facts.extremities = extremities({ shoes = { wet = 0.8, holes = 0, wear = 1, waterRes = 0.5 } })
        assert.are.equal(0.4, Inputs.feetWet(p))
    end)

    it("takes the body's wetness barefoot, and for hands without gloves", function()
        local p = Sim.context()
        p.facts.env.wetness = 0.6
        p.facts.extremities = extremities()
        assert.are.equal(0.6, Inputs.feetWet(p))
        assert.are.equal(0.6, Inputs.handsWet(p))
        p.facts.extremities.gloves = { wet = 0.1, holes = 0 }
        assert.are.equal(0.1, Inputs.wet(p, "Hand_R"))
        assert.are.equal(0.6, Inputs.wet(p, "Foot_R"))
    end)

    it("describes the footwear", function()
        local p = Sim.context()
        p.facts.extremities = extremities({ socks = { wet = 0, holes = 2 },
            shoes = { wet = 0, holes = 1, wear = 0.3, waterRes = 0 } })
        local f = Inputs.footwear(p)
        assert.is_true(f.socks and f.shoes)
        assert.are.same({ 2, 1, 0.3 }, { f.socksHoles, f.shoesHoles, f.shoeWear })
        p.facts.extremities = extremities()
        f = Inputs.footwear(p)
        assert.is_false(f.socks or f.shoes)
        assert.are.equal(1, f.shoeWear)
    end)

    it("reads skin temperature and insulation per part", function()
        local p = Sim.context()
        p.facts.extremities = extremities()
        assert.are.equal(28, Inputs.skinC(p, "Foot_L"))
        assert.are.equal(0.5, Inputs.insulation(p, "Hand_L"))
    end)
end)

describe("extremities meters", function()
    it("lives in the exposure scratch and clamps", function()
        local p = Sim.context()
        assert.are.equal(0, Meters.value(p, "Foot_L", "frictionH"))
        Meters.set(p, "Foot_L", "frictionH", 9, 7)
        assert.are.equal(7, p.state.exposure.data.extremities.parts.Foot_L.frictionH)
        Meters.set(p, "Foot_L", "frictionH", -1)
        assert.are.equal(0, Meters.value(p, "Foot_L", "frictionH"))
    end)

    it("clears one meter on every part", function()
        local p = Sim.context()
        Meters.set(p, "Foot_L", "frictionH", 2)
        Meters.set(p, "Foot_R", "frictionH", 3)
        Meters.set(p, "Foot_R", "wetColdH", 4)
        Meters.clear(p, "frictionH")
        assert.are.equal(0, Meters.value(p, "Foot_R", "frictionH"))
        assert.are.equal(4, Meters.value(p, "Foot_R", "wetColdH"))
    end)
end)

describe("extremities parts", function()
    local function condition()
        return { stage = 1, data = {} }
    end

    it("marks conditions dirty only when a part's stage changes", function()
        local p = Sim.context()
        local c = condition()
        assert.is_true(Parts.setStage(p, c, "Foot_L", 2))
        assert.is_false(Parts.setStage(p, c, "Foot_L", 2))
        assert.are.equal(1, p.dirtied.conditions)
        assert.are.equal(2, c.data.maxStage)
    end)

    it("follows the worst part, ties in fixed order", function()
        local p = Sim.context()
        local c = condition()
        Parts.setStage(p, c, "Hand_R", 2)
        Parts.setStage(p, c, "Foot_R", 2)
        assert.are.equal(2, Parts.result(p, c))
        assert.are.equal("Foot_R", c.source)
        Parts.setStage(p, c, "Hand_L", 3)
        assert.are.equal(3, Parts.result(p, c))
        assert.are.equal("Hand_L", c.source)
        assert.are.same({ { part = "Foot_R", stage = 2 }, { part = "Hand_L", stage = 3 },
            { part = "Hand_R", stage = 2 } }, Parts.list(c))
    end)

    it("recovers when no part is affected", function()
        local p = Sim.context()
        local c = condition()
        Parts.setStage(p, c, "Foot_L", 1)
        Parts.setStage(p, c, "Foot_L", 0)
        assert.are.equal("recovered", Parts.result(p, c))
        Parts.setStage(p, c, "Foot_R", 1)
        assert.is_true(Parts.drop(p, c, "Foot_R"))
        assert.is_false(Parts.drop(p, c, "Foot_R"))
        assert.are.equal("recovered", Parts.result(p, c))
    end)
end)
