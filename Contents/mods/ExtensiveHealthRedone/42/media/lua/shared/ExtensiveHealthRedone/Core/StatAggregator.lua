-- The single writer for vanilla character stats.
--
-- Modules never set a vanilla stat. During a simulation update they describe what they want, and the game adapter
-- resolves each touched stat once and writes it once. That makes stacking explicit (two diseases add up instead of
-- the last writer winning) and keeps vanilla's own changes: we add to the current value instead of replacing it.
--
--   agg:add("SICKNESS", "food_poisoning", 0.4)       -- change this update (already scaled by dt)
--   agg:floor("PAIN", "concussion", 30)              -- keep the stat at or above 30
--   agg:ceiling("THIRST", "dysentery", 0.9)          -- keep the stat at or below 0.9
--   agg:raise("TEMPERATURE", "sepsis", 38.6, 0.01)   -- move up toward 38.6 by at most 0.01 this update
--   agg:lower("ENDURANCE", "ahtr", 0.4, 0.01)        -- move down toward 0.4 by at most 0.01 this update
--   local value, changed = agg:resolve("SICKNESS", current)
--
-- Resolution: current + sum of deltas, clamped to the stat's range; then the highest raise target is approached (by
-- that contribution's step), then the lowest lower target; then capped by the lowest ceiling and raised to the highest
-- floor. A floor beats a ceiling when they conflict: a symptom must not be hidden by a cap. Raise and lower never
-- overshoot their target and never move the other way, so two diseases pushing a fever don't add up past the worst.
--
-- B42 stats have different scales (SICKNESS 0-1, PAIN 0-100). The *F methods (addF, raiseF, lowerF, ceilingF, floorF)
-- take values as fractions of the stat's range, so feature code can say "half the pain scale" without knowing it.
--
-- Stat names are the vanilla CharacterStat names ("SICKNESS", "PAIN", ...). Ranges are passed in by the adapter,
-- which reads them from the game, so B42 scale changes (0-1 versus 0-100) don't live in our code.

local StatAggregator = {}
StatAggregator.__index = StatAggregator

-- ranges: { [statName] = { min = n, max = n } }. Only these stats can be used.
function StatAggregator.new(ranges)
    return setmetatable({ ranges = ranges, entries = {} }, StatAggregator)
end

local function entry(self, stat, source)
    if not self.ranges[stat] then
        error("unknown stat " .. tostring(stat), 3)
    end
    if type(source) ~= "string" then
        error("stat contributions need a source name", 3)
    end
    local e = self.entries[stat]
    if not e then
        e = { delta = 0, floor = nil, ceiling = nil, raise = nil, lower = nil, sources = {} }
        self.entries[stat] = e
    end
    return e
end

local function note(e, source, kind, value)
    e.sources[#e.sources + 1] = { source = source, kind = kind, value = value }
end

function StatAggregator:add(stat, source, delta)
    local e = entry(self, stat, source)
    e.delta = e.delta + delta
    note(e, source, "add", delta)
end

function StatAggregator:floor(stat, source, value)
    local e = entry(self, stat, source)
    if e.floor == nil or value > e.floor then
        e.floor = value
    end
    note(e, source, "floor", value)
end

function StatAggregator:ceiling(stat, source, value)
    local e = entry(self, stat, source)
    if e.ceiling == nil or value < e.ceiling then
        e.ceiling = value
    end
    note(e, source, "ceiling", value)
end

-- Approach a target: keeps the most extreme target (highest for raise, lowest for lower) with its step.
function StatAggregator:raise(stat, source, target, step)
    local e = entry(self, stat, source)
    if e.raise == nil or target > e.raise.target then
        e.raise = { target = target, step = step, source = source }
    end
    note(e, source, "raise", target)
end

function StatAggregator:lower(stat, source, target, step)
    local e = entry(self, stat, source)
    if e.lower == nil or target < e.lower.target then
        e.lower = { target = target, step = step, source = source }
    end
    note(e, source, "lower", target)
end

-- The width of a stat's range, and a fraction of the range as an absolute value.
function StatAggregator:span(stat)
    local range = self.ranges[stat]
    if not range then
        error("unknown stat " .. tostring(stat), 2)
    end
    return range.max - range.min
end

function StatAggregator:at(stat, fraction)
    return self.ranges[stat].min + fraction * self:span(stat)
end

function StatAggregator:addF(stat, source, fraction)
    self:add(stat, source, fraction * self:span(stat))
end

function StatAggregator:raiseF(stat, source, target, step)
    self:raise(stat, source, self:at(stat, target), step * self:span(stat))
end

function StatAggregator:lowerF(stat, source, target, step)
    self:lower(stat, source, self:at(stat, target), step * self:span(stat))
end

function StatAggregator:ceilingF(stat, source, fraction)
    self:ceiling(stat, source, self:at(stat, fraction))
end

function StatAggregator:floorF(stat, source, fraction)
    self:floor(stat, source, self:at(stat, fraction))
end

-- Stats with at least one contribution, sorted.
function StatAggregator:touched()
    local list = {}
    for stat in pairs(self.entries) do
        list[#list + 1] = stat
    end
    table.sort(list)
    return list
end

-- Returns the value to write and whether it differs from current.
function StatAggregator:resolve(stat, current)
    local e = self.entries[stat]
    if not e then
        return current, false
    end
    local range = self.ranges[stat]
    local value = current + e.delta
    if value < range.min then value = range.min end
    if value > range.max then value = range.max end
    if e.raise and value < e.raise.target then
        value = math.min(e.raise.target, value + e.raise.step)
    end
    if e.lower and value > e.lower.target then
        value = math.max(e.lower.target, value - e.lower.step)
    end
    if e.ceiling ~= nil and value > e.ceiling then value = e.ceiling end
    if e.floor ~= nil and value < e.floor then value = e.floor end
    return value, value ~= current
end

-- Removes and returns everything said about one stat this update ({ delta, floor, ceiling, raise, lower, sources },
-- or nil), for a system that owns the stat itself: Body/Temperature turns TEMPERATURE contributions into a held
-- fever, so the stat writer never sees them.
function StatAggregator:take(stat)
    local e = self.entries[stat]
    self.entries[stat] = nil
    return e
end

-- The contributions to one stat, in the order they were made (for the debug menu and logs).
function StatAggregator:explain(stat)
    local e = self.entries[stat]
    return e and e.sources or {}
end

function StatAggregator:clear()
    self.entries = {}
end

return StatAggregator
