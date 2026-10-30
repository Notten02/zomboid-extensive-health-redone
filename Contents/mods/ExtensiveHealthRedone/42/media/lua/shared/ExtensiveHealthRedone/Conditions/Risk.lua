-- The immune system's effect on catching a disease: a multiplier on the contraction chance from the immunity score,
-- the disease's sensitivity (Data/Immunity) and ImmunityEffectStrength.
-- Immunity never changes symptoms or progression once a disease has started. The score itself is Immunity/Immunity.

local Data = require "ExtensiveHealthRedone/Data/Immunity"

local Risk = {}

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

function Risk.multiplier(score, sensitivity, strength)
    score = clamp(tonumber(score) or Data.NEUTRAL, 0, 100)
    local full
    if score >= Data.NEUTRAL then
        full = 1 - Data.BEST * (score - Data.NEUTRAL) / (100 - Data.NEUTRAL)
    else
        full = 1 + Data.WORST * (Data.NEUTRAL - score) / Data.NEUTRAL
    end
    return clamp(1 + (full - 1) * sensitivity * strength, 0.35, 2.0)
end

-- How strongly the score acts (0-2): ImmunityEffectStrength, or 0 when the system or its gameplay effects are off
-- ("monitoring only": the score still moves and shows, but every roll is neutral and nothing is contained).
function Risk.strength(p)
    if p.sandbox("ImmunitySystemEnabled", true) == false or p.sandbox("ImmunityGameplayEffects", true) == false then
        return 0
    end
    return clamp(tonumber(p.sandbox("ImmunityEffectStrength", 1)) or 1, 0, 2)
end

-- The chance of catching disease id, after immunity. Unaffected when the disease isn't supported or immunity is off.
function Risk.chance(p, id, chance)
    local sensitivity = Data.SENSITIVITY[id]
    local strength = Risk.strength(p)
    if not sensitivity or strength <= 0 then
        return chance
    end
    return clamp(chance * Risk.multiplier(p.state.immunity.score, sensitivity, strength), 0, 1)
end

return Risk
