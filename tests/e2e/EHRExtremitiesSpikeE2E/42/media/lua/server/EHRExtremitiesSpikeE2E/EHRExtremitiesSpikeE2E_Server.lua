---@diagnostic disable: undefined-global
-- E2E spike (dev only): can a dedicated server read a remote player's feet and hands? Steps:
--   1. give gloves, long socks and shoes; the client wears them with vanilla's action;
--   2. baseline read on both sides, indoors and dry;
--   3. the client steps outside, the server starts heavy rain, and both sides read every 2 game minutes;
--   4. fallback check: the server wets the worn socks itself (setWetness + syncItemFields); does the client see it?
-- Needs one client (admin). Results are [PZE2E] log lines; the read-outs are logged for a human to compare.
if not isServer() then return end
require "PZE2E/PZE2E"
local Probe = require "EHRExtremitiesSpikeE2E/Probe"

local RAIN_READS = 30

local function wornSocks(player)
    local list = player:getWornItems()
    for i = 0, list:size() - 1 do
        local worn = list:get(i)
        if tostring(worn:getLocation()):lower():gsub("^base:", "") == "socks" then
            return worn:getItem()
        end
    end
end

local function logPair(label, s, c)
    PZE2E.log("%s SERVER %s", label, PZE2E.describe(s))
    PZE2E.log("%s CLIENT %s", label, PZE2E.describe(c))
end

local function num(v)
    return type(v) == "number" and v or nil
end

PZE2E.test("extremities spike: feet and hands on the server", {
    -- 1: clothing to wear.
    function(ctx)
        local inv = ctx.player:getInventory()
        for _, t in ipairs({ "Base.Gloves_LeatherGloves", "Base.Socks_Long", "Base.Shoes_TrainerTINT" }) do
            sendAddItemToContainer(inv, inv:AddItem(t))
        end
        PZE2E.ask(ctx.player, "wear", { types = { "Gloves_LeatherGloves", "Socks_Long", "Shoes_TrainerTINT" } }, "wear")
    end,
    function(ctx)
        if not ctx.answers.wear then return "wait" end
        PZE2E.log("wear: %s", PZE2E.describe(ctx.answers.wear))
    end,
    -- 2: baseline, after the wear actions had a few game minutes.
    function(ctx)
        ctx.state.n = (ctx.state.n or 0) + 1
        if ctx.state.n < 3 then return "wait" end
        ctx.state.base = Probe.read(ctx.player)
        PZE2E.ask(ctx.player, "probe", {}, "base")
    end,
    function(ctx)
        local c = ctx.answers.base
        if not c then return "wait" end
        local s = ctx.state.base
        logPair("baseline", s, c)
        PZE2E.check(s.clothing.socks ~= nil, "server sees worn socks: %s", PZE2E.describe(s.clothing.socks))
        PZE2E.check(s.clothing.shoes ~= nil, "server sees worn shoes: %s", PZE2E.describe(s.clothing.shoes))
        PZE2E.check(s.gloves == true, "server sees gloves worn (isWearingGloves): %s", tostring(s.gloves))
        PZE2E.check(s.Foot_L.node == true, "server has a thermal node for Foot_L")
        PZE2E.check(num(s.Foot_L.nodeSkinC) ~= nil, "server reads Foot_L skin C: %s (client %s)",
            tostring(s.Foot_L.nodeSkinC), tostring(c.Foot_L.nodeSkinC))
        PZE2E.check(num(s.airChillC) ~= nil, "server reads wind-chill air for the character: %s (client %s)",
            tostring(s.airChillC), tostring(c.airChillC))
    end,
    -- 3: outside in heavy rain.
    function(ctx)
        PZE2E.ask(ctx.player, "goOutside", {}, "outside")
        local ok, err = pcall(function() getClimateManager():transmitServerStartRain(1.0) end)
        PZE2E.log("transmitServerStartRain(1.0): %s %s", tostring(ok), tostring(err))
    end,
    function(ctx)
        if not ctx.answers.outside then return "wait" end
        PZE2E.log("goOutside: %s", PZE2E.describe(ctx.answers.outside))
        ctx.state.reads = 0
    end,
    function(ctx)
        local key = "rain" .. ctx.state.reads
        if ctx.state.reads > 0 then
            local prev = "rain" .. (ctx.state.reads - 1)
            if not ctx.answers[prev] then return "wait" end
            logPair(prev, ctx.state[prev], ctx.answers[prev])
        end
        if ctx.state.reads >= RAIN_READS then return end
        ctx.state[key] = Probe.read(ctx.player)
        PZE2E.ask(ctx.player, "probe", {}, key)
        ctx.state.reads = ctx.state.reads + 1
        return "wait"
    end,
    function(ctx)
        local last = "rain" .. (RAIN_READS - 1)
        local s, c = ctx.state[last], ctx.answers[last]
        PZE2E.check(s.raining == true, "server: raining at the end: %s", tostring(s.raining))
        PZE2E.check(s.outside == true, "server: player outside at the end: %s", tostring(s.outside))
        local sw = s.clothing.socks and num(s.clothing.socks.wet)
        local cw = c.clothing.socks and num(c.clothing.socks.wet)
        PZE2E.log("socks wetness after rain: server %s, client %s", tostring(sw), tostring(cw))
        PZE2E.check(cw == nil or cw == 0 or (sw ~= nil and sw > 0), "when the client's socks got wet, the server's did too")
        PZE2E.log("Foot_L part wetness after rain: server %s, client %s", tostring(s.Foot_L.wet), tostring(c.Foot_L.wet))
        PZE2E.log("Hand_L part wetness after rain: server %s, client %s", tostring(s.Hand_L.wet), tostring(c.Hand_L.wet))
        PZE2E.log("Foot_L skin C after rain: server %s, client %s", tostring(s.Foot_L.nodeSkinC), tostring(c.Foot_L.nodeSkinC))
        pcall(function() getClimateManager():transmitServerStopRain() end)
    end,
    -- 4: the server wets the socks itself.
    function(ctx)
        local socks = wornSocks(ctx.player)
        PZE2E.check(socks ~= nil, "server finds the worn socks")
        if not socks then return end
        socks:setWetness(80)
        syncItemFields(ctx.player, socks)
        ctx.state.serverSet = socks:getWetness()
    end,
    function(ctx)
        ctx.state.m = (ctx.state.m or 0) + 1
        if ctx.state.m == 1 then
            PZE2E.ask(ctx.player, "probe", {}, "afterSet")
            return "wait"
        end
        local c = ctx.answers.afterSet
        if not c then return "wait" end
        local s = Probe.read(ctx.player)
        logPair("afterSet", s, c)
        local cw = c.clothing.socks and num(c.clothing.socks.wet)
        PZE2E.check(cw ~= nil and cw > 40, "client sees the server-set sock wetness (set %s): client %s",
            tostring(ctx.state.serverSet), tostring(cw))
        PZE2E.log("server sock wetness ~2 game minutes after setting 80: %s",
            tostring(s.clothing.socks and s.clothing.socks.wet))
    end,
}, { startAfter = 3, every = 2, maxWaits = 120 })
