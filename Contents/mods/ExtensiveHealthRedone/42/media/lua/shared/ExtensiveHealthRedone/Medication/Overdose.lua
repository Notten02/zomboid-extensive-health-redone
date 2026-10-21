-- Early-dose overdose (v0.9 M:2593-2845; docs/porting/phase5/medication-database.md section 5). A dose of a
-- prescription course drug on the overdose list, taken before its interval, overdoses: the earlier, the worse.
-- Another early dose while an overdose runs makes it worse, and the third early dose inside one overdose kills (kept
-- lethal: maintainer, Phase 5).
--
-- State: state.meds.overdose = { level = 1-3, left = minutes, early = early doses so far } or false.

local Overdose = {}

Overdose.LETHAL_EARLY_DOSES = 3

local SRC = "med:overdose"

-- Level from how early the dose was (share of the interval still to go).
function Overdose.level(earlyShare)
    if earlyShare >= 0.92 then
        return 3
    elseif earlyShare >= 0.75 then
        return 2
    end
    return 1
end

-- Numbers per level (v0.9's formulas).
function Overdose.numbers(level)
    local sickness = math.min(0.60, 0.42 + 0.04 * level)
    return {
        hours = math.min(10, 7 + level),
        sickness = sickness,
        foodSickness = math.min(0.50, sickness),
        endurance = math.max(0.45, 0.57 - 0.04 * level),
        thirstNow = 0.08 + 0.03 * level,
        thirstPerHour = 0.10 + 0.03 * level,
        thirstCeiling = math.min(0.78, 0.64 + 0.04 * level),
        healthCap = math.max(45, 70 - 7 * level),
    }
end

local LINES = {
    [1] = "UI_EHR_Text_ThatDoseWasTooEarlyMyBodyIsReactingBadly",
    [2] = "UI_EHR_Text_ThatDoseWasTooEarlyMyBodyIsReactingBadly",
    [3] = "UI_EHR_Text_ITookThatWayTooSoonIFeelAwful",
}

-- An early dose. earlyShare: (interval - time since the last dose) / interval. Returns the overdose record, or
-- "lethal" when this dose kills.
function Overdose.apply(p, earlyShare)
    local meds = p.state.meds
    local od = meds.overdose
    local level = Overdose.level(earlyShare)
    local early = 1
    if od then
        level = math.min(3, math.max(level, od.level + 1))
        early = od.early + 1
    end
    p.dirty("meds")
    if early >= Overdose.LETHAL_EARLY_DOSES then
        meds.overdose = false
        p.say("UI_EHR_Text_TooManyDosesSomethingIsVeryWrong")
        p.body:kill(SRC, "medicationOverdose")
        return "lethal"
    end
    local n = Overdose.numbers(level)
    local left = n.hours * 60
    if od and od.left > left then
        left = od.left
    end
    meds.overdose = { level = level, left = left, early = early, thirstNow = true }
    p.say(LINES[level])
    return meds.overdose
end

-- Holds the overdose's effects for this step and counts it down.
function Overdose.update(p, dt)
    local od = p.state.meds.overdose
    if not od then
        return
    end
    local n = Overdose.numbers(od.level)
    p.stats:floorF("SICKNESS", SRC, n.sickness)
    p.stats:floorF("FOOD_SICKNESS", SRC, n.foodSickness)
    p.stats:ceilingF("ENDURANCE", SRC, n.endurance)
    local thirst = p.facts.norm and p.facts.norm.THIRST or 0
    local add = od.thirstNow and n.thirstNow or n.thirstPerHour * dt / 60
    od.thirstNow = nil
    add = math.min(add, math.max(0, n.thirstCeiling - thirst))
    if add > 0 then
        p.stats:addF("THIRST", SRC, add)
    end
    local health = p.facts.health or 100
    if health > n.healthCap then
        p.body:damage(SRC, health - n.healthCap, n.healthCap)
    end
    od.left = od.left - dt
    if od.left <= 0 then
        p.state.meds.overdose = false
        p.dirty("meds")
    end
end

return Overdose
