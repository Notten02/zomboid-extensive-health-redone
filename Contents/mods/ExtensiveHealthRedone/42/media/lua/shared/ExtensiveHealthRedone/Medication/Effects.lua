-- Timed medication effects a dose starts (v0.9's "general effects": docs/porting/phase5/utility-drugs-and-b42-api.md
-- part A). Each has a start (once, at the dose), an update (every step while it runs) and an end (once, when it runs
-- out: the stimulant crashes). Stat values are fractions of each stat's range.
--
-- State: state.meds.effects[id] = { left = minutes, data = {} }. One of each kind; a medication's "early" rule keeps
-- most of them from being taken twice, and a second hydration or respiratory dose restarts that effect.
--
--   Effects.start(p, defs, spec)      -- spec from a medication's effects list: { id, hours, ... }
--   Effects.update(p, defs, dt)       -- once per step (Medication/System)

local Chance = require "ExtensiveHealthRedone/Core/Chance"
local Tables = require "ExtensiveHealthRedone/Core/Tables"
local SideEffects = require "ExtensiveHealthRedone/Medication/SideEffects"
local Insomnia = require "ExtensiveHealthRedone/Diseases/Mind/Insomnia"

local Effects = {}

-- Last Chance Epinephrine (v0.9 M:1169-1200, M:5389-5488).
Effects.LAST_CHANCE = {
    THRESHOLD = 15,         -- overall health at or below which it is a rescue
    TARGET = 75,            -- rescued health
    DEATH_CHANCE = 0.50,    -- above the threshold
    SPEED = 1.20,           -- movement boost for its hour
    CRASH_FATIGUE = 0.50,
}

local function src(id)
    return "med:" .. id
end

local function stimulantCrash(p, defs, source)
    Insomnia.stimulantCrash(p, defs, source)
end

-- A boost that adds `now` at once and then up to `extra` more at `rate` per hour while it runs (hydration on thirst,
-- downwards; the bronchodilator on endurance, upwards).
local function boostStart(stat, sign)
    return function(p, e, spec)
        e.data.left = spec.extra or 0
        e.data.rate = spec.rate or 0
        if spec.now and spec.now > 0 then
            p.stats:addF(stat, src(e.id), sign * spec.now)
        end
    end
end

local function boostUpdate(stat, sign)
    return function(p, e, dt)
        local step = math.min(e.data.left or 0, (e.data.rate or 0) * dt / 60)
        if step > 0 then
            e.data.left = e.data.left - step
            p.stats:addF(stat, src(e.id), sign * step)
        end
    end
end

