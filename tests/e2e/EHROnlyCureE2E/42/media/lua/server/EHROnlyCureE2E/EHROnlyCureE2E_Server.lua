---@diagnostic disable: undefined-global
-- E2E (dev only): The Only Cure beside us on a dedicated server. The player has a wound infection on the left hand,
-- cuts the hand off with the mod's own action, and we check:
--   1. the authority's DataController knows the cut limb and its dirtiness;
--   2. our state: the infection is gone, state.onlyCure has the cut and the stump, the facts read the hand as missing
--      and the forearm as the stump's wound; the client's mirror and Monitor rows have it;
--   3. vanilla infects the deep wound the mod leaves on the forearm within minutes; under an open stump that flag
--      starts nothing of ours (the stump's roll decides);
--   4. the action length (TOC's adjustMaxTime) agrees on the client and the authority;
--   5. a dirty stump rolls an incubation onto the forearm, and the mod's cleaning stops it.
-- Needs one client (admin) and a world without zombies.
if not isServer() then return end
require "PZE2E/PZE2E"

local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Facts = require "ExtensiveHealthRedone/Server/Facts"
local StatWriter = require "ExtensiveHealthRedone/Server/StatWriter"
local OnlyCure = require "ExtensiveHealthRedone/Game/OnlyCure"
local DataController = require "TOC/Controllers/DataController"

local function state(player)
    return Runtime.store:get(Runtime.attach(player))
end

local function dc(player)
    return DataController.GetInstance(player:getUsername())
end

local function partInfo(player, name)
    local bp = player:getBodyDamage():getBodyPart(BodyPartType[name])
    return {
        bleeding = bp:bleeding(), bleedingTime = bp:getBleedingTime(), injury = bp:HasInjury(),
        infectedWound = bp:isInfectedWound(), infectionLevel = bp:getWoundInfectionLevel(),
        cut = bp:isCut(), deep = bp:deepWounded(), health = bp:getHealth(),
    }
end

local function timing(player)
    local action = ISBaseTimedAction:new(player)
    return action:adjustMaxTime(100)
end

local function logForearm(ctx, label)
    local s = state(ctx.player)
    PZE2E.log("%s: ForeArm_L vanilla %s; our wound entry %s", label, PZE2E.describe(partInfo(ctx.player, "ForeArm_L")),
        PZE2E.describe(s.wounds.parts.ForeArm_L))
end

PZE2E.test("The Only Cure amputation in multiplayer", {
    -- 1: the mod's data is ready on the authority, and we read it.
    function(ctx)
        local inst = dc(ctx.player)
        if not (inst and inst:getIsDataReady()) then return "wait" end
        PZE2E.check(OnlyCure.active(), "The Only Cure is active for us")
        PZE2E.check(OnlyCure.read(ctx.player) ~= nil, "we read the authority's DataController")
        PZE2E.check(state(ctx.player).onlyCure.known == true, "state.onlyCure.known after the first steps")
        -- A stage 2 wound infection on the left hand, and a saw.
        Runtime.applyNow(Runtime.attach(ctx.player), function(p)
            p.state.wounds.parts.Hand_L = { phase = "infected", stage = 2, left = 2000 }
            p.dirty("wounds")
        end)
        local inv = ctx.player:getInventory()
        sendAddItemToContainer(inv, inv:AddItem("Base.Saw"))
        ctx.state.before = timing(ctx.player)
        logForearm(ctx, "before")
        PZE2E.ask(ctx.player, "timing", {}, "timingBefore")
    end,
    -- 2: the client cuts its own left hand with the mod's action.
    function(ctx)
        local t = ctx.answers.timingBefore
        if not t then return "wait" end
        PZE2E.check(t.t == ctx.state.before, "action length before: client %s, authority %s", tostring(t.t),
            tostring(ctx.state.before))
        PZE2E.ask(ctx.player, "cut", { limb = "Hand_L" }, "cut")
    end,
    function(ctx)
        local c = ctx.answers.cut
        if not c then return "wait" end
        PZE2E.check(c.queued == true, "client queued the amputation: %s", PZE2E.describe(c))
    end,
    -- 3: the amputation reaches the authority's DataController.
    function(ctx)
        local inst = dc(ctx.player)
        if not inst:getIsCut("Hand_L") then return "wait" end
        PZE2E.check(true, "Hand_L cut in the authority's DataController")
        PZE2E.check(type(inst:getWoundDirtyness("Hand_L")) == "number", "dirtiness on the authority: %s",
            tostring(inst:getWoundDirtyness("Hand_L")))
        PZE2E.log("authority: cicatrized %s, cauterized %s, prosthesis %s", tostring(inst:getIsCicatrized("Hand_L")),
            tostring(inst:getIsCauterized("Hand_L")), tostring(inst:getIsProstEquipped("Hand_L")))
        logForearm(ctx, "right after the cut")
    end,
    -- 4: our state, facts and the client's mirror.
    function(ctx)
        local s = state(ctx.player)
        PZE2E.check(s.wounds.parts.Hand_L == nil, "the hand's wound infection is gone")
        PZE2E.check(s.onlyCure.cut.Hand_L == true, "state.onlyCure.cut.Hand_L")
        local stump = s.onlyCure.stumps.Hand_L
        PZE2E.check(stump ~= nil and stump.part == "ForeArm_L", "stump on the forearm: %s", PZE2E.describe(stump))
        local facts = Facts.read(ctx.player, StatWriter.ranges())
        PZE2E.check(facts.missing and facts.missing.Hand_L == true, "facts read the hand as missing")
        PZE2E.check(facts.parts.ForeArm_L.stump == "Hand_L", "facts read the forearm as the stump's wound")
        ctx.state.after = timing(ctx.player)
        PZE2E.check(ctx.state.after >= ctx.state.before, "the mod slows actions on the authority: %s -> %s",
            tostring(ctx.state.before), tostring(ctx.state.after))
        PZE2E.ask(ctx.player, "timing", {}, "timingAfter")
        PZE2E.ask(ctx.player, "mirror", {}, "mirror")
    end,
    function(ctx)
        local t, m = ctx.answers.timingAfter, ctx.answers.mirror
        if not (t and m) then return "wait" end
        -- Vanilla's own factors (the pain rising after the cut) move a little between the two reads.
        PZE2E.check(math.abs(t.t - ctx.state.after) <= ctx.state.after * 0.01,
            "action length after, within 1%%: client %s, authority %s", tostring(t.t), tostring(ctx.state.after))
        PZE2E.check(m.stump == "ForeArm_L", "client mirror has the stump: %s", PZE2E.describe(m))
        PZE2E.check(m.rows == 1, "one Monitor row on the client")
        PZE2E.check(m.readCut == true, "the client reads its own cut hand (wash menu)")
        PZE2E.check(m.washMode == "hands" and m.washHandL == false, "wash soil skips the cut hand")
        logForearm(ctx, "4 game minutes after the cut")
    end,
    -- 5: a dirty stump rolls (multiplier 5 at full dirt: certain) once its 12 h are up.
    function(ctx)
        local s = state(ctx.player)
        if s.wounds.parts.ForeArm_L then
            PZE2E.log("ForeArm_L already has a wound entry before the roll: %s", PZE2E.describe(s.wounds.parts.ForeArm_L))
        end
        ctx.state.multiplier = SandboxVars.ExtensiveHealthRework.StumpInfectionChanceMultiplier
        SandboxVars.ExtensiveHealthRework.StumpInfectionChanceMultiplier = 5
        dc(ctx.player):setWoundDirtyness("Hand_L", 1)
        s.onlyCure.stumps.Hand_L.elapsed = 12 * 60 - 0.5
    end,
    function(ctx)
        local e = state(ctx.player).wounds.parts.ForeArm_L
        PZE2E.check(e ~= nil and e.phase == "incubating" and e.stump == "Hand_L",
            "the dirty stump started an incubation on the forearm: %s", PZE2E.describe(e))
        -- The mod's Clean Wound sets the dirtiness down.
        dc(ctx.player):setWoundDirtyness("Hand_L", 0)
    end,
    function(ctx)
        PZE2E.check(state(ctx.player).wounds.parts.ForeArm_L == nil, "cleaning the stump stopped the incubation")
        SandboxVars.ExtensiveHealthRework.StumpInfectionChanceMultiplier = ctx.state.multiplier
    end,
    -- 6: a while later, what vanilla did to the forearm on its own.
    function(ctx)
        ctx.state.n = (ctx.state.n or 0) + 1
        if ctx.state.n < 5 then return "wait" end
        logForearm(ctx, "about 12 game minutes later")
        local e = state(ctx.player).wounds.parts.ForeArm_L
        PZE2E.check(e == nil, "vanilla's infection flag under the open stump started nothing: %s", PZE2E.describe(e))
    end,
}, { startAfter = 3, every = 2, maxWaits = 120 })
