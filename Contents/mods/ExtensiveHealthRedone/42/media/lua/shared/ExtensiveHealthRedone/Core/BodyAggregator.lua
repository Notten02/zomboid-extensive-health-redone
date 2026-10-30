-- What simulation systems want done to the body this update. The body counterpart of Core/StatAggregator.
--
-- Systems never touch body parts. They describe their wishes here; Server/BodyWriter, the only code that changes body
-- parts, reads the current values once, resolves everything with the functions below and writes once.
--
--   body:healFactor("Hand_L", "woundInfection", 0.5)  -- this part keeps at most half of vanilla's healing
--   body:pain("Hand_L", "woundInfection", 30)         -- extra pain we want present on the part (tracked, removable)
--   body:addPain("Neck", "stitch", 10)                -- one-off pain, left to vanilla to fade
--   body:damage("sepsis", 0.5, 30)                    -- overall health damage, never taking health below 30
--   body:partDamage("Head", "spoiledBlood", 12)       -- damage to one part
--   body:infect("Hand_L", "stitch") / body:disinfect("Hand_L", "woundInfection")   -- vanilla infected-wound flag
--   body:scratch("ForeArm_L", "scabies")              -- a new scratch wound, never Knox-infected
--   body:reopen("ForeArm_L", "myaddon:scurvy", "cut") -- an old wound opens again: "scratch", "cut" or "deep"
--   body:woundSpeed("Hand_L", "myaddon:scurvy", 0.5)  -- scratches, cuts, deep wounds and burns close at half speed
--   body:fractureSpeed("ForeArm_L", "myaddon:vitD", 0.7)   -- a fracture knits at 70 % speed
--   body:kill("blood", "exsanguination")
--   body:cureKnox("knoxImmunity") / body:cureKnox("phalanx", 0.25)   -- clear vanilla's Knox infection, or rewind it
--   body:cold("common_cold", 35)                      -- vanilla's cold (moodle, strength); the strongest wish wins
--   body:restoreHealth("med:lastChance", 75)          -- raise overall health to at least 75 (wounds untouched)
--   body:fullRestore("admin")                         -- every part back to full health, wounds and stiffness gone
--
-- Part names are BodyPartType names ("Hand_L", "Neck", ...). Results never depend on pairs order.

local Tables = require "ExtensiveHealthRedone/Core/Tables"

local BodyAggregator = {}
BodyAggregator.__index = BodyAggregator

function BodyAggregator.new()
    return setmetatable({
        heal = {},          -- [part] = lowest factor
        pains = {},         -- [part] = { [source] = amount }
        oneOff = {},        -- [part] = summed one-off pain
        damages = {},       -- list of { source, hp, floor }
        partDamages = {},   -- [part] = summed hp
        infection = {},     -- [part] = true (infect) or false (disinfect); disinfect wins
        killed = nil,       -- { source, cause }
        coldStrength = nil, -- vanilla cold strength wished for (nil = no wish)
    }, BodyAggregator)
end

local function needSource(source)
    if type(source) ~= "string" then
        error("body contributions need a source name", 3)
    end
end

-- Fraction (0-1) of vanilla's HP healing this part may keep. The lowest factor wins; 1 or none means untouched.
function BodyAggregator:healFactor(part, source, factor)
    needSource(source)
    local current = self.heal[part]
    if current == nil or factor < current then
        self.heal[part] = factor
    end
end

function BodyAggregator:healFactorAll(parts, source, factor)
    for _, part in ipairs(parts) do
        self:healFactor(part, source, factor)
    end
end

function BodyAggregator:pain(part, source, amount)
    needSource(source)
    local byPart = self.pains[part]
    if not byPart then
        byPart = {}
        self.pains[part] = byPart
    end
    byPart[source] = (byPart[source] or 0) + amount
end

function BodyAggregator:addPain(part, source, amount)
    needSource(source)
    self.oneOff[part] = (self.oneOff[part] or 0) + amount
end

