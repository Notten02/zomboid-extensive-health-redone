-- The one PatchPoints instance for this Lua VM, defined from Data/PatchPoints.
--
--   local Patches = require "ExtensiveHealthRedone/Game/Patches"
--   Patches.on("eatFood", { name = "foodDisease", after = function(results, action) ... end })
--
-- Targets are installed when they exist: at OnGameBoot (shared and client files are loaded), and again at
-- OnGameStart and OnServerStarted for anything defined later. Each method is wrapped once.
--
-- Add-on mods add their own points with Patches.define (same fields as a Data/PatchPoints entry) and hook vanilla
-- only through points, so every wrapped method is wrapped once however many mods listen.

local PatchPoints = require "ExtensiveHealthRedone/Core/PatchPoints"
local Env = require "ExtensiveHealthRedone/Game/Env"
local definitions = require "ExtensiveHealthRedone/Data/PatchPoints"

local log = Env.logger("Patches")
local points = PatchPoints.new(log)
local otherSide = {}

-- side: "shared" (default), "client" (UI; not on a dedicated server) or "server" (authority; not on an MP client).
local function onThisSide(side)
    if side == "client" then
        return not isServer()
    elseif side == "server" then
        return not isClient()
    end
    return true
end

for _, def in ipairs(definitions) do
    if onThisSide(def.side) then
        points:define(def.name, def.path, def.named)
    else
        otherSide[def.name] = true
    end
end

local Patches = {}

local installedOnce = false
local install

-- def: { name, path = "Class.method", side = "shared" | "client" | "server", named = function(call) ... } as in
-- Data/PatchPoints. Errors on a known name. A point defined after the first install is installed at once when its
-- target exists (and at the next install event otherwise).
function Patches.define(def)
    if type(def) ~= "table" or type(def.name) ~= "string" then
        error("patch points need a name", 2)
    end
    if otherSide[def.name] then
        error("patch point " .. def.name .. " is already defined", 2)
    end
    if onThisSide(def.side) then
        points:define(def.name, def.path, def.named)
        if installedOnce then
            install("define")
        end
    else
        otherSide[def.name] = true
    end
end

-- Listeners on a point that belongs to the other side are ignored, so shared feature code can register freely.
function Patches.on(pointName, listener)
    if not otherSide[pointName] then
        points:on(pointName, listener)
    end
end

function install(when)
    installedOnce = true
    local report = points:install(function(name)
        return _G[name]
    end)
    for _, name in ipairs(report.installed) do
        log:info("patched", name, "at", when)
    end
    for _, name in ipairs(report.missing) do
        -- Expected at boot for targets in server files; after the game has started it means vanilla changed.
        if when == "OnGameBoot" or when == "define" then

            log:debug("patch target for", name, "not loaded yet at", when)
        else
            log:warn("patch target for", name, "missing at", when)
        end
    end
end

Events.OnGameBoot.Add(function() install("OnGameBoot") end)
Events.OnGameStart.Add(function() install("OnGameStart") end)
Events.OnServerStarted.Add(function() install("OnServerStarted") end)

-- One line per load of this file. Two lines in console.txt would mean the game ran it twice (auto-load plus
-- require), giving two instances; the in-game check in phase2-result.md looks for this.
log:info("patch points loaded,", #definitions, "defined")

return Patches
