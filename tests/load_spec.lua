-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Offline synthetic load (Phase 9, docs/porting/phase9/server-authority-and-load-test.md section 2.7): N fake players
-- through the real server wiring in single-player mode against tests/support/fake_game.lua, each with conditions,
-- medication, low blood, a wound infection and a transfusion, then a stretch of game time. It prints CPU time per
-- game minute and sync bytes, and asserts generous budgets plus linear growth with N.
--
-- Tagged #load: `tools/test.sh --exclude-tags=load` skips it, `tools/test.sh --tags=load` runs only it.
-- The default run is short (8 and 32 players, 30 game minutes). EHR_LOAD_FULL=1 runs 1, 4, 8, 16 and 32 players for
-- 60 game minutes each.
--
-- The numbers are relative: PUC Lua 5.1 with Lua-closure fakes is much faster than Kahlua with Java getters. Compare
-- runs of this spec with each other, and calibrate once against the in-game ghost load (debug.perfLoad).

local Perf = require("ExtensiveHealthRedone/Core/Perf")

local out = io.stdout
local FULL = os.getenv("EHR_LOAD_FULL") == "1"
local SIZES = FULL and { 1, 4, 8, 16, 32 } or { 8, 32 }
local MINUTES = FULL and 60 or 30

-- Rotated over the players, three each; long-running, non-lethal within the window.
local CONDITIONS = { "common_cold", "food_poisoning", "concussion", "corpse_sickness", "gastroenteritis", "pneumonia",
    "dysentery", "hypothermia", "insomnia", "cellulitis", "tetanus", "toxin_poisoning", "trichinosis",
    "heat_exhaustion" }
local MEDS = { "Antibiotics", "Painkillers", "CoughSyrup", "ColdFluTablets", "AntiInflammatory", "IVFluids",
    "AntipyreticTablets", "SleepingPills" }

-- n -> measured numbers
local results = {}

