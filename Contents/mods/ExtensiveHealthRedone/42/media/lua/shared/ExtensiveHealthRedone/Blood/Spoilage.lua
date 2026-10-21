-- Blood bag spoilage: a bag turns stale after STALE_HOURS and rotten after ROTTEN_HOURS of warm time. Time spent
-- frozen doesn't count. Stored in the bag's modData under SPOILAGE_KEY in v0.9's format, so bags already in saves
-- keep their state:
--   { createdHour, lastCheckHour, warmElapsed (hours), stale, rotten, isFrozen }
--
-- Spoilage is evaluated lazily: whenever the server looks at a bag, the time since its last check is added as warm
-- time unless the bag is frozen now. A bag that sat on a warm shelf for a day is rotten when picked up; one that sat
-- in a freezer is not. The server scans carried bags regularly, so carried bags spoil on time.

local Data = require "ExtensiveHealthRedone/Data/Blood"

local Spoilage = {}

Spoilage.FRESH, Spoilage.STALE, Spoilage.ROTTEN = "fresh", "stale", "rotten"

function Spoilage.new(nowHours)
    return { createdHour = nowHours, lastCheckHour = nowHours, warmElapsed = 0, stale = false, rotten = false,
        isFrozen = false }
end

local function stateOf(warm, rotten)
    if rotten or warm >= Data.ROTTEN_HOURS then
        return Spoilage.ROTTEN
    elseif warm >= Data.STALE_HOURS then
        return Spoilage.STALE
    end
    return Spoilage.FRESH
end

-- What the bag would be now, without changing it (for display on clients).
function Spoilage.peek(data, nowHours, frozenNow)
    if type(data) ~= "table" then
        return Spoilage.FRESH, 0
    end
    local warm = tonumber(data.warmElapsed) or 0
    local last = tonumber(data.lastCheckHour) or nowHours
    if not frozenNow and not data.rotten then
        warm = warm + math.max(0, nowHours - last)
    end
    return stateOf(warm, data.rotten == true), warm
end

-- Brings the bag's data up to now (authority only). Returns the state and the data table (created if missing).
function Spoilage.update(data, nowHours, frozenNow)
    if type(data) ~= "table" then
        data = Spoilage.new(nowHours)
    end
    local state, warm = Spoilage.peek(data, nowHours, frozenNow)
    data.warmElapsed = warm
    data.lastCheckHour = nowHours
    data.isFrozen = frozenNow == true
    data.rotten = state == Spoilage.ROTTEN
    data.stale = state ~= Spoilage.FRESH
    return state, data
end

-- Hours until the next state change, or nil when rotten or frozen.
function Spoilage.hoursLeft(data, nowHours, frozenNow)
    local state, warm = Spoilage.peek(data, nowHours, frozenNow)
    if frozenNow or state == Spoilage.ROTTEN then
        return nil, state
    end
    local limit = state == Spoilage.FRESH and Data.STALE_HOURS or Data.ROTTEN_HOURS
    return limit - warm, state
end

return Spoilage
