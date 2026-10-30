-- Blood volume: bleeding, regeneration, saline dilution, blood-loss stages, blackouts and death.
-- Numbers in Data/Blood (see its header for the time base). Sandbox options keep the original mod's names and
-- defaults, so existing server configs carry over.
--   * game time throughout; regeneration never "catches up" after a pause
--   * blackouts honour BlackoutCooldownHours and don't stop the death checks; BlackoutEnabled=false doesn't make blood
--     loss harmless
--   * saline only counts the volume it actually added
--   * blood loss brings endurance penalties; the speed penalty is lifted on recovery

local Data = require "ExtensiveHealthRedone/Data/Blood"
local BodyParts = require "ExtensiveHealthRedone/Data/BodyParts"
local Timers = require "ExtensiveHealthRedone/Core/Timers"
local Chance = require "ExtensiveHealthRedone/Core/Chance"
local Speech = require "ExtensiveHealthRedone/Core/Speech"
local Healing = require "ExtensiveHealthRedone/Body/Healing"

local Blood = {}

local N = Data.UPDATES_PER_MINUTE

Blood.HEALTHY, Blood.MILD, Blood.MODERATE, Blood.CRITICAL = 4, 3, 2, 1

local STAGE_LINES = {
    [3] = "UI_EHR_Dialogue_Blood_Stage3",
    [2] = "UI_EHR_Dialogue_Blood_Stage2",
    [1] = "UI_EHR_Dialogue_Blood_Stage1",
}

function Blood.percent(blood)
    return blood.volume / blood.max
end

-- Wound multiplier for one part: the worst wound present, "other" for bleeding without a known wound.
function Blood.woundRate(part)
    for _, kind in ipairs(Data.WOUND_ORDER) do
        if part[kind] then
            return Data.WOUND[kind]
        end
    end
    return Data.WOUND.other
end

-- mL lost per update (Data/Blood) from one part (before BloodLossMultiplier). 0 unless bleeding and unbandaged.
function Blood.partLoss(name, part)
    if not part.bleeding or part.bandaged then
        return 0
    end
    local wound = Blood.woundRate(part)
    local rate = Data.PART[name] or Data.PART_DEFAULT
    local cap = Data.PART_CAP
    if name == "Neck" and wound > Data.WOUND.scratch then
        rate = rate * Data.NECK_BOOST
        cap = cap * Data.NECK_BOOST
    end
    local damage = math.max(0, 100 - (part.health or 100))
    return math.min(cap, damage * wound * rate * Data.LOSS_SCALE)
end

-- mL per game minute from all parts, and whether anything bleeds.
function Blood.lossPerMinute(p)
    local parts = (p.facts and p.facts.parts) or {}
    local total, bleeding = 0, false
    for _, name in ipairs(BodyParts.names) do
        local part = parts[name]
        if part and part.bleeding and not part.bandaged then
            bleeding = true
            total = total + Blood.partLoss(name, part)
        end
    end
    return total * (tonumber(p.sandbox("BloodLossMultiplier", 2.0)) or 2.0) * N, bleeding
end

-- Stage from a share of blood (0-1) and the sandbox thresholds (percent).
function Blood.stageOf(p, share)
    if share >= p.sandbox("BloodThresholdHealthy", 85) / 100 then
        return Blood.HEALTHY
    elseif share >= p.sandbox("BloodThresholdMild", 80) / 100 then
        return Blood.MILD
    elseif share >= p.sandbox("BloodThresholdModerate", 70) / 100 then
        return Blood.MODERATE
    end
    return Blood.CRITICAL
end

-- The share effects are judged by: a beta blocker makes low blood count as SHIFT lower.
function Blood.functionalShare(share, betaBlocker)
    if betaBlocker and share < Data.BETA_BELOW then
        return math.max(0, share - Data.BETA_SHIFT)
    end
    return share
end

-- Changes the volume, clamped to [0, max]. Returns the mL actually added (negative when removed).
function Blood.change(blood, ml)
    local before = blood.volume
    blood.volume = math.max(0, math.min(blood.max, before + ml))
    return blood.volume - before
end

local function bleed(p, b, dt)
    local perMinute, bleeding = Blood.lossPerMinute(p)
    local loss = math.min(b.volume, perMinute * dt)
    if loss > 0 and b.saline > 0 and b.volume > 0 then
        b.saline = math.max(0, b.saline - loss * (b.saline / b.volume))
    end
    b.volume = b.volume - loss
    if bleeding then
        Timers.start(b.timers, "regenDelay", p.sandbox("BloodRegenDelayHours", 2.0) * 60)
    end
    if b.bleeding ~= bleeding then
        b.bleeding = bleeding
        p.dirty("blood")
    end
    return loss
end

local function regenerate(p, b, dt)
    if not p.sandbox("BloodRegenEnabled", true) or b.bleeding or b.volume >= b.max then
        return 0
    end
    if Blood.percent(b) < p.sandbox("BloodRegenMinimumPercent", 30) / 100 then
        return 0
    end
    if Timers.running(b.timers, "regenDelay") then
        return 0
    end
    local bonus = Healing.check(p) and Data.REGEN_BONUS or 1
    local factor = p.mods and p.mods:get("bloodRegen") or 1
    return Blood.change(b, p.sandbox("BloodRegenRatePerHour", 50) / 60 * bonus * factor * dt)

end

