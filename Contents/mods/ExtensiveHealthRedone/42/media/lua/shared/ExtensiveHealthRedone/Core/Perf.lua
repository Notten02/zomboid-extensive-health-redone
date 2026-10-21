-- Load-test instrumentation: time per scheduler job and simulation system, commands and rejections, and estimated
-- sync bytes per section. Off by default; the debug.perf command turns it on (Server/Perf).
--
--   local perf = Perf.new(function() return getTimestampMs() end)   -- the clock returns milliseconds
--   perf:setEnabled(true)                                           -- also starts a new window
--   local t0 = perf:start()             -- nil while disabled
--   ... work ...
--   if t0 then perf:stop("job", "simulate", t0) end
--   perf:sections("sync", msg)          -- estimated bytes per section of a sync message
--   for _, line in ipairs(perf:report()) do print(line) end
--
-- Disabled cost: callers test perf.on (or the nil from start()) once per hook, the same rule as Core/Log. Nothing is
-- measured, sized or stored while it is off.
--
-- Every entry is { count, total, max } under a category and a name: milliseconds for timings, bytes for sync
-- sections, and plain counts for counters (total = count). The game clock (getTimestampMs) has millisecond
-- resolution, so single calls mostly read 0 or 1 ms: trust totals over a window, not one call's time.

local Tables = require "ExtensiveHealthRedone/Core/Tables"

local Perf = {}
Perf.__index = Perf

-- A category holds at most this many names; more go to OTHER, so junk command names can't grow the table.
Perf.MAX_NAMES = 100
Perf.OTHER = "(other)"

-- Size estimate bounds: deeper tables or more nodes than this are not counted further.
Perf.SIZE_DEPTH = 16
Perf.SIZE_NODES = 20000

-- Report sections, in this order: category -> { title, unit }. Other categories follow, sorted by name.
Perf.CATEGORIES = {
    { "job", "Scheduler jobs", "ms" },
    { "system", "Simulation systems", "ms" },
    { "cmd", "Commands", "ms" },
    { "action", "Timed-action commands", "ms" },
    { "reject", "Rejections", "count" },
    { "sync", "Sync deltas by section", "bytes" },
    { "snapshot", "Snapshots by section", "bytes" },
    { "msg", "Messages", "count" },
}

local function zero()
    return 0
end

-- clock: function() -> milliseconds. Defaults to a clock that always reads 0 (for tests that only count).
function Perf.new(clock)
    local perf = setmetatable({ clock = clock or zero, on = false }, Perf)
    perf:reset()
    return perf
end

-- Clears every counter and starts a new window.
function Perf:reset()
    self.data = {}
    self.since = self.clock()
end

-- Turning it on starts a new window; turning it off keeps the numbers for a later report.
function Perf:setEnabled(on)
    on = on == true
    if on and not self.on then
        self:reset()
    end
    self.on = on
end

-- Real milliseconds since the window started.
function Perf:windowMs()
    return self.clock() - self.since
end

local function entry(self, cat, name)
    local byName = self.data[cat]
    if not byName then
        byName = { n = 0, entries = {} }
        self.data[cat] = byName
    end
    name = tostring(name)
    local e = byName.entries[name]
    if not e then
        if byName.n >= Perf.MAX_NAMES then
            name = Perf.OTHER
            e = byName.entries[name]
        end
        if not e then
            e = { count = 0, total = 0, max = 0 }
            byName.entries[name] = e
            byName.n = byName.n + 1
        end
    end
    return e
end

local function record(self, cat, name, value)
    local e = entry(self, cat, name)
    e.count = e.count + 1
    e.total = e.total + value
    if value > e.max then
        e.max = value
    end
end

-- A timestamp to pass to stop(), or nil while disabled.
function Perf:start()
    if self.on then
        return self.clock()
    end
    return nil
end

-- Records the time since t0 under cat/name. Does nothing when t0 is nil (perf was off at start()).
function Perf:stop(cat, name, t0)
    if t0 == nil then
        return
    end
    local dt = self.clock() - t0
    if dt < 0 then
        dt = 0
    end
    record(self, cat, name, dt)
end

-- Adds n (default 1) to a plain counter.
function Perf:count(cat, name, n)
    if not self.on then
        return
    end
    local e = entry(self, cat, name)
    n = n or 1
    e.count = e.count + n
    e.total = e.total + n
end

-- Adds one sample of value (bytes, or any amount) under cat/name.
function Perf:sample(cat, name, value)
    if not self.on then
        return
    end
    record(self, cat, name, value)
