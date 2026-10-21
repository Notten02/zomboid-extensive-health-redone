-- Probabilities on the game-time step.
--
-- The original rolled once per update (about once a real second). We run once per game minute, so a chance "per
-- update" becomes the chance of at least one success over the updates that fit in dt minutes.

local Chance = {}

-- p per update, n updates per game minute, dt game minutes -> probability of at least one success.
function Chance.over(p, n, dt)
    if p <= 0 then
        return 0
    end
    if p >= 1 then
        return 1
    end
    return 1 - (1 - p) ^ (n * dt)
end

-- "1 in oneIn" per update.
function Chance.oneIn(oneIn, n, dt)
    if not oneIn or oneIn <= 0 then
        return 0
    end
    return Chance.over(1 / oneIn, n, dt)
end

function Chance.roll(rng, p)
    return p > 0 and rng.float() < p
end

-- A uniform value in [lo, hi].
function Chance.between(rng, lo, hi)
    return lo + (hi - lo) * rng.float()
end

return Chance
