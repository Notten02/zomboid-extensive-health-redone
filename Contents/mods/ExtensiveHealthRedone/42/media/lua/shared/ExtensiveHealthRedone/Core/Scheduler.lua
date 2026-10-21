-- Game-time scheduler: the single entry point that drives all simulation.
--
-- The game adapter calls update(now) often (every tick is fine) with the current game time in minutes. Each job runs
-- when its interval of game time has passed, so the cadence depends on game time only, never on frame rate.
--
--   local s = Scheduler.new({ maxStepsPerUpdate = 60, maxBacklogMinutes = 1440, log = log, perf = perf })
--   s:every("simulate", 1, function(dt, now) ... end)                    -- called with dt = 1, once per game minute
--   s:every("sync", 1, function(dt, now) ... end, { coalesce = true })   -- one call with all the elapsed time
--
-- Stepped jobs (the default) run once per elapsed interval, at most maxStepsPerUpdate times per update. Time beyond that
-- is carried to the next update, so a fast-forward spreads over several ticks instead of freezing one. A backlog larger
-- than maxBacklogMinutes (a huge time skip) is dropped and logged. Coalesced jobs get a single call with dt = all the
-- elapsed time, rounded down to whole intervals.
--
-- Jobs run in registration order. Nothing is stored in absolute time: when the game loads, the first update only sets
-- the baseline. Time spent offline or before loading therefore never reaches the jobs.

local Log = require "ExtensiveHealthRedone/Core/Log"
local Perf = require "ExtensiveHealthRedone/Core/Perf"

local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new(opts)
    opts = opts or {}
    return setmetatable({
        jobs = {},
        byName = {},
        last = nil,
        maxSteps = opts.maxStepsPerUpdate or 60,
        maxBacklog = opts.maxBacklogMinutes or 1440,
        log = opts.log or Log.silent,
        -- Core/Perf: time per job name while it is on.
        perf = opts.perf or Perf.new(),
    }, Scheduler)
end

-- fn(dtMinutes, nowMinutes). opts.coalesce: one call per update instead of one per interval.
function Scheduler:every(name, intervalMinutes, fn, opts)
    if type(name) ~= "string" or self.byName[name] then
        error("scheduler job name must be a new string: " .. tostring(name), 2)
    end
    if type(intervalMinutes) ~= "number" or intervalMinutes <= 0 then
        error("scheduler job " .. name .. " needs a positive interval", 2)
    end
    local job = {
        name = name,
        interval = intervalMinutes,
        fn = fn,
        coalesce = opts and opts.coalesce or false,
        pending = 0,
    }
    self.jobs[#self.jobs + 1] = job
    self.byName[name] = job
end

-- Forget the time baseline; the next update starts counting again. Use after loading a game.
function Scheduler:reset()
    self.last = nil
    for _, job in ipairs(self.jobs) do
        job.pending = 0
    end
end

local function call(self, job, dt, now)
    if self.perf.on then
        local t0 = self.perf.clock()
        job.fn(dt, now)
        self.perf:stop("job", job.name, t0)
    else
        job.fn(dt, now)
    end
end

local function runJob(self, job, now)
    if job.coalesce then
        local steps = math.floor(job.pending / job.interval)
        if steps > 0 then
            local dt = steps * job.interval
            job.pending = job.pending - dt
            call(self, job, dt, now)
        end
        return
    end
    local steps = 0
    while job.pending >= job.interval and steps < self.maxSteps do
        job.pending = job.pending - job.interval
        steps = steps + 1
        call(self, job, job.interval, now - job.pending)
    end
    if job.pending > self.maxBacklog then
        self.log:warn("job", job.name, "dropped", job.pending - self.maxBacklog, "minutes of backlog")
        job.pending = self.maxBacklog
    end
end

-- now: current game time in minutes.
function Scheduler:update(now)
    local last = self.last
    self.last = now
    if last == nil then
        return
    end
    local delta = now - last
    if delta < 0 then
        self.log:warn("game time went backwards by", -delta, "minutes; restarting the baseline")
        return
    end
    for _, job in ipairs(self.jobs) do
        job.pending = job.pending + delta
        runJob(self, job, now)
    end
end

return Scheduler