local function dilution(p, b, dt)
    if b.saline <= 0 then
        return
    end
    b.saline = math.max(0, b.saline - Data.SALINE_DECAY * N * dt)
    local ratio = b.volume > 0 and b.saline / b.volume or 1
    if ratio >= Data.DILUTION_LETHAL then
        p.stats:raiseF("FATIGUE", "hemodilution", 1, 1)
        p.stats:ceilingF("ENDURANCE", "hemodilution", 0)
        p.body:damage("hemodilution", Data.LETHAL_DAMAGE * N * dt, 0)
        Speech.maybe(p, Speech.pick(p, Data.LETHAL_LINES), Data.LETHAL_LINE_ONE_IN, N, dt)
    elseif ratio >= Data.DILUTION_WARNING then
        p.stats:raiseF("FATIGUE", "hemodilution", Data.WARNING_FATIGUE.target, Data.WARNING_FATIGUE.step * N * dt)
        p.stats:lowerF("ENDURANCE", "hemodilution", Data.WARNING_ENDURANCE.target,
            Data.WARNING_ENDURANCE.step * N * dt)
        Speech.maybe(p, Speech.pick(p, Data.WARNING_LINES), Data.WARNING_LINE_ONE_IN, N, dt)
    end
end

local function blackoutGate(p, beta)
    if beta then
        return true
    end
    local s = (p.facts and p.facts.norm) or {}
    return (s.PANIC or 0) <= Data.BLACKOUT_GATE and (s.STRESS or 0) <= Data.BLACKOUT_GATE
end

-- Waking from a blackout halves fatigue.
local function blackoutWake(p, b, dt)
    if not b.blackout then
        return
    end
    b.blackoutFor = b.blackoutFor + dt
    local asleep = p.facts and p.facts.asleep
    if not asleep and b.blackoutFor > Data.BLACKOUT_GRACE then
        b.blackout = false
        b.blackoutFor = 0
        local fatigue = (p.facts and p.facts.stats and p.facts.stats.FATIGUE) or 0
        p.stats:add("FATIGUE", "blackout", -fatigue / 2)
        Speech.stage(p, "UI_EHR_Dialogue_Blackout_Wake")
        p.dirty("blood")
    end
end

local function critical(p, b, dt, beta)
    -- Death first: a blackout never shields from it.
    local actual = Blood.percent(b)
    if actual <= Data.DEATH_INSTANT then
        Speech.stage(p, "UI_EHR_Dialogue_Blood_Collapse")
        p.body:kill("blood", "exsanguination")
        return
    end
    if actual < Data.DEATH_CHANCE_BELOW and Chance.roll(p.rng, Chance.oneIn(Data.DEATH_ONE_IN, N, dt)) then
        Speech.stage(p, "UI_EHR_Dialogue_Blood_HeartStops")
        p.body:kill("blood", "hypovolemic shock")
        return
    end
    if b.stage ~= Blood.CRITICAL or b.blackout or (p.facts and p.facts.asleep) then
        return
    end
    if not p.sandbox("BlackoutEnabled", true) or Timers.running(b.timers, "blackoutCooldown") then
        Speech.maybe(p, "UI_EHR_Dialogue_Blood_Unconscious", Data.UNCONSCIOUS_ONE_IN, N, dt)
        return
    end
    if blackoutGate(p, beta) and Chance.roll(p.rng, Chance.oneIn(p.sandbox("BlackoutChance", 50), N, dt)) then
        b.blackout = true
        b.blackoutFor = 0
        Timers.start(b.timers, "blackoutCooldown", p.sandbox("BlackoutCooldownHours", 24) * 60)
        p.stats:raiseF("FATIGUE", "blackout", 1, 1)
        Speech.stage(p, "UI_EHR_Dialogue_Blackout_Start")
        p.client("blackout", { hours = Data.BLACKOUT_HOURS })
        p.dirty("blood")
    else
        Speech.maybe(p, "UI_EHR_Dialogue_Blood_Unconscious", Data.UNCONSCIOUS_ONE_IN, N, dt)
    end
end

function Blood.update(p, dt)
    local b = p.state.blood
    Timers.advance(b.timers, dt)
    local before = b.volume
    bleed(p, b, dt)
    regenerate(p, b, dt)
    dilution(p, b, dt)
    local rate = (before - b.volume) / dt
    if math.abs(rate - b.lossRate) > 0.05 or (rate == 0) ~= (b.lossRate == 0) then
        b.lossRate = rate
        p.dirty("blood")
    end
    if math.abs(b.volume - before) > 0 then
        p.dirty("blood")
    end

    local beta = p.treatment:active("betaBlocker")
    local stage = Blood.stageOf(p, Blood.functionalShare(Blood.percent(b), beta))
    if stage ~= b.stage then
        if stage < b.stage then
            Speech.stage(p, STAGE_LINES[stage])
        end
        b.stage = stage
        p.dirty("blood")
    end
    local speed = Data.SPEED[stage] or 1
    if speed < 1 and p.fx then
        p.fx:speed("blood", speed)
    end
    local ceiling = Data.ENDURANCE_CEILING[stage]
    if ceiling then
        p.stats:ceilingF("ENDURANCE", "bloodLoss", ceiling)
    end
    if stage == Blood.MODERATE then
        Speech.maybe(p, "UI_EHR_Dialogue_Blood_Lightheaded", Data.LIGHTHEADED_ONE_IN, N, dt)
    end
    blackoutWake(p, b, dt)
    critical(p, b, dt, beta)
end

Blood.system = { name = "blood", order = 200, update = Blood.update }

return Blood
