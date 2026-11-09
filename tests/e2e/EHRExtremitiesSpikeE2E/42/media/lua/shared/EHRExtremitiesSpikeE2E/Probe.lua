---@diagnostic disable: undefined-global
-- E2E spike (dev only): one read of a character's feet and hands, run the same way on the server and on the client so
-- the two can be compared. Every call is wrapped: a method that fails reads as "ERR".
local Probe = {}

local function try(fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok then return "ERR" end
    if v == nil then return "nil" end
    if type(v) == "number" then return math.floor(v * 1000 + 0.5) / 1000 end
    if type(v) == "boolean" or type(v) == "string" then return v end
    return tostring(v)
end

local function location(worn)
    local ok, loc = pcall(function() return tostring(worn:getLocation()):lower():gsub("^base:", "") end)
    return ok and loc or "?"
end

local WANT = { shoes = true, socks = true, hands = true, hands_left = true, hands_right = true }

local function clothing(player)
    local out = {}
    local list = player:getWornItems()
    for i = 0, list:size() - 1 do
        local worn = list:get(i)
        local loc = location(worn)
        if WANT[loc] then
            local item = worn:getItem()
            out[loc] = {
                type = try(function() return item:getFullType() end),
                wet = try(function() return item:getWetness() end),
                holes = try(function() return item:getHolesNumber() end),
                cond = try(function() return item:getCondition() end),
                condMax = try(function() return item:getConditionMax() end),
                insul = try(function() return item:getInsulation() end),
                waterRes = try(function() return item:getWaterResistance() end),
            }
        end
    end
    return out
end

local function part(player, name)
    local bd = player:getBodyDamage()
    local bp = bd:getBodyPart(BodyPartType[name])
    local node = nil
    pcall(function() node = bp:getThermalNode() end)
    if not node then
        pcall(function() node = bd:getThermoregulator():getNodeForType(BodyPartType[name]) end)
    end
    return {
        wet = try(function() return bp:getWetness() end),
        skinT = try(function() return bp:getSkinTemperature() end),
        node = node ~= nil,
        nodeSkinC = node and try(function() return node:getSkinCelcius() end) or "nil",
        nodeBodyWet = node and try(function() return node:getBodyWetness() end) or "nil",
        nodeClothWet = node and try(function() return node:getClothingWetness() end) or "nil",
        nodeInsul = node and try(function() return node:getInsulation() end) or "nil",
    }
end

function Probe.read(player)
    local cm = getClimateManager()
    local sq = player:getCurrentSquare()
    return {
        side = isServer() and "server" or "client",
        pos = string.format("%d,%d,%d", player:getX(), player:getY(), player:getZ()),
        outside = sq and try(function() return sq:isOutside() end) or "nosq",
        raining = try(function() return cm:isRaining() end),
        rain = try(function() return cm:getRainIntensity() end),
        airC = try(function() return cm:getAirTemperatureForCharacter(player) end),
        airChillC = try(function() return cm:getAirTemperatureForCharacter(player, true) end),
        statWet = try(function() return player:getStats():get(CharacterStat.WETNESS) end),
        clothWetSync = try(function() return player:getClothingWetnessSync() end),
        gloves = try(function() return player:isWearingGloves() end),
        coreC = try(function() return player:getBodyDamage():getThermoregulator():getCoreTemperature() end),
        clothing = clothing(player),
        Foot_L = part(player, "Foot_L"),
        Hand_L = part(player, "Hand_L"),
    }
end

return Probe
