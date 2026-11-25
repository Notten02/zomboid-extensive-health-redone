---@diagnostic disable: undefined-global
-- E2E test (dev only), client side: records OnPlayerGetDamage, moves outside, drops itself from a height and reports
-- what it saw.
require "PZE2E/PZE2E"

local events = {}
local zTrace = nil      -- { max, min, ticks } while a drop is followed

Events.OnPlayerGetDamage.Add(function(character, damageType, damage)
    if character == getPlayer() then
        events[#events + 1] = string.format("%s:%.2f", tostring(damageType), tonumber(damage) or -1)
    end
end)

Events.OnTick.Add(function()
    if not zTrace then return end
    local z = getPlayer():getZ()
    zTrace.max, zTrace.min = math.max(zTrace.max, z), math.min(zTrace.min, z)
    zTrace.ticks = zTrace.ticks + 1
end)

local function openAbove(cell, x, y, z)
    for up = 1, 3 do
        local above = cell:getGridSquare(x, y, z + up)
        if above and above:getFloor() then
            return false
        end
    end
    return true
end

-- Nearest outdoor, walkable square within 25 tiles with nothing above it; the client moves itself there.
PZE2E.answer("goOutside", function()
    local player = getPlayer()
    local cell = getCell()
    local px, py = math.floor(player:getX()), math.floor(player:getY())
    local best, bestD
    for dx = -25, 25 do
        for dy = -25, 25 do
            local sq = cell:getGridSquare(px + dx, py + dy, 0)
            if sq and sq:isOutside() and sq:isFree(false) and openAbove(cell, px + dx, py + dy, 0) then
                local d = dx * dx + dy * dy
                if not bestD or d < bestD then
                    best, bestD = sq, d
                end
            end
        end
    end
    if not best then return { moved = false } end
    player:teleportTo(best:getX() + 0.5, best:getY() + 0.5, 0)
    return { moved = true, to = string.format("%d,%d,0", best:getX(), best:getY()) }
end)

PZE2E.answer("drop", function(args)
    local player = getPlayer()
    events = {}
    zTrace = { max = player:getZ(), min = player:getZ(), ticks = 0 }
    player:teleportTo(player:getX(), player:getY(), args.floors)
    return { from = args.floors, zAfterTeleport = string.format("%.2f", player:getZ()) }
end)

PZE2E.answer("report", function()
    local player = getPlayer()
    local parts = player:getBodyDamage():getBodyParts()
    local lost, fractures = {}, {}
    for i = 0, parts:size() - 1 do
        local part = parts:get(i)
        local name = BodyPartType.ToString(part:getType())
        if part:getHealth() < 99.95 then
            lost[#lost + 1] = string.format("%s=%.1f", name, part:getHealth())
        end
        if part:getFractureTime() > 0 then
            fractures[#fractures + 1] = name
        end
    end
    local trace = zTrace or { max = -1, min = -1, ticks = 0 }
    zTrace = nil
    return {
        events = table.concat(events, ","),
        zMax = string.format("%.2f", trace.max), zMin = string.format("%.2f", trace.min), ticks = trace.ticks,
        zNow = string.format("%.2f", player:getZ()),
        health = string.format("%.1f", player:getBodyDamage():getOverallBodyHealth()),
        parts = table.concat(lost, " "), fractures = table.concat(fractures, " "),
        dead = player:isDead(),
    }
end)
