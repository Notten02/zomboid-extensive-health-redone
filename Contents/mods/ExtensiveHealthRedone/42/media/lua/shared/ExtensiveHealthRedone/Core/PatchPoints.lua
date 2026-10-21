-- Named patch points: the only place where we wrap vanilla Lua methods.
--
-- Each vanilla method is wrapped exactly once, however many features care about it. Features register listeners on
-- the point by name; the wrapper calls them around the original method:
--
--   points:define("eatFood", "ISEatFoodAction.complete")
--   points:on("eatFood", { name = "foodDisease", order = 100, after = function(results, self, ...) end })
--   points:install(function(name) return _G[name] end)   -- done by the game adapter
--
-- Listener fields: name (unique per point), order (lower runs first; ties break by name), before(...) and/or
-- after(results, ...), where results is the packed return of the original ({ n = count, ... }). Listeners see the
-- original arguments, including self. Observers can't change arguments or results.
--
-- The one way to change the outcome is intercept(...): it runs after the before listeners, in order, and may return
-- true followed by the values to return instead of calling the original. The first listener that does wins; the
-- original and the after listeners are then skipped. Used only for the few things Data/PatchPoints lists, each
-- documented where registered. An intercept that throws is logged and treated as "not handled".
--
-- Listener order never depends on file load order. A listener that throws is logged and skipped; the vanilla method
-- and the other listeners still run, because a bug in our code must not break a vanilla action.

local Log = require "ExtensiveHealthRedone/Core/Log"

local PatchPoints = {}
PatchPoints.__index = PatchPoints

function PatchPoints.new(log)
    return setmetatable({ points = {}, log = log or Log.silent }, PatchPoints)
end

-- path: "Class.method" of a global table.
function PatchPoints:define(name, path)
    if self.points[name] then
        error("patch point " .. tostring(name) .. " is already defined", 2)
    end
    local owner, method = tostring(path):match("^([%a_][%w_]*)[%.:]([%a_][%w_]*)$")
    if not owner then
        error("patch point path must look like Class.method: " .. tostring(path), 2)
    end
    self.points[name] = { name = name, path = path, owner = owner, method = method, listeners = {} }
end

local function byOrder(a, b)
    if a.order ~= b.order then
        return a.order < b.order
    end
    return a.name < b.name
end

function PatchPoints:on(pointName, listener)
    local point = self.points[pointName]
    if not point then
        error("unknown patch point " .. tostring(pointName), 2)
    end
    if type(listener.name) ~= "string" then
        error("patch point listeners need a name", 2)
    end
    for _, existing in ipairs(point.listeners) do
        if existing.name == listener.name then
            error("listener " .. listener.name .. " is already on " .. pointName, 2)
        end
    end
    point.listeners[#point.listeners + 1] = {
        name = listener.name,
        order = listener.order or 100,
        before = listener.before,
        after = listener.after,
        intercept = listener.intercept,
    }
    table.sort(point.listeners, byOrder)
end

local function pack(...)
    return { n = select("#", ...), ... }
end

local function wrap(self, point, original)
    local log = self.log
    local function call(listener, phase, fn, ...)
        local ok, err = pcall(fn, ...)
        if not ok then
            log:error("listener", listener.name, phase, point.name, "failed:", err)
        end
    end
    local function intercepted(listener, ...)
        local outcome = pack(pcall(listener.intercept, ...))
        if not outcome[1] then
            log:error("listener", listener.name, "intercept", point.name, "failed:", outcome[2])
            return nil
        end
        if outcome[2] ~= true then
            return nil
        end
        return { n = outcome.n - 2, unpack(outcome, 3, outcome.n) }
    end
    return function(...)
        local listeners = point.listeners
        for i = 1, #listeners do
            local l = listeners[i]
            if l.before then call(l, "before", l.before, ...) end
        end
        for i = 1, #listeners do
            local l = listeners[i]
            if l.intercept then
                local replaced = intercepted(l, ...)
                if replaced then
                    return unpack(replaced, 1, replaced.n)
                end
            end
        end
        local results = pack(original(...))
        for i = 1, #listeners do
            local l = listeners[i]
            if l.after then call(l, "after", l.after, results, ...) end
        end
        return unpack(results, 1, results.n)
    end
end

-- Wraps every defined point whose target exists and isn't wrapped yet. Safe to call again later (for example once
-- client or server files have loaded); each method is wrapped at most once.
-- resolveGlobal(name) -> the global table or nil. Returns { installed = { names }, missing = { names } }, sorted.
function PatchPoints:install(resolveGlobal)
    local report = { installed = {}, missing = {} }
    local names = {}
    for name in pairs(self.points) do
        names[#names + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local point = self.points[name]
        if not point.installed then
            local owner = resolveGlobal(point.owner)
            local original = type(owner) == "table" and owner[point.method]
            if type(original) == "function" then
                owner[point.method] = wrap(self, point, original)
                point.installed = true
                report.installed[#report.installed + 1] = name
            else
                report.missing[#report.missing + 1] = name
            end
        end
    end
    return report
end

return PatchPoints
