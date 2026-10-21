-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
local Simulation = require("ExtensiveHealthRedone/Core/Simulation")
local StatAggregator = require("ExtensiveHealthRedone/Core/StatAggregator")
local Dump = require("ExtensiveHealthRedone/Core/Dump")
local Tables = require("ExtensiveHealthRedone/Core/Tables")

describe("Simulation", function()
    it("runs systems by order then name, whatever the registration order", function()
        local sim = Simulation.new()
        local ran = {}
        local function system(name, order)
            return { name = name, order = order, update = function() ran[#ran + 1] = name end }
        end
        sim:add(system("immunity", 300))
        sim:add(system("blood", 200))
        sim:add(system("bleeding", 200))
        sim:add(system("diseases", 100))
        sim:run({}, 1)
        assert.same({ "diseases", "bleeding", "blood", "immunity" }, ran)
        assert.same(ran, sim:names())
    end)

    it("lets two systems stack their stat changes through one aggregator", function()
        local sim = Simulation.new()
        sim:add({ name = "a", update = function(p, dt) p.stats:add("PAIN", "a", 2 * dt) end })
        sim:add({ name = "b", update = function(p, dt) p.stats:add("PAIN", "b", 3 * dt) end })
        local p = { stats = StatAggregator.new({ PAIN = { min = 0, max = 100 } }) }
        sim:run(p, 2)
        assert.equal(20, (p.stats:resolve("PAIN", 10)))
    end)

    it("rejects duplicate or incomplete systems", function()
        local sim = Simulation.new()
        sim:add({ name = "a", update = function() end })
        assert.has_error(function() sim:add({ name = "a", update = function() end }) end)
        assert.has_error(function() sim:add({ name = "b" }) end)
    end)
end)

describe("Dump", function()
    it("prints plain data with sorted keys", function()
        local text = Dump.lines({ b = 1, a = { y = "x", x = true }, c = {} })
        assert.equal('{\n  a = {\n    x = true\n    y = "x"\n  }\n  b = 1\n  c = {}\n}', text)
    end)
end)

describe("Tables", function()
    it("deep-copies without sharing nested tables", function()
        local original = { a = { b = { 1, 2 } } }
        local copy = Tables.deepCopy(original)
        copy.a.b[1] = 9
        assert.equal(1, original.a.b[1])
    end)
end)
