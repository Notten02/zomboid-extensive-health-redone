-- Conditional healing: the tired gate sits at vanilla's first Tired moodle (60% fatigue), not before it.
local Healing = require("ExtensiveHealthRedone/Body/Healing")
local Sim = require("support/sim")

local function tired(fatigue, facts)
    local p = Sim.context()
    p.facts.norm = { FATIGUE = fatigue }
    for k, v in pairs(facts or {}) do
        p.facts[k] = v
    end
    return Healing.check(p)
end

describe("Healing.check fatigue", function()
    it("heals below the Tired moodle", function()
        assert.is_true(tired(0.55))
        assert.is_true(tired(0.6))
    end)

    it("blocks with the Tired moodle", function()
        local ok, reason = tired(0.65)
        assert.is_false(ok)
        assert.equal("tired", reason)
    end)

    it("heals while asleep, or near death, however tired", function()
        assert.is_true(tired(0.95, { asleep = true }))
        assert.is_true(tired(0.95, { health = 10 }))
    end)
end)
