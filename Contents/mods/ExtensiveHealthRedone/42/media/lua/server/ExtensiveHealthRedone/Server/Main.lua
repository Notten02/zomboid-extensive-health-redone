-- Wires the game to the authority runtime: the clock, client commands and the core commands (sync and debug).
-- Runs in single player and on a dedicated server; an MP client loads this file too and stops at the first line.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local Transport = require "ExtensiveHealthRedone/Game/Transport"
local Sync = require "ExtensiveHealthRedone/Core/Sync"
local Dump = require "ExtensiveHealthRedone/Core/Dump"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
-- Features register their systems and commands on load; requiring them here keeps that independent of load order.
require "ExtensiveHealthRedone/Server/Health"
require "ExtensiveHealthRedone/Server/Consent"
require "ExtensiveHealthRedone/Server/Exam"
require "ExtensiveHealthRedone/Server/Food"
require "ExtensiveHealthRedone/Server/Weather"
require "ExtensiveHealthRedone/Server/Corpse"
require "ExtensiveHealthRedone/Server/Mind"
require "ExtensiveHealthRedone/Server/Knox"
require "ExtensiveHealthRedone/Server/ZVirusVaccine"    -- Phase 10: Zombie Virus Vaccine ties (blood sample, Knox test)
require "ExtensiveHealthRedone/Server/Medication"
require "ExtensiveHealthRedone/Server/Immunity"
require "ExtensiveHealthRedone/Server/Temperature"
require "ExtensiveHealthRedone/Server/IndoorClimate"
require "ExtensiveHealthRedone/Server/Lifestyle"        -- Phase 10: Lifestyle: Hobbies recovery pace and bathing
require "ExtensiveHealthRedone/Server/Watch"
require "ExtensiveHealthRedone/Server/DebugItems"
-- Phase 8: world content.
require "ExtensiveHealthRedone/Server/Loot"
require "ExtensiveHealthRedone/Server/Flyers"
require "ExtensiveHealthRedone/Server/Radio"
require "ExtensiveHealthRedone/Server/Recipes"
require "ExtensiveHealthRedone/Server/WildSearch"
require "ExtensiveHealthRedone/Server/Professions"
require "ExtensiveHealthRedone/Server/Scalpel"
-- Phase 9: load-test commands (debug.perf, debug.perfReport, debug.perfLoad).
require "ExtensiveHealthRedone/Server/Perf"
require "ExtensiveHealthRedone/Server/TemperatureProbe"   -- Phase 6 diagnostic, temporary
-- Phase 9: admin commands (/ehrfullheal, /ehrreset, /ehrinspect) and the debug menu's full heal.
require "ExtensiveHealthRedone/Server/Admin"

local log = Env.logger("Server")

local Main = {}

-- Sync: a client asks for a full snapshot when it joins or when its mirror is stale. 2 per 10 s (SA-12): the client
-- asks at most every 3 s, and a refused hello is simply asked again on the next delta.
Runtime.registry:register("sync.hello", {
    args = { v = { type = "number" } },
    rate = { count = 2, seconds = 10 },
    handler = function(ctx, args)
        if args.v ~= Sync.PROTOCOL then
            log:warn(ctx.actor.key, "speaks sync protocol", args.v, "but the server speaks", Sync.PROTOCOL)
            return
        end
        Runtime.sendSnapshot(ctx.actor.key)
    end,
})

-- Debug commands: sandbox DebugMode plus the medicalAdmin permission (see Game/Permissions).
-- skipTime runs its steps synchronously, so one call is capped at 24 h (1440 steps; SA-13): send it again for more.
Runtime.registry:register("debug.skipTime", {
    args = { minutes = { type = "number", min = 1, max = 24 * 60, integer = true } },
    access = "medicalAdmin",
    debugOnly = true,
    rate = { count = 3, seconds = 10 },
    handler = function(ctx, args)
        -- Advances only this player's simulation; the world clock is untouched.
        local steps = math.floor(args.minutes / Runtime.STEP)
        for _ = 1, steps do
            Runtime.simulate(ctx.actor.key, Runtime.STEP)
        end
        log:info(ctx.actor.key, "debug: skipped", args.minutes, "minutes of health simulation")
    end,
})

Runtime.registry:register("debug.dump", {
    access = "medicalAdmin",
    debugOnly = true,
    handler = function(ctx)
        local text = Dump.lines(Runtime.store:get(ctx.actor.key))
        Transport.toClient(ctx.actor.player, "debugDump", { text = text })
    end,
})

Transport.onClientCommand(Runtime.handleCommand)

local function tick()
    Runtime.scheduler:update(Env.gameMinutes())
end

-- mod.info marks the original (and its predecessor) incompatible, which only the mod screen enforces; a server's mod
-- list or a hand-edited save can still enable both. Two health mods fighting over the same stats is loud in the log.
local ORIGINALS = { "ExtensiveHealthReworkEvolved", "EHR" }

function Main.checkOriginals()
    local mods = getActivatedMods()
    local found = {}
    for _, id in ipairs(ORIGINALS) do
        if mods:contains(id) or mods:contains("\\" .. id) then
            found[#found + 1] = id
        end
    end
    if #found > 0 then
        log:error("the original mod", table.concat(found, ", "), "is enabled together with Extensive Health Redone;",
            "they cannot work together: disable the original")
    end
    return found
end

local function start()
    Env.applyLogLevel()
    Runtime.scheduler:reset()
    log:info("authority started; debug mode", Env.debugMode())
    Main.checkOriginals()
end

-- OnTick drives the scheduler; EveryOneMinute is a fallback in case OnTick doesn't fire on a dedicated server.
-- Extra update calls at the same game time do nothing.
Events.OnTick.Add(tick)
Events.EveryOneMinute.Add(tick)
Events.OnGameStart.Add(start)
Events.OnServerStarted.Add(start)

return Main