end

-- A command finished: its time under cat/name, and its rejection code under "reject". Unknown command names share
-- one entry, so a client can't fill the table with junk names.
function Perf:command(cat, name, t0, ok, code)
    if t0 == nil then
        return
    end
    if not ok and code == "unknown_command" then
        name = "(unknown)"
    end
    self:stop(cat, name, t0)
    if not ok then
        self:count("reject", code)
    end
end

-- A rough, bounded size of plain data as it would cross the network: string length + 2, 8 per number, 1 per
-- boolean, 2 per table plus its keys and values. Stops counting past SIZE_DEPTH levels or SIZE_NODES values.
function Perf.estimateSize(value)
    local budget = Perf.SIZE_NODES
    local function size(v, depth)
        budget = budget - 1
        if budget < 0 then
            return 0
        end
        local t = type(v)
        if t == "string" then
            return #v + 2
        elseif t == "number" then
            return 8
        elseif t == "boolean" then
            return 1
        elseif t ~= "table" or depth > Perf.SIZE_DEPTH then
            return 0
        end
        local n = 2
        for k, item in pairs(v) do
            n = n + size(k, depth + 1) + size(item, depth + 1)
        end
        return n
    end
    return size(value, 0)
end

-- A sync message ({ sections = { [name] = { rev, data } } }): one sample per section with its estimated size,
-- under cat (e.g. "sync" or "snapshot"), plus one "msg" count under cat.
function Perf:sections(cat, msg)
    if not self.on or type(msg) ~= "table" or type(msg.sections) ~= "table" then
        return
    end
    self:count("msg", cat)
    for name, section in pairs(msg.sections) do
        record(self, cat, name, Perf.estimateSize(section))
    end
end

-- The entry for cat/name ({ count, total, max }) or nil.
function Perf:get(cat, name)
    local byName = self.data[cat]
    return byName and byName.entries[tostring(name)] or nil
end

-- Sum of totals and counts over a category.
function Perf:totals(cat)
    local count, total = 0, 0
    local byName = self.data[cat]
    if byName then
        for _, e in pairs(byName.entries) do
            count = count + e.count
            total = total + e.total
        end
    end
    return count, total
end

local function round(v, places)
    local m = 10 ^ (places or 0)
    return tostring(math.floor(v * m + 0.5) / m)
end
Perf.round = round

-- Names of a category, the biggest total first (ties by name).
local function ranked(byName)
    local names = Tables.sortedKeys(byName.entries)
    table.sort(names, function(a, b)
        local ta, tb = byName.entries[a].total, byName.entries[b].total
        if ta ~= tb then
            return ta > tb
        end
        return a < b
    end)
    return names
end

local function section(lines, byName, title, unit, seconds)
    local count, total = 0, 0
    for _, e in pairs(byName.entries) do
        count = count + e.count
        total = total + e.total
    end
    lines[#lines + 1] = title .. " (" .. unit .. "): " .. count .. " calls, total " .. round(total, 1)
    for _, name in ipairs(ranked(byName)) do
        local e = byName.entries[name]
        local line = "  " .. name .. ": n " .. e.count
        if unit == "count" then
            line = line .. ", per s " .. round(e.count / seconds, 2)
        else
            line = line .. ", total " .. round(e.total, 1) .. ", avg " .. round(e.total / e.count, 2)
                .. ", max " .. round(e.max, 1)
            if unit == "ms" then
                line = line .. ", per s " .. round(e.count / seconds, 2)
            end
        end
        lines[#lines + 1] = line
    end
end

-- The report as text lines. header: optional extra lines after the first.
function Perf:report(header)
    local seconds = self:windowMs() / 1000
    local lines = { "Perf " .. (self.on and "on" or "off") .. ", window " .. round(seconds, 1) .. " s real time" }
    for _, line in ipairs(header or {}) do
        lines[#lines + 1] = line
    end
    if seconds <= 0 then
        seconds = 1
    end
    local done = {}
    for _, c in ipairs(Perf.CATEGORIES) do
        done[c[1]] = true
        if self.data[c[1]] then
            section(lines, self.data[c[1]], c[2], c[3], seconds)
        end
    end
    for _, cat in ipairs(Tables.sortedKeys(self.data)) do
        if not done[cat] then
            section(lines, self.data[cat], cat, "ms", seconds)
        end
    end
    if #lines == 1 + #(header or {}) then
        lines[#lines + 1] = "(nothing measured yet)"
    end
    return lines
end

return Perf
