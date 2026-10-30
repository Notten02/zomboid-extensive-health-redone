-- The authority's runtime: the state store, command registry, simulation pipeline and scheduler for this server
-- (or single-player game). Feature modules add systems and commands here:
--
--   if isClient() then return end                 -- MP client: not the authority
--   local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
--   Runtime.sim:add({ name = "blood", order = 200, update = function(p, dt) ... end })
--   Runtime.registry:register("blood.transfuse", { ... })
--
-- Server/Main.lua wires the game events to it. An MP client loads this file too (it loads lua/server), but only
-- builds empty objects: Main.lua stops on clients, so nothing ever drives them.

local Env = require "ExtensiveHealthRedone/Game/Env"
local Transport = require "ExtensiveHealthRedone/Game/Transport"
local Schema = require "ExtensiveHealthRedone/Core/Schema"
local StateStore = require "ExtensiveHealthRedone/Core/StateStore"
local Sync = require "ExtensiveHealthRedone/Core/Sync"
local CommandRegistry = require "ExtensiveHealthRedone/Core/CommandRegistry"
local Permits = require "ExtensiveHealthRedone/Core/Permits"
local Scheduler = require "ExtensiveHealthRedone/Core/Scheduler"
local Simulation = require "ExtensiveHealthRedone/Core/Simulation"
local Perf = require "ExtensiveHealthRedone/Core/Perf"
local StatAggregator = require "ExtensiveHealthRedone/Core/StatAggregator"
local Players = require "ExtensiveHealthRedone/Server/Players"
local PlayerState = require "ExtensiveHealthRedone/Server/PlayerState"
local StatWriter = require "ExtensiveHealthRedone/Server/StatWriter"
local BodyAggregator = require "ExtensiveHealthRedone/Core/BodyAggregator"
local ClientEffects = require "ExtensiveHealthRedone/Core/ClientEffects"
local Treatments = require "ExtensiveHealthRedone/Core/Treatments"
local Facts = require "ExtensiveHealthRedone/Server/Facts"
local BodyWriter = require "ExtensiveHealthRedone/Server/BodyWriter"
local PerkWriter = require "ExtensiveHealthRedone/Server/PerkWriter"
local Modifiers = require "ExtensiveHealthRedone/Core/Modifiers"
local PerkAggregator = require "ExtensiveHealthRedone/Core/PerkAggregator"
local Noise = require "ExtensiveHealthRedone/Server/Noise"
local Xp = require "ExtensiveHealthRedone/Server/Xp"
local Authority = require "ExtensiveHealthRedone/Actions/Authority"

local log = Env.logger("Server")

local Runtime = {}

-- Simulation step length in game minutes. Systems receive dt = STEP.
Runtime.STEP = 1

-- The epoch only has to differ between server runs; the random part guards against coarse timestamp formatting.
Runtime.store = StateStore.new(Schema.SECTIONS, tostring(getTimestampMs()) .. "-" .. tostring(ZombRand(1000000)))
-- An add-on section registered after this file loaded: the store learns it, and attached states get its defaults.
Schema.onSection(function(name)
    Runtime.store:addSection(name)
    for _, key in ipairs(Runtime.store:keys()) do
        Schema.fillDefaults(Runtime.store:get(key))
    end
end)

Runtime.registry = CommandRegistry.new(Env.realSeconds)
Runtime.permits = Permits.new()
-- Load-test counters (Core/Perf), off until debug.perf turns them on (Server/Perf).
Runtime.perf = Perf.new(function() return getTimestampMs() end)
Runtime.sim = Simulation.new({ perf = Runtime.perf })
Runtime.scheduler = Scheduler.new({ log = Env.logger("Scheduler"), perf = Runtime.perf })

-- key -> the IsoPlayer the attached state belongs to. A different object under the same key (a new character after
-- death, or a reconnect) means the old attachment is stale.
local attachedPlayer = {}
-- Data/BodyParts assumes vanilla's body part order; checked once per run against the first player attached.
local bodyOrderChecked = false

-- key -> true until the first simulation step after attaching (systems use p.fresh to record a baseline).
local fresh = {}

local detachListeners = {}

