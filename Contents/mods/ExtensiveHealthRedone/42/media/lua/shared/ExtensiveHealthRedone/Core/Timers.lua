-- Timers stored as remaining durations, not absolute world times.
--
-- A timer table is plain state ({ [name] = minutesLeft }) that lives inside a player's state and is saved with it.
-- Timers only move when the simulation advances them, so a player who is offline (or a save that is not loaded)
-- keeps exactly the time that was left. Nothing needs shifting on login.

local Timers = {}

function Timers.start(timers, name, minutes)
    if type(minutes) ~= "number" or minutes < 0 then
        error("timer " .. tostring(name) .. " needs a duration >= 0", 2)
    end
    timers[name] = minutes
end

function Timers.cancel(timers, name)
    timers[name] = nil
end

-- Minutes left, or nil when the timer is not running.
function Timers.remaining(timers, name)
    return timers[name]
end

function Timers.running(timers, name)
    return timers[name] ~= nil
end

-- Counts every timer down by dt minutes. Expired timers are removed and their names returned, sorted, so callers
-- handle them in a fixed order whatever the table order is.
function Timers.advance(timers, dt)
    local expired = {}
    for name, left in pairs(timers) do
        left = left - dt
        if left <= 0 then
            expired[#expired + 1] = name
        else
            timers[name] = left
        end
    end
    table.sort(expired)
    for _, name in ipairs(expired) do
        timers[name] = nil
    end
    return expired
end

return Timers
