-- Facts about the running game that the rest of the code asks for in one place: which side we are on, clocks,
-- sandbox options, randomness and loggers.

local Log = require "ExtensiveHealthRedone/Core/Log"

local Env = {}

-- Single player and the dedicated server own the health state. An MP client only mirrors it.
function Env.isAuthority()
    return not isClient()
end

function Env.isMultiplayer()
    return isClient() or isServer()
end

-- Game time in minutes since the world was created. Drives the scheduler.
function Env.gameMinutes()
    return getGameTime():getWorldAgeHours() * 60
end

-- Real time in seconds, for rate limits and consent windows.
function Env.realSeconds()
    return getTimestampMs() / 1000
end

-- Our sandbox options keep the original's namespace so old server configs carry over.
function Env.sandbox(name, default)
    local options = SandboxVars and SandboxVars.ExtensiveHealthRework
    local value = options and options[name]
    if value == nil then
        return default
    end
    return value
end

function Env.debugMode()
    return Env.sandbox("DebugMode", false) == true
end

-- Random source for pure modules: float() in [0, 1) and int(lo, hi) inclusive.
Env.rng = {
    float = function()
        return ZombRandFloat(0, 1)
    end,
    int = function(lo, hi)
        return ZombRand(lo, hi + 1)
    end,
}

-- Loggers print to console.txt. The level follows the sandbox DebugMode option once a game is loaded.
local loggers = {}
local level = "info"

function Env.logger(tag)
    local log = loggers[tag]
    if not log then
        log = Log.new(tag, print, level)
        loggers[tag] = log
    end
    return log
end

-- Call once sandbox options are loaded (game start). Loggers created later start at the same level.
function Env.applyLogLevel()
    level = Env.debugMode() and "debug" or "info"
    for _, log in pairs(loggers) do
        log:setLevel(level)
    end
end

return Env
