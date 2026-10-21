-- Load-test commands (Phase 9) over Runtime.perf (Core/Perf). Debug only: sandbox DebugMode plus medicalAdmin.
--
--   debug.perf { on }                 on = true starts a new window, false stops counting; no argument toggles
--   debug.perfReport {}               the report as text in the debug window (debugDump) and in the server log
--   debug.perfLoad { players, minutes } ghost load: the real cost of one player-step on this server
--
-- Ghost load. For each of `players` ghosts, the actor's state is deep-copied once; then for `minutes` steps every
-- ghost reads facts from the actor's real IsoPlayer (Server/Facts, read-only) and runs Runtime.sim on its copy. The
-- context is built here, not through Runtime.simulate or applyNow, so:
--   - nothing is written: no StatWriter, no BodyWriter, no XP, no noise, no messages to any client (the say, client,
--     noise and xp callbacks drop everything, and the context's dirty() marks nothing);
--   - the copies never enter Runtime.store, so they are never synced, saved or listed as players;
--   - each ghost has its own key ("ghost<n>:<actor key>"), so per-key tables never mix with the actor's.
-- Systems never touch game objects (the Core/Simulation contract), so a ghost step has no game side effect. What
-- remains: a system may log a line with the ghost key, the random generator advances, and Server/Corpse refreshes the
-- actor's own corpse-scan cache as the real step would. Runs in one tick: expect a hitch of about
-- players x minutes x the per-step cost.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local Transport = require "ExtensiveHealthRedone/Game/Transport"
local Tables = require "ExtensiveHealthRedone/Core/Tables"
local Perf = require "ExtensiveHealthRedone/Core/Perf"
local StatAggregator = require "ExtensiveHealthRedone/Core/StatAggregator"
local BodyAggregator = require "ExtensiveHealthRedone/Core/BodyAggregator"
local ClientEffects = require "ExtensiveHealthRedone/Core/ClientEffects"
local Treatments = require "ExtensiveHealthRedone/Core/Treatments"
local Facts = require "ExtensiveHealthRedone/Server/Facts"
local StatWriter = require "ExtensiveHealthRedone/Server/StatWriter"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"

local log = Env.logger("Perf")

local ServerPerf = {}

local function noop() end

-- A system context like Runtime's, over a copy, with every writer and message dropped.
local function ghostContext(key, state, facts, ranges)
    return {
        key = key,
        player = nil,
        state = state,
        stats = StatAggregator.new(ranges),
        body = BodyAggregator.new(),
        fx = ClientEffects.new(),
        rng = Env.rng,
        sandbox = Env.sandbox,
        facts = facts,
        treatment = Treatments.forState(state),
        fresh = false,
        dirty = noop,
        say = noop,
        client = noop,
        noise = noop,
        xp = noop,
    }
end

-- Runs the ghost load and returns its report lines. clock: milliseconds. Exposed for tests.
function ServerPerf.ghostLoad(player, key, players, minutes, clock)
    local state = Runtime.store:get(key)
    if not (player and state) then
        return { "Ghost load: the actor has no attached state." }
    end
    local ranges = StatWriter.ranges()
    local ghosts = {}
    for i = 1, players do
        ghosts[i] = { key = "ghost" .. i .. ":" .. key, state = Tables.deepCopy(state) }
    end
    -- Keep the ghosts' per-system timings out of the real window.
    local savedPerf = Runtime.sim.perf
    Runtime.sim.perf = Perf.new()
    local factsMs, simMs = 0, 0
    local ok, err = pcall(function()
        for _ = 1, minutes do
            local t0 = clock()
            for _, ghost in ipairs(ghosts) do
                ghost.facts = Facts.read(player, ranges)
            end
            local t1 = clock()
            for _, ghost in ipairs(ghosts) do
                Runtime.sim:run(ghostContext(ghost.key, ghost.state, ghost.facts, ranges), Runtime.STEP)
            end
            factsMs = factsMs + (t1 - t0)
            simMs = simMs + (clock() - t1)
        end
    end)
    Runtime.sim.perf = savedPerf
    local steps = players * minutes
    local r = Perf.round
    local lines = {
        "Ghost load: " .. players .. " players x " .. minutes .. " game minutes = " .. steps .. " player-steps",
        "  facts " .. r(factsMs, 1) .. " ms, simulation " .. r(simMs, 1) .. " ms, total "
            .. r(factsMs + simMs, 1) .. " ms",
        "  per player per game minute: " .. r((factsMs + simMs) / steps, 3) .. " ms (facts " .. r(factsMs / steps, 3)
            .. ", simulation " .. r(simMs / steps, 3) .. ")",
        "  attached players: " .. #Runtime.store:keys() .. ". Timer resolution is 1 ms; use enough steps.",
    }
    if not ok then
        lines[#lines + 1] = "  stopped by an error: " .. tostring(err)
    end
    return lines
end

local function reply(ctx, lines)
    for _, line in ipairs(lines) do
        log:info(line)
    end
    Transport.toClient(ctx.actor.player, "debugDump", { text = table.concat(lines, "\n") })
end

-- The budget numbers up front: the simulate job runs once per game minute, so its count is the game minutes in the
-- window. Per player uses the players attached now.
local function header()
    local players = #Runtime.store:keys()
    local lines = { "Attached players: " .. players }
    local sim = Runtime.perf:get("job", "simulate")
    if sim and sim.count > 0 and players > 0 then
        local _, bytes = Runtime.perf:totals("sync")
        local r = Perf.round
        lines[#lines + 1] = "Per game minute (" .. sim.count .. " in the window): simulate " .. r(sim.total / sim.count, 2)
            .. " ms = " .. r(sim.total / sim.count / players, 3) .. " ms per player; sync "
            .. r(bytes / sim.count / players, 0) .. " bytes per player"
    end
    return lines
end

Runtime.registry:register("debug.perf", {
    args = { on = { type = "boolean", optional = true } },
    access = "medicalAdmin",
    debugOnly = true,
    rate = { count = 5, seconds = 10 },
    handler = function(ctx, args)
        local on = args.on
        if on == nil then
            on = not Runtime.perf.on
        end
        Runtime.perf:setEnabled(on)
        log:info(ctx.actor.key, "debug: perf", on and "on (new window)" or "off")
        reply(ctx, { on and "Perf on: new window started."
            or "Perf off. \"Perf report\" still shows the last window." })
    end,
})

Runtime.registry:register("debug.perfReport", {
    access = "medicalAdmin",
    debugOnly = true,
    rate = { count = 5, seconds = 10 },
    handler = function(ctx)
        reply(ctx, Runtime.perf:report(header()))
    end,
})

Runtime.registry:register("debug.perfLoad", {
    args = {
        players = { type = "number", integer = true, min = 1, max = 64 },
        minutes = { type = "number", integer = true, min = 1, max = 60 },
    },
    access = "medicalAdmin",
    debugOnly = true,
    rate = { count = 2, seconds = 10 },
    handler = function(ctx, args)
        log:info(ctx.actor.key, "debug: ghost load", args.players, "players x", args.minutes, "minutes")
        local lines = ServerPerf.ghostLoad(ctx.actor.player, ctx.actor.key, args.players, args.minutes,
            Runtime.perf.clock)
        reply(ctx, lines)
    end,
})

log:info("perf commands loaded")

return ServerPerf
