---@diagnostic disable: undefined-global
-- E2E test (dev only): concussion detection on a dedicated server (Diseases/Concussion). Steps:
--   1. after the join: no concussion and no open window for a few game minutes;
--   2. the client drops itself one floor, then two, then three (a teleport into the air above an outdoor square),
--      with the chance forced to 100 %: one floor gives nothing, two and three give a concussion. Logged for a
--      human as well: vanilla's damage event on the server and on the client, and each body part's loss as the
--      server sees it;
--   3. the client reconnects (the bench operator restarts it at the RECONNECT NOW line) with a stale window and stale
--      samples saved in its state: the first steps after the rejoin must not roll.
-- A trace line is logged whenever the server's height or body health of an online player changes.
-- Needs one client (admin). Results are [PZE2E] log lines.
if not isServer() then return end
require "PZE2E/PZE2E"
local Env = require "ExtensiveHealthRedone/Game/Env"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Facts = require "ExtensiveHealthRedone/Server/Facts"
local StatWriter = require "ExtensiveHealthRedone/Server/StatWriter"
local Concussion = require "ExtensiveHealthRedone/Diseases/Concussion/Concussion"
local Engine = require "ExtensiveHealthRedone/Conditions/Engine"
local Schema = require "ExtensiveHealthRedone/Core/Schema"
local BodyParts = require "ExtensiveHealthRedone/Data/BodyParts"
local defs = require "ExtensiveHealthRedone/Conditions/Registry"

local function state(player)
    return player:getModData()[Schema.ROOT_KEY]
end

local function concussionData(player)
    local s = state(player)
    return s and s.exposure.data.concussion
end

local function active(player)
    local s = state(player)
    return s and s.conditions.active.concussion
end

