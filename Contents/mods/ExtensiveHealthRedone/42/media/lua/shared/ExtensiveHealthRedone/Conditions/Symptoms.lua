-- Shared symptom helpers for staged conditions: relief-adjusted fever, and the time-base factors.
--
-- The effect numbers are per check of the original mod, which ran every 2 real seconds (cellulitis, tetanus, AHTR) or
-- every 10 (sepsis). With the default 1-hour day that is 0.8 and 4 game minutes, so a per-check step is TICK or
-- SLOW_TICK times that per game minute.

local Symptoms = {}

Symptoms.TICK = 1.25
Symptoms.SLOW_TICK = 0.25

-- Fever target and step after fever relief.
function Symptoms.fever(target, step, relief)
    if relief >= 0.6 then
        target = math.max(37.0, target - 4.0)
    elseif relief > 0 then
        target = math.max(37.4, target - math.min(1.2, 1.8 * relief))
    end
    return target, step * math.max(0.35, 1 - relief)
end

-- Raises body temperature toward a fever target (deg C) through the stat aggregator.
function Symptoms.applyFever(p, source, target, step)
    if target > 36.8 then
        p.stats:raise("TEMPERATURE", source, target, step)
    end
end

-- All body part names, for "no healing anywhere" while a condition is untreated.
Symptoms.ALL_PARTS = require("ExtensiveHealthRedone/Data/BodyParts").names

return Symptoms
