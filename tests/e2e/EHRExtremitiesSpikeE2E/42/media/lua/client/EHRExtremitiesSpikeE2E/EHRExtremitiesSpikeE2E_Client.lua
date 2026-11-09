---@diagnostic disable: undefined-global
-- E2E spike (dev only), client side: wears the given clothing with vanilla's action, steps outside, and answers the
-- same read-out the server makes (Probe.read) for comparison.
require "PZE2E/PZE2E"
local Probe = require "EHRExtremitiesSpikeE2E/Probe"

PZE2E.answer("probe", function()
    return Probe.read(getPlayer())
end)

PZE2E.answer("wear", function(args)
    local player = getPlayer()
    local inv = player:getInventory()
    local queued = {}
    for _, t in ipairs(args.types) do
        local item = inv:getFirstTypeRecurse(t)
        if item then
            ISTimedActionQueue.add(ISWearClothing:new(player, item))
            queued[#queued + 1] = t
        end
    end
    return { queued = queued }
end)

-- Nearest outdoor, walkable square within 20 tiles; the client moves itself there.
PZE2E.answer("goOutside", function()
    local player = getPlayer()
    local cell = getCell()
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    local best, bestD
    for dx = -20, 20 do
        for dy = -20, 20 do
            local sq = cell:getGridSquare(px + dx, py + dy, pz)
            if sq and sq:isOutside() and sq:isFree(false) then
                local d = dx * dx + dy * dy
                if not bestD or d < bestD then
                    best, bestD = sq, d
                end
            end
        end
    end
    if not best then return { moved = false } end
    player:teleportTo(best:getX() + 0.5, best:getY() + 0.5, best:getZ())
    return { moved = true, to = string.format("%d,%d,%d", best:getX(), best:getY(), best:getZ()) }
end)
