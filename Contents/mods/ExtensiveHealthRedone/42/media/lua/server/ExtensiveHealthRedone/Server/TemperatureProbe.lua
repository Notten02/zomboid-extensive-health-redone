-- A Phase 6 diagnostic: does vanilla keep a TEMPERATURE we write, or overwrite it from the thermoregulator? The answer
-- decides how body temperature and fever are built (docs/porting/phase6/body-temperature.md section 7.1). Remove this
-- file once the answer is recorded. An MP client loads this file too and stops at the first line.
--
-- The debug button "Fever probe" runs four phases on the authority, logging lines starting "FeverProbe" to console.txt:
--   base      10 ticks untouched: the normal values
--   once      one write of base + OFFSET, then watch for ONCE_MINUTES game minutes (snap back, drift, or held?)
--   hold      write base + OFFSET every tick for HOLD_MINUTES (does it stick within a tick; moodle; damage?)
--   release   stop writing and watch for RELEASE_MINUTES (how fast vanilla brings it back)
-- Each line: phase, ticks and game minutes since the phase began, the TEMPERATURE stat, the thermoregulator's core
-- temperature, set point and rate of change, the hyperthermia and hypothermia moodle levels, and overall health.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local StatWriter = require "ExtensiveHealthRedone/Server/StatWriter"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"

local log = Env.logger("Probe")

local Probe = {}

Probe.OFFSET = 2.5          -- deg C over the baseline
Probe.BASE_TICKS = 10
Probe.ONCE_MINUTES = 10
Probe.HOLD_MINUTES = 10
Probe.RELEASE_MINUTES = 60
-- Ticks after a write that are logged one by one, to see how soon vanilla reacts.
Probe.EARLY_TICKS = { [0] = true, [1] = true, [2] = true, [3] = true, [5] = true, [10] = true, [30] = true,
    [60] = true }

---@class ExtensiveHealthRedoneFeverProbe
---@field player IsoPlayer
---@field key string
---@field phase string
---@field ticks integer
---@field since number game minutes when the phase began
---@field lastMinute integer
---@field target number

---@type ExtensiveHealthRedoneFeverProbe?
local run = nil

local failed = {}

-- The thermoregulator API is unverified on 42.21 (and absent in some MP states): read it guarded, log a failure once.
local function read(name, fn)
    local ok, value = pcall(fn)
    if ok then
        return value
    end
    if not failed[name] then
        failed[name] = true
        log:warn("FeverProbe cannot read", name, tostring(value))
    end
    return "n/a"
end

local function round(v)
    if type(v) ~= "number" then
        return tostring(v)
    end
    return tostring(math.floor(v * 1000 + 0.5) / 1000)
end

local function sample(player)
    local function thermo()
        return player:getBodyDamage():getThermoregulator()
    end
    local moodles = player:getMoodles()
    return {
        stat = player:getStats():get(CharacterStat.TEMPERATURE),
        core = read("core", function() return thermo():getCoreTemperature() end),
        setPoint = read("setPoint", function() return thermo():getSetPoint() end),
        rate = read("rate", function() return thermo():getCoreRateOfChange() end),
        hyper = read("hyper", function() return moodles:getMoodleLevel(MoodleType.HYPERTHERMIA) end),
        hypo = read("hypo", function() return moodles:getMoodleLevel(MoodleType.HYPOTHERMIA) end),
        health = player:getBodyDamage():getOverallBodyHealth(),
    }
end

---@param r ExtensiveHealthRedoneFeverProbe
local function line(r, phase, note)
    local s = sample(r.player)
    log:info("FeverProbe", phase, "tick=" .. r.ticks, "min=" .. round(Env.gameMinutes() - r.since),
        "stat=" .. round(s.stat), "core=" .. round(s.core), "setPoint=" .. round(s.setPoint),
        "rate=" .. round(s.rate), "hyper=" .. tostring(s.hyper), "hypo=" .. tostring(s.hypo),
        "health=" .. round(s.health), note or "")
end

---@param r ExtensiveHealthRedoneFeverProbe
local function enter(r, phase)
    r.phase, r.ticks, r.since, r.lastMinute = phase, 0, Env.gameMinutes(), -1
end

---@param r ExtensiveHealthRedoneFeverProbe
local function write(r)
    StatWriter.debugSet(r.player, "TEMPERATURE", r.target)
end

-- Logs the early ticks after a phase change, then once per game minute. Returns game minutes since the phase began.
---@param r ExtensiveHealthRedoneFeverProbe
local function watch(r, phase)
    local minute = math.floor(Env.gameMinutes() - r.since)
    if Probe.EARLY_TICKS[r.ticks] then
        line(r, phase)
    elseif minute ~= r.lastMinute then
        line(r, phase, "(minute)")
    end
    r.lastMinute = minute
    return Env.gameMinutes() - r.since
end

local function onTick()
    local r = run
    if not r then
        return
    end
    local player = r.player
    if player:isDead() then
        log:warn("FeverProbe stopped: the player died")
        run = nil
        return
    end
    if r.phase == "base" then
        line(r, "base")
        if r.ticks + 1 >= Probe.BASE_TICKS then
            r.target = player:getStats():get(CharacterStat.TEMPERATURE) + Probe.OFFSET
            enter(r, "once")
            write(r)
            line(r, "once", "(right after the write, target " .. round(r.target) .. ")")
            r.ticks = 1
            return
        end
    elseif r.phase == "once" then
        if watch(r, "once") >= Probe.ONCE_MINUTES then
            enter(r, "hold")
        end
    elseif r.phase == "hold" then
        -- Read what vanilla left since our last write, then write again.
        if watch(r, "hold") >= Probe.HOLD_MINUTES then
            enter(r, "release")
            line(r, "release", "(last write was one tick ago)")
            r.ticks = 1
            return
        end
        write(r)
    elseif r.phase == "release" then
        if watch(r, "release") >= Probe.RELEASE_MINUTES then
            log:info("FeverProbe done for", r.key)
            run = nil
            return
        end
    end
    r.ticks = r.ticks + 1
end

Runtime.registry:register("debug.feverProbe", {
    access = "medicalAdmin",
    debugOnly = true,
    rate = { count = 1, seconds = 10 },
    handler = function(ctx)
        local player = ctx.actor.player
        local conditions = {}
        local state = Runtime.store:get(ctx.actor.key)
        for id in pairs(state and state.conditions.active or {}) do
            conditions[#conditions + 1] = id
        end
        table.sort(conditions)
        local r = { player = player, key = ctx.actor.key, phase = "base", ticks = 0, since = 0, lastMinute = -1,
            target = 0 }
        enter(r, "base")
        run = r
        log:info("FeverProbe start", PlayerKey.of(player), "server=" .. tostring(isServer()),
            "client=" .. tostring(isClient()), "asleep=" .. tostring(player:isAsleep()),
            "air=" .. round(getClimateManager():getAirTemperatureForCharacter(player, false)),
            "conditions=" .. (#conditions > 0 and table.concat(conditions, ",") or "none"))
    end,
})

Events.OnTick.Add(onTick)

return Probe
