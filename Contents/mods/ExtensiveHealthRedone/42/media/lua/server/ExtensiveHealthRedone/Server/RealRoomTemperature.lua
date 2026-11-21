-- Real Room Temperature 2.0 (Workshop 3741066319) beside us, with its Body Temperature Rework on. Two ties, on the
-- authority only (single player, the dedicated server), where RRT's body model runs too:
--
--   * no foreign writes: Server/Temperature asks ServerRRT.yields before it holds TEMPERATURE, and skips the hold
--     while RRT's cold model owns the body (Game/RealRoomTemperature.owns). A held fever or frozen-food ceiling waits
--     until RRT lets go; our own state keeps running meanwhile.
--   * cold retention: our provider in RRT's registry (RealRoomHeat2.ColdRetention) returns what the Warming Pack and
--     hot food ask for (Body/Temperature.coldRetention), so they still warm a body RRT is cooling.
--
-- RRT's shared files (its registry among them) load before any server file, so the registry is there when this file
-- loads; registering again on OnGameStart / OnServerStarted covers a late one. RRT runs the provider in its own pcall.
-- An MP client loads this file too and stops at the first line.

if isClient() then
    return
end

local Env = require "ExtensiveHealthRedone/Game/Env"
local PlayerKey = require "ExtensiveHealthRedone/Game/PlayerKey"
local RRT = require "ExtensiveHealthRedone/Game/RealRoomTemperature"
local Runtime = require "ExtensiveHealthRedone/Server/Runtime"
local Temperature = require "ExtensiveHealthRedone/Body/Temperature"

local log = Env.logger("RealRoomTemperature")

local ServerRRT = {}

ServerRRT.PROVIDER_ID = "ExtensiveHealthRedone"

local registered = false
local yielding = {}     -- player key -> true while a hold is skipped, to log the start and end once

-- Whether the hold must leave this player's TEMPERATURE alone this tick. Logs when that starts and ends.
function ServerRRT.yields(key, player)
    local owns = RRT.owns(player)
    if owns ~= (yielding[key] == true) then
        yielding[key] = owns or nil
        log:debug(key, owns and "Real Room Temperature owns the body: temperature hold paused"
            or "Real Room Temperature let go of the body: temperature hold resumed")
    end
    return owns
end

-- The cold retention (0-1) for a player, as RRT asks it. Read-only.
function ServerRRT.retentionFor(player)
    if not RRT.active() then
        return 0
    end
    local key = player and PlayerKey.of(player)
    local state = key and Runtime.store:get(key) or nil
    return state and Temperature.coldRetention(state.temperature) or 0
end

-- Registers our provider with RRT, once. Returns true when it is in place.
function ServerRRT.register()
    if registered then
        return true
    end
    if not RRT.loaded() then
        return false
    end
    local registry = RRT.retention()
    if not registry then
        return false
    end
    local ok, result = pcall(registry.registerColdRetentionProvider, ServerRRT.PROVIDER_ID, ServerRRT.retentionFor)
    if not ok or result == false then
        log:warn("Real Room Temperature refused our cold retention provider:", tostring(result))
        return false
    end
    registered = true
    log:info("Real Room Temperature found: the temperature hold yields to its cold model; the Warming Pack and hot",
        "food reach it as cold retention")
    return true
end

-- Forgets the registration (tests, and a new game in the same session).
function ServerRRT.reset()
    local registry = registered and RRT.retention() or nil
    if registry and type(registry.unregisterColdRetentionProvider) == "function" then
        pcall(registry.unregisterColdRetentionProvider, ServerRRT.PROVIDER_ID)
    end
    registered = false
    yielding = {}
    RRT.reset()
end

ServerRRT.register()
Events.OnGameStart.Add(ServerRRT.register)
Events.OnServerStarted.Add(ServerRRT.register)

return ServerRRT
