-- Helpers for tools and tests that read Lua source files. Dev-only, never shipped.
local LuaSource = {}

-- Replace comments and string literals with spaces, keeping newlines so line numbers survive.
function LuaSource.strip(src)
    local out, i, n = {}, 1, #src
    local function blank(s)
        return (s:gsub("[^\n]", " "))
    end
    local function skipTo(stop)
        out[#out + 1] = blank(src:sub(i, stop))
        i = stop + 1
    end
    local function longBracketEnd(eq)
        local _, e = src:find("]" .. eq .. "]", i, true)
        return e or n
    end
    while i <= n do
        local c = src:sub(i, i)
        local commentEq = src:match("^%-%-%[(=*)%[", i)
        local stringEq = src:match("^%[(=*)%[", i)
        if commentEq then
            skipTo(longBracketEnd(commentEq))
        elseif src:sub(i, i + 1) == "--" then
            skipTo((src:find("\n", i, true) or (n + 1)) - 1)
        elseif stringEq then
            skipTo(longBracketEnd(stringEq))
        elseif c == '"' or c == "'" then
            local j = i + 1
            while j <= n do
                local d = src:sub(j, j)
                if d == "\\" then
                    j = j + 2
                elseif d == c or d == "\n" then
                    break
                else
                    j = j + 1
                end
            end
            out[#out + 1] = blank(src:sub(i, j))
            i = j + 1
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

-- Every .lua file under dir, sorted.
function LuaSource.find(dir)
    local files = {}
    local p = assert(io.popen('find "' .. dir .. '" -name "*.lua" | sort'))
    for path in p:lines() do
        files[#files + 1] = path
    end
    p:close()
    return files
end

function LuaSource.read(path)
    local f = assert(io.open(path, "rb"))
    local src = f:read("*a")
    f:close()
    return src
end

return LuaSource