-- fn(key) when a player's state is detached (logout, death, a new character): drop per-player memory.
function Runtime.onDetach(fn)
    detachListeners[#detachListeners + 1] = fn
end

local function detach(key)
    for _, fn in ipairs(detachListeners) do
        fn(key)
    end
    Runtime.store:detach(key)
    Runtime.permits:forget(key)
    Runtime.registry:forget(key)
    attachedPlayer[key] = nil
    fresh[key] = nil
    log:debug("detached", key)
end

-- Makes sure a living player's state is loaded and attached. Returns the key, or nil when the player can't be served.
function Runtime.attach(player)
    if not Players.isAlive(player) then
        return nil
    end
    local key = Players.record(player).key
    if attachedPlayer[key] == player then
        return key
    end
    if attachedPlayer[key] then
        detach(key)
    end
    local state = PlayerState.load(player, key)
    if not state then
        return nil
    end
    Runtime.store:attach(key, state)
    attachedPlayer[key] = player
    fresh[key] = true
    if not bodyOrderChecked then
        bodyOrderChecked = true
        local wrong = Facts.checkOrder(player)
        if #wrong > 0 then
            log:error("vanilla body part order changed; Data/BodyParts is wrong for:", table.concat(wrong, ", "))
        end
    end
    log:debug("attached", key)
    -- The client may hold an older mirror (or none); a snapshot brings it up to date without waiting for a hello.
    Runtime.sendSnapshot(key)
    return key
end

function Runtime.playerFor(key)
    return attachedPlayer[key]
end

-- Calls fn(key, player, state) for every attached player (any order). For per-tick work outside the simulation step,
-- such as Server/Temperature's fever hold.
function Runtime.eachAttached(fn)
    for key, player in pairs(attachedPlayer) do
        local state = Runtime.store:get(key)
        if state then
            fn(key, player, state)
        end
    end
end

-- Attaches players who came online and detaches those who left or died. Offline players are simply not simulated,
-- so their timers pause.
function Runtime.refreshPresence()
    local seen = {}
    for _, player in ipairs(Players.online()) do
        local key = Runtime.attach(player)
        if key then
            seen[key] = true
        end
    end
    for _, key in ipairs(Runtime.store:keys()) do
        if not seen[key] then
            detach(key)
        end
    end
end

local flushListeners = {}

-- fn(key, changedSections) after a player's changes went out (e.g. Server/Exam refreshes an examining doctor's view).
function Runtime.onFlush(fn)
    flushListeners[#flushListeners + 1] = fn
end

-- Sends one player's pending changes to their client.
function Runtime.flush(key)
    local msg = Runtime.store:takeDelta(key)
    if msg then
        Transport.toClient(attachedPlayer[key], "sync", Sync.encode(msg))
        if Runtime.perf.on then
            Runtime.perf:sections("sync", msg)
        end
        for _, fn in ipairs(flushListeners) do
            fn(key, msg.sections)
        end
    end
end

function Runtime.flushAll()
    for _, key in ipairs(Runtime.store:keys()) do
        Runtime.flush(key)
    end
end

-- Flushes only the players with pending changes (after a command: the sender, a patient, whoever it touched).
function Runtime.flushDirty()
    for _, key in ipairs(Runtime.store:dirtyKeys()) do
        Runtime.flush(key)
    end
end

function Runtime.sendSnapshot(key)
    local msg = Runtime.store:snapshot(key)
    Transport.toClient(attachedPlayer[key], "sync", Sync.encode(msg))
    if Runtime.perf.on then
        Runtime.perf:sections("snapshot", msg)
    end
end

-- The player context systems and effect handlers work with (see Core/Simulation for the fields).
-- Messages for the owning client (speech, blackout, falls) are queued and sent after the writers have run.
local function newContext(key)
    local player = attachedPlayer[key]
    local state = Runtime.store:get(key)
    local ranges = StatWriter.ranges()
    local outbox = {}
    local p = {
        key = key,
        player = nil,       -- never for systems; adapters use Runtime.playerFor
        state = state,
        stats = StatAggregator.new(ranges),
        body = BodyAggregator.new(),
        fx = ClientEffects.new(),
        mods = Modifiers.new(),
        perks = PerkAggregator.new(),
        rng = Env.rng,
        sandbox = Env.sandbox,
        facts = Facts.read(player, ranges),
        treatment = Treatments.forState(state),
        fresh = fresh[key] == true,
        dirty = function(section)
            Runtime.store:markDirty(key, section)
        end,
        say = function(textKey)
            outbox[#outbox + 1] = { "say", { key = textKey } }
        end,
        client = function(command, args)
            outbox[#outbox + 1] = { command, args or {} }
        end,
        noise = function(kind, args)
            outbox[#outbox + 1] = { "noise", { kind = kind, args = args } }
        end,
        -- First Aid XP for this player (Server/Xp): "cure" when a condition ends, and so on.
        xp = function(kind, id)
            outbox[#outbox + 1] = { "xp", { kind = kind, id = id } }
        end,
    }
    return p, player, outbox
end

-- dt: the step's game minutes, or nil for a one-off effect.
local function finish(p, player, outbox, oneOff, dt)
    StatWriter.apply(player, p.stats)
    BodyWriter.apply(player, p.body, p.state.body, oneOff)
    if not oneOff then
        PerkWriter.apply(player, p.perks, p.state.body, dt)
    end

    -- A one-off effect states no continuous wishes; the next step does.
    if not oneOff and p.fx:writeTo(p.state.effects) then
        p.dirty("effects")
    end
    for _, message in ipairs(outbox) do
        if message[1] == "noise" then
            Noise.emit(player, message[2].kind, message[2].args)
        elseif message[1] == "xp" then
            Xp.award(player, message[2].kind, message[2].id)
        else
            message[2].owner = p.key
            Transport.toClient(player, message[1], message[2])
        end
    end
end

-- Runs the simulation for one player over dt game minutes, then writes stats and the body once.
function Runtime.simulate(key, dt)
    local p, player, outbox = newContext(key)
    Runtime.sim:run(p, dt)
    fresh[key] = nil
    finish(p, player, outbox, false, dt)

end

-- Applies a one-off effect to an attached player between simulation steps (a transfusion, a disinfected wound).
-- fn(p) gets the same context as a system; its stat, body and message changes are written at once.
-- Returns fn's result, or nil when the player isn't attached.
function Runtime.applyNow(key, fn)
    if not attachedPlayer[key] then
        return nil
    end
    local p, player, outbox = newContext(key)
    local result = fn(p)
    finish(p, player, outbox, true)
    return result
end

local function step(dt)
    Runtime.refreshPresence()
    for _, key in ipairs(Runtime.store:keys()) do
        Runtime.simulate(key, dt)
    end
end

Runtime.scheduler:every("simulate", Runtime.STEP, step)
Runtime.scheduler:every("sync", Runtime.STEP, Runtime.flushAll, { coalesce = true })
Runtime.scheduler:every("permits", 10, function()
    Runtime.permits:prune(Env.realSeconds())
end, { coalesce = true })

-- Builds the command context for a sender (see Core/CommandRegistry).
local function context(player, key)
    return {
        actor = { key = key, player = player },
        can = function(permission)
            return Players.can(player, permission)
        end,
        debugMode = Env.debugMode(),
        findPlayer = Players.find,
        findItem = function(id)
            return Players.findItem(player, id)
        end,
        distance = function(target)
            return Players.distance(player, target.player)
        end,
        permits = Runtime.permits,
        permitNow = Env.realSeconds(),
        runtime = Runtime,
    }
end

-- Rejections: the command name is cut to COMMAND_CHARS in the log and the reply, and each sender gets at most
-- one log line per REJECT_LOG_SECONDS (with the count of the ones left out), so junk commands can't flood the log.
Runtime.COMMAND_CHARS = 64
Runtime.REJECT_LOG_SECONDS = 10
local rejectLog = {}    -- key -> { at = real seconds, skipped = count }
Runtime.onDetach(function(key)
    rejectLog[key] = nil
end)

local function reject(player, key, kind, command, code, detail)
    local name = tostring(command):sub(1, Runtime.COMMAND_CHARS)
    detail = tostring(detail):sub(1, Runtime.COMMAND_CHARS)
    local now = Env.realSeconds()
    local entry = rejectLog[key]
    if entry and now - entry.at < Runtime.REJECT_LOG_SECONDS then
        entry.skipped = entry.skipped + 1
    else
        local skipped = entry and entry.skipped or 0
        rejectLog[key] = { at = now, skipped = 0 }
        if skipped > 0 then
            log:info(key, kind, name, "rejected:", code, detail, "(and", skipped, "more rejections not logged)")
        else
            log:info(key, kind, name, "rejected:", code, detail)
        end
    end
    Transport.toClient(player, "rejected", { command = name, code = code, detail = detail })
end

-- Entry point for every client command.
function Runtime.handleCommand(player, command, args)
    local key = Runtime.attach(player)
    if not key then
        return
    end
    local t0 = Runtime.perf:start()
    local ok, code, detail = Runtime.registry:dispatch(context(player, key), command, args)
    if t0 then
        Runtime.perf:command("cmd", command, t0, ok, code)
    end
    if not ok then
        reject(player, key, "command", command, code, detail)
    end
    Runtime.flushDirty()
end

-- Entry point for our shared timed actions' complete() (Actions/Authority): the same checks as a client command,
-- for commands registered with `action = true`, without the rate limit. Returns true when the command ran.
function Runtime.runAction(player, command, args)
    local key = Runtime.attach(player)
    if not key then
        return false
    end
    local t0 = Runtime.perf:start()
    local ok, code, detail = Runtime.registry:dispatch(context(player, key), command, args, { fromAction = true })
    if t0 then
        Runtime.perf:command("action", command, t0, ok, code)
    end
    if not ok then
        reject(player, key, "action", command, code, detail)
    end
    Runtime.flushDirty()
    return ok
end

if not isClient() then
    Authority.setRunner(Runtime.runAction)
end

log:info("runtime loaded, epoch", Runtime.store.epoch)

return Runtime
