-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
local PatchPoints = require("ExtensiveHealthRedone/Core/PatchPoints")
local Log = require("ExtensiveHealthRedone/Core/Log")

-- A fake vanilla class and a resolver for it.
local function vanilla()
    local calls = {}
    local globals = {
        ISEatFoodAction = {
            complete = function(self, a, b)
                calls[#calls + 1] = "vanilla"
                return self.result, a + b
            end,
        },
    }
    return globals, calls, function(name) return globals[name] end
end

describe("PatchPoints", function()
    it("wraps a method once and fans out to listeners in order, not registration order", function()
        local globals, calls, resolve = vanilla()
        local points = PatchPoints.new()
        points:define("eat", "ISEatFoodAction.complete")
        points:on("eat", { name = "z", order = 50, before = function() calls[#calls + 1] = "z before" end })
        points:on("eat", {
            name = "a",
            order = 50,
            after = function(results, _, a) calls[#calls + 1] = "a after " .. results[2] .. " " .. a end,
        })
        points:on("eat", { name = "first", order = 10, before = function() calls[#calls + 1] = "first before" end })
        local report = points:install(resolve)
        assert.same({ "eat" }, report.installed)
        local action = { result = "done" }
        local r1, r2 = globals.ISEatFoodAction.complete(action, 2, 3)
        assert.equal("done", r1)
        assert.equal(5, r2)
        assert.same({ "first before", "z before", "vanilla", "a after 5 2" }, calls)
    end)

    it("installs each point only once, even when install is called again", function()
        local globals, calls, resolve = vanilla()
        local points = PatchPoints.new()
        points:define("eat", "ISEatFoodAction.complete")
        points:on("eat", { name = "x", before = function() calls[#calls + 1] = "x" end })
        points:install(resolve)
        local wrapped = globals.ISEatFoodAction.complete
        assert.same({}, points:install(resolve).installed)
        assert.equal(wrapped, globals.ISEatFoodAction.complete)
        wrapped({}, 1, 1)
        assert.same({ "x", "vanilla" }, calls)
    end)

    it("reports targets that don't exist yet and installs them later", function()
        local globals, _, resolve = vanilla()
        local points = PatchPoints.new()
        points:define("panel", "ISHealthPanel.update")
        assert.same({ "panel" }, points:install(resolve).missing)
        globals.ISHealthPanel = { update = function() return 1 end }
        assert.same({ "panel" }, points:install(resolve).installed)
    end)

    it("logs a failing listener and still runs vanilla and the other listeners", function()
        local globals, calls, resolve = vanilla()
        local lines = {}
        local points = PatchPoints.new(Log.new("Patch", function(l) lines[#lines + 1] = l end, "error"))
        points:define("eat", "ISEatFoodAction.complete")
        points:on("eat", { name = "broken", order = 1, before = function() error("boom") end })
        points:on("eat", { name = "fine", order = 2, before = function() calls[#calls + 1] = "fine" end })
        points:install(resolve)
        local _, sum = globals.ISEatFoodAction.complete({}, 1, 2)
        assert.equal(3, sum)
        assert.same({ "fine", "vanilla" }, calls)
        assert.equal(1, #lines)
        assert.truthy(lines[1]:find("broken", 1, true))
    end)

    it("sees listeners added after installation", function()
        local globals, calls, resolve = vanilla()
        local points = PatchPoints.new()
        points:define("eat", "ISEatFoodAction.complete")
        points:install(resolve)
        points:on("eat", { name = "late", after = function() calls[#calls + 1] = "late" end })
        globals.ISEatFoodAction.complete({}, 0, 0)
        assert.same({ "vanilla", "late" }, calls)
    end)

    it("keeps nil and multiple return values intact", function()
        local globals, _, resolve = vanilla()
        globals.ISEatFoodAction.complete = function() return nil, 2, nil end
        local points = PatchPoints.new()
        points:define("eat", "ISEatFoodAction.complete")
        points:install(resolve)
        assert.equal(3, select("#", globals.ISEatFoodAction.complete()))
    end)

    it("lets an intercept replace the original, skipping vanilla and the after listeners", function()
        local Owner = { method = function(_, x) return "vanilla " .. x end }
        local points = PatchPoints.new()
        points:define("p", "Owner.method")
        local after = 0
        points:on("p", { name = "watch", after = function() after = after + 1 end })
        points:on("p", { name = "guard", order = 50, intercept = function(_, x)
            if x == "blocked" then
                return true, false, "why"
            end
            return false
        end })
        points:install(function() return Owner end)
        assert.equal("vanilla a", Owner:method("a"))
        assert.equal(1, after)
        assert.same({ false, "why" }, { Owner:method("blocked") })
        assert.equal(1, after)
    end)

    it("treats a failing intercept as not handled", function()
        local Owner = { method = function() return "vanilla" end }
        local points = PatchPoints.new()
        points:define("p", "Owner.method")
        points:on("p", { name = "broken", intercept = function() error("boom") end })
        points:install(function() return Owner end)
        assert.equal("vanilla", Owner.method())
    end)

    it("rejects bad definitions and listeners", function()
        local points = PatchPoints.new()
        points:define("eat", "ISEatFoodAction.complete")
        assert.has_error(function() points:define("eat", "ISEatFoodAction.complete") end)
        assert.has_error(function() points:define("x", "not a path") end)
        assert.has_error(function() points:on("missing", { name = "a" }) end)
        points:on("eat", { name = "a" })
        assert.has_error(function() points:on("eat", { name = "a" }) end)
    end)
end)

describe("Log", function()
    it("formats nothing for disabled levels", function()
        local lines = {}
        local log = Log.new("T", function(l) lines[#lines + 1] = l end, "info")
        local touched = false
        local probe = setmetatable({}, { __tostring = function() touched = true return "probe" end })
        log:debug(probe)
        assert.is_false(touched)
        assert.equal(0, #lines)
        log:info("hello", 3, nil, probe)
        assert.same({ "[ExtensiveHealthRedone] INFO T: hello 3 nil probe" }, lines)
        log:setLevel("trace")
        assert.is_true(log:enabled("trace"))
        assert.has_error(function() log:setLevel("loud") end)
    end)
end)
