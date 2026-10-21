-- Reads Indoor Climate (an optional mod) through its public API, the global IndoorClimateLite: the air temperature of
-- the room it simulates around a player. Never errors; without it, or when it is off, every function says "nothing".
--
-- Indoor Climate Redone simulates rooms on the server and sends each client its player's sample, so the API answers
-- on a dedicated server, on its clients and in SP. The original Indoor Climate Lite computed samples only on the
-- client; with it, a dedicated server gets no sample and uses vanilla's air.

local Env = require "ExtensiveHealthRedone/Game/Env"

local log = Env.logger("IndoorClimate")

local IndoorClimate = {}

IndoorClimate.MIN_C = -50
IndoorClimate.MAX_C = 50

local announced = false
local failed = false

local function api()
    ---@diagnostic disable-next-line: undefined-global
    local icl = IndoorClimateLite
    if type(icl) == "table" then
        return icl
    end
    return nil
end

-- A pcall at the boundary to an optional mod: its API may change under us. Logs the first failure.
local function call(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then
        return result
    end
    if not failed then
        failed = true
        log:warn("Indoor Climate Lite call failed:", tostring(result))
    end
    return nil
end

function IndoorClimate.sane(c)
    return type(c) == "number" and c == c and c >= IndoorClimate.MIN_C and c <= IndoorClimate.MAX_C
end

-- ICL is installed and switched on (any side).
function IndoorClimate.active()
    local icl = api()
    return icl ~= nil and type(icl.isActive) == "function" and call(icl.isActive) == true
end

-- The square is in a room ICL knows (any side).
function IndoorClimate.inRoom(square)
    local icl = api()
    if not icl or not square or type(icl.getRoomDescriptor) ~= "function" then
        return false
    end
    return call(icl.getRoomDescriptor, square) ~= nil
end

-- The air temperature (deg C) of the room ICL simulates around the player, or nil: outdoors, in a vehicle, before ICL
-- has a room, or without ICL.
function IndoorClimate.sample(player)
    local icl = api()
    if not icl or type(icl.getTemperatureSample) ~= "function" or player:getVehicle() ~= nil then
        return nil
    end
    local s = call(icl.getTemperatureSample, player)
    if type(s) ~= "table" or s.source ~= "IndoorClimateLite" or s.active ~= true or s.indoors ~= true
        or s.roomKey == nil or not IndoorClimate.sane(s.airC) then
        return nil
    end
    if not announced then
        announced = true
        log:info("Indoor Climate Lite", tostring(s.version), "found: its room air feeds the cold and heat meters")
    end
    return s.airC
end

return IndoorClimate
