---@diagnostic disable: undefined-global
-- E2E (dev only, issue #10), client side: queues vanilla's stitch actions the way the Health tab does
-- (ISTimedActionQueue.add(ISStitch:new(...))) and plays the minigame to a success.
require "PZE2E/PZE2E"

local StitchMinigame = require "ExtensiveHealthRedone/Client/StitchMinigame"

local function handL()
    return getPlayer():getBodyDamage():getBodyPart(BodyPartType.Hand_L)
end

PZE2E.answer("stitch", function()
    local player = getPlayer()
    local needle = player:getInventory():getFirstTypeRecurse("SutureNeedle")
    if not needle then return { queued = false, error = "no suture needle on this client" } end
    local part = handL()
    ISTimedActionQueue.add(ISStitch:new(player, player, needle, part, true))
    return { queued = true, deep = part:deepWounded() }
end)

PZE2E.answer("panel", function()
    return { open = StitchMinigame.panel() ~= nil }
end)

-- Every point hit: the outcome the panel sends when the last point is clicked.
PZE2E.answer("finish", function()
    local panel = StitchMinigame.panel()
    if not panel then return { finished = false } end
    panel:finish("success")
    return { finished = true }
end)

PZE2E.answer("unstitch", function()
    local player = getPlayer()
    local part = handL()
    ISTimedActionQueue.add(ISStitch:new(player, player, nil, part, false))
    return { queued = true, stitched = part:stitched() }
end)
