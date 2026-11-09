---@diagnostic disable: undefined-global
-- E2E (dev only): the hands and feet conditions on a dedicated server.
--   1. the client wears socks, shoes and gloves; the server's facts.extremities has them;
--   2. the server soaks the socks, the cold, wet feet meter is set just short of trench foot (the room is warm, so the
--      test raises TrenchFootMaxTemperature for its run), and trench foot starts on both feet;
--   3. the client's mirror has the condition with both feet, the wet feet meter, and the Monitor shows it as an
--      unknown foot condition (trench foot is not self-evident and the character knows nothing);
--   4. the trench foot flyer teaches it, and the Monitor row then names it and lists the feet.
-- Needs one client (admin).
if not isServer() then return end
require "PZE2E/PZE2E"

local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Facts = require "ExtensiveHealthRedone/Server/Facts"
local StatWriter = require "ExtensiveHealthRedone/Server/StatWriter"
local Extremities = require "ExtensiveHealthRedone/Server/Extremities"
local Meters = require "ExtensiveHealthRedone/Diseases/Extremities/Meters"
local Learn = require "ExtensiveHealthRedone/Knowledge/Learn"

local SB = SandboxVars.ExtensiveHealthRework

local function state(player)
    return Runtime.store:get(Runtime.attach(player))
end

PZE2E.test("hands and feet: wet socks to trench foot in multiplayer", {
    function(ctx)
        local inv = ctx.player:getInventory()
        for _, t in ipairs({ "Base.Gloves_LeatherGloves", "Base.Socks_Long", "Base.Shoes_TrainerTINT" }) do
            sendAddItemToContainer(inv, inv:AddItem(t))
        end
        PZE2E.ask(ctx.player, "wear", { types = { "Gloves_LeatherGloves", "Socks_Long", "Shoes_TrainerTINT" } }, "wear")
    end,
    function(ctx)
        if not ctx.answers.wear then return "wait" end
        ctx.state.n = (ctx.state.n or 0) + 1
        if ctx.state.n < 3 then return "wait" end
        local e = Facts.read(ctx.player, StatWriter.ranges()).extremities
        PZE2E.log("facts.extremities: %s", PZE2E.describe(e))
        PZE2E.check(e ~= nil and e.socks ~= nil and e.shoes ~= nil and e.gloves ~= nil,
            "the server reads worn socks, shoes and gloves")
        PZE2E.check(e and e.parts.Foot_L and type(e.parts.Foot_L.skinC) == "number", "and the feet's skin temperature")
    end,
    -- Soak the socks and bring the feet to just short of stage 1.
    function(ctx)
        ctx.state.sb = { max = SB.TrenchFootMaxTemperature, hours = SB.TrenchFootHours }
        SB.TrenchFootMaxTemperature = 25
        SB.TrenchFootHours = 2
        local socks = Extremities.worn(ctx.player).socks
        socks:setWetness(100)
        syncItemFields(ctx.player, socks)
        Runtime.applyNow(Runtime.attach(ctx.player), function(p)
            Meters.set(p, "Foot_L", "wetColdH", 2 - 0.02)
            Meters.set(p, "Foot_R", "wetColdH", 2 - 0.02)
        end)
    end,
    function(ctx)
        local c = state(ctx.player).conditions.active.trench_foot
        if not c then
            local socks = Extremities.worn(ctx.player).socks
            PZE2E.log("waiting: socks wetness %s", tostring(socks and socks:getWetness()))
            return "wait"
        end
        PZE2E.check(c.data.parts.Foot_L.stage == 1 and c.data.parts.Foot_R.stage == 1,
            "trench foot started on both feet: %s", PZE2E.describe(c.data.parts))
        PZE2E.check(state(ctx.player).exposure.feet >= 100, "wet feet meter at %s",
            tostring(state(ctx.player).exposure.feet))
        PZE2E.ask(ctx.player, "mirror", {}, "unknown")
    end,
    function(ctx)
        local m = ctx.answers.unknown
        if not m then return "wait" end
        PZE2E.log("client mirror: %s", PZE2E.describe(m))
        PZE2E.check(m.feet == 1 and m.stage == 1, "the client mirror has trench foot on both feet")
        PZE2E.check(m.name == "UI_EHR_Unknown_Foot", "unknown to the character: shown as %s", tostring(m.name))
        PZE2E.check(m.description == "UI_EHR_Unknown_Foot_Desc", "with the unknown hint: %s", tostring(m.description))
        Runtime.applyNow(Runtime.attach(ctx.player), function(p)
            Learn.disease(p, "trench_foot")
        end)
    end,
    function(ctx)
        PZE2E.ask(ctx.player, "mirror", {}, "known")
    end,
    function(ctx)
        local m = ctx.answers.known
        if not m then return "wait" end
        PZE2E.log("client mirror after learning: %s", PZE2E.describe(m))
        PZE2E.check(m.name == "UI_EHR_Disease_trench_foot", "the Monitor names it: %s", tostring(m.name))
        PZE2E.check(m.description == "UI_EHR_Extremities_Join", "and lists both feet: %s", tostring(m.description))
        SB.TrenchFootMaxTemperature = ctx.state.sb.max
        SB.TrenchFootHours = ctx.state.sb.hours
    end,
}, { startAfter = 3, every = 2, maxWaits = 120 })
