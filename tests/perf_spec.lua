-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
local Perf = require("ExtensiveHealthRedone/Core/Perf")
local Scheduler = require("ExtensiveHealthRedone/Core/Scheduler")
local Simulation = require("ExtensiveHealthRedone/Core/Simulation")

-- A clock the test moves by hand (milliseconds).
local function manualClock()
    local c = { now = 0 }
    c.read = function() return c.now end
    return c
end

local function find(lines, text)
    for _, line in ipairs(lines) do
        if line:find(text, 1, true) then
            return line
        end
    end
    return nil
end

describe("Perf", function()
    it("measures nothing and never reads the clock while off", function()
        local reads = 0
        local perf = Perf.new(function()
            reads = reads + 1
            return 0
        end)
        reads = 0
        assert.is_nil(perf:start())
        perf:stop("job", "simulate", nil)
        perf:count("reject", "bad_args")
        perf:sample("sync", "blood", 10)
        perf:sections("sync", { sections = { blood = { rev = 1, data = {} } } })
        perf:command("cmd", "x", nil, false, "bad_args")
        assert.equal(0, reads)
        assert.is_nil(perf:get("reject", "bad_args"))
        assert.same({}, perf.data)
    end)

    it("keeps count, total and max per category and name", function()
        local clock = manualClock()
        local perf = Perf.new(clock.read)
        perf:setEnabled(true)
        for _, ms in ipairs({ 3, 1, 5 }) do
            local t0 = perf:start()
            clock.now = clock.now + ms
            perf:stop("job", "simulate", t0)
        end
        local e = perf:get("job", "simulate")
        assert.same({ count = 3, total = 9, max = 5 }, e)
        assert.equal(3, (perf:totals("job")))
    end)

    it("counts commands and rejections, folding unknown names into one entry", function()
        local perf = Perf.new(manualClock().read)
        perf:setEnabled(true)
        perf:command("cmd", "medication.take", perf:start(), true)
        perf:command("cmd", "junk1", perf:start(), false, "unknown_command")
        perf:command("cmd", "junk2", perf:start(), false, "unknown_command")
        perf:command("cmd", "debug.dump", perf:start(), false, "forbidden")
        assert.equal(1, perf:get("cmd", "medication.take").count)
        assert.equal(2, perf:get("cmd", "(unknown)").count)
        assert.is_nil(perf:get("cmd", "junk1"))
        assert.equal(2, perf:get("reject", "unknown_command").count)
        assert.equal(1, perf:get("reject", "forbidden").count)
    end)

    it("caps the names per category", function()
        local perf = Perf.new()
        perf:setEnabled(true)
        for i = 1, Perf.MAX_NAMES + 10 do
            perf:count("cmd", "name" .. i)
        end
        assert.equal(10, perf:get("cmd", Perf.OTHER).count)
        assert.is_nil(perf:get("cmd", "name" .. (Perf.MAX_NAMES + 1)))
    end)

    it("estimates sizes deterministically and within bounds", function()
        assert.equal(5 + 2, Perf.estimateSize("hello"))
        assert.equal(8, Perf.estimateSize(1.5))
        assert.equal(1, Perf.estimateSize(true))
        -- 2 for the table, key "a" (3) + number (8), key 1 (8) + "xy" (4)
        assert.equal(2 + 3 + 8 + 8 + 4, Perf.estimateSize({ a = 1, "xy" }))
        local deep = {}
        local t = deep
        for _ = 1, 100 do
            t.next = {}
            t = t.next
        end
        assert.truthy(Perf.estimateSize(deep) < 100 * 10)
        local wide = {}
        for i = 1, Perf.SIZE_NODES * 2 do
            wide[i] = i
        end
        assert.truthy(Perf.estimateSize(wide) <= Perf.SIZE_NODES * 8 + 2)
    end)

    it("sizes each section of a sync message and counts the message", function()
        local perf = Perf.new()
        perf:setEnabled(true)
        local msg = { sections = { blood = { rev = 2, data = { volume = 5000 } }, meds = { rev = 1, data = {} } } }
        perf:sections("sync", msg)
        perf:sections("sync", msg)
        assert.equal(2, perf:get("msg", "sync").count)
        assert.equal(2, perf:get("sync", "blood").count)
        assert.equal(2 * Perf.estimateSize(msg.sections.blood), perf:get("sync", "blood").total)
    end)

    it("starts a new window when turned on, and keeps the numbers when turned off", function()
        local clock = manualClock()
        local perf = Perf.new(clock.read)
        perf:setEnabled(true)
        perf:count("reject", "bad_args")
        perf:setEnabled(false)
        assert.equal(1, perf:get("reject", "bad_args").count)
        clock.now = 5000
        perf:setEnabled(true)
        assert.is_nil(perf:get("reject", "bad_args"))
        assert.equal(0, perf:windowMs())
    end)

    it("reports sorted text lines with rates over the window", function()
        local clock = manualClock()
        local perf = Perf.new(clock.read)
        perf:setEnabled(true)
        local t0 = perf:start()
        clock.now = 4
        perf:stop("job", "sync", t0)
        t0 = perf:start()
        clock.now = 14
        perf:stop("job", "simulate", t0)
        perf:count("reject", "rate_limited", 3)
        clock.now = 2000
        local lines = perf:report({ "Attached players: 2" })
        assert.equal("Perf on, window 2 s real time", lines[1])
        assert.equal("Attached players: 2", lines[2])
        assert.truthy(find(lines, "Scheduler jobs (ms): 2 calls, total 14"))
        local simulate, sync
        for i, line in ipairs(lines) do
            if line:find("simulate:", 1, true) then simulate = i end
            if line:find("  sync:", 1, true) then sync = i end
        end
        assert.truthy(simulate < sync, "biggest total first")
        assert.truthy(find(lines, "rate_limited: n 3, per s 1.5"))
        assert.truthy(find(Perf.new():report(), "(nothing measured yet)"))
    end)

    it("times scheduler jobs only while on", function()
        local clock = manualClock()
        local perf = Perf.new(clock.read)
        local s = Scheduler.new({ perf = perf })
        s:every("work", 1, function() clock.now = clock.now + 2 end)
        s:update(0)
        s:update(3)
        assert.is_nil(perf:get("job", "work"))
        perf:setEnabled(true)
        s:update(5)
        assert.same({ count = 2, total = 4, max = 2 }, perf:get("job", "work"))
    end)

    it("times simulation systems only while on, in the same order", function()
        local clock = manualClock()
        local perf = Perf.new(clock.read)
        local sim = Simulation.new({ perf = perf })
        local order = {}
        sim:add({ name = "b", order = 2, update = function() order[#order + 1] = "b"; clock.now = clock.now + 1 end })
        sim:add({ name = "a", order = 1, update = function() order[#order + 1] = "a" end })
        sim:run({}, 1)
        perf:setEnabled(true)
        sim:run({}, 1)
        assert.same({ "a", "b", "a", "b" }, order)
        assert.same({ count = 1, total = 1, max = 1 }, perf:get("system", "b"))
        assert.equal(1, perf:get("system", "a").count)
        -- Without opts the pipeline still works, with perf off.
        local plain = Simulation.new()
        plain:add({ name = "x", update = function() end })
        plain:run({}, 1)
        assert.is_false(plain.perf.on)
    end)
end)

insulate("debug perf commands in single player", function()
    local FakeGame = require("support/fake_game")
    local Tables = require("ExtensiveHealthRedone/Core/Tables")
    local game = FakeGame.install()
    game.sandbox.DebugMode = true
    local Client = require("ExtensiveHealthRedone/Client/Client")
    local player = game.addPlayer({})
    game.events.OnCreatePlayer.trigger(0, player)
    require("ExtensiveHealthRedone/Server/Main")
    local Runtime = require("ExtensiveHealthRedone/Server/Runtime")
    local Transport = require("ExtensiveHealthRedone/Game/Transport")
    game.events.OnGameStart.trigger()
    game.advance(2)

    local dumped
    Client.on("debugDump", function(args) dumped = args.text end)

    it("turns perf on, counts commands, jobs and sync bytes, and reports them", function()
        Client.send(player, "debug.perf", { on = true })
        assert.is_true(Runtime.perf.on)
        assert.truthy(dumped:find("Perf on", 1, true))
        Client.send(player, "debug.condition", { id = "common_cold", action = "start" })
        Client.send(player, "no.such.command", {})
        game.advance(3)
        Client.send(player, "debug.perfReport", {})
        assert.truthy(dumped:find("Attached players: 1", 1, true))
        assert.truthy(dumped:find("Per game minute (3 in the window)", 1, true), dumped)
        assert.truthy(dumped:find("simulate: n 3", 1, true), dumped)
        assert.truthy(dumped:find("debug.condition: n 1", 1, true), dumped)
        assert.truthy(dumped:find("unknown_command: n 1", 1, true), dumped)
        assert.truthy(dumped:find("Sync deltas by section (bytes)", 1, true), dumped)
        assert.truthy(game.logged("simulate: n 3"))
        Client.send(player, "debug.perf", {})
        assert.is_false(Runtime.perf.on)
    end)

    it("runs ghost players without touching the player, the store or any client", function()
        Client.send(player, "debug.setBlood", { percent = 60 })
        Client.send(player, "debug.medication", { id = "Painkillers", action = "dose" })
        game.advance(1)
        local state = Tables.deepCopy(Runtime.store:get("sp:0"))
        local stats = Tables.deepCopy(player.stats)
        local keys = #Runtime.store:keys()
        local sent = {}
        local toClient = Transport.toClient
        ---@diagnostic disable-next-line: duplicate-set-field
        Transport.toClient = function(p, command, args)
            sent[#sent + 1] = command
            return toClient(p, command, args)
        end
        Client.send(player, "debug.perfLoad", { players = 4, minutes = 5 })
        Transport.toClient = toClient
        assert.same({ "debugDump" }, sent)
        assert.truthy(dumped:find("4 players x 5 game minutes = 20 player-steps", 1, true), dumped)
        assert.is_nil(dumped:find("error", 1, true), dumped)
        assert.same(state, Runtime.store:get("sp:0"))
        assert.same(stats, player.stats)
        assert.equal(keys, #Runtime.store:keys())
        assert.is_false(Runtime.store:isDirty("sp:0", "blood"))
        assert.is_false(Runtime.perf.on)
    end)

    it("refuses perf commands without DebugMode", function()
        local code
        Client.on("rejected", function(args) code = args.code end)
        game.sandbox.DebugMode = false
        Client.send(player, "debug.perfLoad", { players = 1, minutes = 1 })
        assert.equal("debug_only", code)
        game.sandbox.DebugMode = true
    end)
end)
