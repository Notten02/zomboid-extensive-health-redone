-- Symptom helpers shared by corpse illness, aspergillosis, scabies and concussion: rolled symptoms with cooldowns,
-- dizziness episodes (vision blur), coughs, collapses and the "health cap" these diseases use.
--
-- Symptom chances are per disease tick of the original mod (60 frames, about 0.8 game minutes), with a cooldown after
-- a success. Here a chance per tick becomes the chance over dt game minutes (Conditions/Symptoms.TICK ticks per
-- minute), and cooldowns are remaining minutes in c.data.cd.

local Symptoms = require "ExtensiveHealthRedone/Conditions/Symptoms"
local Speech = require "ExtensiveHealthRedone/Core/Speech"
local Chance = require "ExtensiveHealthRedone/Core/Chance"
local Cough = require "ExtensiveHealthRedone/Diseases/Shared/Cough"

local Episodes = {}

Episodes.DIZZY_LINES = {
    "UI_EHR_Text_DizzyWorldsSpinning", "UI_EHR_Corpse_Stumbles", "UI_EHR_Corpse_SwaysCantFocus",
}
Episodes.DIZZY_BLUR = 0.55              -- blur strength of a dizzy spell
Episodes.DIZZY_MINUTES = { 5, 10 }      -- game minutes a dizzy spell lasts

-- Counts the condition's cooldowns and episode timers down. Call once at the start of effects().
function Episodes.tick(c, dt)
    local cd = c.data.cd
    if cd then
        for key, left in pairs(cd) do
            cd[key] = left > dt and left - dt or nil
        end
    end
end

-- A symptom that fires with `chance` per disease tick, at most once per cooldownH game hours.
function Episodes.try(p, c, key, chance, cooldownH, dt)
    c.data.cd = c.data.cd or {}
    if c.data.cd[key] or not Chance.roll(p.rng, Chance.over(chance, Symptoms.TICK, dt)) then
        return false
    end
    c.data.cd[key] = cooldownH * 60
    return true
end

-- A line from a pool, at most once per cooldownH (stage-change style: spoken unless dialogue is off).
function Episodes.say(p, c, key, lines, cooldownH)
    c.data.cd = c.data.cd or {}
    if c.data.cd[key] then
        return
    end
    c.data.cd[key] = cooldownH * 60
    Speech.stage(p, Speech.pick(p, lines))
end

-- Starts a dizziness episode: blurred vision for 5-10 game minutes, a line and a jolt of panic.
function Episodes.dizzy(p, c)
    c.data.dizzy = Chance.between(p.rng, Episodes.DIZZY_MINUTES[1], Episodes.DIZZY_MINUTES[2])
    Episodes.say(p, c, "dizzyLine", Episodes.DIZZY_LINES, 0.18)
    p.stats:addF("PANIC", "dizziness", 0.2)
end

-- Keeps a running dizziness episode on screen. Call every step.
function Episodes.blur(p, c, source, dt)
    local left = c.data.dizzy
    if left and left > 0 then
        p.fx:blur(source, Episodes.DIZZY_BLUR)
        c.data.dizzy = left - dt
        if c.data.dizzy <= 0 then
            c.data.dizzy = nil
        end
    end
end

-- A cough: a line, the voice sound and world noise (Server/Noise; a held tissue muffles it). Sounds from all these
-- diseases share one gap (Diseases/Shared/Cough).
function Episodes.cough(p, severe)
    if not Cough.claim(p) then
        return
    end
    Speech.stage(p, severe and "UI_EHR_Text_ViolentCoughingFit" or "UI_EHR_Text_Coughs")
    p.noise(severe and "coughSevere" or "cough")
end

-- A collapse: the character drops, exhausted and panicking.
function Episodes.collapse(p, source)
    Speech.stage(p, "UI_EHR_Text_Collapses")
    p.stats:addF("FATIGUE", source, 0.3)
    p.stats:floorF("PANIC", source, 0.8)
    p.client("fall", { reason = source })
end

-- The health cap these diseases use: health may not regenerate above the cap; the cap follows
-- health down but never below the floor; damage of hpPerMinute is dealt only while health is above the floor.
-- raiseTo: lifts the cap (an improving concussion lets health recover to the new floor). Without a floor the cap
-- has no lower limit (lethal stages).
function Episodes.healthCap(p, c, source, floor, hpPerMinute, dt, raiseTo)
    local health = p.facts.health
    local cap = c.data.cap or health
    if raiseTo and cap < raiseTo then
        cap = raiseTo
    end
    if health < cap then
        cap = math.max(health, floor or 0)
    end
    c.data.cap = cap
    if health >= cap then
        p.body:healFactorAll(Symptoms.ALL_PARTS, source, 0)
    end
    if hpPerMinute > 0 and health > (floor or 0) then
        p.body:damage(source, hpPerMinute * dt, floor or 0)
    end
end

return Episodes
