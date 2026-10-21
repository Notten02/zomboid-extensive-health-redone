-- The one cough gap every disease shares (v0.9's EHR_LastCoughSoundHour: no second cough sound within 0.02 game h,
-- from any source). Lives in state.exposure.timers, which Diseases/Shared/Group counts down once per step.

local Timers = require "ExtensiveHealthRedone/Core/Timers"

local Cough = {}

Cough.GAP = 1.2     -- game minutes

-- Claims the gap: true when a cough may sound now (and starts the gap), false while asleep or within the gap.
function Cough.claim(p)
    local timers = p.state.exposure.timers
    if p.facts.asleep or Timers.running(timers, "cough") then
        return false
    end
    Timers.start(timers, "cough", Cough.GAP)
    return true
end

return Cough
