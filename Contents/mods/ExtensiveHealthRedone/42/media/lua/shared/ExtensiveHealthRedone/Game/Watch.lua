-- The Medical Monitor Watch on game objects: which items are medical watches, their battery state (Items/WatchBattery)
-- in item modData, and which watches and clocks a player wears or holds. Used on both sides: the server drains and
-- swaps batteries, the client shows the blood readout (EHR Monitor), the tooltip and hides the HUD clock.
-- Reading never writes modData, so an MP client never creates item state of its own.

local WatchBattery = require "ExtensiveHealthRedone/Items/WatchBattery"

local Watch = {}

function Watch.isMedical(item)
    return item ~= nil and WatchBattery.TYPES[item:getFullType()] == true
end

-- Vanilla clocks: worn watches and alarm clocks (the item types vanilla's alarm menu checks).
function Watch.isClock(item)
    return item ~= nil and (instanceof(item, "AlarmClockClothing") or instanceof(item, "AlarmClock"))
end

-- The battery state, read-only (a missing table is a full battery).
function Watch.state(item)
    return WatchBattery.read(item:getModData()[WatchBattery.KEY])
end

function Watch.powered(item)
    return WatchBattery.powered(Watch.state(item))
end

-- Writes a state back to the item (the authority, or the client applying the server's sync).
function Watch.save(item, state)
    item:getModData()[WatchBattery.KEY] = WatchBattery.toModData(state)
end

-- Items the player wears or holds, each once.
local function wornOrHeld(player)
    local list, seen = {}, {}
    local function add(item)
        if item and not seen[item] then
            seen[item] = true
            list[#list + 1] = item
        end
    end
    local worn = player:getWornItems()
    for i = 0, worn:size() - 1 do
        add(worn:getItemByIndex(i))
    end
    add(player:getPrimaryHandItem())
    add(player:getSecondaryHandItem())
    return list
end

-- Medical watches worn or held.
function Watch.worn(player)
    local list = {}
    for _, item in ipairs(wornOrHeld(player)) do
        if Watch.isMedical(item) then
            list[#list + 1] = item
        end
    end
    return list
end

-- A powered medical watch is worn or held: the EHR Monitor shows the blood readout.
function Watch.poweredWorn(player)
    for _, item in ipairs(Watch.worn(player)) do
        if Watch.powered(item) then
            return true
        end
    end
    return false
end

-- A clock that isn't a medical watch, worn or held, or loose in the main inventory (an alarm clock in the pocket):
-- it keeps the HUD clock going whatever the medical watch's battery says. Which items vanilla's clock counts is
-- decided in Java; counting more of them only ever errs toward leaving the clock alone.
function Watch.otherClock(player)
    for _, item in ipairs(wornOrHeld(player)) do
        if Watch.isClock(item) and not Watch.isMedical(item) then
            return true
        end
    end
    local items = player:getInventory():getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if Watch.isClock(item) and not Watch.isMedical(item) then
            return true
        end
    end
    return false
end

-- For the HUD clock: does this player wear or hold a dead medical watch, and does anything they have still tell the
-- time (a powered medical watch or another clock)?
function Watch.clockState(player)
    local dead, working = false, false
    for _, item in ipairs(Watch.worn(player)) do
        if Watch.powered(item) then
            working = true
        else
            dead = true
        end
    end
    if dead and not working then
        working = Watch.otherClock(player)
    end
    return dead, working
end

-- Every medical watch the player carries (worn, held or in bags).
function Watch.carried(player)
    local found = player:getInventory():getAllEvalRecurse(function(item)
        return WatchBattery.TYPES[item:getFullType()] == true
    end)
    local list = {}
    for i = 0, found:size() - 1 do
        list[#list + 1] = found:get(i)
    end
    return list
end

-- The charge (0-1) of a vanilla battery item.
function Watch.batteryCharge(item)
    if not item or item:getFullType() ~= WatchBattery.BATTERY then
        return 0
    end
    return math.max(0, math.min(1, tonumber(item:getCurrentUsesFloat()) or 0))
end

-- The best charged vanilla battery the player carries, or nil.
function Watch.bestBattery(player)
    local found = player:getInventory():getAllEvalRecurse(function(item)
        return item:getFullType() == WatchBattery.BATTERY
    end)
    local best, bestCharge = nil, WatchBattery.EPSILON
    for i = 0, found:size() - 1 do
        local item = found:get(i)
        local charge = Watch.batteryCharge(item)
        if charge > bestCharge then
            best, bestCharge = item, charge
        end
    end
    return best
end

-- Switches a watch's alarm off and stops it ringing (a dead or battery-less watch can't ring).
function Watch.silence(item)
    if item:isAlarmSet() then
        item:setAlarmSet(false)
    end
    item:stopRinging()
end

return Watch
