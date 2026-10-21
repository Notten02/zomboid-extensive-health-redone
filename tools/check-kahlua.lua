-- Static check that the mod's Lua stays inside the subset Kahlua (Project Zomboid's Lua 5.1 VM) supports.
--
-- 1. Every file must compile with `luac5.1 -p`. That rejects 5.2+ syntax: goto, //, bitwise operators, etc.
-- 2. With comments and strings stripped, no file may use the libraries and functions listed in FORBIDDEN.
--    Field and method names (t.load, obj:load) are not globals and are allowed.
--
-- Usage (from the repo root): lua5.1 tools/check-kahlua.lua [dir]   (default: the mod's Contents folder)
-- Exits non-zero on any violation.

package.path = "tools/lib/?.lua;" .. package.path
local LuaSource = require("LuaSource")

local root = arg[1] or "Contents"

local FORBIDDEN = {
    { "%f[%w_.:]io%s*%.", "io library" },
    { "%f[%w_.:]os%s*%.", "os library" },
    { "%f[%w_.:]debug%s*%.", "debug library" },
    { "%f[%w_.:]utf8%s*%.", "utf8 library (5.3+)" },
    { "%f[%w_.:]string%s*%.%s*pack%f[^%w_]", "string.pack (5.3+)" },
    { "%f[%w_.:]string%s*%.%s*unpack%f[^%w_]", "string.unpack (5.3+)" },
    { "%f[%w_.:]table%s*%.%s*unpack%f[^%w_]", "table.unpack (5.2+; use unpack)" },
    { "%f[%w_.:]table%s*%.%s*move%f[^%w_]", "table.move (5.3+)" },
    { "%f[%w_.:]loadstring%s*%(", "loadstring" },
    { "%f[%w_.:]load%s*%(", "load" },
    { "%f[%w_.:]dofile%s*%(", "dofile" },
    { "%f[%w_.:]next%s*%(", "next (not a global in 42.21; use pairs or Tables.isEmpty)" },
    { "%f[%w_.:]loadfile%s*%(", "loadfile" },
}

local failures = 0
local function fail(msg)
    failures = failures + 1
    print(msg)
end

local files = LuaSource.find(root)

for _, path in ipairs(files) do
    local syntax = assert(io.popen('luac5.1 -p "' .. path .. '" 2>&1'))
    local err = syntax:read("*a")
    syntax:close()
    if err ~= "" then
        fail(err:gsub("%s+$", ""))
    end

    local code = LuaSource.strip(LuaSource.read(path))
    local lineNo = 0
    for line in (code .. "\n"):gmatch("(.-)\n") do
        lineNo = lineNo + 1
        for _, rule in ipairs(FORBIDDEN) do
            if line:find(rule[1]) then
                fail(string.format("%s:%d: %s is not available in Kahlua", path, lineNo, rule[2]))
            end
        end
    end
end

print(string.format("check-kahlua: %d file(s), %d problem(s)", #files, failures))
os.exit(failures == 0 and 0 or 1)
