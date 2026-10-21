-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
local StatAggregator = require("ExtensiveHealthRedone/Core/StatAggregator")

local RANGES = {
    SICKNESS = { min = 0, max = 1 },
    PAIN = { min = 0, max = 100 },
    THIRST = { min = 0, max = 1 },
}

describe("StatAggregator", function()
    it("adds every contribution to the current value instead of replacing it", function()
        local agg = StatAggregator.new(RANGES)
        agg:add("SICKNESS", "food_poisoning", 0.1)
        agg:add("SICKNESS", "dysentery", 0.2)
        local value, changed = agg:resolve("SICKNESS", 0.3)
        assert.near(0.6, value, 1e-9)
        assert.is_true(changed)
    end)

    it("clamps to the stat range", function()
        local agg = StatAggregator.new(RANGES)
        agg:add("PAIN", "a", 80)
        assert.equal(100, (agg:resolve("PAIN", 50)))
        agg:clear()
        agg:add("PAIN", "a", -80)
        assert.equal(0, (agg:resolve("PAIN", 50)))
    end)

    it("applies the lowest ceiling and the highest floor, and the floor wins a conflict", function()
        local agg = StatAggregator.new(RANGES)
        agg:ceiling("THIRST", "a", 0.8)
        agg:ceiling("THIRST", "b", 0.6)
        assert.equal(0.6, (agg:resolve("THIRST", 0.9)))
        agg:floor("THIRST", "c", 0.7)
        agg:floor("THIRST", "d", 0.65)
        assert.equal(0.7, (agg:resolve("THIRST", 0.9)))
    end)

    it("leaves a value alone when nothing touched the stat", function()
        local agg = StatAggregator.new(RANGES)
        local value, changed = agg:resolve("PAIN", 42)
        assert.equal(42, value)
        assert.is_false(changed)
    end)

    it("reports a floor that is already met as unchanged", function()
        local agg = StatAggregator.new(RANGES)
        agg:floor("PAIN", "concussion", 30)
        local value, changed = agg:resolve("PAIN", 45)
        assert.equal(45, value)
        assert.is_false(changed)
    end)

    it("lists touched stats sorted and explains contributions in order", function()
        local agg = StatAggregator.new(RANGES)
        agg:add("THIRST", "x", 0.1)
        agg:floor("PAIN", "y", 10)
        agg:add("PAIN", "z", 5)
        assert.same({ "PAIN", "THIRST" }, agg:touched())
        assert.same({
            { source = "y", kind = "floor", value = 10 },
            { source = "z", kind = "add", value = 5 },
        }, agg:explain("PAIN"))
    end)

    it("rejects unknown stats and missing sources", function()
        local agg = StatAggregator.new(RANGES)
        assert.has_error(function() agg:add("HAPPINESS", "x", 1) end)
        assert.has_error(function() agg:add("PAIN", nil, 1) end)
    end)
    it("moves toward a raise or lower target without overshooting, keeping the most extreme target", function()
        local agg = StatAggregator.new(RANGES)
        agg:raise("SICKNESS", "sepsis", 0.6, 0.1)
        agg:raise("SICKNESS", "cellulitis", 0.4, 0.5)
        assert.near(0.3, (agg:resolve("SICKNESS", 0.2)), 1e-9)
        assert.near(0.6, (agg:resolve("SICKNESS", 0.55)), 1e-9)
        assert.equal(0.7, (agg:resolve("SICKNESS", 0.7)))       -- never pulls down
        agg:clear()
        agg:lower("THIRST", "a", 0.3, 0.05)
        assert.near(0.45, (agg:resolve("THIRST", 0.5)), 1e-9)
        assert.equal(0.2, (agg:resolve("THIRST", 0.2)))
    end)

    it("takes fractions of the range in the F methods, whatever the stat's scale", function()
        local agg = StatAggregator.new(RANGES)
        agg:addF("PAIN", "reaction", 0.12)
        agg:addF("SICKNESS", "reaction", 0.12)
        assert.near(12, (agg:resolve("PAIN", 0)), 1e-9)
        assert.near(0.12, (agg:resolve("SICKNESS", 0)), 1e-9)
        agg:clear()
        agg:ceilingF("PAIN", "x", 0.5)
        agg:raiseF("THIRST", "y", 0.5, 0.25)
        assert.equal(50, (agg:resolve("PAIN", 90)))
        assert.near(0.25, (agg:resolve("THIRST", 0)), 1e-9)
    end)
end)