local function pick(list, i)
    return list[(i - 1) % #list + 1]
end

local function measure(n)
    insulate("synthetic load, " .. n .. " players #load", function()
        local FakeGame = require("support/fake_game")
        local game = FakeGame.install()
        game.sandbox.DebugMode = true

        local Client = require("ExtensiveHealthRedone/Client/Client")
        local players = {}
        for i = 1, n do
            -- Apart from each other, so every corpse scan covers its own squares.
            players[i] = game.addPlayer({ x = 100 + 20 * i, y = 100 + 7 * (i % 5) })
            game.events.OnCreatePlayer.trigger(i - 1, players[i])
        end
        require("ExtensiveHealthRedone/Server/Main")
        local Runtime = require("ExtensiveHealthRedone/Server/Runtime")
        local Transport = require("ExtensiveHealthRedone/Game/Transport")
        game.events.OnGameStart.trigger()
        game.advance(2)

        it("loads every player with diseases, medication, low blood and a transfusion", function()
            local transfused = 0
            for i, player in ipairs(players) do
                Client.send(player, "debug.setBlood", { percent = 60 })
                Client.send(player, "debug.woundInfection", { part = i % 17, stage = 0 })
                for k = 0, 2 do
                    Client.send(player, "debug.condition", { id = pick(CONDITIONS, 3 * i + k), action = "start" })
                end
                for k = 0, 1 do
                    Client.send(player, "debug.medication", { id = pick(MEDS, 2 * i + k), action = "dose" })
                end
                -- A transfusion through the timed-action entry point (Actions/Authority), as the game runs it.
                local bag = player.inventory:add("ExtensiveHealth.BloodBagOPos", { food = true })
                player.inventory:add("ExtensiveHealth.IVKit", { uses = 1 })
                if Runtime.runAction(player, "blood.transfuse", { bag = bag.id }) then
                    transfused = transfused + 1
                end
                if i % 4 == 0 then
                    Client.send(player, "debug.condition", { id = "ahtr", action = "start" })
                end
            end
            game.advance(3)
            assert.equal(n, #Runtime.store:keys())
            local active = 0
            for _, key in ipairs(Runtime.store:keys()) do
                for _ in pairs(Runtime.store:get(key).conditions.active) do
                    active = active + 1
                end
            end
            assert.truthy(active >= 2 * n, "conditions active: " .. active)
            results[n] = { transfused = transfused, conditions = active }
        end)

        it("runs " .. MINUTES .. " game minutes within budget", function()
            -- Count what the server sends, by message name, and the sync bytes (Core/Perf's size estimate).
            local messages, syncBytes, syncMessages = 0, 0, 0
            local toClient = Transport.toClient
            ---@diagnostic disable-next-line: duplicate-set-field
            Transport.toClient = function(player, command, args)
                messages = messages + 1
                if command == "sync" then
                    syncMessages = syncMessages + 1
                    syncBytes = syncBytes + Perf.estimateSize(args)
                end
                return toClient(player, command, args)
            end
            Runtime.perf.clock = function() return os.clock() * 1000 end
            Runtime.perf:setEnabled(true)
            local t0 = os.clock()
            game.advance(MINUTES)
            local seconds = os.clock() - t0
            Runtime.perf:setEnabled(false)
            Transport.toClient = toClient

            local r = results[n]
            r.msPerMinute = seconds * 1000 / MINUTES
            r.msPerPlayerMinute = r.msPerMinute / n
            r.simulateMs = (Runtime.perf:get("job", "simulate") or { total = 0 }).total / MINUTES
            r.messagesPerPlayerMinute = messages / (n * MINUTES)
            r.bytesPerFlush = syncMessages > 0 and syncBytes / syncMessages or 0
            r.bytesPerPlayerMinute = syncBytes / (n * MINUTES)
            r.attached = #Runtime.store:keys()
            r.report = Runtime.perf:report({ "Attached players: " .. r.attached })

            assert.equal(n, r.attached, "every player still attached")
            assert.truthy(r.bytesPerPlayerMinute < 8192, "sync bytes per player per minute " .. r.bytesPerPlayerMinute)
            assert.truthy(r.messagesPerPlayerMinute < 10,
                "messages per player per minute " .. r.messagesPerPlayerMinute)
            -- Generous: PUC Lua does this in well under a millisecond per player.
            assert.truthy(r.msPerPlayerMinute < 25, "ms per player per game minute " .. r.msPerPlayerMinute)
        end)
    end)
end

for _, n in ipairs(SIZES) do
    measure(n)
end

describe("synthetic load summary #load", function()
    it("grows linearly with the number of players", function()
        local small, big = results[SIZES[1]], results[SIZES[#SIZES]]
        assert.truthy(small and small.msPerMinute and big and big.msPerMinute, "every size ran")
        local function f(v, places)
            return Perf.round(v, places or 2)
        end
        out:write("\n\nSynthetic load, ", MINUTES, " game minutes per size (PUC Lua 5.1, relative numbers)\n")
        out:write(string.format("%8s %12s %16s %10s %12s %16s %12s %11s\n", "players", "ms/game min", "ms/player/min",
            "sim ms/min", "bytes/flush", "bytes/player/min", "msgs/pl/min", "conds/trans"))
        for _, n in ipairs(SIZES) do
            local r = results[n]
            out:write(string.format("%8d %12s %16s %10s %12s %16s %12s %11s\n", n, f(r.msPerMinute),
                f(r.msPerPlayerMinute, 3), f(r.simulateMs), f(r.bytesPerFlush, 0), f(r.bytesPerPlayerMinute, 0),
                f(r.messagesPerPlayerMinute), r.conditions .. "/" .. r.transfused))
        end
        out:write("Top of the perf report at ", SIZES[#SIZES], " players:\n")
        for i, line in ipairs(big.report) do
            if i > 24 then
                break
            end
            out:write("  ", line, "\n")
        end
        -- Bytes per player are deterministic and must not grow with N.
        local bytesRatio = big.bytesPerPlayerMinute / small.bytesPerPlayerMinute
        assert.truthy(bytesRatio > 0.5 and bytesRatio < 2, "bytes per player ratio " .. bytesRatio)
        -- Time per player may grow a little (cache effects, the radio's per-player scans), not quadratically.
        local timeRatio = big.msPerPlayerMinute / small.msPerPlayerMinute
        assert.truthy(timeRatio < 2.5, "time per player ratio " .. timeRatio)
    end)
end)