local function summary(player)
    local d = concussionData(player)
    local c = active(player)
    if not d then
        return "no state yet"
    end
    return string.format("active=%s pending=%s cooldown=%s samples=%d",
        c and ("stage " .. tostring(c.stage) .. " from " .. tostring(c.source)) or "no",
        d.pending and d.pending.kind or "no", tostring(d.cooldown), #(d.history or {}))
end

local function snapshot(player)
    return Concussion.snapshot(Facts.read(player, StatWriter.ranges()))
end

-- Parts that lost health between two samples: "Head=-3.2 Neck=-3.2 ...", and how many lost at least 1.
local function losses(before, after)
    local parts, broad = {}, 0
    for _, name in ipairs(BodyParts.names) do
        local loss = before.health[name] - after.health[name]
        if math.abs(loss) > 0.05 then
            parts[#parts + 1] = string.format("%s=%.1f", name, -loss)
        end
        if loss >= Concussion.PART_LOSS then
            broad = broad + 1
        end
    end
    return table.concat(parts, " "), broad
end

-- Full health, no concussion, no cooldown, no window: a clean start for the next drop.
local function reset(player)
    local key = Runtime.attach(player)
    Runtime.applyNow(key, function(p)
        Engine.finish(p, defs, "concussion", "debug")
        p.body:fullRestore("e2e")
        p.dirty("conditions")
    end)
    local d = concussionData(player)
    if d then
        d.cooldown, d.pending = nil, nil
    end
end

-- Trace -----------------------------------------------------------------------------------------------------------

local traced = {}       -- username -> { player, z, sum }; "first" in a trace line is the first part, Hand_L
local hold = nil        -- username whose state is kept stale every tick until they leave (the reconnect test)

local function plantStale(player)
    local d = concussionData(player)
    if not d then
        return
    end
    local stale = snapshot(player)
    stale.stale = true
    stale.health.Head = stale.health.Head + 10
    stale.headPain = 0
    d.history = { stale, stale }
    d.pending = { kind = "fall", before = stale, left = 2 }
    d.cooldown = nil
    local key = Runtime.attach(player)
    if active(player) then
        Runtime.applyNow(key, function(p)
            Engine.finish(p, defs, "concussion", "debug")
            p.dirty("conditions")
        end)
    end
end

Events.OnTick.Add(function()
    local online = getOnlinePlayers()
    local seen = {}
    for i = 0, online:size() - 1 do
        local player = online:get(i)
        local name = player:getUsername()
        seen[name] = true
        local parts = player:getBodyDamage():getBodyParts()
        local sum = 0
        for j = 0, parts:size() - 1 do
            sum = sum + parts:get(j):getHealth()
        end
        local z = player:getZ()
        local t = traced[name]
        if not t or t.player ~= player then
            PZE2E.log("trace %s JOINED z=%.2f sum=%.1f first=%.1f firstPain=%.1f square=%s dead=%s state: %s", name, z, sum,
                parts:get(0):getHealth(), parts:get(0):getAdditionalPain(), tostring(player:getCurrentSquare() ~= nil),
                tostring(player:isDead()), summary(player))
            traced[name] = { player = player, z = z, sum = sum }
        elseif math.abs(z - t.z) >= 0.05 or math.abs(sum - t.sum) >= 0.5 then
            PZE2E.log("trace %s z=%.2f sum=%.1f first=%.1f firstPain=%.1f", name, z, sum, parts:get(0):getHealth(),
                parts:get(0):getAdditionalPain())
            t.z, t.sum = z, sum
        end
        if hold == name then
            plantStale(player)
        end
    end
    for name in pairs(traced) do
        if not seen[name] then
            PZE2E.log("trace %s LEFT", name)
            traced[name] = nil
            if hold == name then
                hold = nil
            end
        end
    end
end)

-- Does vanilla raise its damage event on the server? (On a B42 client it does not for a fall.)
Events.OnPlayerGetDamage.Add(function(character, damageType, damage)
    local name = instanceof(character, "IsoPlayer") and character:getUsername() or tostring(character)
    PZE2E.log("SERVER OnPlayerGetDamage %s %s %s", tostring(name), tostring(damageType), tostring(damage))
end)

-- Tests -----------------------------------------------------------------------------------------------------------

local function quiet(ctx, label)
    PZE2E.log("%s: %s", label, summary(ctx.player))
    local d = concussionData(ctx.player)
    PZE2E.check(active(ctx.player) == nil, "%s: no concussion", label)
    PZE2E.check(d == nil or d.pending == nil, "%s: no open window", label)
    PZE2E.check(d == nil or #d.history <= Concussion.HISTORY, "%s: at most %d samples kept", label, Concussion.HISTORY)
end

PZE2E.test("concussion: a join is quiet", {
    function(ctx)
        local options = SandboxVars.ExtensiveHealthRework
        options.DebugMode = true
        options.ConcussionFallChanceMultiplier = 5
        options.ConcussionVehicleChanceMultiplier = 5
        Env.applyLogLevel()
        quiet(ctx, "join +0")
    end,
    function(ctx) quiet(ctx, "join +1") end,
    function(ctx) quiet(ctx, "join +2") end,
    function(ctx) quiet(ctx, "join +3") end,
}, { startAfter = 2, every = 1, maxWaits = 5 })

-- concussed: whether a drop from that many floors must give a concussion.
local function dropSteps(floors, concussed)
    local label = floors .. "-floor drop"
    return {
        function(ctx)
            ctx.answers.outside = nil
            PZE2E.ask(ctx.player, "goOutside", {}, "outside")
        end,
        function(ctx)
            if not ctx.answers.outside then return "wait" end
            reset(ctx.player)
        end,
        -- Two quiet steps, so the detector's samples are of the healed body on the ground.
        function() end,
        function(ctx)
            ctx.state.before = snapshot(ctx.player)
            PZE2E.log("%s: before: %s", label, summary(ctx.player))
            PZE2E.ask(ctx.player, "drop", { floors = floors }, "drop")
        end,
        function(ctx)
            if not ctx.answers.drop then return "wait" end
        end,
        function(ctx)
            PZE2E.ask(ctx.player, "report", {}, "report")
        end,
        function(ctx)
            if not ctx.answers.report then return "wait" end
            local before, after = ctx.state.before, snapshot(ctx.player)
            local lost, broad = losses(before, after)
            PZE2E.log("%s: SERVER part changes: %s", label, lost ~= "" and lost or "none")
            PZE2E.log("%s: SERVER parts that lost %d or more: %d (broad trauma from %d); fractures %d -> %d", label,
                Concussion.PART_LOSS, broad, Concussion.BROAD_PARTS, before.fractures, after.fractures)
            PZE2E.log("%s: CLIENT %s", label, PZE2E.describe(ctx.answers.report))
            PZE2E.log("%s: after: %s", label, summary(ctx.player))
            local c = active(ctx.player)
            if concussed then
                PZE2E.check(c ~= nil and c.source == "fall", "%s: a concussion from the fall", label)
            else
                PZE2E.check(c == nil, "%s: no concussion", label)
            end
        end,
    }
end

PZE2E.test("concussion: one floor", dropSteps(1, false), { startAfter = 1, every = 1, maxWaits = 20 })
PZE2E.test("concussion: two floors", dropSteps(2, true), { startAfter = 1, every = 1, maxWaits = 20 })
PZE2E.test("concussion: three floors", dropSteps(3, true), { startAfter = 1, every = 1, maxWaits = 20 })

PZE2E.test("concussion: a rejoin is quiet, even with a stale window saved", {
    function(ctx)
        reset(ctx.player)
        ctx.state.old = ctx.player
        hold = ctx.player:getUsername()
        plantStale(ctx.player)
        PZE2E.log("RECONNECT NOW: stale state planted (%s)", summary(ctx.player))
    end,
    function(ctx)
        if ctx.player == ctx.state.old or hold then return "wait" end
        PZE2E.log("rejoined: %s", summary(ctx.player))
        local d = concussionData(ctx.player)
        ctx.state.staleSaved = d ~= nil and (d.pending ~= nil or (d.history[1] ~= nil and d.history[1].stale == true))
        -- The detector's first step may not have run yet, so nothing is checked in this one.
        PZE2E.log("stale state came back with the character: %s", tostring(ctx.state.staleSaved))
    end,
    function(ctx) quiet(ctx, "rejoin +1") end,
    function(ctx) quiet(ctx, "rejoin +2") end,
    function(ctx) quiet(ctx, "rejoin +3") end,
}, { startAfter = 1, every = 1, maxWaits = 400 })
