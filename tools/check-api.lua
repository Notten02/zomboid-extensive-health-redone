-- Static check that every method the mod calls (obj:name(...)) still exists in the game's API, against the Umbrella
-- type stubs for the target build (tools/fetch-umbrella.sh). Catches a vanilla rename or removal before the game
-- does: 42.21 renamed IsoGridSquare:Is to :has, which broke every simulation step in game while the offline tests,
-- whose fake game still had Is, passed.
--
-- A name passes when the stubs define it on any class, the mod defines it itself (function X:name, function X.name,
-- name = function), or it is a Lua string method. Limits: names only, so a method that exists on a different class
-- passes; static calls (Class.name(...)) and calls on vanilla Lua UI classes the stubs leave out are not checked.
--
-- Usage (from the repo root): lua5.1 tools/check-api.lua [dir]   (default: the mod's Contents folder)
-- Exits non-zero on an unknown method. Without the stubs it warns and passes, so a fresh clone can still run tests.

package.path = "tools/lib/?.lua;" .. package.path
local LuaSource = require("LuaSource")

local root = arg[1] or "Contents"
local STUBS = ".cache/umbrella/library"

local STRING_METHODS = { byte = true, find = true, format = true, gmatch = true, gsub = true, len = true,
    lower = true, match = true, rep = true, reverse = true, sub = true, upper = true }

local function isDir(path)
    local p = assert(io.popen('test -d "' .. path .. '" && echo yes'))
    local out = p:read("*a")
    p:close()
    return out:find("yes") ~= nil
end

if not isDir(STUBS) then
    print("check-api: skipped, no type stubs in " .. STUBS .. " (run tools/fetch-umbrella.sh)")
    os.exit(0)
end

-- Every function name defined in a set of files: function A.b(, function A:b(, function b(, b = function.
local function definedNames(files, names)
    for _, path in ipairs(files) do
        local code = LuaSource.strip(LuaSource.read(path))
        for name in code:gmatch("function%s+[%w_.:]-([%a_][%w_]*)%s*%(") do
            names[name] = true
        end
        for name in code:gmatch("([%a_][%w_]*)%s*=%s*function%f[^%w_]") do
            names[name] = true
        end
    end
    return names
end

local known = definedNames(LuaSource.find(STUBS), {})
local stubCount = 0
for _ in pairs(known) do
    stubCount = stubCount + 1
end
local files = LuaSource.find(root)
definedNames(files, known)
for name in pairs(STRING_METHODS) do
    known[name] = true
end

local failures = 0
for _, path in ipairs(files) do
    local code = LuaSource.strip(LuaSource.read(path))
    local lineNo = 0
    for line in (code .. "\n"):gmatch("(.-)\n") do
        lineNo = lineNo + 1
        for name in line:gmatch("[%w_%)%]]%s*:%s*([%a_][%w_]*)%s*[%(\"'{]") do
            if not known[name] then
                failures = failures + 1
                print(string.format("%s:%d: method %s is not in the game API stubs or the mod", path, lineNo, name))
            end
        end
    end
end

print(string.format("check-api: %d file(s), %d stub names, %d problem(s)", #files, stubCount, failures))
os.exit(failures == 0 and 0 or 1)
