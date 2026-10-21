-- Indoor Climate's room air as the air the player feels: inside a room it simulates, its air temperature replaces
-- vanilla's in facts.env.airC, so the cold and heat meters see heated houses and hot attics. Body temperature stays
-- vanilla's (Indoor Climate's warmth reaches it through its own heat sources). An MP client loads this file too and
-- stops at the first line.
--
-- Indoor Climate Redone simulates rooms on the server, so the server reads the player's room sample through the public
-- API (Game/IndoorClimate) in SP and MP alike. facts.env.nativeAirC keeps vanilla's reading; facts.env.airSource says
-- which one is used.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local IndoorClimate = require "ExtensiveHealthRedone/Game/IndoorClimate"
local Facts = require "ExtensiveHealthRedone/Server/Facts"

local log = Env.logger("IndoorClimate")

local ServerIndoorClimate = {}

-- The Indoor Climate air for a player now (deg C), or nil: in a vehicle, outside a simulated room, or without it.
function ServerIndoorClimate.air(player)
    if player:getVehicle() ~= nil or not IndoorClimate.active() then
        return nil
    end
    return IndoorClimate.sample(player)
end

Facts.extend("icl", function(player, facts)
    local env = facts.env
    env.nativeAirC, env.airSource = env.airC, "vanilla"
    local c = ServerIndoorClimate.air(player)
    if c then
        env.airC, env.airSource = c, "icl"
    end
end)

log:info("indoor climate loaded")

return ServerIndoorClimate
