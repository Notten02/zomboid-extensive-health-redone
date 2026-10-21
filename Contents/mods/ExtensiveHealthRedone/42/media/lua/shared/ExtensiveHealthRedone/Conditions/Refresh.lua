-- Keeps the client's copy of running condition and wound-infection timers roughly current for the EHR Monitor's
-- progress bars. The engine syncs only stage changes, so without this a mirrored `left` is as old as the stage. Like
-- the medication refresh (Medication/System), the two sections are re-sent every SYNC_MINUTES game minutes while
-- something runs in them.

local Tables = require "ExtensiveHealthRedone/Core/Tables"

local Refresh = {}

Refresh.SYNC_MINUTES = 10

function Refresh.update(p, dt)
    local conditions, wounds = p.state.conditions, p.state.wounds
    local running = not Tables.isEmpty(conditions.active)
    local infected = not Tables.isEmpty(wounds.parts)
    if not (running or infected) then
        conditions.syncIn = nil
        return
    end
    conditions.syncIn = (conditions.syncIn or Refresh.SYNC_MINUTES) - dt
    if conditions.syncIn <= 0 then
        conditions.syncIn = Refresh.SYNC_MINUTES
        if running then
            p.dirty("conditions")
        end
        if infected then
            p.dirty("wounds")
        end
    end
end

-- Last, so a sent copy includes this step's changes.
Refresh.system = { name = "displayRefresh", order = 990, update = Refresh.update }

return Refresh
