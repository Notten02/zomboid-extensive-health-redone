-- What active medication does for a player, as the simulation sees it. Medication/System installs the provider
-- (Medication/Provider) with Treatments.setProvider; without one, every question answers "nothing".
--
--   p.treatment:curing("sepsis")                 -- a curative course for this condition is running
--   p.treatment:relief("tetanus", "muscleSpasms") -- 0-1 symptom relief for a condition
--   p.treatment:active("betaBlocker")            -- an effect is active (beta blocker, antiseptic cream, ...)

local Treatments = {}

local none = {}
function none:curing() return false end
function none:relief() return 0 end
function none:active() return false end

Treatments.none = none

local provider

-- fn(state) -> an object with curing/relief/active.
function Treatments.setProvider(fn)
    provider = fn
end

function Treatments.forState(state)
    if provider then
        return provider(state)
    end
    return none
end

return Treatments
