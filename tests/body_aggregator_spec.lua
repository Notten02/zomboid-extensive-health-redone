-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
local BodyAggregator = require("ExtensiveHealthRedone/Core/BodyAggregator")

describe("BodyAggregator", function()
    it("caps healing at the lock, lets a factor of the gain through, and follows damage down", function()
        -- not capped: nothing to write, no lock
        assert.same({}, { BodyAggregator.resolveHeal(nil, 80, 70) })
        assert.same({}, { BodyAggregator.resolveHeal(1, 80, 70) })
        -- first capped step records the current value
        local hp, lock = BodyAggregator.resolveHeal(0, 80, nil)
        assert.is_nil(hp)
        assert.equal(80, lock)
        -- vanilla healed 4: blocked entirely, or half of it
        assert.same({ 80, 80 }, { BodyAggregator.resolveHeal(0, 84, 80) })
        assert.same({ 82, 82 }, { BodyAggregator.resolveHeal(0.5, 84, 80) })
        -- damage lowers the lock
        assert.same({ nil, 60 }, { BodyAggregator.resolveHeal(0, 60, 80) })
    end)

    it("tracks the pain it added so it can take exactly that away again", function()
        assert.same({ 40, 30 }, { BodyAggregator.resolvePain(30, 10, 0) })
        assert.same({ 20, 10 }, { BodyAggregator.resolvePain(10, 40, 30) })
        assert.same({ 10, 0 }, { BodyAggregator.resolvePain(nil, 20, 10) })
        assert.same({ 0, 0 }, { BodyAggregator.resolvePain(nil, 5, 10) })   -- vanilla already faded some
    end)

    it("sums pain per part over sources, keeps the lowest heal factor, and lets disinfect win", function()
        local body = BodyAggregator.new()
        body:pain("Neck", "tetanus", 8)
        body:pain("Neck", "woundInfection", 10)
        body:healFactor("Neck", "a", 0.5)
        body:healFactor("Neck", "b", 0.75)
        body:infect("Hand_L", "stitch")
        body:disinfect("Hand_L", "woundInfection")
        body:infect("Hand_L", "stitch")
        assert.same({ Neck = 18 }, body:painTargets())
        assert.equal(0.5, body.heal.Neck)
        assert.is_false(body.infection.Hand_L)
    end)

    it("applies damage in source order, each above its own floor", function()
        local body = BodyAggregator.new()
        body:damage("sepsis", 30, 65)
        body:damage("ahtr", 10, 50)
        -- ahtr first: 80 -> 70; then sepsis may only go to 65
        assert.equal(15, body:resolveDamage(80))
        local none = BodyAggregator.new()
        none:damage("x", 0, 0)
        assert.equal(0, none:resolveDamage(50))
    end)

    it("keeps the first kill", function()
        local body = BodyAggregator.new()
        body:kill("blood", "exsanguination")
        body:kill("sepsis", "sepsis")
        assert.equal("exsanguination", body.killed.cause)
        assert.has_error(function() body:pain("Neck", nil, 1) end)
    end)

    it("keeps the strongest cold wish, writes vanilla's cold only on change, and clears ours once", function()
        local body = BodyAggregator.new()
        body:cold("common_cold", 35)
        body:cold("pneumonia", 10)
        assert.equal(35, body.coldStrength)
        assert.same({ 35, 35 }, { BodyAggregator.resolveCold(35, nil, 0) })
        assert.same({ nil, 35 }, { BodyAggregator.resolveCold(35, 35, 35) })
        assert.same({ 35, 35 }, { BodyAggregator.resolveCold(35, 35, 30) })      -- vanilla drifted: write again
        assert.same({ 0, nil }, { BodyAggregator.resolveCold(nil, 35, 35) })     -- no wish any more: clear once
        assert.same({ nil, nil }, { BodyAggregator.resolveCold(nil, nil, 20) })  -- vanilla's own cold: left alone
    end)
end)

describe("BodyAggregator scratches", function()
    it("keeps one scratch per part, from the first source", function()
        local body = BodyAggregator.new()
        assert.is_nil(body.scratches)
        body:scratch("Hand_L", "scabies")
        body:scratch("Hand_L", "other")
        body:scratch("Foot_R", "scabies")
        assert.same({ Hand_L = "scabies", Foot_R = "scabies" }, body.scratches)
        assert.has_error(function() body:scratch("Hand_L") end)
    end)
end)
