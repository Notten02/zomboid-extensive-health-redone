-- Readable, deterministic text for plain data (keys sorted), for the debug menu and logs.

local Tables = require "ExtensiveHealthRedone/Core/Tables"

local Dump = {}

local function scalar(value)
    if type(value) == "string" then
        return '"' .. value .. '"'
    end
    return tostring(value)
end

local function write(out, value, indent, depth)
    if type(value) ~= "table" then
        out[#out + 1] = scalar(value)
        return
    end
    if Tables.isEmpty(value) then
        out[#out + 1] = "{}"
        return
    end
    if depth > 12 then
        out[#out + 1] = "{...}"
        return
    end
    out[#out + 1] = "{\n"
    local inner = indent .. "  "
    for _, k in ipairs(Tables.sortedKeys(value)) do
        out[#out + 1] = inner .. tostring(k) .. " = "
        write(out, value[k], inner, depth + 1)
        out[#out + 1] = "\n"
    end
    out[#out + 1] = indent .. "}"
end

-- Multi-line text for a value.
function Dump.lines(value)
    local out = {}
    write(out, value, "", 0)
    return table.concat(out)
end

return Dump
