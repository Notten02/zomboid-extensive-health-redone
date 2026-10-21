-- Bookkeeping shared by every disease group: counts down state.exposure.timers (the shared cough gap, Cough.lua)
-- once per step, before the groups' own triggers run.

local Timers = require "ExtensiveHealthRedone/Core/Timers"

return {
    conditions = {},
    systems = {
        {
            name = "exposureTimers",
            order = 305,
            update = function(p, dt)
                Timers.advance(p.state.exposure.timers, dt)
            end,
        },
    },
}
