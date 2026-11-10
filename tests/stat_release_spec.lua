-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Giving back stats vanilla never lowers (Body/StatRelease): EHR's share of SICKNESS grows with what its sources add,
-- shrinks when anything lowers the stat, and is released once no source holds it, without touching another mod's
-- sickness. Saves from before the share existed claim their leftover once (schema 5 -> 6, imports).
local StatRelease = require("ExtensiveHealthRedone/Body/StatRelease")
local Schema = require("ExtensiveHealthRedone/Core/Schema")
local Importer = require("ExtensiveHealthRedone/Core/Importer")
local Systems = require("ExtensiveHealthRedone/Systems")
local Fixtures = require("fixtures/legacy_ehr")
local Sim = require("support/sim")

local PER_HOUR = StatRelease.STATS.SICKNESS.perHour

local function context(sickness)
    local p = Sim.context()
    p.facts.stats.SICKNESS = sickness or 0
    return p
end

-- One game minute the way Server/Runtime runs it: the sources (optional), the release system, the accounting, then
-- the write. Returns the new SICKNESS.
local function minute(p, source)
    if source then
        source(p)
    end
    StatRelease.update(p, 1)
    StatRelease.account(p)
    p.facts.stats.SICKNESS = Sim.resolve(p, "SICKNESS", p.facts.stats.SICKNESS)
    Sim.step(p)
    return p.facts.stats.SICKNESS
end

local function run(p, minutes, source)
    for _ = 1, minutes do
        minute(p, source)
    end
    return p.facts.stats.SICKNESS
end

local function disease(target)
    return function(p)
        p.stats:raiseF("SICKNESS", "disease", target, 0.01)
    end
end

local function owned(p)
    return p.state.body.statOwned.SICKNESS or 0
end

describe("StatRelease", function()
    it("gives sickness back once the disease that raised it ends", function()
        local p = context(0)
        assert.near(0.3, run(p, 60, disease(0.3)), 1e-9)
        assert.near(0.3, owned(p), 1e-9)
        assert.near(0.3 - PER_HOUR, run(p, 60), 1e-9)
        assert.near(0, run(p, 6 * 60), 1e-9)
        assert.equal(0, owned(p))
    end)

    it("eases to a later stage's lower level instead of keeping the earlier one", function()
        local p = context(0)
        run(p, 90, disease(0.6))
        assert.near(0.2, run(p, 12 * 60, disease(0.2)), 1e-9)
        assert.near(0.2, owned(p), 1e-9)
    end)

    it("never lowers below a floor a source holds", function()
        local p = context(0)
        run(p, 60, disease(0.5))
        local held = run(p, 12 * 60, function(q) q.stats:floorF("SICKNESS", "sideEffect", 0.28) end)
        assert.near(0.28, held, 1e-9)
    end)

    it("leaves sickness another mod set", function()
        local p = context(0.2)
        assert.near(0.2, run(p, 60), 1e-9)
        assert.equal(0, owned(p))
        run(p, 60, disease(0.5))
        assert.near(0.3, owned(p), 1e-9)
        assert.near(0.2, run(p, 12 * 60), 1e-9)
    end)

    it("shrinks its share when something else lowers the stat", function()
        local p = context(0)
        run(p, 60, disease(0.3))
        p.facts.stats.SICKNESS = 0.1        -- another mod cures some of it
        minute(p)
        assert.truthy(owned(p) <= 0.1)
        p.facts.stats.SICKNESS = 0.4        -- and then makes the player sick itself
        local left = owned(p)
        assert.near(0.4 - left, run(p, 12 * 60), 1e-9)
        assert.equal(0, owned(p))
    end)

    it("counts a one-off effect's sickness", function()
        local p = context(0)
        p.stats:addF("SICKNESS", "reaction", 0.12)
        StatRelease.account(p)
        assert.near(0.12, owned(p), 1e-9)
    end)

    it("does nothing on the first step after a player is attached", function()
        local p = context(0.3)
        p.state.body.statOwned.SICKNESS = 0.3
        p.state.body.claimLeftover = true
        p.fresh = true
        StatRelease.update(p, 1)
        assert.is_nil(p.stats:explain("SICKNESS")[1])
        assert.is_true(p.state.body.claimLeftover)
    end)

    describe("an old save's leftover", function()
        it("is claimed once and given back", function()
            local p = context(0.17)
            p.state.body.claimLeftover = true
            minute(p)
            assert.is_false(p.state.body.claimLeftover)
            assert.near(0, run(p, 4 * 60), 1e-9)
        end)

        it("is claimed up to the highest level EHR's diseases reach", function()
            local p = context(0.9)
            p.state.body.claimLeftover = true
            assert.near(0.25, run(p, 24 * 60), 1e-9)
        end)

        it("is not claimed by a new character", function()
            local p = context(0.17)
            assert.near(0.17, run(p, 4 * 60), 1e-9)
        end)

        it("is flagged by the migration from schema 5", function()
            local state = Schema.new({ int = function(lo) return lo end })
            assert.is_false(state.body.claimLeftover)
            state.version = 5
            state.body.statOwned = nil
            state.body.claimLeftover = nil
            assert.is_true((Schema.upgrade(state)))
            assert.is_true(state.body.claimLeftover)
            assert.same({}, state.body.statOwned)
        end)

        it("is flagged for a character imported from the original mod", function()
            local state = Schema.new({ int = function(lo) return lo end })
            Importer.run(Fixtures.veteran(), state)
            assert.is_true(state.body.claimLeftover)
        end)
    end)

    it("runs after every other system that asks for stats", function()
        for _, system in ipairs(Systems) do
            if system.name ~= StatRelease.system.name and system.name ~= "displayRefresh" then
                assert.truthy(system.order < StatRelease.system.order, system.name .. " runs after the release")
            end
        end
    end)
end)
