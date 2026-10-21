-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Enforces the code layout:
--   * every Lua file lives under <side>/ExtensiveHealthRedone/, so require paths can't collide with other mods,
--     with Client/ and Server/ subfolders so no relative path repeats across sides;
--   * shared code outside Game/ and Actions/ (adapters, and our B42 shared timed actions, which are globals the
--     server rebuilds by name) is pure: it uses no game API, so these offline tests can load it;
--   * loading a pure module creates no globals;
--   * only Server/StatWriter writes vanilla stats and only Server/BodyWriter changes body parts.
local LuaSource = require("LuaSource")

local LUA = "Contents/mods/ExtensiveHealthRedone/42/media/lua/"
local ROOTS = {
    shared = "shared/ExtensiveHealthRedone/",
    client = "client/ExtensiveHealthRedone/Client/",
    server = "server/ExtensiveHealthRedone/Server/",
}

-- Game API names that pure shared code must not touch. Not exhaustive; it catches the usual suspects.
local GAME_API = {
    "Events", "ScriptManager", "getPlayer", "getSpecificPlayer", "getOnlinePlayers", "getNumActivePlayers",
    "isClient", "isServer", "isCoopHost", "sendClientCommand", "sendServerCommand", "getGameTime", "getWorld",
    "getCell", "ZombRand", "ZombRandFloat", "getSandboxOptions", "SandboxVars", "ModData", "getTexture", "getText",
    "instanceof", "triggerEvent", "getCore", "getTimestamp", "getTimestampMs", "getActivatedMods",
}

local function relative(path)
    return path:sub(#LUA + 1)
end

local function isPureShared(rel)
    return rel:find("^" .. ROOTS.shared) and not rel:find("^" .. ROOTS.shared .. "Game/")
        and not rel:find("^" .. ROOTS.shared .. "Actions/")
end

describe("code layout", function()
    local files = LuaSource.find(LUA)

    it("keeps every file under its side's ExtensiveHealthRedone folder", function()
        for _, path in ipairs(files) do
            local rel = relative(path)
            local side = rel:match("^(%a+)/")
            assert.truthy(ROOTS[side] and rel:find("^" .. ROOTS[side]), rel .. " is outside " .. tostring(ROOTS[side]))
        end
    end)

    it("keeps shared code outside Game/ and Actions/ free of game API calls", function()
        for _, path in ipairs(files) do
            local rel = relative(path)
            if isPureShared(rel) then
                local code = LuaSource.strip(LuaSource.read(path))
                for _, name in ipairs(GAME_API) do
                    assert.is_nil(code:find("%f[%w_]" .. name .. "%f[^%w_]"), rel .. " uses " .. name)
                end
            end
        end
    end)

    it("writes vanilla stats only in the stat writer", function()
        local writer = "server/ExtensiveHealthRedone/Server/StatWriter.lua"
        local patterns = {
            ":%s*set%s*%(%s*CharacterStat", ":%s*add%s*%(%s*CharacterStat", ":%s*remove%s*%(%s*CharacterStat",
            ":%s*reset%s*%(%s*CharacterStat", "%f[%w_]sendPlayerStat%f[^%w_]", "%f[%w_]sendPlayerStatsChange%f[^%w_]",
            "%f[%w_]syncPlayerStats%f[^%w_]",
        }
        for _, path in ipairs(files) do
            local rel = relative(path)
            if rel ~= writer then
                local code = LuaSource.strip(LuaSource.read(path))
                for _, pattern in ipairs(patterns) do
                    assert.is_nil(code:find(pattern), rel .. " writes a vanilla stat; use the StatAggregator")
                end
            end
        end
    end)

    it("changes body parts only in the body writer", function()
        local writer = "server/ExtensiveHealthRedone/Server/BodyWriter.lua"
        local patterns = {
            ":%s*SetHealth%s*%(", ":%s*ReduceHealth%s*%(", ":%s*AddHealth%s*%(", ":%s*setAdditionalPain%s*%(",
            ":%s*setInfectedWound%s*%(", ":%s*setWoundInfectionLevel%s*%(", ":%s*ReduceGeneralHealth%s*%(",
            ":%s*AddGeneralHealth%s*%(", ":%s*setOverallBodyHealth%s*%(", ":%s*Kill%s*%(",
            ":%s*RestoreToFullHealth%s*%(", ":%s*setStiffness%s*%(", ":%s*removeStiffnessValue%s*%(",
            "%f[%w_]syncBodyPart%f[^%w_]",
        }
        for _, path in ipairs(files) do
            local rel = relative(path)
            if rel ~= writer then
                local code = LuaSource.strip(LuaSource.read(path))
                for _, pattern in ipairs(patterns) do
                    assert.is_nil(code:find(pattern), rel .. " changes a body part; use the BodyAggregator")
                end
            end
        end
    end)

    it("loads pure shared modules without creating globals", function()
        for _, path in ipairs(files) do
            local rel = relative(path)
            if isPureShared(rel) then
                local before = {}
                for k in pairs(_G) do
                    before[k] = true
                end
                require(rel:match("^shared/(.+)%.lua$"))
                for k in pairs(_G) do
                    assert.truthy(before[k], rel .. " created the global " .. tostring(k))
                end
            end
        end
    end)
end)
