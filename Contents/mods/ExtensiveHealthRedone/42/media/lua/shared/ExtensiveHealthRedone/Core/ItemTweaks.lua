-- Property-level changes to item scripts we don't own (vanilla or other mods).
--
-- Redefining a whole vanilla item in a script file freezes every property at the version it was copied from and
-- fights any other mod that touches the item. Instead, each change names one item and one property, and is applied
-- with Item:DoParam once the scripts are loaded (see Game/ItemTweaks.lua). Each item property may be changed by
-- exactly one entry.
--
-- A tweak is a table:
--   item     full type, "Module.Name"
--   property script property name, as in the item script ("UseDelta")
--   value    the new value as a string, exactly as it would appear in the script ("0.0625")
--   reason   why we change it (shown in logs and reviews)

local ItemTweaks = {}

local function describe(tweak, index)
    return string.format("tweak #%d (%s.%s)", index, tostring(tweak.item), tostring(tweak.property))
end

-- Returns a list of problems with the tweak list; empty when it is valid.
function ItemTweaks.validate(tweaks)
    local problems, seen = {}, {}
    for index, tweak in ipairs(tweaks) do
        local name = describe(tweak, index)
        if type(tweak.item) ~= "string" or not tweak.item:match("^[%w_]+%.[%w_]+$") then
            problems[#problems + 1] = name .. ": item must be a full type like Base.Pills"
        end
        if type(tweak.property) ~= "string" or not tweak.property:match("^[%a_][%w_]*$") then
            problems[#problems + 1] = name .. ": property must be a script property name"
        end
        -- Strings only: number-to-string formatting differs between Kahlua and other Lua runtimes.
        if type(tweak.value) ~= "string" then
            problems[#problems + 1] = name .. ": value must be a string"
        end
        if type(tweak.reason) ~= "string" or tweak.reason == "" then
            problems[#problems + 1] = name .. ": reason is required"
        end
        local key = tostring(tweak.item) .. "|" .. tostring(tweak.property)
        if seen[key] then
            problems[#problems + 1] = name .. ": duplicates tweak #" .. seen[key]
        else
            seen[key] = index
        end
    end
    return problems
end

-- Applies the tweaks. getItem(fullType) must return the script item (an object with DoParam(property, value)),
-- or nil when no such item is loaded. Errors on an invalid list.
-- Returns { applied = { tweak, ... }, missing = { tweak, ... } }.
function ItemTweaks.apply(tweaks, getItem)
    local problems = ItemTweaks.validate(tweaks)
    if #problems > 0 then
        error("invalid item tweaks:\n" .. table.concat(problems, "\n"), 2)
    end
    local result = { applied = {}, missing = {} }
    for _, tweak in ipairs(tweaks) do
        local item = getItem(tweak.item)
        if item then
            item:DoParam(tweak.property, tweak.value)
            result.applied[#result.applied + 1] = tweak
        else
            result.missing[#result.missing + 1] = tweak
        end
    end
    return result
end

return ItemTweaks
