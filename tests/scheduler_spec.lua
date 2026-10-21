-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
local Scheduler = require("ExtensiveHealthRedone/Core/Scheduler")
local Timers = require("ExtensiveHealthRedone/Core/Timers")
local Log = require("ExtensiveHealthRedone/Core/Log")

local function recorder()
    local calls = {}
    return calls, function(dt, now)
        calls[#calls + 1] = { dt = dt, now = now }
    end
end

describe("Scheduler", function()
    it("only sets the baseline on the first update", function()
        local s = Scheduler.new()
        local calls, fn = recorder()
        s:every("job", 1, fn)
        s:update(1000)
        assert.equal(0, #calls)
        s:update(1001)
        assert.equal(1, #calls)
        assert.same({ dt = 1, now = 1001 }, calls[1])
    end)

    it("runs on game time, however often update is called", function()
        -- 30 FPS and 144 FPS for the same 10 game minutes give the same calls.
        for _, ticksPerMinute in ipairs({ 30, 144 }) do
            local s = Scheduler.new()
            local calls, fn = recorder()
            s:every("job", 2, fn)
            s:update(0)
            for tick = 1, 10 * ticksPerMinute do
                s:update(tick / ticksPerMinute)
            end
            assert.equal(5, #calls)
            local total = 0
            for _, c in ipairs(calls) do
                total = total + c.dt
            end
            assert.near(10, total, 1e-9)
        end
    end)

    it("steps through a jump one interval at a time and carries what is left", function()
        local s = Scheduler.new({ maxStepsPerUpdate = 3 })
        local calls, fn = recorder()
        s:every("job", 1, fn)
        s:update(0)
        s:update(5.5)
        assert.equal(3, #calls)
        assert.same({ 1, 1, 1 }, { calls[1].dt, calls[2].dt, calls[3].dt })
        -- Each step reports the game time it stands for.
        assert.same({ 1, 2, 3 }, { calls[1].now, calls[2].now, calls[3].now })
        s:update(5.5)
        assert.equal(5, #calls)
        assert.same({ 4, 5 }, { calls[4].now, calls[5].now })
    end)

    it("drops backlog beyond the cap and logs it", function()
        local lines = {}
        local log = Log.new("test", function(line) lines[#lines + 1] = line end, "warn")
        local s = Scheduler.new({ maxStepsPerUpdate = 2, maxBacklogMinutes = 10, log = log })
        local calls, fn = recorder()
        s:every("job", 1, fn)
        s:update(0)
        s:update(100)
        assert.equal(2, #calls)
        assert.equal(1, #lines)
        assert.truthy(lines[1]:find("dropped", 1, true))
        -- 10 minutes stay in the backlog and drain over the next updates.
        for _ = 1, 5 do
            s:update(100)
        end
        assert.equal(12, #calls)
        s:update(100)
        assert.equal(12, #calls)
    end)

    it("gives coalesced jobs one call with all whole intervals", function()
        local s = Scheduler.new()
        local calls, fn = recorder()
        s:every("sync", 0.5, fn, { coalesce = true })
        s:update(0)
        s:update(2.3)
        assert.equal(1, #calls)
        assert.near(2, calls[1].dt, 1e-9)
        s:update(2.6)
        assert.equal(2, #calls)
        assert.near(0.5, calls[2].dt, 1e-9)
    end)

    it("runs jobs in registration order", function()
        local s = Scheduler.new()
        local order = {}
        s:every("b", 1, function() order[#order + 1] = "b" end)
        s:every("a", 1, function() order[#order + 1] = "a" end)
        s:update(0)
        s:update(1)
        assert.same({ "b", "a" }, order)
    end)

    it("ignores time going backwards and restarts the baseline", function()
        local s = Scheduler.new()
        local calls, fn = recorder()
        s:every("job", 1, fn)
        s:update(50)
        s:update(10)
        s:update(11)
        assert.equal(1, #calls)
    end)

    it("never counts time from before a reset (a load or a login)", function()
        local s = Scheduler.new()
        local calls, fn = recorder()
        s:every("job", 1, fn)
        s:update(0)
        s:update(0.9)
        s:reset()
        s:update(500)
        s:update(500.5)
        assert.equal(0, #calls)
    end)

    it("rejects bad job definitions", function()
        local s = Scheduler.new()
        s:every("job", 1, function() end)
        assert.has_error(function() s:every("job", 1, function() end) end)
        assert.has_error(function() s:every("other", 0, function() end) end)
    end)
end)

describe("Timers", function()
    it("counts remaining durations down and reports expiries in name order", function()
        local t = {}
        Timers.start(t, "zeta", 5)
        Timers.start(t, "alpha", 3)
        Timers.start(t, "beta", 10)
        assert.same({}, Timers.advance(t, 2))
        assert.equal(1, Timers.remaining(t, "alpha"))
        assert.same({ "alpha", "zeta" }, Timers.advance(t, 3))
        assert.is_false(Timers.running(t, "alpha"))
        assert.equal(5, Timers.remaining(t, "beta"))
    end)

    it("stores only plain numbers, so a saved table resumes with the same time left", function()
        local t = {}
        Timers.start(t, "course", 90)
        Timers.advance(t, 30)
        local saved = { course = t.course }
        assert.same({}, Timers.advance(saved, 59))
        assert.same({ "course" }, Timers.advance(saved, 1))
    end)

    it("cancels and rejects negative durations", function()
        local t = {}
        Timers.start(t, "x", 1)
        Timers.cancel(t, "x")
        assert.is_nil(Timers.remaining(t, "x"))
        assert.has_error(function() Timers.start(t, "x", -1) end)
    end)
end)
