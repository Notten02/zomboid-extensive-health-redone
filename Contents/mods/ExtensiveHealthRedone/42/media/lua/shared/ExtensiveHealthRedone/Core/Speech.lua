-- Random symptom lines, scaled by the DialogueFrequency sandbox option (1 Off, 2 Rare, 3 Normal, 4 Frequent).
-- Stage-change lines are always spoken (unless Off); random lines use chance() here.

local Chance = require "ExtensiveHealthRedone/Core/Chance"

local Speech = {}

Speech.MULTIPLIER = { [1] = 0, [2] = 0.25, [3] = 1, [4] = 2 }

function Speech.multiplier(p)
    return Speech.MULTIPLIER[tonumber(p.sandbox("DialogueFrequency", 2)) or 2] or 0.25
end

-- A stage-change line: spoken unless dialogue is off.
function Speech.stage(p, key)
    if key and Speech.multiplier(p) > 0 then
        p.say(key)
    end
end

-- A random line, "1 in oneIn" per v0.9 update, n updates per game minute.
function Speech.maybe(p, key, oneIn, n, dt)
    local mult = Speech.multiplier(p)
    if mult <= 0 then
        return false
    end
    if Chance.roll(p.rng, Chance.oneIn(oneIn / mult, n, dt)) then
        p.say(key)
        return true
    end
    return false
end

-- A random line from a pool, on average once every `every` game minutes at Normal frequency.
function Speech.maybePick(p, keys, every, dt)
    local mult = Speech.multiplier(p)
    if mult <= 0 or every <= 0 then
        return false
    end
    if Chance.roll(p.rng, Chance.oneIn(every / mult, 1, dt)) then
        p.say(Speech.pick(p, keys))
        return true
    end
    return false
end

-- One of several keys at random.
function Speech.pick(p, keys)
    return keys[p.rng.int(1, #keys)]
end

return Speech