function BodyAggregator:damage(source, hp, floor)
    needSource(source)
    if hp > 0 then
        self.damages[#self.damages + 1] = { source = source, hp = hp, floor = floor or 0 }
    end
end

function BodyAggregator:partDamage(part, source, hp)
    needSource(source)
    self.partDamages[part] = (self.partDamages[part] or 0) + hp
end

function BodyAggregator:infect(part, source)
    needSource(source)
    if self.infection[part] == nil then
        self.infection[part] = true
    end
end

function BodyAggregator:disinfect(part, source)
    needSource(source)
    self.infection[part] = false
end

-- A new vanilla scratch on the part (scabies), never carrying Knox. self.scratches is [part] = first source.
function BodyAggregator:scratch(part, source)
    needSource(source)
    self.scratches = self.scratches or {}
    if self.scratches[part] == nil then
        self.scratches[part] = source
    end
end

BodyAggregator.REOPEN_RANK = { scratch = 1, cut = 2, deep = 3 }

-- A wound opening on the part again, never carrying Knox: "scratch", "cut" or "deep". The worst kind wished for a part
-- wins. The body writer keeps the Knox guard of scratches. self.reopened is [part] = { kind, source }.
function BodyAggregator:reopen(part, source, kind)
    needSource(source)
    local rank = BodyAggregator.REOPEN_RANK[kind]
    if not rank then
        error("reopen kinds are scratch, cut and deep: " .. tostring(kind), 2)
    end
    self.reopened = self.reopened or {}
    local current = self.reopened[part]
    if current == nil or rank > BodyAggregator.REOPEN_RANK[current.kind] then
        self.reopened[part] = { kind = kind, source = source }
    end
end

-- Share (0-1) of vanilla's wound healing (the scratch, cut, deep wound and burn timers counting down) this part keeps.
-- The lowest factor wins; 1 or none means untouched.
function BodyAggregator:woundSpeed(part, source, factor)
    needSource(source)
    self.woundSpeeds = self.woundSpeeds or {}
    local current = self.woundSpeeds[part]
    if current == nil or factor < current then
        self.woundSpeeds[part] = factor
    end
end

-- The same for the fracture timer.
function BodyAggregator:fractureSpeed(part, source, factor)
    needSource(source)
    self.fractureSpeeds = self.fractureSpeeds or {}
    local current = self.fractureSpeeds[part]
    if current == nil or factor < current then
        self.fractureSpeeds[part] = factor
    end
end

-- Vanilla's Knox infection (Diseases/Knox). Without rewindTo: cured, i.e. the infected flags (body and every part)
-- and infection timers cleared; bite wounds stay. With rewindTo (0-1): still infected, but the infection timers are
-- set back so progress reads rewindTo (Phalanx). The ZOMBIE_INFECTION/ZOMBIE_FEVER stats go through the stat
-- aggregator. A full cure wins over a rewind. self.knox is { source, rewindTo }.
function BodyAggregator:cureKnox(source, rewindTo)
    needSource(source)
    if self.knox and self.knox.rewindTo == nil then
        return
    end
    if self.knox == nil or rewindTo == nil or rewindTo < self.knox.rewindTo then
        self.knox = { source = source, rewindTo = rewindTo }
    end
end

function BodyAggregator:kill(source, cause)
    needSource(source)
    if not self.killed then
        self.killed = { source = source, cause = cause or source }
    end
end

-- Raise overall health to at least target by healing every part below it (Last Chance Epinephrine). Wounds,
-- bleeding and bandages are left as they are. The highest target wins.
function BodyAggregator:restoreHealth(source, target)
    needSource(source)
    if self.restore == nil or target > self.restore.target then
        self.restore = { source = source, target = target }
    end
end

-- Every body part back to full health the way vanilla's health cheat does it (wounds, bleeding and stiffness gone),
-- vanilla's cold off, and our own bookkeeping on the parts (healing caps, tracked pain, cold) dropped. An admin's full
-- heal (Admin/FullHeal). The body writer does it before every other wish. self.full is { source } (the first wins).
function BodyAggregator:fullRestore(source)
    needSource(source)
    if not self.full then
        self.full = { source = source }
    end
end

-- Vanilla's cold: strength 0-100 (0 = no cold while we still own it). The strongest wish wins.
function BodyAggregator:cold(source, strength)
    needSource(source)
    if self.coldStrength == nil or strength > self.coldStrength then
        self.coldStrength = strength
    end
end

-- Desired tracked pain per part: { [part] = amount }, only parts with a contribution.
function BodyAggregator:painTargets()
    local targets = {}
    for part, bySource in pairs(self.pains) do
        local sum = 0
        for _, source in ipairs(Tables.sortedKeys(bySource)) do
            sum = sum + bySource[source]
        end
        targets[part] = sum
    end
    return targets
end

-- Overall health after the damage contributions, applied in source order; each respects its own floor.
-- Returns the total damage to deal.
function BodyAggregator:resolveDamage(health)
    table.sort(self.damages, function(a, b)
        if a.source ~= b.source then
            return a.source < b.source
        end
        return a.hp < b.hp
    end)
    local total = 0
    for _, d in ipairs(self.damages) do
        local allowed = math.max(0, math.min(d.hp, health - d.floor))
        health = health - allowed
        total = total + allowed
    end
    return total
end

-- Healing cap for one part. lock is the HP the part may not exceed (nil when not capped yet).
-- Returns the HP to write (nil = leave it) and the new lock (nil = no cap any more).
-- Damage lowers the lock; healing above it is cut to factor x the gain.
function BodyAggregator.resolveHeal(factor, current, lock)
    if factor == nil or factor >= 1 then
        return nil, nil
    end
    if lock == nil or current <= lock then
        return nil, current
    end
    local allowed = lock + (current - lock) * factor
    return allowed, allowed
end

-- A healing timer slowed to factor of vanilla's pace. current: the timer now; last: what we left it at last step (nil
-- when not slowed yet). Returns the value to write (nil = leave it) and the new last (nil = not slowed any more).
-- A timer that went up since (a new wound, a reset) is accepted as it is; one that went down keeps factor of the drop.
function BodyAggregator.resolveTimer(factor, current, last)
    if factor == nil or factor >= 1 or current <= 0 then
        return nil, nil
    end
    if last == nil or current >= last then
        return nil, current
    end
    local allowed = last - (last - current) * factor
    return allowed, allowed
end

-- Vanilla's cold. want: our wished strength (nil = no wish this step); applied: what we set before (nil = nothing);

-- current: vanilla's strength now. Returns the strength to write (nil = leave vanilla alone) and the new applied
-- value. When we stop asking, our cold is cleared once; vanilla's own colds are otherwise left alone.
function BodyAggregator.resolveCold(want, applied, current)
    if want == nil then
        if applied ~= nil then
            return 0, nil
        end
        return nil, nil
    end
    if current ~= want then
        return want, want
    end
    return nil, want
end

-- Tracked pain for one part. applied is what we added before (0 if nothing). vanilla may have faded some of it.
-- Returns the new additional-pain value and the new applied amount.
function BodyAggregator.resolvePain(target, current, applied)
    target = target or 0
    applied = applied or 0
    local value = current - applied + target
    if value < 0 then value = 0 end
    if value > 100 then value = 100 end
    return value, target
end

return BodyAggregator
