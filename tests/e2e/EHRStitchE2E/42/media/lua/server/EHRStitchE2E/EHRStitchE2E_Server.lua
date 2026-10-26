---@diagnostic disable: undefined-global
-- E2E (dev only, issue #10): on a dedicated server a player stitches a deep wound through the minigame, then removes
-- the stitch. Before the fix both actions stopped at once: the server rebuilt ISStitch without its arguments.
if not isServer() then return end
require "PZE2E/PZE2E"

local SYNC_ALL = 0xFFFFFFFFFFF

local function handL(player)
    return player:getBodyDamage():getBodyPart(BodyPartType.Hand_L)
end

PZE2E.test("stitch and remove a stitch in multiplayer", {
    -- 1: a deep wound on Hand_L and a suture needle.
    function(ctx)
        local player = ctx.player
        local bp = handL(player)
        bp:setDeepWounded(true)
        bp:setDeepWoundTime(20)
        syncBodyPart(bp, SYNC_ALL)
        local inv = player:getInventory()
        sendAddItemToContainer(inv, inv:AddItem("Base.SutureNeedle"))
        PZE2E.check(bp:deepWounded() and not bp:stitched(), "Hand_L deep wounded, not stitched")
    end,
    -- 2: the client stitches through the Health tab's call, which opens the minigame.
    function(ctx)
        PZE2E.ask(ctx.player, "stitch", {}, "stitch")
    end,
    function(ctx)
        local s = ctx.answers.stitch
        if not s then return "wait" end
        PZE2E.check(s.queued == true and s.deep == true, "client queued the stitch: %s", PZE2E.describe(s))
        PZE2E.ask(ctx.player, "panel", {}, "panel")
    end,
    function(ctx)
        local p = ctx.answers.panel
        if not p then return "wait" end
        PZE2E.check(p.open == true, "minigame panel opened after the server's session")
        PZE2E.ask(ctx.player, "finish", {}, "finish")
    end,
    function(ctx)
        local f = ctx.answers.finish
        if not f then return "wait" end
        PZE2E.check(f.finished == true, "minigame finished with a success")
    end,
    -- 3: the vanilla stitch that follows reaches the server.
    function(ctx)
        if not handL(ctx.player):stitched() then return "wait" end
        PZE2E.check(true, "Hand_L stitched on the server")
        PZE2E.ask(ctx.player, "unstitch", {}, "unstitch")
    end,
    function(ctx)
        local u = ctx.answers.unstitch
        if not u then return "wait" end
        PZE2E.check(u.queued == true and u.stitched == true, "client queued the stitch removal: %s",
            PZE2E.describe(u))
    end,
    -- 4: the removal reaches the server.
    function(ctx)
        if handL(ctx.player):stitched() then return "wait" end
        PZE2E.check(true, "stitch removed on the server")
    end,
}, { startAfter = 2, every = 2, maxWaits = 30 })