-- id -> { start(p, e, spec, defs), update(p, e, dt, defs), finish(p, e, defs) }; all optional.
Effects.DEFS = {
    -- Caffeine pills: fatigue cleared and held at zero for 12 h, sleep blocked (and a sleeping character woken), then
    -- a crash to maximum fatigue with a 2 h crash and an insomnia chance.
    fatigueBlock = {
        update = function(p, e)
            p.stats:ceilingF("FATIGUE", src("caffeine"), 0)
            p.fx:noSleep("caffeine")
            -- Once each time the character is found asleep (vanilla's own sleep paths aren't all blocked).
            local asleep = p.facts.asleep and not p.state.blood.blackout
            if asleep and not e.data.woke then
                p.client("wake", { reason = "caffeine" })
            end
            e.data.woke = asleep or nil
        end,
        finish = function(p, _, defs)
            p.stats:floorF("FATIGUE", src("caffeineCrash"), 1)
            SideEffects.start(p, "caffeine_crash", { force = true })
            stimulantCrash(p, defs, "caffeine_crash")
        end,
    },
    -- Nitric oxide booster: endurance locked at 100% for 3 h (the lock beats disease caps: maintainer, Phase 5),
    -- then 6 h of whole-body muscle pain and an insomnia chance.
    staminaLock = {
        update = function(p)
            p.stats:floorF("ENDURANCE", src("nitricOxide"), 1)
        end,
        finish = function(p, _, defs)
            SideEffects.start(p, "whole_body_muscle_pain", { force = true })
            stimulantCrash(p, defs, "nitric_oxide_crash")
        end,
    },
    -- Combat stimulants: 3 h of no stress, panic or unhappiness, endurance helped up toward 92%, and double attack
    -- speed with the held weapon (no walking boost: maintainer, Phase 5); then a 6 h crash and an insomnia chance.
    combat = {
        update = function(p, _, dt)
            p.stats:ceilingF("STRESS", src("combat"), 0)
            p.stats:ceilingF("PANIC", src("combat"), 0)
            p.stats:ceilingF("UNHAPPINESS", src("combat"), 0)
            p.stats:raiseF("ENDURANCE", src("combat"), 0.92, 0.45 * dt / 60)
            p.fx:attackSpeed(src("combat"), 2)
        end,
        finish = function(p, _, defs)
            SideEffects.start(p, "combat_stimulant_crash", { force = true })
            stimulantCrash(p, defs, "combat_stimulant_crash")
        end,
    },
    -- Last Chance Epinephrine: at 15% health or less it brings health back to at least 75%; above that it is a
    -- 50% gamble with death (survivors pay with maximum sickness, stress and unhappiness and a severe headache).
    -- Either way: full endurance, no fatigue and +20% movement for an hour; then a crash, a headache and thirst.
    lastChance = {
        start = function(p, e)
            local L = Effects.LAST_CHANCE
            local health = p.facts.health or 100
            if health > L.THRESHOLD then
                if Chance.roll(p.rng, L.DEATH_CHANCE) then
                    p.say("UI_EHR_Med_LastChanceFatal")
                    p.body:kill(src("lastChance"), "lastChanceEpinephrine")
                    e.data.dead = true
                    return
                end
                p.stats:floorF("SICKNESS", src("lastChance"), 1)
                p.stats:floorF("STRESS", src("lastChance"), 1)
                p.stats:floorF("UNHAPPINESS", src("lastChance"), 1)
                SideEffects.start(p, "last_chance_severe_headache", { force = true })
            end
            p.body:restoreHealth(src("lastChance"), L.TARGET)
            p.stats:floorF("ENDURANCE", src("lastChance"), 1)
            p.stats:ceilingF("FATIGUE", src("lastChance"), 0)
        end,
        update = function(p)
            p.fx:boost(src("lastChance"), Effects.LAST_CHANCE.SPEED)
        end,
        finish = function(p, e)
            if e.data.dead then
                return
            end
            p.stats:floorF("FATIGUE", src("lastChanceCrash"), Effects.LAST_CHANCE.CRASH_FATIGUE)
            SideEffects.start(p, "last_chance_headache", { force = true })
            SideEffects.start(p, "last_chance_thirst", { force = true })
        end,
    },
    -- Plain epinephrine (W6): no fatigue, full endurance, less pain, an adrenaline rush of panic, and it wakes the
    -- character, from a blackout too. Immediate only.
    epinephrine = {
        start = function(p)
            p.stats:ceilingF("FATIGUE", src("epinephrine"), 0)
            p.stats:floorF("ENDURANCE", src("epinephrine"), 1)
            p.stats:addF("PAIN", src("epinephrine"), -0.5)
            p.stats:addF("PANIC", src("epinephrine"), 0.3)
            if p.facts.asleep or p.state.blood.blackout then
                p.client("wake", { reason = "epinephrine" })
                p.say("UI_EHR_Text_GaspsTheAdrenalineIsKickingIn")
            end
        end,
    },
    -- Thirst down by `now` at once, then by up to `extra` more at `rate` per hour.
    hydration = { start = boostStart("THIRST", -1), update = boostUpdate("THIRST", -1) },
    -- The inhaler: endurance up by `now` at once, then by up to `extra` more at `rate` per hour.
    respiratory = { start = boostStart("ENDURANCE", 1), update = boostUpdate("ENDURANCE", 1) },
    -- Relaxant tea: stress falls toward zero at `rate` (share of the range) per hour.
    stress = {
        start = function(_, e, spec)
            e.data.rate = spec.rate
        end,
        update = function(p, e, dt)
            p.stats:lowerF("STRESS", src("stress"), 0, (e.data.rate or 0) * dt / 60)
        end,
    },
    -- Homemade painkillers, like vanilla's: pain fades to zero over `fadeMinutes`, then no new pain while it runs.
    painkiller = {
        start = function(_, e, spec)
            e.data.fade = spec.fadeMinutes or 30
            e.data.total = e.data.fade
        end,
        update = function(p, e, dt)
            if (e.data.fade or 0) > 0 then
                e.data.fade = e.data.fade - dt
                p.stats:lowerF("PAIN", src("painkiller"), 0, dt / math.max(1, e.data.total))
            else
                p.stats:ceilingF("PAIN", src("painkiller"), 0)
            end
        end,
    },
    -- Warming Pack: warms the body toward 37 deg C while it runs. Body/Temperature reads the running effect; the cold
    -- meter counts it as a heat source (Diseases/Weather/Exposure).
    warming = {},
}

function Effects.active(state, id)
    return state.meds.effects[id] ~= nil
end

-- Starts (or restarts) an effect from a medication's spec.
function Effects.start(p, defs, spec)
    local def = Effects.DEFS[spec.id]
    if not def then
        error("unknown medication effect " .. tostring(spec.id), 2)
    end
    local e = { id = spec.id, left = (spec.hours or 0) * 60, data = {} }
    p.state.meds.effects[spec.id] = e
    if def.start then
        def.start(p, e, spec, defs)
    end
    if e.left <= 0 then
        p.state.meds.effects[spec.id] = nil
    end
    p.dirty("meds")
    return e
end

function Effects.update(p, defs, dt)
    local effects = p.state.meds.effects
    for _, id in ipairs(Tables.sortedKeys(effects)) do
        local e = effects[id]
        local def = Effects.DEFS[id]
        if def and def.update then
            def.update(p, e, dt, defs)
        end
        e.left = e.left - dt
        if e.left <= 0 then
            effects[id] = nil
            p.dirty("meds")
            if def and def.finish then
                def.finish(p, e, defs)
            end
        end
    end
end

return Effects
