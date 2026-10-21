-- Small helpers for plain data tables (no metatables, no cycles, no game objects).

local Tables = {}

function Tables.deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = Tables.deepCopy(v)
    end
    return copy
end

-- Keys of a table, sorted by their string form, for loops that must not depend on pairs order.
function Tables.sortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return keys
end

-- No next(): it is not a global in 42.21's Kahlua (tools/check-kahlua.lua rejects it).
function Tables.isEmpty(t)
    for _ in pairs(t) do
        return false
    end
    return true
end

return Tables
