-- Symptom episodes the environmental diseases share: coughs and sneezes (with world noise), dizziness (vision blur),
-- confusion, and collapse into a forced sleep. Speech cooldowns and episode timers live in the condition's data, as
-- remaining game minutes.

local Data = require "ExtensiveHealthRedone/Diseases/Weather/Data"
local Meters = require "ExtensiveHealthRedone/Diseases/Weather/Meters"
local Speech = require "ExtensiveHealthRedone/Core/Speech"
local Chance = require "ExtensiveHealthRedone/Core/Chance"
local Cough = require "ExtensiveHealthRedone/Diseases/Shared/Cough"

local Episodes = {}

local E = Data.episodes

Episodes.COUGH_LINES = { "UI_EHR_Weather_Cough", "UI_EHR_Text_Coughs", "UI_EHR_Weather_CoughCough" }
Episodes.SEVERE_COUGH_LINES = {
    "UI_EHR_Weather_ViolentCoughingFit", "UI_EHR_Weather_CoughsUncontrollably", "UI_EHR_Weather_CoughingCantStop",
}
Episodes.SNEEZE_LINES = { "UI_EHR_Text_ACHOO", "UI_EHR_Text_Sneezes", "UI_EHR_Text_Achoo" }

-- The weather group's own timers (cough throttle, cold and heat-stroke rolls), advanced once per step by the
-- exposure system.
function Episodes.timers(p)
    return Meters.weather(p).timers
end

-- Counts down a per-condition cooldown in c.data. Returns true when it is free (and restarts it).
local function cooldown(c, name, dt, minutes)
    local left = (c.data[name] or 0) - dt
    if left > 0 then
        c.data[name] = left
        return false
    end
    c.data[name] = minutes
    return true
end

-- Ticks a countdown in c.data without restarting it; returns the minutes left.
local function tick(c, name, dt)
    local left = (c.data[name] or 0) - dt
    c.data[name] = left > 0 and left or nil
    return c.data[name] or 0
end

-- A cough: voice, world noise and a line. At most one per Cough.GAP game minutes from any disease.
-- Returns true when the character coughed.
function Episodes.cough(p, severe)
    if not Cough.claim(p) then
        return false
    end
    p.noise(severe and "coughSevere" or "cough")
    Speech.stage(p, Speech.pick(p, severe and Episodes.SEVERE_COUGH_LINES or Episodes.COUGH_LINES))
    return true
end

-- A sneeze (never in its sleep).
function Episodes.sneeze(p)
    if p.facts.asleep then
        return false
    end
    p.noise("sneeze")
    Speech.stage(p, Speech.pick(p, Episodes.SNEEZE_LINES))
    return true
end

-- Runs a "one every intervalH game hours" symptom (cough, sneeze) from a countdown in c.data[name]. relief 0-1
-- stretches the interval (interval / max(0.1, 1 - relief)); at 95% relief or more the symptom stops.
function Episodes.every(p, c, name, intervalH, relief, dt, fn)
    local mult = 1 - (relief or 0)
    if mult <= 0.05 then
        c.data[name] = nil
        return
    end
    local interval = intervalH * 60 / math.max(0.10, mult)
    if c.data[name] == nil then
        c.data[name] = interval
    end
    c.data[name] = c.data[name] - dt
    if c.data[name] <= 0 then
        c.data[name] = interval
        fn(p)
    end
end

-- Dizziness: a blur episode of 5-10 game minutes, panic, and a line (cooldown in game minutes).
function Episodes.dizzy(p, c, chance, dt, lines, lineCooldown)
    if Chance.roll(p.rng, Chance.over(chance, Data.PER_MINUTE, dt)) then
        c.data.blurLeft = Chance.between(p.rng, E.BLUR_MINUTES[1], E.BLUR_MINUTES[2])
        p.stats:addF("PANIC", "dizziness", E.DIZZY_PANIC)
        if cooldown(c, "dizzyLine", dt, lineCooldown) then
            Speech.stage(p, Speech.pick(p, lines))
        end
    else
        tick(c, "dizzyLine", dt)
    end
end

-- The blur of a running dizziness episode.
function Episodes.blur(p, c, source, dt)
    if tick(c, "blurLeft", dt) > 0 then
        p.fx:blur(source, E.BLUR)
    end
end

-- Confusion: panic and a line (cooldown in game minutes).
function Episodes.confused(p, c, chance, dt, lines, lineCooldown)
    if Chance.roll(p.rng, Chance.over(chance, Data.PER_MINUTE, dt)) then
        p.stats:addF("PANIC", "confusion", E.CONFUSION_PANIC)
        if cooldown(c, "confusedLine", dt, lineCooldown) then
            Speech.stage(p, Speech.pick(p, lines))
        end
    else
        tick(c, "confusedLine", dt)
    end
end

-- Collapse: a line, a fall and a forced 1-hour sleep (Client/Effects "fall" and "blackout"), then a cooldown.
-- Returns true when the character collapsed.
function Episodes.collapse(p, c, chance, cooldownMinutes, lines)
    if p.facts.asleep or (c.data.collapseCooldown or 0) > 0 then
        return false
    end
    if not Chance.roll(p.rng, chance) then
        return false
    end
    c.data.collapseCooldown = cooldownMinutes
    Speech.stage(p, Speech.pick(p, lines))
    p.stats:floorF("FATIGUE", "collapse", 1)
    p.client("fall", { reason = "collapse" })
    p.client("blackout", { hours = 1 })
    return true
end

-- Counts the collapse cooldown down (only while awake, so the cooldown starts after waking).
function Episodes.collapseCooldown(p, c, dt)
    if not p.facts.asleep then
        tick(c, "collapseCooldown", dt)
    end
end

return Episodes
